











function fl(n) return math.floor(tonumber(n) or 0) end


function fmtPos(x, y, z)
if not x then return "?" end
return string.format("%d, %d, %d", fl(x), fl(y), fl(z))
end


function dist3(ax, ay, az, bx, by, bz)
return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end





drones, droneOrder = {}, {}


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
for k, l in pairs(savedLogs) do all[k] = l end
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
local okR, real = pcall(os.date, "%d.%m %H:%M")
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



scanDrones = function()
local remote, side = candidates(DR_TYPES)
local list = (#remote > 0) and remote or side
local added = false


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
savedLogs[name] = dr.log
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


function chatTell(name, text)
if not name or name == "" then return end
state.chatOut[#state.chatOut + 1] = { name = name, text = text }
os.queueEvent("chat_send")
end


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


function isOwner(uuid, name)
if state.ownerUuid and uuid then return uuid == state.ownerUuid end
return state.owner ~= nil and name == state.owner
end


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

if CONFIG.drone.home then
local h = CONFIG.drone.home
local w = findWaypoint("Base")
if not w or w.x ~= h.x or w.y ~= h.y or w.z ~= h.z or w.name ~= "Base" then
if w then removeWaypoint(w.name) end
addWaypoint("Base", h.x, h.y, h.z)
end
end


function validCoords(x, y, z)
x, y, z = tonumber(x), tonumber(y), tonumber(z)
if not (x and y and z) then return false end
if x ~= x or y ~= y or z ~= z then return false end
if math.abs(x) > 30000000 or math.abs(z) > 30000000 then return false end
if y < -64 or y > 320 then return false end
return true
end


function canonPlayer(name)
for _, e in ipairs(state.players or {}) do
if e.name:lower() == tostring(name):lower() then return e.name end
end
return name
end


DRONE_DIM = "minecraft:overworld"


OTHER_DIM = "?other"


function dimName(d)
if d == OTHER_DIM then return "another dimension" end
return (tostring(d):gsub("^.*:", ""):gsub("_", " "))
end



function playerDimNow(name, p)
local d = (p and dimFromData(p)) or dimCache[name]
if d then return d end



if det then
local set, full = playersInRangeSet()
if set[name] then return homeDimension() end
if full then return OTHER_DIM end
end
end


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


function resolveDest(dr)
local d = dr and (dr.mdest or dr.dest)
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


function destShort(dr)
local d = dr and (dr.mdest or dr.dest)
if not d then return "?" end
if d.kind == "player" then return "@" .. d.name end
if d.kind == "waypoint" then return d.name end
return fmtPos(d.x, d.y, d.z)
end


function destPosCached(dr)
local d = dr and dr.dest
if not d then return nil end
if d.kind == "player" then
for _, e in ipairs(state.players or {}) do
if e.name == d.name and e.p and e.p.x then
if e.dim and e.dim ~= DRONE_DIM then return nil end
return e.p.x, e.p.y, e.p.z
end
end
return nil
end
return d.x, d.y, d.z
end


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
local ok, a, b, c = pcall(d.getDronePosition)
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


function refreshDrones()
local list = {}
for _, k in ipairs(droneOrder) do list[#list + 1] = drones[k] end
pmap(list, function(dr) refreshDrone(dr) end)
state.t.drone = os.clock()
end



function cleanErr(e)
return (tostring(e):gsub("^[^:]*:%d+: ", ""))
end


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


function areaPoint(dr, x, y, z)
dr.periph.clearArea()
dr.periph.addArea(fl(x), fl(y), fl(z))
end



function travelAction()
return (CONFIG.drone.travel == "fly") and "pneumaticcraft:goto" or "pneumaticcraft:teleport"
end






function rideMinPressure()
if CONFIG.drone.travel ~= "fly" then
return math.max(CONFIG.drone.minPressure, CONFIG.drone.rideMinTeleport or 4)
end
return CONFIG.drone.minPressure
end


function dronePressure(dr)
local okP, p = pcall(dr.periph.getDronePressure)
if okP and type(p) == "number" then dr.pressure = p return p end
return dr.pressure
end

function teleportCost(dr) return dr.tpCost or CONFIG.drone.teleportCost or 0.85 end

function canTeleport(dr, extra)
local p = dronePressure(dr)
if not p then return true end
return p >= teleportCost(dr) * (1 + (extra or 0)) + (CONFIG.drone.airReserve or 1.5)
end




function riderLeft(dr)
if not dr.rider then return false end
if dr.riderCheck and os.clock() - dr.riderCheck < 2 then return false end
dr.riderCheck = os.clock()
return riderGoneNow(dr)
end




function riderGoneNow(dr)
local name = dr.rider
if not name then return false end
if det and det.getOnlinePlayers then
local ok, list = pcall(det.getOnlinePlayers)
if ok and type(list) == "table" then
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



function droneMoveTo(dr, action, x, y, z, limit)
local d = dr.periph
if not d or dr.gone then return false, "Drone Interface disconnected" end
local isTp = action == "pneumaticcraft:teleport"

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
if used and used > 0.05 and used < 5 then dr.tpCost = used end
end
return true
end
local okD, done = pcall(d.isActionDone)
if okD and done and t > 0.6 and not px then return true end
if t > limit then
pcall(d.abortAction)
return false, "did not get there"
end
end
end


local SPOTS = { { 0, 0, 0 }, { 0, 1, 0 }, { 0, 2, 0 }, { 1, 1, 0 }, { -1, 1, 0 },
{ 0, 1, 1 }, { 0, 1, -1 }, { 0, 4, 0 } }




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
add(0, 2, 0)
return list
end






function droneXYZ(dr)
local okP, a, b, c = pcall(dr.periph.getDronePosition)
if not okP then return nil end
return parsePos((type(a) == "number") and { a, b, c } or a)
end

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


local err, retry
if canTeleport(dr, 2) then
ok, err = droneMoveTo(dr, "pneumaticcraft:teleport", hx, hy, hz, CONFIG.drone.travelTimeout)
if not ok and err ~= "did not get there" then return false, err end

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



function skyOpenAbove(x, y, z)
if not MAP or not MAP.get then return nil end
local top = MAP.get(math.floor(x), math.floor(z))
if not top then return nil end
return y >= top + 1, top
end




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



function travelTo(dr, x, y, z, spots, noFly, loaded)
dr.lastSpot = nil
local act = travelAction()
local SPOTS = spots or SPOTS

if act ~= "pneumaticcraft:goto" and not canTeleport(dr) then
droneLog(dr, string.format("Low on air (%.1f bar): flying instead of teleporting", dronePressure(dr) or 0))
act = "pneumaticcraft:goto"
end

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


if not ok and i == 1 and err == "did not get there" and act ~= "pneumaticcraft:goto" and not noFly then
local okS, errS = skyApproach(dr, x + o[1], y + o[2], z + o[3])
if okS then return true end
if errS and errS ~= "did not get there" then return false, errS end
end
if err == "low on air" then
droneLog(dr, "Low on air after failed teleports - flying the rest")
act = "pneumaticcraft:goto"
ok, err = droneMoveTo(dr, act, x + o[1], y + o[2], z + o[3], CONFIG.drone.stepTimeout)
end
if ok then
dr.lastSpot = { x = x + o[1], y = y + o[2], z = z + o[3] }
if i > 1 then
local f = SPOTS[1]
droneLog(dr, "Spot " .. (x + f[1]) .. ", " .. (y + f[2]) .. ", " .. (z + f[3]) .. " was blocked - used " ..
(x + o[1]) .. ", " .. (y + o[2]) .. ", " .. (z + o[3]))
end
return true
end
if err ~= "did not get there" then return false, err end
lastErr = err
if act == "pneumaticcraft:goto" then break end
end
if act ~= "pneumaticcraft:goto" and not noFly then
droneLog(dr, "No spot near " .. x .. ", " .. y .. ", " .. z .. " could be teleported to (the area is " ..
"probably not loaded) - FLYING there instead")
local ok, err = droneMoveTo(dr, "pneumaticcraft:goto", x, y, z, CONFIG.drone.stepTimeout)
if ok then dr.lastSpot = { x = x, y = y, z = z } return true end
if err ~= "did not get there" then return false, err end
lastErr = err


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


function stepGoto(dr, text, getPos, yOff, loaded)
return { text = text, fn = function()
local x, y, z = getPos()
if not x then return false, y end
local isLoaded = loaded
if type(loaded) == "function" then isLoaded = loaded() end
return travelTo(dr, x, y + (yOff or 0), z, nil, nil, isLoaded)
end }
end


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


function letGoHere(dr, why, gx, gy, gz)
local x, y, z = droneXYZ(dr)
if gx then x, y, z = gx, gy, gz end
if not x then return end
droneLog(dr, why .. " - letting go of everything here")
pcall(releaseAt, dr, fl(x), fl(y), fl(z))
end









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


local okA, errA = travelTo(dr, x, y, z, pickupSpots(), true, true)
if not okA then


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

local wrong
local py0, dy0
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
if not ok then

else




local lift = math.max(4, CONFIG.drone.liftHeight or 4)
local okL, errL = droneMoveTo(dr, "pneumaticcraft:goto", x, y + lift, z, 8)
if errL == "stopped" or errL == "the drone disconnected" then return false, errL end
if not okL then

droneLog(dr, "Could not lift (" .. tostring(errL) .. ") - checking on arrival that " .. name .. " came along")
dr.checkAboard = name
dr.rider = name
return true
end





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

letGoHere(dr, "Not the right passenger on board", x, y, z)
end
if dr.abort then return false, "stopped" end
end
return false, name .. " could not be picked up after " .. CONFIG.drone.pickupTries ..
" tries (" .. lastErr .. "). If the drone is already carrying " ..
"something it cannot pick up more - use DROP first."
end } }
end




function dropTarget(dr)
local x, y, z = resolveDest(dr)
if not x then return nil, y end
local md = dr.mdest or dr.dest
if md and md.kind == "player" then x = x + 2 end
return x, y, z
end


function releaseAt(dr, x, y, z)
local ok, err = droneDo(dr, "pneumaticcraft:entity_export", function()
areaPoint(dr, x, y, z)
dr.periph.clearWhitelistText()
dr.periph.clearBlacklistText()
pcall(dr.periph.setUseCount, false)
end, 1, 40)
if ok then
droneLog(dr, "Released at " .. fmtPos(x, y, z))
dr.rider = nil
end
return ok, err
end


function rescueToBase(dr)
local h = CONFIG.drone.home
if not h then return false, "no base set" end
local ok, err = travelTo(dr, h.x, h.y, h.z)
if not ok and err == "passenger got off" then

droneLog(dr, tostring(dr.rider) .. " got off during the ride back")
dr.rider = nil
return travelTo(dr, h.x, h.y, h.z)
end
if not ok then return false, err end
local s = dr.lastSpot or { x = h.x, y = h.y, z = h.z }
return releaseAt(dr, s.x, s.y, s.z)
end


function passengerHere(dr)
local name = dr.checkAboard
if not name or not dr.lastSpot then return true end
waitFor(0.5, "drone_abort")
local px, py, pz = playerPos(name)
if type(px) ~= "number" then return true end
local s = dr.lastSpot
return math.abs(px - s.x) <= 4 and math.abs(pz - s.z) <= 4 and math.abs(py - s.y) <= 5
end


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

local x, y, z
if dr.lastSpot then x, y, z = dr.lastSpot.x, dr.lastSpot.y, dr.lastSpot.z
else x, y, z = dropTarget(dr) end
if not x then return false, y end
return releaseAt(dr, x, y, z)
end },
}
end



ownChargers = {}

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
if t.x then CONFIG.drone.charger = t
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


function setCharger(dr, x, y, z)
CONFIG.drone.charger = x and { x = x, y = y, z = z } or nil
ownChargers = {}
sharedTop = nil
saveChargers()
end

function setOwnCharger(dr, x, y, z)
ownChargers[dr.key] = x and { x = x, y = y, z = z } or nil
sharedTop = nil
saveChargers()
end



sharedTop = nil

local function sharedKeys()
local keys = {}
for _, k in ipairs(droneOrder) do if not ownChargers[k] then keys[#keys + 1] = k end end
return keys
end

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



function parkCheck()
if not CONFIG.drone.returnHome then return end
local keys = sharedKeys()

if CONFIG.drone.charger and #keys > 1 then
local top = sharedTop and drones[sharedTop]
local topFull = not top or not top.conn or top.busy
or (top.pressure and top.lastP and top.pressure >= CONFIG.drone.minPressure * 2
and top.pressure - top.lastP < 0.05)
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

local x, y, z, onCharger = parkSpot(dr)
local tol = 1.5
if not x then x, y, z = homePos(dr) tol = 4 end


local carrying = dr.rider and not dr.failedAt
if carrying then
dr.awaySince = nil
elseif dr.conn and x and dr.pos and dr.pos.x then
local d = math.abs(dr.pos.x - (x + 0.5)) + math.abs(dr.pos.y - (y + 0.5)) + math.abs(dr.pos.z - (z + 0.5))
if d > tol then
dr.awaySince = dr.awaySince or os.clock()
local wait = dr.failedAt and 0 or 20
if os.clock() - dr.awaySince >= wait and (not dr.lastPark or os.clock() - dr.lastPark > 60) then
dr.awaySince, dr.lastPark = nil, os.clock()
droneLog(dr, "Idle away from my parking spot - going back")
submitDrone(dr, { kind = "home" })
end
else
local failed = dr.failedAt
dr.awaySince, dr.failedAt = nil, nil

if dr.rider and failed and (not dr.lastPark or os.clock() - dr.lastPark > 60) then
dr.lastPark = os.clock()
submitDrone(dr, { kind = "home" })
end
end
end
end
end
end




function resetDrone(dr)
local d = dr and dr.periph
if not d then return end
pcall(d.abortAction)
pcall(d.clearWhitelistText)
pcall(d.clearBlacklistText)
pcall(d.clearArea)
end



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


local okP, pr = pcall(d.getDronePressure)
local need = (cmd.kind == "ferry" or cmd.kind == "pickup") and rideMinPressure() or CONFIG.drone.minPressure
if okP and type(pr) == "number" and pr < need and cmd.kind ~= "home" then
dr.mission = { title = cmd.kind, steps = {}, state = "failed",
err = string.format("Pressure too low (%.1f bar). Charge the drone at a " ..
"Charging Station first.", pr) }
droneLog(dr, string.format("Cannot start: pressure %.1f bar", pr))
return
end


dr.mdest = cmd.dest or dr.dest
if (cmd.kind == "fly" or cmd.kind == "ferry" or cmd.kind == "drop") and not dr.mdest then
dr.mission = { title = cmd.kind, steps = {}, state = "failed", err = "No destination chosen" }
droneLog(dr, "Cannot start: no destination chosen")
return
end



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

if not dr.requester then setPopup(dr.label .. " - CANNOT START", cleanErr(why), C.warn) end
return
end
end

dr.abort = false
dr.failedAt = nil
if cmd.kind ~= "home" then
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
local ok, res, why = pcall(st.fn)
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

if dr.mission.state == "failed" then dr.failedAt = os.clock() end
local wentHome = false

if dr.mission.state == "failed" and st.text:find("^Pick up") and CONFIG.drone.returnHome and cmd.kind ~= "home" then
local okH = pcall(homeStep(dr).fn)
wentHome = true
droneLog(dr, okH and "Returned to base" or "Could not return to base")
end


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
if dr.mission.state == "failed" and aboard and not st.text:find("^Pick up") and cmd.kind ~= "home" then
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

if dr.mission.state == "failed" and not wentHome and CONFIG.drone.returnHome and cmd.kind ~= "home" then
local okH = pcall(homeStep(dr).fn)
droneLog(dr, okH and "Back at base after the failure" or "Could not return to base - trying again later")
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

