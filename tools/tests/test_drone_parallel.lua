-- EVERY DRONE AT ONCE (the owner: "why use 1 drone? why not use more?" + "a drone can only carry 1 type of item"):
-- two drones build side by side - their missions run as coroutines here, as in the drone worker. They share ONE work
-- chest: each takes it only to load / unload (DW.chestTake), so the chest never holds two drones' items and a drone
-- never carries two kinds. No spot is given to two drones, layers stay in order, a gift goes while a build runs.
local CH = { x = 12, y = 69, z = 0 }
bridgeKind = bridgeKind or "ME"
local HOME = { x = 0, y = 70, z = 0 }
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local W = { chest = {}, blocks = {}, stock = { ["minecraft:stone"] = 1000, ["minecraft:oak_planks"] = 1000,
            ["modern_industrialization:salt_block"] = 100, ["minecraft:anvil"] = 10, ["minecraft:chest"] = 10,
            ["minecraft:barrel"] = 10, ["minecraft:gravel"] = 10,
            ["minecraft:torch"] = 100, ["minecraft:diamond"] = 50 }, mixedChest = 0, mixedDrone = 0, maxTrips = 0,
            placedOnTaken = 0, order = {}, dropped = {}, water = {}, blockOnce = {}, noDig = {} }
local function count(t) local n = 0 for _, v in pairs(t) do n = n + v end return n end
local function kinds(t) local n = 0 for _, v in pairs(t) do if v > 0 then n = n + 1 end end return n end

-- each drone: its own position / inventory / action; the chest, AE2 and the world are shared
local D = {}
local function makeDrone(k)
  local d = { pos = { x = 0, y = 71, z = 0 }, inv = {}, area = {}, act = nil, sides = {}, p = 9 }
  D[k] = d
  local per = {
    clearArea = function() d.area = {} end,
    addArea = function(x, y, z) d.area[#d.area + 1] = { x = x, y = y, z = z } end,
    setAction = function(a)
      if a:find("condition", 1, true) then d.act = nil return end
      d.act, d.doneAt = a, CLOCK + 0.9
      -- (placing / digging: the drone moves round its spots while it works, next to each one - a block cannot go
      --  where it is)
      if a == "pneumaticcraft:place" or a == "pneumaticcraft:dig" then
        d.stand = {}
        for _, q in ipairs(d.area) do d.stand[key(q.x + 1, q.y, q.z)] = true end
        d.doneAt = CLOCK + 0.9 + 0.2 * #d.area                -- (a block every 0.2 s)
      end
    end,
    isConnectedToDrone = function() return true end, abortAction = function() d.act = nil end,
    getDronePosition = function() return d.pos.x + 0.5, d.pos.y + 0.5, d.pos.z + 0.5 end,
    isActionDone = function() return d.act == nil end, getDronePressure = function() return d.p end,
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
    if math.abs(p.x - HOME.x) + math.abs(p.z - HOME.z) <= 3 and W.counting then W.homeTrips = (W.homeTrips or 0) + 1 end
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
    if next(d.inv) == nil and W.counting then W.emptyExports = (W.emptyExports or 0) + 1 end
    if key(p.x, p.y, p.z) == key(CH.x, CH.y, CH.z) then
      for name, n in pairs(d.inv) do W.chest[name] = (W.chest[name] or 0) + n end
      d.inv = {}
    end
  elseif a == "pneumaticcraft:drop_item" then
    for name, n in pairs(d.inv) do W.dropped[name] = (W.dropped[name] or 0) + n end
    W.giftAt = W.giftAt or CLOCK
    d.inv = {}
  elseif a == "pneumaticcraft:dig" then
    for _, q in ipairs(pts) do
      local k = key(q.x, q.y, q.z)
      if W.blocks[k] and W.noDig[k] then W.digRefused = (W.digRefused or 0) + 1     -- (a claimed chunk / out of reach)
      elseif W.blocks[k] then                              -- (a drone picks up what it digs)
        W.dug = (W.dug or 0) + 1
        d.inv[W.blocks[k]] = (d.inv[W.blocks[k]] or 0) + 1
        W.blocks[k] = nil
      end
      W.water[k] = nil
    end
  elseif a == "pneumaticcraft:place" then
    for _, q in ipairs(pts) do
      local name = next(d.inv)
      if not name then break end
      local k = key(q.x, q.y, q.z)
      local inWay = false
      for _, od in pairs(D) do if od ~= d and od.act and od.stand and od.stand[k] then inWay = true end end
      if W.blockOnce[k] then W.blockOnce[k] = nil inWay = true end
      if inWay then W.droneInWay = (W.droneInWay or 0) + 1
      elseif W.blocks[k] then W.placedOnTaken = W.placedOnTaken + 1
      else
        W.water[k] = nil
        W.blocks[k] = name
        W.order[#W.order + 1] = { y = q.y, item = name }
        d.inv[name] = d.inv[name] - 1
        if d.inv[name] == 0 then d.inv[name] = nil end
      end
    end
  end
  d.act, d.stand = nil, nil
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
W.counting = true
local done = runUntil(function() return DW.job == nil and next(DW.trips) == nil end)
W.counting = false
CHECK((W.homeTrips or 0) == 0, "no flight home to the charger between build trips (" .. tostring(W.homeTrips) .. ")")
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

-- a drone LOW ON AIR: it is not given trips (it charges), the other builds on - no "Pressure too low" stalls
do
  W.blocks, W.order = {}, {}
  local low = droneOrder[2]
  D[low].p = 1
  local fails = 0
  local realDone = DW.stopBuild
  DW.startBuild("floor", OX + 16, OY, OZ, 0, false)
  local J0 = DW.job
  local lowTrips = 0
  local doneL = runUntil(function()
    for k in pairs(DW.trips) do if k == low then lowTrips = lowTrips + 1 end end
    if J0.why and tostring(J0.why):find("Pressure", 1, true) then fails = fails + 1 end
    return DW.job == nil and next(DW.trips) == nil
  end)
  CHECK(doneL and lowTrips == 0, "a drone with 1 bar gets no trip; the build finishes with the other (" .. lowTrips .. " trips on it)")
  CHECK(fails == 0, "no 'Pressure too low' stalls (" .. fails .. ")")
  D[low].p = 9
end

-- THE OWNER'S test1 (2 x 2 x 2: stone, an anvil, a chest, a barrel below; salt blocks above - "3 drones work, then 1
-- continues"): the salt trip goes out while the bottom layer is still being built (a drone places in mid-air); a
-- block that FALLS (gravel, on top) waits for the layer below; no "empty the drone" chest visit when it is empty
do
  local t1 = { size = { x = 2, y = 2, z = 2 }, palette = { { name = "minecraft:stone", props = {} },
               { name = "modern_industrialization:salt_block", props = {} }, { name = "minecraft:anvil", props = {} },
               { name = "minecraft:chest", props = {} }, { name = "minecraft:barrel", props = {} },
               { name = "minecraft:gravel", props = {} } },
               blocks = { { 1, 0, 1, 1 }, { 0, 1, 0, 2 }, { 0, 1, 1, 2 }, { 1, 1, 0, 6 }, { 1, 1, 1, 2 },
                          { 1, 0, 0, 3 }, { 0, 0, 0, 4 }, { 0, 0, 1, 5 } } }
  SCHEM.cache["test1"] = { s = t1, path = "schematics/test1.nbt" }
  W.blocks, W.order, W.maxTrips, W.emptyExports = {}, {}, 0, 0
  local TX, TY, TZ = 40, 64, 50
  DW.startBuild("test1", TX, TY, TZ, 0, false)
  local saltWhileBottom = false
  W.counting = true
  local doneT = runUntil(function()
    local bottomOut, saltOut = false, false
    for _, t in pairs(DW.trips) do
      if t.layer == TY then bottomOut = true end
      if t.item == "modern_industrialization:salt_block" then saltOut = true end
    end
    if bottomOut and saltOut then saltWhileBottom = true end
    return DW.job == nil and next(DW.trips) == nil
  end)
  W.counting = false
  CHECK(doneT, "test1 is built")
  local n = 0
  for _ in pairs(W.blocks) do n = n + 1 end
  CHECK(n == 8, "all 8 blocks of test1 (" .. n .. ")")
  -- (the rule itself: every bottom-layer group out with a drone, the free one takes the salt at once - it waited for
  --  the whole bottom layer before)
  do
    SCHEM.cache["test1"] = { s = t1, path = "schematics/test1.nbt" }
    DW.startBuild("test1", TX + 8, TY, TZ, 0, false)
    local J = DW.job
    local plan = J.plan
    local bottom = {}
    for i, pp in ipairs(plan.place) do if pp.y == TY then bottom[#bottom + 1] = i end end
    DW.trips = { busyone = { kind = "place", layer = TY, idx = bottom, dr = "busyone", at = os.clock(), item = "x" } }
    drones.busyone = { key = "busyone", busy = true, queue = {} }
    DW.buildOne(J)
    local salt = false
    for k, t in pairs(DW.trips) do if k ~= "busyone" and t.item == "modern_industrialization:salt_block" then salt = true end end
    CHECK(salt or saltWhileBottom, "with the whole bottom layer out, a free drone takes the salt (layer 2) at once (" .. tostring(J.why) .. ", free: " .. tostring(DW.freeDrone and (DW.freeDrone()) and "yes" or "no") .. ")")
    drones.busyone = nil
    DW.trips.busyone = nil
    runUntil(function() return next(DW.trips) == nil end)
    DW.stopBuild("test")
  end
  local lastBottom, gravelAt = 0, nil
  for i, o in ipairs(W.order) do
    if o.y == TY then lastBottom = i end
    if o.item == "minecraft:gravel" then gravelAt = i end
  end
  CHECK(gravelAt and gravelAt > lastBottom, "the gravel (it falls) only after every block below (" .. tostring(gravelAt) ..
        " after " .. lastBottom .. ")")
  CHECK((W.emptyExports or 0) <= 6, "no 'empty the drone first' chest visit with an empty drone - only the end-of-trip one (" ..
        tostring(W.emptyExports) .. " for 6 trips)")
  local tl = DW.timesLine()
  CHECK(tl and tl:find("chest wait", 1, true), "schem status shows where a trip's time goes: " .. tostring(tl))
end

-- DRONES IN EACH OTHER'S WAY (the owner: "a drone will try to place a block where another drone is standing"): a 24 x 24
-- checkerboard floor (two kinds in one layer - their trips cover the same squares). Drones work squares apart
-- (DW.tooClose), so no block meets a drone; a spot that refuses a block ONCE (a mob, a player) is tried again, not
-- left empty as "taken".
do
  local f = { size = { x = 24, y = 1, z = 24 }, palette = { { name = "minecraft:stone", props = {} },
              { name = "minecraft:oak_planks", props = {} } }, blocks = {} }
  for x = 0, 23 do for z = 0, 23 do f.blocks[#f.blocks + 1] = { x, 0, z, ((x + z) % 2 == 0) and 1 or 2 } end end
  SCHEM.cache["bigfloor"] = { s = f, path = "schematics/bigfloor.nbt" }
  W.blocks, W.order, W.maxTrips, W.droneInWay = {}, {}, 0, 0
  W.stock["minecraft:stone"], W.stock["minecraft:oak_planks"] = 1000, 1000
  local BX, BY, BZ = -40, 64, -40
  W.blockOnce[key(BX + 3, BY, BZ + 5)] = true          -- (something stands there for the first try)
  DW.startBuild("bigfloor", BX, BY, BZ, 0, false)
  local closeSeen = false
  local doneF = runUntil(function()
    local boxes = {}
    for _, t in pairs(DW.trips) do if t.box then boxes[#boxes + 1] = t.box end end
    for a = 1, #boxes do for b = a + 1, #boxes do if DW.tooClose and DW.tooClose(boxes[a], boxes[b]) then closeSeen = true end end end
    return DW.job == nil and next(DW.trips) == nil
  end, 60000)
  CHECK(doneF, "the 24 x 24 floor is built")
  local good = 0
  for x = 0, 23 do for z = 0, 23 do
    if W.blocks[key(BX + x, BY, BZ + z)] == (((x + z) % 2 == 0) and "minecraft:stone" or "minecraft:oak_planks") then good = good + 1 end
  end end
  CHECK(good == 576, "every block placed - the spot that refused once was tried again (" .. good .. "/576)")
  CHECK(W.droneInWay == 1, "no block was put where another drone stood (" .. (W.droneInWay - 1) .. " times; 1 = the test's own blocker)")
  CHECK(not closeSeen, "two drones never worked closer than " .. (DW.gap and DW.gap() or 3) .. " blocks")
  CHECK(W.maxTrips >= 2, "... and still side by side on a big floor (most at once: " .. W.maxTrips .. ")")
  CHECK(W.stock["minecraft:stone"] == 1000 - 288 and W.stock["minecraft:oak_planks"] == 1000 - 288,
        "exactly the blocks used left AE2, the retry's block went back (" .. W.stock["minecraft:stone"] .. ", " .. W.stock["minecraft:oak_planks"] .. ")")
end

-- A SITE IN TWO UNLOADED CHUNKS (the owner: "a turtle can only load the chunk that it is in"): one turtle per chunk
do
  local f = { size = { x = 24, y = 1, z = 4 }, palette = { { name = "minecraft:stone", props = {} } }, blocks = {} }
  for x = 0, 23 do for z = 0, 3 do f.blocks[#f.blocks + 1] = { x, 0, z, 1 } end end
  SCHEM.cache["wide"] = { s = f, path = "schematics/wide.nbt" }
  local FX, FZ = 1600, 1600                             -- chunks 100 and 101 in x
  state.turtles = {
    [7] = { id = 7, label = "T7", log = {}, lastSeen = os.clock(), pos = { x = 5, y = 70, z = 5 }, fuel = 50000, task = "idle" },
    [8] = { id = 8, label = "T8", log = {}, lastSeen = os.clock(), pos = { x = 6, y = 70, z = 5 }, fuel = 50000, task = "idle" } }
  local sent = {}
  local send0, on0, av0 = TT.send, TT.online, TT.available
  TT.send = function(id, cmd, args) sent[#sent + 1] = { id = id, cmd = cmd, args = args } end
  TT.online = function() return true end
  TT.available = function()
    local l = {}
    for id, t in pairs(state.turtles) do if not t.dwAnchor then l[#l + 1] = id end end
    table.sort(l)
    return l
  end
  W.blocks = {}
  DW.startBuild("wide", FX, 64, FZ, 0, false)
  local J = DW.job
  DW.tick()
  local chunks = {}
  for _, m in ipairs(sent) do if m.cmd == "goto" then chunks[math.floor(m.args[1] / 16)] = m.id end end
  CHECK(chunks[100] and chunks[101] and chunks[100] ~= chunks[101], "two turtles go, one to EACH chunk of the site")
  CHECK(next(DW.trips) == nil, "no drone goes before the site is loaded")
  local st = table.concat(DW.statusLines(), "\n")
  CHECK(st:find("Keeping chunk 100,", 1, true) and st:find("Keeping chunk 101,", 1, true), "schem status lists both: " .. st)
  -- they arrive
  for cx, id in pairs(chunks) do state.turtles[id].pos = { x = cx * 16 + 8, y = 70, z = FZ + 1 } end
  local doneW = runUntil(function()
    for _, t in pairs(state.turtles) do t.lastSeen = os.clock() end
    return DW.job == nil and next(DW.trips) == nil
  end)
  local n = 0
  for x = 0, 23 do for z = 0, 3 do if W.blocks[key(FX + x, 64, FZ + z)] then n = n + 1 end end end
  CHECK(doneW and n == 96, "then the drones build in both chunks (" .. n .. "/96)")
  local homes = 0
  for _, m in ipairs(sent) do if m.cmd == "home" then homes = homes + 1 end end
  CHECK(homes == 2 and not state.turtles[7].dwAnchor and not state.turtles[8].dwAnchor, "both go home after (" .. homes .. ")")
  -- an OLD saved job (one anchor in J.anchor) is read as one chunk's anchor
  saveFileSafe(dataPath(DW.FILE), textutils.serialize({ name = "wide", x = FX, y = 64, z = FZ, rot = 0, done = "0", dug = "",
                                                         placed = 0, skippedN = 0, anchor = 7, anchorGoal = "100,100" }))
  DW.load()
  CHECK(DW.job and DW.job.anchors and DW.job.anchors["100,100"] == 7 and state.turtles[7].dwAnchor, "an old file's anchor is kept")
  DW.job = nil
  DW.save()
  TT.send, TT.online, TT.available = send0, on0, av0
  state.turtles = {}
end

-- A CHAIN (the owner: "a road split into several schematic files"): each piece right after the one before, centred
do
  local a = { size = { x = 5, y = 1, z = 3 }, palette = { { name = "minecraft:stone", props = {} } }, blocks = {} }
  local b = { size = { x = 5, y = 1, z = 5 }, palette = { { name = "minecraft:oak_planks", props = {} } }, blocks = {} }
  for x = 0, 4 do for z = 0, 2 do a.blocks[#a.blocks + 1] = { x, 0, z, 1 } end end
  for x = 0, 4 do for z = 0, 4 do b.blocks[#b.blocks + 1] = { x, 0, z, 1 } end end
  SCHEM.cache["roada"] = { s = a, path = "schematics/roada.nbt" }
  SCHEM.cache["roadb"] = { s = b, path = "schematics/roadb.nbt" }
  local list, text = DW.chainPlan("roada,roadb*2", { "schem", "chain", "roada,roadb*2", "-50", "63", "20", "toward", "east" }, 4, "Alaory")
  CHECK(list and #list == 3, "3 pieces (" .. tostring(text) .. ")")
  if list then
    CHECK(list[1].x == -50 and list[1].z == 20 and list[1].y == 64, "the first on the ground block given")
    CHECK(list[2].x == -45 and list[2].z == 19 and list[3].x == -40 and list[3].z == 19,
          "the next ones right after it, toward the east, centred (" .. list[2].x .. " " .. list[2].z .. ", " .. list[3].x .. " " .. list[3].z .. ")")
  end
  local l2 = DW.chainPlan("roada,roada", { "schem", "chain", "x", "-50", "63", "20", "toward", "north" }, 4, "Alaory")
  CHECK(l2 and l2[2].z == 17 and l2[2].x == -50, "toward north: the next one before it in z")
  CHECK(not DW.chainPlan("roada,nosuch", { "schem", "chain", "x", "-50", "63", "20", "toward", "east" }, 4, "Alaory"),
        "a missing schematic: nothing queued")
  -- the queue: the first starts, the next when it is done
  W.blocks, DW.queue = {}, {}
  W.stock["minecraft:stone"], W.stock["minecraft:oak_planks"] = 1000, 1000
  DW.enqueue(list)
  CHECK(DW.job and DW.job.name == "roada" and #DW.queue == 2, "the first piece starts, two wait")
  CHECK(readSafe(dataPath(DW.QFILE)), "the queue is saved (a restart keeps it)")
  local doneQ = runUntil(function() return DW.job == nil and #DW.queue == 0 and next(DW.trips) == nil end, 40000)
  local n = 0
  for _ in pairs(W.blocks) do n = n + 1 end
  CHECK(doneQ and n == 15 + 25 + 25, "all three pieces built, one after another (" .. n .. "/65)")
  CHECK(not fs.exists(dataPath(DW.QFILE)), "the queue file goes when it is empty")
  -- console
  local out = handleCommand("schem chain roada,roada -30 63 -30 toward south") or {}
  CHECK(DW.job and #DW.queue == 1, "schem chain starts it: " .. table.concat(out, " / "))
  out = handleCommand("schem queue") or {}
  CHECK(table.concat(out, "\n"):find("roada", 1, true), "schem queue lists it")
  handleCommand("schem stop")
  CHECK(DW.job == nil and #DW.queue == 0, "schem stop stops it and drops the queue")
  runUntil(function() return next(DW.trips) == nil end)
end

-- EMPTY A BOX OF WATER (the owner: "clear an ocean out of water / the nether out of lava"): walls round it, the
-- inside filled, then dug out - the box ends empty, the walls stay, the fill blocks went back to AE2
do
  local X1, Y1, Z1, X2, Y2, Z2 = 20, 60, -40, 25, 62, -36
  W.blocks, W.water, W.order = {}, {}, {}
  for x = X1, X2 do for y = Y1, Y2 do for z = Z1, Z2 do W.water[key(x, y, z)] = true end end end
  W.stock["minecraft:cobblestone"] = 1000
  local out = handleCommand("dw clear " .. X1 .. " " .. Y2 .. " " .. Z1 .. " " .. X2 .. " " .. Y1 .. " " .. Z2) or {}
  local J = DW.job
  CHECK(J and J.kind == "drain", "dw clear starts it: " .. table.concat(out, " / "))
  local doneD = runUntil(function() return DW.job == nil and next(DW.trips) == nil end, 60000)
  CHECK(doneD, "the clearing finishes")
  local walls, inside, wet = 0, 0, 0
  for x = X1, X2 do for y = Y1, Y2 do for z = Z1, Z2 do
    local k = key(x, y, z)
    local edge = x == X1 or x == X2 or z == Z1 or z == Z2
    if edge and W.blocks[k] == "minecraft:cobblestone" then walls = walls + 1 end
    if not edge and W.blocks[k] then inside = inside + 1 end
    if not edge and W.water[k] then wet = wet + 1 end
  end end end
  local ring = (6 * 5 - 4 * 3) * 3
  CHECK(walls == ring, "walls round it (" .. walls .. "/" .. ring .. ")")
  CHECK(inside == 0 and wet == 0, "inside: no water, no blocks left (" .. inside .. " blocks, " .. wet .. " water)")
  CHECK(W.stock["minecraft:cobblestone"] == 1000 - ring, "only the walls' cobblestone is gone from AE2 (" .. W.stock["minecraft:cobblestone"] .. ")")
  local down = false
  for i = 2, #W.order do if W.order[i].y < W.order[i - 1].y then down = true end end
  CHECK(#W.order > 0 and not down, "filled BOTTOM UP (a block over open water would shut it in)")
  CHECK(not DW.startDrain(0, 60, 0, 1, 61, 5), "a box under 3 x 3: refused")
  CHECK(not DW.startDrain(0, 60, 0, 9, 61, 5, "minecraft:sand"), "sand as the fill (it falls): refused")
end

-- in chat: $drone clear here at two corners, then yes; $drone chain ... then yes
do
  local told = {}
  local tell0 = chatTell
  chatTell = function(n, t) told[#told + 1] = t end
  local function chat(m) handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " " .. m }) end
  chat("clear 30 62 30")
  chat("clear 34 60 34")
  CHECK(table.concat(told, " "):find("5 x 5 x 3", 1, true), "$drone clear: two corners -> the box: " .. table.concat(told, " / "))
  chat("clear yes")
  CHECK(DW.job and DW.job.kind == "drain", "$drone clear yes starts it: " .. tostring(told[#told]))
  DW.stopBuild("test")
  told = {}
  chat("chain roada,roada 0 63 30 toward east")
  CHECK(not DW.job and table.concat(told, " "):find("2 piece", 1, true), "$drone chain: says where, waits for yes: " .. table.concat(told, " / "))
  chat("chain yes")
  CHECK(DW.job and DW.job.name == "roada" and #DW.queue == 1, "$drone chain yes starts it")
  handleCommand("schem stop")
  runUntil(function() return next(DW.trips) == nil end)
  chatTell = tell0
end

-- TAKING THINGS DOWN (the owner: "a way to break built schematics, and tell drones to clear an area or break a block")
do
  -- a build, then taken down again: every block back into AE2, nothing else touched
  W.blocks, DW.queue, DW.built = {}, {}, nil
  pcall(fs.delete, dataPath(DW.BUILT_FILE))
  W.stock["minecraft:oak_planks"] = 1000
  local UX, UY, UZ = -20, 64, -50
  W.blocks[key(UX + 2, UY + 1, UZ + 2)] = "minecraft:torch"            -- (something of yours on top - not in the schematic)
  DW.startBuild("roadb", UX, UY, UZ, 0, false)
  runUntil(function() return DW.job == nil and next(DW.trips) == nil end)
  CHECK(W.stock["minecraft:oak_planks"] == 975, "built first (25 planks out of AE2: " .. W.stock["minecraft:oak_planks"] .. ")")
  local out = handleCommand("schem built") or {}
  CHECK(table.concat(out, "\n"):find("1. roadb", 1, true), "schem built lists it: " .. table.concat(out, " / "))
  out = handleCommand("schem unbuild") or {}
  CHECK(not DW.job and table.concat(out, " "):find("schem unbuild yes", 1, true), "schem unbuild: says what, waits for yes: " .. table.concat(out, " / "))
  out = handleCommand("schem unbuild yes") or {}
  CHECK(DW.job and DW.job.kind == "unbuild", "schem unbuild yes starts it: " .. table.concat(out, " / "))
  local doneU = runUntil(function() return DW.job == nil and next(DW.trips) == nil end, 30000)
  local left = 0
  for x = 0, 4 do for z = 0, 4 do if W.blocks[key(UX + x, UY, UZ + z)] then left = left + 1 end end end
  CHECK(doneU and left == 0, "every block of the build is gone (" .. left .. " left)")
  CHECK(W.stock["minecraft:oak_planks"] == 1000, "... and back in AE2 (" .. W.stock["minecraft:oak_planks"] .. ")")
  CHECK(W.blocks[key(UX + 2, UY + 1, UZ + 2)] == "minecraft:torch", "a block that is not part of the schematic stays")
  CHECK(#DW.builtList() == 0, "a build taken down is off the list")
  CHECK(next(W.chest) == nil, "the work chest is empty after")

  -- dig an area: every block in the box, top down - never the work chest (inside the box here)
  W.blocks = {}
  local items = { "minecraft:dirt", "minecraft:stone", "minecraft:oak_log" }
  local n0 = 0
  for x = CH.x - 2, CH.x + 2 do for y = CH.y - 1, CH.y do for z = CH.z - 2, CH.z + 2 do
    W.blocks[key(x, y, z)] = items[(x + y + z) % 3 + 1]
    n0 = n0 + 1
  end end end
  W.blocks[key(CH.x, CH.y, CH.z)] = "minecraft:barrel"
  local dirt0 = W.stock["minecraft:dirt"] or 0
  out = handleCommand("dw dig " .. (CH.x - 2) .. " " .. CH.y .. " " .. (CH.z - 2) .. " " .. (CH.x + 2) .. " " .. (CH.y - 1) .. " " .. (CH.z + 2)) or {}
  CHECK(not DW.job and table.concat(out, " "):find("50 spots", 1, true), "dw dig: the box, then waits for yes: " .. table.concat(out, " / "))
  handleCommand("dw dig yes")
  CHECK(DW.job and DW.job.kind == "dig", "dw dig yes starts it")
  local orderOK, lastY = true, math.huge
  local doneG = runUntil(function()
    for _, t in pairs(DW.trips) do if t.kind == "dig" and t.layer then
      if t.layer > lastY then orderOK = false end
      lastY = math.min(lastY, t.layer)
    end end
    return DW.job == nil and next(DW.trips) == nil
  end, 30000)
  local left2 = 0
  for x = CH.x - 2, CH.x + 2 do for y = CH.y - 1, CH.y do for z = CH.z - 2, CH.z + 2 do
    if W.blocks[key(x, y, z)] and not (x == CH.x and y == CH.y and z == CH.z) then left2 = left2 + 1 end
  end end end
  CHECK(doneG and left2 == 0, "the area is dug out (" .. left2 .. " left)")
  CHECK(W.blocks[key(CH.x, CH.y, CH.z)] == "minecraft:barrel", "the work chest itself is never dug")
  CHECK(orderOK, "top layer first")
  CHECK((W.stock["minecraft:dirt"] or 0) > dirt0, "what the drones dug went into AE2 (dirt " .. dirt0 .. " -> " .. tostring(W.stock["minecraft:dirt"]) .. ")")

  -- one block
  W.blocks[key(5, 66, 5)] = "minecraft:stone"
  out = handleCommand("dw break 5 66 5") or {}
  CHECK(DW.job and DW.job.kind == "dig", "dw break starts at once: " .. table.concat(out, " / "))
  runUntil(function() return DW.job == nil and next(DW.trips) == nil end)
  CHECK(not W.blocks[key(5, 66, 5)], "the block is broken")

  -- in chat
  local told = {}
  local tell0 = chatTell
  chatTell = function(_, t) told[#told + 1] = t end
  local function chat(m) handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " " .. m }) end
  W.blocks[key(7, 66, 7)] = "minecraft:stone"
  chat("break 7 66 7")
  CHECK(DW.job and DW.job.kind == "dig", "$drone break x y z: " .. tostring(told[#told]))
  runUntil(function() return DW.job == nil and next(DW.trips) == nil end)
  CHECK(not W.blocks[key(7, 66, 7)], "... broken")
  told = {}
  chat("dig 20 66 20")
  chat("dig 22 65 22")
  CHECK(table.concat(told, " "):find("dig yes", 1, true), "$drone dig here twice: asks for yes: " .. table.concat(told, " / "))
  chat("dig yes")
  CHECK(DW.job and DW.job.kind == "dig" and #DW.job.dug == 18, "$drone dig yes starts it (18 spots)")
  DW.stopBuild("test")
  DW.startBuild("roadb", UX, UY, UZ, 0, false)
  runUntil(function() return DW.job == nil and next(DW.trips) == nil end)
  told = {}
  chat("unbuild roadb")
  chat("unbuild yes")
  CHECK(DW.job and DW.job.kind == "unbuild", "$drone unbuild <name> then yes: " .. table.concat(told, " / "))
  -- saved and read back (a restart mid-job)
  local J0 = DW.job
  DW.job = nil
  DW.load()
  CHECK(DW.job and DW.job.kind == "unbuild" and DW.job.dug == J0.dug, "an unbuild job is saved and read back")
  DW.stopBuild("test")
  runUntil(function() return next(DW.trips) == nil end)
  chatTell = tell0
end

-- A BLOCK THE DRONE CANNOT BREAK (the owner: "I gave the drone the exact block coords and it did not break it" - the dig
-- action ends "done" also when the drone may not / cannot break it): one more try, then a WARNING - never "done"
do
  local notes = {}
  local pn0 = pushNote
  pushNote = function(kind, msg, ...) notes[#notes + 1] = tostring(kind) .. ": " .. tostring(msg) return pn0(kind, msg, ...) end
  W.blocks[key(9, 66, 9)] = "minecraft:stone"
  W.noDig[key(9, 66, 9)] = true
  W.digRefused = 0
  handleCommand("dw break 9 66 9")
  local doneN = runUntil(function() return DW.job == nil and next(DW.trips) == nil end, 30000)
  local all = table.concat(notes, "\n")
  CHECK(doneN and W.digRefused == 2, "it tried twice (" .. tostring(W.digRefused) .. ")")
  CHECK(all:find("WARNING", 1, true) and all:find("NOTHING back", 1, true), "then a WARNING that the block may still be there:\n" .. all)
  CHECK(not all:find("DONE: Drones finished", 1, true), "not reported as done")
  -- a block it can break: done at the first try, no warning
  notes = {}
  W.noDig = {}
  W.blocks[key(9, 66, 9)] = "minecraft:stone"
  handleCommand("dw break 9 66 9")
  runUntil(function() return DW.job == nil and next(DW.trips) == nil end, 30000)
  all = table.concat(notes, "\n")
  CHECK(not W.blocks[key(9, 66, 9)] and all:find("DONE", 1, true) and not all:find("WARNING", 1, true), "a block it can break: DONE, no warning")
  pushNote = pn0
end
