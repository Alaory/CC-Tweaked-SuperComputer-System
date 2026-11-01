-- Part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.

---------------------------------------------------------------------
-- DRONE  (PneumaticCraft Drone Interface)  - several drones supported
---------------------------------------------------------------------
function fl(n) return math.floor(tonumber(n) or 0) end

function fmtPos(x, y, z)
  if not x then return "?" end
  return string.format("%d, %d, %d", fl(x), fl(y), fl(z))
end

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

function droneLog(dr, msg)
  if not dr then return end
  local okR, real = pcall(os.date, "%d.%m %H:%M")   -- real date/time: logs span days
  table.insert(dr.log, 1, { t = textutils.formatTime(os.time(), true),
                            r = okR and real or nil, msg = msg })
  while #dr.log > (CONFIG.drone.logMax or 100) do table.remove(dr.log) end
  pcall(saveLogs)
  os.queueEvent("inv_update")
end

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

function allowPlayer(name)
  state.access.allowed[name:lower()] = { name = name }
  saveAccess()
end

function denyPlayer(name)
  local k = name:lower()
  local had = state.access.allowed[k] ~= nil
  state.access.allowed[k] = nil
  saveAccess()
  return had
end

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

function saveWaypoints()
  local h = fs.open(CONFIG.drone.waypointFile, "w")
  if h then
    h.write(textutils.serialize(state.waypoints))
    h.close()
  end
end

function findWaypoint(name)
  for _, w in ipairs(state.waypoints) do
    if w.name:lower() == tostring(name):lower() then return w end
  end
end

function addWaypoint(name, x, y, z)
  local w = findWaypoint(name)
  if w then w.x, w.y, w.z = x, y, z
  else state.waypoints[#state.waypoints + 1] = { name = name, x = x, y = y, z = z } end
  table.sort(state.waypoints, function(a, b) return a.name:lower() < b.name:lower() end)
  saveWaypoints()
end

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
  local d = dr and dr.dest
  if not d then return nil, "no destination chosen" end
  if d.kind == "player" then return playerPos(d.name) end
  return d.x, d.y, d.z
end

function destLabel(dr)
  local d = dr and dr.dest
  if not d then return "not set" end
  if d.kind == "player" then return "Player " .. d.name .. " (live)" end
  if d.kind == "waypoint" then return "Waypoint " .. d.name end
  return "Coordinates"
end

-- short form for titles: "200, 70, 200" / "Home" / "@Zed"
function destShort(dr)
  local d = dr and dr.dest
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

function droneMoveTo(dr, action, x, y, z, limit)
  local d = dr.periph
  if not d or dr.gone then return false, "Drone Interface disconnected" end
  local isTp = action == "pneumaticcraft:teleport"
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
  local dx, dz = CONFIG.drone.approachDX or 1, CONFIG.drone.approachDZ or 0
  local list, seen = {}, {}
  local function add(a, b, c)
    local k = a .. "," .. b .. "," .. c
    if not seen[k] then seen[k] = true list[#list + 1] = { a, b, c } end
  end
  add(dx, 0, dz)
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do add(d[1], 0, d[2]) end
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do add(d[1], 1, d[2]) end
  add(0, 2, 0)                                    -- above the head (a short hop)
  return list
end

-- go to x y z the configured way; if the spot is blocked, try spots nearby,
-- and when teleporting fails everywhere, try flying once
-- Far away and not loaded (nobody there): a drone can only teleport into
-- loaded chunks. With a passenger it hops in steps the passenger's own view
-- distance has loaded, high above the terrain.
local function droneXYZ(dr)
  local okP, a, b, c = pcall(dr.periph.getDronePosition)
  if not okP then return nil end
  return parsePos((type(a) == "number") and { a, b, c } or a)
end
local function hopTowards(dr, x, z)
  local L, hy = CONFIG.drone.hopLength or 160, CONFIG.drone.hopY or 200
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
    if canTeleport(dr, 2) then
      ok = droneMoveTo(dr, "pneumaticcraft:teleport", hx, hy, hz, CONFIG.drone.travelTimeout)
    end
    if not ok then
      if not dr.flyNote then
        dr.flyNote = true
        droneLog(dr, string.format("Flying the next stretches (air %.1f bar - teleports cost about %.1f each)",
                                   dronePressure(dr) or 0, teleportCost(dr)))
      end
      ok = droneMoveTo(dr, "pneumaticcraft:goto", hx, hy, hz, math.max(90, (CONFIG.drone.hopLength or 160) / 2))
      if not ok then return false, "cannot get further - the area ahead is not loaded" end
    end
  end
  return false, "too many hops"
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
      local okH, errH = hopTowards(dr, x, z)
      if not okH then return false, errH end
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
    lastErr = err
  end
  return false, "could not reach " .. x .. ", " .. y .. ", " .. z .. " (" .. tostring(lastErr) .. ")"
end

function stepGoto(dr, text, getPos, yOff, loaded)
  return { text = text, fn = function()
    local x, y, z = getPos()
    if not x then return false, y end
    local isLoaded = loaded
    if type(loaded) == "function" then isLoaded = loaded() end
    return travelTo(dr, x, y + (yOff or 0), z, nil, nil, isLoaded)
  end }
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

      if attempt > 1 or CONFIG.drone.travel ~= "fly" then
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
      elseif CONFIG.drone.travel ~= "fly" and not CONFIG.drone.liftCheck then
        -- no lift: whether the passenger really came along is checked at the
        -- destination, before anything is released
        dr.checkAboard = name
        droneLog(dr, name .. " picked up (checked on arrival)")
        return true
      else
        local okL, errL = travelTo(dr, x, y + CONFIG.drone.liftHeight, z)
        if not okL then return false, errL end
        waitFor(1, "drone_abort")
        if dr.abort then return false, "stopped" end
        local _, py = playerPos(name)
        if type(py) == "number" and py - y >= CONFIG.drone.liftHeight * 0.5 then
          droneLog(dr, name .. " is on board")
          return true
        end
        lastErr = name .. " did not come along"
        droneLog(dr, "Attempt " .. attempt .. ": " .. lastErr)
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
  if dr.dest and dr.dest.kind == "player" then x = x + 2 end
  return x, y, z
end

-- let the passenger go at x y z (Entity Export), with a time limit
function releaseAt(dr, x, y, z)
  local ok, err = droneDo(dr, "pneumaticcraft:entity_export", function()
    areaPoint(dr, x, y, z)
    dr.periph.clearWhitelistText()
    dr.periph.clearBlacklistText()
    pcall(dr.periph.setUseCount, false)
  end, 1, 40)
  if ok then droneLog(dr, "Released at " .. fmtPos(x, y, z)) end
  return ok, err
end

-- something failed with a passenger on board: bring them back to Base
function rescueToBase(dr)
  local h = CONFIG.drone.home
  if not h then return false, "no base set" end
  local ok, err = travelTo(dr, h.x, h.y, h.z)
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

function dropSteps(dr, who)
  local fly = stepGoto(dr, "Fly to destination", function() return dropTarget(dr) end, 0,
                       function() return dr.dest and dr.dest.kind == "player" end)
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
      local x, y, z = parkSpot(dr)
      if dr.conn and x and dr.pos and dr.pos.x then
        local d = math.abs(dr.pos.x - (x + 0.5)) + math.abs(dr.pos.y - (y + 0.5)) + math.abs(dr.pos.z - (z + 0.5))
        if d > 1.5 then                -- parking spots are only 2 blocks apart
          dr.awaySince = dr.awaySince or os.clock()
          if os.clock() - dr.awaySince > 20 and (not dr.lastPark or os.clock() - dr.lastPark > 60) then
            dr.awaySince, dr.lastPark = nil, os.clock()
            droneLog(dr, "Idle away from my parking spot - going back")
            submitDrone(dr, { kind = "home" })
          end
        else
          dr.awaySince = nil
        end
      end
    end
  end
end

function buildMission(dr, cmd)
  local who = canonPlayer(cmd.passenger or dr.passenger or state.owner or "")
  if cmd.kind == "home" then
    return "Return to base", { homeStep(dr) }
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
  if (cmd.kind == "fly" or cmd.kind == "ferry" or cmd.kind == "drop") and not dr.dest then
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
     and dr.dest and dr.dest.kind == "player" then
    check[#check + 1] = dr.dest.name
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
  dr.checkAboard, dr.notAboard = nil, nil
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
      -- a failed pickup leaves nobody on board: safe to go home
      if dr.mission.state == "failed" and st.text:find("^Pick up") and CONFIG.drone.returnHome then
        local okH = pcall(homeStep(dr).fn)
        droneLog(dr, okH and "Returned to base" or "Could not return to base")
      end
      -- failed AFTER a pickup (or a drop mission): someone is still on board.
      -- Never leave them hanging in the air - bring them back to Base.
      local aboard = (cmd.kind == "drop")
      for j = 1, i - 1 do if steps[j].text:find("^Pick up") then aboard = true end end
      if dr.notAboard then
        aboard = false
        droneLog(dr, "Nobody on board - nothing released")
        if CONFIG.drone.returnHome then
          local okH = pcall(homeStep(dr).fn)
          droneLog(dr, okH and "Back at base" or "Could not return to the charger")
        end
      end
      if dr.mission.state == "failed" and aboard and not st.text:find("^Pick up") then
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
      return
    end
  end
  dr.mission.state = "done"
  droneLog(dr, "Finished: " .. title)

  if CONFIG.drone.returnHome and cmd.kind ~= "home" and cmd.kind ~= "pickup" then
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

