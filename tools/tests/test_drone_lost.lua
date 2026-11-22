-- LOST DRONES (the owner: "drone gifts - I see them teleport up to the sky and get lost, I never see them again" +
-- "it is like hopping to the base instead of teleporting directly - the base is underground, which is hard for drones
-- to teleport to"). tools/tests/lib/drone_sim.lua: a teleport only into a LOADED, FREE spot (free = above GROUND), a
-- flight out of the loaded area = LOST (r.lost). The drone is far away at a player (a gift), the base underground.
dofile(SRC_DIR .. "/tools/tests/lib/drone_sim.lua")
state.owner = "Alaory"
setSetting("drone.simChunks", 6)
local HOME = { x = 0, y = 40, z = 0 }                  -- (under ground: GROUND 64 - no teleport into it)
local function home(opt)
  DRONE_ARRIVE = opt.learned
  if opt.arrive then setSetting("drone.arrive", opt.arrive) else setSetting("drone.arrive", false) end
  return DRONE_SIM.run({ home = HOME, start = { x = 2000, y = 72, z = 0 }, loadedR = 96, ground = 64, air = opt.air,
    players = { Bob = { x = 2000, y = 70, z = 0 }, Alaory = { x = 0, y = 40, z = 3 } }, mission = { kind = "home" } })
end
-- 1) plenty of air, no arrival spot: never hops out of the loaded area
local r = home({ air = 9 })
CHECK(r.lost == 0, "underground base, plenty of air: never flies out of the loaded area (" .. r.lost .. " lost flights)")
local hopped = false
for _, l in ipairs(r.log) do if l:find("teleported to %-?%d+ 200 ") then hopped = true end end
CHECK(not hopped, "no hops at Y 200 towards the base (it is loaded - a refused teleport means blocked)")
-- 2) low air after the gift (2.5 bar): the old code hopped / flew home across unloaded land = lost
r = home({ air = 2.5 })
CHECK(r.lost == 0, "low air: it stays where it is instead of flying home across unloaded land (" .. r.lost .. " lost)")
CHECK(math.abs(r.pos.x - 2000) < 100, "... it waits near the player (" .. r.pos.x .. ")")
CHECK(tostring(r.err):find("lost", 1, true) or tostring(r.err):find("air", 1, true), "... and says why: " .. tostring(r.err))
-- 3) an ARRIVAL SPOT at the base (open air above the tunnel): teleport there, fly in - home
r = home({ air = 6, arrive = { x = 4, y = 70, z = 4 } })
CHECK(r.state == "done" and r.lost == 0 and math.abs(r.pos.y - 40) <= 2, "with an arrival spot: teleport there + fly in = home (" ..
      tostring(r.state) .. " " .. tostring(r.err) .. ", at " .. r.pos.x .. " " .. r.pos.y .. " " .. r.pos.z .. ")")
CHECK(r.refused <= 1, "... at most one refused teleport (" .. r.refused .. ")")
-- 3b) a LEARNED spot is used once a straight teleport into the base was refused (not before - no detour for nothing)
BASE_TP_REFUSED = nil
r = home({ air = 9, learned = { x = 4, y = 70, z = 4 } })
CHECK(BASE_TP_REFUSED == true, "the straight teleport into the underground base was refused: noted")
r = home({ air = 6, learned = { x = 4, y = 70, z = 4 } })
CHECK(r.state == "done" and math.abs(r.pos.y - 40) <= 2 and r.refused == 0, "... next time the learned spot is used: home, nothing refused (" ..
      tostring(r.err) .. ", " .. r.refused .. " refused)")
-- 4) LEARNED: a base the drones CAN teleport to: the spot that worked is remembered
HOME = { x = 0, y = 70, z = 0 }
r = home({ air = 6 })
CHECK(r.state == "done" and DRONE_ARRIVE and math.abs(DRONE_ARRIVE.x) <= 3 and DRONE_ARRIVE.y >= 69,
      "a teleport home from far away teaches the arrival spot (" .. textutils.serialize(DRONE_ARRIVE or {}) .. ")")
CHECK(FILES["drone_arrive.dat"] ~= nil, "... saved (drone_arrive.dat)")
HOME = { x = 0, y = 40, z = 0 }
-- 5) a far trip needs air for there AND back (DW.airFor): gifts / fuel runs wait for a charged drone
local dr = drones[droneOrder[1]]
CONFIG.drone.home = { x = 0, y = 40, z = 0 }
setSetting("drone.workChestAt", { x = 2, y = 40, z = 2 })
local rd, per0 = refreshDrone, dr.periph
refreshDrone = function() end
dr.periph = { getDronePressure = function() return dr.pressure end }
dr.pressure = 3
CHECK(not DW.airFor(dr, 2000, 0), "3 bar: no trip 2000 blocks out (" .. tostring(select(2, DW.airFor(dr, 2000, 0))) .. ")")
CHECK(DW.airFor(dr, 20, 10), "... a trip inside the base is fine")
dr.pressure = 5
CHECK(DW.airFor(dr, 2000, 0), "5 bar: the far trip goes")
refreshDrone, dr.periph = rd, per0
-- 6) WHERE IT WAS LAST SEEN (the owner: "can you show where the drone was last seen")
CHECK(DRONE_SEEN[dr.key] and FILES["drone_seen.dat"], "every position the drone reports is kept (drone_seen.dat)")
droneSeen(dr, 1234, 80, -567)
local warned = 0
local push0 = pushNote
pushNote = function(t, m, ...) if tostring(m):find("LOST CONTACT", 1, true) then warned = warned + 1 end return push0(t, m, ...) end
dr.wasConn = true
local per1 = dr.periph
dr.periph = { isConnectedToDrone = function() return false end, getDronePressure = function() return nil end,
              getDronePosition = function() error("no drone") end, getAction = function() return nil end,
              isActionDone = function() return true end }
refreshDrone(dr)
refreshDrone(dr)
CHECK(not dr.conn and warned == 1, "the drone stops answering: ONE warning (" .. warned .. ")")
local txt = droneSeenText(dr) or ""
CHECK(txt:find("1234, 80, %-567") or txt:find("1234 80 %-567"), "... with where it was last seen: " .. txt)
local out = table.concat(handleCommand("drones") or {}, " ")
CHECK(out:find("last seen", 1, true), "console drones: last seen")
state.drone, state.page, state.t.drone = dr, "drone", os.clock()
safeDraw()
local onScreen = false
for y = 1, H do if win.getLine(y):find("last seen", 1, true) then onScreen = true end end
CHECK(onScreen, "the DRONES page shows where it was last seen")
local saved = textutils.unserialize(FILES["drone_seen.dat"])
CHECK(saved and saved[dr.key] and saved[dr.key].x == 1234, "... and it is saved for after a restart")
dr.periph = per1
droneSeen(dr, 0, 70, 0)
CHECK(dr.lostAt == nil, "found again")
pushNote = push0
