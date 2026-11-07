-- Mining teams on the base (base_mining.lua): reports -> teams and status
-- labels, commands re-sent until the turtle has them, settings sent once,
-- the console `mine drop` goes to the right loader, the MINING page draws.
CONFIG.mining = { rowLength = 3 }
local SEQ = 0
local function report(id, m)
  SEQ = SEQ + 1
  m.n = os.epoch("utc") + SEQ
  m.mine = true
  m.t = m.t or "status"
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
MINE.units = {}
report(10, { role = "loader", dim = "overworld", task = "2 miner(s) in the team - press START on the base", running = false,
             team = { 11, 12 }, partner = 11, fuel = 50000, ci = 0 })
report(11, { role = "miner", dim = "overworld", task = "paused", leader = 10, partner = 10, fuel = 9000, idx = 1 })
report(12, { role = "miner", dim = "overworld", task = "paused", leader = 10, partner = 10, fuel = 9000, idx = 2 })
local teams = MINE.teams()
CHECK(teams.overworld and teams.overworld.loader and teams.overworld.loader.id == 10, "the loader leads the overworld team")
CHECK(#teams.overworld.miners == 2, "2 miners")
CHECK(MINE.status(MINE.units[10]) == "PAUSED", "loader not running -> PAUSED (" .. MINE.status(MINE.units[10]) .. ")")
report(10, { role = "loader", dim = "overworld", task = "chunk 1", running = false, team = { 11, 12 }, partner = 11,
             fuel = 50000, err = "miner 12 is silent for 20 min - team paused" })
local lab, _, why = MINE.status(MINE.units[10])
CHECK(lab == "STOPPED" and tostring(why):find("silent"), "loader stopped with a reason -> STOPPED + why")
report(10, { role = "loader", dim = "overworld", task = "crossing to chunk 2", running = true, team = { 11, 12 }, partner = 11, fuel = 50000 })
CHECK(MINE.status(MINE.units[10]) == "MOVING", "loader crossing -> MOVING")
report(10, { role = "loader", dim = "overworld", task = "waiting for miners", running = false, fuel = 50000 })
CHECK(MINE.status(MINE.units[10]) == "NO MINERS", "loader without miners -> NO MINERS")
report(10, { role = "loader", dim = "overworld", task = "x", running = true, team = { 11 }, partner = 11, fuel = 1500 })
CHECK(MINE.status(MINE.units[10]) == "LOW FUEL", "loader low on fuel -> LOW FUEL")
report(11, { role = "miner", dim = "overworld", task = "teleporting to the unload station", running = true, leader = 10, partner = 10, fuel = 9000 })
CHECK(MINE.status(MINE.units[11]) == "UNLOADING", "miner teleporting -> UNLOADING")
report(11, { role = "miner", dim = "overworld", task = "ready at my lane - waiting for the others (5 s)", running = true, leader = 10, partner = 10, fuel = 9000 })
CHECK(MINE.status(MINE.units[11]) == "WAITING", "miner at its lane -> WAITING")

-- a command is queued and sent again until the turtle reports it has it
local n0 = #state.tOut
MINE.cmd(10, "start", {})
local cmdN = MINE.units[10].queue[#MINE.units[10].queue].n
report(10, { role = "loader", dim = "overworld", task = "x", running = false, lastCmd = 0, fuel = 50000 })
local again = 0
for i = n0 + 1, #state.tOut do if state.tOut[i].msg.n == cmdN then again = again + 1 end end
CHECK(again >= 2, "the command is sent again while the turtle does not have it (" .. again .. ")")
report(10, { role = "loader", dim = "overworld", task = "x", running = true, lastCmd = cmdN, fuel = 50000 })
local still = false
for _, q in ipairs(MINE.units[10].queue) do if q.n == cmdN then still = true end end
CHECK(not still, "dropped from the queue once the turtle has it")

-- the mining settings go out once (and again when they change)
local function cfgSends(id, from)
  local n = 0
  for i = from + 1, #state.tOut do local o = state.tOut[i] if o.id == id and o.msg.cmd == "cfg" then n = n + 1 end end
  return n
end
MINE.units[12].cfgSent = nil
n0 = #state.tOut
report(12, { role = "miner", dim = "overworld", task = "x", running = true, leader = 10, fuel = 9000, lastCmd = 0 })
local q12 = MINE.units[12].queue
local cfgN = q12[#q12] and q12[#q12].n
report(12, { role = "miner", dim = "overworld", task = "x", running = true, leader = 10, fuel = 9000, lastCmd = cfgN })
report(12, { role = "miner", dim = "overworld", task = "x", running = true, leader = 10, fuel = 9000, lastCmd = cfgN })
CHECK(cfgSends(12, n0) == 1 or cfgSends(12, n0) == 2, "settings sent once (+ one repeat before it confirmed): " .. cfgSends(12, n0))
CONFIG.mining.dumpEvery = 1234
n0 = #state.tOut
report(12, { role = "miner", dim = "overworld", task = "x", running = true, leader = 10, fuel = 9000, lastCmd = cfgN })
CHECK(cfgSends(12, n0) == 1, "changed settings are sent again")

-- console: mine drop -> the loader gets "drop 12", the miner is off the list
local say0 = {}
n0 = #state.tOut
say0 = handleCommand("mine drop 12") or {}
local dropped = false
for i = n0 + 1, #state.tOut do local o = state.tOut[i] if o.id == 10 and o.msg.cmd == "drop" and o.msg.args[1] == "12" then dropped = true end end
CHECK(dropped, "mine drop: the loader is told")
CHECK(MINE.units[12] == nil, "mine drop: the miner is off the base's list")

-- the MINING page with a team draws (log merged across the team)
state.page = "mining"
MINE.log(MINE.units[10], "loader line")
MINE.log(MINE.units[11], "miner line")
local okD, errD = pcall(draw)
CHECK(okD, "the MINING page draws: " .. tostring(errD))
