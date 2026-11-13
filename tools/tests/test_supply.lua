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

-- a MODDED tank with its own computer functions (no "fluid_storage" type, no tanks()):
-- getStored() = { name, amount } (nil when empty) - listed, read and filled
local MOD = nil
PERIPHS["bigtanks:steel_tank_0"] = { types = { "bigtanks:steel_tank" }, obj = {
  getStored = function() return MOD end, getCapacity = function() return 64000 end } }
local exp0 = bridge.exportFluid
bridge.exportFluid = function(f, target)
  if target == "bigtanks:steel_tank_0" then
    local n = math.min(f.amount, 4000)
    MOD = { name = f.name, amount = ((MOD and MOD.amount) or 0) + n }
    return n
  end
  return exp0(f, target)
end
-- a block with nothing the base knows: listed as "other", supply check shows its functions
PERIPHS["weirdmod:thing_0"] = { types = { "weirdmod:thing" }, obj = { doStuff = function() end } }
local cands2 = table.concat(SUPPLY.candidates(), " ")
CHECK(cands2:find("steel_tank_0", 1, true), "a modded tank with getStored() is a usable storage")
local listing = table.concat(handleCommand("supply") or {}, "\n")
CHECK(listing:find("weirdmod:thing_0", 1, true) and listing:find("Other blocks", 1, true), "an unknown block on the cable is listed under 'Other blocks'")
local chk = table.concat(handleCommand("supply check weirdmod:thing_0") or {}, "\n")
CHECK(chk:find("doStuff", 1, true) and chk:find("fluids: no", 1, true), "supply check shows what it offers")
ok, msg = SUPPLY.add("bigtanks:steel_tank_0", "fluid", "lava", 10000)
CHECK(ok, "fluid rule on the modded tank: " .. tostring(msg))
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(MOD and MOD.name == "minecraft:lava" and MOD.amount >= 10000, "modded tank filled to 10 buckets (" .. tostring(MOD and MOD.amount) .. ")")
local amt = MOD.amount
CLOCK = CLOCK + 11
SUPPLY.tick()
CHECK(MOD.amount == amt, "and not more once it is full")
SUPPLY.stop("bigtanks:steel_tank_0")

-- THE FLUID BUFFER IS REMEMBERED: the owner's storage controller was the only fluid storage,
-- then an Entangled block went on the cable -> "several fluid storages", filling the owner's
-- tanks stopped. The one found alone is remembered and stays the buffer.
local savedP = {}
for _, k in ipairs({ "mekanism:basic_fluid_tank_0", "bigtanks:steel_tank_0", "entangled:tile_0" }) do savedP[k] = PERIPHS[k] PERIPHS[k] = nil end
local rules0 = SUPPLY.rules
SUPPLY.rules = {}
CONFIG.me.buffer, CONFIG.me.fluidBuffer = "minecraft:barrel_1", nil
FB_MEM = nil
CHECK(fluidBuffer() == "functionalstorage:storage_controller_0", "only one fluid storage -> it is the buffer")
PERIPHS["entangled:tile_0"] = { types = { "entangled:tile", "fluid_storage" }, obj = { tanks = function() return {} end } }
FB_MEM = nil                                 -- (as after a base restart: read back from the file)
local fb2, fbErr = fluidBuffer()
CHECK(fb2 == "functionalstorage:storage_controller_0", "a 2nd fluid storage added later: the remembered one stays (" .. tostring(fb2) .. " " .. tostring(fbErr) .. ")")
CHECK(SUPPLY.refuse("functionalstorage:storage_controller_0"), "the fluid buffer can not be a supply target")
CHECK(not SUPPLY.refuse("entangled:tile_0"), "the Entangled block can")
-- nothing remembered + several: says what to type
FB_MEM = false
local fb3, err3 = fluidBuffer()
CHECK(fb3 == nil and tostring(err3):find("fluidbuffer", 1, true), "several, none remembered -> tells you to type fluidbuffer")
local outFB = table.concat(handleCommand("fluidbuffer") or {}, "\n")
CHECK(outFB:find("1. entangled:tile_0", 1, true) and outFB:find("2. functionalstorage:storage_controller_0", 1, true), "fluidbuffer lists them numbered")
handleCommand("fluidbuffer 2")
CHECK(fluidBuffer() == "functionalstorage:storage_controller_0", "fluidbuffer 2 picks the storage controller")
handleCommand("fluidbuffer auto")
CHECK(CONFIG.me.fluidBuffer == nil, "fluidbuffer auto = found by itself again")
PERIPHS["entangled:tile_0"] = nil
for k, v in pairs(savedP) do PERIPHS[k] = v end
SUPPLY.rules = rules0
CONFIG.me.buffer = "functionalstorage:storage_controller_0"

-- THE AE2 TAB: KEEP A STORAGE FILLED row (tap the storage = next one, an amount twice = keep it,
-- KEPT AT ... - STOP twice = stop). Drawing reads SUPPLY.cache only (filled by the tick).
do
  local rulesB = SUPPLY.rules
  SUPPLY.rules = {}
  CONFIG.me.fluidBuffer = "functionalstorage:storage_controller_0"
  SUPPLY.refreshCache()
  CHECK(#SUPPLY.cache.fluid >= 1 and #SUPPLY.cache.item >= 1, "cache: fluid + item storages (" .. #SUPPLY.cache.fluid .. "/" .. #SUPPLY.cache.item .. ")")
  local me = state.me or {}
  state.me = me
  me.items, me.byName, me.chemicals, me.byNameC, me.cellTypes, me.tasks = me.items or {}, me.byName or {}, {}, {}, {}, {}
  local w = { name = "minecraft:water", display = "Water", count = 2987589793000 }
  me.fluids, me.byNameF = { w }, { ["minecraft:water"] = w }
  me.fluidBuf, me.fluidBufTanks = "functionalstorage:storage_controller_0", {}
  state.meType, state.meSel, state.page = "fluids", "minecraft:water", "me"
  local function findHit(pred)
    for _, h in ipairs(hits) do if pred(h) then return h end end
  end
  local calls0 = 0
  local pc0 = peripheral.call
  peripheral.call = function(...) calls0 = calls0 + 1 return pc0(...) end
  draw()
  peripheral.call = pc0
  CHECK(calls0 == 0, "drawing the AE2 tab calls no peripheral (" .. calls0 .. ")")
  local full = findHit(function(h) return h[5] == "act" and h[6].kind == "supplyset" and h[6].count == SUPPLY.FULL end)
  local nextB = findHit(function(h) return h[5] == "supnext" end)
  CHECK(full and nextB, "KEEP A STORAGE FILLED row: storage button + FULL")
  if full and nextB then
    local first = full[6].target
    local fx, fy = full[1] + 1, full[2] + 1
    -- tap the storage button: the next storage
    if #SUPPLY.cache.fluid > 1 then
      handleTouch(nextB[1] + 1, nextB[2] + 1)
      draw()
      local f2 = findHit(function(h) return h[5] == "act" and h[6].kind == "supplyset" and h[6].count == SUPPLY.FULL end)
      CHECK(f2 and f2[6].target ~= first, "tapping the storage picks the next one")
      handleTouch(nextB[1] + 1, nextB[2] + 1)        -- (back to the first)
      draw()
    end
    handleTouch(fx, fy)
    CHECK(#SUPPLY.rules == 0, "one tap: nothing yet (tap twice)")
    draw()
    handleTouch(fx, fy)
    local r = SUPPLY.rules[1]
    CHECK(r and r.target == first and r.kind == "fluid" and r.name == "minecraft:water" and r.keep == SUPPLY.FULL,
          "two taps on FULL: " .. tostring(first) .. " is kept filled with water")
    draw()
    local stop = findHit(function(h) return h[5] == "act" and h[6].kind == "supplystop" end)
    CHECK(stop, "then the row shows KEPT AT FULL - STOP")
    if stop then
      handleTouch(stop[1] + 1, stop[2] + 1)
      draw()
      handleTouch(stop[1] + 1, stop[2] + 1)
      CHECK(#SUPPLY.rules == 0, "two taps on STOP: no longer kept filled")
    end
  end
  -- FULL fills as much as goes in (one call never above max int)
  CHECK(SUPPLY.amount({ kind = "fluid" }, SUPPLY.FULL) == "FULL", "FULL shows as FULL")
  SUPPLY.rules = rulesB
end

-- SPEED: a tank that takes 1 bucket per call (each call a game tick). Before: 16 calls every
-- 10 s (~1.6 B/s). Now: pumps for SUPPLY.BUDGET s per round and comes straight back while
-- the tank still takes it; back to the slow check once it is full.
do
  local rulesB = SUPPLY.rules
  SUPPLY.rules = {}
  local SLOW, CAP = 0, 300000
  PERIPHS["slowmod:tank_0"] = { types = { "slowmod:tank", "fluid_storage" }, obj = {
    tanks = function() return { { name = "minecraft:water", amount = SLOW } } end } }
  local expS = bridge.exportFluid
  bridge.exportFluid = function(f, target)
    if target == "slowmod:tank_0" then
      CLOCK = CLOCK + 0.05
      local n = math.min(f.amount, 1000, CAP - SLOW)
      SLOW = SLOW + n
      return n
    end
    return expS(f, target)
  end
  MEF["minecraft:water"] = 1e12
  SUPPLY.add("slowmod:tank_0", "fluid", "water", SUPPLY.FULL)
  CLOCK = CLOCK + 11
  local t0 = CLOCK
  local busy = SUPPLY.tick()
  CHECK(SLOW >= 30000, "one round pumps ~" .. SUPPLY.BUDGET .. " s worth, not 16 calls (" .. SLOW .. " mB)")
  CHECK(busy == true, "still taking it -> busy (the worker comes straight back)")
  local rounds = 0
  while busy and rounds < 50 do
    rounds = rounds + 1
    CLOCK = CLOCK + 0.05                               -- (the worker waits 0.05 s)
    busy = SUPPLY.tick()
  end
  CHECK(SLOW == CAP, "full in " .. math.floor(CLOCK - t0) .. " s (300 B; the old way took ~190 s)")
  CHECK(CLOCK - t0 < 30, "fast: " .. math.floor(CLOCK - t0) .. " s")
  CHECK(busy == false, "full -> not busy")
  local before = SLOW
  CLOCK = CLOCK + 1
  CHECK(SUPPLY.tick() == false and SLOW == before, "then only the slow check again (every 10 s)")
  bridge.exportFluid = expS
  PERIPHS["slowmod:tank_0"] = nil
  SUPPLY.rules = rulesB
end
local wsrc = (io.open("base_workers.lua") or io.open("../../base_workers.lua")):read("a")
CHECK(wsrc:find("function supplyWorker", 1, true) and not wsrc:find("pcall(SUPPLY.tick)                 --", 1, true),
      "supply runs in its own worker, not the comms worker")
local isrc = (io.open("inventory.lua") or io.open("../../inventory.lua")):read("a")
CHECK(isrc:find("supplyWorker)", 1, true), "inventory.lua starts supplyWorker")

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
