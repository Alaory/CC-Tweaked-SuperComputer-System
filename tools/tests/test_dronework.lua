-- DRONE WORK (base_dronework.lua) in a small fake world: the work chest, AE2, a drone that
-- teleports / takes / puts / places / digs. A schematic is built bottom up and checked block
-- by block; leftovers go back into AE2; your own (enchanted) items are never taken; a taken
-- spot is counted; a restart goes on where it was; clear digs the air spots first; a site
-- nobody keeps loaded gets a turtle first; fuel runs to a turtle with NO FUEL.
local HOME = { x = 0, y = 70, z = 0 }
local BRIDGE0 = bridge
local CH = { x = 2, y = 69, z = 0 }
local W
local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function world()
  W = { pos = { x = 0, y = 71, z = 0 }, inv = {}, area = {}, act = nil, blocks = {}, order = {},
        chest = {}, stock = { ["minecraft:stone"] = 100, ["minecraft:oak_planks"] = 100, ["minecraft:coal"] = 500 },
        own = { ["minecraft:stone"] = 1 }, tinv = {}, refused = {}, teleports = 0 }
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
        if key(p.x, p.y, p.z) == key(CH.x, CH.y, CH.z) then
          local room = (CONFIG.drone.slots or 1) * 64 - invCount(W.inv)
          for name, n in pairs(W.chest) do
            local take = math.min(n, room)
            if take > 0 then invAdd(W.inv, name, take) W.chest[name] = n - take room = room - take end
            if W.chest[name] == 0 then W.chest[name] = nil end
          end
        end
      elseif a == "pneumaticcraft:inventory_export" then
        local target = (key(p.x, p.y, p.z) == key(CH.x, CH.y, CH.z)) and W.chest or W.tinv[key(p.x, p.y, p.z)]
        if target then
          for name, n in pairs(W.inv) do invAdd(target, name, n) end
          W.inv = {}
        end
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
CHECK(W.teleports == 0, "a build next to the base: the drone FLIES (no air used for teleports: " .. tostring(W.teleports) .. ")")

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
bridge = BRIDGE0
PERIPHS["minecraft:barrel_9"] = nil
