-- Survey turtles came back FULL of dug things: cobblestone, dirt, then ores (the owner: "stop making survey turtles
-- hold ores"), then "they dig trees and leaves and other modded items too". A junk LIST always missed a modded drop -
-- now a KEEP list: away from the base a turtle keeps its gear, its fuel (any item the game burns that is not wood /
-- tools) and its endless fuel; everything else is thrown away - right after the dig that brought it in, and when it
-- is nearly full. Never into a chest, never at the base.
--   lua5.3 tools/tests/node_junk.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local function piece(from, to)
  local a = assert(src:find(from, 1, true), "not found: " .. from)
  local b = assert(src:find(to, a + 1, true), "not found: " .. to)
  return src:sub(a, b - 1)
end
local code = piece("-- WHAT A TURTLE KEEPS", "\nfunction isOre(b)") .. "\n" ..
             piece("function isFuel(n)", "-- what rescue gear this turtle carries")
-- what the GAME says burns (refuel(0)): coal, a modded coke, and wood things (logs, saplings, sticks ...)
local BURNS = { ["minecraft:coal"] = true, ["modpack:coke"] = true, ["minecraft:oak_log"] = true,
                ["minecraft:oak_sapling"] = true, ["minecraft:stick"] = true, ["biomesoplenty:fir_log"] = true }
local SLOTS, SEL, DROPPED, INV = {}, 1, {}, {}
turtle = {
  getItemCount = function(i) return SLOTS[i] and SLOTS[i].count or 0 end,
  getItemDetail = function(i) local d = SLOTS[i] return d and { name = d.name, count = d.count } end,
  getSelectedSlot = function() return SEL end, select = function(i) SEL = i end,
  refuel = function(n) assert(n == 0, "only refuel(0) - nothing burned") return SLOTS[SEL] and BURNS[SLOTS[SEL].name] or false end,
  dropUp = function() DROPPED[#DROPPED + 1] = { "top", SLOTS[SEL].name } SLOTS[SEL] = nil return true end,
  drop = function() DROPPED[#DROPPED + 1] = { "front", SLOTS[SEL].name } SLOTS[SEL] = nil return true end,
  dropDown = function() DROPPED[#DROPPED + 1] = { "bottom", SLOTS[SEL].name } SLOTS[SEL] = nil return true end,
}
peripheral = { hasType = function(side, t) return INV[side] == true and t == "inventory" end }
S = { reuse = { ["modpack:endless_coal_thing"] = true } }
local BASE = false
function inBaseZone() return BASE end
assert(load(code, "=junk"))()
local function fill()
  SLOTS = { { name = "minecraft:cobblestone", count = 64 }, { name = "minecraft:raw_iron", count = 5 },
            { name = "minecraft:diamond", count = 3 }, { name = "advancedperipherals:geo_scanner", count = 1 },
            { name = "minecraft:diamond_pickaxe", count = 1 }, { name = "minecraft:coal", count = 10 },
            { name = "minecraft:oak_sapling", count = 12 }, { name = "minecraft:stick", count = 7 },
            { name = "biomesoplenty:fir_log", count = 4 }, { name = "minecraft:apple", count = 2 },
            { name = "biomesoplenty:willow_vine", count = 3 }, { name = "mekanism:raw_osmium", count = 4 },
            { name = "modpack:coke", count = 9 }, { name = "modpack:endless_coal_thing", count = 1 },
            { name = "computercraft:wireless_modem_advanced", count = 1 }, { name = "advancedperipherals:chunk_controller", count = 1 } }
  DROPPED = {}
end
fill()
CHECK(freeSlots() == 0, "a full turtle")
local n = dropJunk()
local names = {}
for _, d in ipairs(DROPPED) do names[d[2]] = true end
local thrown = { "minecraft:cobblestone", "minecraft:raw_iron", "minecraft:diamond", "minecraft:oak_sapling", "minecraft:stick",
                 "biomesoplenty:fir_log", "minecraft:apple", "biomesoplenty:willow_vine", "mekanism:raw_osmium" }
local missed = {}
for _, t in ipairs(thrown) do if not names[t] then missed[#missed + 1] = t end end
CHECK(#missed == 0, "stone, ores, logs, saplings, sticks, apples, modded drops thrown away (missed: " .. table.concat(missed, ", ") .. ")")
local kept = { "advancedperipherals:geo_scanner", "minecraft:diamond_pickaxe", "minecraft:coal", "modpack:coke",
               "modpack:endless_coal_thing", "computercraft:wireless_modem_advanced", "advancedperipherals:chunk_controller" }
local lost = {}
for _, k in ipairs(kept) do if names[k] then lost[#lost + 1] = k end end
CHECK(#lost == 0, "gear, coal, a modded fuel the game burns, the endless fuel are kept (thrown: " .. table.concat(lost, ", ") .. ")")
CHECK(freeSlots() == #thrown, "slots free again (" .. freeSlots() .. ")")
CHECK(SEL == 1, "the selected slot is put back")
-- never into a chest: a chest above -> it uses the front
fill()
INV = { top = true }
dropJunk()
CHECK(DROPPED[1] and DROPPED[1][1] == "front", "a chest above: thrown out at the front, not into the chest")
INV = { top = true, front = true, bottom = true }
fill()
CHECK(dropJunk() == 0 and #DROPPED == 0, "chests all round: nothing thrown")
INV = {}
BASE = true
fill()
CHECK(dropJunk() == 0, "never at the base")
CHECK(src:find("m.freeSlots = freeSlots", 1, true), "free slots go to the base")
-- tryDig: what the dig brought in is thrown away at once; coal it dug stays; the pickaxe / scanner stay
BASE = false
do
  CONFIG = { dig = true }
  function natural() return true end
  function withEquipped(_, fn) return fn() end
  local NEXT
  turtle.inspect = function() return true, { name = "minecraft:oak_leaves" } end
  turtle.dig = function()
    for i = 1, 16 do if not SLOTS[i] then SLOTS[i] = { name = NEXT, count = 1 } return true end end
    return true
  end
  assert(load(piece("tryDig = function(dir)", "-- WHAT A TURTLE KEEPS"), "=trydig"))()
  SLOTS = { { name = "minecraft:diamond_pickaxe", count = 1 }, { name = "advancedperipherals:geo_scanner", count = 1 },
            { name = "minecraft:coal", count = 10 } }
  DROPPED = {}
  NEXT = "minecraft:raw_iron"
  CHECK(tryDig("front") and #DROPPED == 1 and DROPPED[1][2] == "minecraft:raw_iron", "a dig that brings raw iron: thrown away at once")
  NEXT = "minecraft:oak_sapling"
  tryDig("front")
  CHECK(#DROPPED == 2 and DROPPED[2][2] == "minecraft:oak_sapling", "a leaf's sapling: thrown away at once")
  NEXT = "biomesoplenty:flowering_oak_leaves_drop"
  tryDig("front")
  CHECK(#DROPPED == 3, "a modded drop: thrown away at once")
  NEXT = "minecraft:coal"
  SLOTS[3] = nil
  tryDig("front")
  CHECK(#DROPPED == 3, "coal from coal ore is kept (fuel)")
  CHECK(SLOTS[1] and SLOTS[2], "the pickaxe and the scanner stay")
end
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
