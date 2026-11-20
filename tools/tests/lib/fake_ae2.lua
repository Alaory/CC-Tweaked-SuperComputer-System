-- a fake AE2 network + ME Bridge for the fuzz tests (not a test itself: tests dofile it)
-- an AE2 network (the preview world has none): items, fluids, crafting, transfers
local STOCK = { ["minecraft:diamond"] = 500, ["minecraft:stone"] = 9000, ["minecraft:oak_log"] = 64, ["minecraft:torch"] = 3 }
local FLUIDS = { ["minecraft:water"] = 64000, ["minecraft:lava"] = 8000 }
local function itemList()
  local out = {}
  for n, c in pairs(STOCK) do out[#out + 1] = { name = n, displayName = n:gsub("^.-:", ""), amount = c, count = c, isCraftable = n == "minecraft:torch", tags = {} } end
  return out
end
bridgeKind = "ME"
bridge = {
  isOnline = function() return true end, isConnected = function() return true end,
  getItems = function() return itemList() end,
  getItem = function(f) local c = STOCK[f and f.name or ""] if c then return { name = f.name, amount = c, count = c } end end,
  getFluids = function() local o = {} for n, a in pairs(FLUIDS) do o[#o + 1] = { name = n, amount = a, displayName = n } end return o end,
  getCraftableItems = function() return { { name = "minecraft:torch", displayName = "Torch" } } end,
  getCraftableFluids = function() return {} end,
  isCraftable = function(f) return f and f.name == "minecraft:torch" end,
  isItemCraftable = function(f) return f and f.name == "minecraft:torch" end,
  craftItem = function() return true end, craftFluid = function() return true end,
  exportItem = function(f) local c = math.min(f and f.count or 0, STOCK[f and f.name or ""] or 0) STOCK[f.name] = (STOCK[f.name] or 0) - c return c end,
  importItem = function(f) local c = f and f.count or 1 return c end,
  exportFluid = function(f) return math.min(f and f.count or 1000, 1000) end,
  importFluid = function(f) return math.min(f and f.count or 1000, 1000) end,
  getStoredEnergy = function() return 1000 end, getEnergyCapacity = function() return 2000 end,
  getEnergyUsage = function() return 10 end, getAverageEnergyInput = function() return 20 end,
  getTotalItemStorage = function() return 100000 end, getUsedItemStorage = function() return 50000 end,
  getTotalFluidStorage = function() return 100000 end, getUsedFluidStorage = function() return 1000 end,
  getCraftingCPUs = function() return { { name = "CPU 1", isBusy = false, storage = 1024, coProcessors = 1 } } end,
  getCraftingTasks = function() return {} end,
  getPatterns = function() return { { patternType = "crafting", primaryOutput = { name = "minecraft:torch", count = 4 },
                                       inputs = { { primaryInput = { name = "minecraft:stick", count = 1 }, multiplier = 1 } } } } end,
}
do local okM, me = pcall(fetchME) if okM and type(me) == "table" then state.me = me end end
MEX.readAt, MEX.patAt = -1e9, -1e9
pcall(MEX.read)

