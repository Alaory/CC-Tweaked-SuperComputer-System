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
os.getComputerLabel = function() return "Miner 9" end
os.getComputerID = function() return 9 end
STATE_FILE = "miner_state"
load(piece("SESSION = tostring", "function now()"))()
CHECK(COPY == nil and MYTID == 9, "the original: team id = its id")
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
-- TEAM messages: one for another copy with my radio id (to = 100009) is not mine;
-- the sender's TEAM id (from) is used, not its radio id
S.role = "miner"
local seenFrom
local oldHandle = handle
inbox[#inbox + 1] = { 4, { t = "loaderhere", n = 1, sig = "sig", dim = "overworld", to = 100009, from = 4 }, "basemine" }
local sentTo = {}
function sendTeam(to, t) sentTo[#sentTo + 1] = { to = to, t = t } end
listen(0.01)
CHECK(#sentTo == 0, "a team message for copy 1 of my id is ignored")
inbox[#inbox + 1] = { 4, { t = "loaderhere", n = 2, sig = "sig", dim = "overworld", from = 200004 }, "basemine" }
listen(0.01)
CHECK(sentTo[1] and sentTo[1].to == 200004 and sentTo[1].t == "minerhere", "answers the sender's TEAM id (a loader copy 2)")
-- becomeCopy: tagged name, own state file (role, key, dim, station kept), result, restart
local LABEL2, FILES, REBOOT, SENT = "Miner 9", {}, false, {}
os.getComputerLabel = function() return LABEL2 end
os.setComputerLabel = function(l) LABEL2 = l end
fs = { open = function(p) return { write = function(s) FILES[p] = s end, close = function() end } end }
textutils = { serialize = function(t) return "role=" .. tostring(t.role) .. " station=" .. tostring(t.station and t.station.x) end }
gps = { locate = function() return 1.2, 2.2, 3.2 end }
function sendBase(t, extra) SENT[#SENT + 1] = extra end
sleep = function() end
os.reboot = function() REBOOT = true error("rebooted") end
S.station = { x = 77, y = 1, z = 2 }
load(piece("function becomeCopy(k)", "-- listen for a while"))()
pcall(becomeCopy, 3)
CHECK(LABEL2 == "Miner 9 [c3]", "becomeCopy: tagged name (" .. LABEL2 .. ")")
CHECK(FILES["miner_state_c3"] and FILES["miner_state_c3"]:find("role=miner", 1, true) and FILES["miner_state_c3"]:find("station=77", 1, true),
      "becomeCopy: its own state file keeps role + unload station")
CHECK(SENT[1] and SENT[1].cmd == "becomecopy" and SENT[1].ok, "becomeCopy: tells the base")
CHECK(REBOOT, "becomeCopy: restarts")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
