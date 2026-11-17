-- PACK mode: 6 turtles at different speeds stay close together, and the
-- survey is not much slower than with free-running turtles.
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
local SPEED = { 1, 1, 0.8, 1, 0.6, 1 }

-- The turtles are modelled like node.lua: spots in nearest-first order (orderNearest),
-- a hop over 48 blocks (CONFIG.skyMinDist) climbs to the sky highway (Y 150) and comes
-- down again, 0.4 s per block, 3 s per scan. (The old pack dealt a round's spots IN
-- TURN along one line: 51-block hops over the others' spots = a sky trip per spot, the
-- turtles following each other in a line - the owner saw only the front one scan.)
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

local function sim(packOn)
  CONFIG.map.pack = packOn
  state.turtles = {}
  local W = {}
  for i = 1, 6 do
    local id = 20 + i
    state.turtles[id] = { id = id, label = "S" .. i, log = {}, lastN = 0, fuel = 50000,
      pos = { x = HOME.x + i, y = 70, z = HOME.z }, home = { x = HOME.x + i, y = 70, z = HOME.z },
      task = "idle", lastSeen = os.clock() }
    W[id] = { speed = SPEED[i], i = 0, time = 0 }
  end
  -- (the land around the base is mapped already, like on a real server: the
  --  tiny rings next to the base go by in a few rounds - not what is measured)
  local DONE = {}
  MAP.spotDone = function(x, z)
    return DONE[x .. "," .. z] or math.max(math.abs(x - HOME.x), math.abs(z - HOME.z)) < 340
  end
  MAP.queue = nil
  MAP.queueSurvey(-9000, 7000, -1500, 15000, 8, nil)
  local worst, sum, cnt, done, travel, sky = 0, 0, 0, 0, 0, 0
  for tick = 1, 1500 do
    local n0 = #state.tOut
    MAP.feedSurvey()
    for i = n0 + 1, #state.tOut do
      local o = state.tOut[i]
      if o.msg.cmd == "surveypts" then
        local a, l = o.msg.args, {}
        for j = 2, #a, 2 do l[#l + 1] = { a[j], a[j + 1] } end
        local t = state.turtles[o.id]
        W[o.id].list, W[o.id].i = orderNearest(l, t.pos.x, t.pos.z), 0
        t.task = "survey"
      end
    end
    for id, w in pairs(W) do
      local t = state.turtles[id]
      if w.list then
        w.time = w.time + 5 * w.speed                -- 5 s per tick
        while w.i < #w.list do
          local p = w.list[w.i + 1]
          local d = math.abs(p[1] - t.pos.x) + math.abs(p[2] - t.pos.z)
          local cost = d * 0.4 + 3 + (d > 48 and 160 * 0.4 or 0)
          if w.time < cost then break end
          w.time, w.i = w.time - cost, w.i + 1
          travel = travel + d
          if d > 48 then sky = sky + 1 end
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
    if tick > 250 then                             -- (after the first trip out: ~650 blocks, slow ones too)
      for id, t in pairs(state.turtles) do
        local best
        for oid, o in pairs(state.turtles) do
          if oid ~= id then
            local d = math.max(math.abs(o.pos.x - t.pos.x), math.abs(o.pos.z - t.pos.z))
            if not best or d < best then best = d end
          end
        end
        worst, sum, cnt = math.max(worst, best), sum + best, cnt + 1
      end
    end
    CLOCK = CLOCK + 5
    for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  end
  return done, sum / cnt, worst, travel / math.max(1, done), sky / math.max(1, done)
end

local freeDone, freeAvg, _, freeTravel = sim(false)
local packDone, packAvg, packWorst, packTravel, packSky = sim(true)
io.stderr:write(string.format("free: %d spots, %.0f blocks/spot, mate %.0f | pack: %d spots, %.1f blocks/spot, %.2f sky trips/spot, mate %.0f (worst %d)",
  freeDone, freeTravel, freeAvg, packDone, packTravel, packSky, packAvg, packWorst) .. "\n")
CHECK(packAvg < 40, string.format("pack: nearest team mate %.0f blocks on average (should be < 40)", packAvg))
CHECK(packWorst < 200, "pack: never more than 200 blocks from the nearest (" .. packWorst .. ")")
CHECK(freeAvg > packAvg * 2, string.format("free-running turtles spread out more (%.0f vs %.0f)", freeAvg, packAvg))
-- (75 %: free-running turtles got faster when their batches were cut evenly - dealEven; the
--  old in-turn pack dealing managed 13 %)
CHECK(packDone >= freeDone * 0.75, "pack keeps >= 75% of the speed (" .. packDone .. " vs " .. freeDone .. " spots)")
CHECK(packTravel < 22, string.format("pack: short hops, %.1f blocks per spot (17 = next spot; spots dealt in turn: ~50)", packTravel))
CHECK(packSky < 0.05, string.format("pack: almost no sky-highway trips between spots (%.2f per spot)", packSky))

-- the pack's pieces: every turtle's spots of one round lie together, side by side
-- with the others' (none of its hops passes over another turtle's spot)
do
  CONFIG.map.pack = true
  state.turtles, state.tOut = {}, {}
  for i = 1, 5 do
    local id = 60 + i
    state.turtles[id] = { id = id, label = "P" .. i, log = {}, lastN = 0, fuel = 50000,
      pos = { x = HOME.x + 900, y = 70, z = HOME.z + i * 17 }, home = { x = HOME.x + i, y = 70, z = HOME.z },
      task = "idle", lastSeen = os.clock() }
  end
  MAP.spotDone = function(x, z) return math.max(math.abs(x - HOME.x), math.abs(z - HOME.z)) < 800 end
  MAP.queue = nil
  MAP.queueSurvey(HOME.x - 3000, HOME.z - 3000, HOME.x + 3000, HOME.z + 3000, 8, nil)
  for _ = 1, 20 do
    MAP.feedSurvey()
    if MAP.queue.out and next(MAP.queue.out) then break end
  end
  local q, mine, all = MAP.queue, {}, {}
  for id, l in pairs(q.out or {}) do
    mine[id] = l
    for _, p in ipairs(l) do all[#all + 1] = { p = p, id = id } end
  end
  local n, between = 0, 0
  for id, l in pairs(mine) do
    n = n + 1
    local o = orderNearest(l, state.turtles[id].pos.x, state.turtles[id].pos.z)
    for c = 2, #o do
      local a, b = o[c - 1], o[c]
      CHECK(math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) <= 34, "a turtle's spots lie together (" ..
            a[1] .. " " .. a[2] .. " -> " .. b[1] .. " " .. b[2] .. ")")
      for _, x in ipairs(all) do
        if x.id ~= id and math.min(a[1], b[1]) <= x.p[1] and x.p[1] <= math.max(a[1], b[1])
           and math.min(a[2], b[2]) <= x.p[2] and x.p[2] <= math.max(a[2], b[2]) then between = between + 1 end
      end
    end
  end
  CHECK(n == 5, "every turtle of the pack got spots (" .. n .. ")")
  CHECK(between == 0, "no hop passes over another turtle's spot (" .. between .. ")")
  MAP.queue = nil
end

-- after a BASE RESTART the saved round time (q.wave.t) is ahead of the new clock:
-- the "do not wait for a hung turtle longer than packWait" limit must still work
do
  CONFIG.map.pack = true
  state.turtles, state.tOut = {}, {}
  for i = 1, 2 do
    local id = 40 + i
    state.turtles[id] = { id = id, label = "R" .. i, log = {}, lastN = 0, fuel = 50000,
      pos = { x = HOME.x + i, y = 70, z = HOME.z }, home = { x = HOME.x + i, y = 70, z = HOME.z },
      task = "idle", lastSeen = os.clock() }
  end
  local DONE = {}
  MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
  MAP.queue = nil
  MAP.queueSurvey(-9000, 7000, -1500, 15000, 8, nil)
  local got = { [41] = 0, [42] = 0 }
  local function feed()
    local n0 = #state.tOut
    MAP.feedSurvey()
    for i = n0 + 1, #state.tOut do
      local o = state.tOut[i]
      if o.msg.cmd == "surveypts" then
        got[o.id] = got[o.id] + 1
        state.turtles[o.id].task = "survey"
        if o.id == 41 then                                 -- 41 finishes its spots at once
          local a = o.msg.args
          for j = 2, #a, 2 do DONE[a[j] .. "," .. a[j + 1]] = true end
          state.turtles[41].task, state.turtles[41].idleSince = "idle", os.clock()
          MAP.batchResult(41, true)
        end
      end
    end
  end
  for _ = 1, 10 do CLOCK = CLOCK + 2 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end feed() end
  CHECK(got[41] >= 1 and got[42] >= 1 and MAP.queue.wave, "a pack round is out (" .. got[41] .. "/" .. got[42] .. ")")
  local before = got[41]
  MAP.queue.wave.t = os.clock() + 500000                   -- (saved before the restart)
  for _ = 1, 200 do CLOCK = CLOCK + 2 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end feed() end
  CHECK(got[41] > before, "restart: the free turtle gets work again after packWait (42 hangs) - got " .. (got[41] - before))
  MAP.queue = nil
end
