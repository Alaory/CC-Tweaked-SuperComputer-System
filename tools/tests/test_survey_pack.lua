-- PACK mode: 6 turtles at different speeds stay close together, and the
-- survey is not much slower than with free-running turtles.
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
local SPEED = { 1, 1, 0.8, 1, 0.6, 1 }

local function sim(packOn)
  CONFIG.map.pack = packOn
  state.turtles = {}
  local W = {}
  for i = 1, 6 do
    local id = 20 + i
    state.turtles[id] = { id = id, label = "S" .. i, log = {}, lastN = 0, fuel = 50000,
      pos = { x = HOME.x + i, y = 70, z = HOME.z }, home = { x = HOME.x + i, y = 70, z = HOME.z },
      task = "idle", lastSeen = os.clock() }
    W[id] = { speed = SPEED[i], i = 0, prog = 0 }
  end
  local DONE = {}
  MAP.spotDone = function(x, z) return DONE[x .. "," .. z] end
  MAP.queue = nil
  MAP.queueSurvey(-9000, 7000, -1500, 15000, 8, nil)
  local worst, sum, cnt, done = 0, 0, 0, 0
  for tick = 1, 1500 do
    local n0 = #state.tOut
    MAP.feedSurvey()
    for i = n0 + 1, #state.tOut do
      local o = state.tOut[i]
      if o.msg.cmd == "surveypts" then
        local a, l = o.msg.args, {}
        for j = 2, #a, 2 do l[#l + 1] = { a[j], a[j + 1] } end
        W[o.id].list, W[o.id].i, W[o.id].prog = l, 0, 0
        state.turtles[o.id].task = "survey"
      end
    end
    for id, w in pairs(W) do
      local t = state.turtles[id]
      if w.list then
        w.prog = w.prog + w.speed * 0.25
        while w.prog >= 1 and w.i < #w.list do
          w.prog, w.i = w.prog - 1, w.i + 1
          local p = w.list[w.i]
          t.pos = { x = p[1], y = 70, z = p[2] }
          DONE[p[1] .. "," .. p[2]] = true
          done = done + 1
        end
        if w.i >= #w.list then
          w.list, t.task, t.idleSince = nil, "idle", os.clock()
          MAP.batchResult(id, true)
        end
      end
    end
    if tick > 20 then
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
  return done, sum / cnt, worst
end

local freeDone, freeAvg = sim(false)
local packDone, packAvg, packWorst = sim(true)
CHECK(packAvg < 40, string.format("pack: nearest team mate %.0f blocks on average (should be < 40)", packAvg))
CHECK(packWorst < 200, "pack: never more than 200 blocks from the nearest (" .. packWorst .. ")")
CHECK(freeAvg > packAvg * 2, string.format("free-running turtles spread out more (%.0f vs %.0f)", freeAvg, packAvg))
CHECK(packDone >= freeDone * 0.7, "pack keeps >= 70% of the speed (" .. packDone .. " vs " .. freeDone .. " spots)")

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
