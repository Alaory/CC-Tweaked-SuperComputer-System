-- `chests` (the owner: "how do I check which storages are connected - chests and drone
-- barrels/chests etc"): every chest / barrel / tank on the cable, how full, and its job.
local function inv(name, slots, items)
  PERIPHS[name] = { types = { "minecraft:chest", "inventory" }, obj = {
    size = function() return slots end,
    list = function() return items end } }
end
inv("minecraft:barrel_1", 27, {})
inv("minecraft:barrel_7", 27, {})
inv("minecraft:chest_3", 27, { [1] = { name = "minecraft:stone", count = 64 }, [5] = { name = "minecraft:dirt", count = 10 } })
inv("minecraft:chest_9", 54, {})
PERIPHS["minecraft:tank_2"] = { types = { "fluid_storage" }, obj = {
  tanks = function() return { { name = "minecraft:water", amount = 8000 } } end } }
PERIPHS["turtle_4"] = { types = { "turtle", "inventory" }, obj = { size = function() return 16 end, list = function() return {} end } }
CONFIG.me = CONFIG.me or {}
CONFIG.me.buffer = "minecraft:barrel_1"
CONFIG.drone = CONFIG.drone or {}
CONFIG.drone.workChest = "minecraft:barrel_7"
FACTORY.chest = "minecraft:chest_9"
local out = handleCommand("chests") or {}
local text = table.concat(out, "\n")
local function line(name) for i, l in ipairs(out) do if l:find(name, 1, true) then return l, out[i + 1] or "" end end end
local l1, j1 = line("barrel_1")
CHECK(l1 and l1:find("EMPTY", 1, true) and j1:find("AE2 item buffer", 1, true), "the AE2 buffer is named as such\n" .. text)
local l7, j7 = line("barrel_7")
CHECK(l7 and j7:find("DRONE WORK CHEST", 1, true), "the drone work chest is named as such")
local l3, j3 = line("chest_3")
CHECK(l3 and l3:find("2/27 slots, 74 items", 1, true) and j3:find("not used by the base", 1, true), "how full a chest is: " .. tostring(l3))
local l9, j9 = line("chest_9")
CHECK(l9 and j9:find("factory chest", 1, true), "the factory chest")
local lt = line("tank_2")
CHECK(lt and lt:find("8 B water", 1, true), "a tank and its fluid: " .. tostring(lt))
CHECK(not line("turtle_4"), "turtles are not listed as chests")
CHECK(text:find("Drone work chest: minecraft:barrel_7", 1, true), "the summary names the drone work chest")
-- the ones the base uses come first
local first
for _, l in ipairs(out) do if l:find("^ minecraft:") then first = l break end end
CHECK(first and not first:find("chest_3", 1, true), "chests the base uses are listed first")
