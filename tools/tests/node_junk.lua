-- Survey turtles came back FULL of dug blocks (cobblestone, dirt ...): nothing ever threw
-- them away, and a full turtle cannot take fuel from a chest. Now: with <= 2 free slots a
-- dig throws the junk away (never tools, fuel; never into a chest; never at the base).
-- ORES TOO (the owner: "stop making survey turtles hold ores - it is full"): raw ores, gems, anything a dig brought in
-- (learned per run) are thrown away right after the dig; fuel, endless fuel and tools stay.
--   lua5.3 tools/tests/node_junk.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local a = src:find("-- plain blocks a turtle digs on its way", 1, true)
local b = src:find("\nfunction isOre(b)", a, true)
local code = src:sub(a, b)
local fa = src:find("\nfunction isFuel(n)", 1, true)
code = code .. src:sub(fa, src:find("\nend\n", fa + 1, true) + 4)
S = { reuse = { ["modpack:endless_coal_thing"] = true } }
local SLOTS, SEL, DROPPED, INV = {}, 1, {}, {}
turtle = {
  getItemCount = function(i) return SLOTS[i] and SLOTS[i].count or 0 end,
  getItemDetail = function(i) local d = SLOTS[i] return d and { name = d.name, count = d.count } end,
  getSelectedSlot = function() return SEL end, select = function(i) SEL = i end,
  dropUp = function() DROPPED[#DROPPED + 1] = { "top", SLOTS[SEL].name } SLOTS[SEL] = nil return true end,
  drop = function() DROPPED[#DROPPED + 1] = { "front", SLOTS[SEL].name } SLOTS[SEL] = nil return true end,
  dropDown = function() DROPPED[#DROPPED + 1] = { "bottom", SLOTS[SEL].name } SLOTS[SEL] = nil return true end,
}
peripheral = { hasType = function(side, t) return INV[side] == true and t == "inventory" end }
local BASE = false
function inBaseZone() return BASE end
assert(load(code, "=junk"))()
local function fill()
  SLOTS = { { name = "minecraft:cobblestone", count = 64 }, { name = "minecraft:dirt", count = 40 },
            { name = "minecraft:diamond", count = 3 }, { name = "advancedperipherals:geo_scanner", count = 1 },
            { name = "minecraft:diamond_pickaxe", count = 1 }, { name = "minecraft:coal", count = 10 },
            { name = "minecraft:cobbled_deepslate", count = 64 }, { name = "minecraft:gravel", count = 12 },
            { name = "minecraft:raw_iron", count = 5 }, { name = "minecraft:redstone", count = 9 },
            { name = "minecraft:glowstone", count = 2 }, { name = "create:andesite", count = 3 },
            { name = "minecraft:flint", count = 2 }, { name = "minecraft:netherrack", count = 64 },
            { name = "mekanism:raw_osmium", count = 4 }, { name = "modpack:endless_coal_thing", count = 1 } }
  DROPPED = {}
end
fill()
CHECK(freeSlots() == 0, "a full turtle")
local n = dropJunk()
local names = {}
for _, d in ipairs(DROPPED) do names[d[2]] = true end
CHECK(names["minecraft:cobblestone"] and names["minecraft:dirt"] and names["minecraft:gravel"] and names["minecraft:netherrack"]
      and names["minecraft:cobbled_deepslate"] and names["create:andesite"], "stone, dirt, gravel, netherrack ... thrown away")
CHECK(names["minecraft:diamond"] and names["minecraft:raw_iron"] and names["minecraft:redstone"] and names["mekanism:raw_osmium"],
      "dug ores / gems thrown away too (modded raw ores as well)")
CHECK(not names["minecraft:coal"] and not names["modpack:endless_coal_thing"] and not names["advancedperipherals:geo_scanner"]
      and not names["minecraft:diamond_pickaxe"], "fuel, endless fuel and tools are kept")
CHECK(not names["minecraft:glowstone"], "a glowstone BLOCK it did not dig is not junk")
CHECK(freeSlots() >= 11, "slots free again (" .. freeSlots() .. ")")
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
-- tryDig: what the dig brought in is LEARNED and thrown away at once (an apple from leaves too); the pickaxe swap
-- (the modem side) does not count as brought in
BASE = false
do
  local ta = src:find("tryDig = function(dir)", 1, true)
  local tb = src:find("-- plain blocks a turtle digs on its way", ta, true)
  CONFIG = { dig = true }
  function natural() return true end
  function withEquipped(_, fn) return fn() end
  local NEXT
  turtle.inspect = function() return true, { name = "minecraft:iron_ore" } end
  turtle.dig = function()
    for i = 1, 16 do if not SLOTS[i] then SLOTS[i] = { name = NEXT, count = 1 } return true end end
    return true
  end
  assert(load(src:sub(ta, tb - 1), "=trydig"))()
  SLOTS = { { name = "minecraft:diamond_pickaxe", count = 1 }, { name = "advancedperipherals:geo_scanner", count = 1 },
            { name = "minecraft:coal", count = 10 } }
  DROPPED = {}
  NEXT = "minecraft:raw_iron"
  CHECK(tryDig("front") and #DROPPED == 1 and DROPPED[1][2] == "minecraft:raw_iron", "a dig that brings raw iron: thrown away at once")
  NEXT = "minecraft:apple"
  tryDig("front")
  CHECK(#DROPPED == 2 and DROPPED[2][2] == "minecraft:apple" and DUG["minecraft:apple"], "anything a dig brings in is learned + thrown (an apple)")
  NEXT = "minecraft:coal"
  SLOTS[3] = nil
  tryDig("front")
  CHECK(#DROPPED == 2, "coal from coal ore is kept (fuel)")
  CHECK(SLOTS[1] and SLOTS[2], "the pickaxe and the scanner stay")
end
CHECK(src:find("m.freeSlots = freeSlots", 1, true), "free slots go to the base")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
