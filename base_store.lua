-- base_store.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   STORAGE HELPERS: other computers on the WIRED network that run store.lua
--   keep files for the base (1 MB each = about 8 floppies). The map uses them
--   after the data floppies and before this computer's own disk.
--   A helper answers only the first base computer that talks to it.
--   A file name on a helper looks like "store:<id>/map/o1_2.dat".
--   Every call waits for the answer (rednet), so it is only used where a short
--   wait does not matter: the map worker, start-up, exit and console commands.

STORE = { PROTO = "basestore", helpers = {}, lastFind = -1000, n = 0 }
-- the helpers seen before (store_helpers.dat): at start only those are asked
-- (fast); looking for new ones takes ~2 s and is done by the map worker
local KNOWN_FILE = "store_helpers.dat"
STORE.known = {}
if fs.exists(KNOWN_FILE) then
  local h = fs.open(KNOWN_FILE, "r")
  local t = h and textutils.unserialize(h.readAll() or "")
  if h then h.close() end
  if type(t) == "table" then STORE.known = t end
end
local function saveKnown()
  local h = fs.open(KNOWN_FILE, "w")
  if h then h.write(textutils.serialize(STORE.known)) h.close() end
end

-- rednet on the WIRED modems (the helpers sit on the cable network)
local function openWired()
  local any = false
  for _, name in ipairs(peripheral.getNames()) do
    local okT, isM = pcall(peripheral.hasType, name, "modem")
    if okT and isM then
      local okW, wl = pcall(peripheral.call, name, "isWireless")
      if okW and not wl then
        if not rednet.isOpen(name) then pcall(rednet.open, name) end
        any = true
      end
    end
  end
  return any
end

-- one request to one helper; returns the answer table or nil, error
function STORE.call(id, req, timeout)
  STORE.n = STORE.n + 1
  req.n = os.epoch("utc") * 100 + STORE.n % 100
  local okS = pcall(rednet.send, id, req, STORE.PROTO)
  if not okS then return nil, "could not send" end
  local t0 = os.clock()
  local limit = timeout or 4
  while os.clock() - t0 < limit do
    local from, msg = rednet.receive(STORE.PROTO, limit - (os.clock() - t0))
    if from == id and type(msg) == "table" and msg.re == req.n then
      if msg.ok then return msg end
      return nil, tostring(msg.err or "refused")
    end
  end
  return nil, "no answer"
end

STORE.kicked = STORE.kicked or {}   -- [id] = when the base last turned it on / restarted it
-- helper computers that are OFF (a server crash / restart leaves computers off
-- until someone switches them on): the base turns them on over the cable -
-- they are peripherals there (isOn / turnOn). Only OUR helpers: ones used
-- before (store_helpers.dat) or labelled "Store <id>" (store.lua names itself so).
function STORE.wakeAll()
  local woke = {}
  for _, name in ipairs(peripheral.getNames()) do
    local okT, isC = pcall(peripheral.hasType, name, "computer")
    if okT and isC then
      local okO, on = pcall(peripheral.call, name, "isOn")
      if okO and on == false then
        local okI, id = pcall(peripheral.call, name, "getID")
        local okL, label = pcall(peripheral.call, name, "getLabel")
        local mine = (okI and (STORE.known[id] or STORE.known[tostring(id)]))
                     or (okL and type(label) == "string" and label:match("^Store %d+$"))
        if mine and pcall(peripheral.call, name, "turnOn") then
          woke[#woke + 1] = "#" .. tostring(okI and id or name)
          if okI then STORE.kicked[id] = os.clock() end      -- (just started: not "silent" yet)
        end
      end
    end
  end
  if #woke > 0 then
    if sysLog then sysLog("Storage helper(s) were OFF - turned on: " .. table.concat(woke, ", "), "INFO") end
    if setToast then setToast("Turned on " .. #woke .. " storage helper computer(s) that were off", C.label, 6) end
  end
  return #woke, woke
end

-- helpers that are ON but do not answer (store.lua not running: stopped, or
-- sitting at the prompt): restart them over the cable - startup.lua starts
-- store.lua again. At most once every 10 min per computer.
STORE.kicked = {}
function STORE.kickSilent()
  local kicked = STORE.kicked
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    local okT, isC = pcall(peripheral.hasType, name, "computer")
    if okT and isC then
      local okI, id = pcall(peripheral.call, name, "getID")
      if okI and (STORE.known[id] or STORE.known[tostring(id)]) and not STORE.helpers[id]
         and (not kicked[id] or os.clock() - kicked[id] > 600) then
        local okO, on = pcall(peripheral.call, name, "isOn")
        if okO and on and pcall(peripheral.call, name, "reboot") then
          kicked[id] = os.clock()
          list[#list + 1] = "#" .. id
        end
      end
    end
  end
  if #list > 0 and sysLog then
    sysLog("Storage helper(s) on but not answering - restarted: " .. table.concat(list, ", "), "INFO")
  end
  return #list, list
end

-- find the helpers: { [id] = { id, free, cap, files } }. quick = only the
-- ones seen before (no 2-second lookup)
function STORE.find(quick)
  STORE.lastFind = os.clock()
  if not openWired() then STORE.helpers = {} return STORE.helpers end
  local ids = {}
  if quick then
    for id in pairs(STORE.known) do ids[#ids + 1] = tonumber(id) end
  else
    ids = { rednet.lookup(STORE.PROTO) }
    for id in pairs(STORE.known) do                -- known ones that did not answer the lookup: ask anyway
      local seen = false
      for _, i in ipairs(ids) do if i == tonumber(id) then seen = true end end
      if not seen then ids[#ids + 1] = tonumber(id) end
    end
  end
  local found = {}
  for _, id in ipairs(ids) do
    if type(id) == "number" and id ~= os.getComputerID() then
      local r, err = STORE.call(id, { op = "hello" }, 3)
      if r then
        found[id] = { id = id, free = tonumber(r.free) or 0, cap = tonumber(r.cap) or 0, files = r.files or 0,
                      label = r.label, ver = r.ver }
      elseif err and err:find("belongs", 1, true) then
        found[id] = { id = id, free = 0, cap = 0, refused = err }
      end
    end
  end
  STORE.helpers = found
  local changed = false
  for id, h in pairs(found) do
    if not h.refused and not STORE.known[id] then STORE.known[id] = true changed = true end
  end
  if changed then
    saveKnown()
    local n = 0
    for _ in pairs(found) do n = n + 1 end
    if setToast then setToast("Storage helper(s) found: " .. n .. " - the map uses them when the floppies are full", C.good) end
    if sysLog then sysLog("Storage helpers: " .. n .. " found", "DONE") end
  end
  return found
end

-- ===== updates: a new store.lua next to inventory.lua goes to every helper =====
local function codeHash(str)                     -- the same checksum as store.lua
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end
-- the newest store.lua (read again when it changed): { text, ver } or nil
function STORE.code()
  local path = fs.combine(BASE_DIR or "", "store.lua")
  if not fs.exists(path) then return nil end
  local size = fs.getSize(path)
  if STORE.codeCache and STORE.codeCache.size == size and STORE.codeCache.path == path then return STORE.codeCache end
  local h = fs.open(path, "r")
  local text = h and h.readAll() or ""
  if h then h.close() end
  if not load(text, "store", "t", {}) then return nil end      -- does not compile: never sent
  STORE.codeCache = { text = text, ver = codeHash(text), size = size, path = path }
  return STORE.codeCache
end
-- every helper with an older store.lua gets the new one (it restarts)
function STORE.updateAll()
  local code = STORE.code()
  if not code then return 0 end
  local n = 0
  for id, h in pairs(STORE.helpers) do
    if not h.refused and h.ver and h.ver ~= code.ver then
      local r, err = STORE.call(id, { op = "upd", data = code.text, ver = code.ver }, 10)
      if r then
        n = n + 1
        h.ver = code.ver
        if sysLog then sysLog("Storage helper " .. id .. ": updated store.lua", "DONE") end
      elseif sysLog then
        sysLog("Storage helper " .. id .. ": update failed - " .. tostring(err), "WARNING")
      end
    end
  end
  if n > 0 and setToast then setToast(n .. " storage helper(s) updated (they restart)", C.good) end
  return n
end

-- a helper path?  "store:7/map/o1_2.dat" -> 7, "map/o1_2.dat"
function STORE.parse(path)
  local id, name = tostring(path):match("^store:(%d+)/(.+)$")
  if id then return tonumber(id), name end
end
function STORE.isRemote(path) return STORE.parse(path) ~= nil end

-- write a whole file (the helper writes it through a temp file: never half-written)
function STORE.write(path, text)
  local id, name = STORE.parse(path)
  local r, err = STORE.call(id, { op = "put", name = name, data = text }, 6)
  if r and STORE.helpers[id] then STORE.helpers[id].free = tonumber(r.free) or STORE.helpers[id].free end
  return r ~= nil, err
end
function STORE.read(path)
  local id, name = STORE.parse(path)
  local r = STORE.call(id, { op = "get", names = { name } }, 6)
  return r and r.files and r.files[name]
end
-- several files of one helper in one go (start-up): { [name] = text }
function STORE.readMany(id, names)
  local r = STORE.call(id, { op = "get", names = names }, 15)
  return r and r.files or {}
end
function STORE.delete(path)
  local id, name = STORE.parse(path)
  local r = STORE.call(id, { op = "del", name = name }, 4)
  return r ~= nil
end
-- the files in a folder of a helper: { [name] = size }
function STORE.list(id, dir)
  local r = STORE.call(id, { op = "list", dir = dir }, 6)
  return r and r.files or {}
end
-- all helpers together: free bytes, count
function STORE.space()
  local free, n = 0, 0
  for _, h in pairs(STORE.helpers) do
    if not h.refused then free, n = free + (h.free or 0), n + 1 end
  end
  return free, n
end
