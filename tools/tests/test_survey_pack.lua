-- PACK mode = RINGS: every turtle its own ring round the base, at its own pace. Faster than
-- free-running turtles, short hops, and NOBODY flies over spots another turtle just scanned (the
-- owner: "they move in mapped chunks in a line, only the one in front maps").
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

local function sim(packOn, patchy, overhead)
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
    if patchy and (math.floor(x / 300) + math.floor(z / 400)) % 2 == 0 then return true end   -- (mapped in patches)
    return DONE[x .. "," .. z] or math.max(math.abs(x - HOME.x), math.abs(z - HOME.z)) < 340
  end
  MAP.queue = nil
  MAP.queueSurvey(-9000, 7000, -1500, 15000, 8, nil)
  local worst, sum, cnt, done, travel, sky, over = 0, 0, 0, 0, 0, 0, 0
  local BY = {}
  -- grid spots on the way from (x, z) to (x2, z2) (x first, then z) scanned by ANOTHER turtle
  local function overflown(id, x, z, x2, z2)
    local n, st = 0, 17
    local function at(px, pz) local b = BY[px .. "," .. pz] if b and b ~= id then n = n + 1 end end
    local dx = (x2 > x) and st or -st
    if x ~= x2 then for px = x + dx, x2 - dx, dx do at(px, z) end end
    local dz = (z2 > z) and st or -st
    if z ~= z2 then for pz = z + dz, z2 - dz, dz do at(x2, pz) end end
    return n
  end
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
        W[o.id].time = -(overhead or 0)          -- (each hand-out: report idle, the base's tick, start, ask the base)
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
          if (t.pos.x - p[1]) % 17 == 0 and (t.pos.z - p[2]) % 17 == 0 then over = over + overflown(id, t.pos.x, t.pos.z, p[1], p[2]) end
          t.pos = { x = p[1], y = 70, z = p[2] }
          DONE[p[1] .. "," .. p[2]] = true
          BY[p[1] .. "," .. p[2]] = id
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
  return done, sum / cnt, worst, travel / math.max(1, done), sky / math.max(1, done), over / math.max(1, done)
end

local freeDone, freeAvg, _, freeTravel, _, freeOver = sim(false)
local packDone, packAvg, packWorst, packTravel, packSky, packOver = sim(true)
io.stderr:write(string.format("free: %d spots, %.0f blocks/spot, over %.2f | rings: %d spots, %.1f blocks/spot, %.2f sky trips/spot, over others' spots %.3f/spot, mate %.0f",
  freeDone, freeTravel, freeOver, packDone, packTravel, packSky, packOver, packAvg) .. "\n")
-- (the old ROUNDS managed 2125 here, 80 % of free-running; rings ~3700)
CHECK(packDone >= freeDone * 1.1, "rings are faster than free-running turtles (" .. packDone .. " vs " .. freeDone .. " spots)")
CHECK(packTravel < 20, string.format("rings: short hops, %.1f blocks per spot (17 = next spot)", packTravel))
CHECK(packSky < 0.05, string.format("rings: almost no sky-highway trips between spots (%.2f per spot)", packSky))
CHECK(packOver < 0.05, string.format("rings: nobody flies over spots another turtle scanned (%.3f per spot)", packOver))
-- SPOTS PER HAND-OUT (default 16, was 4): every hand-out costs the turtle 6-10 s in the game; with 6 s the
-- old 4 managed 3086 spots, 16 manage 3674
do
  local k0 = CONFIG.map.packSpots
  CONFIG.map.packSpots = 4
  local d4 = sim(true, false, 6)
  CONFIG.map.packSpots = k0
  local dDef = sim(true, false, 6)
  io.stderr:write("hand-outs cost 6 s: 4 a hand-out " .. d4 .. " spots, default " .. dDef .. "\n")
  CHECK(dDef >= d4 * 1.1, "more spots per hand-out = less waiting (" .. dDef .. " vs " .. d4 .. " with 4)")
end
-- the same over land mapped in PATCHES (where the old rounds put two turtles on one ring line)
local pDone, _, _, pTravel, _, pOver = sim(true, true)
local fDone = sim(false, true)
io.stderr:write(string.format("patchy: rings %d spots (free-running %d), %.1f blocks/spot, over %.3f/spot", pDone, fDone, pTravel, pOver) .. "\n")
-- (the old rounds: 0.405 here - two turtles on one ring line; what is left: crossing other rings
--  on the way out to a new ring)
CHECK(pOver < 0.1, string.format("patchy land: hardly anyone flies over spots another turtle scanned (%.3f per spot)", pOver))
CHECK(pDone >= fDone, "patchy land: rings at least as fast as free-running (" .. pDone .. " vs " .. fDone .. ")")

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

-- every turtle on its OWN ring, all of them working; a STOPPED turtle's ring goes to another
-- (started where that one left off); a helper with no ring left works a ring from its FAR end
do
  CONFIG.map.pack = true
  state.turtles, state.tOut = {}, {}
  for i = 1, 8 do
    local id = 40 + i
    state.turtles[id] = { id = id, label = "R" .. i, log = {}, lastN = 0, fuel = 50000,
      pos = { x = HOME.x + i, y = 70, z = HOME.z }, home = { x = HOME.x + i, y = 70, z = HOME.z },
      task = "idle", lastSeen = os.clock() }
  end
  local DONE = {}
  MAP.spotDone = function(x, z) return DONE[x .. "," .. z] or math.max(math.abs(x - HOME.x), math.abs(z - HOME.z)) < 300 end
  MAP.queue = nil
  MAP.queueSurvey(HOME.x - 2000, HOME.z - 2000, HOME.x + 2000, HOME.z + 2000, 8, nil)
  CLOCK = CLOCK + 2
  local n0 = #state.tOut
  MAP.feedSurvey()
  local q = MAP.queue
  local rings, got = {}, 0
  for id, rec in pairs(q.rr.own) do rings[rec.r] = (rings[rec.r] or 0) + 1 end
  local shared = 0
  for _, c in pairs(rings) do if c > 1 then shared = shared + 1 end end
  for i = n0 + 1, #state.tOut do if state.tOut[i].msg.cmd == "surveypts" then got = got + 1 end end
  CHECK(got == 8 and shared == 0, "all 8 turtles got spots, each on its own ring (" .. got .. ", " .. shared .. " rings shared)")
  -- turtle 41 is STOPPED: its ring (half done) goes to the next turtle that needs one
  local r41 = q.rr.own[41]
  r41.i = math.floor(r41.j / 2)
  state.turtles[41].held = true
  q.out[41] = nil
  for id in pairs(q.out) do q.out[id] = nil end
  q.rr.own[42].i = q.rr.own[42].j                              -- 42 finished its ring
  CLOCK = CLOCK + 20                                            -- (spots handed out < 15 s ago: not free yet)
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  MAP.feedSurvey()
  CHECK(q.rr.own[42] and q.rr.own[42].r == r41.r and q.rr.own[42].i > math.floor(r41.j / 2) - 1,
        "a STOPPED turtle's ring goes on with another turtle, from where it was")
  -- no ring left: a helper takes spots from the FAR end of a ring (walking towards its owner)
  q.rr.next = 99999
  for id in pairs(q.out) do q.out[id] = nil end
  q.rr.own[44].i = q.rr.own[44].j
  local j0 = {}
  for id, rec in pairs(q.rr.own) do j0[id] = rec.j end
  CLOCK = CLOCK + 20
  for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
  local m0 = #state.tOut
  MAP.feedSurvey()
  local help
  for i = m0 + 1, #state.tOut do if state.tOut[i].id == 44 and state.tOut[i].msg.cmd == "surveypts" then help = state.tOut[i] end end
  local shortened = false
  for id, rec in pairs(q.rr.own) do if id ~= 44 and j0[id] and rec.j < j0[id] then shortened = true end end
  CHECK(help and shortened, "with no ring left a free turtle helps from the far end of another's ring")
  MAP.queue = nil
end
