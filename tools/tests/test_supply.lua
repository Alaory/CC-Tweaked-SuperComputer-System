-- SUPPLY (base_supply.lua): a storage on the cable kept stocked from AE2 (console
-- `supply`): items topped up to the amount (only PLAIN ones - never your own),
-- fluids in mB, NOTHING ever taken out, the base's own containers refused, a
-- supplied tank is not taken as the fluid buffer, warnings once.
local ME = { ["minecraft:coal"] = 1000, ["minecraft:diamond_pickaxe"] = 1 }
local MEF = { ["minecraft:water"] = 100000 }
local CHEST = { [1] = { name = "minecraft:coal", count = 20 }, [2] = { name = "minecraft:stone", count = 64 } }
local TANK = { { name = "minecraft:water", amount = 2000 } }
local OWN_PICK = true
local TAKEN = 0
bridgeKind = "ME"
bridge = {
  getItem = function(f) return { name = f.name, amount = ME[f.name] or 0, fingerprint = "FP-" .. f.name } end,
  getItems = function(f)
    if f.name == "minecraft:diamond_pickaxe" and OWN_PICK then
      return { { name = f.name, amount = 1, fingerprint = "MINE", components = { ["minecraft:enchantments"] = { levels = { ["minecraft:efficiency"] = 5 } } } } }
    end
    return { { name = f.name, amount = ME[f.name] or 0, fingerprint = "FP-" .. f.name } }
  end,
  exportItem = function(f, target)
    if target ~= "minecraft:chest_7" then return 0 end
    if f.fingerprint == "MINE" then TAKEN = TAKEN + 1 end
    local n = math.min(f.count, ME[f.name] or 0)
    ME[f.name] = (ME[f.name] or 0) - n
    CHEST[#CHEST + 1] = { name = f.name, count = n }
    return n
  end,
  exportFluid = function(f, target)
    if target ~= "mekanism:basic_fluid_tank_0" then return 0 end
    local n = math.min(f.amount, MEF[f.name] or 0, 1000)        -- (1 bucket per call)
    MEF[f.name] = (MEF[f.name] or 0) - n
    TANK[#TANK + 1] = { name = f.name, amount = n }
    return n
  end,
}
PERIPHS["minecraft:chest_7"] = { types = { "minecraft:chest", "inventory" }, obj = {
  list = function() local l = {} for i, v in ipairs(CHEST) do l[i] = v end return l end,
  pullItems = function() error("must never take anything out") end, pushItems = function() error("must never take anything out") end } }
PERIPHS["mekanism:basic_fluid_tank_0"] = { types = { "mekanism:basic_fluid_tank", "fluid_storage" }, obj = {
  tanks = function() return TANK end, pushFluid = function() error("must never take anything out") end } }
PERIPHS["functionalstorage:storage_controller_0"] = { types = { "functionalstorage:storage_controller", "inventory", "fluid_storage" }, obj = {
  list = function() return {} end, tanks = function() return {} end } }
CONFIG.me = CONFIG.me or {}
CONFIG.me.fluidBuffer = nil
CONFIG.me.buffer = "functionalstorage:storage_controller_0"
SUPPLY.rules = {}
local function sum(list, name, k)
  local n = 0
  for _, v in ipairs(list) do if v.name == name then n = n + v[k] end end
  return n
end

-- refused: the base's own buffer, a non-storage, a missing one, a fluid into a chest
CHECK(not SUPPLY.add("functionalstorage:storage_controller_0", "item", "coal", 10), "the AE2 buffer (your storage controller) is refused")
CHECK(not SUPPLY.add("minecraft:chest_99", "item", "coal", 10), "a storage that is not on the cable is refused")
CHECK(not SUPPLY.add("minecraft:chest_7", "fluid", "water", 1000), "a fluid into a chest is refused")
CHECK(not SUPPLY.add("minecraft:chest_7", "item", "coal", 0), "0 is refused")
local cands = table.concat(SUPPLY.candidates(), " ")
CHECK(cands:find("chest_7", 1, true) and not cands:find("storage_controller", 1, true), "candidates: the chest, not the buffer")

-- items: kept at 128 coal (20 there already), the stone left alone
local ok, msg = SUPPLY.add("minecraft:chest_7", "item", "coal", 128)
CHECK(ok, "rule added: " .. tostring(msg))
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(sum(CHEST, "minecraft:coal", "count") == 128, "topped up to 128 coal (" .. sum(CHEST, "minecraft:coal", "count") .. ")")
CHECK(ME["minecraft:coal"] == 1000 - 108, "exactly 108 came out of AE2")
CHECK(sum(CHEST, "minecraft:stone", "count") == 64, "the other things in it are untouched")
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(ME["minecraft:coal"] == 892, "full: nothing more")
-- the owner takes 50 out -> refilled
for _, v in ipairs(CHEST) do if v.name == "minecraft:coal" then v.count = math.max(0, v.count - 50) end end
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(sum(CHEST, "minecraft:coal", "count") == 128, "50 used -> refilled to 128")
-- your OWN (enchanted) pickaxe is never sent
local notes0 = #(NOTES or {})
SUPPLY.add("minecraft:chest_7", "item", "diamond_pickaxe", 1)
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(TAKEN == 0 and sum(CHEST, "minecraft:diamond_pickaxe", "count") == 0, "your own enchanted pickaxe is NOT sent")
local r = SUPPLY.rules[2]
CHECK(r.why and r.why:find("OWN", 1, true), "and it says why: " .. tostring(r.why))
CHECK(r.warned, "a warning when it runs short")
local warned = r.warned
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(r.warned == warned, "warned once, not every tick")
OWN_PICK = false
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(sum(CHEST, "minecraft:diamond_pickaxe", "count") == 1 and not r.why, "a plain one in AE2 -> sent")

-- fluids: 16 buckets, the tank takes 1 bucket per call
ok, msg = SUPPLY.add("mekanism:basic_fluid_tank_0", "fluid", "water", 16000)
CHECK(ok, "fluid rule added: " .. tostring(msg))
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(sum(TANK, "minecraft:water", "amount") == 16000, "tank topped up to 16 buckets (" .. sum(TANK, "minecraft:water", "amount") .. " mB)")
-- the supplied tank is not taken as the fluid buffer
local buf0 = CONFIG.me.buffer
CONFIG.me.buffer = nil                    -- (found by itself: the only OTHER fluid storage on the cable)
local fb = fluidBuffer()
CONFIG.me.buffer = buf0
CHECK(fb == "functionalstorage:storage_controller_0", "the fluid buffer stays your storage controller, not the supplied tank (" .. tostring(fb) .. ")")
-- the factory never picks a supplied chest
CHECK(FACTORY.reserved("minecraft:chest_7") == "supply", "a supplied chest is never the factory chest")

-- saved and read back
SUPPLY.save()
local keep = SUPPLY.rules
SUPPLY.rules = {}
SUPPLY.load()
CHECK(#SUPPLY.rules == #keep and SUPPLY.rules[3].kind == "fluid" and SUPPLY.rules[3].keep == 16000, "rules saved and read back")

-- console
local out = table.concat(handleCommand("supply") or {}, "\n")
CHECK(out:find("KEPT STOCKED", 1, true) and out:find("chest_7", 1, true), "console  supply  lists the rules")
out = table.concat(handleCommand("supply 1 fluid lava") or {}, "\n")
CHECK(out:find("Use:", 1, true), "a half command explains how")
out = table.concat(handleCommand("supply stop 2") or {}, "\n")
CHECK(#SUPPLY.rules == 2 and out:find("stopped", 1, true), "supply stop 2")
out = table.concat(handleCommand("supply stop all") or {}, "\n")
CHECK(#SUPPLY.rules == 0, "supply stop all")
