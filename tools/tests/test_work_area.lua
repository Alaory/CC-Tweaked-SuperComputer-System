-- The WORK AREA (SETTINGS > MAP corners): no survey spot outside it - big
-- surveys, small ones, auto-map (which starts over when the area changes);
-- the MAP shows it. Plus the tap-only setup: factory chest / builder choosers,
-- the DROP button for a lost miner.
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
local function fleet(n)
  state.turtles = {}
  for i = 1, n do
    local id = 20 + i
    state.turtles[id] = { id = id, label = "S" .. i, log = {}, lastN = 0, fuel = 50000,
      pos = { x = HOME.x + i, y = 70, z = HOME.z }, home = { x = HOME.x + i, y = 70, z = HOME.z }, task = "idle", lastSeen = os.clock() }
  end
end
local function spotsSent(from)
  local l = {}
  for i = from + 1, #state.tOut do
    local o = state.tOut[i]
    if o.msg.cmd == "surveypts" then for j = 2, #o.msg.args, 2 do l[#l + 1] = { o.msg.args[j], o.msg.args[j + 1] } end end
  end
  return l
end
local function settingDef(label)
  for _, g in ipairs(SETTING_GROUPS) do for _, d in ipairs(g.list) do if d.label == label then return d end end end
end

-- the area: 400 x 300 blocks east of the base
CONFIG.map.areaA = { x = -5000, y = 70, z = 10700 }
CONFIG.map.areaB = { x = -4600, y = 64, z = 11000 }
local ax1, az1, ax2, az2 = MAP.area()
CHECK(ax1 == -5000 and az1 == 10700 and ax2 == -4600 and az2 == 11000, "the area from the two corners")
CHECK(MAP.inArea(-4800, 10800) and not MAP.inArea(-5100, 10800) and not MAP.inArea(-4800, 11001), "inside / outside")

-- a big survey of the whole zoomed-out view: only spots inside the area
fleet(3)
local DONE = {}
local spotDone0 = MAP.spotDone
MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
MAP.queue = nil
local n = MAP.queueSurvey(-40000, -30000, 40000, 30000, 8, nil)
CHECK(n > 0 and n < 1000, "the survey is cut down to the area (" .. n .. " spots)")
local outside, total = 0, 0
for round = 1, 300 do
  CLOCK = CLOCK + 20
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  local m0 = #state.tOut
  MAP.feedSurvey()
  if not MAP.queue then break end
  for _, p in ipairs(spotsSent(m0)) do
    total = total + 1
    DONE[p[1] .. "," .. p[2]] = true
    if not (p[1] >= ax1 and p[1] <= ax2 and p[2] >= az1 and p[2] <= az2) then outside = outside + 1 end
  end
  for id, t in pairs(state.turtles) do if MAP.queue and MAP.queue.out and MAP.queue.out[id] then MAP.batchResult(id, true) end end
end
CHECK(MAP.queue == nil, "the survey finished")
CHECK(total >= n and outside == 0, "every spot inside the area (" .. total .. " sent, " .. outside .. " outside)")

-- a view completely outside: nothing
MAP.queue = nil
CHECK(MAP.queueSurvey(0, 0, 300, 300, 8, nil) == 0 and MAP.queue == nil, "a view outside the area: no survey")
-- small surveys (one turtle / SURVEY ALL small): outside spots left out
local sp = MAP.surveySpots(-5100, 10650, -4900, 10750, 8)
local bad = 0
for _, p in ipairs(sp) do if not MAP.inArea(p[1], p[2]) then bad = bad + 1 end end
CHECK(#sp > 0 and bad == 0, "small survey: only the part inside the area (" .. #sp .. " spots)")

-- auto-map: inside the area; a new area = a fresh start inside the new one
fleet(3)
DONE = {}
MAP.queue = nil
MAP.auto = { on = true, cursor = 0 }
MAP.autoTick()
CHECK(MAP.queue and MAP.queue.auto, "auto-map starts")
local m0 = #state.tOut
MAP.feedSurvey()
local first = spotsSent(m0)
CHECK(#first > 0, "auto-map hands out spots")
local inside = true
for _, p in ipairs(first) do if not MAP.inArea(p[1], p[2]) then inside = false end end
CHECK(inside, "auto-map spots are inside the area")
CONFIG.map.areaA, CONFIG.map.areaB = { x = 1000, y = 70, z = 1000 }, { x = 1300, y = 70, z = 1200 }
MAP.feedSurvey()
CHECK(MAP.queue == nil and MAP.auto.cursor == 0, "a new area: the old auto-map queue is dropped")
for _, t in pairs(state.turtles) do t.queueAt = nil end
MAP.autoTick()
for id in pairs(MAP.queue and MAP.queue.out or {}) do MAP.queue.out[id] = nil end
for _, t in pairs(state.turtles) do t.task, t.queueAt = "idle", nil end
m0 = #state.tOut
MAP.feedSurvey()
local second = spotsSent(m0)
inside = #second > 0
for _, p in ipairs(second) do if not MAP.inArea(p[1], p[2]) then inside = false end end
CHECK(inside, "auto-map goes on inside the new area")
MAP.spotDone = spotDone0

-- the MAP draws the area; tapping "Work area" clears it
state.page = "map"
local okD, errD = pcall(draw)
CHECK(okD, "the map draws with an area: " .. tostring(errD))
local wa = settingDef("Work area")
CHECK(wa and tostring(wa.get()):find("x"), "SETTINGS shows the area size: " .. tostring(wa and wa.get()))
local reset0 = resetSetting
resetSetting = function(path) setConfigPath(path, nil) end
if wa then wa.next(1) end
resetSetting = reset0
CHECK(MAP.area() == nil and wa.get() == "whole world", "one tap: the whole world again")

-- FACTORY setup by tapping: the chest chooser offers only EMPTY chests
local CH = { ["minecraft:chest_1"] = { { name = "minecraft:dirt", count = 3 } }, ["minecraft:chest_2"] = {},
             ["minecraft:barrel_7"] = {} }
local names0, has0, call0 = peripheral.getNames, peripheral.hasType, peripheral.call
peripheral.getNames = function() local l = {} for k in pairs(CH) do l[#l + 1] = k end return l end
peripheral.hasType = function(n, t) return CH[n] ~= nil and t == "inventory" end
peripheral.call = function(n, m) if m == "list" then return CH[n] end if m == "size" then return 27 end end
FACTORY.chest = nil
local fc = settingDef("Factory chest")
fc.next(1)
local firstPick = FACTORY.chest
fc.next(1)
local secondPick = FACTORY.chest
fc.next(1)
CHECK(firstPick and secondPick and firstPick ~= secondPick and firstPick ~= "minecraft:chest_1" and secondPick ~= "minecraft:chest_1",
      "the chest chooser cycles through the EMPTY chests only (" .. tostring(firstPick) .. ", " .. tostring(secondPick) .. ")")
CHECK(FACTORY.chest == firstPick, "and around again")
peripheral.getNames, peripheral.hasType, peripheral.call = names0, has0, call0
-- the builder chooser: automatic (the rescuer), then each turtle
fleet(2)
state.turtles[21].rescuerRole = true
FACTORY.builder = nil
local fb = settingDef("Builder turtle")
CHECK(tostring(fb.get()):find("rescuer"), "builder: the rescuer by default (" .. tostring(fb.get()) .. ")")
fb.next(1)
CHECK(FACTORY.builder == 21, "tap: the first turtle")
fb.next(1) fb.next(1)
CHECK(FACTORY.builder == nil, "around again: back to automatic")

-- MINING: a miner gone for 20+ min gets a DROP button
CONFIG.mining = { rowLength = 3 }
MINE.units = {
  [10] = { id = 10, role = "loader", dim = "overworld", label = "L", running = false, partner = 11, team = { 11 },
           lastSeen = os.clock(), seenEpoch = os.epoch("utc"), log = {}, queue = {}, fuel = 50000 },
  [11] = { id = 11, role = "miner", dim = "overworld", label = "Digger", leader = 10, partner = 10,
           lastSeen = os.clock() - 9999, seenEpoch = os.epoch("utc") - 3600000, log = {}, queue = {}, fuel = 9000 } }
state.page = "mining"
draw()
local dropBtn = false
for _, h in ipairs(hits or {}) do
  local a = h[6]
  if type(a) == "table" and a.kind == "minedrop" and a.name == "11" then dropBtn = true end
end
CHECK(dropBtn, "the MINING tab shows a DROP button for the lost miner")
local ok, msg = MINE.drop(11)
CHECK(ok and MINE.units[11] == nil, "DROP: " .. tostring(msg))
