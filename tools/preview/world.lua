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
PERIPHS = {
  right = { types = { "monitor" }, obj = nil },
  inventory_manager_3 = { types = { "inventory_manager" }, obj = inv },
  player_detector_1 = { types = { "player_detector" }, obj = det },
  chat_box_0 = { types = { "chat_box" }, obj = { sendMessageToPlayer = function() end } },
  drone_interface_0 = { types = { "drone_interface" }, obj = drone },
  drone_interface_2 = { types = { "drone_interface" }, obj = drone2 },
}
