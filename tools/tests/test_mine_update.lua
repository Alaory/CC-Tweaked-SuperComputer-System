-- MINE UPDATE (base_mining.lua): miner.lua from a data floppy / dragged in / GitHub,
-- running teams PAUSED first, the pieces sent only to turtles running another
-- program, START again once the whole team runs it; teams with an old program
-- (m20 or older: no checksum) are left alone.
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
local function sent(id, cmd)
  local n = 0
  for _, o in ipairs(state.tOut) do if o.id == id and o.msg.cmd == cmd then n = n + 1 end end
  return n
end
local h = io.open("miner.lua", "rb") or io.open("../../miner.lua", "rb")
local SRC = h:read("a")
h:close()

BASE_DIR = "tb"               -- (the stand-in reads the repo's own files: no miner.lua in "tb")
MINE.units = {}
-- overworld team (m21: reports a checksum), running; nether team has an m20 miner
report(10, { role = "loader", dim = "overworld", running = true, team = { 11, 12 }, fuel = 50000, ver = "m21", code = "aaaa0000" })
report(11, { role = "miner", dim = "overworld", running = true, leader = 10, idx = 1, fuel = 9000, ver = "m21", code = "aaaa0000" })
report(12, { role = "miner", dim = "overworld", running = true, leader = 10, idx = 2, fuel = 9000, ver = "m21", code = "aaaa0000" })
report(20, { role = "loader", dim = "nether", running = true, team = { 21 }, fuel = 50000, ver = "m21", code = "aaaa0000" })
report(21, { role = "miner", dim = "nether", running = true, leader = 20, idx = 1, fuel = 9000, ver = "m20" })
CHECK(MINE.units[10].code == "aaaa0000", "the checksum is kept from the report")

-- the program: not on the computer -> nothing; a broken one is refused
local c0, why0 = MINE.loadCode(false)
CHECK(c0 == nil and tostring(why0):find("miner.lua"), "no miner.lua anywhere -> says how to get one")
CHECK(MINE.setCode("this is not lua (", "x") == nil, "a file that does not compile is refused")
CHECK(MINE.setCode("print('hi')", "x") == nil, "a program that is not miner.lua is refused")
-- dragged next to inventory.lua: used, moved onto the data storage
local f = fs.open(fs.combine(BASE_DIR or "", "miner.lua"), "wb") f.write(SRC) f.close()
local c = MINE.loadCode(false)
CHECK(c and c.myver and c.ver == MINE.codeHash(SRC), "miner.lua dragged in is used (" .. tostring(c and c.myver) .. ")")
CHECK(not fs.exists(fs.combine(BASE_DIR or "", "miner.lua")), "and moved off the program folder")
CHECK(fs.exists(dataFile(MINE.CODE_FILE)), "kept as " .. MINE.CODE_FILE)
local c2 = MINE.loadCode(false)
CHECK(c2 and c2.ver == c.ver and c2.from == "the stored copy", "next time: the stored copy")
local all = table.concat(c.pieces)
CHECK(all == SRC and #c.pieces == math.ceil(#SRC / MINE.PIECE), "pieces put back together = the program")

-- start: the overworld team is paused, the nether team (m20 miner) left alone
state.tOut = {}
local lines = table.concat(MINE.startUpdate(c), "\n")
CHECK(MINE.upd ~= nil, "an update runs")
CHECK(sent(10, "pause") == 1, "the running overworld team is PAUSED first")
CHECK(sent(20, "pause") == 0 and sent(20, "upd") == 0 and sent(21, "upd") == 0, "the team with an m20 miner gets nothing")
CHECK(lines:find("#21", 1, true) and lines:find("by hand", 1, true), "and the base says which one needs a hand copy")
CHECK(sent(10, "upd") == #c.pieces and sent(11, "upd") == #c.pieces and sent(12, "upd") == #c.pieces,
      "every overworld turtle gets all pieces (" .. sent(11, "upd") .. "/" .. #c.pieces .. ")")
for _, o in ipairs(state.tOut) do
  if o.msg.cmd == "upd" then
    CHECK(o.msg.sig == TT.sign(CONFIG.turtles.key, "cmd", o.msg.n, "upd", o.msg.args), "pieces are signed")
    CHECK(o.msg.args[1] == c.ver, "with the version (checksum)")
    break
  end
end
local inQ = 0
for _, q in ipairs(MINE.units[11].queue or {}) do if q.cmd == "upd" then inQ = inQ + 1 end end
CHECK(inQ == 0, "pieces are NOT in the resend queue (would go out with every report)")

-- 20 s later: 11 has it ready (waits for the install), 12 still old -> not again before 60 s
CLOCK = CLOCK + 21
report(11, { role = "miner", dim = "overworld", running = false, leader = 10, idx = 1, ver = "m21", code = "aaaa0000", updReady = c.ver })
state.tOut = {}
MINE.updTick()
CHECK(sent(11, "upd") == 0 and sent(12, "upd") == 0, "no resend within 60 s / to one that has it ready")
CHECK(sent(10, "start") == 0, "not started while some still run the old one")
CLOCK = CLOCK + 61
state.tOut = {}
MINE.updTick()
CHECK(sent(12, "upd") == #c.pieces and sent(11, "upd") == 0, "after 60 s: sent again only to the one without it")
-- all restarted with the new program -> START again, update over
report(10, { role = "loader", dim = "overworld", running = false, team = { 11, 12 }, ver = c.myver, code = c.ver })
report(11, { role = "miner", dim = "overworld", running = false, leader = 10, idx = 1, ver = c.myver, code = c.ver })
report(12, { role = "miner", dim = "overworld", running = false, leader = 10, idx = 2, ver = c.myver, code = c.ver })
CLOCK = CLOCK + 21
state.tOut = {}
MINE.updTick()
CHECK(sent(10, "start") == 1, "the paused team is STARTED again")
CHECK(sent(20, "start") == 0, "the team that was left alone gets no START")
CHECK(MINE.upd == nil, "update finished")

-- a team that was NOT running is not started by the update
MINE.units[10].code = "bbbb0000"
MINE.units[10].running = false
state.tOut = {}
MINE.startUpdate(c)
CHECK(sent(10, "pause") == 0 and sent(10, "upd") == #c.pieces, "a paused team: no PAUSE, just the program")
MINE.units[10].code = c.ver
CLOCK = CLOCK + 21
state.tOut = {}
MINE.updTick()
CHECK(sent(10, "start") == 0 and MINE.upd == nil, "and no START after")
-- nothing to do
state.tOut = {}
local l2 = table.concat(MINE.startUpdate(c), " ")
CHECK(MINE.upd == nil and l2:find("already", 1, true), "everyone up to date -> says so")

-- the console command
local out = table.concat(handleCommand("mine update") or {}, "\n")
CHECK(out:find("already", 1, true) or out:find("Sending", 1, true), "console  mine update  works: " .. out:sub(1, 80))
-- the MINING page draws while an update runs
MINE.units[11].code = "cccc0000"
MINE.startUpdate(c)
local okD, errD = pcall(function() state.page = "mining" draw() end)
CHECK(okD, "MINING page draws during an update: " .. tostring(errD))
