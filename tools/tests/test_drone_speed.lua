-- DRONE SPEED, MEASURED IN SERVER TICKS (the owner: "the drones are slow" + "you know a server will have a low
-- TPS"). tools/tests/lib/drone_sim.lua runs the real missions against a PneumaticCraft-like drone: a teleport =
-- 120 ticks of warm-up and only into a LOADED spot (refused = the same 120 ticks + its air), flying 0.15 blocks a
-- tick. The old code (numbers in the checks): a ride 300 blocks out first tried a straight teleport and one into
-- the air above - both refused (nobody there loads it): 726 ticks; a work leg of 40 blocks flew with a teleport's
-- 8-s limit (= 24 blocks), was stopped, then teleported: 281 ticks.
dofile(SRC_DIR .. "/tools/tests/lib/drone_sim.lua")
local HOME = { x = 0, y = 70, z = 0 }
state.owner = "Alaory"
-- (these first checks: a server that RUNS 160+ blocks around players - simulation distance 12; the simulation-distance
--  checks are at the end)
setSetting("drone.simChunks", 12)
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

resetSetting("drone.simChunks")
-- SIMULATION DISTANCE (the owner: "when a drone hop-teleports I get stuck in an unloaded chunk, I see the world
-- unloading, I never move even when I am on it"): a teleport is accepted into any LOADED chunk, but the drone only
-- RUNS within the server's simulation distance of a player. The model: runs within simR = 96 blocks; the old code
-- hopped 160 and froze there with its rider for good.
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 160, simR = 96,
  players = { Alaory = { x = 0, y = 70, z = 0 } }, dest = { kind = "coords", x = 1000, y = 80, z = 0 },
  mission = { kind = "ferry", passenger = "Alaory" } })
CHECK(r.state == "done" and r.freezes == 0, "simulation distance 6 chunks: hops stay inside it - the ride gets there, " ..
      "never frozen (" .. tostring(r.state) .. ", " .. r.freezes .. " freezes, " .. r.ticks .. " ticks)")
CHECK(dr.hopOK and dr.hopOK <= safeHop(), "hops no longer than the simulation distance allows (" .. tostring(dr.hopOK) ..
      " <= " .. safeHop() .. ")")
-- set too high (10 chunks = hops of 128) on a server that runs only 96 blocks: the freeze is NOTICED - the rider is
-- told, the next hops are shorter (not: silence for minutes, the base retrying into nothing)
setSetting("drone.simChunks", 10)
local told = {}
local ct0 = chatTell
chatTell = function(n, t) told[#told + 1] = tostring(n) .. ": " .. tostring(t) end
r = DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 160, simR = 96,
  players = { Alaory = { x = 0, y = 70, z = 0 } }, dest = { kind = "coords", x = 1000, y = 80, z = 0 },
  mission = { kind = "ferry", passenger = "Alaory" } })
chatTell = ct0
resetSetting("drone.simChunks")
CHECK(r.freezes == 1 and tostring(r.err):find("froze", 1, true), "a hop beyond the simulation distance: the freeze is " ..
      "noticed (" .. tostring(r.err) .. ")")
CHECK(table.concat(told, " | "):find("Alaory: The drone is stuck", 1, true), "the rider is told what happened: " ..
      table.concat(told, " | "))
CHECK(dr.hopOK and dr.hopOK <= 80, "next time: shorter hops (" .. tostring(dr.hopOK) .. ")")
-- A PLAYER AS A SPRINGBOARD (the owner: "make drones teleport to a player - up in the sky - who is near the wanted area,
-- and the drone hops from there"): Bob plays 2,600 blocks out on the way to 3,000 - one teleport into the sky above him,
-- then the last ~400 in hops (instead of ~47 hops from the base)
local function far(withBob)
  state.online = { alaory = true, bob = true }
  local P = { Alaory = { x = 0, y = 70, z = 0 } }
  if withBob then P.Bob = { x = 2600, y = 72, z = 30 } end
  dr.hopOK, dr.hopTrust = nil, nil
  return DRONE_SIM.run({ home = HOME, start = { x = 2, y = 70, z = 0 }, loadedR = 96, simR = 96, air = 10,
    players = P, dest = { kind = "coords", x = 3000, y = 80, z = 0 }, mission = { kind = "ferry", passenger = "Alaory" } })
end
local r0 = far(false)
local r1 = far(true)
local viaBob = false
for _, l in ipairs(r1.log) do if l:find("teleported to 2600 ", 1, true) then viaBob = true end end
CHECK(viaBob, "the drone first teleports into the sky above Bob (the player near the target)")
CHECK(r1.state == "done" and r1.freezes == 0, "... and gets there (" .. tostring(r1.state) .. " " .. tostring(r1.err) .. ")")
CHECK(r1.teleports <= r0.teleports and r1.ticks < r0.ticks / 4, "... far quicker: " .. r1.teleports .. " teleports / " ..
      r1.ticks .. " ticks instead of " .. r0.teleports .. " / " .. r0.ticks)
-- a player in another dimension at those x z, or offline, is no springboard
state.players = { { name = "Bob", p = { x = 2600, y = 72, z = 30 }, dim = "minecraft:the_nether" } }
CHECK(springboard(dr, 3000, 0) == nil, "a player in the Nether is no springboard")
state.players = { { name = "Bob", p = { x = 2600, y = 72, z = 30 }, dim = DRONE_DIM } }
state.online = { alaory = true }
CHECK(springboard(dr, 3000, 0) == nil, "an offline player is no springboard")
