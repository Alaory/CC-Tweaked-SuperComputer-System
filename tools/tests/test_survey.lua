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
