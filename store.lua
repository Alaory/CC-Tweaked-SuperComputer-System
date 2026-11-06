--[[
  STORAGE HELPER for the base computer (CC:Tweaked).

  Put this computer next to the base (same chunk is best - it must stay
  loaded), give it a WIRED modem connected to the base's cable network
  (right-click the modem so it turns on), copy this file onto it and run:

      store

  It installs itself as startup.lua, so it starts by itself from now on.
  It keeps files for the base (the map) on its own disk: 1 MB per computer.

  Safety:
    * it only listens on WIRED modems (nobody can reach it wirelessly)
    * it belongs to the FIRST base computer that talks to it; others are
      refused. To give it to another base:  store reset
    * files are written through a temp file - never half-written
    * it only ever touches its own "store" folder
]]

local PROTO = "basestore"
local ROOT = "store"
local OWNER_FILE = "store_owner.dat"

-- run as "store" (not startup.lua)? install as startup.lua and start that
local me = shell and shell.getRunningProgram() or "startup.lua"
local args = { ... }
if args[1] == "reset" then
  if fs.exists(OWNER_FILE) then fs.delete(OWNER_FILE) end
  print("This helper no longer belongs to any base. The next base that talks to it gets it.")
  return
end
if me ~= "startup.lua" then
  if fs.exists("startup.lua") then
    if fs.exists("startup.old") then fs.delete("startup.old") end
    fs.move("startup.lua", "startup.old")
  end
  fs.copy(me, "startup.lua")
  print("Installed as startup.lua - starts by itself from now on.")
end
if not os.getComputerLabel() then os.setComputerLabel("Store " .. os.getComputerID()) end

-- wired modems only
local opened = 0
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.hasType(name, "modem") and not peripheral.call(name, "isWireless") then
    rednet.open(name)
    opened = opened + 1
  end
end
if opened == 0 then
  printError("No WIRED modem found. Put a wired modem on this computer, connect it to the base's cable")
  printError("network and right-click it (it turns red/on). Then reboot.")
  return
end
rednet.host(PROTO, "store" .. os.getComputerID())

local owner
if fs.exists(OWNER_FILE) then
  local h = fs.open(OWNER_FILE, "r")
  owner = tonumber(h.readAll())
  h.close()
end

-- a safe name inside the store folder ("map/o1_2.dat")
local function safe(name)
  name = tostring(name or "")
  if name == "" or name:find("..", 1, true) or not name:match("^[%w_%-%./]+$") or name:sub(1, 1) == "/" then
    return nil
  end
  return fs.combine(ROOT, name)
end
local function freeSpace()
  local ok, f = pcall(fs.getFreeSpace, "/")
  return ok and f or 0
end
local function capacity()
  local ok, c = pcall(fs.getCapacity, "/")
  return ok and c or nil
end
local function countFiles(dir)
  local n = 0
  if not fs.exists(dir) then return 0 end
  for _, f in ipairs(fs.list(dir)) do
    local p = fs.combine(dir, f)
    if fs.isDir(p) then n = n + countFiles(p) else n = n + 1 end
  end
  return n
end

local stats = { put = 0, get = 0, del = 0 }
local function show()
  term.clear()
  term.setCursorPos(1, 1)
  print("STORAGE HELPER " .. os.getComputerID() .. "  (" .. (os.getComputerLabel() or "") .. ")")
  print("Base: " .. (owner and ("computer " .. owner) or "none yet (waiting for one)"))
  print(string.format("Disk: %d KB free%s", math.floor(freeSpace() / 1024),
        capacity() and (" of " .. math.floor(capacity() / 1024) .. " KB") or ""))
  print("Files kept: " .. countFiles(ROOT))
  print(string.format("Written %d, read %d, deleted %d", stats.put, stats.get, stats.del))
  print("")
  print("Ctrl+T stops it.  'store reset' = give it to another base.")
end
show()

local function answer(id, req, t)
  t.re = req.n
  rednet.send(id, t, PROTO)
end

while true do
  local id, req = rednet.receive(PROTO)
  if type(req) == "table" and req.op then
    if not owner and req.op ~= "hello" then
      owner = id
      local h = fs.open(OWNER_FILE, "w")
      h.write(tostring(id))
      h.close()
    end
    if owner and id ~= owner then
      answer(id, req, { ok = false, err = "this helper belongs to computer " .. owner .. " (store reset to change)" })
    elseif req.op == "hello" then
      answer(id, req, { ok = true, free = freeSpace(), cap = capacity(), files = countFiles(ROOT),
                        label = os.getComputerLabel() })
    elseif req.op == "put" then
      local path = safe(req.name)
      local data = tostring(req.data or "")
      if not path then
        answer(id, req, { ok = false, err = "bad file name" })
      elseif freeSpace() < #data + 4096 then
        answer(id, req, { ok = false, err = "full", free = freeSpace() })
      else
        fs.makeDir(fs.getDir(path))
        local tmp = path .. ".tmp"
        local h = fs.open(tmp, "w")
        local okW = h and pcall(function() h.write(data) h.close() end)
        if okW then
          if fs.exists(path) then fs.delete(path) end
          fs.move(tmp, path)
          stats.put = stats.put + 1
          answer(id, req, { ok = true, free = freeSpace() })
        else
          if h then pcall(h.close) end
          if fs.exists(tmp) then fs.delete(tmp) end
          answer(id, req, { ok = false, err = "could not write", free = freeSpace() })
        end
      end
    elseif req.op == "get" then
      local files, size = {}, 0
      for _, name in ipairs(type(req.names) == "table" and req.names or {}) do
        local path = safe(name)
        if path and fs.exists(path) and not fs.isDir(path) and size < 200000 then
          local h = fs.open(path, "r")
          files[name] = h.readAll()
          h.close()
          size = size + #files[name]
          stats.get = stats.get + 1
        end
      end
      answer(id, req, { ok = true, files = files })
    elseif req.op == "list" then
      local dir = safe(req.dir or "")
      local files = {}
      if dir and fs.exists(dir) and fs.isDir(dir) then
        for _, f in ipairs(fs.list(dir)) do
          local p = fs.combine(dir, f)
          if not fs.isDir(p) and not f:find("%.tmp$") then files[f] = fs.getSize(p) end
        end
      end
      answer(id, req, { ok = true, files = files })
    elseif req.op == "del" then
      local path = safe(req.name)
      if path and fs.exists(path) then fs.delete(path) stats.del = stats.del + 1 end
      answer(id, req, { ok = true, free = freeSpace() })
    else
      answer(id, req, { ok = false, err = "unknown request" })
    end
    show()
  end
end
