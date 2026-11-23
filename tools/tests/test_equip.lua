-- ARMOUR + OFFHAND ON THE INVENTORY TAB (the owner: "fix the inventory tab - equipment cannot be selected or moved"): a
-- tapped armour piece was un-picked by the next inventory read (selName kept only backpack items) and DETAILS had no view
-- for it. Now: hit "equip" -> state.equipSel -> DETAILS of the piece + TAKE OFF > INTO YOUR INVENTORY / TAKE OFF + SEND >
-- AE2 (equipMove: exportItem with fromSlot 36..40 into the buffer chest, then the backpack / the network); a manager that
-- ignores fromSlot (took one from the backpack instead) -> put back, refused with the reason.
local P, CHEST, ME = {}, {}, {}
local honour = true
local function key(t, a, b) if type(a) == "table" then return a, b end return b, a end
local function add(t, name, n) t[name] = (t[name] or 0) + n end
local function reset()
  P = { [0] = { name = "minecraft:diamond_helmet", count = 1 }, [5] = { name = "minecraft:bread", count = 10 },
        [39] = { name = "minecraft:diamond_helmet", count = 1, displayName = "Diamond Helmet", damage = 10, maxDamage = 363 },
        [36] = { name = "minecraft:iron_boots", count = 1 }, [40] = { name = "minecraft:shield", count = 1 } }
  CHEST, ME = {}, {}
end
reset()
local FAKE = {
  getOwner = function() return "Alaory" end,
  getItems = function()
    local out = {}
    for s, it in pairs(P) do out[#out + 1] = { name = it.name, count = it.count, slot = s, displayName = it.displayName,
                                               damage = it.damage, maxDamage = it.maxDamage } end
    return out
  end,
  exportItem = function(a, b)                                     -- player -> chest
    local f = key(nil, a, b)
    local from = honour and f.fromSlot
    for s = 0, 40 do
      local it = P[s]
      if it and it.name == f.name and (not from or s == from) then
        local n = math.min(it.count, f.count or 64)
        it.count = it.count - n
        if it.count <= 0 then P[s] = nil end
        add(CHEST, f.name, n)
        return n
      end
    end
    return 0
  end,
  importItem = function(a, b)                                     -- chest -> player (first free backpack slot)
    local f = key(nil, a, b)
    local have = CHEST[f.name] or 0
    local n = math.min(have, f.count or 64)
    if n <= 0 then return 0 end
    for s = 0, 35 do
      if not P[s] then P[s] = { name = f.name, count = n } CHEST[f.name] = have - n return n end
    end
    return 0
  end,
}
local inv0, bridge0, owner0 = inv, bridge, state.owner
bridgeKind = bridgeKind or "ME"
inv, state.owner = FAKE, "Alaory"
bridge = { importItem = function(a, b) local f = key(nil, a, b) local n = math.min(CHEST[f.name] or 0, f.count or 64)
  CHEST[f.name] = (CHEST[f.name] or 0) - n add(ME, f.name, n) return n end, getItem = function() return nil end }
local function readAll() pcall(refreshInventory) end
readAll()
CHECK(state.equip[1] and state.equip[1].name == "minecraft:diamond_helmet", "the helmet is read as equipment")

-- picking: hit "equip" -> stays picked after an inventory read (before: dropped by the next read)
state.page = "inventory"
hits = {}
draw()
local eh
for _, h in ipairs(hits) do if h[5] == "equip" and h[6] == 1 then eh = h end end
CHECK(eh, "the helmet cell is a tap area of its own")
handleTouch(eh[1], eh[2])
CHECK(state.equipSel == 1, "tap = picked")
readAll()
CHECK(state.equipSel == 1, "still picked after the next inventory read")
hits = {}
draw()
local scr = {}
for y = 1, H do scr[#scr + 1] = (MONITOR.getLine(y)) end
scr = table.concat(scr, "\n")
CHECK(scr:find("Diamond Helmet", 1, true) and scr:find("TAKE OFF", 1, true), "DETAILS show the piece + TAKE OFF")

-- TAKE OFF -> into the backpack, from the HELMET slot (not the spare helmet in slot 0)
runAction({ kind = "eqoff", name = "minecraft:diamond_helmet", count = 1, slotIdx = 1 })
local helmets = 0
for s = 0, 35 do if P[s] and P[s].name == "minecraft:diamond_helmet" then helmets = helmets + 1 end end
CHECK(not P[39] and helmets == 2 and P[0], "taken off into the backpack (worn slot empty, 2 helmets in the backpack)")
CHECK(state.equipSel == nil, "un-picked once moved")

-- SEND > AE2: boots off and into the network
reset() readAll()
runAction({ kind = "eqsend", name = "minecraft:iron_boots", count = 1, slotIdx = 4 })
CHECK(not P[36] and (ME["minecraft:iron_boots"] or 0) == 1, "boots taken off + sent to AE2")
runAction({ kind = "eqsend", name = "minecraft:shield", count = 1, slotIdx = 5 })
CHECK(not P[40] and (ME["minecraft:shield"] or 0) == 1, "the offhand too")

-- a manager that ignores fromSlot: the spare helmet came out of the BACKPACK -> put back, refused
reset() readAll() honour = false
local toast0 = setToast
local said
setToast = function(t) said = t end
runAction({ kind = "eqoff", name = "minecraft:diamond_helmet", count = 1, slotIdx = 1 })
setToast = toast0
CHECK(P[39] and said and said:find("cannot take worn items off", 1, true), "fromSlot ignored -> put back, says why: " .. tostring(said))
local back = 0
for s = 0, 35 do if P[s] and P[s].name == "minecraft:diamond_helmet" then back = back + 1 end end
CHECK(back == 1 and (CHEST["minecraft:diamond_helmet"] or 0) == 0, "the spare helmet is back in the backpack")
honour = true

-- a full backpack: TAKE OFF refused
reset()
for s = 0, 35 do P[s] = { name = "minecraft:dirt", count = 64 } end
readAll()
said = nil
setToast = function(t) said = t end
runAction({ kind = "eqoff", name = "minecraft:diamond_helmet", count = 1, slotIdx = 1 })
setToast = toast0
CHECK(P[39] and said and said:find("full", 1, true), "full backpack: refused, says so")
inv, bridge, state.owner = inv0, bridge0, owner0
state.page, state.equipSel = "home", nil
