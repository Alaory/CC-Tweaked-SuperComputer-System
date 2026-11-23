-- RELEASE REVIEW (the owner: "I don't want things to bug out and crash"): one error in a worker / a page / a
-- button used to end the whole base (startup.lua started it again from nothing). Now a worker starts again,
-- a page that cannot be drawn falls back to HOME, a button's error is a box - the base keeps running.
local pull0, sleep0 = os.pullEventRaw, sleep
sleep = function(s) CLOCK = CLOCK + (s or 0) end
state.running = true

-- 1) a worker that fails twice keeps going (restarted), then ends normally
local runs, restarted = 0, 0
WORKER_RESTART["test worker"] = function() restarted = restarted + 1 end
local w = keepWorker("test worker", function()
  runs = runs + 1
  if runs <= 2 then error("boom " .. runs) end
end)
local ok, err = pcall(w)
CHECK(ok and runs == 3 and restarted == 2, "a failing worker is started again (runs " .. runs .. ", restarts " .. restarted .. "): " .. tostring(err))
local found = false
for _, l in ipairs(SYSLOG or {}) do if tostring(l.msg or l.text or l[2] or l):find("test worker stopped with an error", 1, true) then found = true end end
CHECK(found or WORKER_FAILS["test worker"] == 2, "... and it is noted")
-- 2) failing again and again (5 in a minute): the error goes up as before (startup.lua restarts the base)
local w2 = keepWorker("bad worker", function() error("always") end)
local ok2, err2 = pcall(w2)
CHECK(not ok2 and tostring(err2):find("keeps failing", 1, true), "5 errors in a minute: it gives up (" .. tostring(err2) .. ")")
-- 3) Ctrl+T still stops it at once
local w3 = keepWorker("t worker", function() error("Terminated", 0) end)
local ok3, err3 = pcall(w3)
CHECK(not ok3 and tostring(err3) == "Terminated", "Terminated goes up at once (" .. tostring(err3) .. ")")
-- 4) the drone worker restarting frees its drones
drones = drones or {}
local fakeDr = { key = "zz", label = "Z", busy = true, queue = {}, log = {} }
drones.zz = fakeDr
WORKER_RESTART["drone worker"]()
CHECK(not fakeDr.busy and fakeDr.failedAt and fakeDr.mission.state == "failed", "drone worker restart: its drones are free and sent home")
drones.zz = nil

-- 5) a page that cannot be drawn: HOME instead, no error out of the screen loop
local draw0 = drawStorage
local pageDraw = {}
for _, name in ipairs({ "drawStoragePage", "drawTurtlesPage", "drawMapPage" }) do pageDraw[name] = _G[name] end
state.page = "turtles"
local dt = drawTurtlesPage
drawTurtlesPage = function() error("odd value") end
local okD, r = pcall(safeDraw)
drawTurtlesPage = dt
CHECK(okD and r == false and state.page == "home" and state.drawErr, "a page that fails to draw: HOME instead (" .. tostring(state.page) .. ")")
-- HOME failing too: a plain error screen, still no error
local dh = drawHomePage
drawHomePage = function() error("home broken") end
state.page = "home"
local okH = pcall(safeDraw)
drawHomePage = dh
CHECK(okH, "even HOME failing: no crash")
CHECK(safeDraw() == true and state.drawErr == nil, "the next good draw works again")

-- 6) the screen loop: a failing button, a craft event, a broken peripheral event - it keeps running
local events = {
  { "monitor_touch", monName, 5, 5 },
  { "me_crafting", false, 42, "JOB_DONE" },
  { "peripheral", "weird_0" },
  { "peripheral_detach", "weird_0" },
  { "playerJoin", "Bob", "minecraft:overworld" },
  { "terminate" },
}
local hT, rp = handleTouch, rescanPeripherals
handleTouch = function() error("button bug") end
rescanPeripherals = function() error("scan bug") end
local mexGot = nil
local ev0 = MEX and MEX.event
if MEX then MEX.event = function(a, b, c) mexGot = { a, b, c } end end
local i = 0
os.pullEventRaw = function() i = i + 1 CLOCK = CLOCK + 0.1 local e = events[i] or { "terminate" } return table.unpack(e) end
state.running = true
local okU, errU = pcall(uiLoop)
os.pullEventRaw = pull0
handleTouch, rescanPeripherals = hT, rp
if MEX then MEX.event = ev0 end
CHECK(okU, "the screen loop keeps running through a failing button and a failing peripheral scan: " .. tostring(errU))
CHECK(not MEX or (mexGot and mexGot[2] == 42), "the craft event reaches the AE2 SYSTEM page (MEX.event)")
state.running = true

-- 7) the base starts every worker through keepWorker
local inv = io.open(SRC_DIR .. "/inventory.lua"):read("a")
for _, wk in ipairs({ "uiLoop", "invWorker", "pageWorker", "actionWorker", "droneWorker", "terminalWorker", "chatWorker",
                      "commsWorker", "mapWorker", "supplyWorker", "addonWorker", "playerWorker" }) do
  CHECK(inv:find('K%("[^"]+", ' .. wk .. '%)'), "inventory.lua starts " .. wk .. " through keepWorker")
end
sleep = sleep0
