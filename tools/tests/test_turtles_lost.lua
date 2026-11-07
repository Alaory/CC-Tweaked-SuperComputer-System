-- Lost turtles: the old far survey order is converted and its turtles called
-- back; MISSING after the rescuer finds nothing; FORGET; a missing turtle that
-- reports again; after a crash the rescuer waits, then goes to the biggest group.
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
local SEQ = 0
local function report(id, m)
  SEQ = SEQ + 1
  m.n = os.epoch("utc") + SEQ
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
local function sentTo(id, from)
  local out = {}
  for i = from + 1, #state.tOut do if state.tOut[i].id == id then out[#out + 1] = state.tOut[i].msg.cmd end end
  return table.concat(out, ",")
end
local now = os.epoch("utc")

-- 1. an old row-by-row survey (saved by an older version): converted, far batches dropped, turtle called back
state.turtles = {
  [21] = { id = 21, label = "S21", log = {}, lastN = 0, fuel = 50000, pos = { x = HOME.x, y = 70, z = HOME.z }, task = "idle",
           lastSeen = os.clock(), home = { x = HOME.x, y = 70, z = HOME.z } },
  [22] = { id = 22, label = "S22", log = {}, lastN = 0, fuel = 3000, pos = { x = -15000, y = 120, z = 2000 }, task = "survey",
           lastSeen = os.clock() - 999, home = { x = HOME.x + 1, y = 70, z = HOME.z } } }
MAP.queue = { x1 = -25000, z1 = -5000, x2 = 15000, z2 = 25000, r = 8, step = 17, cols = 2353, rows = 1765, cursor = 5000,
              sent = 300, skipped = 0, redo = { { -19990, -4990 } }, out = { [22] = { { -19000, -4900 } } } }
local n0 = #state.tOut
MAP.feedSurvey()
local q = MAP.queue
CHECK(q.spiral and q.rect, "converted to the spiral")
CHECK(#(q.redo or {}) == 0 and not (q.out and q.out[22]), "old far spots dropped")
CHECK(state.turtles[22].recall, "the far turtle is called back")
local a = n0 and state.tOut[#state.tOut].msg.args
CHECK(a and math.abs(a[2] - HOME.x) + math.abs(a[3] - HOME.z) < 300, "new spots start at the base")
n0 = #state.tOut
report(22, { t = "status", task = "survey: going to spot 3/64" })    -- it comes back, still on the old job
CHECK(sentTo(22, n0):find("stop"), "STOP for the old far job")
n0 = #state.tOut
report(22, { t = "status", task = "idle", home = { x = HOME.x + 1, y = 70, z = HOME.z } })
CHECK(sentTo(22, n0):find("home"), "then home")
CHECK(not state.turtles[22].recall, "call-back done")

-- 2. MISSING: the rescuer was there and found nothing
state.turtles[1] = { id = 1, label = "Rescuer", log = {}, lastN = 0, fuel = 90000, pos = { x = HOME.x, y = 70, z = HOME.z },
                     task = "idle", lastSeen = os.clock(), seenEpoch = now, rescuerRole = true }
state.turtles[5] = { id = 5, label = "Scout5", log = {}, lastN = 0, fuel = 9000, pos = { x = -3000, y = 80, z = 9000 },
                     task = "survey", seenEpoch = now - 3600000, gear = "pickaxe, geo scanner" }
MAP.queue = nil
MAP.queueSurvey(-6000, 10000, -4000, 12000, 8, nil)
MAP.queue.out = { [5] = { { -3001, 9001 }, { -3018, 9001 } } }
report(1, { t = "rescued", target = 5, mode = "install", ok = false, msg = "turtle 5 not found within 24 blocks of -3000 80 9000", task = "idle" })
local key = TT.status(state.turtles[5])
CHECK(key == "missing", "status MISSING (" .. tostring(key) .. ")")
CHECK(#(MAP.queue.redo or {}) == 2, "its spots back in the queue")
TT.forget(5)
CHECK(state.turtles[5] == nil, "FORGET removes it")
CHECK(not (FILES["turtles.dat"] or ""):find("Scout5", 1, true), "and from the saved list")
state.turtles[7] = { id = 7, label = "Scout7", log = {}, lastN = 0, fuel = 9000, pos = { x = 0, y = 70, z = 0 }, seenEpoch = now - 3600000 }
TT.markMissing(state.turtles[7], "Rescuer")
report(7, { t = "status", task = "idle", pos = { x = 0, y = 70, z = 0 } })
CHECK(not state.turtles[7].missing and TT.status(state.turtles[7]) ~= "missing", "a missing turtle that reports is back")

-- 3. after a crash: many offline - wait first, then the biggest group
local function crash(silent)
  state.turtles = {}
  state.turtles[1] = { id = 1, label = "Rescuer", log = {}, lastN = 0, fuel = 90000, pos = { x = HOME.x, y = 70, z = HOME.z },
                       home = { x = HOME.x, y = 70, z = HOME.z }, task = "idle", lastSeen = os.clock(), seenEpoch = now,
                       rescuerRole = true, gear = "pickaxe" }
  for i = 1, 5 do
    state.turtles[10 + i] = { id = 10 + i, label = "P" .. i, log = {}, lastN = 0, fuel = 9000,
      pos = { x = -3000 + i * 17, y = 80, z = 9000 }, task = "survey", seenEpoch = now - silent * 1000 }
  end
  for i = 1, 2 do
    state.turtles[20 + i] = { id = 20 + i, label = "Q" .. i, log = {}, lastN = 0, fuel = 9000,
      pos = { x = 1000 + i * 300, y = 80, z = 2000 }, task = "survey", seenEpoch = now - silent * 1000 - 5000 }
  end
  TT.startedAt = os.clock() - 400
  local sent
  local rescue0 = TT.rescue
  TT.rescue = function(id) sent = state.turtles[id].label return true end
  TT.patrolTick()
  TT.rescue = rescue0
  return sent
end
CHECK(crash(300) == nil, "5 min after a crash: the rescuer waits")
local who = crash(900)
CHECK(who and who:sub(1, 1) == "P", "15 min: the rescuer goes to the group of 5 (" .. tostring(who) .. ")")
