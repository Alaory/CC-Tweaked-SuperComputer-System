-- Surveys: spiral from the base, inside the area, every spot exactly once,
-- progress only goes up, a held batch is never overwritten, the pack stays
-- together. (run by tools/run_tests.py through tools/preview/run.lua)
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
local function fleet(n, fuel)
  state.turtles = {}
  for i = 1, n do
    local id = 20 + i
    state.turtles[id] = { id = id, label = "S" .. i, log = {}, lastN = 0, fuel = fuel or 50000,
      pos = { x = HOME.x + i, y = 70, z = HOME.z }, home = { x = HOME.x + i, y = 70, z = HOME.z },
      task = "idle", lastSeen = os.clock() }
  end
end
local function batchesSent(from)
  local out = {}
  for i = from + 1, #state.tOut do
    local o = state.tOut[i]
    if o.msg.cmd == "surveypts" then
      local a, l = o.msg.args, {}
      for j = 2, #a, 2 do l[#l + 1] = { a[j], a[j + 1] } end
      out[#out + 1] = { id = o.id, spots = l }
    end
  end
  return out
end

-- 1. zoomed all the way out: the first spots are next to the base, inside the border
fleet(3)
local n = MAP.queueSurvey(-40000, -30000, 40000, 30000, 8, nil)
local q = MAP.queue
CHECK(q.x1 >= -20000 and q.x2 <= 20000 and q.z1 >= -20000 and q.z2 <= 20000, "area clamped to the world border")
CHECK(n > 5000000 and n < 6000000, "spot count of the whole world (" .. n .. ")")
local n0 = #state.tOut
MAP.feedSurvey()
local b = batchesSent(n0)
CHECK(#b > 0, "a batch goes out at once")
for _, x in ipairs(b) do
  local p = x.spots[1]
  CHECK(math.abs(p[1] - HOME.x) + math.abs(p[2] - HOME.z) < 300, "first spot near the base (" .. p[1] .. " " .. p[2] .. ")")
end

-- 2. an area away from the base: every spot exactly once, inside, progress up
fleet(3)
local DONE = {}
local spotDone0 = MAP.spotDone
MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
local X1, Z1, X2, Z2 = -4300, 10600, -3700, 11050
MAP.queue = nil                -- (a new survey keeps the old one's open batches - start clean)
local total = MAP.queueSurvey(X1, Z1, X2, Z2, 8, nil)
local handed, twice, outside, lastProg, back = 0, 0, 0, -1, false
for round = 1, 600 do
  CLOCK = CLOCK + 20
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  local m0 = #state.tOut
  MAP.feedSurvey()
  if not MAP.queue then break end
  for _, x in ipairs(batchesSent(m0)) do
    for _, p in ipairs(x.spots) do
      if p[1] < X1 or p[1] > X2 or p[2] < Z1 or p[2] > Z2 then outside = outside + 1 end
      if DONE[p[1] .. "," .. p[2]] then twice = twice + 1 end
      DONE[p[1] .. "," .. p[2]] = true
      handed = handed + 1
    end
    state.turtles[x.id].task = "survey"
  end
  -- the turtles finish their batches and say so
  for id, t in pairs(state.turtles) do
    if t.task == "survey" then t.task = "idle" MAP.batchResult(id, true) end
  end
  local f = MAP.surveyProgress()
  if f then
    if f < lastProg then back = true end
    lastProg = f
  end
end
CHECK(MAP.queue == nil, "the survey finished")
CHECK(handed == total, "every spot handed out (" .. handed .. " of " .. total .. ")")
CHECK(twice == 0, "no spot twice (" .. twice .. ")")
CHECK(outside == 0, "no spot outside the area (" .. outside .. ")")
CHECK(not back, "progress never goes back")

-- 2b. the same with PACK (rings) turned off and on again in the middle (rings handed out):
--     still every spot exactly once
fleet(4)
DONE = {}
MAP.queue = nil
total = MAP.queueSurvey(X1, Z1, X2, Z2, 8, nil)
handed, twice, outside = 0, 0, 0
local switched = 0
for round = 1, 900 do
  CLOCK = CLOCK + 20
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  if round % 2 == 0 then
    CONFIG.map.pack = (CONFIG.map.pack == false) and nil or false
    switched = switched + 1
  end
  local m0 = #state.tOut
  MAP.feedSurvey()
  if not MAP.queue then break end
  for _, x in ipairs(batchesSent(m0)) do
    for _, p in ipairs(x.spots) do
      if p[1] < X1 or p[1] > X2 or p[2] < Z1 or p[2] > Z2 then outside = outside + 1 end
      if DONE[p[1] .. "," .. p[2]] then twice = twice + 1 end
      DONE[p[1] .. "," .. p[2]] = true
      handed = handed + 1
    end
    state.turtles[x.id].task = "survey"
  end
  for id, t in pairs(state.turtles) do
    if t.task == "survey" then t.task = "idle" MAP.batchResult(id, true) end
  end
end
CONFIG.map.pack = nil
CHECK(switched > 2, "pack mode was switched during the survey (" .. switched .. ", " .. total .. " spots)")
CHECK(MAP.queue == nil, "pack on/off: the survey finished")
CHECK(handed == total, "pack on/off: every spot handed out (" .. handed .. " of " .. total .. ")")
CHECK(twice == 0, "pack on/off: no spot twice (" .. twice .. ")")
CHECK(outside == 0, "pack on/off: no spot outside the area (" .. outside .. ")")

-- 2c. SURVEY: ALL on a small area uses EVERY free turtle (the owner: "it seems to send half
--     of the turtles") - pack on and off: 10 turtles, ~30 spots -> all 10 get a share
for _, packOn in ipairs({ true, false }) do
  CONFIG.map.pack = packOn
  fleet(10)
  DONE = {}
  MAP.queue = nil
  MAP.queueSurvey(-9000, 7000, -1500, 15000, 8, nil)       -- (a big one running: auto-map like)
  local q = MAP.queue
  q.cursor = q.cols * q.rows                               -- (its spiral done: only the new area is left)
  local n = MAP.addSurvey(-5000, 10000, -4900, 10085, 8)
  local m0 = #state.tOut
  MAP.feedSurvey()
  local got, most = 0, 0
  for _, x in ipairs(batchesSent(m0)) do
    got = got + 1
    most = math.max(most, #x.spots)
  end
  CHECK(got == 10 and most <= math.ceil(n / 10) + 1, (packOn and "pack" or "no pack") .. ": " .. n ..
        " spots shared by all 10 free turtles (" .. got .. " got some, at most " .. most .. " each)")
end
CONFIG.map.pack = nil
MAP.queue = nil

-- 2d. PACK + a long given-back list scattered over the map: a round stays short (2 x packSpots
--     each) and takes the spots NEAREST the pack - 64 scattered spots each kept the whole pack
--     waiting for turtles crossing the map ("now turtles dont survey")
CONFIG.map.pack = true
fleet(10)
DONE = {}
MAP.queue = nil
MAP.queueSurvey(-9000, 7000, -1500, 15000, 8, nil)
local q5 = MAP.queue
q5.redo = {}
for i = 1, 300 do q5.redo[#q5.redo + 1] = { HOME.x + (i % 30) * 17 + ((i > 150) and 3000 or 0), HOME.z + math.floor(i / 30) * 17 } end
local m5 = #state.tOut
MAP.feedSurvey()
local most5, far5, got5 = 0, 0, 0
for _, x in ipairs(batchesSent(m5)) do
  got5 = got5 + 1
  most5 = math.max(most5, #x.spots)
  for _, p in ipairs(x.spots) do if p[1] > HOME.x + 2000 then far5 = far5 + 1 end end
end
local K5 = tonumber(CONFIG.map.packSpots) or 4
CHECK(got5 == 10 and most5 <= 2 * K5, "pack + 300 given-back spots: all 10 get some, at most " .. 2 * K5 .. " each (" .. got5 .. ", " .. most5 .. ")")
CHECK(far5 == 0, "the round takes the spots nearest the pack, not the far ones (" .. far5 .. " far)")
CHECK(#q5.redo == 300 - 10 * 2 * K5, "the rest stay in the list for later (" .. #q5.redo .. ")")
CONFIG.map.pack = nil
MAP.queue = nil

-- 2e. the owner's game: a big survey started right after STOP ALL / HOME - 1 turtle free, the
--     map around the base already done (thousands of spots: looking past it takes several calls),
--     then 11 more turtles come back: every one gets its OWN ring ("1 sent" for ages before).
CONFIG.map.pack = true
fleet(12)
for id, t in pairs(state.turtles) do if id ~= 21 then t.task = "going home" end end
local DONE6 = {}
MAP.spotDone = function(x, z) return DONE6[x .. "," .. z] or math.max(math.abs(x - HOME.x), math.abs(z - HOME.z)) < 1200 end
MAP.queue = nil
MAP.queueSurvey(HOME.x - 3400, HOME.z - 3600, HOME.x + 3400, HOME.z + 3600, 8, nil)
local q6 = MAP.queue
local function feed6()
  CLOCK = CLOCK + 3
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  local m = #state.tOut
  MAP.feedSurvey()
  local got = batchesSent(m)
  for _, x in ipairs(got) do
    for _, p in ipairs(x.spots) do DONE6[p[1] .. "," .. p[2]] = true end
    state.turtles[x.id].task = "idle"
    state.turtles[x.id].queueAt = CLOCK - 100
    MAP.batchResult(x.id, true)
  end
  return got
end
-- (while it looks past the mapped land, the progress moves and the panel can say so)
local p0 = MAP.queuePos(q6)
feed6()
CHECK(q6.rr and (MAP.queuePos(q6) > p0 or q6.rr.own[21]), "looking for rings: the progress moves (" ..
      tostring(p0) .. " -> " .. tostring(MAP.queuePos(q6)) .. ")")
for _ = 1, 40 do feed6() if q6.rr.own[21] then break end end
CHECK(q6.rr.own[21] ~= nil, "the 1 free turtle got a ring")
for _, t in pairs(state.turtles) do t.task = "idle" end          -- the others are back
local most, seen = 0, {}
for _ = 1, 60 do
  local got = feed6()
  for _, x in ipairs(got) do seen[x.id] = true end
  most = math.max(most, #got)
  if most >= 12 then break end
end
local nSeen = 0
for _ in pairs(seen) do nSeen = nSeen + 1 end
local rings6, n6 = {}, 0
for _, rec in pairs(q6.rr.own) do if not rings6[rec.r] then rings6[rec.r] = true n6 = n6 + 1 end end
CHECK(n6 == 12, "12 turtles on 12 different rings (" .. n6 .. ")")
CHECK(most >= 10 and nSeen == 12, "rounds use (nearly) every turtle again (" .. most .. " in a round, " .. nSeen .. " in all)")
MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
CONFIG.map.pack = nil
MAP.queue = nil

-- 2f. the owner's game: SURVEY: ALL after an old one-turtle survey left ONE spot, over land
--     that is mapped in patches. Before: round 1 = that one spot for one turtle (the pack waited
--     for it - "when I hit SURVEY: ALL only one turtle goes"), then rounds of 1 spot for 3 .. 13
--     of 30 turtles. Now every round uses (nearly) all 30, the lone spot is not waited for.
CONFIG.map.pack = true
fleet(30)
local DONE7 = {}
MAP.spotDone = function(x, z)
  if DONE7[x .. "," .. z] then return true end
  local dx, dz = x - HOME.x, z - HOME.z
  return math.max(math.abs(dx), math.abs(dz)) < 1200 or (dx > 0 and dz > 0) or ((math.floor(x / 500) + math.floor(z / 700)) % 3 == 0)
end
MAP.queue = nil
MAP.queueSurvey(HOME.x - 1000, HOME.z - 1000, HOME.x + 3000, HOME.z + 3000, 8, { 21 })
MAP.queue.redo = { { HOME.x - 1300, HOME.z + 17 } }
MAP.queueSurvey(HOME.x - 800, HOME.z - 600, HOME.x + 2656, HOME.z + 3080, 8, nil)
local q7 = MAP.queue
local fewest, dup7, seen7 = 99, 0, {}
for round = 1, 12 do
  CLOCK = CLOCK + 3
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  local m = #state.tOut
  MAP.feedSurvey()
  local got = batchesSent(m)
  fewest = math.min(fewest, #got)
  for _, x in ipairs(got) do
    for _, p in ipairs(x.spots) do
      local key = p[1] .. "," .. p[2]
      if seen7[key] then dup7 = dup7 + 1 end
      seen7[key], DONE7[key] = true, true
    end
  end
  if round == 1 then
    local lone
    for _, x in ipairs(got) do
      for _, p in ipairs(x.spots) do if p[1] == HOME.x - 1300 and p[2] == HOME.z + 17 then lone = x.id end end
    end
    local inWave = false
    for _, id in ipairs(q7.wave and q7.wave.ids or {}) do if id == lone then inWave = true end end
    CHECK(lone and not inWave, "the old survey's lone spot goes out, and the pack does not wait for it (" ..
          tostring(lone) .. ", in the wave: " .. tostring(inWave) .. ")")
  end
  for id, t in pairs(state.turtles) do
    if q7.out and q7.out[id] then t.queueAt = CLOCK - 100 MAP.batchResult(id, true) end
  end
end
CHECK(fewest >= 27, "SURVEY: ALL over patchy land: every round uses (nearly) all 30 turtles (fewest " .. fewest .. ")")
CHECK(dup7 == 0, "no spot handed out twice (" .. dup7 .. ")")
MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
CONFIG.map.pack = nil
MAP.queue = nil

-- 2g. the owner's game: a round goes out while half the fleet is busy (coming home, refuelling).
--     Those that turn free WHILE the round runs join it at once with a short share - before they
--     waited for the whole round ("waiting for the rest of the pack" for minutes while the others
--     flew 2,000 blocks), then the first half waited for THEM: half the fleet worked at a time.
CONFIG.map.pack = true
fleet(20)
for id, t in pairs(state.turtles) do if id > 30 then t.task = "going home" end end
local DONE8 = {}
MAP.spotDone = function(x, z) return DONE8[x .. "," .. z] or math.max(math.abs(x - HOME.x), math.abs(z - HOME.z)) < 600 end
MAP.queue = nil
MAP.queueSurvey(HOME.x - 3000, HOME.z - 3000, HOME.x + 3000, HOME.z + 3000, 8, nil)
local q8 = MAP.queue
local function feed8()
  CLOCK = CLOCK + 3
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  local m = #state.tOut
  MAP.feedSurvey()
  return batchesSent(m)
end
local first = feed8()
for _ = 1, 20 do if #first > 0 then break end first = feed8() end
CHECK(#first == 10, "round 1: the 10 free turtles (" .. #first .. ")")
local seen8 = {}
for _, x in ipairs(first) do for _, p in ipairs(x.spots) do seen8[p[1] .. "," .. p[2]] = true end end
for id, t in pairs(state.turtles) do if id > 30 then t.task = "idle" end end    -- the others are back
local late8 = feed8()
local most8, dup8 = 0, 0
for _, x in ipairs(late8) do
  most8 = math.max(most8, #x.spots)
  for _, p in ipairs(x.spots) do
    if seen8[p[1] .. "," .. p[2]] then dup8 = dup8 + 1 end
    seen8[p[1] .. "," .. p[2]] = true
  end
end
CHECK(#late8 == 10, "the 10 that came back join the running round at once (" .. #late8 .. ")")
CHECK(most8 <= 6 and dup8 == 0, "with a short share, no spot twice (most " .. most8 .. ", twice " .. dup8 .. ")")
local again = feed8()
CHECK(#again == 0, "nobody gets more while it still holds spots (" .. #again .. ")")
MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
CONFIG.map.pack = nil
MAP.queue = nil

-- 2h. a turtle that REFUSES its spots at once (facing unknown ...) looked like "the base sent it
--     nothing" ("only half get sent"): it is kept out for 2 min with the reason on the TURTLES
--     list, and the SURVEY: ALL report ~20 s after the press names it. Pressing SURVEY: ALL on a
--     small area again does not add its spots twice.
CONFIG.map.pack = true
fleet(6)
local DONE9 = {}
MAP.spotDone = function(x, z) return DONE9[x .. "," .. z] or math.max(math.abs(x - HOME.x), math.abs(z - HOME.z)) < 300 end
MAP.queue = nil
local popups = {}
local oldPopup = setPopup
setPopup = function(title, msg, col) popups[#popups + 1] = title .. ": " .. tostring(msg) end
MAP.queueSurvey(HOME.x - 2000, HOME.z - 2000, HOME.x + 2000, HOME.z + 2000, 8, nil)
if MAP.pressStart then MAP.pressStart() end
local function feed9()
  CLOCK = CLOCK + 2
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  local m = #state.tOut
  MAP.feedSurvey()
  return batchesSent(m)
end
local r1 = feed9()
CHECK(#r1 == 6, "all 6 get spots (" .. #r1 .. ")")
-- S3 refuses at once; the rest work on them
CLOCK = CLOCK + 1
MAP.batchResult(23, false, "position/facing unknown - use GPS LOCATE")
local again = 0
for _ = 1, 15 do for _, x in ipairs(feed9()) do if x.id == 23 then again = again + 1 end end end
CHECK(again == 0, "a turtle that refused its spots gets none for 2 min (" .. again .. " batches)")
local why = TT.idleWhy(state.turtles[23]) or ""
CHECK(why:find("REFUSED", 1, true) and why:find("facing unknown", 1, true), "its card says why: " .. why)
local rep
for _, p in ipairs(popups) do if p:find("SURVEY: ALL", 1, true) then rep = p end end
CHECK(rep and rep:find("5 of 6", 1, true) and rep:find("facing unknown", 1, true), "the press report names it: " .. tostring(rep))
setPopup = oldPopup
-- small area pressed twice: no spot twice in the list
MAP.queue = nil
fleet(3)
for _, t in pairs(state.turtles) do t.task = "busy" end
MAP.queueSurvey(HOME.x - 2000, HOME.z - 2000, HOME.x + 2000, HOME.z + 2000, 8, nil)
MAP.addSurvey(HOME.x + 400, HOME.z + 400, HOME.x + 600, HOME.z + 600, 8)
local n1 = #MAP.queue.redo
MAP.addSurvey(HOME.x + 400, HOME.z + 400, HOME.x + 600, HOME.z + 600, 8)
CHECK(n1 > 0 and #MAP.queue.redo == n1, "pressed twice: the spots are in the list once (" .. n1 .. " -> " .. #MAP.queue.redo .. ")")
MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
CONFIG.map.pack = nil
MAP.queue = nil

-- 3. a turtle that still holds a batch (idle, no result yet) is not given a new one
--    (without pack mode - the pack waits for its members anyway)
CONFIG.map.pack = false
fleet(1)
DONE = {}
MAP.queue = nil
MAP.queueSurvey(-6000, 10000, -4000, 12000, 8, nil)
MAP.feedSurvey()
local q3 = MAP.queue
local first = q3.out and q3.out[21]
CHECK(first ~= nil, "the turtle got a batch")
CLOCK = CLOCK + 20                                   -- idle 20 s: still counts as its batch
state.turtles[21].lastSeen = CLOCK
local m0 = #state.tOut
MAP.feedSurvey()
CHECK(#batchesSent(m0) == 0 and q3.out[21] == first, "no new batch over a held one")
CLOCK = CLOCK + 40                                   -- idle > 30 s: taken back, then a new one
state.turtles[21].lastSeen = CLOCK
MAP.feedSurvey()
CHECK(#(q3.redo or {}) > 0 or (q3.out[21] and q3.out[21] ~= first), "the held batch is taken back after 30 s")
CONFIG.map.pack = nil

-- 4. silent for 10 min: its spots go to the others
fleet(2)
MAP.queue = nil
MAP.queueSurvey(-6000, 10000, -4000, 12000, 8, nil)
MAP.feedSurvey()
local q4 = MAP.queue
local gone = next(q4.out or {})
CHECK(gone ~= nil, "a batch went out")
state.turtles[gone].lastSeen = CLOCK - 9999
state.turtles[gone].seenEpoch = os.epoch("utc") - 700000
MAP.feedSurvey()
CHECK(q4.out[gone] == nil, "the silent turtle's batch was taken back")
MAP.spotDone = spotDone0
