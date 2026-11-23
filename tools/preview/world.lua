-- fake blocks with sample data
local items = {
  [1] = { name = "minecraft:diamond_pickaxe", displayName = "Diamond Pickaxe", count = 1, damage = 120, maxDamage = 1561 },
  [2] = { name = "minecraft:torch", displayName = "Torch", count = 64 },
  [3] = { name = "minecraft:cobblestone", displayName = "Cobblestone", count = 64 },
  [4] = { name = "minecraft:cobblestone", displayName = "Cobblestone", count = 41 },
  [5] = { name = "minecraft:cooked_beef", displayName = "Steak", count = 23 },
  [6] = { name = "minecraft:iron_ingot", displayName = "Iron Ingot", count = 37 },
  [10] = { name = "sophisticatedbackpacks:backpack", displayName = "Backpack", count = 1 },
  [12] = { name = "minecraft:oak_log", displayName = "Oak Log", count = 18 },
  [15] = { name = "minecraft:redstone", displayName = "Redstone Dust", count = 52 },
  [20] = { name = "pneumaticcraft:drone", displayName = "Drone", count = 1 },
  [27] = { name = "minecraft:ender_pearl", displayName = "Ender Pearl", count = 9 },
}
local inv = {
  getOwner = function() return "Alaory" end,
  list = function() return items end,
  getArmor = function() return { { name = "minecraft:diamond_helmet", displayName = "Diamond Helmet", count = 1, slot = 103 },
                                  { name = "minecraft:elytra", displayName = "Elytra", count = 1, slot = 102 } } end,
  getItemInHand = function() return items[1] end,
  getItemInOffHand = function() return { name = "minecraft:shield", displayName = "Shield", count = 1 } end,
  wrapStorageItem = function() return nil end,
  listCurios = function() return {} end, getCuriosSizes = function() return {} end,
}
local players = {
  Alaory = { x = -5290.4, y = 68, z = 10841.2, health = 18, maxHealth = 20, airSupply = 300, yaw = 90 },
  Zed = { x = -120, y = 64, z = 330, health = 7, maxHealth = 20, airSupply = 300, yaw = 10 },
  Mia = { x = 812, y = 40, z = -77, health = 20, maxHealth = 20, airSupply = 140, yaw = 200 },
}
local det = {
  getOnlinePlayers = function() return { "Alaory", "Zed", "Mia" } end,
  getPlayer = function(n) return players[n] end,
  getPlayersInRange = function() return { "Alaory", "Mia" } end,
}
local drone = {
  isConnectedToDrone = function() return true end, getDronePressure = function() return 9.4 end,
  getDronePosition = function() return -5293, 15, 10846 end, getAction = function() return nil end,
  isActionDone = function() return true end,
}
local drone2 = {
  isConnectedToDrone = function() return true end, getDronePressure = function() return 3.1 end,
  getDronePosition = function() return -5294, 15, 10846 end, getAction = function() return "pneumaticcraft:teleport" end,
  isActionDone = function() return false end,
}
-- an Environment Detector like Advanced Peripherals 0.7 for 1.21.1 (getMoonId / getMoonName,
-- scanEntities(radius): living things only, x y z relative to the detector)
ENVDET = {
  getBiome = function() return "minecraft:plains" end, getBlockLightLevel = function() return 11 end,
  getSkyLightLevel = function() return 15 end, getDayLightLevel = function() return 13 end,
  getTime = function() return 24000 * 41 + 11800 end, isSlimeChunk = function() return true end,
  getDimension = function() return "minecraft:overworld" end,
  listDimensions = function() return { "minecraft:overworld", "minecraft:the_nether", "minecraft:the_end",
                                       "javd:void", "twilightforest:twilight_forest", "ae2:spatial_storage",
                                       "compactmachines:5de22bb4-4a67-42d5-9172-7830057de9b7",
                                       "compactmachines:65b7d22a-1a5c-419f-97cc-4513cfe3addf", "blue_skies:end" } end,
  getMoonId = function() return 2 end, getMoonName = function() return "Third quarter" end,
  isRaining = function() return true end, isThunder = function() return false end, isSunny = function() return false end,
  canSleepHere = function() return false end,
  scanEntities = function(r)
    if r > 16 then return nil, "Radius exceeds max value" end
    -- (like the owner's server: the TYPE as the name, a baby flag on the player too)
    return { { name = "minecraft:zombie", health = 14, maxHealth = 20, baby = false, x = 6.5, y = -1, z = -9.2 },
             { name = "minecraft:cave_spider", health = 12, maxHealth = 12, baby = false, x = -3.1, y = 0, z = 4.4 },
             { name = "minecraft:cow", health = 10, maxHealth = 10, baby = true, inLove = false, x = 12, y = 0, z = 3 },
             { name = "minecraft:player", health = 18, maxHealth = 20, baby = false, x = 2, y = 0, z = 2 } }
  end,
}
PERIPHS = {
  right = { types = { "monitor" }, obj = nil },
  environment_detector_0 = { types = { "environment_detector" }, obj = ENVDET },
  inventory_manager_3 = { types = { "inventory_manager" }, obj = inv },
  player_detector_1 = { types = { "player_detector" }, obj = det },
  chat_box_0 = { types = { "chat_box" }, obj = { sendMessageToPlayer = function() end } },
  drone_interface_0 = { types = { "drone_interface" }, obj = drone },
  drone_interface_2 = { types = { "drone_interface" }, obj = drone2 },
}
