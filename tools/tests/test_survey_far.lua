-- THE SURVEY FAR OUT (the owner: "how come the mining turtles are faster? 200 chunks surveyed while 350 chunks mined -
-- something is broken with the survey turtles"; away 11 h: +217 chunks; screenshots: turtles on "sky highway" trips of
-- 1,500-3,600 blocks). The map is ~108K chunks: the survey's edge is ~2,400 blocks out, a ring there is ~1,130 spots
-- (~19,000 blocks round). Turtles get lost there (25 lost, server-crash copies) and leave their ring LOOSE.
-- Measured in the travel model of test_survey_pack (0.4 s a block, a sky trip over 48, 3 s a scan): 10 turtles, the
-- edge 2,400 out, one turtle lost every hour (a new one starts at the base 10 min later), 8 hours.
local HOME = { x = 1200, y = 70, z = -2400 }          -- (made-up)
CONFIG.drone.home = HOME
MAP.auto = { on = false }
CONFIG.map.pack = true
local R0 = 2400

local function orderNearest(pts, x, z)
  local out, left = {}, {}
  for i, p in ipairs(pts) do left[i] = p end
  while #left > 0 do
    local bi, bd = 1, math.huge
    for i, p in ipairs(left) do
      local d = math.abs(p[1] - x) + math.abs(p[2] - z)
      if d < bd then bi, bd = i, d end
    end
    local p = table.remove(left, bi)
    out[#out + 1] = p
    x, z = p[1], p[2]
  end
  return out
end

local function sim(seed, hours)
  math.randomseed(seed)
  state.turtles = {}
  state.tOut = {}
  local W, nextId = {}, 100
  local function newTurtle(x, z)
    nextId = nextId + 1
    local id = nextId
    state.turtles[id] = { id = id, label = "S" .. id, log = {}, lastN = 0, fuel = 100000, fuelMax = 100000,
      pos = { x = x, y = 70, z = z }, home = { x = HOME.x + id % 7, y = 70, z = HOME.z },
      task = "idle", lastSeen = CLOCK, seenEpoch = os.epoch("utc") }
    W[id] = { time = 0 }
    return id
  end
  -- 10 turtles already out at the edge, spread round it
  for i = 1, 10 do
    local a = (i / 10) * 2 * math.pi
    newTurtle(HOME.x + math.floor(math.cos(a) * R0), HOME.z + math.floor(math.sin(a) * R0))
  end
  local DONE = {}
  MAP.spotDone = function(x, z)
    if DONE[x .. "," .. z] then return true end
    local d = math.max(math.abs(x - HOME.x), math.abs(z - HOME.z))
    if d < R0 then return true end
    -- (patches mapped before, like a real server: whole 300 x 400 squares)
    return d < R0 + 600 and (math.floor(x / 300) + math.floor(z / 400)) % 3 == 0
  end
  MAP.queue = nil
  MAP.queueSurvey(HOME.x - 5000, HOME.z - 5000, HOME.x + 5000, HOME.z + 5000, 8, nil)
  local done, travel, longTrips, lost, firstTrips = 0, 0, 0, 0, 0
  local ticks = math.floor(hours * 3600 / 5)
  local waitNew = {}
  for tick = 1, ticks do
    local n0 = #state.tOut
    MAP.feedSurvey()
    for i = n0 + 1, #state.tOut do
      local o = state.tOut[i]
      if o.msg.cmd == "surveypts" and W[o.id] then
        local a, l = o.msg.args, {}
        for j = 2, #a, 2 do l[#l + 1] = { a[j], a[j + 1] } end
        local t = state.turtles[o.id]
        W[o.id].list, W[o.id].i, W[o.id].time = orderNearest(l, t.pos.x, t.pos.z), 0, -6
        t.task = "survey"
      end
    end
    for id, w in pairs(W) do
      local t = state.turtles[id]
      if w.list then
        w.time = w.time + 5
        while w.i < #w.list do
          local p = w.list[w.i + 1]
          local d = math.abs(p[1] - t.pos.x) + math.abs(p[2] - t.pos.z)
          local cost = d * 0.4 + 3 + (d > 48 and 160 * 0.4 or 0)
          if w.time < cost then break end
          w.time, w.i = w.time - cost, w.i + 1
          travel = travel + d
          if d > 1000 then
            if w.first then firstTrips = firstTrips + 1 else longTrips = longTrips + 1 end
          end
          w.first = nil
          t.pos = { x = p[1], y = 70, z = p[2] }
          DONE[p[1] .. "," .. p[2]] = true
          done = done + 1
        end
        if w.i >= #w.list then
          w.list, t.task, t.idleSince, w.time = nil, "idle", os.clock(), 0
          MAP.batchResult(id, true)
        end
      end
    end
    -- one turtle lost every hour (its ring is left LOOSE); a new one starts at the base 10 min later
    if tick % 720 == 360 then
      local ids = {}
      for id in pairs(W) do ids[#ids + 1] = id end
      table.sort(ids)
      local id = ids[math.random(1, #ids)]
      W[id] = nil
      local t = state.turtles[id]
      t.lastSeen, t.seenEpoch = CLOCK - 100000, os.epoch("utc") - 10 ^ 8
      lost = lost + 1
      waitNew[#waitNew + 1] = tick + 120
    end
    for i = #waitNew, 1, -1 do
      if tick >= waitNew[i] then table.remove(waitNew, i) W[newTurtle(HOME.x, HOME.z)].first = true end
    end
    CLOCK = CLOCK + 5
    for id in pairs(W) do state.turtles[id].lastSeen = CLOCK end
  end
  return done / hours, travel / math.max(1, done), longTrips, lost, firstTrips, #(MAP.queue.redo or {})
end

local rate, per, long, first, waiting = 0, 0, 0, 0, 0
for _, seed in ipairs({ 1, 2, 3 }) do
  local r, p, l, _, f, w = sim(seed, 8)
  rate, per, long, first, waiting = rate + r / 3, per + p / 3, long + l, first + f, waiting + w
end
-- the old dealing (a loose ring taken where its lost turtle stopped, a helper at a ring's far end, given-back spots
-- to ANY free turtle): 1935 spots an hour, 31.9 blocks a spot, 44 trips over 1,000 blocks (+22 from the base, not
-- counted: a new turtle has to get out). Nearest work first: ~2140, ~27.8, 2-4.
CHECK(long <= 12, string.format("no trips across the map between hand-outs: %d over 1,000 blocks in 24 turtle-fleet hours (the old dealing: 44)", long))
CHECK(rate >= 2050, string.format("the fleet surveys more far out: %.0f spots an hour (the old dealing: 1935)", rate))
CHECK(per <= 29.5, string.format("less flying per spot: %.1f blocks (the old dealing: 31.9)", per))
CHECK(waiting <= 3 * 40, string.format("given-back spots are not left behind: %d still waiting after 8 h (3 runs)", waiting))

-- a turtle that took another order a moment before answers "busy: ..." - that is no refusal of THESE spots (no 2-min
-- wait, "REFUSED its survey spots" on the list); a real refusal (facing unknown) still is
do
  local q = MAP.queue
  local id = next(state.turtles)
  local t = state.turtles[id]
  q.out = q.out or {}
  q.out[id], t.queueAt, t.surveyFail = { { HOME.x + 5000, HOME.z } }, os.clock(), nil
  MAP.batchResult(id, false, "busy: idle (press STOP first)")
  CHECK(t.surveyFail == nil, "'busy: ...' is not a refusal of the spots (" .. tostring(t.surveyFail and t.surveyFail.msg) .. ")")
  q.out[id], t.queueAt = { { HOME.x + 5000, HOME.z } }, os.clock()
  MAP.batchResult(id, false, "facing unknown")
  CHECK(t.surveyFail ~= nil, "a real refusal still keeps it out for 2 min")
end
