-- CraftOS throws away events (also timers) that come while a program waits for a
-- peripheral's answer. The base's 2-s jobs (turtle updates, going home, rescues
-- ...) must keep running when their timer is lost - before, they all stopped
-- until a restart ("UPDATE QUEUED" forever, idle turtles never sent home).
local ran = 0
local upd0 = TT.updateTick
TT.updateTick = function() ran = ran + 1 end
local n = 0
local pull0 = os.pullEventRaw
os.pullEventRaw = function()
  n = n + 1
  CLOCK = CLOCK + 0.5
  if n > 60 then state.running = false end
  return "timer", -1                   -- some other worker's timer; OUR timer never arrives
end
state.running = true
local ok, err = pcall(commsWorker)
os.pullEventRaw = pull0
state.running = true
TT.updateTick = upd0
CHECK(ok, "commsWorker ran: " .. tostring(err))
CHECK(ran >= 10, "the 2-s jobs keep running with their timer lost (" .. ran .. " times in 30 s)")
-- waitFor returns after its time even when its timer is lost
local pull1 = os.pullEventRaw
local m = 0
os.pullEventRaw = function() m = m + 1 CLOCK = CLOCK + 0.5 if m > 50 then return "terminate" end return "timer", -1 end
waitFor(3)
os.pullEventRaw = pull1
CHECK(m <= 8, "waitFor ends on time without its timer (" .. m .. " events)")
