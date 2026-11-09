-- YOUR commands go first: a turtle busy with a job PAUSES it for a command you
-- give (m.hand: DRIVE, GO HOME, ...), does yours at once, and goes back to the
-- job after resumeAfter s without another one. Automatic base orders while busy
-- are still refused; STOP forgets the paused job. Runs the REAL listener and
-- worker as coroutines with a fake radio and clock.
--   lua5.3 tools/tests/node_hand.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a + 1, true)
  assert(a and b, "not found: " .. from)
  return src:sub(a, b - 1)
end
local code = piece("-- YOUR commands go first", "function reply(cmd, ok, msg)") ..
             piece("function listener()", "function heartbeat()")
-- a fake world
CLOCK = 0
os.clock = function() return CLOCK end
os.queueEvent = function() end
os.reboot = function() error("reboot") end
function sleep() coroutine.yield("sleep") end
CONFIG = { protocol = "p", key = "k", resumeAfter = 120, heartbeat = 5, gpsIdle = 60 }
S, job, task, stopFlag = { coreChecked = true, refuelDone = true }, nil, "idle", false
SESSION, COPY, DUP = "s1", nil, false
function sign() return "SIG" end
function save() end function trailSave() end function gpsCheck() end function fmt() return "here" end
function hasCore() return false end function atHome() return true end
function afterForcedStop() end
turtle = { getFuelLevel = function() return "unlimited" end }
modemAttached, SLOT_LOCK, TOPUP_RUNNING, FORCE_STOP, STEPPING = true, false, false, false, false
local SENT = {}
function send(t, m) SENT[#SENT + 1] = { t = t, m = m } end
function reply(cmd, ok, msg) SENT[#SENT + 1] = { t = "result", m = { cmd = cmd, ok = ok, msg = msg } } end
parallel = { waitForAny = function(a) a() end }
local RAN, DRIVEN = {}, {}
-- a job runs until stopped (goto) or finishes at once (anything else)
function runJob(j)
  RAN[#RAN + 1] = j.cmd
  task = j.cmd
  if j.cmd == "goto" or j.cmd == "surveypts" then
    while not stopFlag do coroutine.yield("job") end
    return false, "stopped at here"
  end
  return true, j.cmd .. " done"
end
function driveStep(act) DRIVEN[#DRIVEN + 1] = act return true, "moved " .. act end
function driveLook() end
-- immediate: drive + stop like node.lua (only what the test needs)
function immediate(cmd, a)
  if cmd == "stop" then
    S.paused, NEXT_JOB, DRIVE_NEXT = nil, nil, nil
    stopFlag = true
    return true, "stopping"
  elseif cmd == "drive" then
    if job then
      if not HAND then return false, "busy" end
      local was = task
      pauseForHand()
      DRIVE_NEXT = { act = tostring(a[1] or ""), force = a[2] == "force" }
      return true, "paused '" .. tostring(was) .. "' - your step comes right after"
    end
    return driveStep(a[1])
  end
  return nil
end
local INBOX, N = {}, 0
rednet = { receive = function()
  while #INBOX == 0 do coroutine.yield("radio") end
  return 1, table.remove(INBOX, 1)
end }
local fn, err = load(code, "=node pieces")
assert(fn, err)
fn()
-- the real immediate's drive branch must match the stub's idea (pause when HAND)
CHECK(src:find('if not HAND then return false, "busy: "', 1, true), "node immediate: drive pauses the job for YOUR step")
local function cmd(c, args, hand)
  N = N + 1
  INBOX[#INBOX + 1] = { t = "cmd", n = N, cmd = c, args = args or {}, hand = hand, sig = "SIG" }
end
local L = coroutine.create(listener)
local W = coroutine.create(worker)
local function run(steps)
  for _ = 1, steps or 5 do
    assert(coroutine.resume(L))
    local ok, e = coroutine.resume(W)
    if not ok then error(e) end
  end
end
local function lastResult(c)
  for i = #SENT, 1, -1 do if SENT[i].t == "result" and SENT[i].m.cmd == c then return SENT[i].m end end
end
-- a long trip is running
cmd("goto", { 100, 70, 100 })
run(3)
CHECK(job and job.cmd == "goto", "the trip runs")
-- an AUTOMATIC order while busy: refused as before
cmd("home", {})
run(3)
CHECK(lastResult("home") and lastResult("home").ok == false, "automatic order while busy: refused")
-- YOUR order while busy: the trip pauses, yours runs at once
cmd("home", {}, true)
run(4)
CHECK(RAN[#RAN] == "home", "your GO HOME ran at once (" .. table.concat(RAN, ",") .. ")")
CHECK(S.paused and S.paused.cmd == "goto", "the trip is kept (paused)")
CHECK(tostring(task):find("waiting - paused 'goto'", 1, true), "it says so: " .. tostring(task))
-- a DRIVE step while busy with something else: paused, then the step
cmd("goto", { 5, 5, 5 }, true)                         -- (your own goto: runs)
run(3)
cmd("drive", { "f" }, true)
run(4)
CHECK(DRIVEN[#DRIVEN] == "f", "your DRIVE step ran while it was busy")
-- no command from you for 2 min: back to the paused job
CLOCK = CLOCK + 60
run(3)
CHECK(not job or job.cmd ~= "goto" or RAN[#RAN] ~= "goto" or #RAN < 5, "not back before resumeAfter")
CLOCK = CLOCK + 70
run(4)
CHECK(job and job.cmd == "goto", "after 2 min without your commands: back to the paused job")
-- STOP forgets it
cmd("drive", { "u" }, true)
run(4)
CHECK(S.paused ~= nil, "paused again for a step")
cmd("stop", {})
run(3)
CLOCK = CLOCK + 500
run(3)
CHECK(S.paused == nil and not job, "STOP: the paused job is forgotten, it stays idle")
-- a paused SURVEY batch is not resumed by the turtle: it becomes free for the base
cmd("surveypts", { 8, 1, 2 })
run(3)
cmd("home", {}, true)
run(4)
CLOCK = CLOCK + 200
run(4)
CHECK(not job and task == "idle", "paused survey: idle afterwards (the base hands out survey work again)")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
