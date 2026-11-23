-- SHOWCASE: a busy example base for the README pictures (tools/preview, not game code).
--   lua5.3 run.lua ../.. out/home.txt home showcase.lua && python3 render.py out/home.txt out/home.png
-- Made-up coordinates (never the ones in base_config.lua), an AE2 network, a fleet of turtles in every
-- state, mapped land, messages, worn curios and a schematic picked for a drone build.
local HOME = { x = 240, y = 70, z = -380 }
CONFIG.drone.home = HOME
CONFIG.drone.charger = { x = 238, y = 70, z = -384 }
state.mapView = nil

-- saved places + drones + the work chest, all at the made-up base (never your own coordinates)
state.waypoints = { { name = "Base", x = HOME.x, y = HOME.y, z = HOME.z }, { name = "Farm", x = HOME.x + 140, y = 66, z = HOME.z - 60 },
                    { name = "Nether portal", x = HOME.x - 90, y = 71, z = HOME.z + 35 }, { name = "Spawn", x = 0, y = 72, z = 0 } }
for i, nm in ipairs({ "drone_interface_0", "drone_interface_2" }) do
  local d = PERIPHS[nm] and PERIPHS[nm].obj
  if d then d.getDronePosition = function() return HOME.x - 2 - i, HOME.y + 1, HOME.z - 4 end end
end
PERIPHS["minecraft:barrel_7"] = { types = { "minecraft:barrel", "inventory" }, obj = { list = function() return {} end, size = function() return 27 end } }
CONFIG.drone.workChest, CONFIG.drone.workChestAt = "minecraft:barrel_7", { x = HOME.x - 3, y = HOME.y, z = HOME.z - 5 }
pcall(refreshDrones)
-- players (made-up spots near the made-up base)
local PL = {
  Alaory = { x = 242.4, y = 70, z = -377.2, health = 18, maxHealth = 20, airSupply = 300, yaw = 180, eyeHeight = 1.62,
             dimension = "minecraft:overworld" },
  Zed = { x = 610, y = 66, z = -120, health = 7, maxHealth = 20, airSupply = 300, yaw = 10, dimension = "minecraft:overworld" },
  Mia = { x = -90, y = 41, z = -700, health = 20, maxHealth = 20, airSupply = 140, yaw = 200, dimension = "minecraft:overworld" },
}
local det = PERIPHS.player_detector_1.obj
det.getPlayer = function(n) return PL[n] end
det.getPlayerPos = function(n) return PL[n] end
pcall(refreshPlayers, true)

-- AE2
local STOCK = {
  { "minecraft:cobblestone", "Cobblestone", 184320 }, { "minecraft:iron_ingot", "Iron Ingot", 12844 },
  { "minecraft:diamond", "Diamond", 3412 }, { "minecraft:redstone", "Redstone Dust", 20488 },
  { "minecraft:oak_log", "Oak Log", 6120 }, { "minecraft:gold_ingot", "Gold Ingot", 4211 },
  { "minecraft:coal_block", "Block of Coal", 1902 }, { "minecraft:glass", "Glass", 8800 },
  { "minecraft:torch", "Torch", 2304 }, { "minecraft:emerald", "Emerald", 911 },
  { "minecraft:netherite_ingot", "Netherite Ingot", 42 }, { "minecraft:ender_pearl", "Ender Pearl", 388 },
  { "mekanism:ingot_osmium", "Osmium Ingot", 7340 }, { "create:andesite_alloy", "Andesite Alloy", 2650 },
  { "minecraft:golden_carrot", "Golden Carrot", 612 }, { "minecraft:totem_of_undying", "Totem of Undying", 14 },
  { "ae2:certus_quartz_crystal", "Certus Quartz Crystal", 5120 }, { "minecraft:oak_planks", "Oak Planks", 9022 },
  { "minecraft:stone_bricks", "Stone Bricks", 15010 }, { "minecraft:copper_ingot", "Copper Ingot", 3300 },
}
local FL = { { "minecraft:water", "Water", 2048000 }, { "minecraft:lava", "Lava", 612000 }, { "mekanism:hydrogen", "Hydrogen", 88000 } }
local function find(n) for _, s in ipairs(STOCK) do if s[1] == n then return s end end end
bridgeKind = "ME"
bridge = {
  isOnline = function() return true end, isConnected = function() return true end,
  getItems = function()
    local o = {}
    for _, s in ipairs(STOCK) do o[#o + 1] = { name = s[1], displayName = s[2], amount = s[3], count = s[3],
      isCraftable = s[1] == "minecraft:torch" or s[1] == "minecraft:glass", tags = {} } end
    return o
  end,
  getItem = function(f) local s = find(f and f.name or "") if s then return { name = s[1], displayName = s[2], amount = s[3], count = s[3] } end end,
  getFluids = function() local o = {} for _, f in ipairs(FL) do o[#o + 1] = { name = f[1], displayName = f[2], amount = f[3] } end return o end,
  getCraftableItems = function() return { { name = "minecraft:torch", displayName = "Torch" }, { name = "minecraft:glass", displayName = "Glass" } } end,
  getCraftableFluids = function() return {} end,
  isItemCraftable = function(f) return f and (f.name == "minecraft:torch" or f.name == "minecraft:glass") end,
  getStoredEnergy = function() return 1630000 end, getEnergyCapacity = function() return 2400000 end,
  getEnergyUsage = function() return 412 end, getAverageEnergyInput = function() return 900 end,
  getTotalItemStorage = function() return 16777216 end, getUsedItemStorage = function() return 9437184 end,
  getTotalFluidStorage = function() return 4194304 end, getUsedFluidStorage = function() return 1310720 end,
  getCraftingCPUs = function() return {
    { name = "CPU 1", isBusy = true, storage = 65536, coProcessors = 4,
      craftingJob = { quantity = 512, crafted = 340, completion = 0.66, resource = { name = "minecraft:torch", displayName = "Torch" } } },
    { name = "CPU 2", isBusy = false, storage = 16384, coProcessors = 1 },
    { name = "CPU 3", isBusy = false, storage = 4096, coProcessors = 1 } } end,
  getCraftingTasks = function() return {} end,
  getDrives = function() return {
    { name = "ME Drive", usedBytes = 3100000, totalBytes = 5242880, cells = {
      { item = "ae2:item_storage_cell_256k", usedBytes = 210000, bytes = 262144, type = "item" },
      { item = "ae2:item_storage_cell_256k", usedBytes = 150000, bytes = 262144, type = "item" },
      { item = "ae2:fluid_storage_cell_64k", usedBytes = 30000, bytes = 65536, type = "fluid" } } } } end,
  getPatterns = function() return {
    { patternType = "crafting", primaryOutput = { name = "minecraft:torch", displayName = "Torch", count = 4 },
      inputs = { { primaryInput = { name = "minecraft:stick", count = 1 }, multiplier = 1 }, { primaryInput = { name = "minecraft:coal", count = 1 }, multiplier = 1 } } },
    { patternType = "processing", primaryOutput = { name = "minecraft:glass", displayName = "Glass", count = 1 },
      inputs = { { primaryInput = { name = "minecraft:sand", count = 1 }, multiplier = 1 } } } } end,
  craftItem = function() return true end, exportItem = function(f) return f and f.count or 0 end, importItem = function(f) return f and f.count or 0 end,
}
do local okM, me = pcall(fetchME) if okM and type(me) == "table" then state.me = me end end
if MEX then MEX.readAt, MEX.patAt = -1e9, -1e9 pcall(MEX.read) end
state.meSel = state.meSel or "minecraft:diamond"

-- the turtle program (version 14), held by every turtle but one
CODE = CODE or { ver = "showcase-v14", pieces = { "" }, text = "" }
TT.versions.byHash[CODE.ver] = 14
-- turtles: a fleet in every state
local function T(id, label, fuel, dx, dz, y, task, ago, extra)
  local t = { id = id, label = label, log = {}, lastN = 0, fuel = fuel, fuelMax = 100000,
              pos = { x = HOME.x + dx, y = y, z = HOME.z + dz, f = "north" }, task = task, lastSeen = CLOCK - (ago or 1),
              home = { x = HOME.x + (id % 4), y = 69, z = HOME.z - 6 }, gear = { "modem", "scanner", "chunky" },
              ver = CODE.ver, movedAt = CLOCK - 1, taskAt = CLOCK - 5 }
  for k, v in pairs(extra or {}) do t[k] = v end
  t.log = { { t = CLOCK - 40, text = "Survey: 16 spots handed out" }, { t = CLOCK - 9, text = "Scanned " .. (HOME.x + dx) .. ", " .. (HOME.z + dz) } }
  state.turtles[id] = t
end
state.turtles = {}
T(3, "Scout1", 41820, 92, -74, 96, "surveying spot 6 of 16", 1)
T(4, "Scout2", 37011, -84, 66, 104, "surveying spot 11 of 16", 2)
T(5, "Scout3", 52440, 38, 98, 88, "surveying spot 2 of 16", 1)
T(6, "Scout4", 18760, -40, -30, 150, "going home", 3)
T(7, "Rescuer", 64000, 1, -6, 69, "idle", 2, { rescuerRole = true })
T(8, "Builder", 22000, 2, -6, 69, "idle", 4, { gear = { "modem", "chunky", "pick" } })
T(9, "Scout5", 640, 104, 34, 77, "idle", 3, { ver = "old-v13" })
T(11, "Scout6", 30100, -98, -88, 71, "survey", 3600)
T(12, "Scout7", 12000, 60, 84, 64, "idle", 5, { stuck = "blocked - could not reach the spot", stuckPos = { x = HOME.x + 60, y = 64, z = HOME.z + 84 } })
state.dsel = 3
state.tsel = nil

-- mapped land around the base (a turtle's scan = 17 x 17 columns)
MAP.loaded = true
local NAMES = { "minecraft:grass_block", "minecraft:sand", "minecraft:water", "minecraft:stone", "minecraft:oak_leaves",
                "minecraft:snow", "minecraft:spruce_leaves", "minecraft:dirt_path" }
local function hash(a, b) local n = math.sin(a * 127.1 + b * 311.7) * 43758.5453 return n - math.floor(n) end
local function noise(x, z, sc)                      -- smooth value noise
  local gx, gz = math.floor(x / sc), math.floor(z / sc)
  local fx, fz = x / sc - gx, z / sc - gz
  fx, fz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
  local a, b = hash(gx, gz), hash(gx + 1, gz)
  local c, d = hash(gx, gz + 1), hash(gx + 1, gz + 1)
  return (a + (b - a) * fx) * (1 - fz) + (c + (d - c) * fx) * fz
end
local function terrain(x, z)
  local h = 58 + 22 * noise(x, z, 90) + 8 * noise(x, z, 31) + 3 * noise(x, z, 9)
  local lake = math.sqrt((x - HOME.x - 70) ^ 2 + ((z - HOME.z + 60) * 1.3) ^ 2)
  if lake < 38 then h = math.min(h, 58 + lake / 6) end
  if math.abs(x - HOME.x) < 22 and math.abs(z - HOME.z) < 22 then h = 70 end    -- (the base's flat yard)
  h = math.floor(h)
  local b
  if h < 62 then b, h = 3, 62
  elseif h < 64 then b = 2
  elseif h > 86 then b = 6
  elseif h > 79 then b = 4
  elseif noise(x, z, 14) > 0.62 and hash(x, z) > 0.45 then b, h = (h > 74 and 7 or 5), h + 6
  else b = 1 end
  if (math.abs(x - HOME.x) <= 1 or math.abs(z - HOME.z) <= 1) and b ~= 3 and math.abs(x - HOME.x) + math.abs(z - HOME.z) < 160 then b = 8 end
  if math.abs(x - HOME.x) <= 6 and math.abs(z - HOME.z) <= 6 then b = 4 end         -- (the base itself)
  return h, b
end
-- (far ones first: only the newest chunks keep every column - the ones round the base)
local spots = {}
for sx = HOME.x - 340, HOME.x + 340, 17 do
  for sz = HOME.z - 300, HOME.z + 300, 17 do
    local d = math.max(math.abs(sx - HOME.x), math.abs(sz - HOME.z))
    if d < 280 or (d < 330 and (sx + sz) % 3 == 0) then spots[#spots + 1] = { sx, sz, d } end
  end
end
table.sort(spots, function(a, b) return a[3] > b[3] end)
for _, sp in ipairs(spots) do
  local sx, sz = sp[1], sp[2]
  local cols = {}
  for i = 0, 17 * 17 - 1 do
    local x, z = sx + (i % 17) - 8, sz + math.floor(i / 17) - 8
    local h, b = terrain(x, z)
    cols[i + 1] = { h - 64, b }
  end
  MAP.addScan({ x = sx, y = 64, z = sz, r = 8, cols = cols, names = NAMES })
end
state.mapView = nil
local v = MAP.view()
v.zoom, v.rot = tonumber(GETENV and GETENV("ZOOM")) or 2, 0
v.cx, v.cz = HOME.x, HOME.z
state.mapImage = nil

-- messages
local notes = {
  { "DONE", "Scout3 finished its survey batch: 16 spots mapped", C.good },
  { "INFO", "Drone 1: Alaory > Base - done", C.info },
  { "DONE", "Craft job: 512 Torch - started on CPU 1", C.good },
  { "WARNING", "Scout5 is low on fuel (640) - a drone brings fuel", C.warn },
  { "DONE", "Factory built a new turtle: Scout7", C.good },
  { "INFO", "Survey: 9 of 9 free turtles went", C.info },
  { "WARNING", "Scout7 is STUCK at " .. (HOME.x + 60) .. ", 64, " .. (HOME.z + 84) .. " - the rescuer goes", C.warn },
}
local push0 = USER_ACTION
for _, n in ipairs(notes) do pcall(pushNote, n[1], n[2], n[3]) end
USER_ACTION = push0
if state.notes then state.notes = {} end                  -- (no boxes over the picture; they stay in the lists)

-- a schematic picked for a drone build
local s = { size = { x = 7, y = 5, z = 6 }, palette = { { name = "minecraft:stone_bricks", props = {} },
            { name = "minecraft:oak_planks", props = {} }, { name = "minecraft:glass", props = {} }, { name = "minecraft:torch", props = {} } },
            blocks = {} }
for x = 0, 6 do for z = 0, 5 do
  s.blocks[#s.blocks + 1] = { x, 0, z, 1 }
  if x == 0 or x == 6 or z == 0 or z == 5 then
    for y = 1, 3 do s.blocks[#s.blocks + 1] = { x, y, z, (y == 2 and (x == 3 or z == 2)) and 3 or 2 } end
  end
  s.blocks[#s.blocks + 1] = { x, 4, z, (x + z) % 2 == 0 and 1 or 2 }
end end
s.blocks[#s.blocks + 1] = { 3, 1, 1, 4 }
SCHEM.cache = { watchtower = { s = s, path = "store:31/schematics/watchtower.b64" }, cottage = { s = s, path = "disk2/schematics/cottage.nbt" } }
if DW then
  DW.view = DW.view or {}
  DW.view.schems = { "watchtower", "cottage" }
  pcall(DW.select, "watchtower")
end
