-- miner.lua with DUPLICATE copies: commands for another session are ignored, a
-- "dupstop" freezes the copy (dupPark), a stopped copy never saves / talks to
-- the team; between steps only "dupstop" is acted on, the rest waits (backlog).
--   lua5.3 tools/tests/miner_dup.lua miner.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "miner.lua"):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a + 1, true)
  assert(a and b, "not found: " .. from)
  return src:sub(a, b - 1)
end
os.epoch = function() return 1700000000000 end
load(piece("SESSION = tostring", "function now()"))()
CHECK(type(SESSION) == "string" and DUP == false, "a session is picked at start")
CHECK(piece("function save()", "function loadState()"):find("if DUP then return end", 1, true), "a copy never saves")
CHECK(piece("function sendTeam(", "function isMember("):find("if DUP or not modemSide()", 1, true), "a copy never talks to the team")
local sb = piece("function sendBase(", "function sendTeam(")
CHECK(sb:find("m.ses = SESSION", 1, true) and sb:find("m.dup = true", 1, true), "reports carry the session")
load(piece("function handle(id, m, proto)", "-- I am an extra COPY"))()
load(piece("-- a short listen between steps", "---------------------------------------------------------------------- inventory"))()
CONFIG = { protocol = "base", team = "basemine" }
S = { key = "k", dim = "overworld", lastCmd = 0 }
function sign() return "sig" end
function save() end
local did = {}
function doCmd(c) did[#did + 1] = c end
local PARKED = 0
function dupPark() PARKED = PARKED + 1 DUP = true end
local inbox = {}
rednet = { receive = function() local m = table.remove(inbox, 1) if m then return m[1], m[2], m[3] end end }
local n = 0
local function cmd(c, ses) n = n + 1 inbox[#inbox + 1] = { 1, { t = "cmd", n = n, cmd = c, args = {}, ses = ses, sig = "sig" }, "base" } end
cmd("start", "other")
listen(0.01)
CHECK(#did == 0, "a command for another copy is ignored")
cmd("start", SESSION)
listen(0.01)
CHECK(did[1] == "start", "a command for my session is done")
-- between steps: only dupstop now, the rest kept in order
did = {}
cmd("newfield")
cmd("start")
hearDup()
CHECK(#did == 0 and #BACKLOG == 2, "between steps: other commands wait (" .. #BACKLOG .. ")")
listen(0.01)
CHECK(did[1] == "newfield" and did[2] == "start" and #BACKLOG == 0, "...and are done at the next listen, in order")
cmd("dupstop", SESSION)
hearDup()
CHECK(PARKED == 1 and DUP, "dupstop between steps: the copy freezes")
did = {}
cmd("start")
inbox[#inbox + 1] = { 5, { t = "ready", n = 99, sig = "sig", dim = "overworld" }, "basemine" }
listen(0.01)
CHECK(#did == 0, "a stopped copy takes no commands and no team messages")
cmd("dupfree", SESSION)
listen(0.01)
CHECK(DUP == false, "dupfree: the real one again")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
