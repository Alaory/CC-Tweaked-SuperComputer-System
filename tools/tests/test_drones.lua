-- Drone missions in a small fake world (teleport mode): the right / wrong
-- passenger, chat rides vs the DRONES page, failures bring the drone home,
-- PICKUP-and-hold stays, STOP stays, a passenger is never let out mid-air.
local HOME = { x = 0, y = 70, z = 0 }
local W                                   -- this scenario's world
local function world(opts)
  W = { pos = { x = 2, y = 70, z = 0 }, P = opts.players, carry = nil, act = nil, aborts = 0,
        grab = opts.grab, miss = opts.miss, hang = opts.hang or 1, short = opts.short or 0, unreachable = opts.unreachable or 1e9, homeRefused = opts.homeRefused or 0 }
  os.pullEventRaw = function()
    CLOCK = CLOCK + 0.3
    if W.act and CLOCK >= W.doneAt then
      local t = W.target
      if W.act == "pneumaticcraft:entity_import" then
        local who = W.grab
        if W.miss then who = nil                 -- the grab catches nobody (the drone is next to you anyway)
        elseif not who then           -- the player at the import spot
          for n, p in pairs(W.P) do if math.abs(p.x - t.x) <= 1 and math.abs(p.z - t.z) <= 1 then who = n end end
        end
        if who then W.pos = { x = W.P[who].x, y = W.P[who].y, z = W.P[who].z } W.carry = who end
      elseif W.act == "pneumaticcraft:entity_export" then
        if W.carry then W.P[W.carry] = { x = t.x, y = t.y, z = t.z } end
        W.carry = nil
      elseif t.x >= W.unreachable then
        -- refused: not loaded
      elseif t.x == HOME.x and math.abs(t.z - HOME.z) < 8 and W.homeRefused > 0 then
        W.homeRefused = W.homeRefused - 1
      else
        -- (a FLY move counts as there within 2.5 blocks: it may stop short when climbing)
        local sy = (W.act == "pneumaticcraft:goto" and t.y > W.pos.y) and (t.y - W.short) or t.y
        W.pos = { x = t.x, y = sy, z = t.z }
      end
      W.act = nil
    end
    if W.carry then W.P[W.carry] = { x = W.pos.x, y = W.pos.y - W.hang, z = W.pos.z } end
    return "timer", 1
  end
  os.pullEvent = os.pullEventRaw
  local per = {
    clearArea = function() end, addArea = function(x, y, z) W.target = { x = x, y = y, z = z } end,
    setAction = function(a) W.act = a W.doneAt = CLOCK + (a == "pneumaticcraft:teleport" and 1 or 3) end,
    isConnectedToDrone = function() return true end, abortAction = function() W.act = nil W.aborts = W.aborts + 1 end,
    getDronePosition = function() return W.pos.x + 0.5, W.pos.y + 0.5, W.pos.z + 0.5 end,
    isActionDone = function() return W.act == nil end, getDronePressure = function() return 9 end,
    clearWhitelistText = function() end, clearBlacklistText = function() end, addWhitelistText = function() end,
    setUseCount = function() end, exitPiece = function() end, getAction = function() return W.act end }
  det = { getPlayer = function(n) local p = W.P[n] return p and { x = p.x, y = p.y, z = p.z, dimension = "minecraft:overworld" } end,
          getOnlinePlayers = function() local l = {} for n in pairs(W.P) do l[#l + 1] = n end return l end }
  playerDimNow = function() return DRONE_DIM end
  CONFIG.drone.travel, CONFIG.drone.home, CONFIG.drone.returnHome, CONFIG.drone.charger = "teleport", HOME, true, nil
  CONFIG.drone.liftCheck = false
  local dr = drones[droneOrder[1]]
  dr.periph, dr.gone, dr.busy, dr.queue, dr.mission = per, false, false, {}, nil
  dr.rider, dr.failedAt, dr.lastPark, dr.awaySince, dr.mdest, dr.checkAboard, dr.notAboard = nil, nil, nil, nil, nil, nil, nil
  refreshDrone = function(d) d.conn = true d.pos = { x = W.pos.x + 0.5, y = W.pos.y + 0.5, z = W.pos.z + 0.5 } end
  state.owner = "Alaory"
  return dr
end
local function near(p, x, z) return p and math.abs(p.x - x) <= 3 and math.abs(p.z - z) <= 3 end

-- a normal ride: Bob to Alaory
local dr = world({ players = { Bob = { x = 300, y = 70, z = 0 }, Alaory = { x = 0, y = 70, z = 0 } } })
dr.dest = { kind = "player", name = "Alaory" }
runMission(dr, { kind = "ferry", passenger = "Bob" })
CHECK(dr.mission.state == "done", "ride: done (" .. tostring(dr.mission.err) .. ")")
CHECK(near(W.P.Bob, 0, 0), "ride: Bob is at Alaory")

-- the name filter does not work: it grabs Alaory instead of Bob -> let go at once
dr = world({ players = { Bob = { x = 300, y = 70, z = 0 }, Alaory = { x = 0, y = 70, z = 0 } }, grab = "Alaory" })
dr.dest = { kind = "player", name = "Alaory" }
runMission(dr, { kind = "ferry", passenger = "Bob" })
CHECK(dr.mission.state == "failed" and tostring(dr.mission.err):find("instead of", 1, true), "wrong player: refused")
CHECK(near(W.P.Alaory, 0, 0), "wrong player: Alaory stays where she was")
CHECK(W.carry == nil, "wrong player: nobody on board")

-- the grab catches nobody: the drone stands next to Bob all the same - it must NOT
-- think he is on board and teleport away without him
dr = world({ players = { Bob = { x = 300, y = 70, z = 0 }, Alaory = { x = 0, y = 70, z = 0 } }, miss = true })
dr.dest = { kind = "player", name = "Alaory" }
local tps = 0
local setA = dr.periph.setAction
dr.periph.setAction = function(a) if a == "pneumaticcraft:teleport" and W.target and W.target.x < 250 then tps = tps + 1 end return setA(a) end
runMission(dr, { kind = "ferry", passenger = "Bob" })
CHECK(dr.mission.state == "failed", "missed grab: the ride fails (" .. tostring(dr.mission.err) .. ")")
CHECK(tps == 0 or not tostring(dr.mission.steps[2] and dr.mission.steps[2].status):find("done"),
      "missed grab: never flew off to the destination without him")
CHECK(dr.mission.steps[1].status == "fail", "missed grab: noticed at the pickup, not at the destination (" ..
      tostring(dr.mission.err) .. ")")
CHECK(dr.rider == nil, "missed grab: nobody counted as on board")
CHECK(near(W.P.Bob, 300, 0), "missed grab: Bob where he was")

-- a long ride (hops of 160 - the far end is not loaded yet) and you get off half way:
-- the drone must not hop on into unloaded land without you; it goes home
for _, mode in ipairs({ "gets off", "logs off" }) do
  dr = world({ players = { Bob = { x = 0, y = 70, z = 0 } }, unreachable = 900 })
  dr.dest = { kind = "coords", x = 1000, y = 80, z = 0 }
  local farTp = 0
  local setA2 = dr.periph.setAction
  dr.periph.setAction = function(a) if a == "pneumaticcraft:teleport" and W.target and W.target.x >= 500 and W.target.x < 900 then farTp = farTp + 1 end return setA2(a) end
  local pe = os.pullEventRaw
  os.pullEventRaw = function(...)
    local r1, r2 = pe(...)
    if W.carry == "Bob" and W.pos.x >= 300 then
      if mode == "logs off" then W.P.Bob = nil end
      W.carry = nil
    end
    return r1, r2
  end
  os.pullEvent = os.pullEventRaw
  runMission(dr, { kind = "ferry", passenger = "Bob" })
  os.pullEventRaw, os.pullEvent = pe, pe
  CHECK(dr.mission.state == "failed" and tostring(dr.mission.err):find("got off", 1, true),
        "you " .. mode .. " half way: the ride ends (" .. tostring(dr.mission.err) .. ")")
  CHECK(farTp == 0, "you " .. mode .. " half way: no more hops into unloaded land (" .. farTp .. ")")
  CHECK(near(W.pos, HOME.x, HOME.z), "you " .. mode .. " half way: the drone went home")
end

-- a chat ride: what was asked in chat, not what is on the DRONES page
dr = world({ players = { Bob = { x = 300, y = 70, z = 0 }, Alaory = { x = 0, y = 70, z = 0 } } })
for _, k in ipairs(droneOrder) do drones[k].conn = true drones[k].pressure = 9 drones[k].periph = dr.periph drones[k].busy = false end
dr.passenger, dr.dest = "Alaory", { kind = "player", name = "Bob" }      -- the monitor's choice
local refresh0, tell0 = refreshDrones, chatTell
refreshDrones, chatTell = function() end, function() end
startRide("Bob", { kind = "player", name = "Alaory" }, false)
refreshDrones, chatTell = refresh0, tell0
local cmd
for _, k in ipairs(droneOrder) do local q = drones[k].queue if q[1] then cmd = table.remove(q, 1) dr = drones[k] end end
CHECK(cmd and cmd.passenger == "Bob" and cmd.dest and cmd.dest.name == "Alaory", "chat ride: Bob to Alaory")
if cmd then runMission(dr, cmd) end
CHECK(near(W.P.Bob, 0, 0) and near(W.P.Alaory, 0, 0), "chat ride: Bob flown to Alaory, Alaory not moved")
CHECK(dr.passenger == "Alaory" and dr.dest.name == "Bob", "chat ride: the DRONES page choice is unchanged")

-- a failed flight: home at once
dr = world({ players = { Alaory = { x = 0, y = 70, z = 0 } }, unreachable = 900 })
dr.dest = { kind = "coords", x = 1000, y = 80, z = 0 }
runMission(dr, { kind = "fly" })
CHECK(dr.mission.state == "failed", "failed flight: failed")
CHECK(near(W.pos, HOME.x, HOME.z), "failed flight: the drone is home")
CHECK(W.aborts > 0, "failed flight: its action was stopped")

-- a failed ride, and the first trip home is refused too: rider kept (not let out
-- mid-air), the park check brings it home later and lets the rider out there
dr = world({ players = { Bob = { x = 50, y = 70, z = 0 } }, unreachable = 900, homeRefused = 3 })
dr.dest = { kind = "coords", x = 1000, y = 80, z = 0 }
local rescue0 = rescueToBase
rescueToBase = function() return false, "home not loaded" end
runMission(dr, { kind = "ferry", passenger = "Bob" })
rescueToBase = rescue0
CHECK(dr.mission.state == "failed", "failed ride: failed")
CHECK(W.carry == "Bob" and dr.rider == "Bob", "failed ride: Bob still on board (not dropped mid-air)")
W.homeRefused = 0
for _ = 1, 3 do
  parkCheck()
  local c = table.remove(dr.queue, 1)
  if c then dr.busy = true runMission(dr, c) dr.busy = false end
end
CHECK(near(W.pos, HOME.x, HOME.z), "failed ride: home later")
CHECK(W.carry == nil and near(W.P.Bob, HOME.x, HOME.z), "failed ride: Bob let out at home")

-- a REAL ride: the player hangs 2.5 blocks UNDER the drone and the lift stops 2
-- blocks short (it counts as there within 2.5) - before, "did not come along":
-- the drone let them out at the pickup spot and flew home without them
dr = world({ players = { Bob = { x = 60, y = 70, z = 0 } }, hang = 2.5, short = 2 })
runMission(dr, { kind = "pickup", passenger = "Bob" })
CHECK(dr.rider == "Bob" and W.carry == "Bob", "hanging under the drone, short lift: still counted as on board")
-- and nobody on board (the grab missed): still caught
dr = world({ players = { Bob = { x = 60, y = 70, z = 0 } }, hang = 2.5, short = 2, miss = true })
runMission(dr, { kind = "pickup", passenger = "Bob" })
CHECK(dr.rider == nil, "missed grab with the real offsets: nobody counted as on board")

-- PICKUP and hold (the owner DROPs later): the park check leaves it alone
dr = world({ players = { Bob = { x = 50, y = 70, z = 0 } } })
runMission(dr, { kind = "pickup", passenger = "Bob" })
CHECK(dr.rider == "Bob", "pickup: Bob on board")
parkCheck() parkCheck()
CHECK(#dr.queue == 0, "pickup: not sent home while holding a passenger on purpose")

-- STOP is not a failure: no trip home
dr = world({ players = { Alaory = { x = 0, y = 70, z = 0 } } })
dr.dest = { kind = "coords", x = 200, y = 80, z = 0 }
local origStep = stepGoto
dr.abort = false
local trip = W
os.pullEventRaw = (function(f) return function(...) dr.abort = true return f(...) end end)(os.pullEventRaw)
os.pullEvent = os.pullEventRaw
runMission(dr, { kind = "fly" })
CHECK(dr.mission.state == "stopped", "stop: stopped (" .. tostring(dr.mission.state) .. ")")
CHECK(dr.failedAt == nil, "stop: not counted as a failure")
dr.abort = false
