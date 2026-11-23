-- SURVEY STATS + LOST REPORT (the owner: "3 days and only ~1000 chunks", "the amount of lost turtles"): measured
-- from what the turtles report - where their time goes, scans an hour - and one line per offline turtle.
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
local SEQ = 0
local function report(id, extra)
  SEQ = SEQ + 1
  local m = { t = "status", n = os.epoch("utc") + 1000 + SEQ, label = "Scout" .. id, task = "idle", fuel = 5000,
              pos = { x = HOME.x + 2400, y = 70, z = HOME.z }, home = { x = HOME.x, y = 68, z = HOME.z } }
  for k, v in pairs(extra or {}) do m[k] = v end
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
local function scan(id)
  SEQ = SEQ + 1
  local m = { t = "scan", n = os.epoch("utc") + 1000 + SEQ, x = HOME.x + 2400, z = HOME.z, y = 70, r = 8, cols = "",
              task = state.turtles[id] and state.turtles[id].task }   -- (every message carries the task)
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
state.turtles, state.tOut = {}, {}
TT.statSince = os.clock()
report(41, { task = "survey 1/4" })
for i = 1, 10 do CLOCK = CLOCK + 10 report(41, { task = "survey " .. math.min(4, i) .. "/4" }) if i % 3 == 0 then scan(41) end end
for _ = 1, 5 do CLOCK = CLOCK + 10 report(41, { task = "sky highway to 1 2" }) end
for _ = 1, 3 do CLOCK = CLOCK + 10 report(41, { task = "planning a route" }) end
CLOCK = CLOCK + 900                                  -- silent: offline
report(41, { task = "idle" })
local s = state.turtles[41].stat
CHECK(s and s.scans >= 3, "scans counted: " .. tostring(s and s.scans))
CHECK(s and math.abs(s.survey - 100) <= 11, "time surveying ~100 s: " .. tostring(s and s.survey))
CHECK(s and math.abs(s.sky - 50) <= 11, "time on long trips ~50 s: " .. tostring(s and s.sky))
CHECK(s and math.abs(s.way - 30) <= 11, "time finding a way ~30 s: " .. tostring(s and s.way))
CHECK(s and s.offline >= 890, "time offline: " .. tostring(s and s.offline))
local txt = table.concat(handleCommand("survey stats") or {}, "\n")
CHECK(txt:find("scans", 1, true) and txt:find("offline", 1, true) and txt:find("Scout41", 1, true),
      "survey stats lists it:\n" .. txt)

-- the lost report: a copy, one without fuel for the way home, one at the base
local function mk(id, dx, fuel)
  state.turtles[id] = { id = id, label = "L" .. id, log = { { t = "12:00", msg = "last words " .. id } }, lastN = 0,
    fuel = fuel, task = "survey 3/4", pos = { x = HOME.x + dx, y = 70, z = HOME.z },
    home = { x = HOME.x, y = 68, z = HOME.z }, lastSeen = CLOCK - 99999, seenEpoch = os.epoch("utc") - 7200 * 1000 }
end
mk(100009, 2000, 9000)
mk(10, 2400, 900)
mk(11, 20, 9000)
txt = table.concat(handleCommand("lost") or {}, "\n")
CHECK(txt:find("1 copies", 1, true) and txt:find("1 without fuel for the way home", 1, true) and txt:find("1 at the base", 1, true),
      "the summary counts the causes:\n" .. txt)
CHECK(txt:find("last words 10", 1, true) and txt:find("from the base", 1, true), "each one: last log line, how far out")
-- the last fuel is kept over a restart (turtles.dat): the report needs it
TT.saveList()
state.turtles[10].fuel = nil
TT.loadList()
CHECK(tonumber(state.turtles[10].fuel) == 900, "last fuel kept in turtles.dat")
state.turtles, state.tOut = {}, {}
