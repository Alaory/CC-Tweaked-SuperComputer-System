-- EVERY DRONE AT ONCE (the owner: "why use 1 drone? why not use more?" + "a drone can only carry 1 type of item"):
-- two drones build side by side - their missions run as coroutines here, as in the drone worker. They share ONE work
-- chest: each takes it only to load / unload (DW.chestTake), so the chest never holds two drones' items and a drone
-- never carries two kinds. No spot is given to two drones, layers stay in order, a gift goes while a build runs.
local CH = { x = 2, y = 69, z = 0 }
bridgeKind = bridgeKind or "ME"
local HOME = { x = 0, y = 70, z = 0 }
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local W = { chest = {}, blocks = {}, stock = { ["minecraft:stone"] = 1000, ["minecraft:oak_planks"] = 1000,
            ["minecraft:torch"] = 100, ["minecraft:diamond"] = 50 }, mixedChest = 0, mixedDrone = 0, maxTrips = 0,
            placedOnTaken = 0, order = {}, dropped = {} }
local function count(t) local n = 0 for _, v in pairs(t) do n = n + v end return n end
local function kinds(t) local n = 0 for _, v in pairs(t) do if v > 0 then n = n + 1 end end return n end

-- each drone: its own position / inventory / action; the chest, AE2 and the world are shared
local D = {}
local function makeDrone(k)
  local d = { pos = { x = 0, y = 71, z = 0 }, inv = {}, area = {}, act = nil, sides = {} }
  D[k] = d
  local per = {
    clearArea = function() d.area = {} end,
    addArea = function(x, y, z) d.area[#d.area + 1] = { x = x, y = y, z = z } end,
    setAction = function(a)
      if a:find("condition", 1, true) then d.act = nil return end
      d.act, d.doneAt = a, CLOCK + 0.9
    end,
    isConnectedToDrone = function() return true end, abortAction = function() d.act = nil end,
    getDronePosition = function() return d.pos.x + 0.5, d.pos.y + 0.5, d.pos.z + 0.5 end,
    isActionDone = function() return d.act == nil end, getDronePressure = function() return 9 end,
    clearWhitelistText = function() end, clearBlacklistText = function() end, addWhitelistText = function() end,
    clearWhitelistItemFilter = function() end, setUseCount = function() end, exitPiece = function() end,
    setSides = function(...) d.sides = { ... } end, setDropStraight = function() end,
    setSide = function(_, v) d.sides[#d.sides + 1] = v end,
    getAction = function() return d.act end, setOperator = function() end, setCount = function() end,
    evaluateCondition = function() return false end,
  }
  return per
end
-- an action that is due: what it does
local function finish(d)
  local a, pts = d.act, d.area
  local p = pts[1]
  if a == "pneumaticcraft:teleport" or a == "pneumaticcraft:goto" then
    d.pos = { x = p.x, y = p.y, z = p.z }
  elseif a == "pneumaticcraft:inventory_import" then
    if key(p.x, p.y, p.z) == key(CH.x, CH.y, CH.z) then
      if kinds(W.chest) > 1 then W.mixedChest = W.mixedChest + 1 end
      local room = 64 - count(d.inv)
      for name, n in pairs(W.chest) do
        local take = math.min(n, room)
        if take > 0 then d.inv[name] = (d.inv[name] or 0) + take W.chest[name] = n - take room = room - take end
        if W.chest[name] == 0 then W.chest[name] = nil end
      end
      if kinds(d.inv) > 1 then W.mixedDrone = W.mixedDrone + 1 end
    end
  elseif a == "pneumaticcraft:inventory_export" then
    if key(p.x, p.y, p.z) == key(CH.x, CH.y, CH.z) then
      for name, n in pairs(d.inv) do W.chest[name] = (W.chest[name] or 0) + n end
      d.inv = {}
    end
  elseif a == "pneumaticcraft:drop_item" then
    for name, n in pairs(d.inv) do W.dropped[name] = (W.dropped[name] or 0) + n end
    W.giftAt = W.giftAt or CLOCK
    d.inv = {}
  elseif a == "pneumaticcraft:place" then
    for _, q in ipairs(pts) do
      local name = next(d.inv)
      if not name then break end
      local k = key(q.x, q.y, q.z)
      if W.blocks[k] then W.placedOnTaken = W.placedOnTaken + 1
      else
        W.blocks[k] = name
        W.order[#W.order + 1] = { y = q.y, item = name }
        d.inv[name] = d.inv[name] - 1
        if d.inv[name] == 0 then d.inv[name] = nil end
      end
    end
  end
  d.act = nil
end

-- AE2 + the work chest (shared)
bridge = {
  getItems = function(f)
    if (W.stock[f.name] or 0) > 0 then return { { name = f.name, amount = W.stock[f.name], fingerprint = "plain-" .. f.name } } end
    return {}
  end,
  exportItem = function(f, target)
    if type(f) ~= "table" then return nil end
    local n = math.min(f.count or 0, W.stock[f.name] or 0)
    W.stock[f.name] = (W.stock[f.name] or 0) - n
    W.chest[f.name] = (W.chest[f.name] or 0) + n
    return n
  end,
  importItem = function(f)
    if type(f) ~= "table" then return nil end
    local n = math.min(f.count or 0, W.chest[f.name] or 0)
    W.chest[f.name] = (W.chest[f.name] or 0) - n
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
CONFIG.drone.worker = nil
CHECK(#droneOrder >= 2, "two drones in the test world (" .. #droneOrder .. ")")
for _, k in ipairs(droneOrder) do
  local dr = drones[k]
  dr.periph, dr.gone, dr.busy, dr.queue, dr.mission, dr.conn = makeDrone(k), false, false, {}, nil, true
  dr.rider, dr.failedAt, dr.workSlots = nil, nil, nil
end
refreshDrone = function(dr) local d = D[dr.key] dr.conn = true dr.pos = { x = d.pos.x + 0.5, y = d.pos.y + 0.5, z = d.pos.z + 0.5 } end
state.owner = "Alaory"
state.players = { { name = "Alaory", isOwner = true, p = { x = 0, y = 70, z = 0 }, dim = DRONE_DIM } }
state.turtles = {}
DW.job, DW.trips, DW.trip, DW.runs, DW.auto = nil, {}, nil, {}, false

-- missions as coroutines: a wait gives the others a turn (like the drone worker)
local CO = {}
os.pullEventRaw = function() if coroutine.isyieldable() then coroutine.yield() end return "timer", 1 end
os.pullEvent = os.pullEventRaw
sleep = function(t)
  local e = CLOCK + (tonumber(t) or 0)
  if not coroutine.isyieldable() then CLOCK = e return end
  repeat coroutine.yield() until CLOCK >= e
end
local function step()
  CLOCK = CLOCK + 0.3
  for _, k in ipairs(droneOrder) do
    local d = D[k]
    if d.act and CLOCK >= d.doneAt then finish(d) end
  end
  for _, k in ipairs(droneOrder) do
    local dr = drones[k]
    if not CO[k] and #dr.queue > 0 then
      local cmd = table.remove(dr.queue, 1)
      dr.busy = true
      CO[k] = coroutine.create(function() return runMission(dr, cmd) end)
    end
    if CO[k] then
      local okR, err = coroutine.resume(CO[k])
      if not okR then CHECK(false, "a mission stopped with an error: " .. tostring(err)) end
      if coroutine.status(CO[k]) == "dead" then CO[k] = nil dr.busy = false end
    end
  end
  local n = 0
  for _ in pairs(DW.trips) do n = n + 1 end
  if n > W.maxTrips then W.maxTrips = n end
end
local function runUntil(cond, maxSteps)
  local nextTick = CLOCK
  for _ = 1, maxSteps or 20000 do
    if CLOCK >= nextTick then DW.tick() nextTick = CLOCK + 2 end
    if cond() then return true end
    step()
  end
  return false
end

-- a 12 x 2 x 12 schematic in ONE chunk: a floor of stone and planks (checkerboard - 2 items in one layer), torches on it
local s = { size = { x = 12, y = 2, z = 12 }, palette = { { name = "minecraft:stone", props = {} },
            { name = "minecraft:oak_planks", props = {} }, { name = "minecraft:torch", props = {} } }, blocks = {} }
for x = 0, 11 do for z = 0, 11 do
  s.blocks[#s.blocks + 1] = { x, 0, z, ((x + z) % 2 == 0) and 1 or 2 }
  if x % 4 == 0 and z % 4 == 0 then s.blocks[#s.blocks + 1] = { x, 1, z, 3 } end
end end
SCHEM.cache["floor"] = { s = s, path = "schematics/floor.nbt" }
local OX, OY, OZ = 32, 64, 32
local ok, msg = DW.startBuild("floor", OX, OY, OZ, 0, false)
CHECK(ok, "the build starts (" .. tostring(msg) .. ")")
local done = runUntil(function() return DW.job == nil and next(DW.trips) == nil end)
CHECK(done, "the build finishes")
local good = 0
for x = 0, 11 do for z = 0, 11 do
  local want = ((x + z) % 2 == 0) and "minecraft:stone" or "minecraft:oak_planks"
  if W.blocks[key(OX + x, OY, OZ + z)] == want then good = good + 1 end
  if x % 4 == 0 and z % 4 == 0 and W.blocks[key(OX + x, OY + 1, OZ + z)] == "minecraft:torch" then good = good + 1 end
end end
CHECK(good == 144 + 9, "every block placed (" .. good .. "/153)")
CHECK(W.maxTrips >= 2, "the drones work SIDE BY SIDE (most trips at once: " .. W.maxTrips .. ")")
CHECK(W.mixedChest == 0, "the work chest never held two drones' items at a load (" .. W.mixedChest .. ")")
CHECK(W.mixedDrone == 0, "a drone never carried two kinds of item (" .. W.mixedDrone .. ")")
CHECK(W.placedOnTaken == 0, "no spot was given to two drones (" .. W.placedOnTaken .. " placed onto a taken spot)")
local torchEarly = false
local solidSeen = 0
for _, o in ipairs(W.order) do
  if o.item == "minecraft:torch" then if solidSeen < 144 then torchEarly = true end else solidSeen = solidSeen + 1 end
end
CHECK(not torchEarly, "the torches came only after every floor block (layers in order)")
CHECK(W.stock["minecraft:stone"] == 1000 - 72 and W.stock["minecraft:oak_planks"] == 1000 - 72 and
      W.stock["minecraft:torch"] == 100 - 9, "exactly the blocks used left AE2 (stone " .. W.stock["minecraft:stone"] ..
      ", planks " .. W.stock["minecraft:oak_planks"] .. ", torches " .. W.stock["minecraft:torch"] .. ")")
CHECK(next(W.chest) == nil, "the work chest is empty at the end")
CHECK(DW.chestBy == nil, "nobody holds the work chest at the end")

-- a GIFT while a build runs: the free drone goes at once (it was refused "a drone job is running")
W.blocks, W.order, W.maxTrips = {}, {}, 0
SCHEM.cache["floor"] = { s = s, path = "schematics/floor.nbt" }
DW.startBuild("floor", OX, OY, OZ + 16, 0, false)
-- one build trip out, the other drone free
DW.tick()
local trips = 0
for _ in pairs(DW.trips) do trips = trips + 1 end
for _, k in ipairs(droneOrder) do if #drones[k].queue > 0 and not CO[k] then end end
local free = DW.freeDrone()
local okG, whyG
if free then
  okG, whyG = DW.giftRun("Alaory", "minecraft:diamond", 5)
else
  -- (both took a build trip: the gift waits for the first free one)
  runUntil(function() return DW.freeDrone() ~= nil end)
  okG, whyG = DW.giftRun("Alaory", "minecraft:diamond", 5)
end
CHECK(okG, "a gift starts while the build runs (" .. tostring(whyG) .. ")")
local doneB = runUntil(function() return DW.job == nil and next(DW.trips) == nil end)
CHECK(doneB and (W.dropped["minecraft:diamond"] or 0) == 5, "the gift arrived and the build finished (" ..
      tostring(W.dropped["minecraft:diamond"]) .. " diamonds)")
CHECK(W.mixedChest == 0 and W.mixedDrone == 0, "gift + build: still one kind per drone, the chest never mixed")
