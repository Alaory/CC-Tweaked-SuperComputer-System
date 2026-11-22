-- TURTLE STATUS (the owner: "some turtles report that they cannot move when they can, and other stuff too"):
-- STUCK only for a trip that could not MOVE (node.lua used to flag ANY failed trip - a survey stopped for the fuel
-- home, an unknown facing, a taken home spot - and the base showed STUCK, kept the turtle from fuel / home trips and
-- sent the rescuer); NOT MOVING never for jobs that stand still on purpose (building, crafting, scanning, a look
-- around, being driven); an old stuck flag is gone once it moved away.
local now = os.epoch("utc")
local function T(id, f)
  local t = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 9000, pos = { x = 500, y = 70, z = 500 },
              home = { x = 0, y = 70, z = 0 }, task = "idle", lastSeen = os.clock(), seenEpoch = now }
  for k, v in pairs(f or {}) do t[k] = v end
  state.turtles[id] = t
  return t
end
state.turtles = {}
local function key(t) return (TT.status(t)) end

-- 1) STUCK: only movement failures
local notMove = { "fuel 1800 only for the way home (2400) after 3/16 scans", "low fuel (150) after 2 of 16 scans",
  "position/facing unknown - use GPS LOCATE (GPS: no signal)", "the offered home 1 2 3 is not free - asked the base for another one",
  "no home set (SET HOME)", "area too big (900 scans) - zoom in on the map", "could not equip the Geo Scanner (scan 3/16)" }
for i, m in ipairs(notMove) do
  local t = T(100 + i, { stuck = m, stuckPos = { x = 500, y = 70, z = 500 } })
  CHECK(key(t) ~= "stuck", "'" .. m .. "' is not STUCK (" .. tostring(key(t)) .. ")")
  CHECK(not TT.isStuck(t), "... TT.isStuck false")
  local mk = mapMarker(t)
  CHECK(mk ~= "!", "... no red ! on the map")
end
local moveFails = { "blocked at 500 70 500", "could not reach 900 900 (at 500 70 500)", "no progress (going in circles) at 1 2 3",
  "gave up after 6 plans (scan 2/16)", "no way up to the sky highway (blocked)", "no way found" }
for i, m in ipairs(moveFails) do
  local t = T(200 + i, { stuck = m, stuckPos = { x = 500, y = 70, z = 500 } })
  CHECK(key(t) == "stuck", "'" .. m .. "' IS stuck (" .. tostring(key(t)) .. ")")
end
-- moved away from where it said so: old news (also straight up / down)
local up = T(300, { stuck = "blocked at 500 70 500", stuckPos = { x = 500, y = 70, z = 500 }, pos = { x = 500, y = 80, z = 500 } })
CHECK(key(up) ~= "stuck", "moved 10 up since: not stuck any more")

-- 2) the rescuer goes only to a turtle that really cannot move
state.turtles = {}
local fine = T(1, { stuck = "fuel 1800 only for the way home (2400) after 3/16 scans", stuckPos = { x = 500, y = 70, z = 500 } })
local real = T(2, { stuck = "blocked at 500 70 500", stuckPos = { x = 500, y = 70, z = 500 } })
TT.problemOf(fine) TT.problemOf(real)
CLOCK = CLOCK + 70
fine.lastSeen, real.lastSeen = os.clock(), os.clock()
CHECK(TT.problemOf(fine) == nil, "the survey that stopped for the fuel home: no rescue (" .. tostring(TT.problemOf(fine)) .. ")")
CHECK(TT.problemOf(real) == "stuck", "a really blocked turtle: the rescuer comes (" .. tostring(TT.problemOf(real)) .. ")")

-- 3) ...and the one that can move is sent home as usual (it was left out for being "stuck")
state.turtles = {}
state.tOut = {}
local f2 = T(3, { stuck = "fuel 1800 only for the way home (2400) after 3/16 scans", stuckPos = { x = 500, y = 70, z = 500 } })
TT.homeTick()
CLOCK = CLOCK + (tonumber(CONFIG.turtles.idleHome) or 120) + 5
f2.lastSeen = os.clock()
TT.homeTick()
local sent = false
for _, o in ipairs(state.tOut) do if o.id == 3 and o.msg and o.msg.cmd == "home" then sent = true end end
CHECK(sent, "a turtle whose survey stopped for fuel is sent home (not left out as 'stuck')")

-- 4) NOT MOVING: never for jobs that stand still on purpose
state.turtles = {}
local still = { "building a turtle", "starting the new turtle 57", "crafting", "scanning", "scanning the surroundings",
  "search party: looking around", "checking the End Automata Core", "driven by hand", "refuelling at the fuel chest",
  "waiting for turtle 9 to install itself", "GPS" }
for i, task in ipairs(still) do
  local t = T(400 + i, { task = task, movedAt = os.clock() - 400, taskAt = os.clock() - 400 })
  CHECK(key(t) ~= "still", "'" .. task .. "' 400 s without moving is not NOT MOVING (" .. tostring(key(t)) .. ")")
end
local hung = T(450, { task = "going to 1 2 3", movedAt = os.clock() - 200, taskAt = os.clock() - 200 })
CHECK(key(hung) == "still", "a trip 200 s without moving IS NOT MOVING (" .. tostring(key(hung)) .. ")")
-- the 3-min STOP only for that one
state.tOut = {}
TT.stallTick()
local stopped = {}
for _, o in ipairs(state.tOut) do if o.msg and o.msg.cmd == "stop" then stopped[o.id] = true end end
CHECK(stopped[450] and not stopped[401] and not stopped[403], "the stall STOP: the hung trip only")
-- going round something: a calm word, not "blocked"
local _, _, _, why = TT.status(T(460, { task = "planning a route" }))
CHECK(not tostring(why):find("^blocked"), "FINDING A WAY says it is going round something: " .. tostring(why))
