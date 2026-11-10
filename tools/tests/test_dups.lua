-- DUPLICATE turtles (server crash): one id, several sessions talking at once.
local SEQ = 0
local function report(id, ses, pos, extra)
  SEQ = SEQ + 1
  local m = { t = "status", n = os.epoch("utc") + 1000 + SEQ, ses = ses, label = "Scout", task = "idle", fuel = 5000,
              pos = pos, home = { x = 0, y = 64, z = 0 } }
  for k, v in pairs(extra or {}) do m[k] = v end
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
local function sent(cmd)
  local r = {}
  for _, o in ipairs(state.tOut) do if o.msg.cmd == cmd then r[#r + 1] = o end end
  return r
end
state.turtles, state.tOut, state.notes = {}, {}, {}
TT.sess = {}
CONFIG.turtles.copies = "stop"                     -- (first: copies are parked)
-- a normal restart: old session, then a new one (the old one goes silent) = no copies
report(68, "A", { x = 1, y = 64, z = 1 })
CLOCK = CLOCK + 5
report(68, "A", { x = 2, y = 64, z = 1 })
CLOCK = CLOCK + 20
report(68, "B", { x = 2, y = 64, z = 1 })
CLOCK = CLOCK + 5
report(68, "B", { x = 3, y = 64, z = 1 })
local t = state.turtles[68]
CHECK(not t.dups and t.mainSes == "B", "a restart is not a copy")
-- the crash: C near home and D far away talk at the same time
CLOCK = CLOCK + 700
report(68, "C", { x = 5, y = 64, z = 5 })
report(68, "D", { x = 900, y = 70, z = 900 })
CLOCK = CLOCK + 3
report(68, "C", { x = 5, y = 64, z = 6 })
report(68, "D", { x = 900, y = 70, z = 901 })
CLOCK = CLOCK + 3
report(68, "C", { x = 5, y = 64, z = 7 })
report(68, "D", { x = 900, y = 70, z = 902 })
CHECK(t.dups and #t.dups == 1, "2 sessions at once = 1 extra copy")
CHECK(t.mainSes == "C", "the copy nearest home stays the turtle")
CHECK(t.pos.x == 5, "a copy's reports do not move the real turtle (" .. tostring(t.pos.x) .. ")")
local stops = sent("dupstop")
CHECK(#stops >= 1 and stops[1].msg.ses == "D", "the copy (and only it) gets dupstop")
CHECK(TT.dupText(t) and TT.dupText(t):find("900", 1, true), "the card says where the copy is")
local warned = false
for _, e in ipairs(state.noteLog or {}) do if tostring(e.msg or e.text):find("TIMES", 1, true) then warned = true end end
for _, e in ipairs(state.notes or {}) do if tostring(e.msg or e.text):find("TIMES", 1, true) then warned = true end end
CHECK(warned, "a warning is shown")
-- while it has copies, commands go to the real one only
state.tOut = {}
TT.send(68, "home", {})
CHECK(state.tOut[1].msg.ses == "C", "commands carry the real one's session")
-- the copy obeyed (dup) - no more dupstops; it is broken (silent 10 min) -> copies gone
state.tOut = {}
CLOCK = CLOCK + 20
report(68, "D", { x = 900, y = 70, z = 902 }, { dup = true })
CHECK(#sent("dupstop") == 0, "a stopped copy is not stopped again")
CLOCK = CLOCK + 650
report(68, "C", { x = 5, y = 64, z = 8 })
CHECK(not t.dups and TT.dupText(t) == nil, "copy broken: no copies any more")
state.tOut = {}
TT.send(68, "home", {})
CHECK(state.tOut[1].msg.ses == nil, "no copies: commands without a session (a restart is never locked out)")
-- the real one restarts while a stopped copy still talks: the stopped copy is never picked
TT.sess = {}
t.mainSes, t.dups = nil, nil
report(68, "E", { x = 1, y = 64, z = 1 }, { dup = true })
report(68, "F", { x = 800, y = 64, z = 800 })
CLOCK = CLOCK + 3
report(68, "E", { x = 1, y = 64, z = 1 }, { dup = true })
report(68, "F", { x = 800, y = 64, z = 801 })
CLOCK = CLOCK + 3
report(68, "E", { x = 1, y = 64, z = 1 }, { dup = true })
report(68, "F", { x = 800, y = 64, z = 802 })
CHECK(t.mainSes == "F", "a stopped copy never becomes the real one (even nearer home)")

-- USE the copies (the default): the copy becomes a turtle of its own
CONFIG.turtles.copies = "use"
TT.sess, TT.copyRes = {}, {}
state.turtles, state.tOut = {}, {}
report(70, "P", { x = 5, y = 64, z = 5 })
CLOCK = CLOCK + 3
report(70, "P", { x = 5, y = 64, z = 6 })
report(70, "Q", { x = 400, y = 64, z = 400 })
CLOCK = CLOCK + 3
report(70, "P", { x = 5, y = 64, z = 7 })
report(70, "Q", { x = 400, y = 64, z = 401 })
CLOCK = CLOCK + 3
report(70, "P", { x = 5, y = 64, z = 8 })
report(70, "Q", { x = 400, y = 64, z = 402 })
local bc = sent("becomecopy")
CHECK(#bc >= 1 and bc[1].msg.ses == "Q" and bc[1].msg.args[1] == 1 and bc[1].id == 70, "USE: the copy is told to become copy 1")
CHECK(#sent("dupstop") == 0, "USE: not parked")
-- it says yes: its old session no longer counts as a copy
report(70, "Q", nil, { t = "result", cmd = "becomecopy", ok = true })
CLOCK = CLOCK + 3
report(70, "P", { x = 5, y = 64, z = 9 })
CHECK(not state.turtles[70].dups, "after it said yes: no copies listed for #70")
-- it restarts as "Scout [c1]": its reports (m.copy = 1) are turtle 100070
report(70, "Q2", { x = 400, y = 64, z = 402 }, { copy = 1, label = "Scout [c1]" })
local c1 = state.turtles[100070]
CHECK(c1 and c1.label == "Scout [c1]" and c1.pos.x == 400, "the copy is turtle 100070 of its own")
CHECK(state.turtles[70].pos.x == 5, "...and does not touch #70")
local real, cn = TT.realId(100070)
CHECK(real == 70 and cn == 1, "100070 = radio id 70, copy 1")
CHECK(TT.freeCopyNo(70) == 2, "the next copy of #70 would be copy 2")

-- MINING turtles (miner.lua m17) the same way: MINE.receive
local function mreport(id, ses, pos, extra)
  SEQ = SEQ + 1
  local m = { t = "status", n = os.epoch("utc") + 1000 + SEQ, ses = ses, mine = true, role = "miner", dim = "overworld",
              label = "Miner 9", pos = pos }
  for k, v in pairs(extra or {}) do m[k] = v end
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
state.tOut = {}
CONFIG.turtles.copies = "stop"
mreport(90, "M1", { x = 100, y = 20, z = 100 })
CLOCK = CLOCK + 3
mreport(90, "M1", { x = 101, y = 20, z = 100 })
mreport(90, "M2", { x = 2000, y = 20, z = 2000 })
CLOCK = CLOCK + 3
mreport(90, "M1", { x = 102, y = 20, z = 100 })
mreport(90, "M2", { x = 2000, y = 20, z = 2001 })
CLOCK = CLOCK + 3
mreport(90, "M1", { x = 103, y = 20, z = 100 })
mreport(90, "M2", { x = 2000, y = 20, z = 2002 })
local u = MINE.units[90]
CHECK(u and u.dups and #u.dups == 1 and u.mainSes == "M1", "miner copies: the one where the real one was stays")
CHECK(u.pos.x == 103, "a miner copy's reports do not move the real one")
local ms = {}
for _, o in ipairs(state.tOut) do if o.msg.cmd == "dupstop" then ms[#ms + 1] = o end end
CHECK(#ms >= 1 and ms[1].msg.ses == "M2" and ms[1].id == 90, "the miner copy gets dupstop (its session)")
state.tOut = {}
MINE.cmd(90, "unloadnow", {})
CHECK(state.tOut[1] and state.tOut[1].msg.ses == "M1", "mining commands go to the real one only")
-- USE: a MINER copy becomes a miner of its own, a LOADER copy is parked
CONFIG.turtles.copies = "use"
TT.sess, state.tOut = {}, {}
local function pair(id, role)
  mreport(id, "A" .. id, { x = 10, y = 20, z = 10 }, { role = role })
  CLOCK = CLOCK + 3
  mreport(id, "A" .. id, { x = 10, y = 20, z = 11 }, { role = role })
  mreport(id, "B" .. id, { x = 900, y = 20, z = 900 }, { role = role })
  CLOCK = CLOCK + 3
  mreport(id, "A" .. id, { x = 10, y = 20, z = 12 }, { role = role })
  mreport(id, "B" .. id, { x = 900, y = 20, z = 901 }, { role = role })
  CLOCK = CLOCK + 3
  mreport(id, "A" .. id, { x = 10, y = 20, z = 13 }, { role = role })
  mreport(id, "B" .. id, { x = 900, y = 20, z = 902 }, { role = role })
end
pair(91, "miner")
pair(92, "loader")
local got = {}
for _, o in ipairs(state.tOut) do got[o.id .. o.msg.cmd] = o.msg end
CHECK(got["91becomecopy"] and got["91becomecopy"].ses == "B91", "a miner copy becomes a miner of its own")
CHECK(got["92dupstop"] and not got["92becomecopy"], "a loader copy is parked (one loader per dimension)")
mreport(91, "B91x", { x = 900, y = 20, z = 902 }, { copy = 1, label = "Miner 91 [c1]" })
CHECK(MINE.units[100091] and MINE.units[100091].label == "Miner 91 [c1]", "the miner copy is unit 100091")
