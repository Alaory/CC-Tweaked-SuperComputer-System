-- base_drones.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   PneumaticCraft drones: one drone per Drone Interface. Logs, saved places,
--   the chat allow list, player positions (overworld only), air / teleport cost,
--   travel (teleport or fly, hops when far and unloaded), pickup and drop with
--   Entity Import / Export, charging stations + parking, missions (with
--   rescue-to-Base when something fails) and submitDrone() used by every button.

---------------------------------------------------------------------
-- DRONE  (PneumaticCraft Drone Interface)  - several drones supported
---------------------------------------------------------------------
function fl(n) return math.floor(tonumber(n) or 0) end

-- "x, y, z" as whole numbers ("?" when unknown)
function fmtPos(x, y, z)
  if not x then return "?" end
  return string.format("%d, %d, %d", fl(x), fl(y), fl(z))
end

-- straight-line distance between two points
function dist3(ax, ay, az, bx, by, bz)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

-- drones -------------------------------------------------------------------
-- Every Drone Interface on the network is one drone (a drone connects to one
-- interface). Each drone keeps its own status, mission, log, destination and
-- passenger, and drones can run missions at the same time.
drones, droneOrder = {}, {}

-- logs survive restarts (CONFIG.drone.logFile), at most logMax per drone
savedLogs = {}
do
  local f = dataFile(CONFIG.drone.logFile)
  if f and fs.exists(f) then
    local h = fs.open(f, "r")
    if h then
      local t = textutils.unserialize(h.readAll() or "")
      h.close()
      if type(t) == "table" then savedLogs = t end
    end
  end
end

-- save every drone's log (also of drones that are not connected now)
function saveLogs()
  local all = {}
  for k, l in pairs(savedLogs) do all[k] = l end     -- drones not connected right now
  for k, dr in pairs(drones) do
    all[k] = dr.log
    savedLogs[k] = dr.log
  end
  local okS, text = pcall(textutils.serialize, all)
  if okS then
    local path = dataFile(CONFIG.drone.logFile, true)
    if saveFileSafe(path, text) then dropOldCopy(CONFIG.drone.logFile, path, next(all) == nil) end
  end
end

-- add a line to a drone's log (newest first) and save it
function droneLog(dr, msg)
  if not dr then return end
  local okR, real = pcall(os.date, "%d.%m %H:%M")   -- real date/time: logs span days
  table.insert(dr.log, 1, { t = textutils.formatTime(os.time(), true),
                            r = okR and real or nil, msg = msg })
  while #dr.log > (CONFIG.drone.logMax or 100) do table.remove(dr.log) end
  pcall(saveLogs)
  os.queueEvent("inv_update")
end

-- a new drone record for the Drone Interface called `key`
function newDrone(key)
  return { key = key, periph = peripheral.wrap(key),
           nick = CONFIG.drone.names and CONFIG.drone.names[key] or nil,
           dest = nil, passenger = nil,
           conn = false, pressure = nil, pos = nil, action = nil, done = nil,
           mission = nil, log = savedLogs[key] or {}, busy = false, abort = false, queue = {} }
end

-- "drone_interface_2" before "drone_interface_10"
function naturalLess(a, b)
  local pa, na = a:match("^(.-)(%d*)$")
  local pb, nb = b:match("^(.-)(%d*)$")
  if pa ~= pb then return pa < pb end
  return (tonumber(na) or -1) < (tonumber(nb) or -1)
end

-- sort the drones and name them "Drone 1", "Drone 2" ... (or their nickname)
function relabel()
  table.sort(droneOrder, naturalLess)
  for i, k in ipairs(droneOrder) do
    local dr = drones[k]
    dr.index = i
    dr.label = dr.nick or ("Drone " .. i)
  end
  if not state.drone or not drones[state.drone.key] then
    state.drone = droneOrder[1] and drones[droneOrder[1]] or nil
  end
end

-- find every Drone Interface (network names preferred; plain sides only when
-- there is no networked one, so one block is not counted twice)
scanDrones = function()
  local remote, side = candidates(DR_TYPES)
  local list = (#remote > 0) and remote or side
  local added = false
  -- once interfaces are on the network, drop entries found by a plain side
  -- name: those are the same blocks and would control the same drone twice
  if #remote > 0 then
    for _, sname in ipairs(side) do
      local old = drones[sname]
      if old and not old.busy then
        forgetDrone(sname)
        added = true
      end
    end
  end
  for _, name in ipairs(list) do
    if not drones[name] then
      local dr = newDrone(name)
      if dr.periph then
        drones[name] = dr
        droneOrder[#droneOrder + 1] = name
        added = true
      end
    end
  end
  if added then relabel() end
end

-- a Drone Interface was removed: stop its drone and forget it (the log is kept)
forgetDrone = function(name)
  local dr = drones[name]
  if not dr then return end
  savedLogs[name] = dr.log           -- comes back when the drone reconnects
  dr.abort, dr.gone = true, true
  drones[name] = nil
  for i, k in ipairs(droneOrder) do
    if k == name then table.remove(droneOrder, i) break end
  end
  if state.drone == dr then state.drone = nil end
  relabel()
end

scanDrones()
if #droneOrder > 0 then print("Drone interfaces: " .. table.concat(droneOrder, ", ")) end

-- private chat reply (sent by the chat worker, needs a Chat Box)
function chatTell(name, text)
  if not name or name == "" then return end
  state.chatOut[#state.chatOut + 1] = { name = name, text = text }
  os.queueEvent("chat_send")
end

-- who may use "$drone" in chat -----------------------------------------
function loadAccess()
  local f = CONFIG.chat.accessFile
  if fs.exists(f) then
    local h = fs.open(f, "r")
    if h then
      local t = textutils.unserialize(h.readAll() or "")
      h.close()
      if type(t) == "table" and type(t.allowed) == "table" then state.access = t end
    end
  end
end

-- save the chat allow list
function saveAccess()
  local h = fs.open(CONFIG.chat.accessFile, "w")
  if h then
    h.write(textutils.serialize(state.access))
    h.close()
  end
end

loadAccess()

-- the owner = the player on the memory card (by UUID when the game gives one)
function isOwner(uuid, name)
  if state.ownerUuid and uuid then return uuid == state.ownerUuid end
  return state.owner ~= nil and name == state.owner
end

-- allowed players are tied to their UUID the first time they use it
function isAllowed(uuid, name)
  local e = state.access.allowed[tostring(name):lower()]
  if not e then return false end
  if e.uuid and uuid and e.uuid ~= uuid then return false end
  if not e.uuid and uuid then
    e.uuid = uuid
    saveAccess()
  end
  return true
end

-- let a player use '$drone' (the UUID is tied on their first use)
function allowPlayer(name)
  state.access.allowed[name:lower()] = { name = name }
  saveAccess()
end

-- take a player off the allow list; true if they were on it
function denyPlayer(name)
  local k = name:lower()
  local had = state.access.allowed[k] ~= nil
  state.access.allowed[k] = nil
  saveAccess()
  return had
end

-- the allowed players' names, sorted
function allowedNames()
  local out = {}
  for _, e in pairs(state.access.allowed) do out[#out + 1] = e.name end
  table.sort(out)
  return out
end

-- saved places ---------------------------------------------------------
function loadWaypoints()
  local f = CONFIG.drone.waypointFile
  if fs.exists(f) then
    local h = fs.open(f, "r")
    if h then
      local txt = h.readAll()
      h.close()
      local t = textutils.unserialize(txt or "")
      if type(t) == "table" then state.waypoints = t end
    end
  end
end

-- save the saved places
function saveWaypoints()
  local h = fs.open(CONFIG.drone.waypointFile, "w")
  if h then
    h.write(textutils.serialize(state.waypoints))
    h.close()
  end
end

-- a saved place by name (any case), or nil
function findWaypoint(name)
  for _, w in ipairs(state.waypoints) do
    if w.name:lower() == tostring(name):lower() then return w end
  end
end

-- save a place (or move it if the name exists)
function addWaypoint(name, x, y, z)
  local w = findWaypoint(name)
  if w then w.x, w.y, w.z = x, y, z
  else state.waypoints[#state.waypoints + 1] = { name = name, x = x, y = y, z = z } end
  table.sort(state.waypoints, function(a, b) return a.name:lower() < b.name:lower() end)
  saveWaypoints()
end

-- delete a saved place; true if it existed
function removeWaypoint(name)
  for i, w in ipairs(state.waypoints) do
    if w.name:lower() == tostring(name):lower() then
      table.remove(state.waypoints, i)
      saveWaypoints()
      return true
    end
  end
end

loadWaypoints()
-- "Base" always follows CONFIG.drone.home (also after you change the config)
if CONFIG.drone.home then
  local h = CONFIG.drone.home
  local w = findWaypoint("Base")
  if not w or w.x ~= h.x or w.y ~= h.y or w.z ~= h.z or w.name ~= "Base" then
    if w then removeWaypoint(w.name) end
    addWaypoint("Base", h.x, h.y, h.z)
  end
end

-- sensible Minecraft coordinates? (stops typos like 1e309 or y = 9000)
function validCoords(x, y, z)
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not (x and y and z) then return false end
  if x ~= x or y ~= y or z ~= z then return false end                 -- NaN
  if math.abs(x) > 30000000 or math.abs(z) > 30000000 then return false end
  if y < -64 or y > 320 then return false end
  return true
end

-- players / destination -------------------------------------------------
function canonPlayer(name)
  for _, e in ipairs(state.players or {}) do
    if e.name:lower() == tostring(name):lower() then return e.name end
  end
  return name
end

-- drones only fly in the overworld: players / places anywhere else are refused
DRONE_DIM = "minecraft:overworld"

-- "not in the detector's dimension, name not known yet"
OTHER_DIM = "?other"

-- short name for messages: "minecraft:the_nether" -> "the nether"
function dimName(d)
  if d == OTHER_DIM then return "another dimension" end
  return (tostring(d):gsub("^.*:", ""):gsub("_", " "))
end

-- the dimension a player is in right now (nil = not known).
-- p = what the detector just returned for them (optional)
function playerDimNow(name, p)
  local d = (p and dimFromData(p)) or dimCache[name]
  if d then return d end
  -- detector reports no dimension: getPlayersInRange only finds players in the
  -- detector's own dimension -> in range = that dimension, not in range = another one
  -- (only when the full range was searched: a smaller fallback range proves nothing)
  if det then
    local set, full = playersInRangeSet()
    if set[name] then return homeDimension() end
    if full then return OTHER_DIM end
  end
end

-- live position of a player (Player Detector), only if they are in the overworld
function playerPos(name)
  if not det then return nil, "no Player Detector (needed to find players)" end
  local fn = det.getPlayer or det.getPlayerPos
  if not fn then return nil, "Detector has no getPlayer()" end
  local ok, p = pcall(fn, name)
  if ok and type(p) == "table" and p.x then
    local d = playerDimNow(name, p)
    if d and d ~= DRONE_DIM then
      return nil, tostring(name) .. " is in " .. dimName(d) .. " - drones only fly in the overworld", d
    end
    return p.x, p.y, p.z
  end
  return nil, "player '" .. tostring(name) .. "' was not found by the detector"
end

-- where a drone's destination is right now (players are looked up live)
function resolveDest(dr)
  local d = dr and (dr.mdest or dr.dest)
  if not d then return nil, "no destination chosen" end
  if d.kind == "player" then return playerPos(d.name) end
  return d.x, d.y, d.z
end

-- what kind of destination a drone has, for the screen
function destLabel(dr)
  local d = dr and dr.dest
  if not d then return "not set" end
  if d.kind == "player" then return "Player " .. d.name .. " (live)" end
  if d.kind == "waypoint" then return "Waypoint " .. d.name end
  return "Coordinates"
end

-- short form for titles: "200, 70, 200" / "Home" / "@Zed"
function destShort(dr)
  local d = dr and (dr.mdest or dr.dest)
  if not d then return "?" end
  if d.kind == "player" then return "@" .. d.name end
  if d.kind == "waypoint" then return d.name end
  return fmtPos(d.x, d.y, d.z)
end

-- position shown on screen without extra game calls (cached player list)
function destPosCached(dr)
  local d = dr and dr.dest
  if not d then return nil end
  if d.kind == "player" then
    for _, e in ipairs(state.players or {}) do
      if e.name == d.name and e.p and e.p.x then
        if e.dim and e.dim ~= DRONE_DIM then return nil end   -- not in the overworld
        return e.p.x, e.p.y, e.p.z
      end
    end
    return nil
  end
  return d.x, d.y, d.z
end

-- drone status -----------------------------------------------------------
function parsePos(t)
  if type(t) ~= "table" then return nil end
  local x, y, z = t[1] or t.x, t[2] or t.y, t[3] or t.z
  if x and y and z then return tonumber(x), tonumber(y), tonumber(z) end
end

-- read one drone's status (connected, air, position, action) all at once
function refreshDrone(dr)
  local d = dr.periph
  local r = {}
  parallel.waitForAll(
    function() local ok, v = pcall(d.isConnectedToDrone); r.conn = ok and v and true or false end,
    function() local ok, v = pcall(d.getDronePressure); if ok then r.pressure = tonumber(v) end end,
    function()
      local ok, a, b, c = pcall(d.getDronePosition)   -- returns x, y, z
      if ok then r.pos = (type(a) == "number") and { a, b, c } or a end
    end,
    function() local ok, v = pcall(d.getAction); if ok then r.action = v end end,
    function() local ok, v = pcall(d.isActionDone); if ok then r.done = v end end)
  dr.conn = r.conn
  dr.pressure = r.conn and r.pressure or nil
  local x, y, z = parsePos(r.pos)
  dr.pos = (r.conn and x) and { x = x, y = y, z = z } or nil
  dr.action = r.conn and r.action or nil
  dr.done = r.done
end

-- status of every drone, all at once
function refreshDrones()
  local list = {}
  for _, k in ipairs(droneOrder) do list[#list + 1] = drones[k] end
  pmap(list, function(dr) refreshDrone(dr) end)
  state.t.drone = os.clock()
end

-- missions ---------------------------------------------------------------
-- "inventory.lua:1604: Unknown area type" -> "Unknown area type"
function cleanErr(e)
  return (tostring(e):gsub("^[^:]*:%d+: ", ""))
end

-- Runs one action on one drone and waits until it is done.  returns ok, errorText
function droneDo(dr, action, setup, minTime, limit)
  local d = dr.periph
  if not d or dr.gone then return false, "Drone Interface disconnected" end
  local okS, errS = pcall(setup)
  if not okS then return false, cleanErr(errS) end
  local ok, err = pcall(d.setAction, action)
  if not ok then return false, cleanErr(err) end

  local t0 = os.clock()
  while true do
    waitFor(0.3, "drone_abort")
    if dr.abort then pcall(d.abortAction); return false, "stopped" end
    local okC, conn = pcall(d.isConnectedToDrone)
    if not okC or not conn then return false, "the drone disconnected" end
    local okD, done = pcall(d.isActionDone)
    if okD and done and os.clock() - t0 > (minTime or 0.6) then return true end
    if os.clock() - t0 > (limit or CONFIG.drone.stepTimeout) then
      pcall(d.abortAction)
      return false, "timed out"
    end
  end
end

-- Always start a new area with clearArea(), then add the exact block.
function areaPoint(dr, x, y, z)
  dr.periph.clearArea()
  dr.periph.addArea(fl(x), fl(y), fl(z))
end

-- how the drone travels: "teleport" (no pathfinding, never gets lost in an
-- underground base) or "fly" (CONFIG.drone.travel)
function travelAction()
  return (CONFIG.drone.travel == "fly") and "pneumaticcraft:goto" or "pneumaticcraft:teleport"
end

-- one move to x y z. Done = the drone IS there (checked by its real position).
-- A teleport to a spot that is not free never happens - PneumaticCraft then
-- keeps retrying forever - so every attempt has a short time limit.
-- least air a drone needs to take a ride (teleports: to the player, to the
-- destination, home - about 3 x 0.85 bar - plus the reserve)
function rideMinPressure()
  if CONFIG.drone.travel ~= "fly" then
    return math.max(CONFIG.drone.minPressure, CONFIG.drone.rideMinTeleport or 4)
  end
  return CONFIG.drone.minPressure
end

-- the drone's air right now (bar)
function dronePressure(dr)
  local okP, p = pcall(dr.periph.getDronePressure)
  if okP and type(p) == "number" then dr.pressure = p return p end
  return dr.pressure
end
-- one teleport's cost in bar for this drone (measured; Volume Upgrades lower it)
function teleportCost(dr) return dr.tpCost or CONFIG.drone.teleportCost or 0.85 end
-- enough air for one more teleport, keeping the reserve?
function canTeleport(dr, extra)
  local p = dronePressure(dr)
  if not p then return true end
  return p >= teleportCost(dr) * (1 + (extra or 0)) + (CONFIG.drone.airReserve or 1.5)
end

-- WHO IS ON BOARD - asked the DRONE itself (PneumaticCraft's "drone_condition_entity":
-- counts the drone's real passengers that match the name filter; evaluateCondition
-- answers true / false). name = nil: anybody. Returns true / false, or nil when this
-- drone / version cannot answer (then the old position checks are used).
-- Sets the drone's action: only call it while no move / grab is running.
function droneCarries(dr, name)
  local d = dr.periph
  if not (d and d.evaluateCondition and d.setOperator and d.setCount) or dr.condBroken then return nil end
  local ok, r = pcall(function()
    d.clearWhitelistText()
    d.clearBlacklistText()
    if name then d.addWhitelistText('"' .. name .. '"') end   -- (quoted = a player's NAME)
    d.setOperator(">=")                                       -- (empty by default: must be set)
    d.setCount(1)
    d.setAction("pneumaticcraft:drone_condition_entity")
    return d.evaluateCondition()
  end)
  pcall(d.clearWhitelistText)
  if ok and type(r) == "boolean" then dr.condOK = true return r end
  if not dr.condOK then
    dr.condBroken = true
    droneLog(dr, "This drone cannot say who is on board (" .. cleanErr(r) .. ") - checking by positions instead")
  end
  return nil
end

-- the passenger (dr.rider) is still with the drone? Checked every 2 s while
-- moving; twice in a row more than 12 blocks apart = they got off. Unknown
-- positions never count as "got off".
function riderLeft(dr)
  if not dr.rider then return false end
  if dr.condOK then return false end           -- (the drone answers before every move instead)
  if dr.riderCheck and os.clock() - dr.riderCheck < 2 then return false end
  dr.riderCheck = os.clock()
  return riderGoneNow(dr)
end
-- checked NOW (before every move with a passenger - before, a long trip made a
-- few more 160-block hops into unloaded land after you got off, and got lost):
-- logged off = gone; more than 12 blocks from the drone, read twice 0.5 s apart
-- (one late detector reading is not enough) = gone. Unknown = not gone.
function riderGoneNow(dr)
  local name = dr.rider
  if not name then return false end
  -- the drone itself knows (the Player Detector can lag behind a teleport: "got
  -- off" while you hung under it -> it flew you back home)
  local c = droneCarries(dr, name)
  if c == true then return false end
  if c == false then droneLog(dr, name .. " is not on board any more") return true end
  if det and det.getOnlinePlayers then
    local ok, list = pcall(det.getOnlinePlayers)
    if ok and type(list) == "table" then                 -- (empty = nobody online: you were the last one)
      local on = false
      for _, n in ipairs(list) do if tostring(n):lower() == name:lower() then on = true end end
      if not on then droneLog(dr, name .. " logged off during the ride") return true end
    end
  end
  for try = 1, 2 do
    local px, py, pz = playerPos(name)
    local dx, dy, dz = droneXYZ(dr)
    if type(px) ~= "number" or not dx then return false end
    if math.abs(px - dx) <= 12 and math.abs(pz - dz) <= 12 and math.abs(py - dy) <= 12 then return false end
    if try == 1 then waitFor(0.5, "drone_abort") end
  end
  return true
end

-- teleport or fly one drone to x y z and wait; returns ok, error
-- (measures the real air cost of a teleport)
function droneMoveTo(dr, action, x, y, z, limit)
  local d = dr.periph
  if not d or dr.gone then return false, "Drone Interface disconnected" end
  local isTp = action == "pneumaticcraft:teleport"
  -- a passenger on board: still with me? Never go on (into unloaded land) without them
  if dr.rider and riderGoneNow(dr) then return false, "passenger got off" end
  if isTp and not canTeleport(dr) then return false, "low on air" end
  local pBefore = isTp and dronePressure(dr) or nil
  local okS, errS = pcall(areaPoint, dr, x, y, z)
  if not okS then return false, cleanErr(errS) end
  local ok, err = pcall(d.setAction, action)
  if not ok then return false, cleanErr(err) end
  local t0 = os.clock()
  while true do
    waitFor(0.3, "drone_abort")
    if dr.abort then pcall(d.abortAction); return false, "stopped" end
    local okC, conn = pcall(d.isConnectedToDrone)
    if not okC or not conn then return false, "the drone disconnected" end
    if riderLeft(dr) then pcall(d.abortAction); return false, "passenger got off" end
    local okP, a, b, c = pcall(d.getDronePosition)
    local px, py, pz
    if okP then px, py, pz = parsePos((type(a) == "number") and { a, b, c } or a) end
    local near = px and math.abs(px - (x + 0.5)) <= 2.5 and math.abs(py - (y + 0.5)) <= 2.5
                 and math.abs(pz - (z + 0.5)) <= 2.5
    local t = os.clock() - t0
    if near and t > 0.6 then
      if pBefore then
        local pAfter = dronePressure(dr)
        local used = pAfter and (pBefore - pAfter)
        if used and used > 0.05 and used < 5 then dr.tpCost = used end   -- what a teleport really costs
      end
      return true
    end
    local okD, done = pcall(d.isActionDone)
    if okD and done and t > 0.6 and not px then return true end   -- position unknown: trust it
    if t > limit then
      pcall(d.abortAction)
      return false, "did not get there"
    end
  end
end

-- free spots to try, around the wanted one (it may be inside a block)
local SPOTS = { { 0, 0, 0 }, { 0, 1, 0 }, { 0, 2, 0 }, { 1, 1, 0 }, { -1, 1, 0 },
                { 0, 1, 1 }, { 0, 1, -1 }, { 0, 4, 0 } }

-- landing spots for a PICKUP, relative to the player: all within 1.5 blocks,
-- so Entity Import grabs right away and never has to fly to the player.
-- The configured side first, then the other sides at foot and head height.
function pickupSpots()
  -- NOT right beside the player: a drone teleported in 1 block next to you lands
  -- against you and PUSHES you. Above your head first (3 up: clear of you), then
  -- 2 blocks to a side at head height, then at foot height; Entity Import flies
  -- the last bit down to you by itself.
  local dx, dz = CONFIG.drone.approachDX or 1, CONFIG.drone.approachDZ or 0
  dx, dz = (dx > 0 and 1) or (dx < 0 and -1) or 0, (dz > 0 and 1) or (dz < 0 and -1) or 0
  local list, seen = {}, {}
  local function add(a, b, c)
    local k = a .. "," .. b .. "," .. c
    if not seen[k] then seen[k] = true list[#list + 1] = { a, b, c } end
  end
  add(0, 3, 0)
  if dx ~= 0 or dz ~= 0 then add(dx * 2, 1, dz * 2) end
  for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do add(d[1], 1, d[2]) end
  for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do add(d[1], 0, d[2]) end
  return list
end

-- go to x y z the configured way; if the spot is blocked, try spots nearby,
-- and when teleporting fails everywhere, try flying once
-- Far away and not loaded (nobody there): a drone can only teleport into
-- loaded chunks. With a passenger it hops in steps the passenger's own view
-- distance has loaded, high above the terrain.
function droneXYZ(dr)
  local okP, a, b, c = pcall(dr.periph.getDronePosition)
  if not okP then return nil end
  return parsePos((type(a) == "number") and { a, b, c } or a)
end
-- far + not loaded: teleport in hops high above the terrain until close
local function hopTowards(dr, x, z)
  local L, hy = CONFIG.drone.hopLength or 160, CONFIG.drone.hopY or 200
  local minL = 48
  local logged = false
  dr.flyNote = nil
  for _ = 1, 400 do
    if dr.abort then return false, "stopped" end
    local px, _, pz = droneXYZ(dr)
    if not px then return false, "the drone's position is unknown" end
    local dx, dz = x - px, z - pz
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist <= L then return true end
    if not logged then
      logged = true
      droneLog(dr, "Far away and not loaded: hopping there in steps of " .. L .. " blocks (" ..
                   math.floor(dist) .. " to go)")
    end
    local hx, hz = math.floor(px + dx / dist * L), math.floor(pz + dz / dist * L)
    local ok
    -- teleport while there is air to spare (keep enough for the rest of the
    -- ride: release + way home), otherwise FLY this stretch (costs no air)
    local err, retry
    if canTeleport(dr, 2) then
      ok, err = droneMoveTo(dr, "pneumaticcraft:teleport", hx, hy, hz, CONFIG.drone.travelTimeout)
      if not ok and err ~= "did not get there" then return false, err end   -- stopped / got off / gone
      -- that far ahead is not loaded: try shorter hops before flying
      if not ok and L > minL then
        L = math.max(minL, math.floor(L / 2))
        droneLog(dr, "Hop not possible (not loaded that far ahead) - trying hops of " .. L .. " blocks")
        retry = true
      end
    end
    if not ok and not retry then
      if not dr.flyNote then
        dr.flyNote = true
        droneLog(dr, string.format("Flying the next stretches (air %.1f bar - teleports cost about %.1f each)",
                                   dronePressure(dr) or 0, teleportCost(dr)))
      end
      ok, err = droneMoveTo(dr, "pneumaticcraft:goto", hx, hy, hz, math.max(60, L))
      if not ok and err ~= "did not get there" then return false, err end
      if not ok then return false, "cannot get further - the area ahead is not loaded" end
    end
  end
  return false, "too many hops"
end

-- open sky above x y z? From the base's map (turtle scans): the highest block
-- of that column is not above the target. nil = the map does not know.
function skyOpenAbove(x, y, z)
  if not MAP or not MAP.get then return nil end
  local top = MAP.get(math.floor(x), math.floor(z))
  if not top then return nil end
  return y >= top + 1, top
end

-- the exact spot was refused (blocked / tight): with open sky above it,
-- teleport ONCE into the air above (always free) and fly down - flying costs
-- no air. Under a roof or underground this is never tried.
function skyApproach(dr, x, y, z)
  local open, top = skyOpenAbove(x, y, z)
  if not open then return false end
  local sy = math.min(300, math.max(y + 12, top + 8))
  droneLog(dr, "Spot " .. x .. ", " .. y .. ", " .. z .. " refused - open sky above it: teleporting to Y " .. sy ..
               " and flying down")
  local ok, err = droneMoveTo(dr, "pneumaticcraft:teleport", x, sy, z, CONFIG.drone.travelTimeout)
  if not ok then return false, err end
  ok, err = droneMoveTo(dr, "pneumaticcraft:goto", x, y, z, 40)
  if ok then dr.lastSpot = { x = x, y = y, z = z } end
  return ok, err
end

-- loaded = true: the target is next to a player (players keep their own area
-- loaded), so a refused teleport means a blocked spot, never "not loaded"
function travelTo(dr, x, y, z, spots, noFly, loaded)
  dr.lastSpot = nil
  local act = travelAction()
  local SPOTS = spots or SPOTS
  -- not enough air for a teleport (+ reserve): fly - flying costs no air
  if act ~= "pneumaticcraft:goto" and not canTeleport(dr) then
    droneLog(dr, string.format("Low on air (%.1f bar): flying instead of teleporting", dronePressure(dr) or 0))
    act = "pneumaticcraft:goto"
  end
  -- far away: try straight there once; if that area is not loaded, hop
  if act ~= "pneumaticcraft:goto" and not loaded then
    local px, _, pz = droneXYZ(dr)
    if px and math.abs(x - px) + math.abs(z - pz) > (CONFIG.drone.hopLength or 160) * 1.5 then
      local f = SPOTS[1]
      local ok, err = droneMoveTo(dr, act, x + f[1], y + f[2], z + f[3], CONFIG.drone.travelTimeout)
      if ok then
        dr.lastSpot = { x = x + f[1], y = y + f[2], z = z + f[3] }
        return true
      end
      if err ~= "did not get there" then return false, err end
      -- refused: blocked (a cave, a turtle in the way) or not loaded? The air
      -- high above the spot is always free, so a teleport there tells which:
      -- it works = loaded (the spot was just blocked) -> carry on from up
      -- there; it fails = not loaded -> hop as before
      local above = false
      if not noFly and canTeleport(dr, 2) then
        local _, top = skyOpenAbove(x, y, z)
        local sy = math.min(300, math.max(y + 12, (top or 0) + 8, top and 0 or (CONFIG.drone.hopY or 200)))
        droneLog(dr, "Could not teleport straight to " .. (x + f[1]) .. ", " .. (y + f[2]) .. ", " .. (z + f[3]) ..
                     " - trying the air above it (Y " .. sy .. ")")
        local okA, errA = droneMoveTo(dr, "pneumaticcraft:teleport", x, sy, z, CONFIG.drone.travelTimeout)
        if not okA and errA ~= "did not get there" then return false, errA end
        above = okA
        if okA then droneLog(dr, "Above the spot - the area is loaded, the spot itself was blocked") end
      end
      if not above then
        local okH, errH = hopTowards(dr, x, z)
        if not okH then return false, errH end
      end
    end
  end
  local limit = (act == "pneumaticcraft:goto") and CONFIG.drone.stepTimeout or CONFIG.drone.travelTimeout
  local lastErr
  for i, o in ipairs(SPOTS) do
    if i == 2 and act ~= "pneumaticcraft:goto" then
      local f = SPOTS[1]
      droneLog(dr, "Could not teleport to " .. (x + f[1]) .. ", " .. (y + f[2]) .. ", " .. (z + f[3]) ..
                   " (blocked or not loaded) - trying spots nearby")
    end
    local ok, err = droneMoveTo(dr, act, x + o[1], y + o[2], z + o[3], limit)
    -- the first spot refused: open sky above it? one teleport up + fly down
    -- instead of trying the spots around it (each try costs air)
    if not ok and i == 1 and err == "did not get there" and act ~= "pneumaticcraft:goto" and not noFly then
      local okS, errS = skyApproach(dr, x + o[1], y + o[2], z + o[3])
      if okS then return true end
      if errS and errS ~= "did not get there" then return false, errS end   -- stopped / got off / gone
    end
    if err == "low on air" then
      droneLog(dr, "Low on air after failed teleports - flying the rest")
      act = "pneumaticcraft:goto"
      ok, err = droneMoveTo(dr, act, x + o[1], y + o[2], z + o[3], CONFIG.drone.stepTimeout)
    end
    if ok then
      dr.lastSpot = { x = x + o[1], y = y + o[2], z = z + o[3] }   -- where it really is
      if i > 1 then
        local f = SPOTS[1]
        droneLog(dr, "Spot " .. (x + f[1]) .. ", " .. (y + f[2]) .. ", " .. (z + f[3]) .. " was blocked - used " ..
                     (x + o[1]) .. ", " .. (y + o[2]) .. ", " .. (z + o[3]))
      end
      return true
    end
    if err ~= "did not get there" then return false, err end   -- stopped / disconnected
    lastErr = err
    if act == "pneumaticcraft:goto" then break end             -- flying: no point retrying spots
  end
  if act ~= "pneumaticcraft:goto" and not noFly then
    droneLog(dr, "No spot near " .. x .. ", " .. y .. ", " .. z .. " could be teleported to (the area is " ..
                 "probably not loaded) - FLYING there instead")
    local ok, err = droneMoveTo(dr, "pneumaticcraft:goto", x, y, z, CONFIG.drone.stepTimeout)
    if ok then dr.lastSpot = { x = x, y = y, z = z } return true end
    if err ~= "did not get there" then return false, err end
    lastErr = err
    -- underground (a cave, a turtle stuck in rock): the ground right above it
    -- is the closest a drone can get - land there
    local open, top = skyOpenAbove(x, y, z)
    if open == false and top then
      droneLog(dr, "The spot is under ground (surface at Y " .. top .. ") - landing on the surface right above it")
      for _, o in ipairs({ { 0, 1, 0 }, { 0, 2, 0 }, { 1, 1, 0 }, { -1, 1, 0 }, { 0, 1, 1 }, { 0, 1, -1 } }) do
        local okS, errS = droneMoveTo(dr, act, x + o[1], top + o[2], z + o[3], CONFIG.drone.travelTimeout)
        if okS then
          dr.lastSpot = { x = x + o[1], y = top + o[2], z = z + o[3] }
          droneLog(dr, "Landed above the spot: " .. math.max(0, top + 1 - y) ..
                       " blocks above it - dig down from here")
          return true
        end
        if errS == "low on air" then break end
        if errS ~= "did not get there" then return false, errS end
      end
    end
  end
  return false, "could not reach " .. x .. ", " .. y .. ", " .. z .. " (" .. tostring(lastErr) .. ")"
end

-- a mission step: travel to the position getPos() gives when the step runs
function stepGoto(dr, text, getPos, yOff, loaded)
  return { text = text, fn = function()
    local x, y, z = getPos()
    if not x then return false, y end
    local isLoaded = loaded
    if type(loaded) == "function" then isLoaded = loaded() end
    return travelTo(dr, x, y + (yOff or 0), z, nil, nil, isLoaded)
  end }
end

-- other overworld players within r blocks of x y z (not `name`): { {name, d}, ... }
function playersNear(name, x, y, z, r)
  local out = {}
  if not det or not det.getOnlinePlayers then return out end
  local ok, list = pcall(det.getOnlinePlayers)
  if not ok or type(list) ~= "table" then return out end
  for _, n in pairs(list) do
    if type(n) == "string" and n:lower() ~= tostring(name):lower() then
      local px, py, pz = playerPos(n)
      if type(px) == "number" then
        local d = math.max(math.abs(px - x), math.abs(pz - z), math.abs(py - y))
        if d <= r then out[#out + 1] = { n, d } end
      end
    end
  end
  return out
end
-- the drone may have grabbed someone else: let go of whatever it carries,
-- right where it is (they are put down where they were picked up)
function letGoHere(dr, why, gx, gy, gz)
  local x, y, z = droneXYZ(dr)
  if gx then x, y, z = gx, gy, gz end            -- (lifted: put them down where they were picked up)
  if not x then return end
  droneLog(dr, why .. " - letting go of everything here")
  pcall(releaseAt, dr, fl(x), fl(y), fl(z))
end

-- Pick a player up (matches PneumaticCraft's own code):
--   clearArea(); addArea(player x, y, z)
--   filter = "Name" IN QUOTES - without quotes PneumaticCraft matches the
--   entity TYPE (zombie, player, ...) instead of a player's name
--   entity_import: the drone flies to the player by itself and grabs them;
--   isActionDone() becomes true when it is finished
-- Then lift off: if the player came along they are on board.
-- If a try fails, the next one first flies the drone right beside the player.
function pickupSteps(dr, name)
  return { { text = "Pick up " .. name, fn = function()
    local d = dr.periph
    local lastErr = "not picked up"
    for attempt = 1, CONFIG.drone.pickupTries do
      local x, y, z = playerPos(name)
      if not x then return false, y end

      -- already close (Entity Import flies the last bit itself): no teleport next to
      -- the player - that cost air and landed the drone against them
      local cdx, cdy, cdz = droneXYZ(dr)
      local close = cdx and math.abs(cdx - x) <= 12 and math.abs(cdz - z) <= 12 and math.abs(cdy - y) <= 8
      if (attempt > 1 or CONFIG.drone.travel ~= "fly") and not (close and attempt == 1) then
        droneLog(dr, "Attempt " .. attempt .. ": " ..
                     (CONFIG.drone.travel == "fly" and "flying" or "teleporting") .. " next to " .. name)
        -- no flying fallback here: Entity Import flies the last bit itself, and
        -- where no spot is allowed (water without a Security Upgrade) flying fails too
        local okA, errA = travelTo(dr, x, y, z, pickupSpots(), true, true)
        if not okA then
          -- every spot around the player was refused: usually water (a drone
          -- may only enter liquids with a Security Upgrade) or a very tight space
          if tostring(errA):find("could not reach", 1, true) then
            errA = "could not get next to " .. name .. " - in water? The drone needs a Security Upgrade " ..
                   "for that. In a tight space? Step into a bigger opening."
            droneLog(dr, errA)
          end
          return false, errA
        end
        x, y, z = playerPos(name)
        if not x then return false, y end
      end

      -- another player right next to them: the drone could take the wrong one
      local close = playersNear(name, x, y, z, 4)
      if #close > 0 then
        return false, close[1][1] .. " is right next to " .. name .. " - the drone could take the wrong player. " ..
                      "Step a few blocks apart, then ask again."
      end
      droneLog(dr, "Attempt " .. attempt .. ": Entity Import at " .. fmtPos(x, y, z))
      local ok, err = droneDo(dr, "pneumaticcraft:entity_import", function()
        areaPoint(dr, x, y, z)
        d.clearWhitelistText()
        d.clearBlacklistText()
        d.addWhitelistText('"' .. name .. '"')
        pcall(d.setUseCount, false)
      end, 1)
      if not ok then
        if err == "stopped" or err == "the drone disconnected" then return false, err end
        lastErr = err
        droneLog(dr, "Entity Import: " .. tostring(err))
      end
      -- did it take the RIGHT player? (the drone must be with them now)
      local wrong
      local py0, dy0                             -- player + drone height right after the grab
      if ok then
        local dx, dy, dz = droneXYZ(dr)
        local qx, qy, qz = playerPos(name)
        py0, dy0 = qy, dy
        if dx and type(qx) == "number" and
           (math.abs(qx - dx) > 5 or math.abs(qz - dz) > 5 or math.abs(qy - dy) > 6) then
          local who = playersNear(name, dx, dy, dz, 3)
          wrong = who[1] and who[1][1] or "nobody"
          letGoHere(dr, "Took " .. wrong .. " instead of " .. name)
          if wrong ~= "nobody" then
            setPopup(dr.label .. " TOOK THE WRONG PLAYER", "It was sent for " .. name .. " but took " .. wrong ..
                     " - it let go of them again at once. See the drone's log.", C.bad)
            return false, "the drone took " .. wrong .. " instead of " .. name .. " (let go again at once). " ..
                          "Its name filter did not work - tell the base owner"
          end
          ok, err = false, name .. " was not picked up"
          lastErr = err
        end
      end
      -- ASK THE DRONE who it carries now (no guessing from positions)
      if ok then
        local c = droneCarries(dr, name)
        if c == true then
          droneLog(dr, name .. " is on board (the drone says so)")
          dr.rider = name
          return true
        elseif c == false then
          local other = droneCarries(dr, nil)
          if other then
            letGoHere(dr, "Carrying someone else, not " .. name, x, y, z)
            lastErr = "it grabbed someone else (let go again)"
          else
            lastErr = name .. " was not picked up"
          end
          droneLog(dr, "Attempt " .. attempt .. ": " .. lastErr)
          ok = false
        end
      end
      if not ok then
        -- (nothing more to do this attempt)
      else
        -- on board? The drone is right next to them after ANY import (it went there
        -- to pick them up), so being close proves nothing. LIFT them a few blocks by
        -- FLYING (costs no air, also in teleport mode): they rise with it = on board.
        -- (a move counts as there within 2.5 blocks: the lift must be higher than that)
        local lift = math.max(4, CONFIG.drone.liftHeight or 4)
        local okL, errL = droneMoveTo(dr, "pneumaticcraft:goto", x, y + lift, z, 8)
        if errL == "stopped" or errL == "the drone disconnected" then return false, errL end
        if not okL then
          -- no room to lift (a roof): checked on arrival instead (as before)
          droneLog(dr, "Could not lift (" .. tostring(errL) .. ") - checking on arrival that " .. name .. " came along")
          dr.checkAboard = name
          dr.rider = name
          return true
        end
        -- they rose WITH it = on board. Measured against the drone's own climb from
        -- right after the grab: a carried player hangs UNDER the drone and a move
        -- counts as there within 2.5 blocks - "2 blocks above the pickup spot"
        -- failed for a real passenger (let out, the drone flew home without them).
        -- Looked at every 0.3 s for 3 s, goes on at once.
        local aboard = false
        for _ = 1, 10 do
          if dr.abort then return false, "stopped" end
          local _, qy = playerPos(name)
          local _, ddy = droneXYZ(dr)
          if type(qy) == "number" and type(py0) == "number" and ddy and dy0 then
            local droneUp, playerUp = ddy - dy0, qy - py0
            if droneUp >= 1 and playerUp >= droneUp - 1 and playerUp >= 1 then aboard = true break end
          end
          waitFor(0.3, "drone_abort")
        end
        if dr.abort then return false, "stopped" end
        if aboard then
          droneLog(dr, name .. " is on board (lifted)")
          dr.rider = name
          return true
        end
        lastErr = name .. " did not come along"
        droneLog(dr, "Attempt " .. attempt .. ": " .. lastErr .. " - trying again")
        -- someone else may be on board: never carry them along to the next try
        letGoHere(dr, "Not the right passenger on board", x, y, z)
      end
      if dr.abort then return false, "stopped" end
    end
    return false, name .. " could not be picked up after " .. CONFIG.drone.pickupTries ..
                  " tries (" .. lastErr .. "). If the drone is already carrying " ..
                  "something it cannot pick up more - use DROP first."
  end } }
end

-- Deliver: fly to the destination, then Entity Export at that same block.
-- For a player destination the drone stops 2 blocks beside them, so it does
-- not fly into (and push) them.
function dropTarget(dr)
  local x, y, z = resolveDest(dr)
  if not x then return nil, y end
  local md = dr.mdest or dr.dest
  if md and md.kind == "player" then x = x + 2 end
  return x, y, z
end

-- let the passenger go at x y z (Entity Export), with a time limit.
-- Entity Export reports "done" also when it did nothing - so the drone is ASKED
-- afterwards whether it still carries them; if so: again (also one block higher,
-- then where the drone is). Before, a release that did nothing was taken as done
-- and the drone flew home - WITH you.
function releaseAt(dr, x, y, z)
  local spots = { { x, y, z }, { x, y + 1, z } }
  local cx, cy, cz = droneXYZ(dr)
  if cx then spots[#spots + 1] = { fl(cx), fl(cy), fl(cz) } end
  local lastErr
  for i, p in ipairs(spots) do
    local ok, err = droneDo(dr, "pneumaticcraft:entity_export", function()
      areaPoint(dr, p[1], p[2], p[3])
      dr.periph.clearWhitelistText()
      dr.periph.clearBlacklistText()
      pcall(dr.periph.setUseCount, false)
    end, 1, 40)
    if not ok and (err == "stopped" or err == "the drone disconnected") then return false, err end
    lastErr = err
    local still = droneCarries(dr, nil)
    if ok and still ~= true then
      droneLog(dr, "Released at " .. fmtPos(p[1], p[2], p[3]) .. (still == false and " (the drone carries nobody now)" or ""))
      dr.rider = nil
      return true
    end
    if still == true then
      lastErr = "still on board after letting go"
      droneLog(dr, "Let go at " .. fmtPos(p[1], p[2], p[3]) .. " but " .. tostring(dr.rider or "the passenger") ..
                   " is still on board - trying again" .. (i < #spots and "" or ""))
    end
  end
  return false, "could not let " .. tostring(dr.rider or "the passenger") .. " off (" .. tostring(lastErr) .. ")"
end

-- something failed with a passenger on board: bring them back to Base
function rescueToBase(dr)
  local h = CONFIG.drone.home
  if not h then return false, "no base set" end
  local ok, err = travelTo(dr, h.x, h.y, h.z)
  if not ok and err == "passenger got off" then
    -- they got off on the way: nobody to release, just bring the drone home
    droneLog(dr, tostring(dr.rider) .. " got off during the ride back")
    dr.rider = nil
    return travelTo(dr, h.x, h.y, h.z)
  end
  if not ok then return false, err end
  local s = dr.lastSpot or { x = h.x, y = h.y, z = h.z }
  return releaseAt(dr, s.x, s.y, s.z)
end

-- is the passenger really here with the drone? (only after a pickup without lift)
function passengerHere(dr)
  local name = dr.checkAboard
  if not name or not dr.lastSpot then return true end
  waitFor(0.5, "drone_abort")
  local px, py, pz = playerPos(name)
  if type(px) ~= "number" then return true end          -- unknown: do not block the ride
  local s = dr.lastSpot
  return math.abs(px - s.x) <= 4 and math.abs(pz - s.z) <= 4 and math.abs(py - s.y) <= 5
end

-- the mission steps to fly to the destination and let the passenger go
function dropSteps(dr, who)
  local fly = stepGoto(dr, "Fly to destination", function() return dropTarget(dr) end, 0,
                       function() local md = dr.mdest or dr.dest return md and md.kind == "player" end)
  local flyFn = fly.fn
  fly.fn = function()
    local ok, err = flyFn()
    if not ok then return false, err end
    if not passengerHere(dr) then
      dr.notAboard = true
      return false, dr.checkAboard .. " did not come along (the pickup failed) - please ask again"
    end
    return true
  end
  return {
    fly,
    { text = "Release " .. (who ~= "" and who or "passenger"), fn = function()
      -- release where the drone really arrived (the wanted spot may be blocked)
      local x, y, z
      if dr.lastSpot then x, y, z = dr.lastSpot.x, dr.lastSpot.y, dr.lastSpot.z
      else x, y, z = dropTarget(dr) end
      if not x then return false, y end
      return releaseAt(dr, x, y, z)
    end },
  }
end

-- Charging stations: one per drone ([interface name] = {x, y, z}); the one in
-- CONFIG.drone.charger goes to the first drone that has no own station.
ownChargers = {}
-- the charger exactly as written in base_config.lua (to notice when it is changed)
CONFIG_CHARGER = CONFIG.drone.charger and { x = CONFIG.drone.charger.x, y = CONFIG.drone.charger.y,
                                             z = CONFIG.drone.charger.z } or nil
do
  local f = CONFIG.drone.chargerFile
  if f and fs.exists(f) then
    local h = fs.open(f, "r")
    if h then
      local t = textutils.unserialize(h.readAll() or "")
      h.close()
      if type(t) == "table" then
        -- the charger in base_config.lua wins if it was CHANGED since the
        -- file was saved (otherwise the value set with "charger" is used)
        local cfg = CONFIG.drone.charger
        local function same(a, b)
          if not a or not b then return a == b end
          return a.x == b.x and a.y == b.y and a.z == b.z
        end
        local cfgChanged = t.cfgSeen == nil or not same(t.cfgSeen.x and t.cfgSeen or nil, cfg)
        if cfgChanged and cfg and cfg.x then
          ownChargers = {}
          chargerNote = "Charging Station from base_config.lua: " .. cfg.x .. ", " .. cfg.y .. ", " .. cfg.z
        else
          if t.x then CONFIG.drone.charger = t                     -- old file format
          elseif t.off then CONFIG.drone.charger = nil end
          if type(t.default) == "table" then
            CONFIG.drone.charger = t.default.x and t.default or nil
          end
          if type(t.drones) == "table" then ownChargers = t.drones end
        end
      end
    end
  end
end

-- save the charging stations
function saveChargers()
  local h = fs.open(CONFIG.drone.chargerFile, "w")
  if h then
    h.write(textutils.serialize({ default = CONFIG.drone.charger or { off = true },
                                  drones = ownChargers, cfgSeen = CONFIG_CHARGER or { off = true } }))
    h.close()
  end
end

-- the SHARED station of all drones (clears their own stations)
function setCharger(dr, x, y, z)
  CONFIG.drone.charger = x and { x = x, y = y, z = z } or nil
  ownChargers = {}
  sharedTop = nil
  saveChargers()
end
-- a station for one drone only
function setOwnCharger(dr, x, y, z)
  ownChargers[dr.key] = x and { x = x, y = y, z = z } or nil
  sharedTop = nil
  saveChargers()
end

-- Drones without their own station share CONFIG.drone.charger: one parks ON
-- it (and charges), the others park side by side next to it. They take turns.
sharedTop = nil
-- the drones that use the shared station (no own one)
local function sharedKeys()
  local keys = {}
  for _, k in ipairs(droneOrder) do if not ownChargers[k] then keys[#keys + 1] = k end end
  return keys
end
-- where a drone parks: x, y, z, and whether that is ON a Charging Station
function parkSpot(dr)
  if not dr then return nil end
  local own = ownChargers[dr.key]
  if own then return own.x, own.y + 1, own.z, true end
  local c = CONFIG.drone.charger
  if not (c and c.x) then return nil end
  local keys = sharedKeys()
  local found = false
  for _, k in ipairs(keys) do if k == sharedTop then found = true end end
  if not found then sharedTop = keys[1] end
  if dr.key == sharedTop then return c.x, c.y + 1, c.z, true end
  local slot = 0
  for _, k in ipairs(keys) do
    if k ~= sharedTop then
      slot = slot + 1
      if k == dr.key then break end
    end
  end
  return c.x + 2 * slot, c.y + 1, c.z, false
end

-- station of a drone, and whether it may use it (only one drone per station)
function chargerFor(dr)
  local own = dr and ownChargers[dr.key]
  if own then return own, true end
  local c = CONFIG.drone.charger
  if not (c and c.x) then return nil, false end
  for _, k in ipairs(droneOrder) do
    if not ownChargers[k] then return c, (dr ~= nil and k == dr.key) end
  end
  return c, false
end

-- where a drone parks after a mission: above its own Charging Station (it
-- recharges there). Drones without a free station park side by side at Base.
function homePos(dr)
  local px, py, pz = parkSpot(dr)
  if px then return px, py, pz end
  local c, mine = chargerFor(dr)
  if c and mine then return c.x, c.y + 1, c.z end
  local h = CONFIG.drone.home
  if not h then return nil, "no base set (CONFIG.drone.home)" end
  local slot = 0
  for _, k in ipairs(droneOrder) do
    local ck, mk = chargerFor(drones[k])
    if not (ck and mk) then
      if dr and k == dr.key then break end
      slot = slot + 1
    end
  end
  return h.x + 2 * slot, h.y + 2, h.z
end

-- a mission step: back to the charger, or to Base when there is none
function homeStep(dr)
  local px, _, _, on = parkSpot(dr)
  if not px and dr and not dr.chargerHint then
    dr.chargerHint = true
    droneLog(dr, "No Charging Station set: parking at Base. Type  charger <x> <y> <z>  on the computer.")
  end
  return stepGoto(dr, on and "Return to the charger" or (px and "Park next to the charger" or "Return to base"),
                  function() return homePos(dr) end, 0)
end

-- every ~10 s (page worker): idle drones that are not at their parking spot
-- go back; the drone on the station hands it over when it is full
function parkCheck()
  if not CONFIG.drone.returnHome then return end
  local keys = sharedKeys()
  -- whose turn is it on the shared station?
  if CONFIG.drone.charger and #keys > 1 then
    local top = sharedTop and drones[sharedTop]
    local topFull = not top or not top.conn or top.busy
                    or (top.pressure and top.lastP and top.pressure >= CONFIG.drone.minPressure * 2
                        and top.pressure - top.lastP < 0.05)        -- not rising any more = full
    if topFull then
      local low, lp
      for _, k in ipairs(keys) do
        local d = drones[k]
        if k ~= sharedTop and d.conn and not d.busy and d.pressure and (not lp or d.pressure < lp) then
          low, lp = k, d.pressure
        end
      end
      if low and (not top or not top.conn or top.busy or lp < (top.pressure or 0) - 1) then
        sharedTop = low
        droneLog(drones[low], "My turn on the Charging Station")
      end
    end
  end
  for _, k in ipairs(droneOrder) do
    local dr = drones[k]
    if dr and not dr.busy and #dr.queue == 0 then
      local lastP = dr.pressure
      pcall(refreshDrone, dr)
      dr.lastP = lastP
      -- its parking spot at the charger, or its place at Base when there is no charger
      local x, y, z, onCharger = parkSpot(dr)
      local tol = 1.5                  -- parking spots are only 2 blocks apart
      if not x then x, y, z = homePos(dr) tol = 4 end
      -- someone on board ON PURPOSE (PICKUP done, waiting for you to DROP them):
      -- the drone stays where it is. Only after a FAILED mission it comes home.
      local carrying = dr.rider and not dr.failedAt
      if carrying then
        dr.awaySince = nil
      elseif dr.conn and x and dr.pos and dr.pos.x then
        local d = math.abs(dr.pos.x - (x + 0.5)) + math.abs(dr.pos.y - (y + 0.5)) + math.abs(dr.pos.z - (z + 0.5))
        if d > tol then
          dr.awaySince = dr.awaySince or os.clock()
          local wait = dr.failedAt and 0 or 20                 -- after a failure: at once
          if os.clock() - dr.awaySince >= wait and (not dr.lastPark or os.clock() - dr.lastPark > 60) then
            dr.awaySince, dr.lastPark = nil, os.clock()
            -- somebody on board the base does not know of (a release that did nothing):
            -- never fly them home - ask the drone first
            if not dr.failedAt and droneCarries(dr, nil) == true then
              dr.rider = dr.rider or "passenger"
              droneLog(dr, "Somebody is on board - staying here (DROP lets them off)")
            else
              droneLog(dr, "Idle away from my parking spot - going back")
              submitDrone(dr, { kind = "home" })
            end
          end
        else
          local failed = dr.failedAt
          dr.awaySince, dr.failedAt = nil, nil
          -- home after a failure with someone still on board: let them out (as a mission)
          if dr.rider and failed and (not dr.lastPark or os.clock() - dr.lastPark > 60) then
            dr.lastPark = os.clock()
            submitDrone(dr, { kind = "home" })
          end
        end
      end
    end
  end
end

-- after a failure: stop whatever PneumaticCraft action is still running (a
-- teleport it keeps retrying, an import) and clear the filters / area, so the
-- drone takes the next order cleanly
function resetDrone(dr)
  local d = dr and dr.periph
  if not d then return end
  pcall(d.abortAction)
  pcall(d.clearWhitelistText)
  pcall(d.clearBlacklistText)
  pcall(d.clearArea)
end

-- someone still on board after a failure (dr.rider): let them out where the
-- drone stands (it is at home / its parking spot then)
function releaseRider(dr)
  if not dr.rider then return true end
  local x, y, z = droneXYZ(dr)
  if dr.lastSpot then x, y, z = dr.lastSpot.x, dr.lastSpot.y, dr.lastSpot.z end
  if not x then return false end
  local who = dr.rider
  local ok = releaseAt(dr, fl(x), fl(y), fl(z))
  droneLog(dr, ok and (who .. " let out after the failed ride") or ("Could not let " .. who .. " out - try RELEASE"))
  return ok
end

-- title + steps for a command (home, fly, pickup, drop, ferry)
function buildMission(dr, cmd)
  local who = canonPlayer(cmd.passenger or dr.passenger or state.owner or "")
  if cmd.kind == "home" then
    local steps = { homeStep(dr) }
    if dr.rider then
      steps[2] = { text = "Let " .. dr.rider .. " out", fn = function() return releaseRider(dr) end }
    end
    return "Return to base", steps
  elseif cmd.kind == "fly" then
    return "Fly to " .. destShort(dr),
           { stepGoto(dr, "Fly to " .. destShort(dr), function() return resolveDest(dr) end, 0) }
  elseif cmd.kind == "pickup" then
    return "Pick up " .. who, pickupSteps(dr, who)
  elseif cmd.kind == "drop" then
    return "Drop " .. who, dropSteps(dr, who)
  elseif cmd.kind == "ferry" then
    local steps = pickupSteps(dr, who)
    for _, st in ipairs(dropSteps(dr, who)) do steps[#steps + 1] = st end
    return "Ferry " .. who .. " > " .. destShort(dr), steps
  end
end

-- run one command on one drone (in the drone worker): checks air,
-- destination and the overworld first, then the steps; on failure with someone
-- on board, brings them back to Base
function runMission(dr, cmd)
  local d = dr.periph
  if not d or dr.gone then return end
  if cmd.cancelled then
    dr.mission = { title = cmd.kind, steps = {}, state = "stopped" }
    droneLog(dr, "Cancelled: " .. cmd.kind)
    return
  end

  if cmd.kind == "stop" then
    pcall(d.abortAction)
    dr.abort = false
    droneLog(dr, "Stopped the current action")
    return
  elseif cmd.kind == "release" then
    pcall(d.abortAction)
    local ok = pcall(d.exitPiece)
    dr.abort = false
    dr.mission = nil
    droneLog(dr, ok and "Released the drone (it continues its own program)" or "Release failed")
    return
  end

  local okC, conn = pcall(d.isConnectedToDrone)
  if not okC or not conn then
    dr.mission = { title = cmd.kind, steps = {}, state = "failed",
                   err = "No drone is connected to this interface" }
    droneLog(dr, "Cannot start: no drone connected")
    return
  end
  if cmd.kind ~= "pickup" and cmd.kind ~= "fly" and cmd.kind ~= "drop" and cmd.kind ~= "ferry"
     and cmd.kind ~= "home" then return end

  -- not enough air: the drone would stop working halfway
  local okP, pr = pcall(d.getDronePressure)
  local need = (cmd.kind == "ferry" or cmd.kind == "pickup") and rideMinPressure() or CONFIG.drone.minPressure
  if okP and type(pr) == "number" and pr < need and cmd.kind ~= "home" then
    dr.mission = { title = cmd.kind, steps = {}, state = "failed",
                   err = string.format("Pressure too low (%.1f bar). Charge the drone at a " ..
                                       "Charging Station first.", pr) }
    droneLog(dr, string.format("Cannot start: pressure %.1f bar", pr))
    return
  end
  -- this mission's own destination: a chat ride brings its own (cmd.dest) and
  -- never uses or changes what is chosen on the monitor
  dr.mdest = cmd.dest or dr.dest
  if (cmd.kind == "fly" or cmd.kind == "ferry" or cmd.kind == "drop") and not dr.mdest then
    dr.mission = { title = cmd.kind, steps = {}, state = "failed", err = "No destination chosen" }
    droneLog(dr, "Cannot start: no destination chosen")
    return
  end

  -- every player involved must be in the overworld BEFORE the drone moves
  -- (a teleport costs air even when it goes nowhere useful)
  local check = {}
  if cmd.kind == "pickup" or cmd.kind == "ferry" then
    check[#check + 1] = canonPlayer(cmd.passenger or dr.passenger or state.owner or "")
  end
  if (cmd.kind == "fly" or cmd.kind == "drop" or cmd.kind == "ferry")
     and dr.mdest and dr.mdest.kind == "player" then
    check[#check + 1] = dr.mdest.name
  end
  for _, pn in ipairs(check) do
    local px, why = playerPos(pn)
    if not px then
      dr.mission = { title = cmd.kind, steps = {}, state = "failed", err = cleanErr(why) }
      droneLog(dr, "Cannot start: " .. cleanErr(why))
      -- a chat ride is answered in chat (to that player only); the monitor gets a popup
      if not dr.requester then setPopup(dr.label .. " - CANNOT START", cleanErr(why), C.warn) end
      return
    end
  end

  dr.abort = false
  dr.failedAt = nil
  if cmd.kind ~= "home" then                     -- (going home keeps who is on board)
    dr.checkAboard, dr.notAboard = nil, nil
    dr.rider, dr.riderFar, dr.riderCheck = nil, 0, nil
  end
  local title, steps = buildMission(dr, cmd)
  dr.mission = { title = title, state = "running", steps = {} }
  for i, st in ipairs(steps) do dr.mission.steps[i] = { text = st.text, status = "pending" } end
  droneLog(dr, "Started: " .. title)

  for i, st in ipairs(steps) do
    local ms = dr.mission.steps[i]
    ms.status = "run"
    os.queueEvent("inv_update")
    local ok, res, why = pcall(st.fn)      -- steps return true, or false + reason
    local good = ok and res and true or false
    local err = (not ok) and res or why
    if good then
      ms.status = "done"
    else
      ms.status = "fail"
      dr.mission.state = (tostring(err) == "stopped") and "stopped" or "failed"
      dr.mission.err = cleanErr(err or "failed")
      droneLog(dr, (dr.mission.state == "stopped" and "Stopped: " or "Failed: ") ..
                   st.text .. " - " .. cleanErr(err))
      resetDrone(dr)
      -- (a STOP by you is not a failure: the drone stays where you stopped it)
      if dr.mission.state == "failed" then dr.failedAt = os.clock() end   -- the park check sends it home if all below fails
      local wentHome = false
      -- a failed pickup leaves nobody on board: safe to go home
      if dr.mission.state == "failed" and st.text:find("^Pick up") and CONFIG.drone.returnHome and cmd.kind ~= "home" then
        local okH = pcall(homeStep(dr).fn)
        wentHome = true
        droneLog(dr, okH and "Returned to base" or "Could not return to base")
      end
      -- failed AFTER a pickup (or a drop mission): someone is still on board.
      -- Never leave them hanging in the air - bring them back to Base.
      local aboard = (cmd.kind == "drop")
      for j = 1, i - 1 do if steps[j].text:find("^Pick up") then aboard = true end end
      if tostring(err) == "passenger got off" then
        droneLog(dr, tostring(dr.rider) .. " got off during the ride - going straight home (while the area is still loaded)")
        dr.rider = nil
        dr.notAboard = true
        dr.mission.err = "you got off during the ride - the drone went home"
      end
      if dr.notAboard then
        aboard = false
        dr.rider = nil
        droneLog(dr, "Nobody on board - nothing released")
        if CONFIG.drone.returnHome and not wentHome then
          wentHome = true
          local okH = pcall(homeStep(dr).fn)
          droneLog(dr, okH and "Back at base" or "Could not return to the charger")
        end
      end
      -- the RELEASE itself failed: the drone IS at the destination with them -
      -- stay there (before: "bring them back to Base" = you were flown back)
      if dr.mission.state == "failed" and st.text:find("^Release") and cmd.kind ~= "home" then
        wentHome = true
        dr.failedAt = nil                      -- (the park check leaves a drone with a rider alone)
        dr.rider = dr.rider or "passenger"
        dr.mission.err = dr.mission.err .. " - the drone stays here with you: press DROP again, or get off yourself (sneak)"
        setPopup(dr.label .. " COULD NOT LET YOU OFF", "It stays where it is. Press DROP again, or sneak to get off.", C.warn)
      end
      if dr.mission.state == "failed" and aboard and not st.text:find("^Pick up") and not st.text:find("^Release")
         and cmd.kind ~= "home" then
        wentHome = true
        droneLog(dr, "Passenger still on board - bringing them back to Base")
        local okR, r1, r2 = pcall(rescueToBase, dr)
        local good = okR and r1
        droneLog(dr, good and "Passenger released at Base"
                          or ("Rescue failed: " .. cleanErr((not okR) and r1 or r2)))
        dr.mission.err = dr.mission.err .. (good and " - passenger brought back to Base" or "")
        if good and CONFIG.drone.returnHome then
          local okH = pcall(homeStep(dr).fn)
          droneLog(dr, okH and "Back at base" or "Could not return to the charger")
        end
      end
      -- any other failure (a fly mission, a failed trip home ...): home now
      if dr.mission.state == "failed" and not wentHome and CONFIG.drone.returnHome and cmd.kind ~= "home" then
        local okH = pcall(homeStep(dr).fn)
        droneLog(dr, okH and "Back at base after the failure" or "Could not return to base - trying again later")
      end
      -- (someone still on board and home not reached: NOT let out here - it may
      -- be up in the air. The park check tries home again; RELEASE is yours.)
      return
    end
  end
  dr.mission.state = "done"
  droneLog(dr, "Finished: " .. title)

  if CONFIG.drone.returnHome and cmd.kind ~= "home" and cmd.kind ~= "pickup" and droneCarries(dr, nil) == true then
    droneLog(dr, "Somebody is still on board - NOT flying home with them")
    dr.rider = dr.rider or "passenger"
  elseif CONFIG.drone.returnHome and cmd.kind ~= "home" and cmd.kind ~= "pickup" then
    local hs = homeStep(dr)
    dr.mission.steps[#dr.mission.steps + 1] = { text = hs.text, status = "run" }
    os.queueEvent("inv_update")
    local ok, res, why = pcall(hs.fn)
    local good = ok and res
    dr.mission.steps[#dr.mission.steps].status = good and "done" or "fail"
    droneLog(dr, good and "Back at base" or ("Return to base failed: " .. cleanErr((not ok) and res or why)))
  end
  setToast(dr.label .. ": " .. title .. " - done", C.good, 8)
end

-- the UI and the console both use this (never calls the drone itself)
function submitDrone(dr, cmd)
  if not dr then
    setToast("No drone selected", C.warn, 4)
    return false
  end
  if cmd.kind == "stop" or cmd.kind == "release" then
    dr.abort = true
    for _, q in ipairs(dr.queue) do
      if q.kind ~= "stop" and q.kind ~= "release" then q.cancelled = true end
    end
    dr.queue[#dr.queue + 1] = cmd
    os.queueEvent("drone_abort")
    os.queueEvent("drone_cmd")
    return true
  end
  if dr.busy then
    setToast(dr.label .. " is busy - press STOP first", C.warn, 4)
    return false
  end
  dr.busy = true
  dr.queue[#dr.queue + 1] = cmd
  os.queueEvent("drone_cmd")
  return true
end

