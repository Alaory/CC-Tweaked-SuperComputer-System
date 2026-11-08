-- CURIOS: items listed under "#curios:<slot>" fit that slot even when the
-- answer has no tags; learned items (worn before) are listed; AUTO toggles a
-- rule; CURIOS.autoTick puts one on from AE2 when the slot is empty (a used
-- totem), not when it is worn or none is left; the page draws with buttons.
local function hitsOf(kind)
  local r = {}
  for _, h in ipairs(hits or {}) do if h[5] == kind then r[#r + 1] = h end end
  return r
end
CURIOS.auto, CURIOS.fits, CURIOS.busy = {}, {}, {}
local worn = {}                                    -- charm slot 1
local rows = function()
  return { { name = "charm", count = 1, base = 0, cells = { [1] = worn[1] } },
           { name = "ring", count = 2, base = 0, cells = {} } }
end
local savedFetch, savedInv, savedBridge, savedKind = fetchCurios, inv, bridge, bridgeKind
bridgeKind = bridgeKind or "ME"
fetchCurios = function() return rows() end
inv = inv or {}
local stock = { ["minecraft:totem_of_undying"] = 3 }
bridge = { getItem = function(f) local n = stock[f.name] return n and { name = f.name, count = n } or nil end }

-- learning + toggling
CURIOS.learnWorn({ { name = "ring", cells = { [1] = { name = "mod:ring_of_x" } } } })
CHECK(CURIOS.fits.ring and CURIOS.fits.ring["mod:ring_of_x"], "worn item learned for its slot")
CHECK(CURIOS.toggleAuto("charm", "minecraft:totem_of_undying", "Totem of Undying") == true, "AUTO on")
CHECK(#CURIOS.auto == 1, "one rule")

-- empty slot + totems in AE2 -> one is put on
state.actionQueue = {}
CURIOS.lastRead = -100
CURIOS.autoTick()
local a = state.actionQueue[1]
CHECK(a and a.kind == "cequip" and a.name == "minecraft:totem_of_undying" and a.slotType == "charm" and a.slotNo == 0
      and a.count == 1 and a.auto, "auto-equip queued for the empty charm slot")
-- not again while it is running
state.actionQueue = {}
CLOCK = CLOCK + 9 CURIOS.autoTick()
CHECK(#state.actionQueue == 0, "not twice while busy")
-- worn now -> nothing
worn[1] = { name = "minecraft:totem_of_undying", count = 1 }
CLOCK = CLOCK + 30 CURIOS.autoTick()
CHECK(#state.actionQueue == 0, "worn: nothing to do")
-- totem used, none left -> reason shown, nothing queued
worn[1] = nil stock["minecraft:totem_of_undying"] = nil
CLOCK = CLOCK + 30 CURIOS.autoTick()
CHECK(#state.actionQueue == 0 and CURIOS.auto[1].why == "none left in AE2", "none in AE2: says why")
-- a failed put-on: reason kept
CURIOS.autoResult({ slotType = "charm", name = "minecraft:totem_of_undying" }, 0, "no curios chest")
CHECK(CURIOS.auto[1].why == "no curios chest", "failure reason kept")

-- partial ME view: "#curios:charm" listing without tags -> fits charm
state.meTagCache = { curioOf = { ["mod:lucky_charm"] = { charm = true } } }
-- the page: an empty charm slot lists the totem (tagless, AUTO on), the
-- learned ring is listed for ring, SHOW ALL lists everything
state.me = { items = {
  { name = "minecraft:totem_of_undying", display = "Totem of Undying", count = 2 },
  { name = "mod:lucky_charm", display = "Lucky Charm", count = 1, curios = { charm = true } },
  { name = "mod:ring_of_x", display = "Ring of X", count = 1 },
  { name = "minecraft:dirt", display = "Dirt", count = 64 } }, byName = {} }
state.curios = rows()
state.t.curios = os.clock()
state.page, state.curiosSel, state.curiosAll = "curios", { type = "charm", pos = 1 }, false
CHECK(pcall(draw), "CURIOS page draws")
local names = {}
for _, h in ipairs(hitsOf("act")) do if h[6].kind == "cequip" then names[h[6].name] = true end end
CHECK(names["mod:lucky_charm"] and names["minecraft:totem_of_undying"], "tagged + auto item listed for charm")
CHECK(not names["minecraft:dirt"], "dirt not listed")
CHECK(#hitsOf("cauto") >= 2, "AUTO buttons shown")
state.curiosSel = { type = "ring", pos = 1 }
draw()
names = {}
for _, h in ipairs(hitsOf("act")) do if h[6].kind == "cequip" then names[h[6].name] = true end end
CHECK(names["mod:ring_of_x"], "learned (untagged) ring listed")
state.curiosAll = true
draw()
names = {}
for _, h in ipairs(hitsOf("act")) do if h[6].kind == "cequip" then names[h[6].name] = true end end
CHECK(names["minecraft:dirt"], "SHOW ALL lists everything")
-- worn item: KEEP ONE ON button
worn[1] = { name = "minecraft:totem_of_undying", count = 1, displayName = "Totem of Undying" }
state.curios = rows()
state.curiosSel = { type = "charm", pos = 1 }
draw()
CHECK(#hitsOf("cauto") == 1, "worn item: KEEP ONE ON button")

fetchCurios, inv, bridge, bridgeKind = savedFetch, savedInv, savedBridge, savedKind
CURIOS.auto, CURIOS.fits = {}, {}
