--[[
  node.lua - a remote-controlled (chunky) turtle for the base computer

  Setup:
    * Equip: Chunky upgrade + Ender Modem (or Wireless Modem, ~64 blocks)
    * Put fuel in the inventory (coal etc.), press REFUEL on the base screen
    * For the MAP: put a Geo Scanner (the item) in the inventory. For each scan
      the turtle swaps its modem for the scanner, scans, and swaps back.
    * Give it a name:   label set Scout1
    * Save this file as  startup.lua  so it restarts when its chunk reloads
    * protocol, baseName and key below MUST match CONFIG.turtles on the base

  Position: with a GPS setup it finds itself. Otherwise tell it once:
      turtle <id> setpos <x> <y> <z> <north|south|east|west>
  (on the base computer); it then tracks every move itself.
]]

local CONFIG = {
  protocol  = "basectl",
  baseName  = "base",        -- = CONFIG.turtles.hostname on the base
  key       = "change-me",   -- = CONFIG.turtles.key on the base
  heartbeat = 5,             -- seconds between status reports
  climb     = 20,            -- blocks it may climb to get over an obstacle
  sidestep  = 6,             -- sideways tries around an obstacle before giving up
  trailMax  = 4000,          -- remembered path back home (blocks)
  gpsEvery  = 32,            -- while travelling: compare with GPS every N blocks
  pathfind  = 4,             -- when stuck: plan a route (A*), at most N times per trip
  navMargin = 40,            -- route planning looks this far around start and target
  navNodes  = 60000,         -- planning effort limit (cells)
  navReplans = 40,           -- new plans allowed while following one route
  navRescan = 6,             -- re-scan after moving this far (with a Geo Scanner)
  backoff   = { 8, 16, 32 }, -- stuck: go back this many steps along the trail, then try again
  outboxMax = 40,            -- scans kept until the base confirms them (base offline)
  -- long trips use the SKY HIGHWAY: up to skyY, across, down at the target
  skyY      = 150,
  skyMinDist = 48,           -- trips longer than this (blocks, sideways) use it
  exitNear  = 24,            -- this close to the exit route's inside end = "inside the base"
  noProgress = 60,           -- moves without getting closer = going in circles: change strategy
  deadLife  = 3 * 3600000,   -- a remembered dead end is avoided this long (ms)
  deadRadius = 3,            -- ... and the blocks around it
  learnEvery = 10,           -- seconds between sharing what was learnt with the base
  -- End Automata Core (optional): teleport between saved points
  warpAutoMax = 40,          -- automatic points kept (the core holds 64 at most)
  warpGain  = 48,            -- warp first only if that saves at least this many blocks
  resendEvery = 20,          -- seconds between re-sending unconfirmed scans
  settleMax = 10,            -- survey: sink at most this far before a scan (no dropping into caves)
  gpsIdle   = 60,            -- when idle: compare with GPS every N seconds
  -- Dig through NATURAL blocks when stuck. Needs a pickaxe ITEM in the
  -- inventory (it is swapped in for a moment, like the Geo Scanner).
  dig       = false,
  digOk     = { "stone", "dirt", "grass_block", "gravel", "sand", "deepslate", "tuff",
                "andesite", "diorite", "granite", "netherrack", "leaves", "snow", "clay",
                "moss", "mud", "calcite", "basalt", "blackstone", "cobblestone", "podzol" },
  geoItem   = "advancedperipherals:geo_scanner",
  scanRadius = 8,            -- 8 = free scan (17x17x17); the base can ask for another
  minFuel   = 200,           -- a survey stops below this fuel level
  refuelTo  = nil,           -- reusable fuel: fill up to this (nil = the turtle's full tank)
  maxSurveyPoints = 400,
}

-- Per-turtle settings that survive updates, e.g. { dig = true }. Updates from
-- the base replace this program, never node_settings. (key, protocol and
-- baseName always come from the program: the base fills them in.)
local SETTINGS_FILE = "node_settings"
function loadSettings()
  if not fs.exists(SETTINGS_FILE) then return {} end
  local h = fs.open(SETTINGS_FILE, "r")
  local t = textutils.unserialize(h.readAll() or "")
  h.close()
  return type(t) == "table" and t or {}
end
for k, v in pairs(loadSettings()) do
  if k ~= "key" and k ~= "protocol" and k ~= "baseName" then CONFIG[k] = v end
end

-- version of this program = a checksum of its text (the base compares it)
function codeHash(str)
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end
local MYPATH = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "startup.lua"
local MYVER = "?"
if fs.exists(MYPATH) then
  local h = fs.open(MYPATH, "r")
  MYVER = codeHash(h.readAll() or "")
  h.close()
end
local UPD, rebootSoon = nil, false
local UPD_READY = nil      -- { ver, code }: a complete update, installed when the current job is done
-- started by hand (e.g. "node")? Then also make it the startup program, so it
-- starts by itself after every restart and never gets "lost" again
if MYPATH ~= "startup.lua" and MYPATH ~= "/startup.lua" and fs.exists(MYPATH)
   and not fs.exists("startup.lua") then
  fs.copy(MYPATH, "startup.lua")
  print("Installed myself as startup.lua - I start by myself from now on.")
end

---------------------------------------------------------------------
-- modem
---------------------------------------------------------------------
function findModemSide()
  for _, s in ipairs(rs.getSides()) do
    if peripheral.getType(s) == "modem" and peripheral.call(s, "isWireless") then return s end
  end
end

-- slot holding an item whose name contains `part` (e.g. "modem")
function findItemLike(part)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name:find(part, 1, true) then return i end
  end
end

---------------------------------------------------------------------
-- the Chunky upgrade is NEVER taken off (it keeps the turtle loaded)
---------------------------------------------------------------------
function isChunkyItem(name) return tostring(name or ""):lower():find("chunk", 1, true) ~= nil end

-- the item equipped on a side (nil = empty or this version cannot tell)
function equippedName(side)
  local f = (side == "left") and turtle.getEquippedLeft or turtle.getEquippedRight
  if not f then return nil end
  local ok, d = pcall(f)
  return ok and type(d) == "table" and d.name or nil
end

function isChunkySide(side)
  if isChunkyItem(equippedName(side)) then return true end
  local ty = peripheral.getType(side)
  return ty ~= nil and isChunkyItem(ty)
end

-- equip the selected slot on `side`. Refuses the Chunky side; and if the item
-- that came off turns out to be the Chunky upgrade anyway, it goes straight
-- back on (checked on the item itself, works on every version).
function equipOn(side)
  if isChunkySide(side) then return false end
  local was = STEPPING
  STEPPING = true
  local ok
  if side == "left" then ok = turtle.equipLeft() else ok = turtle.equipRight() end
  if ok then
    local d = turtle.getItemDetail(turtle.getSelectedSlot())
    if d and isChunkyItem(d.name) then
      if side == "left" then turtle.equipLeft() else turtle.equipRight() end   -- Chunky back on
      ok = false
    end
  end
  STEPPING = was
  return ok
end

-- no Chunky upgrade on either side but one in the inventory (it came off
-- somehow): put it back on the side without the modem. Only on versions that
-- can read the equipped items (otherwise it could be a spare one).
function chunkyFix(modemSide)
  if not (turtle.getEquippedLeft and turtle.getEquippedRight) then return nil end
  if isChunkySide("left") or isChunkySide("right") then return nil end
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isChunkyItem(d.name) then
      local side = (modemSide == "left") and "right" or "left"
      local sel = turtle.getSelectedSlot()
      turtle.select(i)
      local ok
      if side == "left" then ok = turtle.equipLeft() else ok = turtle.equipRight() end
      turtle.select(sel)
      return ok and ("Chunky upgrade was in the inventory - equipped it again (" .. side .. ")") or nil
    end
  end
end

local modem = findModemSide()
if not modem then
  -- recovery: the modem is in the inventory (e.g. after a failed scan swap).
  -- Put it back where the Geo Scanner / core is, else on a free side -
  -- never on the side with the Chunky upgrade (equipOn refuses that).
  local slot = findItemLike("modem")
  if slot then
    local sides = {}
    for _, side in ipairs({ "left", "right" }) do
      local ty = tostring(peripheral.getType(side) or ""):lower()
      if ty:find("geo", 1, true) or ty:find("automata", 1, true) then table.insert(sides, 1, side)
      elseif peripheral.getType(side) == nil then sides[#sides + 1] = side end
    end
    for _, side in ipairs(sides) do
      turtle.select(findItemLike("modem") or slot)
      if equipOn(side) then break end
    end
    turtle.select(1)
    sleep(0.3)
    modem = findModemSide()
    if modem then print("Modem was in the inventory - equipped it again.") end
  end
end
do
  local fixed = chunkyFix(modem)
  if fixed then print(fixed) end
end
if not modem then error("Equip a Wireless or Ender Modem first.", 0) end
rednet.open(modem)

---------------------------------------------------------------------
-- saved state: position, facing, home, last command number
---------------------------------------------------------------------
local STATE_FILE = "node_state"
local S = { pos = nil, home = nil, lastN = 0 }
local outboxAck, outboxResend, outboxCount   -- scan outbox (defined further down)
local moveCount = 0            -- every real move (for the progress watchdog)
local recAdd                   -- route recording (defined further down)
local gearString               -- rescue gear carried (defined further down)
local learnBlocked             -- remember a block we could not pass (further down)
if fs.exists(STATE_FILE) then
  local h = fs.open(STATE_FILE, "r")
  local t = textutils.unserialize(h.readAll() or "")
  h.close()
  if type(t) == "table" then S = t end
end
-- save a table to a file; a failure is reported, never stops the program
local writeErr = nil
function writeFile(path, value)
  local ok, text = pcall(textutils.serialize, value)
  if not ok then
    writeErr = "cannot save " .. path .. ": " .. tostring(text)
    printError(writeErr)
    return false
  end
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(text)
  h.close()
  return true
end

function save()
  writeFile(STATE_FILE, S)
end
S.recording = nil  -- a recording does not survive a restart

-- facing: 0 south (+z), 1 west (-x), 2 north (-z), 3 east (+x)
local FACE = { south = 0, west = 1, north = 2, east = 3 }
local FNAME = { [0] = "south", "west", "north", "east" }
local DX = { [0] = 0, -1, 0, 1 }
local DZ = { [0] = 1, 0, -1, 0 }

function fmt()
  if not (S.pos and S.pos.x) then return "?" end
  return S.pos.x .. " " .. S.pos.y .. " " .. S.pos.z
end
function known() return S.pos ~= nil and S.pos.x ~= nil and S.pos.f ~= nil end

-- Breadcrumbs: every block the turtle moved through (loops cut out), in the
-- turtle's OWN frame: (0,0,0) is where the trail started (home), and every
-- forward/back/up/down/turn is counted there. That frame never depends on GPS,
-- so retracing is always physically right - even if the world coordinates
-- were wrong on the way out. GO HOME retraces this first.
local TRAIL_FILE = "node_trail"
local trail, trailIdx, trailDirty = {}, {}, 0
local T = { x = 0, y = 0, z = 0, f = 0 }          -- position/facing in the trail frame
function trailRebuild()
  trailIdx = {}
  for i, k in ipairs(trail) do trailIdx[k] = i end
end
if fs.exists(TRAIL_FILE) then
  local h = fs.open(TRAIL_FILE, "r")
  local t = textutils.unserialize(h.readAll() or "")
  h.close()
  if type(t) == "table" and t.v == 2 and type(t.trail) == "table" and type(t.T) == "table" then
    trail, T = t.trail, t.T
  end
  trailRebuild()
end
function trailSave()
  writeFile(TRAIL_FILE, { v = 2, T = T, trail = trail })
  trailDirty = 0
end
function frameKey() return T.x .. "," .. T.y .. "," .. T.z end
function trailReset()
  T = { x = 0, y = 0, z = 0, f = 0 }
  trail = { frameKey() }
  trailRebuild()
  trailSave()
end
if #trail == 0 then trailReset() end
function trailAdd()
  local k = frameKey()
  local i = trailIdx[k]
  if i then
    -- been here before on this trip: cut the loop out
    for j = #trail, i + 1, -1 do trailIdx[trail[j]] = nil; trail[j] = nil end
  else
    trail[#trail + 1] = k
    trailIdx[k] = #trail
    if #trail > CONFIG.trailMax + 200 then
      for _ = 1, 200 do table.remove(trail, 1) end
      trailRebuild()
    end
  end
  trailDirty = trailDirty + 1
  if trailDirty >= 25 then trailSave() end
end
-- the turtle really moved: "f" forward, "b" back, "u" up, "d" down
-- (dir = which frame direction "forward" was, default the current one)
function frameMove(kind, dir)
  moveCount = moveCount + 1
  local f = dir or T.f
  if kind == "u" then T.y = T.y + 1
  elseif kind == "d" then T.y = T.y - 1
  elseif kind == "f" then T.x, T.z = T.x + DX[f], T.z + DZ[f]
  else T.x, T.z = T.x - DX[f], T.z - DZ[f] end
  trailAdd()
end

---------------------------------------------------------------------
-- messages (same checksum as the base)
---------------------------------------------------------------------
function sign(key, t, n, cmd, args)
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

local baseId, task, job, stopFlag = nil, "idle", nil, false
local lastSent = 0

function itemCount()
  local n = 0
  for i = 1, 16 do n = n + turtle.getItemCount(i) end
  return n
end

local modemAttached = true
local pendingInfo = nil        -- extra lines to report once the modem is back

function send(t, extra)
  if not modemAttached then return end
  if not baseId then
    local ok, id = pcall(rednet.lookup, CONFIG.protocol, CONFIG.baseName)
    baseId = ok and id or nil
  end
  if not baseId then return end
  local n = os.epoch("utc")
  if n <= lastSent then n = lastSent + 1 end
  lastSent = n
  -- a fresh table: the caller's table (e.g. a scan kept in the outbox) must
  -- never get fields added - shared tables in it cannot be saved any more
  local m = {}
  for k, v in pairs(extra or {}) do m[k] = v end
  m.t, m.n = t, n
  m.sig = sign(CONFIG.key, t, n)
  m.label = os.getComputerLabel() or ("Turtle " .. os.getComputerID())
  local fuel = turtle.getFuelLevel()
  m.fuel = fuel
  m.fuelMax = (fuel ~= "unlimited") and turtle.getFuelLimit() or nil
  m.items = itemCount()
  m.task = task
  if S.pos and S.pos.x then
    m.pos = { x = S.pos.x, y = S.pos.y, z = S.pos.z, f = S.pos.f and FNAME[S.pos.f] or nil }
  end
  m.home = S.home and { x = S.home.x, y = S.home.y, z = S.home.z } or nil
  m.stuck = S.stuck
  m.trail = #trail
  m.anchor = S.anchor
  m.ver = MYVER
  m.updReady = UPD_READY and UPD_READY.ver or nil
  m.gear = S.gear
  m.rec = S.recording and (S.recCount or 1) or nil
  m.waiting = outboxCount and outboxCount() or 0
  pcall(rednet.send, baseId, m, CONFIG.protocol)
end

function reply(cmd, ok, msg)
  send("result", { cmd = cmd, ok = ok, msg = msg })
  if pendingInfo then
    for i, l in ipairs(pendingInfo) do
      send("result", { cmd = cmd, ok = false, msg = "scanner functions " .. i .. "/" .. #pendingInfo .. ": " .. l })
    end
    pendingInfo = nil
  end
end

---------------------------------------------------------------------
-- movement (keeps track of position and facing)
---------------------------------------------------------------------
local memFree     -- defined further down (terrain memory)
function moved(dx, dy, dz)
  if S.pos and S.pos.x then
    S.pos.x, S.pos.y, S.pos.z = S.pos.x + dx, S.pos.y + dy, S.pos.z + dz
    save()
    if memFree then memFree(S.pos.x, S.pos.y, S.pos.z) end
    if recAdd then recAdd() end
  end
end

-- A move failed. A BLOCK is remembered (with its kind and time). If there is
-- no block, something that moves is in the way (mob, player, other turtle):
-- wait a little and try again - and never remember it as a wall.
function blockedOrWait(move, detect, dir)
  if detect() then
    if learnBlocked then learnBlocked(dir) end
    return false
  end
  for _ = 1, 4 do
    sleep(0.5)
    if move() then return true end
    if detect() then
      if learnBlocked then learnBlocked(dir) end
      return false
    end
  end
  return false
end

-- before every move: nearly empty? Top up from reusable fuel; really empty and
-- none of that? Burn real fuel items (coal, charcoal, lava, blaze rods) - never
-- anything else. Checking costs no game tick.
function ensureFuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" or f >= 20 then return end
  if S.reuse and next(S.reuse) then
    topUp(math.min(refuelTarget(), f + 2000), true)
    if turtle.getFuelLevel() >= 20 then return end
  end
  local sel = turtle.getSelectedSlot()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isFuel(d.name) then
      turtle.select(i)
      while turtle.getFuelLevel() < 500 and turtle.refuel(1) do end
      if turtle.getFuelLevel() >= 500 then break end
    end
  end
  turtle.select(sel)
end

-- STEPPING = a move/turn/equip is under way: a forced STOP waits for it to
-- finish, so the saved position and the equipment always stay right
STEPPING = false
-- FORCE_STOP = a STOP was not obeyed within 2 s: no new move or turn starts
FORCE_STOP = false
function forceCheck()
  if FORCE_STOP then error("stopped (forced) at " .. fmt(), 0) end
end

function fwd()
  forceCheck()
  STEPPING = true
  ensureFuel()
  local ok = turtle.forward() or blockedOrWait(turtle.forward, turtle.detect, "forward")
  if ok then
    if S.pos and S.pos.f then moved(DX[S.pos.f], 0, DZ[S.pos.f]) end
    frameMove("f")
  end
  STEPPING = false
  return ok
end
function bck()
  forceCheck()
  STEPPING = true
  ensureFuel()
  local ok = turtle.back()
  if ok then
    if S.pos and S.pos.f then moved(-DX[S.pos.f], 0, -DZ[S.pos.f]) end
    frameMove("b")
  end
  STEPPING = false
  return ok
end
function up()
  forceCheck()
  STEPPING = true
  ensureFuel()
  local ok = turtle.up() or blockedOrWait(turtle.up, turtle.detectUp, "up")
  if ok then
    moved(0, 1, 0)
    frameMove("u")
  end
  STEPPING = false
  return ok
end
function down()
  forceCheck()
  STEPPING = true
  ensureFuel()
  local ok = turtle.down() or blockedOrWait(turtle.down, turtle.detectDown, "down")
  if ok then
    moved(0, -1, 0)
    frameMove("d")
  end
  STEPPING = false
  return ok
end
function right()
  forceCheck()
  STEPPING = true
  turtle.turnRight()
  if S.pos and S.pos.f then S.pos.f = (S.pos.f + 1) % 4 save() end
  T.f = (T.f + 1) % 4
  STEPPING = false
end
function left()
  forceCheck()
  STEPPING = true
  turtle.turnLeft()
  if S.pos and S.pos.f then S.pos.f = (S.pos.f + 3) % 4 save() end
  T.f = (T.f + 3) % 4
  STEPPING = false
end
-- turn to a direction of the trail frame
function faceFrame(tf)
  while T.f ~= tf do
    if (T.f + 1) % 4 == tf then right() else left() end
  end
end
function face(f)
  while S.pos.f ~= f do
    if (S.pos.f + 1) % 4 == f then right() else left() end
  end
end

local tryDig     -- defined further down (needs the equip helpers)
local gpsCheck   -- defined further down (GPS helpers)
local findWay    -- defined further down (scan + plan a way around)

-- forward; if something is in the way: dig it (only if allowed and natural),
-- otherwise climb over it
function stepForward()
  if fwd() then return true end
  if tryDig("forward") and fwd() then return true end
  -- with a Geo Scanner a route is planned after a short climb (cheaper than
  -- climbing up to CONFIG.climb blindly and coming down again)
  local maxClimb = CONFIG.climb
  if findItem(CONFIG.geoItem) then maxClimb = math.min(6, CONFIG.climb) end
  for _ = 1, maxClimb do
    if stopFlag then return false end
    if not up() then
      if not (tryDig("up") and up()) then return false end
    end
    if fwd() then return true end
    if tryDig("forward") and fwd() then return true end
  end
  return false
end

-- blocked straight ahead: step one block to the right or the left
function sidestep(f)
  for _, d in ipairs({ 1, 3 }) do
    face((f + d) % 4)
    if fwd() or (tryDig("forward") and fwd()) then
      face(f)
      return true
    end
  end
  face(f)
  return false
end

function noFuel()
  ensureFuel()
  local f = turtle.getFuelLevel()
  return f ~= "unlimited" and f < 1
end

-- REUSABLE fuel: an item that is still there after turtle.refuel (e.g. one
-- that gives 10 fuel per use and can be used again). topUp refuels from it
-- again and again until the fuel level reaches `target`.
--   onlyReusable = true: only items already known to be reusable (S.reuse) -
--     used when the turtle tops itself up, so it never burns anything else
--   budget = at most this many refuel calls (one game tick each); nil = no limit
-- Normal fuel (coal ...) is burnt one item at a time, only as far as needed.
-- Returns the fuel gained and whether it stopped because of the budget.
local TOPUP = {}       -- the last top-up: gained, uses, refused, seconds (for the REFUEL answer)
-- equipping (core swap) and refuelling both select slots: they take turns.
-- SLOT_LOCK = someone is equipping; TOPUP_RUNNING = a top-up is selecting slots
SLOT_LOCK, TOPUP_RUNNING = false, false
local REUSE_SLOTS      -- the slots holding reusable fuel last time (saves looking at all 16)
function topUp(target, onlyReusable, budget)
  local f0 = turtle.getFuelLevel()
  if f0 == "unlimited" or SLOT_LOCK then return 0, false end
  TOPUP_RUNNING = true
  local limit = turtle.getFuelLimit()
  target = math.min(target or limit, limit)
  S.reuse = S.reuse or {}
  local t0, calls, refused, sel, learnt = os.clock(), 0, 0, turtle.getSelectedSlot(), false
  -- the slots to use: the remembered reusable ones, else all 16 looked at once
  -- (known reusable ones first: saves coal)
  local slots = {}
  if onlyReusable and REUSE_SLOTS then
    for _, sl in ipairs(REUSE_SLOTS) do slots[#slots + 1] = { i = sl.i, name = sl.name, count = sl.count } end
  else
    for i = 1, 16 do
      local d = turtle.getItemDetail(i)
      if d and (not onlyReusable or S.reuse[d.name]) then
        slots[#slots + 1] = { i = i, name = d.name, count = d.count }
      end
    end
    table.sort(slots, function(a, b)
      local ra, rb = S.reuse[a.name] and 1 or 0, S.reuse[b.name] and 1 or 0
      if ra ~= rb then return ra > rb end
      return a.i < b.i
    end)
  end
  local stop = false
  while #slots > 0 and turtle.getFuelLevel() < target and not stop do
    local keep, any, cooling = {}, false, false
    for _, sl in ipairs(slots) do
      turtle.select(sl.i)
      local dead = false
      while turtle.getFuelLevel() < target do
        if (budget and calls >= budget) or (job and stopFlag) or SLOT_LOCK then stop = true break end
        local before = turtle.getFuelLevel()
        local ok = turtle.refuel(1)
        calls = calls + 1
        if not ok or turtle.getFuelLevel() <= before then
          -- refused: a reusable item still in its slot is only cooling down
          local d = S.reuse[sl.name] and turtle.getItemDetail(sl.i)
          if d and d.name == sl.name then
            cooling, refused = true, refused + 1
          else
            dead = true
          end
          break
        end
        any = true
        if not S.reuse[sl.name] then
          -- still there after use? then it is reusable (checked until known)
          local c = turtle.getItemCount(sl.i)
          if c >= sl.count then S.reuse[sl.name], learnt = true, true
          else
            sl.count = c
            if c == 0 then dead = true break end            -- normal fuel used up
          end
        end
      end
      if not dead then keep[#keep + 1] = sl end
      if stop then break end
    end
    slots = keep
    if not any then
      if not cooling or stop then break end
      sleep(0.05)                                           -- all cooling down: one tick
      calls = calls + 1
    end
  end
  turtle.select(sel)
  -- remember where the reusable fuel is (nil = look at all slots next time)
  local rs = {}
  for _, sl in ipairs(slots) do if S.reuse[sl.name] then rs[#rs + 1] = sl end end
  REUSE_SLOTS = (#rs > 0) and rs or nil
  if learnt then save() end
  TOPUP_RUNNING = false
  local gained = turtle.getFuelLevel() - f0
  TOPUP = { gained = gained, uses = calls - refused, refused = refused, secs = os.clock() - t0 }
  return gained, stop and budget ~= nil and calls >= budget
end

-- the fuel level the turtle fills itself up to with reusable fuel
function refuelTarget()
  local limit = turtle.getFuelLimit()
  return math.min(limit, tonumber(CONFIG.refuelTo) or limit)
end

-- one block to an ADJACENT position (used to retrace the trail)
function stepTo(x, y, z)
  local dx, dy, dz = x - S.pos.x, y - S.pos.y, z - S.pos.z
  if math.abs(dx) + math.abs(dy) + math.abs(dz) ~= 1 then return false end
  if dy == 1 then return up() or (tryDig("up") and up()) end
  if dy == -1 then return down() or (tryDig("down") and down()) end
  if dx == 1 then face(3) elseif dx == -1 then face(1) elseif dz == 1 then face(0) else face(2) end
  return fwd() or (tryDig("forward") and fwd())
end

-- one block to an adjacent position of the TRAIL FRAME
function stepToFrame(x, y, z)
  local dx, dy, dz = x - T.x, y - T.y, z - T.z
  if math.abs(dx) + math.abs(dy) + math.abs(dz) ~= 1 then return false end
  if dy == 1 then return up() or (tryDig("up") and up()) end
  if dy == -1 then return down() or (tryDig("down") and down()) end
  if dx == 1 then faceFrame(3) elseif dx == -1 then faceFrame(1)
  elseif dz == 1 then faceFrame(0) else faceFrame(2) end
  return fwd() or (tryDig("forward") and fwd())
end

-- walk the remembered path backwards to where it started (home)
function backtrack()
  local total = #trail
  while #trail > 1 do
    if stopFlag then return false, "stopped while retracing at " .. fmt() end
    if noFuel() then return false, "out of fuel at " .. fmt() end
    if trail[#trail] ~= frameKey() then return false, "path record does not match my moves" end
    task = "retracing path " .. (total - #trail + 1) .. "/" .. (total - 1)
    local x, y, z = trail[#trail - 1]:match("^(-?%d+),(-?%d+),(-?%d+)$")
    if not stepToFrame(tonumber(x), tonumber(y), tonumber(z)) then
      return false, "retracing blocked at " .. fmt()
    end
  end
  return true
end

-- go back up to n steps along the trail (the way it came)
function backtrackSteps(n)
  local done = 0
  while done < n and #trail > 1 do
    if stopFlag then return false end
    if trail[#trail] ~= frameKey() then return false end
    local x, y, z = trail[#trail - 1]:match("^(-?%d+),(-?%d+),(-?%d+)$")
    if not stepToFrame(tonumber(x), tonumber(y), tonumber(z)) then return false end
    done = done + 1
  end
  return done > 0
end

function round(v) return math.floor(v + 0.5) end
local gpsWarned = false

-- raw GPS position; warns once if the numbers are not whole (a GPS host has
-- wrong coordinates in its "gps host x y z" line)
function gpsRaw(timeout)
  local ok, x, y, z = pcall(gps.locate, timeout or 1)
  if not ok or not x then return nil end
  if not gpsWarned and (math.abs(x - round(x)) > 0.15 or math.abs(y - round(y)) > 0.15
                        or math.abs(z - round(z)) > 0.15) then
    gpsWarned = true
    send("result", { cmd = "gps", ok = false, msg = string.format(
      "GPS gives uneven numbers (%.2f %.2f %.2f) - check the coordinates in the gps host computers' startup", x, y, z) })
  end
  return round(x), round(y), round(z)
end

-- which way am I facing? Try a test move forward; if blocked, try the other
-- directions (turning back afterwards). Returns facing or nil, plus the real
-- position (in case the turtle could not move back).
function detectFacing(x, y, z)
  for turns = 0, 3 do
    if turtle.forward() then
      local x2, _, z2 = gpsRaw(2)
      local backOk = turtle.back()
      local f
      if x2 then
        if x2 > x then f = 3 elseif x2 < x then f = 1 elseif z2 > z then f = 0 elseif z2 < z then f = 2 end
      end
      if not backOk then
        if x2 then x, z = x2, z2 end                -- stuck one block further
        frameMove("f", (T.f + turns) % 4)
      end
      for _ = 1, turns do
        turtle.turnLeft()
        if f then f = (f + 3) % 4 end
      end
      return f, x, y, z
    end
    turtle.turnRight()
  end
  -- 4 right turns: back to where it started; no free side to test
  return nil, x, y, z
end

-- full fix: position AND facing from GPS
function gpsFix()
  local x, y, z = gpsRaw(2)
  if not x then return false, "no GPS signal - use setpos instead" end
  STEPPING = true                              -- test moves: never cut by a STOP
  local okF, f, rx, ry, rz = pcall(detectFacing, x, y, z)
  STEPPING = false
  if not okF then error(f, 0) end
  local oldF = S.pos and S.pos.f or nil
  local changed = not (S.pos and S.pos.x == rx and S.pos.y == ry and S.pos.z == rz and (f == nil or f == oldF))
  S.pos = { x = rx, y = ry, z = rz, f = f or oldF }
  save()
  local note = ""
  if f == nil then note = " (facing NOT checked: blocked on all sides)"
  elseif oldF ~= nil and oldF ~= f then note = " (facing was wrong: " .. FNAME[oldF] .. ")" end
  return true, "GPS: " .. fmt() .. (S.pos.f and (" facing " .. FNAME[S.pos.f]) or "") .. note
end

-- quick check (no test move): correct the position if GPS disagrees.
-- Returns a message when something was corrected.
gpsCheck = function()
  if not (S.pos and S.pos.x) then return nil end
  local x, y, z = gpsRaw(1)
  if not x then return nil end
  if x ~= S.pos.x or y ~= S.pos.y or z ~= S.pos.z then
    local was = fmt()
    S.pos.x, S.pos.y, S.pos.z = x, y, z
    save()
    return "position corrected by GPS: " .. was .. " -> " .. fmt()
  end
end

-- before a trip: full fix if GPS is there (also fixes a wrong facing)
function verifyPose()
  if gpsRaw(1) then
    local ok, msg = gpsFix()
    if ok and (msg:find("was wrong", 1, true) or msg:find("NOT checked", 1, true)) then
      send("result", { cmd = "gps", ok = true, msg = msg })
    end
  end
end

---------------------------------------------------------------------
-- scanning (the Geo Scanner is swapped in for the modem, then back)
---------------------------------------------------------------------
function findItem(name)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == name then return i end
  end
end

-- run fn(scanner) with the Geo Scanner equipped where the modem was
function withScanner(fn)
  if modem ~= "left" and modem ~= "right" then
    return false, "the modem must be EQUIPPED (left or right) for scanning"
  end
  local slot = findItem(CONFIG.geoItem)
  if not slot then return false, "no Geo Scanner in the inventory" end
  turtle.select(slot)
  if not equipOn(modem) then
    turtle.select(1)
    return false, "could not equip the Geo Scanner"
  end
  modemAttached = false                -- the modem is now an item in `slot`

  -- the upgrade can take a moment to appear: wait up to 2 seconds, then find
  -- its scan function ("scan", or whatever this version calls it)
  local sc, methods
  for _ = 1, 20 do
    sleep(0.1)
    methods = peripheral.getMethods(modem)
    if methods then
      local name
      for _, m in ipairs(methods) do if m == "scan" then name = m end end
      if not name then
        for _, m in ipairs(methods) do
          local l = m:lower()
          if l:find("scan", 1, true) and not l:find("cost", 1, true) then name = m break end
        end
      end
      if name then
        local side = modem
        sc = { scan = function(r) return peripheral.call(side, name, r) end, fname = name }
        break
      end
    end
  end
  local info
  if not sc then
    info = "the Geo Scanner has no scan function (side " .. modem .. ", type " ..
           tostring((peripheral.getType(modem))) .. ")"
  end
  local ok, a, b = pcall(function()
    if not sc then error(info, 0) end
    return fn(sc)
  end)
  if not sc and methods then
    -- send the full list in short pieces, so it can be read on the base LOG
    local line = ""
    local lines = {}
    for _, m in ipairs(methods) do
      if #line + #m > 60 then lines[#lines + 1] = line; line = "" end
      line = line .. (line == "" and "" or ",") .. m
    end
    if line ~= "" then lines[#lines + 1] = line end
    pendingInfo = lines
  end
  -- always put the modem back. It is NOT always in `slot`: with a stack of
  -- scanners there it went to another free slot - so look for it by name.
  local back = false
  local mslot = findItemLike("modem")
  if mslot then
    turtle.select(mslot)
    back = equipOn(modem)
  end
  turtle.select(1)
  sleep(0.2)
  pcall(rednet.open, modem)
  modemAttached = back and true or false
  if not back then return false, "could not re-equip the modem!" end
  if not ok then return false, tostring(a) end
  return a, b
end

-- run fn() with an item whose name contains `part` equipped where the modem
-- was; the modem is always put back (found by name, like after a scan)
function withEquipped(part, fn)
  if modem ~= "left" and modem ~= "right" then return false end
  local slot = findItemLike(part)
  if not slot then return false end
  turtle.select(slot)
  if not equipOn(modem) then turtle.select(1) return false end
  modemAttached = false
  sleep(0.1)
  local ok, res = pcall(fn)
  local mslot = findItemLike("modem")
  local back = false
  if mslot then
    turtle.select(mslot)
    back = equipOn(modem)
  end
  turtle.select(1)
  sleep(0.1)
  pcall(rednet.open, modem)
  modemAttached = back and true or false
  return ok and res
end

function natural(name)
  name = tostring(name)
  for _, n in ipairs(CONFIG.digOk) do
    if name:find(n, 1, true) then return true end
  end
  return false
end

tryDig = function(dir)
  if not CONFIG.dig then return false end
  local inspect = (dir == "up" and turtle.inspectUp) or (dir == "down" and turtle.inspectDown) or turtle.inspect
  local okI, data = inspect()
  if not okI or type(data) ~= "table" or not natural(data.name) then return false end
  local dig = (dir == "up" and turtle.digUp) or (dir == "down" and turtle.digDown) or turtle.dig
  return withEquipped("_pickaxe", dig) == true
end

function isOre(b)
  local n = tostring(b.name)
  if n:find("_ore", 1, true) or n:find("ancient_debris", 1, true) then return true end
  if type(b.tags) == "table" then
    for _, t in pairs(b.tags) do
      if tostring(t):find("ores", 1, true) then return true end
    end
  end
  return false
end

-- scan here and send the map summary: top block per column + ores
-- Terrain memory (world coordinates). In Minecraft nothing remembered is a
-- fact: blocks get placed and dug. So every wall has a TIME and a KIND, is
-- fully trusted only while fresh, and then fades back to "unknown". What the
-- turtle sees now always wins. Walls found by bumping into them, dead ends
-- and the exit route are shared with all turtles through the base.
function now() return os.epoch("utc") end
local MEM, memCount = {}, 0       -- [key] = { t = time, k = kind, s = "scan"|"bump"|"base" }
local DEAD = {}                    -- [key] = { x, y, z, t }   places where a turtle got stuck
local EXIT = nil                   -- { points = { {x,y,z}, ... }, t = time }   the way out of the base
local pend = { walls = {}, clears = {}, dead = {} }           -- still to tell the base
function memKey(x, y, z) return x .. "," .. y .. "," .. z end

-- how long a remembered wall is trusted (ms): fully while fresh, then it fades
local LIFE = {
  hard  = { fresh = 10 * 60000, fade = 6 * 3600000 },  -- stone, buildings
  short = { fresh = 2 * 60000,  fade = 30 * 60000 },   -- sand, gravel, leaves, snow: change by themselves
  door  = { fresh = 60000,      fade = 10 * 60000 },   -- doors, trapdoors, gates: opened and closed
}
function kindOf(name)
  local n = tostring(name)
  if n:find("door", 1, true) or n:find("gate", 1, true) then return "door" end
  if n:find("sand", 1, true) or n:find("gravel", 1, true) or n:find("leaves", 1, true)
     or n:find("snow", 1, true) or n:find("powder", 1, true) or n:find("scaffold", 1, true) then
    return "short"
  end
  return "hard"
end
-- extra cost of planning through a remembered wall: nil = blocked, 0 = forgotten
function wallCost(e, t)
  local L = LIFE[e.k] or LIFE.hard
  local age = t - e.t
  if age < L.fresh then return nil end
  if age > L.fresh + L.fade then return 0 end
  return 40 * (1 - (age - L.fresh) / L.fade)
end
function isLiquid(name)
  name = tostring(name)
  return name:find("water", 1, true) or name:find("lava", 1, true)
end

function memWall(x, y, z, kind, src, t)
  local k = memKey(x, y, z)
  local old = MEM[k]
  t = t or now()
  if old and old.t > t then return end              -- keep the newer knowledge
  if not old then memCount = memCount + 1 end
  MEM[k] = { t = t, k = kind or "hard", s = src or "scan" }
end
function memClear(x, y, z)
  local k = memKey(x, y, z)
  local old = MEM[k]
  if old then
    MEM[k] = nil
    memCount = memCount - 1
    if old.s ~= "scan" then pend.clears[#pend.clears + 1] = k end   -- a shared wall is gone
  end
end
memFree = function(x, y, z) memClear(x, y, z) end

-- a scan: listed blocks are walls (with their kind), every other cell is free
function learnScan(data, r)
  if not (S.pos and S.pos.x) then return end
  if memCount > 250000 then MEM, memCount = {}, 0 end
  local cx, cy, cz = S.pos.x, S.pos.y, S.pos.z
  local seen = {}
  for _, b in ipairs(data) do
    if type(b) == "table" and b.name and not isLiquid(b.name) then
      seen[memKey(cx + (b.x or 0), cy + (b.y or 0), cz + (b.z or 0))] = kindOf(b.name)
    end
  end
  local t = now()
  for dx = -r, r do
    for dy = -r, r do
      for dz = -r, r do
        local x, y, z = cx + dx, cy + dy, cz + dz
        local kind = seen[memKey(x, y, z)]
        if kind then memWall(x, y, z, kind, "scan", t) else memClear(x, y, z) end
      end
    end
  end
  memClear(cx, cy, cz)
end
local lastScanAt = nil

-- a move failed and there IS a block: remember it, and tell the others
learnBlocked = function(dir)
  if not (S.pos and S.pos.x and S.pos.f) then return end
  local inspect = (dir == "up" and turtle.inspectUp) or (dir == "down" and turtle.inspectDown) or turtle.inspect
  local okI, d = inspect()
  if not okI then return end
  local x, y, z = S.pos.x, S.pos.y, S.pos.z
  if dir == "up" then y = y + 1
  elseif dir == "down" then y = y - 1
  else x, z = x + DX[S.pos.f], z + DZ[S.pos.f] end
  local kind = kindOf(type(d) == "table" and d.name)
  local k = memKey(x, y, z)
  local old = MEM[k]
  memWall(x, y, z, kind, "bump")
  if not old or old.s == "scan" or (now() - old.t) > 60000 then
    pend.walls[#pend.walls + 1] = k .. "," .. kind
  end
end

-- a place where the turtle could not get on: avoided for a while (shared)
function addDead(x, y, z)
  local k = memKey(x, y, z)
  DEAD[k] = { x = x, y = y, z = z, t = now() }
  pend.dead[#pend.dead + 1] = k
end
-- is x y z inside a remembered dead end (still fresh)?
function deadNear(x, y, z)
  local r, t = CONFIG.deadRadius, now()
  for _, d in pairs(DEAD) do
    if t - d.t < CONFIG.deadLife and math.abs(d.x - x) <= r and math.abs(d.z - z) <= r
       and math.abs(d.y - y) <= r then
      return true
    end
  end
  return false
end

-- route recording (the exit route): every block moved through, loops cut out
local REC, recIdx = nil, nil
function recStart()
  REC, recIdx = {}, {}
  if S.pos and S.pos.x then
    REC[1] = { S.pos.x, S.pos.y, S.pos.z }
    recIdx[memKey(S.pos.x, S.pos.y, S.pos.z)] = 1
  end
end
recAdd = function()
  if not REC then return end
  local k = memKey(S.pos.x, S.pos.y, S.pos.z)
  local i = recIdx[k]
  if i then
    for j = #REC, i + 1, -1 do
      recIdx[memKey(REC[j][1], REC[j][2], REC[j][3])] = nil
      REC[j] = nil
    end
  else
    REC[#REC + 1] = { S.pos.x, S.pos.y, S.pos.z }
    recIdx[k] = #REC
  end
  S.recCount = #REC
end
function recStop()
  local r = REC
  REC, recIdx = nil, nil
  return r or {}
end
-- keep only the corners of a path of neighbouring blocks
function compressRoute(cells)
  if #cells <= 2 then return cells end
  local out = { cells[1] }
  for i = 2, #cells - 1 do
    local a, b, c = cells[i - 1], cells[i], cells[i + 1]
    local d1 = (b[1] - a[1]) .. "," .. (b[2] - a[2]) .. "," .. (b[3] - a[3])
    local d2 = (c[1] - b[1]) .. "," .. (c[2] - b[2]) .. "," .. (c[3] - b[3])
    if d1 ~= d2 then out[#out + 1] = b end
  end
  out[#out + 1] = cells[#cells]
  return out
end
function routeToString(points)
  local o = {}
  for _, p in ipairs(points) do o[#o + 1] = p[1] .. "," .. p[2] .. "," .. p[3] end
  return table.concat(o, ";")
end
function routeFromString(str)
  local pts = {}
  for x, y, z in tostring(str or ""):gmatch("(-?%d+),(-?%d+),(-?%d+)") do
    pts[#pts + 1] = { tonumber(x), tonumber(y), tonumber(z) }
  end
  return pts
end

-- scan around the turtle (GPS-checked first); returns the raw block list
function scanRaw(r)
  local fix = gpsCheck()
  if fix then send("result", { cmd = "gps", ok = true, msg = fix }) end
  if not (S.pos and S.pos.x) then return nil, "position unknown - use GPS LOCATE" end
  r = math.max(1, math.min(16, math.floor(tonumber(r) or CONFIG.scanRadius)))
  local data, err = withScanner(function(sc)
    local res, e = sc.scan(r)
    if not res then
      sleep(2.5)                       -- probably the cooldown between scans
      res, e = sc.scan(r)
    end
    if not res then error(e or "scan failed") end
    return res
  end)
  if not data then return nil, err end
  learnScan(data, r)
  lastScanAt = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
  return data, r
end

-- Scans are kept here until the base confirms it stored them (it may be
-- offline when the owner left the server). Re-sent from the heartbeat.
local OUTBOX_FILE = "node_outbox"
local outbox = {}
if fs.exists(OUTBOX_FILE) then
  local h = fs.open(OUTBOX_FILE, "r")
  local t = textutils.unserialize(h.readAll() or "")
  h.close()
  if type(t) == "table" then
    outbox = t
    for _, p in ipairs(outbox) do       -- fields an old version wrongly added to stored scans
      if type(p) == "table" then p.home, p.pos, p.sig, p.n, p.t = nil, nil, nil, nil, nil end
    end
  end
end
function outboxSave()
  writeFile(OUTBOX_FILE, outbox)
end
function sendScan(payload)
  S.scanSeq = (S.scanSeq or 0) + 1
  save()
  payload.sid = S.scanSeq
  outbox[#outbox + 1] = payload
  while #outbox > CONFIG.outboxMax do table.remove(outbox, 1) end
  outboxSave()
  send("scan", payload)
end
outboxAck = function(sid)
  for i = #outbox, 1, -1 do
    if outbox[i].sid == sid then table.remove(outbox, i) end
  end
  outboxSave()
end
outboxCount = function() return #outbox end
outboxResend = function()
  for i = 1, math.min(3, #outbox) do send("scan", outbox[i]) end
end

-- send the map summary of a scan (top block per column + ores); returns #ores
function sendSummary(data, r)
  local n = 2 * r + 1
  local cols, names, nidx, ores = {}, {}, {}, {}
  local function pal(nm)
    local i = nidx[nm]
    if not i then
      i = #names + 1
      names[i], nidx[nm] = nm, i
    end
    return i
  end
  for _, b in ipairs(data) do
    if type(b) == "table" and b.name then
      local dx, dy, dz = b.x or 0, b.y or 0, b.z or 0
      if not (dx == 0 and dy == 0 and dz == 0) and math.abs(dx) <= r and math.abs(dz) <= r then
        local idx = (dz + r) * n + (dx + r) + 1
        local t = cols[idx]
        if not t or dy > t[1] then cols[idx] = { dy, pal(b.name) } end
        if #ores < 300 and isOre(b) then ores[#ores + 1] = { dx, dy, dz, pal(b.name) } end
      end
    end
  end
  sendScan({ x = S.pos.x, y = S.pos.y, z = S.pos.z, r = r,
             names = names, cols = cols, ores = ores })
  return #ores
end

-- scan here and send the map summary
function scanHere(r)
  task = "scanning"
  local data, rr = scanRaw(r)
  if not data then return false, rr end
  local nores = sendSummary(data, rr)
  return true, "scanned " .. #data .. " blocks at " .. fmt() .. " (" .. nores .. " ores)"
end

---------------------------------------------------------------------
-- navigation
---------------------------------------------------------------------
function isStop(err) return tostring(err):find("^stopped") ~= nil end
function note(cmd, msg) send("result", { cmd = cmd, ok = false, msg = msg }) end

-- ---- sharing with the base (all turtles learn from each other) ----
local knowReady = false
-- ask the base what is known around here and around the target (walls with
-- their age, dead ends, the exit route); waits up to 3 s for the answer
-- CRUISE = how high this trip has to fly (from the base's map; nil = not known
-- -> the sky highway CONFIG.skyY). CRUISE_FOR = the target it was asked for.
CRUISE, CRUISE_FOR = nil, nil
function requestKnowledge(tx, tz)
  if not (S.pos and S.pos.x) then return end
  knowReady = false
  CRUISE, CRUISE_FOR = nil, tx .. "," .. tz
  send("need", { x1 = math.min(S.pos.x, tx), z1 = math.min(S.pos.z, tz),
                 x2 = math.max(S.pos.x, tx), z2 = math.max(S.pos.z, tz),
                 fx = S.pos.x, fz = S.pos.z, tx = tx, tz = tz })
  for _ = 1, 15 do
    if knowReady then return end
    sleep(0.2)
  end
end
-- what this turtle learnt: walls it bumped into, walls that are gone, dead ends
function learnFlush()
  if #pend.walls + #pend.clears + #pend.dead == 0 then return end
  send("learn", { walls = table.concat(pend.walls, ";"), clears = table.concat(pend.clears, ";"),
                  dead = table.concat(pend.dead, ";") })
  pend = { walls = {}, clears = {}, dead = {} }
end

-- ---- progress watchdog: no real progress for a while = change strategy ----
local WD = {}
function watchStart(tx, ty, tz, goalY)
  WD = { tx = tx, ty = ty, tz = tz, goalY = goalY, best = math.huge, at = moveCount }
end
function watchStalled()
  if not (S.pos and S.pos.x and WD.tx) then return false end
  local d
  if WD.goalY then d = math.max(0, WD.goalY - S.pos.y)
  else
    d = math.abs(S.pos.x - WD.tx) + math.abs(S.pos.z - WD.tz)
    if WD.ty then d = d + math.abs(S.pos.y - WD.ty) end
  end
  if d < WD.best then WD.best, WD.at = d, moveCount end
  return moveCount - WD.at > CONFIG.noProgress
end

-- ---- A* through the remembered terrain ----
-- Unknown space counts as passable. A fresh wall blocks; an older wall can be
-- planned through at extra cost (it may be gone). Dead ends cost extra.
-- ty = nil: any height at tx/tz is fine. goalY: just get up to that height.
function astar(sx, sy, sz, tx, ty, tz, goalY, near)
  local m = CONFIG.navMargin
  local minX, maxX = math.min(sx, tx) - m, math.max(sx, tx) + m
  local minZ, maxZ = math.min(sz, tz) - m, math.max(sz, tz) + m
  local minY = math.max(-63, math.min(sy, ty or sy) - 20)
  local maxY = math.min(318, math.max(sy, ty or sy, goalY or sy) + 30)
  local SY, SZ = maxY - minY + 1, maxZ - minZ + 1
  local tnow = now()
  local function key(x, y, z) return ((x - minX) * SY + (y - minY)) * SZ + (z - minZ) end
  local function h(x, y, z)
    if goalY then return math.max(0, goalY - y) end
    local d = math.abs(x - tx) + math.abs(z - tz)
    if ty then d = d + math.abs(y - ty) end
    if type(near) == "table" then
      return math.max(0, math.abs(x - tx) + math.abs(z - tz) - near.h) + math.max(0, math.abs(y - (ty or y)) - near.v)
    elseif near then
      d = math.max(0, d - near)
    end
    return d
  end
  local function isGoal(x, y, z)
    if goalY then return y >= goalY end
    if type(near) == "table" then
      return math.abs(x - tx) + math.abs(z - tz) <= near.h and math.abs(y - (ty or y)) <= near.v
    elseif near then
      return math.abs(x - tx) + math.abs(z - tz) + (ty and math.abs(y - ty) or 0) <= near
    end
    return x == tx and z == tz and (not ty or y == ty)
  end
  -- dead ends near the route cost extra (fading with their age)
  local deadCost = {}
  for _, d in pairs(DEAD) do
    local age = tnow - d.t
    if age < CONFIG.deadLife and d.x >= minX and d.x <= maxX and d.z >= minZ and d.z <= maxZ then
      local pen = 25 * (1 - age / CONFIG.deadLife)
      local R = CONFIG.deadRadius
      for dx = -R, R do for dy = -R, R do for dz = -R, R do
        local kk = memKey(d.x + dx, d.y + dy, d.z + dz)
        deadCost[kk] = math.max(deadCost[kk] or 0, pen)
      end end end
    end
  end
  local hf, hk, hn = {}, {}, 0
  local function push(f, k)
    hn = hn + 1
    local i = hn
    while i > 1 do
      local pi = math.floor(i / 2)
      if hf[pi] <= f then break end
      hf[i], hk[i] = hf[pi], hk[pi]
      i = pi
    end
    hf[i], hk[i] = f, k
  end
  local function pop()
    local k = hk[1]
    local lf, lk = hf[hn], hk[hn]
    hf[hn], hk[hn] = nil, nil
    hn = hn - 1
    if hn > 0 then
      local i = 1
      while true do
        local c = i * 2
        if c > hn then break end
        if c < hn and hf[c + 1] < hf[c] then c = c + 1 end
        if hf[c] >= lf then break end
        hf[i], hk[i] = hf[c], hk[c]
        i = c
      end
      hf[i], hk[i] = lf, lk
    end
    return k
  end
  local g, X, Y, Z, parent, closed = {}, {}, {}, {}, {}, {}
  local sk = key(sx, sy, sz)
  g[sk], X[sk], Y[sk], Z[sk], parent[sk] = 0, sx, sy, sz, false
  push(h(sx, sy, sz), sk)
  local D6 = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 0, -1, 0 } }
  local expanded = 0
  while hn > 0 do
    local k = pop()
    if not closed[k] then
      closed[k] = true
      local x, y, z = X[k], Y[k], Z[k]
      if isGoal(x, y, z) then
        local path, n = {}, k
        while parent[n] do
          table.insert(path, 1, { X[n], Y[n], Z[n] })
          n = parent[n]
        end
        return path
      end
      expanded = expanded + 1
      if expanded > CONFIG.navNodes then return nil, "the way is too long or too complicated" end
      if expanded % 1000 == 0 then
        os.queueEvent("nav_yield")
        os.pullEvent("nav_yield")
      end
      for _, d in ipairs(D6) do
        local nx, ny, nz = x + d[1], y + d[2], z + d[3]
        if nx >= minX and nx <= maxX and ny >= minY and ny <= maxY and nz >= minZ and nz <= maxZ then
          local mk = memKey(nx, ny, nz)
          local e = MEM[mk]
          local extra = 0
          if e then extra = wallCost(e, tnow) end
          if extra ~= nil then
            local nk = key(nx, ny, nz)
            if not closed[nk] then
              local step = 1 + extra + (deadCost[mk] or 0)
              if not ty and not goalY and d[2] < 0 then step = step + 0.5 end  -- don't sink into caves
              local ng = g[k] + step
              if g[nk] == nil or ng < g[nk] then
                g[nk], X[nk], Y[nk], Z[nk], parent[nk] = ng, nx, ny, nz, k
                push(ng + h(nx, ny, nz), nk)
              end
            end
          end
        end
      end
    end
  end
  return nil, "no way found with what I know"
end

-- plan a route (A*), follow it, check every step against reality: a block
-- that is not where the plan expected is learnt and the route re-planned;
-- re-scan as it goes (with a Geo Scanner) or feel around (without).
findWay = function(tx, ty, tz, goalY, near)
  local scanner = findItem(CONFIG.geoItem) ~= nil
  local function rescan()
    if not scanner then return end
    task = "scanning the surroundings"
    local data, r = scanRaw(CONFIG.scanRadius)
    if data then pcall(sendSummary, data, r) end
  end
  local function senseAround()
    local x, y, z = S.pos.x, S.pos.y, S.pos.z
    if turtle.detectUp() then memWall(x, y + 1, z, "hard", "scan") else memClear(x, y + 1, z) end
    if turtle.detectDown() then memWall(x, y - 1, z, "hard", "scan") else memClear(x, y - 1, z) end
    if S.pos.f then
      for _ = 1, 4 do
        local f = S.pos.f
        if turtle.detect() then memWall(x + DX[f], y, z + DZ[f], "hard", "scan")
        else memClear(x + DX[f], y, z + DZ[f]) end
        right()
      end
    end
  end
  local function arrived()
    if goalY then return S.pos.y >= goalY end
    if type(near) == "table" then
      return math.abs(S.pos.x - tx) + math.abs(S.pos.z - tz) <= near.h and math.abs(S.pos.y - (ty or S.pos.y)) <= near.v
    elseif near then
      return math.abs(S.pos.x - tx) + math.abs(S.pos.z - tz) + (ty and math.abs(S.pos.y - ty) or 0) <= near
    end
    return S.pos.x == tx and S.pos.z == tz and (not ty or S.pos.y == ty)
  end
  watchStart(tx, ty, tz, goalY)
  rescan()
  if not scanner then senseAround() end
  local maxPlans = scanner and CONFIG.navReplans or CONFIG.navReplans * 6
  local plans, bumps = 0, 0
  while plans < maxPlans do
    if stopFlag then return false, "stopped" end
    if arrived() then return true, "reached the target on a planned route" end
    task = "planning a route"
    local path, err = astar(S.pos.x, S.pos.y, S.pos.z, tx, ty, tz, goalY, near)
    if not path then return false, err end
    plans = plans + 1
    task = "following a planned route (" .. #path .. " blocks)"
    for _, p in ipairs(path) do
      if stopFlag then return false, "stopped" end
      if noFuel() then return false, "out of fuel at " .. fmt() end
      if watchStalled() then return false, "no progress (going in circles) at " .. fmt() end
      if not stepTo(p[1], p[2], p[3]) then
        -- reality differs from the plan: the block is learnt (fwd/up/down
        -- did that); make sure a planned cell never stays "free" in memory
        if not MEM[memKey(p[1], p[2], p[3])] then memWall(p[1], p[2], p[3], "hard", "bump") end
        bumps = bumps + 1
        if scanner then
          if bumps % 3 == 0 then rescan() end
        else
          senseAround()
        end
        break
      end
      if scanner and lastScanAt and (math.abs(S.pos.x - lastScanAt.x) + math.abs(S.pos.y - lastScanAt.y)
                                    + math.abs(S.pos.z - lastScanAt.z)) >= CONFIG.navRescan then
        rescan()
        break
      end
    end
  end
  if arrived() then return true, "reached the target on a planned route" end
  return false, "gave up after " .. plans .. " plans"
end

-- reach tx/tz at about the current height: forward, climb, step around, and
-- when really stuck: a planned route. The watchdog ends useless wandering.
local sinceCheck = 0
function moveToXZ(tx, tz)
  local planned = 0
  watchStart(tx, nil, tz)
  for _ = 1, 6 do
    if S.pos.x == tx and S.pos.z == tz then return true end
    for _, axis in ipairs({ "x", "z" }) do
      local target = (axis == "x") and tx or tz
      local tries = 0
      while S.pos[axis] ~= target do
        if stopFlag then return false, "stopped at " .. fmt() end
        local fl = turtle.getFuelLevel()
        if fl ~= "unlimited" and fl < 50 and S.reuse and next(S.reuse) then
          topUp(math.min(refuelTarget(), fl + 2000), true)
          fl = turtle.getFuelLevel()
        end
        if fl ~= "unlimited" and fl < 1 then return false, "out of fuel at " .. fmt() end
        if watchStalled() then return false, "no progress (going in circles) at " .. fmt() end
        local f
        if axis == "x" then f = (target > S.pos.x) and 3 or 1
        else f = (target > S.pos.z) and 0 or 2 end
        face(f)
        -- a known dead end straight ahead: plan a way around it instead of
        -- walking back into it
        if planned < CONFIG.pathfind and deadNear(S.pos.x + DX[f], S.pos.y, S.pos.z + DZ[f]) then
          planned = planned + 1
          local okW, why = findWay(tx, nil, tz)
          if okW then break end
          if isStop(why) then return false, why end
        end
        if not stepForward() then
          tries = tries + 1
          if tries > CONFIG.sidestep or not sidestep(f) then
            if planned >= CONFIG.pathfind then return false, "blocked at " .. fmt() end
            planned = planned + 1
            local okW, why = findWay(tx, nil, tz)
            if not okW then return false, "blocked at " .. fmt() .. " (" .. tostring(why) .. ")" end
            note("move", why)
            tries = 0
            watchStart(tx, nil, tz)
          end
        end
        sinceCheck = sinceCheck + 1
        if sinceCheck >= CONFIG.gpsEvery then
          sinceCheck = 0
          local fix = gpsCheck()
          if fix then send("result", { cmd = "gps", ok = true, msg = fix }) end
        end
      end
    end
  end
  if S.pos.x == tx and S.pos.z == tz then return true end
  return false, "could not reach " .. tx .. " " .. tz .. " (at " .. fmt() .. ")"
end

-- the last part of a trip: sideways at about this height, then up/down
function gotoLocal(tx, ty, tz)
  for attempt = 1, CONFIG.pathfind + 1 do
    local ok, err = moveToXZ(tx, tz)
    if not ok then return false, err end
    local stuck = false
    while S.pos.y ~= ty do
      if stopFlag then return false, "stopped at " .. fmt() end
      local moved
      if S.pos.y > ty then moved = down() or (tryDig("down") and down())
      else moved = up() or (tryDig("up") and up()) end
      if not moved then stuck = true break end
    end
    if not stuck then return true, "arrived at " .. fmt() end
    if attempt > CONFIG.pathfind then break end
    local okW, why = findWay(tx, ty, tz)
    if okW then return true, "arrived at " .. fmt() end
    if isStop(why) then return false, why end
  end
  return false, "could not reach " .. tx .. " " .. ty .. " " .. tz .. " (at " .. fmt() .. ")"
end

-- up to the sky highway (straight up, or a planned way up past a roof)
function climbToSky()
  -- as high as this trip needs (the base's map), the sky highway otherwise
  local sky = CONFIG.skyY
  if CRUISE and CRUISE < sky then sky = CRUISE end
  task = (sky < CONFIG.skyY) and ("climbing to cruise height " .. sky) or "climbing to the sky highway"
  while S.pos.y < sky do
    if stopFlag then return false, "stopped" end
    if noFuel() then return false, "out of fuel" end
    if not up() and not (tryDig("up") and up()) then
      local ok, err = findWay(S.pos.x, nil, S.pos.z, sky)
      if not ok then return false, "no way up to the sky highway (" .. tostring(err) .. ")" end
    end
  end
  return true
end

-- the cells of one straight piece of a route (a exclusive, b inclusive)
function segmentCells(a, b)
  local cells = {}
  local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local n = math.abs(dx) + math.abs(dy) + math.abs(dz)
  if (dx ~= 0 and 1 or 0) + (dy ~= 0 and 1 or 0) + (dz ~= 0 and 1 or 0) > 1 then return nil end
  local sx, sy, sz = (dx > 0 and 1) or (dx < 0 and -1) or 0, (dy > 0 and 1) or (dy < 0 and -1) or 0,
                     (dz > 0 and 1) or (dz < 0 and -1) or 0
  for i = 1, n do cells[i] = { a[1] + sx * i, a[2] + sy * i, a[3] + sz * i } end
  return cells
end

-- follow a recorded route (the exit route), checking every step. A blocked
-- piece is walked around; the repaired route is saved for everybody.
function followRoute(points, label, reversed)
  local ok, err = gotoLocal(points[1][1], points[1][2], points[1][3])
  if not ok then return false, label .. ": cannot reach its start (" .. tostring(err) .. ")" end
  recStart()
  local repaired = false
  for i = 2, #points do
    if stopFlag then recStop() return false, "stopped" end
    local a, b = points[i - 1], points[i]
    task = label .. " " .. (i - 1) .. "/" .. (#points - 1)
    local cells = segmentCells(a, b)
    local blocked = cells == nil
    if cells then
      for _, c in ipairs(cells) do
        if not stepTo(c[1], c[2], c[3]) then blocked = true break end
      end
    end
    if blocked then
      local okW, why = findWay(b[1], b[2], b[3])
      if not okW then
        recStop()
        return false, label .. " is blocked near " .. fmt() .. " (" .. tostring(why) .. ")"
      end
      repaired = true
    end
  end
  local cellsWalked = recStop()
  if repaired and #cellsWalked > 1 then
    local pts = compressRoute(cellsWalked)
    if reversed then
      local r = {}
      for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
      pts = r
    end
    EXIT = { points = pts, t = now() }
    send("exitroute", { route = routeToString(pts) })
    note("route", label .. " was blocked - found another way and saved it")
  end
  return true
end

function near(p, x, z, d) return p and math.abs(p[1] - x) + math.abs(p[3] - z) <= d end

-- ===== End Automata Core: teleport between saved points =====
-- The points live inside the core (lost if it is taken off); their
-- positions are kept here too (the core only tells the names).
-- is this an End Automata Core? ("end_automata", "endAutomata", the overpowered
-- one ... - spelled differently in different versions)
function isEndCore(s)
  s = tostring(s or ""):lower():gsub("[^%a]", "")
  return s:find("endautomata", 1, true) ~= nil
end
-- the side an EQUIPPED core is on
function warpCore()
  for _, side in ipairs({ "left", "right" }) do
    local t = peripheral.getType(side)
    if t and isEndCore(t) then return side end
  end
end
-- the inventory slot of a CARRIED core (not equipped)
function coreSlot()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isEndCore(d.name) then return i end
  end
end
function hasCore() return warpCore() ~= nil or coreSlot() ~= nil end
-- can this turtle warp? Equipped core: yes. Carried core: only if it keeps its
-- warp points when taken off (tested once - coreCheck)
function canWarp()
  if warpCore() then return true end
  return coreSlot() ~= nil and S.coreKeepsPoints ~= false
end

-- once per core: equip it, read ALL its functions (sent to the base), and for
-- a carried core test whether it keeps a warp point when taken off
function coreCheck()
  S.coreChecked = true
  local carried = (warpCore() == nil)
  local saved = withCore(function()
    local side = warpCore()
    local okM, m = pcall(peripheral.getMethods, side)
    if okM and type(m) == "table" then table.sort(m) S.coreMethods = m end
    return wcall("savePoint", "zz_keeptest") and true or false
  end)
  local keeps
  if carried and saved then
    -- taken off and put on again: is the point still there?
    keeps = withCore(function()
      local pts = wcall("getPoints")
      local found = false
      if type(pts) == "table" then
        for k, v in pairs(pts) do if v == "zz_keeptest" or k == "zz_keeptest" then found = true end end
      end
      wcall("deletePoint", "zz_keeptest")
      return found
    end) and true or false
    S.coreKeepsPoints = keeps
  elseif saved then
    withCore(function() return wcall("deletePoint", "zz_keeptest") end)
  end
  save()
  send("result", { cmd = "core", ok = true, msg = "End Automata Core (" .. (carried and "carried" or "equipped") ..
                   ") functions: " .. table.concat(S.coreMethods or { "?" }, ", ") })
  if carried and keeps == false then
    send("result", { cmd = "core", ok = false, msg = "the carried End Automata Core forgets its warp points when it " ..
                     "is taken off - it cannot warp while carried (the Chunky upgrade always stays on)" })
  elseif carried and keeps then
    send("result", { cmd = "core", ok = true, msg = "the carried End Automata Core keeps its warp points - it is " ..
                     "swapped in for every warp" })
  end
end
-- run fn with the core equipped: equipped already, or carried - then it goes
-- where the modem is for a moment (like the Geo Scanner; the Chunky upgrade
-- stays, so the chunk stays loaded) and the modem is put back afterwards
function withCore(fn)
  if warpCore() then return fn() end
  local slot = coreSlot()
  if not slot then return false, "no End Automata Core" end
  if modem ~= "left" and modem ~= "right" then return false, "the modem must be equipped to swap the core in" end
  -- wait until a running top-up has put its slot back
  SLOT_LOCK = true
  for _ = 1, 100 do if not TOPUP_RUNNING then break end sleep(0.05) end
  slot = coreSlot() or slot
  local sel = turtle.getSelectedSlot()
  turtle.select(slot)
  if not equipOn(modem) then turtle.select(sel) SLOT_LOCK = false return false, "could not equip the End Automata Core" end
  modemAttached = false
  for _ = 1, 10 do if warpCore() then break end sleep(0.1) end
  local res = { pcall(fn) }
  local mslot = findItemLike("modem")
  local back = false
  if mslot then
    turtle.select(mslot)
    back = equipOn(modem)
  end
  turtle.select(sel)
  sleep(0.1)
  pcall(rednet.open, modem)
  modemAttached = back and true or false
  SLOT_LOCK = false
  if not res[1] then return false, tostring(res[2]) end
  return res[2], res[3]
end
function wcall(m, ...)
  local side = warpCore()
  if not side then return nil, "no End Automata Core equipped" end
  local ok, a, b = pcall(peripheral.call, side, m, ...)
  if not ok then return nil, tostring(a) end
  return a, b
end
function warpSave(name)
  if not (S.pos and S.pos.x) then return false, "position unknown" end
  if not hasCore() then return false, "no End Automata Core" end
  if not canWarp() then return false, "the carried End Automata Core forgets its points - it cannot warp (the Chunky stays on)" end
  return withCore(function() return warpSaveNow(name) end)
end
function warpSaveNow(name)
  S.warps = S.warps or {}
  wcall("deletePoint", name)
  local ok, err = wcall("savePoint", name)
  if not ok and tostring(err):find("limit", 1, true) then
    -- full: drop the oldest automatic point, then try again
    local oldest, ot
    for n, w in pairs(S.warps) do
      if n:sub(1, 5) == "auto_" and (not ot or w.t < ot) then oldest, ot = n, w.t end
    end
    if oldest then wcall("deletePoint", oldest) S.warps[oldest] = nil end
    ok, err = wcall("savePoint", name)
  end
  if not ok then return false, "cannot save warp point: " .. tostring(err) end
  S.warps[name] = { x = S.pos.x, y = S.pos.y, z = S.pos.z, t = now() }
  save()
  return true, "warp point '" .. name .. "' saved at " .. fmt()
end
-- teleport to a saved point (checks the fuel first)
function warpTo(name)
  local w = S.warps and S.warps[name]
  if not w then return false, "no warp point called '" .. tostring(name) .. "'" end
  return withCore(function() return warpToNow(name, w) end)
end
function warpToNow(name, w)
  -- the points live in the core: is this one really still there?
  local pts = wcall("getPoints")
  if type(pts) == "table" then
    local found = false
    for k, v in pairs(pts) do if v == name or k == name then found = true end end
    if not found then
      S.warps[name] = nil
      save()
      return false, "warp point '" .. name .. "' is no longer in the core - forgotten"
    end
  end
  local cost = tonumber((wcall("estimateWarpCost", name)))
  local fuel = turtle.getFuelLevel()
  if fuel ~= "unlimited" and cost and cost > fuel - 50 then return false, "not enough fuel to warp" end
  local ok, err = wcall("warpToPoint", name)
  if not ok then return false, "warp failed: " .. tostring(err) end
  S.pos.x, S.pos.y, S.pos.z = w.x, w.y, w.z
  save()
  trailReset()                       -- the walked path means nothing after a teleport
  return true, "warped to '" .. name .. "' (" .. w.x .. " " .. w.y .. " " .. w.z .. ")"
end
-- the saved point closest to a target, if warping there first saves a lot
function bestWarpFor(tx, ty, tz)
  if not (S.warps and next(S.warps) and canWarp()) then return nil end
  local here = math.abs(tx - S.pos.x) + math.abs(tz - S.pos.z) + math.abs(ty - S.pos.y)
  local best, bd
  for n, w in pairs(S.warps) do
    local d = math.abs(tx - w.x) + math.abs(tz - w.z) + math.abs(ty - w.y)
    if not bd or d < bd then best, bd = n, d end
  end
  if best and bd + CONFIG.warpGain <= here then return best end
end
-- after a long trip: remember the place as an automatic warp point
function warpRemember()
  if not canWarp() then return end
  -- near home: the "home" point is used for that
  if S.home and math.abs(S.home.x - S.pos.x) + math.abs(S.home.z - S.pos.z) + math.abs(S.home.y - S.pos.y) < 32 then
    return
  end
  S.warps = S.warps or {}
  for _, w in pairs(S.warps) do
    if math.abs(w.x - S.pos.x) + math.abs(w.z - S.pos.z) + math.abs(w.y - S.pos.y) < 32 then return end
  end
  local auto = 0
  for n in pairs(S.warps) do if n:sub(1, 5) == "auto_" then auto = auto + 1 end end
  while auto >= CONFIG.warpAutoMax do
    local oldest, ot
    for n, w in pairs(S.warps) do
      if n:sub(1, 5) == "auto_" and (not ot or w.t < ot) then oldest, ot = n, w.t end
    end
    if not oldest then break end
    wcall("deletePoint", oldest)
    S.warps[oldest] = nil
    auto = auto - 1
  end
  warpSave("auto_" .. S.pos.x .. "_" .. S.pos.z)
end

-- A whole trip, the best way: out through the exit route if inside the base,
-- along the sky highway if far, and back in through the exit route if the
-- target is inside the base. Short trips go directly.
function travelOnce(tx, ty, tz)
  if math.abs(tx - S.pos.x) + math.abs(tz - S.pos.z) > CONFIG.skyMinDist and CRUISE_FOR ~= tx .. "," .. tz then
    requestKnowledge(tx, tz)
  end
  -- End Automata Core: teleport to the saved point nearest the target first
  local wp = bestWarpFor(tx, ty, tz)
  if wp then
    local okW, msgW = warpTo(wp)
    note("warp", msgW)
  end
  local far = math.abs(tx - S.pos.x) + math.abs(tz - S.pos.z) > CONFIG.skyMinDist
  if not far then return gotoLocal(tx, ty, tz) end
  local route = EXIT and EXIT.points and #EXIT.points >= 2 and EXIT.points or nil
  local inside, outside = route and route[1], route and route[#route]
  local iAmIn = route and near(inside, S.pos.x, S.pos.z, CONFIG.exitNear)
  local targetIn = route and near(inside, tx, tz, CONFIG.exitNear)
  if iAmIn and not targetIn then
    local ok, err = followRoute(route, "exit route")
    if not ok then return false, err end
  end
  if targetIn and not iAmIn then
    -- home: across the sky to the outside end of the route, then in
    local ok, err = climbToSky()
    if not ok then return false, err end
    ok, err = moveToXZ(outside[1], outside[3])
    if not ok then return false, err end
    ok, err = gotoLocal(outside[1], outside[2], outside[3])
    if not ok then return false, err end
    local rev = {}
    for i = #route, 1, -1 do rev[#rev + 1] = route[i] end
    ok, err = followRoute(rev, "way in", true)
    if not ok then return false, err end
    return gotoLocal(tx, ty, tz)
  end
  if math.abs(tx - S.pos.x) + math.abs(tz - S.pos.z) > CONFIG.skyMinDist then
    local ok, err = climbToSky()
    if not ok then return false, err end
    task = "sky highway to " .. tx .. " " .. tz
    ok, err = moveToXZ(tx, tz)
    if not ok then return false, err end
  end
  return gotoLocal(tx, ty, tz)
end

-- the ladder of strategies: try; back up along the trail and try again;
-- try from the sky highway; then remember a dead end (shared) and give up
function withLadder(what, fn)
  local ok, err = fn()
  if ok or isStop(err) then return ok, err end
  -- stuck here: remember it NOW, so the tries below go around it instead of
  -- walking straight back into it (shared with every turtle)
  addDead(S.pos.x, S.pos.y, S.pos.z)
  learnFlush()
  for _, n in ipairs(CONFIG.backoff) do
    if #trail <= 1 then break end
    note(what, tostring(err) .. " - going back " .. n .. " steps to try another way")
    task = "backing up " .. n .. " steps"
    if not backtrackSteps(n) then break end
    ok, err = fn()
    if ok or isStop(err) then return ok, err end
  end
  if S.pos.y < CONFIG.skyY - 2 then
    note(what, tostring(err) .. " - trying from the sky highway")
    local okS = climbToSky()
    if okS then
      ok, err = fn()
      if ok or isStop(err) then return ok, err end
    end
  end
  addDead(S.pos.x, S.pos.y, S.pos.z)
  learnFlush()
  return false, tostring(err) .. " (remembered as a dead end)"
end

local gotoPos
gotoPos = function(tx, ty, tz)
  if not known() then
    return false, "position/facing unknown - use setpos or GPS LOCATE"
  end
  task = "going to " .. tx .. " " .. ty .. " " .. tz
  send("status")
  requestKnowledge(tx, tz)
  local startDist = math.abs(tx - S.pos.x) + math.abs(tz - S.pos.z)
  local ok, msg = withLadder("goto", function() return travelOnce(tx, ty, tz) end)
  if ok and startDist > CONFIG.skyMinDist then pcall(warpRemember) end
  return ok, msg
end

-- GO HOME: the best way (exit route / sky highway / direct); the whole
-- trail backwards only if that fails
function goHome()
  if not S.home then return false, "no home set (SET HOME)" end
  local h = S.home
  local ok, msg = gotoPos(h.x, h.y, h.z)
  if ok then
    trailReset()
    -- End Automata Core without a "home" point (e.g. equipped after SET HOME): save it now
    if canWarp() and not (S.warps and S.warps.home) then
      local okW = warpSave("home")
      if okW then msg = msg .. " (warp point 'home' saved - GO HOME teleports from now on)" end
    end
    return true, "home: " .. msg
  end
  if isStop(msg) then return false, msg end
  if #trail > 1 then
    note("home", tostring(msg) .. " - retracing my path instead")
    local okB, errB = backtrack()
    if not okB then return false, errB end
    local ok2, msg2 = gotoLocal(h.x, h.y, h.z)
    if ok2 then trailReset() return true, "home (retraced the path)" end
    return false, msg2
  end
  return false, msg
end

-- go down until standing on something - but never far (over a cave or a
-- ravine the turtle would otherwise drop into it)
function settle()
  for _ = 1, CONFIG.settleMax do
    if stopFlag then return end
    if turtle.detectDown() then return end
    if not down() then return end
  end
end

-- map an area: scan points one scan-width apart, zigzag, near the ground
local surveyPoints    -- below

-- a list of spots (from the base): visit the nearest first, then the next
-- nearest, and so on (short trips, no criss-crossing)
function orderNearest(pts)
  local out, left = {}, {}
  for i, p in ipairs(pts) do left[i] = p end
  local cx, cz = S.pos.x, S.pos.z
  while #left > 0 do
    local bi, bd = 1, math.huge
    for i, p in ipairs(left) do
      local d = math.abs(p[1] - cx) + math.abs(p[2] - cz)
      if d < bd then bi, bd = i, d end
    end
    local p = table.remove(left, bi)
    out[#out + 1] = p
    cx, cz = p[1], p[2]
  end
  return out
end

function survey(x1, z1, x2, z2, r)
  if not known() then return false, "position/facing unknown - use GPS LOCATE" end
  r = math.max(1, math.min(16, math.floor(tonumber(r) or CONFIG.scanRadius)))
  if x1 > x2 then x1, x2 = x2, x1 end
  if z1 > z2 then z1, z2 = z2, z1 end
  local step = 2 * r + 1
  local points, row = {}, 0
  for z = z1 + r, z2 + r, step do
    local xs = {}
    for x = x1 + r, x2 + r, step do xs[#xs + 1] = x end
    if row % 2 == 1 then
      for i = 1, math.floor(#xs / 2) do xs[i], xs[#xs + 1 - i] = xs[#xs + 1 - i], xs[i] end
    end
    for _, x in ipairs(xs) do points[#points + 1] = { x, z } end
    row = row + 1
  end
  return surveyPoints(points, r)
end

-- visit scan spots in this order: travel, settle near the ground, scan
surveyPoints = function(points, r)
  if not known() then return false, "position/facing unknown - use GPS LOCATE" end
  if #points > CONFIG.maxSurveyPoints then
    return false, "area too big (" .. #points .. " scans) - zoom in on the map"
  end
  if #points == 0 then return true, "nothing to survey here (already mapped)" end
  requestKnowledge(points[1][1], points[1][2])

  for i, p in ipairs(points) do
    if stopFlag then return false, "stopped after " .. (i - 1) .. " of " .. #points .. " scans" end
    -- the spots still to do (this one included): continued after a restart
    if S.job then
      local left = {}
      for k = i, #points do left[#left + 1] = points[k] end
      S.job.left = left
      save()
    end
    local f = turtle.getFuelLevel()
    if f ~= "unlimited" and f < CONFIG.minFuel * 2 and S.reuse and next(S.reuse) then
      task = "refuelling (reusable fuel)"
      topUp(math.min(refuelTarget(), f + 2000), true)
      f = turtle.getFuelLevel()
    end
    if f ~= "unlimited" and f < CONFIG.minFuel then
      return false, "low fuel (" .. f .. ") after " .. (i - 1) .. " of " .. #points .. " scans"
    end
    task = "survey " .. i .. "/" .. #points
    send("status")
    local far = math.abs(p[1] - S.pos.x) + math.abs(p[2] - S.pos.z) > CONFIG.skyMinDist
    local ok, err = withLadder("survey", function()
      if far then
        -- far away: exit route / sky highway, then come down to the ground
        local okT, errT = travelOnce(p[1], S.pos.y, p[2])
        if not okT and S.pos.x == p[1] and S.pos.z == p[2] then okT = true end
        if okT then pcall(warpRemember) end
        return okT, errT
      end
      return moveToXZ(p[1], p[2])
    end)
    if not ok then return false, err .. " (scan " .. i .. "/" .. #points .. ")" end
    -- after the sky highway: down until standing on something
    for _ = 1, 400 do
      if stopFlag or turtle.detectDown() then break end
      if not down() then break end
      if S.pos.y <= -60 then break end
      if S.pos.y < CONFIG.skyY - 1 and not far then break end
    end
    settle()
    local okS, msg = scanHere(r)
    if not okS then return false, msg end
    task = "survey " .. i .. "/" .. #points
  end
  return true, "survey done: " .. #points .. " scans"
end

---------------------------------------------------------------------
-- search & rescue: find a lost turtle and reinstall it from the install
-- floppy, or bring fuel / a pickaxe to a stuck one
---------------------------------------------------------------------
function slotOf(test)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and test(d.name) then return i, d end
  end
end
function isDrive(n) return n == "computercraft:disk_drive" end
function isFloppy(n) return n == "computercraft:disk" end
function isPick(n) return n:find("_pickaxe", 1, true) ~= nil end
function isFuel(n)
  return n:find("coal", 1, true) or n:find("charcoal", 1, true) or n:find("lava_bucket", 1, true)
         or n:find("blaze_rod", 1, true)
end
-- what rescue gear this turtle carries (reported to the base)
-- what is equipped on a side: item name (short) if this version can tell,
-- else the peripheral type
function sideInfo(side)
  local n = equippedName(side)
  if n then return (n:gsub("^[^:]*:", "")) end
  local ty = peripheral.getType(side)
  return ty and ("[" .. tostring(ty) .. "]") or "?"
end

gearString = function()
  local g = {}
  -- equipment first: a missing Chunky or a short-range modem explains a lot
  local l, r = sideInfo("left"), sideInfo("right")
  g[#g + 1] = "L=" .. l .. " R=" .. r
  local canTell = turtle.getEquippedLeft ~= nil
  if canTell and not (isChunkySide("left") or isChunkySide("right")) then g[#g + 1] = "NO CHUNKY" end
  local mname = canTell and equippedName(modem) or nil
  if mname and not mname:find("advanced", 1, true) and not mname:find("ender", 1, true) then
    g[#g + 1] = "WIRELESS modem (~64 blocks)"
  end
  if slotOf(isDrive) then g[#g + 1] = "drive" end
  if slotOf(isFloppy) then g[#g + 1] = "floppy" end
  if slotOf(isPick) then g[#g + 1] = "pick" end
  if slotOf(isFuel) then g[#g + 1] = "fuel" end
  if findItem(CONFIG.geoItem) then g[#g + 1] = "scanner" end
  local np = 0
  for _ in pairs(S.warps or {}) do np = np + 1 end
  if warpCore() then g[#g + 1] = "warp core (equipped, " .. np .. " points)"
  elseif coreSlot() then
    g[#g + 1] = "warp core (carried, " .. (S.coreKeepsPoints == false and "cannot warp while carried"
                or (np .. " points")) .. ")"
  end
  return table.concat(g, ",")
end

local N6 = { { 0, 1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, -1, 0 } }
function adjacent(x, y, z)
  return math.abs(x - S.pos.x) + math.abs(y - S.pos.y) + math.abs(z - S.pos.z) == 1
end
-- turn towards a neighbouring block: its side name and the matching actions
function faceCell(x, y, z)
  local dx, dy, dz = x - S.pos.x, y - S.pos.y, z - S.pos.z
  if dy == 1 then return "top", turtle.placeUp, turtle.dropUp, turtle.suckUp, turtle.digUp end
  if dy == -1 then return "bottom", turtle.placeDown, turtle.dropDown, turtle.suckDown, turtle.digDown end
  if dx == 1 then face(3) elseif dx == -1 then face(1) elseif dz == 1 then face(0) else face(2) end
  return "front", turtle.place, turtle.drop, turtle.suck, turtle.dig
end
-- get next to x y z (on any free side, except `avoid`)
function approach(x, y, z, avoid)
  if adjacent(x, y, z) and not (avoid and S.pos.x == avoid[1] and S.pos.y == avoid[2] and S.pos.z == avoid[3]) then
    return true
  end
  local cells = {}
  for _, d in ipairs(N6) do
    local c = { x + d[1], y + d[2], z + d[3] }
    if not (avoid and c[1] == avoid[1] and c[2] == avoid[2] and c[3] == avoid[3]) then cells[#cells + 1] = c end
  end
  local function dist(c) return math.abs(c[1] - S.pos.x) + math.abs(c[2] - S.pos.y) + math.abs(c[3] - S.pos.z) end
  table.sort(cells, function(a, b) return dist(a) < dist(b) end)
  for i, c in ipairs(cells) do
    if stopFlag then return false end
    local ok = (i == 1) and gotoPos(c[1], c[2], c[3]) or gotoLocal(c[1], c[2], c[3])
    if ok then return true end
  end
  return false
end
-- is the turtle next to me (at x y z) the one with this ID?
function isTurtle(tid, x, y, z)
  if not adjacent(x, y, z) then return false end
  local side = faceCell(x, y, z)
  if peripheral.getType(side) ~= "turtle" then return false end
  local ok, id = pcall(peripheral.call, side, "getID")
  return ok and id == tid
end

-- find it: at its last known position, else search with the Geo Scanner in
-- a grid of scans (every 16 blocks, nearest first) up to `radius` around it
function locate(tid, x, y, z, radius)
  if approach(x, y, z) and isTurtle(tid, x, y, z) then return x, y, z end
  if not findItem(CONFIG.geoItem) then
    return nil, "turtle " .. tid .. " is not at its last position - I need a Geo Scanner to search"
  end
  radius = math.max(16, math.min(128, math.floor(tonumber(radius) or 16)))
  local around = {}
  for dx = -radius, radius, 16 do
    for dz = -radius, radius, 16 do around[#around + 1] = { dx, dz } end
  end
  table.sort(around, function(a, b) return math.abs(a[1]) + math.abs(a[2]) < math.abs(b[1]) + math.abs(b[2]) end)
  for i, o in ipairs(around) do
    if stopFlag then return nil, "stopped" end
    if i > 1 then gotoPos(x + o[1], y, z + o[2]) end           -- scan from there (or as close as I got)
    task = "searching for turtle " .. tid .. " (" .. i .. "/" .. #around .. ")"
    local data, r = scanRaw(CONFIG.scanRadius)
    if data then
      pcall(sendSummary, data, r)
      local found = {}
      for _, b in ipairs(data) do
        if type(b) == "table" and tostring(b.name):find("turtle", 1, true)
           and not ((b.x or 0) == 0 and (b.y or 0) == 0 and (b.z or 0) == 0) then
          found[#found + 1] = { S.pos.x + b.x, S.pos.y + b.y, S.pos.z + b.z }
        end
      end
      table.sort(found, function(a, b)
        return math.abs(a[1] - x) + math.abs(a[2] - y) + math.abs(a[3] - z)
             < math.abs(b[1] - x) + math.abs(b[2] - y) + math.abs(b[3] - z)
      end)
      for _, f in ipairs(found) do
        if approach(f[1], f[2], f[3]) and isTurtle(tid, f[1], f[2], f[3]) then return f[1], f[2], f[3] end
      end
    end
  end
  return nil, "turtle " .. tid .. " not found within " .. radius .. " blocks of " .. x .. " " .. y .. " " .. z
end

-- an OFFLINE turtle: a Disk Drive with the install floppy next to it, then
-- switch it on - it boots from the floppy and installs the turtle program
function reinstall(tid, lx, ly, lz)
  local dslot, fslot = slotOf(isDrive), slotOf(isFloppy)
  if not (dslot and fslot) then return false, "I need a Disk Drive and the install floppy" end
  local R = { S.pos.x, S.pos.y, S.pos.z }             -- next to the lost turtle: the drive goes here
  local moved = false
  for _, d in ipairs(N6) do
    local c = { R[1] + d[1], R[2] + d[2], R[3] + d[3] }
    if not (c[1] == lx and c[2] == ly and c[3] == lz) and stepTo(c[1], c[2], c[3]) then moved = true break end
  end
  if not moved then return false, "no room next to it for the Disk Drive" end
  local _, place, drop = faceCell(R[1], R[2], R[3])
  turtle.select(dslot)
  if not place() then turtle.select(1) return false, "could not place the Disk Drive" end
  turtle.select(slotOf(isFloppy) or fslot)
  local okDrop = drop(1)
  turtle.select(1)
  if not okDrop then return false, "could not put the floppy into the Disk Drive" end
  if not approach(lx, ly, lz, R) then return false, "cannot get to another side of it to switch it on" end
  local side = faceCell(lx, ly, lz)
  local okOn, on = pcall(peripheral.call, side, "isOn")
  if okOn and on then pcall(peripheral.call, side, "reboot") else pcall(peripheral.call, side, "turnOn") end
  task = "waiting for turtle " .. tid .. " to install itself"
  sleep(8)
  local msg = "turtle " .. tid .. " reinstalled and started at " .. lx .. " " .. ly .. " " .. lz
  if approach(R[1], R[2], R[3], { lx, ly, lz }) then
    local _, _, _, suck, dig = faceCell(R[1], R[2], R[3])
    suck()                                              -- the floppy back
    if slotOf(isPick) then
      if not withEquipped("_pickaxe", dig) then msg = msg .. " (could not pick the Disk Drive up)" end
    else
      msg = msg .. " (Disk Drive left at " .. R[1] .. " " .. R[2] .. " " .. R[3] .. " - I have no pickaxe)"
    end
  else
    msg = msg .. " (could not get back to the Disk Drive at " .. R[1] .. " " .. R[2] .. " " .. R[3] .. ")"
  end
  return true, msg
end

-- a STUCK or empty turtle: put fuel (and a spare pickaxe) into its inventory
function supply(tid, lx, ly, lz)
  local _, _, drop = faceCell(lx, ly, lz)
  local gave = {}
  local fuelSlot = slotOf(isFuel)
  if fuelSlot then
    turtle.select(fuelSlot)
    if drop(math.max(1, math.floor(turtle.getItemCount(fuelSlot) / 2))) then gave[#gave + 1] = "fuel" end
  end
  local picks = 0
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isPick(d.name) then picks = picks + d.count end
  end
  if picks >= 2 then
    turtle.select((slotOf(isPick)))
    if drop(1) then gave[#gave + 1] = "pick" end
  end
  turtle.select(1)
  if #gave == 0 then return false, "nothing to give (I need fuel, or 2 pickaxes to give one away)" end
  return true, "gave turtle " .. tid .. ": " .. table.concat(gave, " + "), table.concat(gave, ",")
end

-- SWEEP: nobody knows where the lost turtles are. Search the area around a
-- centre in a grid of big scans, at three heights; every turtle found that is
-- not online (not in `skip`) is reinstalled on the spot. Natural blocks may be
-- dug during the sweep (with a pickaxe) - lost turtles are often in caves.
function sweep(cx, cy, cz, radius, skip)
  if S.anchor then return false, "I am the ANCHOR - send another turtle" end
  if not findItem(CONFIG.geoItem) then return false, "I need a Geo Scanner to search" end
  if not (slotOf(isDrive) and slotOf(isFloppy)) then
    return false, "I need a Disk Drive and the install floppy to reinstall lost turtles"
  end
  radius = math.max(16, math.min(160, math.floor(tonumber(radius) or 96)))
  local skipSet, handled, rescued = {}, {}, {}
  for id in tostring(skip or ""):gmatch("%d+") do skipSet[tonumber(id)] = true end
  -- progress is saved after every spot: the same search started again
  -- (after a STOP or a restart) continues where it was
  local SWEEP_FILE = "node_sweep"
  local key = cx .. "," .. cy .. "," .. cz .. "," .. radius
  local first = 1
  if fs.exists(SWEEP_FILE) then
    local h = fs.open(SWEEP_FILE, "r")
    local pr = textutils.unserialize(h.readAll() or "")
    h.close()
    if type(pr) == "table" and pr.key == key then
      first = (pr.done or 0) + 1
      handled = pr.handled or {}
      rescued = pr.rescued or {}
      for _, id in ipairs(rescued) do skipSet[id] = true end
      note("rescue", "continuing the search at spot " .. first)
    end
  end
  local function saveProgress(done)
    writeFile(SWEEP_FILE, { key = key, done = done, handled = handled, rescued = rescued })
  end
  skipSet[os.getComputerID()] = true
  local scanR = 16
  local spots = {}
  -- spots every 24 blocks: the scans (16 each way) overlap, so nothing in
  -- between is missed even when a spot is only reached within 4 blocks
  local step = 24
  for _, dy in ipairs({ 0, -30, 30 }) do
    for dx = -radius, radius, step do
      for dz = -radius, radius, step do
        spots[#spots + 1] = { cx + dx, cy + dy, cz + dz, math.abs(dx) + math.abs(dz) + math.abs(dy) * 2 }
      end
    end
  end
  table.sort(spots, function(a, b) return a[4] < b[4] end)
  local function finish(ok, msg) return ok, msg end
  for i = first, #spots do
    local sp = spots[i]
    if stopFlag then
      return finish(false, "stopped at spot " .. i .. "/" .. #spots .. " (" .. #rescued ..
                           " rescued) - start the search again to continue from here")
    end
    task = "searching for lost turtles (" .. i .. "/" .. #spots .. ", found " .. #rescued .. ")"
    send("status")
    -- get to the spot (4 blocks sideways, 12 up/down are enough) through open
    -- space - caves and shafts; with "dig" allowed also through natural rock;
    -- far spots via the exit route / sky highway first. Scan from wherever I got.
    if math.abs(sp[1] - S.pos.x) + math.abs(sp[3] - S.pos.z) > CONFIG.skyMinDist then
      travelOnce(sp[1], S.pos.y, sp[3])
    end
    findWay(sp[1], sp[2], sp[3], nil, { h = 4, v = 12 })
    local data, r = scanRaw(scanR)
    if not data then data, r = scanRaw(8) end         -- a big scan may cost more than allowed
    if data then
      pcall(sendSummary, data, r)
      for _, b in ipairs(data) do
        if type(b) == "table" and tostring(b.name):find("turtle", 1, true)
           and not ((b.x or 0) == 0 and (b.y or 0) == 0 and (b.z or 0) == 0) then
          local x, y, z = S.pos.x + b.x, S.pos.y + b.y, S.pos.z + b.z
          local k = memKey(x, y, z)
          -- "handled" only once it was really checked; an unreachable one is
          -- tried again from another spot (twice), a STOP marks nothing
          if handled[k] ~= true and (handled[k] or 0) < 2 then
            local reached = approach(x, y, z)
            if reached then
              handled[k] = true
            elseif not stopFlag then
              handled[k] = (handled[k] or 0) + 1
            end
            if reached then
              local side = faceCell(x, y, z)
              local okId, id = pcall(peripheral.call, side, "getID")
              if okId and type(id) == "number" and not skipSet[id] then
                note("rescue", "found turtle " .. id .. " at " .. x .. " " .. y .. " " .. z .. " - reinstalling it")
                local ok, msg = reinstall(id, x, y, z)
                send("rescued", { target = id, mode = "install", ok = ok, msg = msg, at = { x = x, y = y, z = z } })
                skipSet[id] = true
                if ok then rescued[#rescued + 1] = id end
                saveProgress(i - 1)
                if not (slotOf(isDrive) and slotOf(isFloppy)) then
                  goHome()
                  return finish(#rescued > 0, "rescued " .. #rescued .. " turtle(s) - stopped: the Disk Drive or floppy is gone")
                end
              end
            end
          end
        end
      end
    end
    saveProgress(i)                                  -- this spot is done
  end
  if fs.exists(SWEEP_FILE) then fs.delete(SWEEP_FILE) end   -- the whole area is done
  goHome()
  return finish(true, "search done: " .. #rescued .. " lost turtle(s) found and reinstalled" ..
                      (#rescued > 0 and (" (" .. table.concat(rescued, ", ") .. ")") or ""))
end

function rescue(tid, x, y, z, mode, radius)
  if S.anchor then return false, "I am the ANCHOR - send another turtle" end
  task = "rescue: looking for turtle " .. tid
  local lx, ly, lz = locate(tid, x, y, z, radius)
  if not lx then return false, ly end
  local ok, msg, gave
  if mode == "supply" then ok, msg, gave = supply(tid, lx, ly, lz)
  else ok, msg = reinstall(tid, lx, ly, lz) end
  send("rescued", { target = tid, mode = mode, ok = ok, msg = msg, gave = gave,
                    at = { x = lx, y = ly, z = lz } })
  if ok then goHome() end
  return ok, msg
end

---------------------------------------------------------------------
-- commands
---------------------------------------------------------------------
function runJob(j)
  local a = j.args
  if S.anchor and (j.cmd == "survey" or j.cmd == "surveypts") then
    return false, "I am the ANCHOR (I keep the base loaded) - turn ANCHOR off first"
  end
  if j.cmd == "goto" or j.cmd == "home" or j.cmd == "survey" or j.cmd == "surveypts" or j.cmd == "rescue"
     or j.cmd == "sweep" then
    verifyPose()
  end
  if j.cmd == "goto" then
    local x, y, z = tonumber(a[1]), tonumber(a[2]), tonumber(a[3])
    if not (x and y and z) then return false, "usage: goto x y z" end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    return gotoPos(x, y, z)
  elseif j.cmd == "home" then
    return goHome()
  elseif j.cmd == "move" then
    local dir, n = tostring(a[1] or ""), tonumber(a[2]) or 1
    task = "move " .. dir
    for _ = 1, n do
      if stopFlag then return false, "stopped" end
      local ok
      if dir == "forward" then ok = fwd()
      elseif dir == "back" then ok = bck()
      elseif dir == "up" then ok = up()
      elseif dir == "down" then ok = down()
      elseif dir == "left" then left() ok = true
      elseif dir == "right" then right() ok = true
      else return false, "unknown direction " .. dir end
      if not ok then return false, "blocked (" .. dir .. ") at " .. fmt() end
    end
    return true, dir .. " x" .. n .. " -> " .. fmt()
  elseif j.cmd == "locate" then
    task = "GPS"
    return gpsFix()
  elseif j.cmd == "scan" then
    return scanHere(a[1])
  elseif j.cmd == "survey" then
    local x1, z1, x2, z2 = tonumber(a[1]), tonumber(a[2]), tonumber(a[3]), tonumber(a[4])
    if not (x1 and z1 and x2 and z2) then return false, "usage: survey x1 z1 x2 z2 [radius]" end
    if type(j.left) == "table" and #j.left > 0 then              -- continuing after a restart
      return surveyPoints(orderNearest(j.left), math.max(1, math.min(16, math.floor(tonumber(a[5]) or CONFIG.scanRadius))))
    end
    return survey(x1, z1, x2, z2, a[5])
  elseif j.cmd == "rescue" then
    local tid, x, y, z = tonumber(a[1]), tonumber(a[2]), tonumber(a[3]), tonumber(a[4])
    if not (tid and x and y and z) then return false, "usage: rescue <id> <x> <y> <z> [install|supply]" end
    return rescue(tid, math.floor(x), math.floor(y), math.floor(z), a[5] == "supply" and "supply" or "install",
                  tonumber(a[6]))
  elseif j.cmd == "warp" then
    return warpTo(tostring(a[1] or ""))
  elseif j.cmd == "sweep" then
    local cx, cy, cz = tonumber(a[1]), tonumber(a[2]), tonumber(a[3])
    if not (cx and cy and cz) then return false, "usage: sweep <x> <y> <z> [radius] [skip ids]" end
    return sweep(math.floor(cx), math.floor(cy), math.floor(cz), tonumber(a[4]), a[5])
  elseif j.cmd == "surveypts" then
    -- args: radius, x1, z1, x2, z2, ...  (this turtle's share of a survey)
    local r = math.max(1, math.min(16, math.floor(tonumber(a[1]) or CONFIG.scanRadius)))
    local pts = {}
    for i = 2, #a - 1, 2 do
      local x, z = tonumber(a[i]), tonumber(a[i + 1])
      if x and z then pts[#pts + 1] = { math.floor(x), math.floor(z) } end
    end
    if not known() then return false, "position/facing unknown - use GPS LOCATE" end
    if type(j.left) == "table" and #j.left > 0 then pts = j.left end     -- continuing after a restart
    return surveyPoints(orderNearest(pts), r)
  end
  if j.cmd == "core" then
    task = "checking the End Automata Core"
    coreCheck()
    return true, "End Automata Core: functions " .. table.concat(S.coreMethods or { "?" }, ", ") ..
                 (warpCore() and "" or (S.coreKeepsPoints and " - keeps its points when carried"
                  or " - FORGETS its points when carried: cannot warp"))
  end
  return false, "unknown command " .. tostring(j.cmd)
end

-- write a new program over this one (the old one is kept as startup.old)
function installUpdate(code)
  if fs.exists("startup.old") then fs.delete("startup.old") end
  if fs.exists(MYPATH) then fs.copy(MYPATH, "startup.old") end
  local targets = { MYPATH }
  if MYPATH ~= "startup.lua" and fs.exists("startup.lua") then targets[2] = "startup.lua" end
  for _, path in ipairs(targets) do
    local h = fs.open(path, "w")
    h.write(code)
    h.close()
  end
end

-- commands that answer at once (also while a job is running)
function immediate(cmd, a)
  if cmd == "upd" then
    -- a new program from the base, in pieces: { version, piece, pieces, text }.
    -- Pieces are collected also during a job; a complete update is installed
    -- at once when idle, otherwise as soon as the job is done.
    local ver, i, n = tostring(a[1]), tonumber(a[2]), tonumber(a[3])
    if not (i and n) then return nil, "quiet" end
    if UPD_READY and UPD_READY.ver == ver then return nil, "quiet" end   -- already have it
    if not UPD or UPD.ver ~= ver or UPD.n ~= n then UPD = { ver = ver, n = n, parts = {}, got = 0 } end
    UPD.last = os.clock()
    if not UPD.parts[i] then
      UPD.parts[i] = tostring(a[4] or "")
      UPD.got = UPD.got + 1
    end
    if UPD.got < UPD.n then return nil, "quiet" end
    local code = table.concat(UPD.parts)
    UPD = nil
    if codeHash(code) ~= ver then return false, "update arrived damaged - the base will send it again" end
    local fn, err = load(code, "node", "t", {})          -- compile check only, nothing runs
    if not fn then return false, "update does not compile, not installed: " .. tostring(err) end
    if job then
      UPD_READY = { ver = ver, code = code }
      return true, "update ready - installs when the current job is done"
    end
    installUpdate(code)
    rebootSoon = true
    return true, "updated - restarting"
  elseif cmd == "warpsave" then
    if job then return false, "busy: " .. tostring(task) .. " (press STOP first)" end
    local name = tostring(a[1] or "")
    if name == "" then return false, "usage: warpsave <name>" end
    return warpSave(name)
  elseif cmd == "core" then
    if not hasCore() then return false, "no End Automata Core (equipped or in the inventory)" end
    if a[1] == "check" or not S.coreMethods then return nil end   -- runs as a job (worker)
    return true, "End Automata Core " .. (warpCore() and "equipped" or "carried") .. "; " ..
                 (warpCore() and "warps" or (S.coreKeepsPoints and "keeps points - warps (swapped in)"
                  or (S.coreKeepsPoints == false and "FORGETS points when taken off - cannot warp" or "not tested"))) ..
                 "; functions: " .. table.concat(S.coreMethods or { "?" }, ", ")
  elseif cmd == "warps" then
    local o = {}
    for n, w in pairs(S.warps or {}) do o[#o + 1] = n .. " (" .. w.x .. " " .. w.y .. " " .. w.z .. ")" end
    return true, (#o > 0 and table.concat(o, ", ") or "no warp points") ..
                 (warpCore() and "" or (coreSlot() and " - End Automata Core carried (swapped in to warp)"
                                                   or " - no End Automata Core"))
  elseif cmd == "setting" then
    -- change one setting on this turtle (kept across updates): setting dig true
    local name, raw = tostring(a[1] or ""), a[2]
    if name == "" or name == "key" or name == "protocol" or name == "baseName" then
      return false, "usage: setting <name> <value>  (key/protocol/baseName cannot be changed)"
    end
    if CONFIG[name] == nil then return false, "no setting called '" .. name .. "'" end
    local v = raw
    if raw == "true" then v = true elseif raw == "false" then v = false
    elseif tonumber(raw) then v = tonumber(raw) end
    if type(v) ~= type(CONFIG[name]) then
      return false, name .. " must be a " .. type(CONFIG[name]) .. " (now: " .. tostring(CONFIG[name]) .. ")"
    end
    CONFIG[name] = v
    local t = loadSettings()
    t[name] = v
    writeFile(SETTINGS_FILE, t)
    return true, name .. " = " .. tostring(v) .. " (kept across updates)"
  elseif cmd == "know" then
    -- what the base knows: walls "x,y,z,kind,time;..", dead ends "x,y,z,time;..",
    -- the exit route "x,y,z;.." and its time
    for x, y, z, k, t in tostring(a[1] or ""):gmatch("(-?%d+),(-?%d+),(-?%d+),(%a+),(%d+)") do
      memWall(tonumber(x), tonumber(y), tonumber(z), k, "base", tonumber(t))
    end
    for x, y, z, t in tostring(a[2] or ""):gmatch("(-?%d+),(-?%d+),(-?%d+),(%d+)") do
      local k = memKey(x, y, z)
      if not DEAD[k] or DEAD[k].t < tonumber(t) then
        DEAD[k] = { x = tonumber(x), y = tonumber(y), z = tonumber(z), t = tonumber(t) }
      end
    end
    local pts = routeFromString(a[3])
    if #pts >= 2 then EXIT = { points = pts, t = tonumber(a[4]) or now() }
    elseif tostring(a[3] or "") == "none" then EXIT = nil end
    CRUISE = tonumber(a[5])                       -- nil when the map does not know the way
    knowReady = true
    return nil, "quiet"
  elseif cmd == "exitrec" then
    if not (S.pos and S.pos.x) then return false, "position unknown - use GPS LOCATE first" end
    recStart()
    S.recording = true
    return true, "recording the exit route: drive me out of the base into the open, then SAVE"
  elseif cmd == "exitsave" then
    if not S.recording then return false, "not recording - press START first" end
    S.recording = false
    local pts = compressRoute(recStop())
    if #pts < 2 then return false, "the route is too short" end
    EXIT = { points = pts, t = now() }
    send("exitroute", { route = routeToString(pts) })
    return true, "exit route saved: " .. #pts .. " corners, ends at " .. pts[#pts][1] .. " " ..
                 pts[#pts][2] .. " " .. pts[#pts][3]
  elseif cmd == "ack" then
    outboxAck(tonumber(a[1]))
    return nil, "quiet"                       -- no reply for acks
  elseif cmd == "anchor" then
    S.anchor = (tostring(a[1]) == "on")
    save()
    return true, S.anchor and "I am the ANCHOR now: I stay here and keep this chunk loaded"
                           or "not the anchor any more"
  elseif cmd == "ping" then return true, "pong"
  elseif cmd == "status" then return true, "status sent"
  elseif cmd == "stop" then
    stopFlag = true
    if S.job then S.job = nil end            -- never continue it after a reload
    save()
    os.queueEvent("node_stop")               -- wakes the STOP watcher at once
    return true, job and "stopping" or "stopped (idle)"
  elseif (cmd == "setpos" or cmd == "refuel") and job then
    -- these touch the selected slot / the position: never in the middle of a
    -- job (a scan swaps the modem using the selected slot)
    return false, "busy: " .. tostring(task) .. " (press STOP first)"
  elseif cmd == "setpos" then
    local x, y, z, f = tonumber(a[1]), tonumber(a[2]), tonumber(a[3]), FACE[tostring(a[4] or ""):lower()]
    if not (x and y and z and f) then return false, "usage: setpos x y z north|south|east|west" end
    S.pos = { x = x, y = y, z = z, f = f }
    save()
    return true, "position set to " .. fmt() .. " facing " .. FNAME[f]
  elseif cmd == "sethome" then
    local x, y, z = tonumber(a[1]), tonumber(a[2]), tonumber(a[3])
    if x and y and z then
      S.home = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
      save()
      return true, "home set to " .. S.home.x .. " " .. S.home.y .. " " .. S.home.z
    end
    gpsCheck()                                -- make sure "here" is really here
    if not (S.pos and S.pos.x) then return false, "position unknown" end
    S.home = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
    save()
    trailReset()
    local okW = select(1, warpSave("home"))
    return true, "home set to " .. fmt() .. " (here)" .. (okW and " + warp point 'home' (GO HOME teleports)" or "")
  elseif cmd == "refuel" then
    -- every slot, like before; a reusable item is used again and again (up to
    -- 10 s here - the rest it does by itself while idle)
    local before = turtle.getFuelLevel()
    local _, more = topUp(refuelTarget(), false, 200)
    local names = {}
    for n in pairs(S.reuse or {}) do names[#names + 1] = n:gsub("^.*:", "") end
    if before == "unlimited" then return true, "fuel is unlimited on this server - nothing to do" end
    local gained, uses, refused, secs = TOPUP.gained or 0, TOPUP.uses or 0, TOPUP.refused or 0, TOPUP.secs or 0
    local rate = secs > 0 and math.floor(gained / secs) or gained
    return true, "fuel " .. tostring(before) .. " -> " .. tostring(turtle.getFuelLevel()) ..
                 " (" .. uses .. " uses" .. (refused > 0 and (", refused " .. refused .. "x") or "") ..
                 ", " .. string.format("%.1f", secs) .. " s = " .. rate .. " fuel/s)" ..
                 (#names > 0 and ("; reusable fuel: " .. table.concat(names, ", ") ..
                  (more and " - it keeps filling up by itself while idle" or "")) or "")
  end
  return nil
end

function listener()
  while true do
    local id, m = rednet.receive(CONFIG.protocol)
    if type(m) == "table" and m.t == "cmd" and type(m.n) == "number"
       and m.n > (S.lastN or 0) and m.sig == sign(CONFIG.key, m.t, m.n, m.cmd, m.args) then
      S.lastN = m.n
      save()
      baseId = id
      local a = type(m.args) == "table" and m.args or {}
      local okI, ok, msg = pcall(immediate, m.cmd, a)
      if not okI then ok, msg = false, "error in '" .. tostring(m.cmd) .. "': " .. tostring(ok) end
      if ok == nil and msg == "quiet" then
        -- handled, nothing to say
      elseif ok ~= nil then
        reply(m.cmd, ok, msg)
        if rebootSoon then
          S.rebootWhy = "after an update"
          save()
          sleep(1)
          os.reboot()
        end
      elseif job then
        reply(m.cmd, false, "busy: " .. task .. " (press STOP first)")
      else
        stopFlag = false
        job = { cmd = m.cmd, args = a }
      end
    end
  end
end

-- jobs worth continuing after a restart (long trips and searches)
local RESUMABLE = { ["goto"] = true, home = true, survey = true, surveypts = true, rescue = true, sweep = true }

-- after a job was cut off by a forced STOP: put the modem back if it was
-- swapped out, free the slot locks, end a route recording, check the position
function afterForcedStop()
  STEPPING, SLOT_LOCK, TOPUP_RUNNING = false, false, false
  if not findModemSide() and (modem == "left" or modem == "right") then
    local slot = findItemLike("modem")
    if slot then
      turtle.select(slot)
      equipOn(modem)
      sleep(0.2)
    end
  end
  pcall(rednet.open, modem)
  modemAttached = findModemSide() ~= nil
  turtle.select(1)
  if not S.recording then recStop() end
  pcall(chunkyFix, modem)
  pcall(gpsCheck)
end

-- STOP watcher (runs next to a job): after a STOP the job gets 2 s to end by
-- itself; then no new move or turn may start (FORCE_STOP), and the job is cut
-- off at the next safe moment (not in the middle of a move, a turn or an
-- equipment swap). Returns true when it cut the job off.
function stopWatch()
  while not stopFlag do os.pullEvent("node_stop") end
  local t0 = os.clock()
  while os.clock() - t0 < 2 do sleep(0.1) end
  FORCE_STOP = true                          -- every next move/turn ends the job
  while true do
    local safe = not STEPPING and modemAttached and not SLOT_LOCK and not TOPUP_RUNNING
    if safe or os.clock() - t0 > 60 then return true end
    sleep(0.05)
  end
end

function worker()
  while true do
    if job then
      local j = job
      -- remember the job on disk: after a restart (server restart, chunk
      -- reload, update) the turtle continues it by itself
      if RESUMABLE[j.cmd] and not stopFlag then
        S.job = { cmd = j.cmd, args = j.args, left = j.left, resumes = j.resumes or 0 }
        save()
      end
      -- a job continued after a restart waits a few seconds first, so a STOP
      -- the base sends again (it remembers it) arrives before the first move
      if j.delay and not stopFlag then
        task = "restarted - continuing " .. j.cmd .. " in " .. j.delay .. " s"
        send("status")
        local t0 = os.clock()
        while os.clock() - t0 < j.delay and not stopFlag do sleep(0.25) end
      end
      local okRun, ok, msg
      if stopFlag then
        okRun, ok, msg = true, false, "stopped (before it started)"
      else
        local forced = false
        parallel.waitForAny(
          function() okRun, ok, msg = pcall(runJob, j) end,
          function() forced = stopWatch() end)
        if forced and okRun == nil then
          afterForcedStop()
          okRun, ok, msg = true, false, "stopped (forced) at " .. fmt()
        end
      end
      if not okRun then ok, msg = false, tostring(ok) end
      if FORCE_STOP then
        FORCE_STOP = false
        if not modemAttached or SLOT_LOCK or TOPUP_RUNNING then afterForcedStop() end
      end
      job, task = nil, "idle"
      S.job = nil                                -- finished, failed or stopped: forget it
      trailSave()
      if ok or tostring(msg):find("^stopped") then
        S.stuck = nil                         -- done, or stopped on purpose
      elseif j.cmd == "goto" or j.cmd == "home" or j.cmd == "move" or j.cmd == "survey"
             or j.cmd == "surveypts" or j.cmd == "rescue" then
        S.stuck = msg
        local fix = gpsCheck()
        if fix then msg = msg .. " (" .. fix .. ")" end
      end
      save()
      reply(j.cmd, ok and true or false, msg)
      if UPD_READY then
        -- an update arrived during the job: install it now
        installUpdate(UPD_READY.code)
        UPD_READY = nil
        send("result", { cmd = "upd", ok = true, msg = "job done - update installed, restarting" })
        S.rebootWhy = "after an update"
        save()
        sleep(1)
        os.reboot()
      end
    else
      -- idle: a core not checked yet - read its functions, test it (once)
      if not S.coreChecked and hasCore() and modemAttached then pcall(coreCheck) end
      -- idle: fill up with reusable fuel, a little at a time (stays responsive)
      local f = turtle.getFuelLevel()
      if f ~= "unlimited" and S.reuse and next(S.reuse) and f < refuelTarget() then
        local gained = topUp(refuelTarget(), true, 40)  -- about 2 s at a time
        if gained <= 0 then sleep(1) end             -- refused / nothing to use right now
      else
        sleep(0.2)
      end
    end
  end
end

function heartbeat()
  send("hello", { resumed = S.resumedNote })
  if BOOTNOTE then send("result", { cmd = "boot", ok = true, msg = BOOTNOTE }) BOOTNOTE = nil end
  do
    local side = warpCore() or (coreSlot() and "carried - swapped in for each warp")
    local n = 0
    for _ in pairs(S.warps or {}) do n = n + 1 end
    if side then
      send("result", { cmd = "warp", ok = true, msg = "End Automata Core found (" .. side .. "): " .. n ..
        " warp point(s)" .. ((S.warps and S.warps.home) and ", incl. 'home'" or " - no 'home' yet: press SET HOME at home, or GO HOME once") })
    end
  end
  if S.resumedNote then
    send("result", { cmd = "restart", ok = not CRASHED, msg = S.resumedNote })
    S.resumedNote = nil
    save()
  end
  -- the base was told: keep only the time and count (for the restart wait)
  if CRASHED then
    CRASHED = nil
    pcall(function() if fs.exists(CRASH_FILE) then
      local h = fs.open(CRASH_FILE, "r")
      local t = textutils.unserialize(h.readAll() or "") or {}
      h.close()
      t.err = nil
      writeFile(CRASH_FILE, t)
    end end)
  end
  local idleFor, sinceResend, sinceLearn = 0, 0, 0
  while true do
    sleep(CONFIG.heartbeat)
    S.alive = now()                    -- real time: how long it was off after a restart
    if not S.aliveSaved or S.alive - S.aliveSaved > 30000 then S.aliveSaved = S.alive save() end
    sinceResend = sinceResend + CONFIG.heartbeat
    sinceLearn = sinceLearn + CONFIG.heartbeat
    if not job and gearString then S.gear = gearString() end
    if sinceLearn >= CONFIG.learnEvery and modemAttached then
      sinceLearn = 0
      learnFlush()
    end
    if sinceResend >= CONFIG.resendEvery and outboxCount() > 0 and modemAttached then
      sinceResend = 0
      outboxResend()
    end
    -- an update stopped arriving: ask the base for the missing pieces
    if UPD and UPD.last and os.clock() - UPD.last > 6 and modemAttached then
      local miss = {}
      for k = 1, UPD.n do if not UPD.parts[k] then miss[#miss + 1] = k end end
      send("updmiss", { want = UPD.ver, missing = miss })
      UPD.last = os.clock()
    end
    if job then
      idleFor = 0
    else
      idleFor = idleFor + CONFIG.heartbeat
      if idleFor >= CONFIG.gpsIdle then
        idleFor = 0
        local fix = gpsCheck()
        if fix then send("result", { cmd = "gps", ok = true, msg = fix }) end
      end
    end
    send("status")
  end
end

term.clear()
term.setCursorPos(1, 1)
print("node: " .. (os.getComputerLabel() or ("Turtle " .. os.getComputerID())) ..
      "  id " .. os.getComputerID())
print("modem: " .. modem .. "   position: " .. fmt())
print("Waiting for commands from '" .. CONFIG.baseName .. "'...")
if not known() then pcall(gpsFix) end

-- a job that was running when the turtle stopped (server restart, chunk
-- reload, update): continue it - unless it keeps restarting the turtle
if type(S.job) == "table" and RESUMABLE[S.job.cmd] then
  local sj = S.job
  sj.resumes = (sj.resumes or 0) + 1
  if sj.resumes > 5 then
    print("The last job (" .. sj.cmd .. ") restarted me 5 times - not continuing it.")
    S.resumedNote = "restarted - NOT continuing '" .. sj.cmd .. "' (it was interrupted 5 times)"
    S.job = nil
  else
    job = { cmd = sj.cmd, args = sj.args or {}, left = sj.left, resumes = sj.resumes, delay = 6 }
    local what = sj.cmd
    if type(sj.left) == "table" then what = what .. " (" .. #sj.left .. " spots left)" end
    print("Continuing the interrupted job: " .. what)
    S.resumedNote = "restarted - continuing the job: " .. what
  end
  save()
end

-- why this start, and how long the turtle was off (real seconds since the
-- last heartbeat): tells a chunk unload apart from our own restarts
do
  local off = S.alive and math.floor((now() - S.alive) / 1000) or nil
  local why = S.rebootWhy or "by the game (chunk loaded again, server start or Ctrl+R)"
  BOOTNOTE = "started " .. why .. (off and (" - was off for about " .. off .. " s") or "") ..
             " - start #" .. ((S.boots or 0) + 1)
  S.boots = (S.boots or 0) + 1
  S.rebootWhy = nil
  save()
end

-- the program must never just end: an error used to leave the turtle at its
-- command prompt (offline, deaf to commands until rebooted by hand). Now the
-- error is written down, the turtle restarts itself, and the base is told.
CRASH_FILE = "node_crash"
if fs.exists(CRASH_FILE) then
  local h = fs.open(CRASH_FILE, "r")
  local t = textutils.unserialize(h.readAll() or "") or {}
  h.close()
  CRASHED = t
  S.resumedNote = (S.resumedNote and (S.resumedNote .. "; ") or "") ..
                  "restarted after an ERROR: " .. tostring(t.err)
end
local okMain, errMain = pcall(parallel.waitForAny, listener, worker, heartbeat)
if not okMain and tostring(errMain) ~= "Terminated" then
  local c = {}
  if fs.exists(CRASH_FILE) then
    local h = fs.open(CRASH_FILE, "r")
    c = textutils.unserialize(h.readAll() or "") or {}
    h.close()
  end
  local n = ((c.at and now() - c.at < 600000) and (c.n or 0) or 0) + 1   -- crashes in the last 10 min
  writeFile(CRASH_FILE, { err = tostring(errMain), at = now(), n = n })
  printError("node.lua stopped with an error:")
  printError(tostring(errMain))
  local wait = math.min(60, 5 * n)                 -- crashing again and again: wait longer
  print("Restarting in " .. wait .. " s (hold Ctrl+T to stay stopped)...")
  S.rebootWhy = "after an ERROR"
  save()
  sleep(wait)
  os.reboot()
end
