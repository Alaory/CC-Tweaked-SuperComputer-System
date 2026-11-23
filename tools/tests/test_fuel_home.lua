-- FUEL FOR THE WAY HOME (the owner: "you can see the amount of lost turtles in the map"; the survey edge was
-- ~2,400 blocks from the base). Before: survey spots down to 500 fuel, sent home only below 2000 - the way home
-- (up to the sky highway, across, down) costs more, so every turtle at the edge ran dry on the way home.
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
local function sent(id, cmd)
  local r = {}
  for _, o in ipairs(state.tOut) do if o.id == id and o.msg.cmd == cmd then r[#r + 1] = o end end
  return r
end
local function mk(id, dist, fuel, extra)
  local t = { id = id, label = "F" .. id, log = {}, lastN = 0, fuel = fuel, task = "idle",
    pos = { x = HOME.x + dist, y = 70, z = HOME.z }, home = { x = HOME.x, y = 68, z = HOME.z + id },
    lastSeen = os.clock(), seenEpoch = os.epoch("utc") }
  for k, v in pairs(extra or {}) do t[k] = v end
  state.turtles[id] = t
  return t
end
state.turtles, state.tOut = {}, {}

-- the cost of the way home
local far = mk(31, 2400, 3600)
local cost = TT.homeCost(far)
CHECK(cost > 2400 + 160 and cost < 3500, "the way home from 2,400 blocks costs " .. cost .. " (sky highway up + across + down)")
far.homeFuel = 2900
CHECK(TT.homeCost(far) == 2900, "the turtle's own number is used when it sends one")
far.homeFuel = nil
CHECK(TT.surveyFuelNeed(far) >= cost + 800, "survey spots need the way home + a batch: " .. TT.surveyFuelNeed(far))
local endless = mk(32, 2400, 700, { endless = true })
CHECK(TT.surveyFuelNeed(endless) == (tonumber(CONFIG.map.surveyMinFuel) or 500), "endless fuel: the plain minimum")

-- 1) no new spots far out with only 2500 fuel (old: anything above 500 got spots)
MAP.queue = nil
MAP.queueSurvey(HOME.x + 2350, HOME.z - 100, HOME.x + 2450, HOME.z + 100, 8, nil)
for _ = 1, 3 do CLOCK = CLOCK + 20 far.lastSeen = CLOCK endless.lastSeen = CLOCK MAP.feedSurvey() end
CHECK(#sent(31, "surveypts") == 0, "3600 fuel at 2,400 blocks out (home ~3,250 + a batch): no more survey spots")
CHECK(#sent(32, "surveypts") > 0, "the endless-fuel turtle keeps working out there")
local why = TT.idleWhy(far)
CHECK(tostring(why):find("way home", 1, true), "the card says why: " .. tostring(why))
MAP.queue = nil

-- 2) it goes HOME while it can (old: 3600 >= lowFuel 2000 = "not low", it stood there for good)
state.tOut = {}
far.idleSince = nil
for _ = 1, 3 do CLOCK = CLOCK + 6 far.lastSeen = CLOCK TT.homeTick() end
CHECK(#sent(31, "home") == 1, "it is sent home while the fuel still covers the way")
CHECK(not far.fuelShort, "... it is not 'short'")

-- 3) too little to get home: it stays where it is (its chunk stays loaded) and fuel is brought
local short = mk(33, 2400, 1500)
state.tOut = {}
for _ = 1, 3 do CLOCK = CLOCK + 6 short.lastSeen = CLOCK TT.homeTick() end
CHECK(#sent(33, "home") == 0 and #sent(33, "fuelup") == 0, "1500 fuel at 2,400 blocks out: NOT sent home (it would run dry on the way)")
CHECK(short.fuelShort, "it waits for fuel (fuelShort)")
CHECK(tostring(TT.idleWhy(short)):find("not enough to get home", 1, true), "the card says so: " .. tostring(TT.idleWhy(short)))
-- the rescuer brings fuel after 2 min
local resc = mk(34, 10, 60000, { rescuerRole = true })
resc.pos = { x = HOME.x + 2, y = 68, z = HOME.z }
resc.home = { x = HOME.x + 2, y = 68, z = HOME.z }
TT.startedAt = -1000
state.tOut = {}
for _ = 1, 30 do
  CLOCK = CLOCK + 10
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  TT.homeTick()
  TT.patrolTick()
end
local went, cmds = false, {}
for _, o in ipairs(state.tOut) do if o.id == 34 then cmds[#cmds + 1] = o.msg.cmd if o.msg.cmd ~= "home" then went = true end end end
local rl = {}
for i = 1, math.min(4, #resc.log) do rl[#rl + 1] = resc.log[i].msg end
CHECK(went or short.rescueAt, "the rescuer is sent with fuel (sent: " .. table.concat(cmds, ",") .. "; log: " .. table.concat(rl, " | ") .. ")")
-- fuel came: short no more
short.fuel = 5000
TT.homeTick()
CHECK(not short.fuelShort, "refuelled: no longer short")

-- 4) near home nothing changes: a turtle at home with 600 fuel is not "short"
local near = mk(35, 5, 600)
near.pos = { x = HOME.x, y = 68, z = HOME.z + 40 }
TT.homeTick()
CHECK(not near.fuelShort, "at home: never 'short'")
state.turtles, state.tOut = {}, {}
MAP.queue = nil
