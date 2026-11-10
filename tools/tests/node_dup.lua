-- node.lua with DUPLICATE copies of one id (server crash): a command meant for
-- another copy's session is ignored, a stopped copy (DUP) takes no jobs and
-- never writes the shared disk, "dupstop" / "dupfree" switch it.
--   lua5.3 tools/tests/node_dup.lua node.lua
local NODE = arg[1] or "node.lua"
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(NODE):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a + 1, true)
  assert(a and b, "not found: " .. from)
  return src:sub(a, b - 1)
end
math.randomseed(7)
os.epoch = function() return 1700000000000 end
os.queueEvent = function() end
-- the session + writeFile guard, the listener, the dupstop / dupfree branch
load(piece("SESSION = tostring", "function writeFile"))()
CHECK(type(SESSION) == "string" and #SESSION > 5 and DUP == false, "a session is picked at start")
local wf = piece("function writeFile(path, value)", "local ok, text = pcall")
CHECK(wf:find("if DUP then return false end", 1, true), "a DUPLICATE never writes the shared disk")
load(piece("function listener()", "-- jobs worth continuing"))()
load("function immediate(cmd, a) if cmd == 'x' then " ..
     piece('elseif cmd == "dupstop" then', 'elseif cmd == "stop" then') ..
     " else return nil end end")()
CONFIG = { protocol = "p", key = "k" }
S = { pos = { x = 1, y = 2, z = 3, f = 0 } }
function sign() return "sig" end
function save() end
function gpsRaw() return 50, 60, 70 end
local replies = {}
function reply(cmd, ok, msg) replies[#replies + 1] = { cmd = cmd, ok = ok, msg = msg } end
job, task, stopFlag = nil, "idle", false
local n = 0
local queue = {}
local function cmd(c, ses) n = n + 1 queue[#queue + 1] = { t = "cmd", n = n, cmd = c, args = {}, ses = ses, sig = "sig" } end
rednet = { receive = function()
  local m = table.remove(queue, 1)
  if not m then error("done") end
  return 1, m
end }
local function run() pcall(listener) end

cmd("goto", "someone-else")
run()
CHECK(job == nil, "a command for another copy's session is ignored")
cmd("goto", SESSION)
run()
CHECK(job and job.cmd == "goto", "a command for MY session is taken")
job = nil
cmd("goto")
run()
CHECK(job and job.cmd == "goto", "a command without a session (old base) is taken")
job = nil
cmd("dupstop", SESSION)
run()
CHECK(DUP == true and stopFlag == true, "dupstop: I am a copy, my job stops")
CHECK(S.pos.x == 50 and S.pos.z == 70, "dupstop: my real (GPS) position is reported")
CHECK(replies[#replies] and replies[#replies].msg:find("DUPLICATE", 1, true), "dupstop: says so")
cmd("goto")
cmd("home", SESSION)
run()
CHECK(job == nil, "a stopped copy takes no jobs")
cmd("dupfree", SESSION)
run()
CHECK(DUP == false, "dupfree: the real turtle again")
-- USE a copy: "becomecopy 2" -> name "Scout [c2]" (kept in the turtle block),
-- its own state file, a restart; with that name it is COPY 2 with _c2 files
DUP = false
local LABEL = "Scout"
local FILES = {}
os.getComputerLabel = function() return LABEL end
os.setComputerLabel = function(l) LABEL = l end
os.getComputerID = function() return 68 end
fs = { open = function(p) return { write = function(s) FILES[p] = s end, close = function() end } end }
textutils = { serialize = function() return "{...}" end }
S.reuse = { ["mod:endless"] = true }
rebootSoon = false
n = n + 1
queue[#queue + 1] = { t = "cmd", n = n, cmd = "becomecopy", args = { 2 }, ses = SESSION, sig = "sig" }
run()
CHECK(LABEL == "Scout [c2]", "becomecopy: tagged name (" .. LABEL .. ")")
CHECK(FILES["node_state_c2"] ~= nil, "becomecopy: its own state file")
CHECK(rebootSoon == true and DUP == true, "becomecopy: restarts, writes nothing shared before")
local cp = piece("COPY = tonumber(", "-- Per-turtle settings")
load(cp)()
CHECK(COPY == 2 and COPYSFX == "_c2", "named [c2]: copy 2, files end in _c2")
CHECK(src:find('local STATE_FILE = "node_state" .. COPYSFX', 1, true) and src:find('local OUTBOX_FILE = "node_outbox" .. COPYSFX', 1, true),
      "a copy keeps its own state + outbox files")
-- a message for the untagged turtle (no m.copy) is not for copy 2; one with copy = 2 is
DUP, job = false, nil
cmd("goto")
run()
CHECK(job == nil, "copy 2 ignores messages for the original")
n = n + 1
queue[#queue + 1] = { t = "cmd", n = n, cmd = "goto", args = {}, copy = 2, sig = "sig" }
run()
CHECK(job and job.cmd == "goto", "copy 2 takes messages tagged copy 2")

-- the send() adds the session
local snd = piece("function send(t, extra)", "function reply(")
CHECK(snd:find("m.ses = SESSION", 1, true) and snd:find("if DUP then m.dup = true end", 1, true), "every report carries the session")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
