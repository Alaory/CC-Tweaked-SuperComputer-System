-- DRONE SPEED, MEASURED IN SERVER TICKS (the owner: "the drones are slow" + "you know a server will have a low
-- TPS"). tools/tests/lib/drone_sim.lua runs the real missions against a PneumaticCraft-like drone: a teleport =
-- 120 ticks of warm-up and only into a LOADED spot (refused = the same 120 ticks + its air), flying 0.15 blocks a
-- tick. The old code (numbers in the checks): a ride 300 blocks out first tried a straight teleport and one into
-- the air above - both refused (nobody there loads it): 726 ticks; a work leg of 40 blocks flew with a teleport's
-- 8-s limit (= 24 blocks), was stopped, then teleported: 281 ticks.
dofile(SRC_DIR .. "/tools/tests/lib/drone_sim.lua")
local HOME = { x = 0, y = 70, z = 0 }
state.owner = "Alaory"
local function ride(d)
  return DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 160,
    players = { Alaory = { x = 0, y = 70, z = 0 } }, dest = { kind = "coords", x = d, y = 80, z = 0 },
    mission = { kind = "ferry", passenger = "Alaory" } })
end
local r = ride(300)
CHECK(r.state == "done" and r.refused == 0 and r.ticks <= 450, "ride 300 blocks out: no refused teleports, " ..
      r.ticks .. " ticks (old 726)")
r = ride(1500)
CHECK(r.state == "done" and r.refused <= 1 and r.ticks <= 1450, "ride 1500 blocks out: " .. r.ticks .. " ticks, " ..
      r.refused .. " refused (old 1691, 2 refused)")
CHECK(r.air > 0, "... with air left (" .. string.format("%.1f", r.air) .. " bar; the old code went below 0)")
-- a moving / known-loaded target still goes straight: Bob 300 out (Bob loads his area)
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 160,
  players = { Bob = { x = 300, y = 70, z = 0 }, Alaory = { x = 0, y = 70, z = 0 } },
  dest = { kind = "player", name = "Alaory" }, mission = { kind = "ferry", passenger = "Bob" } })
CHECK(r.state == "done" and r.refused == 0 and r.ticks <= 300, "Bob 300 out -> you: straight teleports (" .. r.ticks .. " ticks)")
-- short: fly when quicker than the 120-tick warm-up
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 160,
  players = { Alaory = { x = 0, y = 70, z = 0 } }, dest = { kind = "coords", x = 14, y = 72, z = 0 }, mission = { kind = "fly" } })
CHECK(r.state == "done" and r.teleports == 0 and r.ticks <= 200, "12 blocks: flown, " .. r.ticks .. " ticks (old 242)")
-- drone work legs (DW.goNear)
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 160,
  players = { Alaory = { x = 0, y = 70, z = 0 } }, run = function(dr) DW.goNear(dr, 42, 72, 0, true) end })
CHECK(r.ticks <= 130, "work leg 40 blocks: one teleport, " .. r.ticks .. " ticks (old 281)")
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 160, air = 3,
  players = { Alaory = { x = 0, y = 70, z = 0 } }, run = function(dr) DW.goNear(dr, 42, 72, 0, true) end })
CHECK(r.teleports == 0 and r.flights == 1, "work leg 40 blocks with little air: flown (no air), " .. r.ticks .. " ticks")
-- the hop length that worked is remembered: the next far ride starts with it (no refused first hop)
local dr = drones[droneOrder[1]]
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 100,
  players = { Alaory = { x = 0, y = 70, z = 0 } }, dest = { kind = "coords", x = 900, y = 80, z = 0 },
  mission = { kind = "ferry", passenger = "Alaory" } })
local learned = dr.hopOK
CHECK(learned and learned <= 100, "a short view distance: the hop that works is learned (" .. tostring(learned) .. ")")
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 100, hopOK = learned,
  players = { Alaory = { x = 0, y = 70, z = 0 } }, dest = { kind = "coords", x = 900, y = 80, z = 0 },
  mission = { kind = "ferry", passenger = "Alaory" } })
CHECK(r.refused == 0, "the next ride: no refused hop (" .. r.refused .. ")")
