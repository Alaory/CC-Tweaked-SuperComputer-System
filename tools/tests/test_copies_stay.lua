-- COPIES STAY PUT (the owner: "copy turtles may stop loading chunks even if they have Chunky upgrades on them").
-- Advanced Peripherals keeps a Chunky's loaded chunk under a UUID stored IN the upgrade - a copy has its twin's:
-- when one of them moves into a new chunk, the other one's chunk is unloaded and it freezes. So the base never
-- gives a copy a job that moves it, until it has a NEW Chunky (`turtle <id> newchunky`).
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
local function sent(id, cmd)
  local r = {}
  for _, o in ipairs(state.tOut) do if o.id == id and o.msg.cmd == cmd then r[#r + 1] = o end end
  return r
end
local function mk(id, x, task)
  state.turtles[id] = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 50000, task = task or "idle",
    pos = { x = x, y = 70, z = HOME.z }, home = { x = HOME.x + id % 100, y = 70, z = HOME.z }, lastSeen = os.clock(),
    seenEpoch = os.epoch("utc") }
  return state.turtles[id]
end
state.turtles, state.tOut = {}, {}
local main = mk(7, HOME.x + 300)
local copy = mk(100007, HOME.x + 900)            -- copy 1 of turtle 7
CHECK(TT.isCopy(copy) and not TT.isCopy(main), "a copy is known by its number (n x 100000 + id)")

-- 1) no survey work for a copy
local av = TT.available()
local hasCopy = false
for _, id in ipairs(av) do if id == 100007 then hasCopy = true end end
CHECK(not hasCopy and #av == 1, "a copy is not available for jobs")
MAP.queue = nil
MAP.queueSurvey(HOME.x + 800, HOME.z - 100, HOME.x + 1000, HOME.z + 100, 8, nil)
for _ = 1, 3 do CLOCK = CLOCK + 20 main.lastSeen, copy.lastSeen = CLOCK, CLOCK MAP.feedSurvey() end
CHECK(#sent(100007, "surveypts") == 0 and #sent(7, "surveypts") > 0, "survey spots go to the real turtle, never to the copy")
CHECK(not (MAP.queue.out and MAP.queue.out[100007]), "the copy holds no survey batch")
MAP.queue = nil

-- 2) idle far from home / low on fuel: a copy is NOT sent home (the trip would unload its twin's chunk)
state.tOut = {}
copy.fuel = 900
copy.idleSince = nil
for _ = 1, 4 do CLOCK = CLOCK + 200 copy.lastSeen = CLOCK main.lastSeen = CLOCK TT.homeTick() end
CHECK(#sent(100007, "home") == 0 and #sent(100007, "fuelup") == 0, "a copy is never sent home / for fuel")

-- 3) a copy on a survey the old code gave it: stopped (no hold), once per 10 min
copy.task = "survey 3/64"
state.tOut = {}
TT.homeTick()
local st = sent(100007, "stop")
CHECK(#st == 1, "a copy on a survey trip is stopped")
CHECK(not copy.held, "... without a hold (it is not STOPPED by you)")
TT.homeTick()
CHECK(#sent(100007, "stop") == 1, "... not again and again")
copy.task = "idle"
-- your own drive is left alone
copy.task = "drive f"
copy.copyStopAt = nil
state.tOut = {}
TT.homeTick()
CHECK(#sent(100007, "stop") == 0, "your DRIVE commands are not stopped")
copy.task = "idle"

-- 4) offline copy: no rescue, no search party target
copy.lastSeen = CLOCK - 99999
copy.seenEpoch = os.epoch("utc") - 3600 * 1000
local lost = TT.lostList()
local inLost = false
for _, t in ipairs(lost) do if t.id == 100007 then inLost = true end end
CHECK(not inLost, "a frozen copy is not a lost turtle to look for")
local why = TT.idleWhy(copy)
copy.lastSeen = CLOCK
why = TT.idleWhy(copy)
CHECK(tostring(why):find("COPY", 1, true) and tostring(why):find("newchunky", 1, true), "the card says why it stays: " .. tostring(why))

-- 5) a NEW Chunky on it: `turtle <id> newchunky` -> it works again (saved in turtles.dat)
local out = handleCommand("turtle 100007 newchunky")
CHECK(copy.ownChunky == true, "newchunky marks its own Chunky: " .. table.concat(out or {}, " | "))
av = TT.available()
hasCopy = false
for _, id in ipairs(av) do if id == 100007 then hasCopy = true end end
CHECK(hasCopy, "with its own Chunky it gets jobs again")
TT.saveList()
copy.ownChunky = nil
TT.loadList()
CHECK(state.turtles[100007].ownChunky == true, "kept over a restart (turtles.dat)")
handleCommand("turtle 100007 newchunky off")
CHECK(not state.turtles[100007].ownChunky, "newchunky off = a copy again")
out = handleCommand("turtle 7 newchunky")
CHECK(table.concat(out or {}, " "):find("not a copy", 1, true), "the real turtle: nothing to do")
state.turtles, state.tOut = {}, {}
