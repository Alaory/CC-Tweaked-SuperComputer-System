-- base_turtles.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   Talking to the turtles (node.lua) over a wireless / ender modem, with
--   signed messages. Shared terrain knowledge (walls, dead ends, exit route),
--   sending node.lua updates and keeping the install floppy current, the saved
--   turtle list, rescue / findlost, and splitting surveys between turtles.

-- TURTLES  (remote control over a wireless / ender modem) -----------------
TT = {}

-- small keyed checksum so other players cannot send commands to the turtles
-- (not real cryptography, but enough against casual tampering)
function TT.sign(key, t, n, cmd, args)
  local parts = {}
  for i, v in ipairs(args or {}) do parts[i] = tostring(v) end
  local str = key .. "|" .. tostring(t) .. "|" .. tostring(n) .. "|" .. tostring(cmd or "") ..
              "|" .. table.concat(parts, ",")
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end

-- a wireless or ender modem on a side of this computer
function TT.findModem()
  for _, name in ipairs(peripheral.getNames()) do
    if SIDES[name] then
      local okT, isM = pcall(peripheral.hasType, name, "modem")
      if okT and isM then
        local okW, w = pcall(peripheral.call, name, "isWireless")
        if okW and w then return name end
      end
    end
  end
end

-- a turtle's record (created on first contact)
function TT.get(id)
  local t = state.turtles[id]
  if not t then
    t = { id = id, label = "Turtle " .. id, log = {}, lastN = 0 }
    state.turtles[id] = t
  end
  return t
end

-- add a line to a turtle's log (40 kept)
function TT.log(t, msg)
  table.insert(t.log, 1, { t = textutils.formatTime(os.time(), true), msg = msg })
  while #t.log > 40 do table.remove(t.log) end
end

-- has the turtle reported recently?
function TT.online(t)
  return t.lastSeen ~= nil and (os.clock() - t.lastSeen) < CONFIG.turtles.offlineAfter
end

-- all turtles, sorted by ID
function TT.list()
  local out = {}
  for _, t in pairs(state.turtles) do out[#out + 1] = t end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- a turtle by ID or label
function TT.find(word)
  local n = tonumber(word)
  if n and state.turtles[n] then return state.turtles[n] end
  for _, t in pairs(state.turtles) do
    if t.label:lower() == tostring(word):lower() then return t end
  end
end

-- a message from a turtle (status every few seconds, results of commands)
function TT.receive(id, m)
  if type(m) ~= "table" or type(m.n) ~= "number" or type(m.t) ~= "string" then return end
  if m.sig ~= TT.sign(CONFIG.turtles.key, m.t, m.n) then return end
  local t = TT.get(id)
  if m.n <= (t.lastN or 0) then return end           -- old / replayed message
  t.lastN = m.n
  t.lastSeen = os.clock()
  if type(m.label) == "string" then t.label = m.label end
  t.fuel, t.fuelMax, t.items = m.fuel, m.fuelMax, m.items
  t.pos, t.task, t.home = m.pos, m.task, m.home
  t.stuck, t.trail = m.stuck, m.trail
  t.anchor, t.waiting = m.anchor, m.waiting
  t.rec = m.rec
  -- STOP arrived (it answers) or it is idle anyway
  if t.stopAsk and ((m.t == "result" and m.cmd == "stop") or m.task == "idle") then t.stopAsk = nil end
  local oldVer = t.ver
  if m.ver then t.ver = m.ver end
  t.updReady = m.updReady
  if oldVer and oldVer ~= "?" and m.ver and m.ver ~= oldVer and CODE and m.ver == CODE.ver then
    pcall(TT.updated, t, oldVer)
  end
  if m.gear then t.gear = m.gear end
  t.seenEpoch = os.epoch("utc")
  TT.listDirty = true
  if m.t == "updmiss" and CODE and m.want == CODE.ver and type(m.missing) == "table" then
    -- some pieces of the update did not arrive: send just those again
    for _, k in ipairs(m.missing) do
      local p = CODE.pieces[tonumber(k) or 0]
      if p then TT.send(id, "upd", { CODE.ver, tonumber(k), #CODE.pieces, p }, true) end
    end
    if TT.updating and TT.updating.id == id then TT.updating.t0 = os.clock() end
  elseif m.t == "hello" then
    TT.log(t, "Connected")
  elseif m.t == "scan" then
    local ok = pcall(MAP.addScan, m)
    TT.log(t, ok and ("Scan received at " .. tostring(m.x) .. " " .. tostring(m.z))
                  or "Scan could not be stored")
    -- confirm it: the turtle keeps every scan until the base has stored it
    if ok and m.sid then TT.send(id, "ack", { m.sid }, true) end
  elseif m.t == "rescued" then
    local target = tonumber(m.target) and TT.get(tonumber(m.target)) or nil
    if target and not target.label then target.label = "Turtle " .. target.id end
    local where = type(m.at) == "table" and (" at " .. tostring(m.at.x) .. " " .. tostring(m.at.y) .. " " .. tostring(m.at.z)) or ""
    TT.log(t, (m.ok and "Rescue done: " or "Rescue failed: ") .. tostring(m.msg))
    if target then
      if type(m.at) == "table" and tonumber(m.at.x) then
        target.pos = { x = tonumber(m.at.x), y = tonumber(m.at.y), z = tonumber(m.at.z), f = target.pos and target.pos.f }
      end
      TT.log(target, (m.ok and "Rescued by " or "Rescue by ") .. t.label .. (m.ok and "" or " failed") .. where)
      target.rescuer = nil
      -- supplies delivered: refuel, allow digging with the new pickaxe, come home
      if m.ok and m.mode == "supply" then
        TT.send(target.id, "refuel", {})
        if tostring(m.gave or ""):find("pick", 1, true) then TT.send(target.id, "setting", { "dig", "true" }) end
        TT.send(target.id, "home", {})
      end
    end
    setToast((m.ok and "Rescue done: " or "Rescue failed: ") .. tostring(m.msg), m.ok and C.good or C.warn, 8)
  elseif m.t == "learn" then
    pcall(KNOW.learn, m)
  elseif m.t == "need" then
    -- a turtle starts a trip: send it what is known around there
    local x1, z1 = tonumber(m.x1), tonumber(m.z1)
    local x2, z2 = tonumber(m.x2), tonumber(m.z2)
    if x1 and z1 and x2 and z2 then
      local okA, walls, dead = pcall(KNOW.around, x1, z1, x2, z2)
      if okA then
        TT.send(id, "know", { walls, dead, EXITROUTE and EXITROUTE.route or "none",
                              EXITROUTE and EXITROUTE.t or 0 }, true)
      end
    end
  elseif m.t == "exitroute" and type(m.route) == "string" then
    local n = 0
    for _ in m.route:gmatch(";") do n = n + 1 end
    EXITROUTE = { route = m.route, t = os.epoch("utc"), n = n + 1, by = t.label }
    KNOW.dirty = true
    TT.log(t, "Exit route saved (" .. (n + 1) .. " corners) - shared with all turtles")
  elseif m.t == "result" and m.cmd == "upd" then
    TT.log(t, "Update: " .. tostring(m.msg))
    if not m.ok then
      setToast(t.label .. ": update failed - " .. tostring(m.msg), C.warn)
      if TT.updating and TT.updating.id == id then TT.updating = nil t.updRetry = os.clock() + 120 end
    elseif tostring(m.msg):find("ready", 1, true) then
      setToast(t.label .. " got " .. (CODE and TT.verName(CODE.ver) or "the update") ..
               " - installs when its job is done", C.label)
    end
  elseif m.t == "result" then
    TT.log(t, (m.ok and "Done: " or "Failed: ") .. tostring(m.msg))
    if not m.ok then setToast(t.label .. ": " .. tostring(m.msg), C.warn, 6) end
  end
  if not state.tSel then state.tSel = id end
  os.queueEvent("inv_update")
end

-- queue a signed command for a turtle (sent by the comms worker)
-- the turtle keeping the base computer's chunk loaded (if any), and whether
-- it really sits in the same chunk as the base computer
-- ===== shared knowledge (from all turtles) =====
-- Walls the turtles bumped into and dead ends, each with its time: in
-- Minecraft blocks get placed and dug, so old knowledge fades and is dropped.
-- The same lifetimes as in node.lua (fresh + fade), in ms.
local KNOW_LIFE = { hard = 6 * 3600000 + 600000, short = 32 * 60000, door = 11 * 60000 }
local DEAD_LIFE = 3 * 3600000
KNOW = { walls = {}, dead = {}, n = 0, dirty = false, saved = 0 }
EXITROUTE = nil          -- { route = "x,y,z;...", t = time, n = corners }
-- real time in ms
local function epoch() return os.epoch("utc") end

-- drop knowledge that is too old, and the oldest walls over knowMax
function KNOW.prune()
  local t = epoch()
  for k, w in pairs(KNOW.walls) do
    if t - w.t > (KNOW_LIFE[w.k] or KNOW_LIFE.hard) then KNOW.walls[k] = nil KNOW.n = KNOW.n - 1 end
  end
  for k, d in pairs(KNOW.dead) do
    if t - d.t > DEAD_LIFE then KNOW.dead[k] = nil end
  end
  if KNOW.n > (CONFIG.turtles.knowMax or 20000) then
    local list = {}
    for k, w in pairs(KNOW.walls) do list[#list + 1] = { k = k, t = w.t } end
    table.sort(list, function(a, b) return a.t < b.t end)
    for i = 1, KNOW.n - CONFIG.turtles.knowMax do KNOW.walls[list[i].k] = nil end
    KNOW.n = CONFIG.turtles.knowMax
  end
end

-- save the shared knowledge (shrinks it if the disk is full)
function KNOW.save()
  KNOW.prune()
  local path = dataFile(CONFIG.turtles.knowFile, true)
  local function text()
    local lines = {}
    for k, w in pairs(KNOW.walls) do lines[#lines + 1] = "W " .. k .. "," .. w.k .. "," .. w.t end
    for k, d in pairs(KNOW.dead) do lines[#lines + 1] = "D " .. k .. "," .. d.t end
    return table.concat(lines, "\n") .. "\n"
  end
  local ok = saveFileSafe(path, text())
  local tries = 0
  while not ok and KNOW.n > 200 and tries < 4 do
    -- does not fit: keep only the newest half of the walls (they are relearnt)
    tries = tries + 1
    local was = CONFIG.turtles.knowMax
    CONFIG.turtles.knowMax = math.floor(KNOW.n / 2)
    KNOW.prune()
    CONFIG.turtles.knowMax = was
    ok = saveFileSafe(path, text())
  end
  if ok then dropOldCopy(CONFIG.turtles.knowFile, path, KNOW.n == 0) end
  if EXITROUTE then
    local f = fs.open(CONFIG.turtles.exitFile, "w")
    if f then f.write(textutils.serialize(EXITROUTE)) f.close() end
  elseif fs.exists(CONFIG.turtles.exitFile) then
    fs.delete(CONFIG.turtles.exitFile)
  end
  KNOW.dirty, KNOW.saved = false, os.clock()
end

-- read the saved knowledge, exit route and turtle list
function KNOW.load()
TT.loadList()
  if fs.exists(dataFile(CONFIG.turtles.knowFile)) then
    local h = fs.open(dataFile(CONFIG.turtles.knowFile), "r")
    while h do
      local line = h.readLine()
      if not line then break end
      local x, y, z, k, t = line:match("^W (-?%d+),(-?%d+),(-?%d+),(%a+),(%d+)$")
      if x then
        KNOW.walls[x .. "," .. y .. "," .. z] = { k = k, t = tonumber(t) }
        KNOW.n = KNOW.n + 1
      else
        local dx, dy, dz, dt = line:match("^D (-?%d+),(-?%d+),(-?%d+),(%d+)$")
        if dx then KNOW.dead[dx .. "," .. dy .. "," .. dz] = { t = tonumber(dt) } end
      end
    end
    if h then h.close() end
  end
  if fs.exists(CONFIG.turtles.exitFile) then
    local f = fs.open(CONFIG.turtles.exitFile, "r")
    if f then
      local t = textutils.unserialize(f.readAll() or "")
      f.close()
      if type(t) == "table" and t.route then EXITROUTE = t end
    end
  end
  KNOW.prune()
end

-- a turtle reports what it learnt
function KNOW.learn(m)
  local t = epoch()
  for x, y, z, k in tostring(m.walls or ""):gmatch("(-?%d+),(-?%d+),(-?%d+),(%a+)") do
    local key = x .. "," .. y .. "," .. z
    if not KNOW.walls[key] then KNOW.n = KNOW.n + 1 end
    KNOW.walls[key] = { k = k, t = t }
  end
  for x, y, z in tostring(m.clears or ""):gmatch("(-?%d+),(-?%d+),(-?%d+)") do
    local key = x .. "," .. y .. "," .. z
    if KNOW.walls[key] and KNOW.walls[key].t <= t then KNOW.walls[key] = nil KNOW.n = KNOW.n - 1 end
  end
  for x, y, z in tostring(m.dead or ""):gmatch("(-?%d+),(-?%d+),(-?%d+)") do
    KNOW.dead[x .. "," .. y .. "," .. z] = { t = t }
  end
  KNOW.dirty = true
end

-- what is known around an area (sent to a turtle before its trip)
function KNOW.around(x1, z1, x2, z2)
  local m = 48
  x1, z1, x2, z2 = x1 - m, z1 - m, x2 + m, z2 + m
  local list = {}
  for k, w in pairs(KNOW.walls) do
    local x, z = k:match("^(-?%d+),%-?%d+,(-?%d+)$")
    x, z = tonumber(x), tonumber(z)
    if x and x >= x1 and x <= x2 and z >= z1 and z <= z2 then list[#list + 1] = { k = k, w = w } end
  end
  table.sort(list, function(a, b) return a.w.t > b.w.t end)        -- newest first
  local walls = {}
  for i = 1, math.min(#list, 2500) do walls[i] = list[i].k .. "," .. list[i].w.k .. "," .. list[i].w.t end
  local dead = {}
  for k, d in pairs(KNOW.dead) do
    local x, z = k:match("^(-?%d+),%-?%d+,(-?%d+)$")
    x, z = tonumber(x), tonumber(z)
    if x and x >= x1 and x <= x2 and z >= z1 and z <= z2 then dead[#dead + 1] = k .. "," .. d.t end
  end
  return table.concat(walls, ";"), table.concat(dead, ";")
end

-- ===== turtle program updates =====
-- The base keeps node.lua next to inventory.lua. It fills in its own key,
-- protocol and name (so an update can never lock a turtle out), works out the
-- version (a checksum of the text) and sends it, in signed pieces, to every
-- idle turtle with another version. The turtle checks it and restarts.
CODE = nil               -- { text, ver, mod, pieces = {...} }
local CHUNK = 8000

-- readable version numbers: every new node.lua (new checksum) gets the next
-- number - v1, v2, v3 ... (kept in a small file)
local VER_FILE = "turtle_versions.dat"
TT.versions = { next = 1, byHash = {} }
do
  if fs.exists(VER_FILE) then
    local h = fs.open(VER_FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" and type(t.byHash) == "table" then TT.versions = t end
  end
end
-- "v7" for a checksum (number given when the base first loads that node.lua)
function TT.verName(hash)
  if not hash or hash == "?" then return "?" end
  local n = TT.versions.byHash[hash]
  return n and ("v" .. n) or "old"
end

-- checksum of node.lua (the turtles' version number)
local function codeHash(str)
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end

-- replace the text value of a setting in node.lua (e.g. the key)
local function setStr(code, name, val)
  val = tostring(val):gsub("%%", "%%%%")
  return (code:gsub('(\n%s*' .. name .. '%s*=%s*)"[^"\n]*"', '%1"' .. val .. '"', 1))
end

-- node.lua: in the program folder, or (if it is not there) on a floppy -
-- the install floppy always has a copy
function TT.codePath()
  local name = CONFIG.turtles.codeFile or "node.lua"
  local here = fs.combine(BASE_DIR or "", name)
  if fs.exists(here) then return here end
  for _, d in ipairs(mountedDisks()) do
    local p = fs.combine(d.mount, name)
    if fs.exists(p) then return p end
  end
  return here
end

-- (re)read node.lua if it is new or changed
function TT.codeLoad()
  local path = TT.codePath()
  if not fs.exists(path) then CODE = nil return end
  local mod = fs.attributes and (fs.attributes(path).modified) or fs.getSize(path)
  if CODE and CODE.mod == mod then return end
  local h = fs.open(path, "r")
  local text = h.readAll() or ""
  h.close()
  text = setStr(text, "protocol", CONFIG.turtles.protocol)
  text = setStr(text, "baseName", CONFIG.turtles.hostname)
  text = setStr(text, "key", CONFIG.turtles.key)
  -- the base runs the same Lua as the turtles: if it does not compile here,
  -- it would not compile there either - keep the version the turtles have
  local okC, errC = load(text, "node", "t", {})
  if not okC then
    if not (CODE and CODE.badMod == mod) then
      setPopup("TURTLE PROGRAM", "The new node.lua does not compile - not sent to the turtles: " ..
               tostring(errC), C.bad)
    end
    if CODE then CODE.badMod = mod end
    return
  end
  local pieces = {}
  for i = 1, #text, CHUNK do pieces[#pieces + 1] = text:sub(i, i + CHUNK - 1) end
  CODE = { text = text, ver = codeHash(text), mod = mod, pieces = pieces }
  if not TT.versions.byHash[CODE.ver] then
    TT.versions.byHash[CODE.ver] = TT.versions.next
    TT.versions.next = TT.versions.next + 1
    saveFileSafe(VER_FILE, textutils.serialize(TT.versions))
    if next(state.turtles) then
      setToast("New turtle program " .. TT.verName(CODE.ver) .. " - updating the turtles one by one", C.label)
    end
  end
  for _, t in pairs(state.turtles) do t.updSent, t.updRetry = nil, nil end
  TT.updating = nil
  TT.writeInstallDisk()
end

-- send the program to one turtle
function TT.pushCode(id)
  if not CODE then return false end
  local t = state.turtles[id]
  for i, p in ipairs(CODE.pieces) do
    TT.send(id, "upd", { CODE.ver, i, #CODE.pieces, p }, true)
  end
  if t then
    t.updSent = os.clock()
    TT.log(t, "Sending the turtle program update " .. TT.verName(CODE.ver))
  end
  return true
end

-- updates, ONE turtle at a time (comms worker, every 2 s): send it, wait until
-- it runs the new version or has it ready (busy turtles install it after their
-- job), then the next one. No answer in 45 s: try that one again in 2 minutes.
function TT.updateTick()
  if not CODE or not CONFIG.turtles.autoUpdate then return end
  local u = TT.updating
  if u then
    local t = state.turtles[u.id]
    if not t or t.ver == CODE.ver or t.updReady == CODE.ver then
      TT.updating = nil
    elseif os.clock() - u.t0 > 45 then
      t.updRetry = os.clock() + 120
      TT.log(t, "No answer to the update - trying again later")
      TT.updating = nil
    else
      return
    end
  end
  for _, t in ipairs(TT.list()) do
    if TT.online(t) and TT.outdated(t) and t.updReady ~= CODE.ver
       and (not t.updRetry or os.clock() > t.updRetry) then
      TT.pushCode(t.id)
      TT.updating = { id = t.id, t0 = os.clock() }
      return
    end
  end
end

-- a turtle runs a new version now: tell the owner (and when all are done)
function TT.updated(t, oldVer)
  TT.log(t, "Updated: " .. TT.verName(oldVer) .. " -> " .. TT.verName(t.ver))
  setToast(t.label .. " updated to " .. TT.verName(t.ver), C.good)
  if not CODE then return end
  local n, all = 0, true
  for _, o in pairs(state.turtles) do
    if TT.online(o) then
      n = n + 1
      if o.ver ~= CODE.ver then all = false end
    end
  end
  if all and n > 1 then setToast("All " .. n .. " turtles run " .. TT.verName(CODE.ver), C.good) end
end

-- is this turtle's program older than the base's node.lua?
function TT.outdated(t)
  return CODE ~= nil and t.ver ~= nil and t.ver ~= "?" and t.ver ~= CODE.ver
end

-- the install floppy: a disk in a Disk Drive on this computer gets the
-- installer + the current program. Only empty disks or our own disk are used.
local INSTALLER = [[
-- TURTLE INSTALLER (kept up to date by the base computer).
-- Put a NEW turtle next to the disk drive with this disk and turn it on.
if not turtle then print("This disk installs the turtle program - use it with a turtle.") return end
local here = fs.getDir(shell.getRunningProgram())
local src = fs.combine(here, "node.lua")
if not fs.exists(src) then printError("node.lua is missing on this disk") return end
if not os.getComputerLabel() then os.setComputerLabel("Turtle " .. os.getComputerID()) end
if fs.exists("startup.lua") then
  if fs.exists("startup.old") then fs.delete("startup.old") end
  fs.move("startup.lua", "startup.old")
end
fs.copy(src, "startup.lua")
print("Turtle program installed on " .. os.getComputerLabel() .. ".")
print("Needs: an Ender (or Wireless) Modem and the Chunky upgrade equipped, fuel inside.")
print("Move it away from the drive or take the disk out. Starting now...")
sleep(2)
shell.run("/startup.lua")
]]
-- keep the install floppy up to date with the current node.lua
-- the INSTALL DRIVE: a Disk Drive only for install floppies (CONFIG.turtles.
-- installDrive, default "bottom"). A floppy put in there gets the installer
-- and the current node.lua at once; it is never used for the map.
function TT.installDrive()
  local n = CONFIG.turtles.installDrive or "bottom"
  if peripheral.isPresent(n) and peripheral.getType(n) == "drive" then return n end
end

-- write the installer + node.lua onto a mounted floppy (only what changed)
local function writeInstaller(d)
  local function put(file, text)
    local p = fs.combine(d.mount, file)
    if fs.exists(p) then                        -- unchanged: do not write again
      local h0 = fs.open(p, "r")
      local old = h0 and h0.readAll()
      if h0 then h0.close() end
      if old == text then return true end
    end
    local h = fs.open(p, "w")
    if not h then return false end
    local ok = pcall(h.write, text)
    pcall(h.close)
    return ok
  end
  local ok = put("startup.lua", INSTALLER) and put("node.lua", CODE.text) and put("turtle_installer", CODE.ver)
  pcall(disk.setLabel, d.name, "Turtle installer " .. TT.verName(CODE.ver))
  state.installDisk = d.name
  return ok
end

-- a floppy was put into the install drive: make it an install floppy
-- (empty or already an installer); never touches a data floppy or other files
function TT.prepareInstallFloppy(quiet)
  local drive = TT.installDrive()
  if not drive or not disk or not disk.hasData(drive) then return end
  if not CODE then
    setToast("No node.lua on this computer - cannot make an install floppy", C.warn)
    return
  end
  local d
  for _, m in ipairs(mountedDisks()) do if m.name == drive then d = m end end
  if not d then return end
  if d.data then
    setPopup("INSTALL DRIVE", "That is a data floppy (map) - it is not changed. Put an EMPTY floppy in.", C.warn)
    return
  end
  if not d.empty and not d.installer then
    setPopup("INSTALL DRIVE", "That floppy has other files on it - it is not changed. Put an EMPTY floppy in.", C.warn)
    return
  end
  local fresh = d.installer and fs.exists(fs.combine(d.mount, "turtle_installer"))
  if fresh then
    local h = fs.open(fs.combine(d.mount, "turtle_installer"), "r")
    fresh = h and h.readAll() == CODE.ver
    if h then h.close() end
  end
  if writeInstaller(d) then
    if not (quiet and fresh) then
      setToast("Install floppy ready (" .. TT.verName(CODE.ver) .. ") - take it out of the drive for a rescue turtle",
               C.good)
    end
  else
    setToast("Could not write the install floppy (full?)", C.bad)
  end
end

-- keep install floppies up to date (called when node.lua changes): the install
-- drive's floppy and any other installer floppy. Without an install drive the
-- first empty floppy becomes the installer (as before).
function TT.writeInstallDisk()
  if not CODE or not disk then return end
  local disks, target = mountedDisks(), {}
  local drive = TT.installDrive()
  for _, d in ipairs(disks) do
    if d.installer or (drive and d.name == drive and d.empty) then target[#target + 1] = d end
  end
  if #target == 0 and not drive then
    for _, d in ipairs(disks) do if d.empty and not d.data then target[1] = d break end end
  end
  for _, d in ipairs(target) do writeInstaller(d) end
end

-- ===== the turtle list survives restarts =====
-- Every turtle ever seen, with its last position and when it was last seen,
-- so a turtle that went quiet (e.g. while you were offline) can be found.
TT.listDirty = false
-- save every known turtle (turtles.dat)
function TT.saveList()
  local out = {}
  for id, t in pairs(state.turtles) do
    out[#out + 1] = { id = id, label = t.label, pos = t.pos, home = t.home, seen = t.seenEpoch,
                      task = t.task, ver = t.ver, gear = t.gear, anchor = t.anchor }
  end
  local h = fs.open(CONFIG.turtles.listFile, "w")
  if h then h.write(textutils.serialize(out)) h.close() end
  TT.listDirty = false
end
-- read the saved turtle list
function TT.loadList()
  if not fs.exists(CONFIG.turtles.listFile) then return end
  local h = fs.open(CONFIG.turtles.listFile, "r")
  local list = textutils.unserialize(h.readAll() or "")
  h.close()
  if type(list) ~= "table" then return end
  for _, e in ipairs(list) do
    if type(e) == "table" and tonumber(e.id) then
      local t = TT.get(tonumber(e.id))
      if e.label then t.label = e.label end
      t.pos, t.home, t.seenEpoch, t.task = e.pos, e.home, e.seen, e.task
      t.ver, t.gear, t.anchor = e.ver, e.gear, e.anchor
    end
  end
end
-- "5 min ago", "14 h ago"
function TT.ago(epochMs)
  if not epochMs then return "never" end
  local s = math.floor((os.epoch("utc") - epochMs) / 1000)
  if s < 90 then return s .. " s ago" end
  if s < 5400 then return math.floor(s / 60) .. " min ago" end
  if s < 172800 then return math.floor(s / 3600) .. " h ago" end
  return math.floor(s / 86400) .. " days ago"
end

-- ===== search & rescue =====
local function hasGear(t, what)
  return type(t.gear) == "string" and ("," .. t.gear .. ","):find("," .. what .. ",", 1, true) ~= nil
end
-- what a rescue of this turtle needs: "install" (offline: reinstall it from
-- the install floppy) or "supply" (online but stuck / out of fuel)
function TT.rescueMode(t)
  if TT.online(t) then return "supply" end
  return "install"
end
-- the best turtle to send: online, idle, not the anchor, has the gear; nearest
function TT.pickRescuer(target, mode, x, z)
  local best, bestD
  for id, t in pairs(state.turtles) do
    if id ~= target.id and TT.online(t) and not t.anchor and (t.task == nil or t.task == "idle")
       and t.pos and t.pos.x then
      local ok
      if mode == "install" then ok = hasGear(t, "drive") and hasGear(t, "floppy")
      else ok = hasGear(t, "fuel") or hasGear(t, "pick") end
      if ok then
        local d = math.abs(t.pos.x - x) + math.abs(t.pos.z - z)
        if not bestD or d < bestD then best, bestD = t, d end
      end
    end
  end
  return best
end
-- can this turtle rescue others? ("yes", or what is missing)
function TT.rescueReady(t)
  local miss = {}
  if not hasGear(t, "drive") then miss[#miss + 1] = "a Disk Drive" end
  if not hasGear(t, "floppy") then miss[#miss + 1] = "the install floppy" end
  if not hasGear(t, "scanner") then miss[#miss + 1] = "a Geo Scanner" end
  if #miss == 0 then
    return true, hasGear(t, "pick") and "can rescue lost turtles"
                 or "can rescue (no pickaxe: Disk Drives are left behind)", 0
  end
  return false, "cannot rescue yet - needs " .. table.concat(miss, " + "), #miss
end

-- nobody knows where they are: the best rescuer searches around the base and
-- reinstalls every turtle it finds that is not online
function TT.findLost(radius, cx, cy, cz)
  if not cx then
    local b = state.basePos or CONFIG.drone.home
    if not b then return false, "base position unknown - use: findlost <radius> <x> <y> <z>" end
    cx, cy, cz = b.x, b.y, b.z
  end
  local best, bestD
  local why, whyMiss = "no turtle is online and idle", math.huge
  for id, t in pairs(state.turtles) do
    if TT.online(t) and not t.anchor and (t.task == nil or t.task == "idle") and t.pos and t.pos.x then
      local ok, msg, nmiss = TT.rescueReady(t)
      if ok then
        local d = math.abs(t.pos.x - cx) + math.abs(t.pos.z - cz)
        if not bestD or d < bestD then best, bestD = t, d end
      elseif nmiss < whyMiss then
        why, whyMiss = t.label .. " " .. msg, nmiss            -- the turtle closest to ready
      end
    end
  end
  if not best then return false, why end
  local skip = {}
  for id, t in pairs(state.turtles) do if TT.online(t) then skip[#skip + 1] = id end end
  radius = radius or 96
  TT.send(best.id, "sweep", { cx, cy, cz, radius, table.concat(skip, ",") })
  TT.log(best, "Searching for lost turtles within " .. radius .. " blocks of " .. cx .. " " .. cy .. " " .. cz)
  return true, best.label .. " is searching for lost turtles (" .. radius .. " blocks around the base)"
end

-- send a rescue; x y z = where to look (default: where it was last seen)
function TT.rescue(targetId, x, y, z, radius)
  local target = state.turtles[targetId]
  if not target then
    target = TT.get(targetId)
    target.label = target.label or ("Turtle " .. targetId)
  end
  if not x then
    if not (target.pos and target.pos.x) then return false, "its last position is unknown - give x y z" end
    x, y, z = target.pos.x, target.pos.y, target.pos.z
  end
  local mode = TT.rescueMode(target)
  local r = TT.pickRescuer(target, mode, x, z)
  if not r then
    return false, mode == "install"
      and "no free turtle with a Disk Drive + the install floppy (and a Geo Scanner to search)"
      or "no free turtle with fuel or a spare pickaxe"
  end
  TT.send(r.id, "rescue", { target.id, x, y, z, mode, radius or 24 })
  TT.log(target, "Rescue on its way: " .. r.label .. " (" .. mode .. ")")
  target.rescuer = r.id
  return true, r.label .. " is on its way (" .. (mode == "install" and "reinstall" or "supplies") .. ")"
end

-- the anchor turtle, and whether it is in the base's chunk
function TT.anchorInfo()
  for _, t in pairs(state.turtles) do
    if t.anchor then
      local inChunk
      local b = state.basePos
      if b and t.pos and t.pos.x then
        inChunk = math.floor(t.pos.x / 16) == math.floor(b.x / 16)
              and math.floor(t.pos.z / 16) == math.floor(b.z / 16)
      end
      return t, inChunk
    end
  end
end

-- turtles that can take a job right now: online, position known, idle,
-- and not the anchor
function TT.available()
  local list = {}
  for id, t in pairs(state.turtles) do
    if TT.online(t) and t.pos and t.pos.x and (t.task == nil or t.task == "idle") and not t.anchor then
      list[#list + 1] = id
    end
  end
  table.sort(list)
  return list
end

-- split survey spots between turtles: one strip per turtle (along the longer
-- side of the area), each strip going to the turtle closest to it
function TT.splitSurvey(spots, ids)
  local out = {}
  if #ids == 0 or #spots == 0 then return out end
  local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(spots) do
    minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
    minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
  end
  -- cut the strips along the direction the turtles are spread out in (so each
  -- works on its own side); if they stand close together, along the longer side
  local alongX = (maxX - minX) >= (maxZ - minZ)
  if #ids >= 2 then
    local tminX, tmaxX, tminZ, tmaxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, id in ipairs(ids) do
      local p = state.turtles[id].pos
      tminX, tmaxX = math.min(tminX, p.x), math.max(tmaxX, p.x)
      tminZ, tmaxZ = math.min(tminZ, p.z), math.max(tmaxZ, p.z)
    end
    local sx, sz = tmaxX - tminX, tmaxZ - tminZ
    if math.max(sx, sz) >= 17 then alongX = sx >= sz end
  end
  local sorted = {}
  for i, p in ipairs(spots) do sorted[i] = p end
  table.sort(sorted, function(a, b)
    if alongX then return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end
    return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1])
  end)
  local n = math.min(#ids, #sorted)
  local groups = {}
  for i = 1, n do groups[i] = {} end
  for i, p in ipairs(sorted) do
    local gi = math.floor((i - 1) * n / #sorted) + 1
    groups[gi][#groups[gi] + 1] = p
  end
  -- closest turtle/strip pairs first
  local pairsList = {}
  for _, id in ipairs(ids) do
    local t = state.turtles[id]
    for gi, g in ipairs(groups) do
      local sx, sz = 0, 0
      for _, p in ipairs(g) do sx, sz = sx + p[1], sz + p[2] end
      sx, sz = sx / #g, sz / #g
      pairsList[#pairsList + 1] = { id = id, gi = gi, d = math.abs(t.pos.x - sx) + math.abs(t.pos.z - sz) }
    end
  end
  table.sort(pairsList, function(a, b) return a.d < b.d end)
  local usedT, usedG = {}, {}
  for _, pr in ipairs(pairsList) do
    if not usedT[pr.id] and not usedG[pr.gi] then
      usedT[pr.id], usedG[pr.gi] = true, true
      out[pr.id] = groups[pr.gi]
    end
  end
  return out
end

-- send one turtle its list of spots
function TT.sendSpots(id, spots, r)
  local args = { r }
  for _, p in ipairs(spots) do
    args[#args + 1] = p[1]
    args[#args + 1] = p[2]
  end
  TT.send(id, "surveypts", args)
end

-- queue a signed command for a turtle (sent by the comms worker)
-- STOP must arrive: a surveying turtle takes its modem off for every scan
-- (the Geo Scanner goes in its place) and hears nothing then. So STOP is sent
-- again every 3 s until the turtle answers or is idle (up to a minute), and
-- the turtle gets no more batches from a big survey.
function TT.stopTick()
  for _, t in pairs(state.turtles) do
    local s = t.stopAsk
    if s and os.clock() - s.last >= 3 then
      if s.tries >= 20 then
        t.stopAsk = nil
        TT.log(t, "STOP: no answer for a minute")
        setToast(t.label .. " does not answer STOP (out of range or busy scanning?)", C.warn)
      else
        s.tries, s.last = s.tries + 1, os.clock()
        TT.send(t.id, "stop", {}, true, true)
      end
    end
  end
end

function TT.send(id, cmd, args, quiet, again)
  local n = os.epoch("utc")
  if n <= state.tLastN then n = state.tLastN + 1 end
  state.tLastN = n
  local a = {}
  for i, v in ipairs(args or {}) do a[i] = v end
  state.tOut[#state.tOut + 1] = { id = id, msg = { t = "cmd", n = n, cmd = cmd, args = a,
                                    sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) } }
  local t = state.turtles[id]
  if cmd == "stop" and t and not again then
    t.stopAsk = { tries = 1, last = os.clock() }
    if MAP.queue then
      MAP.queue.excluded = MAP.queue.excluded or {}
      MAP.queue.excluded[id] = true                -- no more big-survey batches for it
    end
  end
  if t and not quiet then
    local shown = {}
    for i, v in ipairs(a) do shown[i] = tostring(v) end
    if cmd == "surveypts" then
      TT.log(t, "> survey: " .. math.floor((#a - 1) / 2) .. " spots")
    else
      TT.log(t, "> " .. cmd .. (#shown > 0 and (" " .. table.concat(shown, " ")) or ""))
    end
  end
  os.queueEvent("turtle_send")
end


KNOW.load()
