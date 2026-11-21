-- DRONE WORK (base_dronework.lua) in a small fake world: the work chest, AE2, a drone that
-- teleports / takes / puts / places / digs. A schematic is built bottom up and checked block
-- by block; leftovers go back into AE2; your own (enchanted) items are never taken; a taken
-- spot is counted; a restart goes on where it was; clear digs the air spots first; a site
-- nobody keeps loaded gets a turtle first; fuel runs to a turtle with NO FUEL.
local HOME = { x = 0, y = 70, z = 0 }
local BRIDGE0 = bridge
bridgeKind = bridgeKind or "ME"
local CH = { x = 2, y = 69, z = 0 }
local W
local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function world()
  W = { pos = { x = 0, y = 71, z = 0 }, inv = {}, area = {}, act = nil, blocks = {}, order = {},
        chest = {}, stock = { ["minecraft:stone"] = 100, ["minecraft:oak_planks"] = 100, ["minecraft:coal"] = 500 },
        own = { ["minecraft:stone"] = 1 }, tinv = {}, refused = {}, teleports = 0, sides = {} }
  function W.anySide() for _, v in pairs(W.sides or {}) do if v == true then return true end end return false end
  local function invAdd(t, name, n) t[name] = (t[name] or 0) + n end
  local function invCount(t) local c = 0 for _, n in pairs(t) do c = c + n end return c end
  os.pullEventRaw = function()
    CLOCK = CLOCK + 0.3
    if W.act and CLOCK >= W.doneAt then
      local a, pts = W.act, W.area
      local p = pts[1]
      if a == "pneumaticcraft:teleport" then W.teleports = W.teleports + 1 end
      if a == "pneumaticcraft:teleport" or a == "pneumaticcraft:goto" then
        if not W.refused[math.floor(p.x / 16) .. "," .. math.floor(p.z / 16)] then W.pos = { x = p.x, y = p.y, z = p.z } end
      elseif a == "pneumaticcraft:inventory_import" then
        -- (like PneumaticCraft: a computer-controlled drone uses only the SELECTED sides, none at first)
        if key(p.x, p.y, p.z) == key(CH.x, CH.y, CH.z) and W.anySide() then
          local room = (CONFIG.drone.slots or 1) * 64 - invCount(W.inv)
          for name, n in pairs(W.chest) do
            local take = math.min(n, room)
            if take > 0 then invAdd(W.inv, name, take) W.chest[name] = n - take room = room - take end
            if W.chest[name] == 0 then W.chest[name] = nil end
          end
        end
      elseif a == "pneumaticcraft:inventory_export" then
        local target = (key(p.x, p.y, p.z) == key(CH.x, CH.y, CH.z)) and W.chest or W.tinv[key(p.x, p.y, p.z)]
        if target and W.anySide() then
          for name, n in pairs(W.inv) do invAdd(target, name, n) end
          W.inv = {}
        end
      elseif a == "pneumaticcraft:drop_item" then
        W.dropped = W.dropped or {}
        for name, n in pairs(W.inv) do W.dropped[name] = (W.dropped[name] or 0) + n end
        W.dropAt, W.dropFrom = { x = p.x, y = p.y, z = p.z }, { x = W.pos.x, y = W.pos.y, z = W.pos.z }
        W.inv = {}
      elseif a == "pneumaticcraft:place" then
        for _, q in ipairs(pts) do
          local name = next(W.inv)
          if not name then break end
          local k = key(q.x, q.y, q.z)
          if not W.blocks[k] then
            W.blocks[k] = name
            W.order[#W.order + 1] = q.y
            W.inv[name] = W.inv[name] - 1
            if W.inv[name] == 0 then W.inv[name] = nil end
          end
        end
      elseif a == "pneumaticcraft:dig" then
        for _, q in ipairs(pts) do
          local k = key(q.x, q.y, q.z)
          if W.blocks[k] then invAdd(W.inv, W.blocks[k], 1) W.blocks[k] = nil end
        end
      end
      W.act = nil
    end
    return "timer", 1
  end
  os.pullEvent = os.pullEventRaw
  local per = {
    clearArea = function() W.area = {} end,
    addArea = function(x, y, z) W.area[#W.area + 1] = { x = x, y = y, z = z } end,
    setAction = function(a)
      if a:find("condition", 1, true) then W.act = nil return end
      W.act, W.doneAt = a, CLOCK + 0.9
    end,
    isConnectedToDrone = function() return true end, abortAction = function() W.act = nil end,
    getDronePosition = function() return W.pos.x + 0.5, W.pos.y + 0.5, W.pos.z + 0.5 end,
    isActionDone = function() return W.act == nil end, getDronePressure = function() return 9 end,
    clearWhitelistText = function() end, clearBlacklistText = function() end, addWhitelistText = function() end,
    clearWhitelistItemFilter = function() end, setUseCount = function() end, exitPiece = function() end,
    setSides = function(...) W.sides = { ... } end,
    setSide = function(s, v) W.sides = W.sides or {} W.sides[#W.sides + 1] = v end,
    getAction = function() return W.act end, setOperator = function() end, setCount = function() end,
    evaluateCondition = function() return false end,
  }
  -- AE2: plain items + one of YOUR stone (enchanted) that must never be taken
  bridge = {
    getItems = function(f)
      local out = {}
      if (W.stock[f.name] or 0) > 0 then out[#out + 1] = { name = f.name, amount = W.stock[f.name], fingerprint = "plain-" .. f.name } end
      if W.own[f.name] then out[#out + 1] = { name = f.name, amount = W.own[f.name], fingerprint = "own", enchantments = { { name = "sharpness", level = 5 } } } end
      return out
    end,
    exportItem = function(f, target)
      if type(f) ~= "table" then return nil end
      assert(target == "minecraft:barrel_9", "exported somewhere else: " .. tostring(target))
      if f.fingerprint == "own" then W.tookOwn = true end
      local n = math.min(f.count or 0, W.stock[f.name] or 0)
      W.stock[f.name] = (W.stock[f.name] or 0) - n
      W.chest[f.name] = (W.chest[f.name] or 0) + n
      return n
    end,
    importItem = function(f, from)
      if type(f) ~= "table" then return nil end
      local n = math.min(f.count or 0, W.chest[f.name] or 0)
      W.chest[f.name] = W.chest[f.name] - n
      if W.chest[f.name] == 0 then W.chest[f.name] = nil end
      W.stock[f.name] = (W.stock[f.name] or 0) + n
      return n
    end,
  }
  PERIPHS["minecraft:barrel_9"] = { types = { "minecraft:barrel", "inventory" }, obj = {
    list = function() local l, i = {}, 0 for name, n in pairs(W.chest) do i = i + 1 l[i] = { name = name, count = n } end return l end,
    size = function() return 27 end } }
  CONFIG.drone.travel, CONFIG.drone.home, CONFIG.drone.returnHome, CONFIG.drone.charger = "teleport", HOME, true, nil
  CONFIG.drone.workChest, CONFIG.drone.workChestAt, CONFIG.drone.slots = "minecraft:barrel_9", CH, 1
  local dr = drones[droneOrder[1]]
  for _, k in ipairs(droneOrder) do drones[k].busy = true end            -- (only the first one works here)
  dr.periph, dr.gone, dr.busy, dr.queue, dr.mission, dr.conn = per, false, false, {}, nil, true
  dr.rider, dr.failedAt, dr.workSlots = nil, nil, nil
  refreshDrone = function(d) d.conn = true d.pos = { x = W.pos.x + 0.5, y = W.pos.y + 0.5, z = W.pos.z + 0.5 } end
  state.owner = "Alaory"
  state.players = { { name = "Alaory", isOwner = true, p = { x = 0, y = 70, z = 0 }, dim = DRONE_DIM } }
  state.turtles = {}
  DW.job, DW.trip, DW.runs, DW.auto = nil, nil, {}, nil
  return dr
end

-- run the comms tick + the drone worker until nothing is left to do
local function run(dr, maxTicks)
  for _ = 1, maxTicks or 200 do
    DW.tick()
    if #dr.queue > 0 then
      local cmd = table.remove(dr.queue, 1)
      runMission(dr, cmd)
      dr.busy = false
    elseif not DW.job and not DW.trip then
      DW.tick()
      return
    end
    CLOCK = CLOCK + 2
  end
end

-- a 3 x 2 x 3 schematic: a stone floor, a ring of planks above it, air in the middle
local s = { size = { x = 3, y = 2, z = 3 }, palette = { { name = "minecraft:stone", props = {} },
            { name = "minecraft:oak_planks", props = {} }, { name = "minecraft:air", props = {} } }, blocks = {} }
for x = 0, 2 do for z = 0, 2 do
  s.blocks[#s.blocks + 1] = { x, 0, z, 1 }
  s.blocks[#s.blocks + 1] = { x, 1, z, (x == 1 and z == 1) and 3 or 2 }
end end
SCHEM.cache["hut"] = { s = s, path = "schematics/hut.nbt" }

------------------------------------------------------------------ a normal build
local dr = world()
local OX, OY, OZ = 20, 64, 20
W.blocks[key(OX + 1, OY + 1, OZ + 1)] = "minecraft:dirt"    -- in the middle (air in the schematic): left alone without clear
local ok, msg = DW.startBuild("hut", OX, OY, OZ, 0, false)
CHECK(ok, "build starts (" .. tostring(msg) .. ")")
run(dr)
local good = 0
for x = 0, 2 do for z = 0, 2 do
  if W.blocks[key(OX + x, OY, OZ + z)] == "minecraft:stone" then good = good + 1 end
  if not (x == 1 and z == 1) and W.blocks[key(OX + x, OY + 1, OZ + z)] == "minecraft:oak_planks" then good = good + 1 end
end end
CHECK(good == 17, "every block of the schematic is placed (" .. good .. "/17)")
local bottomFirst = true
for i = 2, #W.order do if W.order[i] < W.order[i - 1] then bottomFirst = false end end
CHECK(bottomFirst, "bottom layer first")
CHECK(W.stock["minecraft:stone"] == 91 and W.stock["minecraft:oak_planks"] == 92, "exactly the blocks used left AE2 (stone " ..
      tostring(W.stock["minecraft:stone"]) .. ", planks " .. tostring(W.stock["minecraft:oak_planks"]) .. ")")
CHECK(next(W.chest) == nil and next(W.inv) == nil, "work chest and drone empty at the end")
CHECK(not W.tookOwn and W.own["minecraft:stone"] == 1, "your own (enchanted) stone was never taken")
CHECK(W.blocks[key(OX + 1, OY + 1, OZ + 1)] == "minecraft:dirt", "without clear nothing is dug")
CHECK(DW.job == nil, "the build is finished")
CHECK(W.teleports > 0, "a build next to the base with air to spare: legs over ~18 blocks TELEPORT (120 ticks vs " ..
      "flying 0.15 blocks a tick): " .. tostring(W.teleports))
-- low on air: the same build FLIES (no air used)
do
  local dr2 = world()
  dr2.periph.getDronePressure = function() return 3 end
  DW.startBuild("hut", OX + 40, OY, OZ, 0, false)
  run(dr2)
  CHECK(W.teleports == 0, "low on air: the build legs FLY (teleports: " .. tostring(W.teleports) .. ")")
end

------------------------------------------------------------------ a taken spot, a restart, clear
dr = world()
W.blocks[key(OX, OY, OZ)] = "minecraft:cobblestone"          -- a spot of the floor is taken
W.blocks[key(OX + 1, OY + 1, OZ + 1)] = "minecraft:dirt"     -- clear: must be dug
ok = DW.startBuild("hut", OX, OY, OZ, 0, true)
CHECK(ok, "build with clear starts")
-- one trip (the clearing), then the base restarts (memory gone, the file stays)
DW.tick()
if #dr.queue > 0 then runMission(dr, table.remove(dr.queue, 1)) dr.busy = false end
CLOCK = CLOCK + 2
DW.tick()
local before = DW.job and DW.job.dug
DW.job, DW.trip = nil, nil
DW.load()
CHECK(DW.job and DW.job.name == "hut" and DW.job.dug == before, "after a restart the build is read back (dug " .. tostring(before) .. ")")
run(dr)
CHECK(W.blocks[key(OX + 1, OY + 1, OZ + 1)] == nil, "clear: the air spot was dug")
CHECK(W.stock["minecraft:dirt"] == 1, "the dug dirt went into AE2")
CHECK(W.blocks[key(OX, OY, OZ)] == "minecraft:cobblestone", "the taken spot is left as it was (no clear for blocks)")
CHECK(W.stock["minecraft:stone"] == 92, "the stone that did not fit went back into AE2 (stone " .. tostring(W.stock["minecraft:stone"]) .. ")")
CHECK(next(W.chest) == nil and next(W.inv) == nil, "nothing left in the chest / drone after the taken spot")

------------------------------------------------------------------ a site nobody keeps loaded
dr = world()
local FX, FZ = 600, 600
W.refused[math.floor(FX / 16) .. "," .. math.floor(FZ / 16)] = true    -- (teleports there fail until it is loaded)
state.turtles = { [7] = { id = 7, label = "T7", log = {}, lastSeen = os.clock(), pos = { x = 5, y = 70, z = 5 }, fuel = 50000, task = "idle" } }
local sent = {}
local send0 = TT.send
TT.send = function(id, cmd, args) sent[#sent + 1] = { id = id, cmd = cmd, args = args } end
ok = DW.startBuild("hut", FX, 64, FZ, 0, false)
for _ = 1, 3 do DW.tick() CLOCK = CLOCK + 2 state.turtles[7].lastSeen = os.clock() end
CHECK(#dr.queue == 0, "the drone does not go to a site that is not loaded")
CHECK(sent[1] and sent[1].id == 7 and sent[1].cmd == "goto" and math.floor(sent[1].args[1] / 16) == math.floor(FX / 16)
      and sent[1].args[2] > 66, "a turtle is sent there first, above the build (" .. tostring(sent[1] and sent[1].cmd) .. ")")
CHECK(state.turtles[7].dwAnchor and TT.idleWhy(state.turtles[7]):find("drone build", 1, true), "the turtle is the site's anchor")
local avail = TT.available()
CHECK(#avail == 0, "the anchor gets no other work")
-- it arrives: the chunk is loaded now
state.turtles[7].pos = { x = sent[1].args[1], y = sent[1].args[2], z = sent[1].args[3] }
W.refused = {}
for _ = 1, 300 do
  state.turtles[7].lastSeen = os.clock()
  DW.tick()
  if #dr.queue > 0 then runMission(dr, table.remove(dr.queue, 1)) dr.busy = false end
  if not DW.job and not DW.trip then break end
  CLOCK = CLOCK + 2
end
CHECK(W.blocks[key(FX, 64, FZ)] == "minecraft:stone" and W.blocks[key(FX + 2, 65, FZ + 2)] == "minecraft:oak_planks",
      "then the drone builds there")
CHECK(not state.turtles[7].dwAnchor and sent[#sent].cmd == "home", "after the build the turtle goes home")
TT.send = send0

------------------------------------------------------------------ fuel run
dr = world()
local TP = { x = 40, y = 64, z = 40 }
W.tinv[key(TP.x, TP.y, TP.z)] = {}
state.turtles = { [9] = { id = 9, label = "T9", lastSeen = os.clock(), pos = { x = TP.x, y = TP.y, z = TP.z }, fuel = 0, task = "idle", log = {} } }
DW.tick()
CHECK(#dr.queue == 0, "no fuel run in the first 30 s (it may refuel itself)")
for _ = 1, 20 do state.turtles[9].lastSeen = os.clock() CLOCK = CLOCK + 2 DW.tick() if #dr.queue > 0 then break end end
CHECK(#dr.queue == 1, "a drone fuel run starts for the turtle with NO FUEL")
CHECK(DW.fuelBusy(state.turtles[9]), "the rescuer waits while the drone flies")
runMission(dr, table.remove(dr.queue, 1)) dr.busy = false
DW.tick()
CHECK((W.tinv[key(TP.x, TP.y, TP.z)]["minecraft:coal"] or 0) == 32, "32 coal in the turtle (" ..
      tostring(W.tinv[key(TP.x, TP.y, TP.z)]["minecraft:coal"]) .. ")")
CHECK(W.stock["minecraft:coal"] == 468 and next(W.chest) == nil, "exactly that coal left AE2")
CHECK(DW.fuelBusy(state.turtles[9]), "the rescuer still waits while the turtle burns it")
state.turtles[9].fuel = 2560
state.turtles[9].lastSeen = os.clock()
DW.tick()
CHECK(DW.runs[9] == nil, "fuel burned: the run is over")
-- offline: no run (its chunk is not loaded)
state.turtles[9].fuel = 0
state.turtles[9].lastSeen = os.clock() - 9999
local okF, whyF = DW.fuelRun(9)
CHECK(not okF and tostring(whyF):find("offline", 1, true), "an offline turtle gets no drone (" .. tostring(whyF) .. ")")

------------------------------------------------------------------ fuel FAR OUT: a drone instead of a trip home
-- (the owner's survey edge is ~2,400 blocks out: a low turtle flew home and back, ~5,000 blocks, for fuel)
dr = world()
CONFIG.drone.slots = 2
W.tinv[key(TP.x, TP.y, TP.z)] = {}
local sentT = {}
local send1 = TT.send
TT.send = function(id, cmd, a, ...) sentT[#sentT + 1] = id .. ":" .. cmd return send1(id, cmd, a, ...) end
state.turtles = { [9] = { id = 9, label = "T9", lastSeen = os.clock(), pos = { x = TP.x, y = TP.y, z = TP.z }, fuel = 3600,
                          task = "idle", log = {}, home = { x = TP.x - 2400, y = 64, z = TP.z } } }
local tf = state.turtles[9]
for _ = 1, 4 do CLOCK = CLOCK + 6 tf.lastSeen = CLOCK TT.homeTick() end
local s1 = table.concat(sentT, " ")
CHECK(tf.dwWant and not s1:find("9:home", 1, true), "low on fuel 2,400 blocks out: waits for a drone, NOT sent home (" .. s1 .. ")")
CHECK(tostring(TT.idleWhy(tf)):find("DRONE", 1, true), "the card says a drone brings fuel")
for _ = 1, 10 do tf.lastSeen = os.clock() CLOCK = CLOCK + 2 DW.tick() if #dr.queue > 0 then break end end
CHECK(#dr.queue == 1, "a drone fuel run starts within seconds")
runMission(dr, table.remove(dr.queue, 1)) dr.busy = false
CHECK((W.tinv[key(TP.x, TP.y, TP.z)]["minecraft:coal"] or 0) == 128, "a FULL load (2 slots x 64), not 32 (" ..
      tostring(W.tinv[key(TP.x, TP.y, TP.z)]["minecraft:coal"]) .. ")")
DW.tick()
CHECK(table.concat(sentT, " "):find("9:refuel", 1, true), "the turtle is told to burn it (it could still get home: it would not by itself)")
tf.fuel = 13000
tf.lastSeen = os.clock()
DW.tick()
CHECK(DW.runs[9] == nil and not tf.dwWant, "fuel burned: done, it works again")
-- no drones set up: the trip home as before
tf.fuel, tf.dwTries, tf.dwTryAt, tf.idleHomeAt, tf.idleSince = 3600, nil, nil, nil, nil
local cf = DW.canFuel
DW.canFuel = function() return false end
sentT = {}
for _ = 1, 4 do CLOCK = CLOCK + 6 tf.lastSeen = CLOCK TT.homeTick() end
CHECK(not tf.dwWant and table.concat(sentT, " "):find("9:home", 1, true), "no drones: sent home as before")
DW.canFuel = cf
-- the drone failed: home next time (not waiting for ever)
tf.idleHomeAt, tf.idleSince = nil, nil
tf.dwEdgeFail = os.clock()
sentT = {}
for _ = 1, 4 do CLOCK = CLOCK + 6 tf.lastSeen = CLOCK TT.homeTick() end
CHECK(not tf.dwWant and table.concat(sentT, " "):find("9:home", 1, true), "a failed drone run: the trip home")
TT.send = send1
CONFIG.drone.slots = nil
state.turtles = {}

------------------------------------------------------------------ gifts (the talking base: friendship rewards)
dr = world()
CONFIG.drone.slots = 2
W.stock["minecraft:diamond"], W.own["minecraft:diamond"] = 100, 1
state.players[#state.players + 1] = { name = "Kevin", p = { x = 6.5, y = 70, z = 3.5 }, dim = DRONE_DIM }
local gOk, gDel, gWhy
local okG, whyG = DW.giftRun("Kevin", "minecraft:diamond", 100, function(o, d, w) gOk, gDel, gWhy = o, d, w end, function() return true end)
CHECK(okG, "a gift trip starts: " .. tostring(whyG))
CHECK(not DW.giftRun("Kevin", "minecraft:diamond", 5, nil), "... only one drone job at a time")
run(dr)
CHECK(gOk and gDel == 100 and W.dropped and W.dropped["minecraft:diamond"] == 100, "100 diamonds dropped (2 slots = 128 max): " .. tostring(gDel) .. " / " .. tostring(gWhy))
CHECK(W.dropAt and W.dropAt.x == 6 and W.dropAt.z == 3 and W.dropAt.y == 71, "dropped right next to Kevin")
CHECK(not W.tookOwn and W.stock["minecraft:diamond"] == 0 and W.own["minecraft:diamond"] == 1, "only PLAIN diamonds - your own one stays in AE2")
-- the player leaves the base: the trip stops, nothing is dropped, everything goes back to AE2
dr = world()
CONFIG.drone.slots = 1
W.stock["minecraft:emerald"] = 50
state.players[#state.players + 1] = { name = "Kevin", p = { x = 6.5, y = 70, z = 3.5 }, dim = DRONE_DIM }
local here = true
gOk, gDel = nil, nil
DW.giftRun("Kevin", "minecraft:emerald", 32, function(o, d) gOk, gDel = o, d end, function() return here end)
here = false
run(dr)
CHECK(gOk == false and gDel == 0 and not (W.dropped and W.dropped["minecraft:emerald"]), "the player left: no gift dropped (" .. tostring(gOk) .. ")")
run(dr)
DW.tick()
local inDrone = W.inv["minecraft:emerald"] or 0
CHECK(W.stock["minecraft:emerald"] + inDrone == 50, "the emeralds are back in AE2 or still in the drone for the next first step (" .. W.stock["minecraft:emerald"] .. " + " .. inDrone .. ")")
-- another dimension: no trip
state.players[#state.players].dim = "minecraft:the_nether"
local okD, whyD = DW.giftRun("Kevin", "minecraft:emerald", 5, nil)
CHECK(not okD and tostring(whyD):find("another dimension", 1, true), "a player in another dimension gets no drone (" .. tostring(whyD) .. ")")
CONFIG.drone.slots = 1

------------------------------------------------------------------ dw test (the owner: "how do I test the drone chest")
dr = world()
state.owner = "Alaory"
state.players = { { name = "Alaory", isOwner = true, p = { x = CH.x + 3.5, y = CH.y + 1, z = CH.z + 0.5 }, dim = DRONE_DIM } }
local notes = {}
local realNote = pushNote
pushNote = function(kind, msg, col) notes[#notes + 1] = tostring(kind) .. ": " .. tostring(msg) end
local tl = {}
local okT = DW.test(function(l) tl[#tl + 1] = l end)
local tt = table.concat(tl, "\n")
CHECK(okT and tt:find("OK: AE2 put 1 Stone into the work chest", 1, true) and tt:find("OK: it went back into AE2", 1, true),
      "dw test: AE2 -> work chest -> AE2 with a plain item it has (stone)\n" .. tt)
CHECK(W.stock["minecraft:stone"] == 100 and next(W.chest) == nil, "... and it is all back in AE2")
CHECK(tt:find("brings 1 Stone to Alaory", 1, true), "you stand near the chest: a drone brings one to you")
run(dr)
CHECK(W.dropped and W.dropped["minecraft:stone"] == 1, "the drone took it out of the work chest and dropped it next to you")
CHECK(notes[#notes] and notes[#notes]:find("DONE: DRONE TEST: it works", 1, true), "a DONE note says it worked: " .. tostring(notes[#notes]))
-- far from the chest: only the base side, and it says how to do the drone part
dr = world()
state.players[1].p = { x = CH.x + 500, y = CH.y, z = CH.z }
tl = {}
CHECK(DW.test(function(l) tl[#tl + 1] = l end), "far away: the base side still tested")
tt = table.concat(tl, "\n")
CHECK(tt:find("stand within 48 blocks", 1, true) and #dr.queue == 0, "far away: no drone, it says to come closer\n" .. tt)
-- a test item named by you; one AE2 does not have
tl = {}
CHECK(not DW.test(function(l) tl[#tl + 1] = l end, "minecraft:nether_star") and table.concat(tl, " "):find("no plain", 1, true),
      "an item AE2 does not have: it says so")
-- no work chest yet
local wc = CONFIG.drone.workChest
CONFIG.drone.workChest = nil
tl = {}
CHECK(not DW.test(function(l) tl[#tl + 1] = l end) and tl[1]:find("NOT READY", 1, true), "no work chest: NOT READY + how to set it")
CONFIG.drone.workChest = wc
-- the console command
local out = handleCommand("dw test") or {}
CHECK(table.concat(out, " "):find("Work chest:", 1, true), "console: dw test")
-- in CHAT at the chest (the owner: "how do I test it when the chest is far away from the console")
dr = world()
state.players[1].p = { x = CH.x + 2.5, y = CH.y + 1, z = CH.z + 0.5 }
local toldT = {}
local tellT = chatTell
chatTell = function(n, t) toldT[#toldT + 1] = t end
handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " test" })
run(dr)
chatTell = tellT
local chatText = table.concat(toldT, "\n")
CHECK(chatText:find("OK: AE2 put 1 Stone", 1, true) and chatText:find("brings 1 Stone to Alaory", 1, true),
      "chat  $drone test : the steps come back in chat\n" .. chatText)
CHECK(chatText:find("DRONE TEST: it works", 1, true), "... and the drone's result too (in chat, not only on the monitor)")
-- the owner's test: "it did not bring me a cobblestone" - the saved spot was the block UNDER the chest
-- (standing on a chest = 0.875 high: floor(y) - 1 was one too low)
dr = world()
SETTINGS["drone.workChestAt"] = nil
CONFIG.drone.workChestAt = { x = CH.x, y = CH.y - 1, z = CH.z }
toldT = {}
chatTell = function(n, t) toldT[#toldT + 1] = t end
handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " test" })
run(dr)
chatText = table.concat(toldT, "\n")
CHECK(chatText:find("took nothing", 1, true) and chatText:find("Saved spot: " .. CH.x .. " " .. (CH.y - 1), 1, true)
      and chatText:find("Targeted Block", 1, true) and chatText:find("workchest x y z", 1, true),
      "a wrong spot: the message says where it looked, where the drone was and how to fix it\n" .. chatText)
CHECK(not (W.dropped and W.dropped["minecraft:stone"]), "... nothing was dropped")
CHECK(W.stock["minecraft:stone"] == 100, "... and the stone is back in AE2 (" .. tostring(W.stock["minecraft:stone"]) .. ")")
-- fixed by typing the chest's spot in chat (F3 Targeted Block)
toldT = {}
handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " workchest " .. CH.x .. " " .. CH.y .. " " .. CH.z })
local fx, fy, fz = DW.chestAt()
CHECK(fx == CH.x and fy == CH.y and fz == CH.z, "$drone workchest x y z sets the exact spot: " .. tostring(toldT[1]))
dr = world()
toldT = {}
handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " test" })
run(dr)
CHECK(table.concat(toldT, "\n"):find("DRONE TEST: it works", 1, true), "... and then the test works")
chatTell = tellT
-- standing ON a chest (0.875 high): the chest itself, not the block under it
local realPos = playerPos
playerPos = function() return 10.5, 70.875, -3.5 end
local bx, by, bz = playerBlock("Alaory")
CHECK(bx == 10 and by == 70 and bz == -4, "standing on a chest = the chest (" .. tostring(by) .. ")")
playerPos = function() return 10.5, 71, -3.5 end
bx, by = playerBlock("Alaory")
CHECK(by == 70, "standing on a full block = that block")
playerPos = function() return 10.5, 70.5, -3.5 end
bx, by = playerBlock("Alaory")
CHECK(by == 70, "standing on a slab = the slab")
bx, by = playerBlock("Alaory", true)
CHECK(by == 70, "feet = the block the feet are in")
playerPos = realPos
-- a stranger cannot
toldT = {}
chatTell = function(n, t) toldT[#toldT + 1] = t end
handleChat({ name = "Griefer", uuid = "x-1", msg = "$" .. CONFIG.chat.command .. " test" })
chatTell = tellT
CHECK(#dr.queue == 0 and table.concat(toldT, " "):find("Only", 1, true), "only the owner can run the drone test")
pushNote = realNote

------------------------------------------------------------------ places
state.players = { { name = "Alaory", isOwner = true, p = { x = 10.5, y = 71, z = -3.2 }, dim = DRONE_DIM } }
det = { getPlayer = function() return { x = 10.5, y = 71, z = -3.2, dimension = "minecraft:overworld" } end }
playerDimNow = function() return DRONE_DIM end
local x, y, z = posArg({ "me" }, 1)
CHECK(x == 10 and y == 70 and z == -4, "me = the block under you (" .. tostring(x) .. " " .. tostring(y) .. " " .. tostring(z) .. ")")
addWaypoint("chestA", 1, 2, 3)
x, y, z = posArg({ "chesta" }, 1)
CHECK(x == 1 and y == 2 and z == 3, "a saved place works instead of x y z")
x, y = posArg({ "nowhere" }, 1)
CHECK(x == nil and tostring(y):find("mark", 1, true), "an unknown place says how to mark one")
removeWaypoint("chestA")
------------------------------------------------------------------ the DRONE WORK page: all by tapping
dr = world()
state.turtles = { [9] = { id = 9, label = "T9", log = {}, lastSeen = os.clock(), pos = { x = 40, y = 64, z = 40 }, fuel = 0, task = "idle" } }
W.tinv[key(40, 64, 40)] = {}
CONFIG.drone.workChest, CONFIG.drone.workChestAt = nil, nil
SETTINGS["drone.workChest"], SETTINGS["drone.workChestAt"] = nil, nil
DW.auto = false                                      -- (no automatic run while the page is tested)
state.page = "work"
DW.view.at = -999
DW.tick()
local function hitOf(kind, val)
  for _, h in ipairs(hits) do
    local v = h[6]
    if h[5] == kind and (val == nil or v == val or (type(v) == "table" and (v.kind == val or v.name == val))) then return h end
  end
end
local function tap(kind, val, twice)
  draw()
  local h = hitOf(kind, val)
  CHECK(h, "the page shows a button for " .. kind .. " " .. tostring(val))
  if not h then return end
  handleTouch(h[1], h[2])
  if twice then draw() h = hitOf(kind, val) if h then handleTouch(h[1], h[2]) end end
end
CHECK(DW.view.cands[1] == "minecraft:barrel_9", "the page lists the empty barrel on the cable")
tap("dwnext")
CHECK(DW.chestName() == "minecraft:barrel_9", "CHEST picks it")
state.players = { { name = "Alaory", isOwner = true, p = { x = 2.5, y = 70, z = 0.5 }, dim = DRONE_DIM } }
det = { getPlayer = function() return { x = 2.5, y = 70, z = 0.5, dimension = "minecraft:overworld" } end }
tap("act", "dwchesthere", true)
local cx, cy, cz = DW.chestAt()
CHECK(cx == CH.x and cy == CH.y and cz == CH.z, "BLOCK UNDER ME (two taps) = standing on the chest sets its spot")
tap("act", "dwfuel", true)
CHECK(#dr.queue == 1, "SEND FUEL starts a drone fuel run")
runMission(dr, table.remove(dr.queue, 1)) dr.busy = false
DW.tick()
CHECK((W.tinv[key(40, 64, 40)]["minecraft:coal"] or 0) > 0, "... and the coal arrives")
-- a build by tapping: pick the schematic, AT: a saved place, TURN, BUILD (two taps)
DW.view.at = -999
DW.tick()
addWaypoint("Site", OX, OY + 20, OZ)
tap("dwsel", "hut")
CHECK(DW.sel and DW.sel.name == "hut" and DW.sel.place == 17, "tapping a schematic shows what it needs (" .. tostring(DW.sel and DW.sel.place) .. " blocks)")
local idx
for i, wp in ipairs(state.waypoints) do if wp.name == "Site" then idx = i end end
for _ = 1, idx do tap("dwat") end
CHECK(DW.ui.at == idx, "AT cycles to the saved place")
tap("dwrot")
CHECK(DW.ui.rot == 90, "TURN: 90")
tap("act", "dwbuild", true)
CHECK(DW.job and DW.job.y == OY + 20 and DW.job.rot == 90, "BUILD starts it at the saved place, turned 90")
tap("dwpause")
CHECK(DW.job and DW.job.paused, "PAUSE")
tap("dwpause")
CHECK(DW.job and not DW.job.paused, "RESUME")
tap("act", "dwstop", true)
CHECK(DW.job == nil, "STOP THE BUILD (two taps)")
tap("act", "dwmark", true)
CHECK(findWaypoint("Place 1"), "SAVE WHERE I STAND saves Place 1")
tap("act", "Place 1", true)
CHECK(not findWaypoint("Place 1"), "DELETE (two taps) forgets it")
-- FUEL: the next fuel AE2 has, the amount per run
W.stock["minecraft:coal_block"] = 20
DW.view.at = -999
DW.tick()
CHECK(DW.fuelItem() == "minecraft:coal", "fuel: coal by default")
tap("dwfuelnext")
CHECK(DW.fuelItem() == "minecraft:coal_block", "FUEL > picks the next fuel AE2 has (" .. tostring(DW.fuelItem()) .. ")")
tap("dwfuelnext")
CHECK(DW.fuelItem() == "minecraft:coal", "... and round again (no fuel AE2 lacks)")
local _, n0 = DW.fuelItem()
tap("dwfuelcount")
local _, n1 = DW.fuelItem()
CHECK(n0 == 32 and n1 == 64, "x PER RUN > steps the amount (" .. tostring(n0) .. " -> " .. tostring(n1) .. ")")
tap("dwauto")
CHECK(DW.autoOn() == true, "AUTO: ON / OFF")
removeWaypoint("Site")
state.page = "home"
-- chat: stand ON the work chest far from the monitor and type  $drone workchest
CONFIG.drone.workChest, CONFIG.drone.workChestAt = nil, nil
SETTINGS["drone.workChest"], SETTINGS["drone.workChestAt"] = nil, nil
det = { getPlayer = function() return { x = 2.5, y = 70, z = 0.5, dimension = "minecraft:overworld" } end }
local told = {}
local tell0 = chatTell
chatTell = function(n, t) told[#told + 1] = t end
handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " workchest" })
chatTell = tell0
cx, cy, cz = DW.chestAt()
CHECK(cx == CH.x and cy == CH.y and cz == CH.z, "chat  workchest  = the block under you (" .. tostring(told[1]) .. ")")
CHECK(DW.chestName() == "minecraft:barrel_9", "... and the only empty chest on the cable is picked")

bridge = BRIDGE0
PERIPHS["minecraft:barrel_9"] = nil
