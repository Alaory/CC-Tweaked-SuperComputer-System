-- base_me.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   The ME (AE2) / RS network: reading it (with a 'partial view' when getItems()
--   crashes), moving items through the buffer chest, fluids to/from your tanks,
--   crafting, 'mesetup', and the OWED list (items the program put in a buffer and
--   still has to deliver - only those exact amounts are ever moved).
--   Also: setToast() / setPopup(), and runAction() which runs confirmed button presses.

---------------------------------------------------------------------
-- ME / RS BRIDGE
---------------------------------------------------------------------
-- ===== messages (shown as boxes top-right; see drawNotes in base_ui_core.lua) =====
-- Every message also goes into the EVENTS tab (the last few, in memory only).
-- How long a box stays, in seconds, by kind (0 = until it is tapped). Can be
-- changed with CONFIG.notes = { info = 3, done = 3, warning = 3, error = 3, keep = 100 }
-- (everything stays readable in the EVENTS tab)
local NOTE_DEFAULTS = { info = 3, done = 3, warning = 3, error = 3, keep = 100 }
function noteSetting(k)
  local v = CONFIG.notes and tonumber(CONFIG.notes[k])
  if v == nil then v = NOTE_DEFAULTS[k] end
  return v
end
local noteId = 0

-- the label of a message, from its colour
function noteKind(col)
  if col == C.bad then return "ERROR" end
  if col == C.warn then return "WARNING" end
  if col == C.good then return "DONE" end
  return "INFO"
end

-- real time for the EVENTS tab ("01.11 14:30"); game time if os.date is missing
local function realTime(fmt)
  local ok, r = pcall(os.date, fmt)
  if ok and type(r) == "string" then return r end
  return textutils.formatTime(os.time(), true)
end

-- show a message. It stays for its kind's time (CONFIG.notes; `secs` from the
-- caller is ignored - the owner wants short messages), or until tapped
function pushNote(title, msg, col, secs)
  col = col or C.good
  msg = tostring(msg or "")
  local now = os.clock()
  local life = noteSetting(noteKind(col):lower())
  local exp = (life > 0) and (now + life) or nil
  -- the same message again while it is shown: refresh it instead of stacking
  for _, n in ipairs(state.notes) do
    if n.msg == msg and n.title == title then
      n.t, n.exp, n.life, n.times = now, exp, life, (n.times or 1) + 1
      os.queueEvent("inv_update")
      return
    end
  end
  noteId = noteId + 1
  local when = realTime("%H:%M")
  table.insert(state.notes, 1, { id = noteId, title = title, msg = msg, col = col, t = now,
                                 exp = exp, life = life, when = when })
  table.insert(state.noteLog, 1, { title = title, msg = msg, col = col, when = realTime("%d.%m %H:%M") })
  while #state.noteLog > noteSetting("keep") do table.remove(state.noteLog) end
  if state.page ~= "events" then state.noteUnread = (state.noteUnread or 0) + 1 end
  os.queueEvent("inv_update")
end

-- close one message box
function dismissNote(id)
  for i, n in ipairs(state.notes) do
    if n.id == id then table.remove(state.notes, i) return end
  end
end

-- a short message
function setToast(msg, col, secs) pushNote(nil, msg, col, secs) end

-- an important message with a title (a warning unless another colour is given)
function setPopup(title, msg, col) pushNote(title, msg, col or C.warn) end

-- pcall wrapper: returns ok, r1, r2
function callx(obj, fn, ...)
  if type(obj[fn]) ~= "function" then return false, "missing function " .. fn end
  return pcall(obj[fn], ...)
end

-- A transfer (import/export), whatever this Advanced Peripherals version
-- calls it and whatever order it wants: (item, target) or (target, item).
-- A wrong order always fails with a type error before anything moves, so
-- trying both is safe; the order that worked is remembered.
local ORDER = {}                     -- [function name] = "it" (item first) or "ti" (target first)
function transfer(obj, names, target, item)
  for _, fn in ipairs(names) do
    if type(obj[fn]) == "function" then
      local function call(order)
        if order == "it" then return pcall(obj[fn], item, target) end
        return pcall(obj[fn], target, item)
      end
      local first = ORDER[fn] or "it"
      local ok, r, e = call(first)
      if ok then ORDER[fn] = first return true, r, e end
      local other = (first == "it") and "ti" or "it"
      local ok2, r2, e2 = call(other)
      if ok2 then ORDER[fn] = other return true, r2, e2 end
      return false, tostring(r2 or r)
    end
  end
  return false, "missing function " .. table.concat(names, " / ")
end
-- ME Bridge: chest <-> ME;  Inventory Manager: chest <-> player
local ME_IN, ME_OUT = { "importItem" }, { "exportItem" }
local INV_TO_PLAYER, INV_FROM_PLAYER = { "importItem", "addItemToPlayer" }, { "exportItem", "removeItemFromPlayer" }
-- Curios slots <-> a chest (Inventory Manager): same style as importItem / exportItem
local CURIO_IN, CURIO_OUT = { "importCuriosItem" }, { "exportCuriosItem" }

-- a count from a number or a {count / amount} table
function numOf(r)
  if type(r) == "number" then return r end
  if type(r) == "table" then return tonumber(r.count or r.amount) end
  return nil
end

-- One modded item that the server cannot convert breaks Advanced Peripherals'
-- whole getItems() list. A list filtered BY TAG only converts items with that
-- tag - so the network is read tag by tag instead (the broken item is left
-- out, unless it has that tag: those tags are reported to find it).
ME_TAGS = {
  "c:ingots", "c:nuggets", "c:gems", "c:dusts", "c:ores", "c:raw_materials", "c:storage_blocks",
  "c:rods", "c:plates", "c:gears", "c:wires", "c:stones", "c:cobblestones", "c:sands", "c:gravels",
  "c:glass_blocks", "c:glass_panes", "c:dyes", "c:seeds", "c:crops", "c:foods", "c:tools", "c:armors",
  "c:buckets", "c:chests", "c:barrels", "c:fences", "c:fence_gates", "c:obsidians", "c:netherracks",
  "c:end_stones", "c:sandstone_blocks", "c:strings", "c:leathers", "c:feathers", "c:eggs", "c:bones",
  "c:gunpowders", "c:slime_balls", "c:ender_pearls", "c:mushrooms", "c:flowers", "c:clay",
  "c:enchanting_fuels", "c:fertilizers", "c:rope", "c:tools/melee_weapon", "c:tools/mining_tool",
  "minecraft:logs", "minecraft:planks", "minecraft:wool", "minecraft:saplings", "minecraft:leaves",
  "minecraft:stairs", "minecraft:slabs", "minecraft:walls", "minecraft:doors", "minecraft:trapdoors",
  "minecraft:buttons", "minecraft:rails", "minecraft:coals", "minecraft:arrows", "minecraft:boats",
  "minecraft:candles", "minecraft:beds", "minecraft:banners", "minecraft:terracotta", "minecraft:flowers",
  "minecraft:dirt", "minecraft:sand", "minecraft:stone_bricks", "minecraft:wool_carpets",
  "minecraft:signs", "minecraft:fishes", "minecraft:music_discs", "minecraft:decorated_pot_sherds",
  "minecraft:trim_templates", "minecraft:bookshelf_books", "minecraft:anvil",
  -- Curios slot tags: the CURIOS tab lists what fits an empty slot
  "curios:ring", "curios:charm", "curios:necklace", "curios:belt", "curios:bracelet",
  "curios:hands", "curios:head", "curios:back", "curios:body", "curios:feet", "curios:curio",
}

-- the Curios slot types an item fits, from its tags: { ring = true, ... }
function curioSlotsOf(it)
  local out
  if type(it.tags) ~= "table" then return nil end
  for k, v in pairs(it.tags) do
    local tg = type(v) == "string" and v or (type(k) == "string" and k or nil)
    local slot = tg and tg:gsub("^#", ""):match("^curios:(.+)$")
    if slot then
      out = out or {}
      out[slot] = true
    end
  end
  return out
end

-- what kind of storage a cell holds (AE2 key type ids -> readable)
function cellTypeLabel(t)
  local s = tostring(t or "?"):lower()
  if s:find("flux", 1, true) or s:find(":fe", 1, true) or s:find("energy", 1, true) then return "Flux (FE)" end
  if s:find("chemical", 1, true) or s:find("appmek", 1, true) or s:find("mekanism", 1, true) then return "Chemicals" end
  if s:find("source", 1, true) then return "Source" end
  if s:find("mana", 1, true) then return "Mana" end
  if s:find("ae2:f", 1, true) or s:find("fluid", 1, true) then return "Fluids" end
  if s:find("ae2:i", 1, true) or s:find("item", 1, true) then return "Items" end
  return tostring(t)
end

-- a fluid / chemical list in the same shape as the item list
local function normList(raw)
  local list, by = {}, {}
  for _, it in pairs(type(raw) == "table" and raw or {}) do
    if type(it) == "table" and it.name then
      local cnt = tonumber(it.count or it.amount) or 0
      local cur = by[it.name]
      if cur then
        cur.count = cur.count + cnt
      else
        cur = { name = it.name, count = cnt, craftable = it.isCraftable and true or false,
                display = cleanName(it.displayName or prettify(it.name)) }
        by[it.name] = cur
        list[#list + 1] = cur
      end
    end
  end
  return list, by
end

-- item names known from anywhere (seen on this page, craftable, carried,
-- mapped, added by hand) - looked up one by one while the full list is broken
local NAMES_FILE = "me_names.dat"
ME_NAMES = {}
do
  if fs.exists(NAMES_FILE) then
    local h = fs.open(NAMES_FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then for _, n in ipairs(t) do ME_NAMES[n] = true end end
  end
end
local namesDirty, namesSavedAt = false, -100
-- remember an item name seen in the network (for the partial view)
function meRememberName(n)
  if type(n) == "string" and n:find(":", 1, true) and not ME_NAMES[n] then
    ME_NAMES[n] = true
    namesDirty = true
  end
end
-- save the remembered item names (at most once a minute unless forced)
local function saveNames(force)
  if not namesDirty or (not force and os.clock() - namesSavedAt < 60) then return end
  local list = {}
  for n in pairs(ME_NAMES) do list[#list + 1] = n end
  table.sort(list)
  local okS, text = pcall(textutils.serialize, list)
  if okS and saveFileSafe(NAMES_FILE, text) then namesDirty, namesSavedAt = false, os.clock() end
end
-- 'me add <id>': look this item up in the partial view from now on
function meAddName(n) meRememberName(n) saveNames(true) state.meNameCache = nil end

-- read the whole ME / RS network (items, fluids, energy, storage, crafting)
function fetchME()
  local me = { kind = bridgeKind, items = {}, tasks = {}, byName = {},
               energy = {}, storage = {}, fstorage = {}, cstorage = {},
               fluids = {}, byNameF = {}, chemicals = {}, byNameC = {}, cellTypes = {} }
  state.meVersion = (state.meVersion or 0) + 1

  local function get(fn, ...)
    local ok, r = callx(bridge, fn, ...)
    if ok then return r end
  end

  -- every question is asked at the same time
  local ok, items, e
  local craftables, tasks
  local fluidsRaw, chemRaw, cellsRaw, craftFluidsRaw
  me.hasChem = type(bridge.getChemicals) == "function"
  local fns = {
    function() ok, items, e = callx(bridge, "getItems", {}) end,
    function() me.connected = get("isConnected") end,
    function() me.online = get("isOnline") end,
    function() me.energy.stored = get("getStoredEnergy") end,
    function() me.energy.cap = get("getEnergyCapacity") end,
    function() me.energy.usage = get("getEnergyUsage") end,
    -- newer Advanced Peripherals renamed some functions: try the new name, then the old
    function() me.energy.inj = get("getAverageEnergyInput") or get("getAvgPowerInjection") end,
    function() me.storage.used = get("getUsedItemStorage") end,
    function() me.storage.max = get("getTotalItemStorage") or get("getMaxItemStorage") end,
    function() tasks = get("getCraftingTasks") end,
    -- the chests next to the Inventory Manager (needed for taking / sending items)
    function()
      -- checked every 15 s (chests rarely move; each check costs two calls)
      if state.meChests and os.clock() - (state.meChestsT or -100) < 15 then
        me.chests = state.meChests
        me.bufOk = me.chests.give and me.chests.give.ok
        return
      end
      state.meChestsT = os.clock()
      me.chests = {}
      state.meChests = me.chests
      if inv and inv.getItemsChest then
        for _, w in ipairs({ "give", "take" }) do
          local dir = chestManagerDir(w)
          local okB, r = pcall(inv.getItemsChest, dir)
          me.chests[w] = { dir = dir, ok = okB and type(r) == "table", items = okB and r or nil }
        end
        me.bufOk = me.chests.give.ok
      end
    end,
    -- fluids, chemicals (Applied Mekanistics) and the cells in the drives
    function() fluidsRaw = get("getFluids", {}) end,
    function() craftFluidsRaw = get("getCraftableFluids", {}) end,
    function()      -- the player's storage items (for "In your containers")
      if inv and (not state.storage or os.clock() - ((state.t and state.t.storage) or -100) > 10) then
        pcall(refreshStorage)
      end
    end,
    function()
      local b, err = fluidBuffer()
      me.fluidBuf, me.fluidBufErr = b, err
      if b then
        local okT, t = pcall(peripheral.call, b, "tanks")
        me.fluidBufTanks = okT and type(t) == "table" and t or {}
      end
    end,
    function() me.fstorage.used = get("getUsedFluidStorage") end,
    function() me.fstorage.max = get("getTotalFluidStorage") end,
    function() cellsRaw = get("getCells") end,
  }
  if me.hasChem then
    fns[#fns + 1] = function() chemRaw = get("getChemicals", {}) end
    fns[#fns + 1] = function() me.cstorage.used = get("getUsedChemicalStorage") end
    fns[#fns + 1] = function() me.cstorage.max = get("getTotalChemicalStorage") end
  end
  if state.meCraftOnly then
    fns[#fns + 1] = function() craftables = get("getCraftableItems", {}) end
  end
  parallel.waitForAll(table.unpack(fns))
  if me.chests then pcall(autoFindChests, me.chests) end

  if me.connected == false then
    me.err = "The bridge is not connected to a storage network."
    return me
  end

  if not ok and isDistError(items) then
    -- Some modded item in the network breaks the full listing. Read it tag by
    -- tag (at most every 30 s), plus the items the player carries.
    me.partial = true
    local cache = state.meTagCache
    if not cache or os.clock() - cache.t > 30 then
      -- the common tags, plus every tag learnt from items already listed
      -- (mod-specific ones too) - each sweep sees a bit more of the network
      local tags, inList = {}, {}
      for _, t in ipairs(ME_TAGS) do tags[#tags + 1] = t inList[t] = true end
      for t in pairs(state.meLearntTags or {}) do
        if not inList[t] and #tags < 400 then tags[#tags + 1] = t inList[t] = true end
      end
      local res = pmap(tags, function(tag)
        local okT, list = callx(bridge, "getItems", { name = "#" .. tag })
        if okT and type(list) == "table" then return list end
        if not okT and isDistError(list) then return "BROKEN" end
        return {}
      end)
      cache = { t = os.clock(), items = {}, broken = {} }
      local seenKey = {}
      for i, list in ipairs(res) do
        if list == "BROKEN" then
          cache.broken[#cache.broken + 1] = "#" .. tags[i]
        elseif type(list) == "table" then
          for _, it in ipairs(list) do
            if type(it) == "table" and it.name then
              local k = tostring(it.name) .. "|" .. (type(it.fingerprint) == "string" and it.fingerprint or "")
              if not seenKey[k] then seenKey[k] = true cache.items[#cache.items + 1] = it end
              -- learn this item's tags for the next sweep
              if type(it.tags) == "table" then
                state.meLearntTags = state.meLearntTags or {}
                for kk, vv in pairs(it.tags) do
                  local tg = type(vv) == "string" and vv or (type(kk) == "string" and kk or nil)
                  if tg then
                    tg = tg:gsub("^#", "")
                    if tg:find(":", 1, true) then state.meLearntTags[tg] = true end
                  end
                end
              end
            end
          end
        end
      end
      state.meTagCache = cache
    end
    me.brokenTags = cache.broken
    local tagItems, seen = {}, {}
    for _, it in ipairs(cache.items) do tagItems[#tagItems + 1] = it seen[it.name] = true end
    local names = {}
    local function addName(n)
      if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    for _, it in pairs(state.slots or {}) do addName(it.name) end
    for _, it in pairs(state.equip or {}) do addName(it.name) end
    local carried = #names
    local res = pmap(names, function(n)
      local okI, it = callx(bridge, "getItem", { name = n })
      if okI and type(it) == "table" and it.name then return it end
      local okC, craft = callx(bridge, "isCraftable", { name = n })
      return { name = n, count = 0, isCraftable = okC and craft and true or false }
    end)
    items = tagItems
    for i = 1, carried do if res[i] then items[#items + 1] = res[i] end end
    for _, it in ipairs(tagItems) do meRememberName(it.name) end

    -- every other known name, looked up one by one (each lookup converts only
    -- that item, so it works while the full list is broken). At most 250
    -- per minute, rotating; the results are kept until the next round.
    local nc = state.meNameCache
    if not nc or os.clock() - nc.t > 60 then
      local pool = {}
      local function addPool(n) if type(n) == "string" and n:find(":", 1, true) and not seen[n] then seen[n] = true pool[#pool + 1] = n end end
      for _, c in pairs(type(craftables) == "table" and craftables or {}) do if type(c) == "table" then addPool(c.name) end end
      for n in pairs(ME_NAMES) do addPool(n) end
      for _, n in ipairs(MAP and MAP.names or {}) do addPool(n) end
      table.sort(pool)
      local start = ((nc and nc.next) or 1)
      if start > #pool then start = 1 end
      local batch = {}
      for i = start, math.min(#pool, start + 249) do batch[#batch + 1] = pool[i] end
      local found, broken = (nc and nc.found) or {}, (nc and nc.broken) or nil
      local r2 = pmap(batch, function(n)
        local okI, it = callx(bridge, "getItem", { name = n })
        if okI and type(it) == "table" and it.name and (tonumber(it.count) or 0) > 0 then return it end
        if not okI and isDistError(it) then return "BROKEN" end
        return false
      end)
      for i, n in ipairs(batch) do
        if r2[i] == "BROKEN" then broken = n
        elseif type(r2[i]) == "table" then found[n] = r2[i] meRememberName(n)
        else found[n] = nil end
      end
      nc = { t = os.clock(), found = found, broken = broken, next = start + #batch }
      state.meNameCache = nc
    end
    local listed = {}
    for _, it in ipairs(items) do listed[it.name] = true end
    for n, it in pairs(nc.found) do
      if not listed[n] then items[#items + 1] = it listed[n] = true end   -- never twice
    end
    me.brokenName = nc.broken
    saveNames(false)
    me.partialCount = #items
  elseif not ok then
    me.err = tostring(items)
    return me
  elseif type(items) ~= "table" then
    me.err = tostring(e or "getItems() returned nothing")
    return me
  end

  local function add(it, craftable)
    local cur = me.byName[it.name]
    local cnt = tonumber(it.count or it.amount) or 0
    if cur then
      cur.count = cur.count + cnt
      cur.craftable = cur.craftable or craftable
    else
      cur = { name = it.name, count = cnt, craftable = craftable,
              display = cleanName(it.displayName or prettify(it.name)),
              curios = curioSlotsOf(it) }
      me.byName[it.name] = cur
      me.items[#me.items + 1] = cur
    end
  end

  for _, it in pairs(items) do
    if type(it) == "table" and it.name then
      add(it, it.isCraftable and true or false)
    end
  end

  if state.meCraftOnly and type(craftables) == "table" then
    for _, it in pairs(craftables) do
      if type(it) == "table" and it.name then
        local cur = me.byName[it.name]
        if cur then cur.craftable = true
        else add({ name = it.name, count = 0, displayName = it.displayName }, true) end
      end
    end
  end

  local total = 0
  for _, it in ipairs(me.items) do total = total + it.count end
  me.total, me.types = total, #me.items

  me.fluids, me.byNameF = normList(fluidsRaw)
  -- craftable fluids: marked [C]; those not in the network right now are listed with 0
  for _, f in pairs(type(craftFluidsRaw) == "table" and craftFluidsRaw or {}) do
    if type(f) == "table" and f.name then
      local cur = me.byNameF[f.name]
      if cur then
        cur.craftable = true
      else
        cur = { name = f.name, count = 0, craftable = true,
                display = cleanName(f.displayName or prettify(f.name)) }
        me.byNameF[f.name] = cur
        me.fluids[#me.fluids + 1] = cur
      end
    end
  end
  me.chemicals, me.byNameC = normList(chemRaw)
  -- the cells, per kind of storage (items, fluids, chemicals, Applied Flux ...)
  if type(cellsRaw) == "table" then
    local byT = {}
    for _, c in pairs(cellsRaw) do
      if type(c) == "table" then
        local label = cellTypeLabel(c.type)
        local e2 = byT[label]
        if not e2 then
          e2 = { label = label, n = 0, used = 0, total = 0 }
          byT[label] = e2
          me.cellTypes[#me.cellTypes + 1] = e2
        end
        e2.n = e2.n + 1
        e2.used = e2.used + (tonumber(c.usedBytes) or 0)
        e2.total = e2.total + (tonumber(c.bytes) or 0)
      end
    end
    table.sort(me.cellTypes, function(a, b) return a.label < b.label end)
  end

  if type(tasks) == "table" then
    for _, t in pairs(tasks) do
      if type(t) == "table" then
        local res = type(t.resource) == "table" and t.resource or {}
        me.tasks[#me.tasks + 1] = {
          name = cleanName(res.displayName or prettify(tostring(res.name or "unknown"))),
          quantity = tonumber(t.quantity) or 0,
          crafted = tonumber(t.crafted) or 0,
          completion = tonumber(t.completion) or 0,
        }
      end
    end
  end
  return me
end

-- Where the buffer chest is, as each block should address it:
-- a network name (wired modems), or a direction like "@up" (touching).
-- Advanced Peripherals wants plain directions ("up", "east", "left" ...): a
-- leading "@" (old settings) is removed. The ME Bridge may also use the chest's
-- network name; the Inventory Manager can ONLY use a direction (the chest must
-- touch it).
local function dirOf(d, default) return (tostring(d or default):gsub("^@", "")) end
-- how the ME Bridge reaches the buffer chest
function bufBridge() return CONFIG.me.buffer or dirOf(CONFIG.me.bufferFromBridge, "up") end
-- how the Inventory Manager reaches the buffer chest
function bufManager() return dirOf(CONFIG.me.bufferFromManager, "east") end

-- Two chests: "give" (items going TO the player) and "take" (items coming FROM
-- the player). Without the two-chest settings both are the single buffer chest.
function chestManagerDir(which)
  local d = (which == "give") and CONFIG.me.giveFromManager or CONFIG.me.takeFromManager
  return dirOf(d or CONFIG.me.bufferFromManager, "east")
end
-- how the ME Bridge reaches the give / take chest
function chestBridge(which)
  local manual = (which == "give") and CONFIG.me.giveChest or CONFIG.me.takeChest
  if manual then return dirOf(manual) end
  if state.meAuto and state.meAuto[which] then return state.meAuto[which] end
  return bufBridge()
end

-- find the chests on the network: the same contents as the manager sees in
-- that direction (needs at least one item in each chest, and different contents)
local function chestSig(list)
  local parts = {}
  for _, it in pairs(type(list) == "table" and list or {}) do
    if type(it) == "table" and it.name then parts[#parts + 1] = it.name .. ":" .. (tonumber(it.count) or 0) end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end
-- work out which chest is which for the bridge, by their contents
function autoFindChests(chests)
  state.meAuto = state.meAuto or {}
  local want = {}
  for _, w in ipairs({ "give", "take" }) do
    local manual = (w == "give") and CONFIG.me.giveChest or CONFIG.me.takeChest
    local c = chests[w]
    if not manual and not state.meAuto[w] and c and c.ok then
      local s = chestSig(c.items)
      if s ~= "" then want[w] = s end
    end
  end
  if not next(want) then return end
  if want.give and want.take and want.give == want.take and chestManagerDir("give") ~= chestManagerDir("take") then
    return                                         -- same contents: cannot tell them apart
  end
  if os.clock() - (state.meAutoAt or -100) < 30 then return end
  state.meAutoAt = os.clock()
  local found = {}
  for _, n in ipairs(inventoriesOnNetwork()) do
    local okL, l = pcall(peripheral.call, n, "list")
    if okL then
      local s = chestSig(l)
      for w, sg in pairs(want) do
        if s == sg then found[w] = found[w] or {} found[w][#found[w] + 1] = n end
      end
    end
  end
  for w, list in pairs(found) do
    if #list == 1 then state.meAuto[w] = list[1] end
  end
end

-- chests / barrels / anything with an inventory on the network
function inventoriesOnNetwork()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    local ok, is = pcall(peripheral.hasType, n, "inventory")
    if ok and is then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

-- returns an error text if a configured buffer chest is missing
function bufferProblem()
  local b = CONFIG.me.buffer
  if b and not peripheral.isPresent(b) then
    local list = inventoriesOnNetwork()
    return "Buffer chest '" .. b .. "' is not on the network. Inventories seen: " ..
           (#list > 0 and table.concat(list, ", ") or "none")
  end
end

-- bring anything of this item still sitting in the buffer chest back into ME
function flushToME(name, chunk)
  for _ = 1, 8 do
    local ok, r = transfer(bridge, ME_IN, chestBridge("give"),
                        { name = name, count = chunk })
    local n = ok and numOf(r) or nil
    if not n or n <= 0 then break end
  end
end

-- ME -> player.  returns moved, errorText
-- ===== items the program put into a buffer and could not deliver yet =====
-- (e.g. your inventory AND the ME network were full). Only these exact
-- amounts are ever moved again - never anything else in the buffer (it may
-- be a storage that holds your own items too). Retried every 30 s.
local OWED_FILE = "me_owed.dat"
OWED = {}
do
  if fs.exists(OWED_FILE) then
    local h = fs.open(OWED_FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then OWED = t end
  end
end
-- save the OWED list
local function saveOwed()
  local okS, text = pcall(textutils.serialize, OWED)
  if okS then saveFileSafe(OWED_FILE, text) end
end
-- save the OWED list (for other files)
function saveOwedNow() saveOwed() end
-- remember n of an item left in a buffer that still has to go `to` ME or the player
local function owe(name, n, to, chest)
  if n <= 0 then return end
  for _, o in ipairs(OWED) do
    if o.name == name and o.to == to and o.chest == chest then o.count = o.count + n saveOwed() return end
  end
  OWED[#OWED + 1] = { name = name, count = n, to = to, chest = chest }
  saveOwed()
end

-- move exactly n of an item from a buffer into the ME network; returns how many
local function bufferToME(name, n, chest)
  local done = 0
  for _ = 1, 16 do
    if done >= n then break end
    local ok, r = transfer(bridge, ME_IN, chestBridge(chest), { name = name, count = n - done })
    local m = ok and numOf(r) or 0
    if not m or m <= 0 then break end
    done = done + m
  end
  return done
end
-- move exactly n of an item from a buffer to the player; returns how many
local function bufferToPlayer(name, n, chest)
  local done = 0
  for _ = 1, 16 do
    if done >= n then break end
    local ok, r = transfer(inv, INV_TO_PLAYER, chestManagerDir(chest), { name = name, count = n - done })
    local m = ok and tonumber(r) or 0
    if m <= 0 then break end
    done = done + m
  end
  return done
end

-- try to deliver the waiting items (every 30 s, and before each transfer)
function settleOwed()
  if #OWED == 0 or not bridge then return end
  local changed = false
  for i = #OWED, 1, -1 do
    local o = OWED[i]
    local m = 0
    if o.fluid then m = moveFluid("store", o.name, o.count)
    elseif o.to == "me" then m = bufferToME(o.name, o.count, o.chest)
    elseif inv then m = bufferToPlayer(o.name, o.count, o.chest) end
    if m > 0 then
      o.count = o.count - m
      changed = true
      if o.count <= 0 then table.remove(OWED, i) end
    end
  end
  if changed then saveOwed() end
end
-- how many items are still owed, and in how many entries
function owedCount()
  local n = 0
  for _, o in ipairs(OWED) do n = n + o.count end
  return n, #OWED
end

-- ME -> player: exactly `count` (in chunks); returns moved, error
function takeFromME(name, count)
  pcall(settleOwed)
  local remaining, total = count, 0
  local chunk = CONFIG.me.chunk
  for _ = 1, 60 do
    local step = math.min(remaining, chunk)
    local ok, r, e = transfer(bridge, ME_OUT, chestBridge("give"), { name = name, count = step })
    if not ok then return total, tostring(r) end
    if r == nil then return total, tostring(e or "export failed") end
    local exported = numOf(r) or 0
    if exported <= 0 then break end                    -- the network has no more

    -- exactly what was exported goes to the player ...
    local added = bufferToPlayer(name, exported, "give")
    total = total + added
    local left = exported - added
    if left > 0 then
      -- ... the rest (inventory full / not accepted) goes back to the network
      local back = bufferToME(name, left, "give")
      if back < left then
        owe(name, left - back, "me", "give")
        return total, (left - back) .. " could not go back to the network - kept in the buffer, retried automatically"
      end
      break
    end
    remaining = remaining - exported
    if remaining <= 0 or exported < step then break end
  end
  return total
end
-- player -> ME: exactly `count` (in chunks); returns sent, error
function sendToME(name, count)
  pcall(settleOwed)
  local remaining, sent = count, 0
  local chunk = CONFIG.me.chunk
  for _ = 1, 60 do
    local step = math.min(remaining, chunk)
    local ok, r = transfer(inv, INV_FROM_PLAYER, chestManagerDir("take"), { name = name, count = step })
    if not ok then return sent, tostring(r) end
    local removed = tonumber(r) or 0
    if removed <= 0 then break end

    local accepted = bufferToME(name, removed, "take")
    sent = sent + accepted
    local refused = removed - accepted
    if refused > 0 then
      -- whatever the network did not accept goes back to the player
      local back = bufferToPlayer(name, refused, "take")
      if back < refused then
        owe(name, refused - back, "player", "take")
        return sent, (refused - back) .. " could not go back to you - kept in the buffer, retried automatically"
      end
      return sent, "the network did not accept " .. refused .. " (full?) - given back to you"
    end
    remaining = remaining - removed
    if remaining <= 0 then break end
  end
  return sent
end

-- ===== Curios: worn items <-> ME network / inventory (through the buffer chest) =====
-- exportCuriosItem / importCuriosItem take different arguments in different
-- Advanced Peripherals versions, so the program asks the function itself:
-- - a call with too few arguments fails with "bad argument #n (TYPE expected,
--   got no value)": that gives the TYPE of every argument;
-- - every text gets its own marker (__p1__, __p2__ ...); the error names the
--   marker it did not like: "Curios slot '__p1__' does not exist" -> argument
--   1 is the SLOT TYPE (it then gets a real one and the function is asked
--   again), "Target '__p2__' does not exist" -> argument 2 is the CHEST.
-- The chest is always a marker while asking, so asking never moves anything.
CURIO_SIG = {}          -- [function name] = { types = {...}, roles = { [n] = "slot"/"target"/"item" } }
local unpack = table.unpack or unpack
local PLACEHOLDER = { string = "__probe__", number = 1, table = {}, boolean = false }

-- which argument a "... '<value>' does not exist" error is about, and its role
local function roleFromError(err, args)
  local low = tostring(err):lower()
  for k, v in pairs(args) do
    if type(v) == "string" and v ~= "" and tostring(err):find("'" .. v .. "'", 1, true) then
      if low:find("slot", 1, true) or low:find("curio", 1, true) then return k, "slot" end
      if low:find("target", 1, true) or low:find("inventory", 1, true) or low:find("peripheral", 1, true) then
        return k, "target"
      end
      return k, "item"
    end
  end
end

-- the argument types and roles of an Inventory Manager curios function
-- (slotType = a real slot type of the player, used while asking)
function curioSignature(fn, slotType)
  if CURIO_SIG[fn] then return CURIO_SIG[fn] end
  if type(inv[fn]) ~= "function" then return nil, "this Inventory Manager has no " .. fn end
  local types, roles, args = {}, {}, {}
  for _ = 1, 12 do
    local ok, err = pcall(inv[fn], unpack(args, 1, #types))
    if ok then break end
    local n, ty = tostring(err):match("bad argument #(%d+) %((%a+) expected")
    n = tonumber(n)
    if n and PLACEHOLDER[ty] then
      for k = #types + 1, n do                      -- (missing ones in between: text)
        types[k] = (k == n) and ty or "string"
        args[k] = (types[k] == "string") and ("__p" .. k .. "__") or PLACEHOLDER[types[k]]
      end
      if types[n] ~= ty then
        types[n] = ty
        args[n] = (ty == "string") and ("__p" .. n .. "__") or PLACEHOLDER[ty]
      end
    else
      local k, role = roleFromError(err, args)
      if not k or roles[k] then break end
      roles[k] = role
      if role ~= "slot" then break end              -- chest or item found: stop asking
      args[k] = slotType                            -- a real slot type, ask again
    end
  end
  if #types == 0 then return nil, "could not find out how " .. fn .. " is called" end
  -- OPTIONAL arguments (the function works without them, so the questions
  -- above never see them): an extra argument of a wrong type (true) is refused
  -- with the type the function wants there - before it does anything (the
  -- chest is still a marker, so nothing moves). A number becomes the slot
  -- number, a table the item filter, a text the item name.
  for _ = 1, 3 do
    local n = #types + 1
    local a2 = {}
    for k = 1, #types do a2[k] = args[k] end
    a2[n] = true
    local ok, err = pcall(inv[fn], unpack(a2, 1, n))
    local m, ty = tostring(err):match("bad argument #(%d+) %((%a+) expected, got boolean")
    if ok or tonumber(m) ~= n or not PLACEHOLDER[ty] or ty == "boolean" then break end
    types[n] = ty
    args[n] = (ty == "string") and ("__p" .. n .. "__") or PLACEHOLDER[ty]
  end
  CURIO_SIG[fn] = { types = types, roles = roles }
  local NAMES, parts = { slot = "slot type", target = "chest", item = "item name" }, {}
  for k, ty in ipairs(types) do parts[k] = (roles[k] and NAMES[roles[k]]) or ty end
  table.insert(state.noteLog, 1, { title = "Curios", col = C.label, when = realTime("%d.%m %H:%M"),
    msg = fn .. " wants (" .. table.concat(parts, ", ") .. ")" })
  return CURIO_SIG[fn]
end

-- the arguments for a real call: texts by role (chest, slot type, item name),
-- numbers: the slot number, then the count; a table: the item filter
local function curioArgs(sig, target, slotType, slotNo, name, count)
  local have, args, nNum = {}, {}, 0
  for _, r in pairs(sig.roles) do have[r] = true end
  for k, ty in ipairs(sig.types) do
    if ty == "string" then
      local r = sig.roles[k]
      if not r then                                 -- not seen yet: the missing role (a guess)
        r = (not have.slot and "slot") or (not have.target and "target") or "item"
        sig.roles[k], have[r] = r, true
        sig.guessed = sig.guessed or {}
        sig.guessed[k] = true
      end
      args[k] = (r == "target" and target) or (r == "slot" and slotType) or name
    elseif ty == "number" then
      nNum = nNum + 1
      args[k] = (nNum == 1) and slotNo or count
    elseif ty == "table" then
      args[k] = { name = name, count = count }
    else
      args[k] = PLACEHOLDER[ty]
    end
  end
  return args
end

-- a real call failed with "... '<value>' does not exist": that value is in the
-- wrong place - swap the roles of the two arguments. true if something changed
local function fixRoles(sig, args, err)
  local k, role = roleFromError(err, args)
  if not k or sig.roles[k] == role then return false end
  for j, r in pairs(sig.roles) do
    if r == role and j ~= k then sig.roles[j] = sig.roles[k] end
  end
  sig.roles[k] = role
  return true
end

-- what is worn where: [slot type .. "|" .. key] = item name (nil if unreadable)
local function curiosNow()
  local ok, list = pcall(inv.listCurios)
  if not ok or type(list) ~= "table" then return nil end
  local out = {}
  for t, items in pairs(list) do
    if type(items) == "table" then
      for k, it in pairs(items) do
        if type(it) == "table" and it.name then out[t .. "|" .. tostring(k)] = it.name end
      end
    end
  end
  return out
end

-- call fn with the learnt arguments; tries the slot number as listed and one
-- lower/higher (versions count slots from 0 or 1) and both orders of the texts,
-- until the wanted change shows in listCurios. check(before, after) -> true
-- when the right thing happened. Returns how many moved, error
local SLOT_SHIFT      -- the slot-number shift that worked (learnt from exact matches only)
-- one line in the EVENTS list (no box): what a curios call sent and what really changed
local function curioLog(fn, args, n, target, ok, r, before, after)
  local shown = {}
  for k = 1, n do
    local v = args[k]
    if v == target then shown[k] = "<chest>"
    elseif type(v) == "string" then shown[k] = '"' .. v .. '"'
    elseif type(v) == "table" then shown[k] = "{" .. tostring(v.name) .. "}"
    else shown[k] = tostring(v) end
  end
  local changed = {}
  if before and after then
    for k, nm in pairs(before) do if after[k] ~= nm then changed[#changed + 1] = "off " .. prettify(nm) .. " (" .. k .. ")" end end
    for k, nm in pairs(after) do if before[k] ~= nm then changed[#changed + 1] = "on " .. prettify(nm) .. " (" .. k .. ")" end end
  end
  local res = ok and ("-> " .. tostring(type(r) == "table" and (r.count or "table") or r)) or ("error: " .. cleanErr(r))
  table.insert(state.noteLog, 1, { title = "Curios call", col = C.label, when = realTime("%d.%m %H:%M"),
    msg = fn .. "(" .. table.concat(shown, ", ") .. ") " .. res ..
          (#changed > 0 and ("; " .. table.concat(changed, ", ")) or (ok and "; nothing changed" or "")) })
  while #state.noteLog > noteSetting("keep") do table.remove(state.noteLog) end
end

-- can the function be told WHICH item (a filter table or an item-name text)?
local function canChooseItem(sig)
  for k, ty in ipairs(sig.types) do
    if ty == "table" or (ty == "string" and sig.roles[k] == "item") then return true end
  end
  return false
end

-- does the chest hold nothing but `name`? (read with the normal inventory
-- functions; nil = cannot be read)
local function chestHoldsOnly(chestName, name)
  if not (peripheral.isPresent(chestName) and peripheral.hasType(chestName, "inventory")) then return nil end
  local ok, list = pcall(peripheral.call, chestName, "list")
  if not ok or type(list) ~= "table" then return nil end
  for _, it in pairs(list) do
    if type(it) == "table" and it.name and it.name ~= name then return false end
  end
  return true
end

-- how many items are worn in a slot type (now = curiosNow())
local function wornIn(now, slotType)
  local n = 0
  for k in pairs(now or {}) do if k:sub(1, #slotType + 1) == slotType .. "|" then n = n + 1 end end
  return n
end

-- can the function be told which SLOT (a number) or which ITEM?
local function canChoose(sig)
  for _, ty in ipairs(sig.types) do if ty == "number" then return true end end
  return canChooseItem(sig)
end

-- Optional arguments read only AFTER the chest is checked: asked with the
-- real chest, but on a slot type where nothing can move - an EMPTY one for
-- taking off, a FULL one for putting on. An extra argument of a wrong type
-- (true) is then refused with the type wanted there.
local function probeOptional(fn, sig, target)
  if sig.optChecked then return end
  sig.optChecked = true
  local okS, sizes = pcall(inv.getCuriosSizes)
  local now = curiosNow()
  if not okS or type(sizes) ~= "table" or not now then return end
  local pick
  for t, size in pairs(sizes) do
    size = tonumber(size) or 0
    local worn = wornIn(now, t)
    if size > 0 and ((fn == "exportCuriosItem" and worn == 0) or (fn == "importCuriosItem" and worn >= size)) then
      pick = t
      break
    end
  end
  if not pick then return end
  for _ = 1, 3 do
    local args = curioArgs(sig, target, pick, 1, "__probe__", 1)
    local n = #sig.types + 1
    args[n] = true
    local ok, err = pcall(inv[fn], unpack(args, 1, n))
    local m, ty = tostring(err):match("bad argument #(%d+) %((%a+) expected, got boolean")
    if ok or tonumber(m) ~= n or not PLACEHOLDER[ty] or ty == "boolean" then break end
    sig.types[n] = ty
  end
  local parts = {}
  local NAMES = { slot = "slot type", target = "chest", item = "item name" }
  for k, ty in ipairs(sig.types) do parts[k] = (sig.roles[k] and NAMES[sig.roles[k]]) or ty end
  table.insert(state.noteLog, 1, { title = "Curios", col = C.label, when = realTime("%d.%m %H:%M"),
    msg = fn .. " (checked with the real chest on '" .. pick .. "'): (" .. table.concat(parts, ", ") .. ")" })
end

-- items that came off but were not asked for: back on (only if that cannot
-- take a different item from the buffer), else into the inventory by exact
-- name, else kept for later (OWED). Returns a short summary
local function restoreOthers(list, target, slotType)
  local osig = curioSignature("importCuriosItem", slotType)
  local on, toInv, kept = {}, {}, {}
  for _, o in ipairs(list) do
    local done = false
    if osig and (canChooseItem(osig) or chestHoldsOnly(target, o.name) == true) then
      local before = curiosNow()
      local args = curioArgs(osig, target, slotType, o.slotNo, o.name, 1)
      pcall(inv.importCuriosItem, unpack(args, 1, #osig.types))
      local after = curiosNow()
      if before and after then
        for k, n in pairs(after) do if before[k] == nil and n == o.name then done = true end end
      end
    end
    if done then on[#on + 1] = prettify(o.name)
    elseif bufferToPlayer(o.name, 1, "take") > 0 then toInv[#toInv + 1] = prettify(o.name)
    else
      owe(o.name, 1, "player", "take")
      kept[#kept + 1] = prettify(o.name)
    end
  end
  local out = {}
  if #on > 0 then out[#out + 1] = "put back on: " .. table.concat(on, ", ") end
  if #toInv > 0 then out[#out + 1] = "moved to your inventory: " .. table.concat(toInv, ", ") end
  if #kept > 0 then out[#out + 1] = "inventory full, given to you later: " .. table.concat(kept, ", ") end
  return table.concat(out, "; ")
end

-- call a curios function with the learnt arguments and check in listCurios
-- what really happened. Taking off: EVERY item that came off is handled (the
-- wanted one is returned as moved, all others go back - see restoreOthers).
-- Returns how many of `name` moved, and an error / a note
local function curioCall(fn, target, slotType, slotNo, name, count)
  local sig, err = curioSignature(fn, slotType)
  if not sig then return 0, err end
  probeOptional(fn, sig, target)
  -- putting on without saying which item takes ANY fitting item from the chest:
  -- only allowed when the chest holds nothing else (it may hold your own items)
  if fn == "importCuriosItem" and not canChooseItem(sig) and chestHoldsOnly(target, name) ~= true then
    return 0, "this Inventory Manager cannot be told which item to put on, and the buffer holds other items too"
  end
  local function hasNumber()
    for _, ty in ipairs(sig.types) do if ty == "number" then return true end end
    return false
  end
  local first = curiosNow()
  -- taking off without saying which: the function takes EVERY item of that slot type
  if fn == "exportCuriosItem" and (not canChoose(sig) or sig.takesAll) and wornIn(first, slotType) > 1 then
    return 0, "your Inventory Manager takes off ALL " .. prettify(slotType) .. " items at once (" ..
              wornIn(first, slotType) .. " are worn). To take one of them, connect an EMPTY barrel for " ..
              "curios and set CONFIG.me.curiosChest to its network name", "takesall"
  end
  local lastErr
  -- slot numbers counted from 0 or 1: also try one lower / higher - but only
  -- when listCurios can show what really moved (no guessing otherwise)
  local shifts = { SLOT_SHIFT or 0 }
  local function moreShifts()
    if not SLOT_SHIFT and first and hasNumber() and #shifts == 1 then
      shifts[2], shifts[3] = -1, 1
    end
  end
  local roleRetry = false
  local idx = 0
  local wantKey = slotType .. "|" .. tostring(slotNo)
  while idx < #shifts do
    idx = idx + 1
    local sh = shifts[idx]
    local before = curiosNow()
    local args, ok, r
    for _ = 1, 6 do
      args = curioArgs(sig, target, slotType, (tonumber(slotNo) or 1) + sh, name, count)
      ok, r = pcall(inv[fn], unpack(args, 1, #sig.types))
      if not ok then curioLog(fn, args, #sig.types, target, ok, r) end
      if ok then break end
      -- one more argument wanted: learn it; a value in the wrong place: swap
      local n, ty = tostring(r):match("bad argument #(%d+) %((%a+) expected, got no value")
      if tonumber(n) == #sig.types + 1 and PLACEHOLDER[ty] then
        sig.types[#sig.types + 1] = ty
      elseif not fixRoles(sig, args, r) then
        break
      end
    end
    moreShifts()
    if not ok then
      lastErr = cleanErr(r)
    else
      local after = curiosNow()
      curioLog(fn, args, #sig.types, target, ok, r, before, after)
      if not (before and after) then
        -- cannot see what happened: trust the result
        local m = tonumber(numOf(r)) or 0
        if m > 0 then return m end
      elseif fn == "exportCuriosItem" then
        local wantOff = before[wantKey] == name and after[wantKey] == nil
        local others = {}
        for k, nm in pairs(before) do
          if after[k] == nil and not (k == wantKey and wantOff) then
            others[#others + 1] = { name = nm, slotNo = tonumber(k:match("|(.*)$")) }
          end
        end
        local note
        if #others > 0 then
          sig.takesAll = true                         -- it does not take only what it is told
          note = "other items came off too - " .. restoreOthers(others, target, slotType)
        end
        if wantOff then
          if #others == 0 and hasNumber() then SLOT_SHIFT = sh end
          sig.guessed = nil
          return 1, note
        end
        lastErr = note or "nothing came off"
        if #others > 0 then return 0, lastErr end     -- no more tries after a wrong take
      else
        -- putting on: it is on if it appeared anywhere ("exact" in the chosen slot)
        local key = slotType .. "|" .. tostring((tonumber(slotNo) or 1) + sh)
        local exact = after[key] == name and before[key] == nil
        local on = exact
        for k, nm in pairs(after) do if before[k] == nil and nm == name then on = true end end
        if on then
          if exact and hasNumber() then SLOT_SHIFT = sh end
          sig.guessed = nil
          return 1
        end
        lastErr = "it did not go on"
      end
      -- nothing happened and a text's meaning was only guessed: the other guess
      -- (slot type <-> item name), once, from the start
      if sig.guessed and next(sig.guessed) and not roleRetry then
        roleRetry = true
        for k in pairs(sig.guessed) do
          sig.roles[k] = (sig.roles[k] == "slot") and "item" or (sig.roles[k] == "item" and "slot" or sig.roles[k])
        end
        idx = 0
      end
    end
  end
  return 0, lastErr
end

-- ===== the CURIOS CHEST (CONFIG.me.curiosChest): an EMPTY barrel used only
-- for curios moves. Needed when the Inventory Manager can only take off ALL
-- items of a slot type and put on ANY fitting item: in that barrel there are
-- only the player's own curios, so "all" and "any" are safe there.
function curiosChest()
  local c = CONFIG.me.curiosChest
  if c and peripheral.isPresent(c) then return c end
end
-- what is in a chest: [name] = count (nil = cannot be read)
local function chestItems(c)
  local ok, list = pcall(peripheral.call, c, "list")
  if not ok or type(list) ~= "table" then return nil end
  local out = {}
  for _, it in pairs(list) do
    if type(it) == "table" and it.name then out[it.name] = (out[it.name] or 0) + (tonumber(it.count) or 1) end
  end
  return out
end
-- everything in the curios chest goes back on (put on takes ANY fitting item:
-- there are only the player's own curios in it); what does not go on goes to
-- the inventory by exact name. Returns the names that are still left
local function putAllBack(c, slotType)
  local sig = curioSignature("importCuriosItem", slotType)
  for _ = 1, 64 do
    local items = chestItems(c)
    if not items or not next(items) or not sig then break end
    local before = curiosNow()
    local args = curioArgs(sig, c, slotType, 1, (next(items)), 1)
    local ok, r = pcall(inv.importCuriosItem, unpack(args, 1, #sig.types))
    local after = curiosNow()
    curioLog("importCuriosItem", args, #sig.types, c, ok, r, before, after)
    local changed = false
    if before and after then for k in pairs(after) do if not before[k] then changed = true end end end
    if not changed then break end
  end
  local left = {}
  for nm, n in pairs(chestItems(c) or {}) do
    local ok, r = transfer(inv, INV_TO_PLAYER, c, { name = nm, count = n })
    local m = ok and tonumber(numOf(r)) or 0
    if m < n then left[#left + 1] = prettify(nm) end
  end
  return left
end

-- take ONE curio off when the Inventory Manager can only take off all of a
-- slot type: all go into the empty curios chest, the wanted one goes on to
-- dest ("me" or "player"), all others go back on. Returns moved, error/note
function curioTakeOne(name, slotType, dest)
  local c = curiosChest()
  if not c then return 0, "no curios chest: set CONFIG.me.curiosChest to the network name of an EMPTY barrel" end
  local items = chestItems(c)
  if not items then return 0, "the curios chest " .. c .. " cannot be read" end
  if next(items) then return 0, "the curios chest " .. c .. " is not empty - empty it first" end
  local sig, err = curioSignature("exportCuriosItem", slotType)
  if not sig then return 0, err end
  local before = curiosNow()
  local args = curioArgs(sig, c, slotType, 64, name, 64)       -- numbers here: as many as possible
  local ok, r = pcall(inv.exportCuriosItem, unpack(args, 1, #sig.types))
  curioLog("exportCuriosItem", args, #sig.types, c, ok, r, before, curiosNow())
  items = chestItems(c) or {}
  local moved = 0
  if ok and (items[name] or 0) > 0 then
    local ok2, r2
    if dest == "me" then ok2, r2 = transfer(bridge, ME_IN, c, { name = name, count = 1 })
    else ok2, r2 = transfer(inv, INV_TO_PLAYER, c, { name = name, count = 1 }) end
    moved = ok2 and (tonumber(numOf(r2)) or 0) or 0
  end
  local left = putAllBack(c, slotType)
  local note = (#left > 0) and ("still in the curios chest: " .. table.concat(left, ", ")) or nil
  if moved > 0 then return moved, note end
  local why = (not ok) and cleanErr(r) or (((items[name] or 0) > 0) and
              ((dest == "me") and "the network did not accept it" or "your inventory is full") or "it did not come off")
  return 0, why .. (note and (" - " .. note) or " - everything else is back on")
end

-- put ONE item from ME on when the Inventory Manager puts on ANY fitting item:
-- it goes alone into the empty curios chest first. Returns moved, error
local function meToCurioViaChest(name, slotType)
  local c = curiosChest()
  local items = c and chestItems(c)
  if not items then return 0, "no curios chest (CONFIG.me.curiosChest)" end
  if next(items) then return 0, "the curios chest " .. c .. " is not empty - empty it first" end
  local ok, r = transfer(bridge, ME_OUT, c, { name = name, count = 1 })
  if not ok or (tonumber(numOf(r)) or 0) < 1 then return 0, ok and "not in the network" or tostring(r) end
  local sig = curioSignature("importCuriosItem", slotType)
  local before = curiosNow()
  local args = curioArgs(sig, c, slotType, 1, name, 1)
  local okI, rI = pcall(inv.importCuriosItem, unpack(args, 1, #sig.types))
  local after = curiosNow()
  curioLog("importCuriosItem", args, #sig.types, c, okI, rI, before, after)
  local on = false
  if before and after then for k, nm in pairs(after) do if before[k] == nil and nm == name then on = true end end end
  if on then return 1 end
  -- not on: back to the network
  transfer(bridge, ME_IN, c, { name = name, count = 1 })
  return 0, okI and "no free slot it fits" or cleanErr(rI)
end

-- the worn curio in slot `slotNo` of `slotType` -> the "take" chest; returns how many, error/note
local function curioOut(name, count, slotType, slotNo)
  return curioCall("exportCuriosItem", chestManagerDir("take"), slotType, slotNo, name, count)
end
-- the chest -> a Curios slot (`slotNo` of `slotType`, if the function lets us
-- choose); returns how many, error
local function curioIn(name, count, chest, slotType, slotNo)
  return curioCall("importCuriosItem", chestManagerDir(chest), slotType, slotNo, name, count)
end

-- 'curios probe' on the computer: what the two functions want (nothing moves)
function curiosProbe(say)
  if not inv then say("No Inventory Manager.") return end
  local slotType = "charm"
  local okS, sizes = pcall(inv.getCuriosSizes)
  if okS and type(sizes) == "table" then for n in pairs(sizes) do slotType = n break end end
  local NAMES = { slot = "slot type", target = "chest", item = "item name" }
  for _, fn in ipairs({ "exportCuriosItem", "importCuriosItem" }) do
    CURIO_SIG[fn] = nil
    local sig, err = curioSignature(fn, slotType)
    if not sig then say(fn .. ": " .. tostring(err))
    else
      local parts = {}
      for k, ty in ipairs(sig.types) do
        parts[k] = ty .. ((ty == "string" and sig.roles[k]) and (" = " .. NAMES[sig.roles[k]]) or "")
      end
      say(fn .. "(" .. table.concat(parts, ", ") .. ")")
    end
  end
end

-- a worn curio -> ME. Whatever the network refuses goes back on (or into
-- the inventory). Returns moved, error
function curioToME(name, count, slotType, slotNo)
  pcall(settleOwed)
  local out, err, code = curioOut(name, count, slotType, slotNo)
  if code == "takesall" and curiosChest() then return curioTakeOne(name, slotType, "me") end
  if out <= 0 then return 0, err or "the item did not come off (not worn?)" end
  local note = err
  local stored = bufferToME(name, out, "take")
  local left = out - stored
  if left > 0 then
    local back = curioIn(name, left, "take", slotType, slotNo)
    if back < left then back = back + bufferToPlayer(name, left - back, "take") end
    if back < left then owe(name, left - back, "player", "take") end
    return stored, "the network did not accept " .. left .. " - given back to you"
  end
  return stored, note
end

-- a worn curio -> the inventory. Returns moved, error
function curioToInventory(name, count, slotType, slotNo)
  pcall(settleOwed)
  local out, err, code = curioOut(name, count, slotType, slotNo)
  if code == "takesall" and curiosChest() then return curioTakeOne(name, slotType, "player") end
  if out <= 0 then return 0, err or "the item did not come off (not worn?)" end
  local note = err
  local moved = bufferToPlayer(name, out, "take")
  local left = out - moved
  if left > 0 then
    local back = curioIn(name, left, "take", slotType, slotNo)
    if back < left then owe(name, left - back, "player", "take") end
    return moved, "your inventory is full - " .. (back >= left and "put back on" or "kept in the buffer, retried")
  end
  return moved, note
end

-- ME -> a Curios slot (the first free one it fits). What does not go on goes
-- back to the network. Returns moved, error
function meToCurio(name, count, slotType, slotNo)
  pcall(settleOwed)
  -- puts on ANY fitting item from the chest: through the empty curios chest
  local isig = curioSignature("importCuriosItem", slotType)
  if isig and not canChooseItem(isig) and curiosChest() then return meToCurioViaChest(name, slotType) end
  local ok, r, e = transfer(bridge, ME_OUT, chestBridge("give"), { name = name, count = count })
  if not ok then return 0, tostring(r) end
  local exported = numOf(r) or 0
  if exported <= 0 then return 0, tostring(e or "not in the network") end
  local on, err = curioIn(name, exported, "give", slotType, slotNo)
  local left = exported - on
  if left > 0 then
    local back = bufferToME(name, left, "give")
    if back < left then owe(name, left - back, "me", "give") end
    return on, (err or "no free slot it fits") .. " - " .. left .. " back to the network"
  end
  return on
end

-- ===== fluids: between the ME network and a fluid storage on the network =====
-- CONFIG.me.fluidBuffer (network name), else the item buffer if it also holds
-- fluids, else the only fluid storage on the network
function fluidBuffer()
  if CONFIG.me.fluidBuffer then return CONFIG.me.fluidBuffer end
  local function isFluid(n)
    local ok, t = pcall(peripheral.hasType, n, "fluid_storage")
    return ok and t
  end
  if CONFIG.me.buffer and isFluid(CONFIG.me.buffer) then return CONFIG.me.buffer end
  local list = {}
  for _, n in ipairs(peripheral.getNames()) do
    local okT, ty = pcall(peripheral.getType, n)
    ty = (okT and type(ty) == "string") and ty or ""
    if isFluid(n) and not ty:find("me_bridge", 1, true) and not ty:find("inventory_manager", 1, true) then
      list[#list + 1] = n
    end
  end
  table.sort(list)
  if #list == 1 then return list[1] end
  if #list == 0 then return nil, "no fluid storage on the network" end
  return nil, "several fluid storages - set fluidBuffer in base_config.lua (me): " .. table.concat(list, ", ")
end

local FL_OUT, FL_IN = { "exportFluid" }, { "importFluid" }
-- dir "take": ME -> fluid storage; "store": fluid storage -> ME. Returns mB moved.
function moveFluid(dir, name, mb)
  local b, err = fluidBuffer()
  if not b then return 0, err end
  local moved, left = 0, mb
  for _ = 1, 64 do
    local ok, r, e = transfer(bridge, dir == "take" and FL_OUT or FL_IN, b,
                              { name = name, amount = math.min(left, 2147483647) })
    if not ok then return moved, tostring(r) end
    local n = tonumber(r) or 0
    if n <= 0 then return moved, (moved == 0) and tostring(e or "nothing moved") or nil end
    moved, left = moved + n, left - n
    if left <= 0 then break end
  end
  return moved
end

-- ===== fluids into / out of the player's fluid containers (tanks, etc.) =====
-- the containers the STORAGE scan found that hold fluids
local function sameRef(a, b)
  return a and b and a.kind == b.kind and a.raw == b.raw and a.slot == b.slot and a.idx == b.idx
end
-- the owner's fluid containers (from the STORAGE scan)
function playerTanks(onlyRef)
  -- the list is built by the STORAGE tab; fresh if it is old or missing
  if not state.storage or os.clock() - ((state.t and state.t.storage) or -100) > 5 then
    pcall(refreshStorage)
  end
  local out = {}
  for _, s in ipairs(state.storage or {}) do
    if s.isFluid and s.ref and (not onlyRef or sameRef(s.ref, onlyRef)) then out[#out + 1] = s end
  end
  return out
end
-- open a storage item again from its saved reference
local function openRef(ref)
  local ok, w
  if ref.kind == "slot" then ok, w = pcall(inv.wrapStorageItem, ref.raw)
  else ok, w = pcall(inv.wrapCuriosStorageItem, ref.slot, ref.idx) end
  if ok and type(w) == "table" then return w end
end
-- remember fluid left in the buffer that still has to go back to ME
local function oweFluid(name, mb)
  if mb <= 0 then return end
  for _, o in ipairs(OWED) do
    if o.fluid and o.name == name then o.count = o.count + mb saveOwedNow() return end
  end
  OWED[#OWED + 1] = { name = name, count = mb, to = "me", fluid = true }
  saveOwedNow()
end

-- what an opened container may call filling / emptying (versions differ)
local TANK_IN  = { "pullFluid", "importFluid", "insertFluid" }
local TANK_OUT = { "pushFluid", "exportFluid", "extractFluid" }
-- the function names of a wrapped object, as one text
local function fnList(w)
  local fns = {}
  for k, v in pairs(w) do if type(v) == "function" then fns[#fns + 1] = k end end
  table.sort(fns)
  return table.concat(fns, ", ")
end
-- does the object have any of these functions?
local function hasAny(w, names)
  for _, n in ipairs(names) do if type(w[n]) == "function" then return true end end
end
-- fill / empty an opened container: Advanced Peripherals style (a filter
-- table, either order), else ComputerCraft style (target, amount, fluid name)
local function tankCall(w, names, target, fluid, amount)
  local ok, r = transfer(w, names, target, { name = fluid, amount = amount, count = amount })
  if ok and (tonumber(r) or 0) > 0 then return true, r end
  for _, n in ipairs(names) do
    if type(w[n]) == "function" then
      local ok3, r3 = pcall(w[n], target, amount, fluid)
      if ok3 then return true, r3 end
      if not ok then r = r3 end
    end
  end
  return ok, r
end

-- many containers move at most a little per call (often 1 bucket): call
-- again until the amount is moved or it stops taking (max 256 calls)
local function tankLoop(w, names, target, fluid, amount)
  local done, firstErr = 0, nil
  for _ = 1, 256 do
    if done >= amount then break end
    local ok, n = tankCall(w, names, target, fluid, amount - done)
    n = ok and (tonumber(n) or 0) or 0
    if not ok and done == 0 then firstErr = n end
    if n <= 0 then break end
    done = done + n
  end
  return done, firstErr
end

-- ME -> buffer -> the player's containers (exactly what was exported; the
-- rest goes back to the network). Returns mB delivered.
function fluidToPlayer(name, mb, onlyRef)
  local b, err = fluidBuffer()
  if not b then return 0, err end
  local tanks = playerTanks(onlyRef)
  if #tanks == 0 then return 0, "no fluid container (tank) found in your inventory or curios" end
  local exported, e1 = moveFluid("take", name, mb)
  if exported <= 0 then return 0, e1 or "the network has none of it" end
  local left, why = exported, {}
  for _, t in ipairs(tanks) do
    if left <= 0 then break end
    local w = openRef(t.ref)
    local label = t.display or t.name or "container"
    if not w then
      why[#why + 1] = label .. ": could not be opened"
    elseif not hasAny(w, TANK_IN) then
      why[#why + 1] = label .. ": no fill function (offers: " .. fnList(w) .. ")"
    else
      local n, err1 = tankLoop(w, TANK_IN, b, name, left)
      if n > 0 then left = left - n
      elseif err1 then why[#why + 1] = label .. ": " .. tostring(err1)
      else why[#why + 1] = label .. ": took 0 (this fluid not allowed, or full)" end
    end
  end
  if left > 0 then
    local back = moveFluid("store", name, left)
    if back < left then oweFluid(name, left - back) end
    if left == exported then
      return 0, "nothing went in - " .. table.concat(why, "; ")
    end
    return exported - left, "your containers had room for " .. fmtBuckets(exported - left) .. " - the rest went back"
  end
  return exported
end

-- the player's containers -> buffer -> ME. Returns mB stored.
function fluidFromPlayer(name, mb, onlyRef)
  local b, err = fluidBuffer()
  if not b then return 0, err end
  local stored, left = 0, mb
  for _, t in ipairs(playerTanks(onlyRef)) do
    if left <= 0 then break end
    local has = false
    for _, tk in ipairs(t.tanks or {}) do if tk.name == name then has = true end end
    local w = has and openRef(t.ref)
    if w and hasAny(w, TANK_OUT) then
      local n = tankLoop(w, TANK_OUT, b, name, left)
      if n > 0 then
        local inME = moveFluid("store", name, n)
        if inME < n then
          -- the network did not take it all: back into the container, else retried later
          local nb = tankLoop(w, TANK_IN, b, name, n - inME)
          oweFluid(name, n - inME - nb)
          stored = stored + inME
          return stored, "the network did not accept all of it (full?)"
        end
        stored, left = stored + n, left - n
      end
    end
  end
  if stored == 0 then return 0, "none of your containers holds this fluid" end
  return stored
end

-- the functions an opened storage item offers (for the "report" command)
function describeStorageItem(ref)
  local w = ref and openRef(ref)
  return w and fnList(w) or nil
end

-- "BUFFER -> ME": everything in the buffer(s) back into the network - the
-- item buffer(s) (by network name) and the fluid buffer. Returns a summary.
function flushBufferToME()
  local items, fluids, notes, seen = 0, 0, {}, {}
  for _, w in ipairs({ "give", "take" }) do
    local t = chestBridge(w)
    if t and not seen[t] then
      seen[t] = true
      if not tostring(t):find(":", 1, true) then
        notes[#notes + 1] = "the item buffer is reached by side (" .. t .. ") - give it a wired modem to empty it from here"
      else
        local okL, l = pcall(peripheral.call, t, "list")
        if okL and type(l) == "table" then
          local totals = {}
          for _, it in pairs(l) do
            if type(it) == "table" and it.name then totals[it.name] = (totals[it.name] or 0) + (tonumber(it.count) or 0) end
          end
          for name, n in pairs(totals) do
            local moved = 0
            for _ = 1, 32 do
              if moved >= n then break end
              local ok, r = transfer(bridge, ME_IN, t, { name = name, count = n - moved })
              local m = ok and numOf(r) or 0
              if not m or m <= 0 then break end
              moved = moved + m
            end
            items = items + moved
            if moved < n then notes[#notes + 1] = (n - moved) .. "x " .. name .. " not accepted" end
          end
        else
          notes[#notes + 1] = "cannot read " .. t
        end
      end
    end
  end
  local b = fluidBuffer()
  if b then
    local okT, tk = pcall(peripheral.call, b, "tanks")
    for _, f in pairs(okT and type(tk) == "table" and tk or {}) do
      if type(f) == "table" and f.name and (tonumber(f.amount) or 0) > 0 then
        local m = moveFluid("store", f.name, tonumber(f.amount))
        fluids = fluids + m
        if m < tonumber(f.amount) then notes[#notes + 1] = fmtBuckets(f.amount - m) .. " " .. f.name .. " not accepted" end
      end
    end
  end
  -- what was waiting in the buffer has gone with it
  OWED = {}
  saveOwedNow()
  return items, fluids, notes
end

-- console "tanks": the player's fluid containers, their contents and functions
function tankReport(say)
  local list = playerTanks()
  if #list == 0 then
    say("No fluid containers found in your inventory or curios (see the STORAGE tab).")
    return
  end
  local b = fluidBuffer()
  say("Fluid storage used in between: " .. tostring(b or "NONE FOUND"))
  for _, t in ipairs(list) do
    local w = openRef(t.ref)
    local inside = {}
    for _, tk in ipairs(t.tanks or {}) do inside[#inside + 1] = tostring(tk.name) .. " " .. fmtBuckets(tk.amount) end
    say((t.display or t.name or "?") .. (t.where and (" (" .. tostring(t.where) .. ")") or "") .. ": " ..
        (#inside > 0 and table.concat(inside, ", ") or "empty"))
    if w then
      say("  functions: " .. fnList(w))
      local okT, tk = pcall(function() return w.tanks and w.tanks() end)
      if okT and type(tk) == "table" then
        for _, f in pairs(tk) do
          if type(f) == "table" then
            say("  tank: " .. tostring(f.name or "empty") .. " " .. tostring(f.amount or 0) .. " / " .. tostring(f.capacity or "?") .. " mB")
          end
        end
      end
    else
      say("  could not be opened right now")
    end
  end
end

-- ask the ME network to craft a fluid
function craftFluidME(name, mb)
  local ok, r, e = callx(bridge, "craftFluid", { name = name, amount = mb })
  if not ok then return false, tostring(r) end
  if not r then return false, tostring(e or "craft request failed") end
  return true
end

-- ask the ME network to craft an item
function craftME(name, count)
  local ok, r, e = callx(bridge, "craftItem", { name = name, count = count })
  if not ok then return false, tostring(r) end
  if r == nil then return false, tostring(e or "craft request failed") end
  return true
end

-- runs a confirmed action {kind, name, count, label}
function runAction(a)
  local disp = prettify(a.name)
  local known = state.me and state.me.byName and state.me.byName[a.name]
  if known then disp = known.display end

  local fluid = a.kind == "ftake" or a.kind == "fstore" or a.kind == "fcraft" or a.kind == "ftank" or a.kind == "fempty"
                or a.kind == "ftop1" or a.kind == "fempty1" or a.kind == "flushbuf"
  if fluid then
    local knownF = state.me and state.me.byNameF and state.me.byNameF[a.name]
    if knownF then disp = knownF.display end
  end
  if (a.kind ~= "craft" and not fluid and not inv) or not bridge then
    setToast("Inventory Manager or bridge is disconnected right now", C.bad, 8)
    return
  end

  if a.kind ~= "craft" and not fluid then
    local prob = bufferProblem()
    if prob then
      setToast(prob, C.bad, 12)
      return
    end
  end

  if a.kind == "cstore" or a.kind == "cunequip" or a.kind == "cequip" then
    local n, err
    if a.kind == "cstore" then n, err = curioToME(a.name, a.count, a.slotType, a.slotNo)
    elseif a.kind == "cunequip" then n, err = curioToInventory(a.name, a.count, a.slotType, a.slotNo)
    else n, err = meToCurio(a.name, a.count, a.slotType, a.slotNo) end
    local verb = (a.kind == "cstore" and "Stored in the network: ") or (a.kind == "cunequip" and "Moved to your inventory: ")
                 or "Put on: "
    if n > 0 then setToast(verb .. disp .. (err and (" - " .. err) or ""), err and C.warn or C.good, 8)
    else setToast("Curios: " .. disp .. " not moved - " .. tostring(err or "nothing happened"), C.bad, 12) end
    state.force.curios = true
    state.meForce = true
    os.queueEvent("inv_wake")
    return
  end

  if a.kind == "take" then
    local n, err = takeFromME(a.name, a.count)
    if err then
      if n == 0 then
        setToast("Failed: " .. err .. "  (buffer chest set up? see CONFIG.me)", C.bad, 10)
      else
        setToast(string.format("Took %s %s, then: %s", commas(n), disp, err), C.bad, 10)
      end
    elseif n == 0 then
      setToast("Nothing moved: network empty or your inventory is full", C.warn)
    else
      setToast(string.format("Took %s %s from the network", commas(n), disp), C.good)
    end
  elseif a.kind == "send" then
    local n, err = sendToME(a.name, a.count)
    if err then
      if n == 0 then
        setToast("Failed: " .. err .. "  (buffer chest set up? see CONFIG.me)", C.bad, 10)
      else
        setToast(string.format("Sent %s %s, then: %s", commas(n), disp, err), C.bad, 10)
      end
    elseif n == 0 then
      setToast("Nothing moved: network full or item not found", C.warn)
    else
      setToast(string.format("Sent %s %s to the network", commas(n), disp), C.good)
    end
  elseif a.kind == "flushbuf" then
    local items, fluids, notes = flushBufferToME()
    setToast(string.format("Buffer emptied into the network: %d items, %s of fluids%s", items, fmtBuckets(fluids),
             #notes > 0 and (" - " .. table.concat(notes, "; ")) or ""), #notes > 0 and C.warn or C.good, 10)
  elseif a.kind == "ftop1" or a.kind == "fempty1" then
    -- one container only (buttons on the STORAGE tab)
    local n, err
    if a.kind == "ftop1" then n, err = fluidToPlayer(a.name, a.count, a.ref)
    else n, err = fluidFromPlayer(a.name, a.count, a.ref) end
    if n == 0 then
      setToast("Fluid not moved: " .. tostring(err), C.bad, 10)
    else
      setToast(string.format("%s %s of %s%s", a.kind == "ftop1" and "Topped up with" or "Emptied", fmtBuckets(n), disp,
               err and (" - " .. err) or (a.kind == "fempty1" and " into the network" or "")), err and C.warn or C.good, 8)
    end
    state.t.storage = -100                    -- show the new contents soon
  elseif a.kind == "ftank" or a.kind == "fempty" then
    local n, err
    if a.kind == "ftank" then n, err = fluidToPlayer(a.name, a.count)
    else n, err = fluidFromPlayer(a.name, a.count) end
    if n == 0 then
      setToast("Fluid not moved: " .. tostring(err), C.bad, 10)
    else
      setToast(string.format("%s %s of %s%s", a.kind == "ftank" and "Filled your containers with" or "Stored",
               fmtBuckets(n), disp, err and (" - " .. err) or (a.kind == "fempty" and " in the network" or "")),
               err and C.warn or C.good, 8)
    end
  elseif a.kind == "fcraft" then
    local ok, err = craftFluidME(a.name, a.count)
    if ok then
      setToast(string.format("Crafting requested: %s of %s", fmtBuckets(a.count), disp), C.good)
    else
      setToast("Craft failed: " .. tostring(err), C.bad, 10)
    end
  elseif fluid then
    local n, err = moveFluid(a.kind == "ftake" and "take" or "store", a.name, a.count)
    local where = a.kind == "ftake" and "into the fluid storage" or "into the ME network"
    if n == 0 then
      setToast("Fluid not moved: " .. tostring(err), C.bad, 10)
    else
      setToast(string.format("Moved %s of %s %s%s", fmtBuckets(n), disp, where,
               err and (" (then: " .. err .. ")") or ""), err and C.warn or C.good)
    end
  elseif a.kind == "craft" then
    local ok, err = craftME(a.name, a.count)
    if ok then
      setToast(string.format("Crafting requested: %s x %s", commas(a.count), disp), C.good)
    else
      setToast("Craft failed: " .. tostring(err), C.bad, 10)
    end
  end
  state.meForce = true
end



---------------------------------------------------------------------
-- "mesetup": find the buffer chest by itself (one item in it is enough)
-- and save how the Inventory Manager and the ME Bridge reach it - no
-- settings to edit. The result (me_setup.dat) overrides base_config.lua.
---------------------------------------------------------------------
local SETUP_FILE = "me_setup.dat"
local SIDES = { "north", "south", "east", "west", "up", "down" }

-- use the buffer chest found by 'mesetup' (me_setup.dat)
function loadMESetup()
  if not fs.exists(SETUP_FILE) then return end
  local h = fs.open(SETUP_FILE, "r")
  local t = h and textutils.unserialize(h.readAll() or "")
  if h then h.close() end
  if type(t) == "table" and t.managerSide and t.bridge then
    CONFIG.me.bufferFromManager = t.managerSide
    CONFIG.me.giveFromManager, CONFIG.me.takeFromManager = nil, nil   -- one chest for both ways
    CONFIG.me.giveChest, CONFIG.me.takeChest = nil, nil
    if t.bridgeIsName then
      CONFIG.me.buffer = t.bridge
    else
      CONFIG.me.buffer = nil
      CONFIG.me.bufferFromBridge = t.bridge
    end
    MESETUP = t
  end
end

-- save what 'mesetup' found and report it
local function saveSetup(side, cd, say)
  local h = fs.open(SETUP_FILE, "w")
  if h then
    h.write(textutils.serialize({ managerSide = side, bridge = cd.target, bridgeIsName = cd.isName or false }))
    h.close()
  end
  loadMESetup()
  state.meChests, state.meChestsT = nil, nil
  say("SETUP DONE: the Inventory Manager reaches the buffer " ..
      (side:find(":", 1, true) and ("by its network name " .. side) or ("on its " .. side .. " side")) .. ";")
  say("the ME Bridge reaches it " .. (cd.isName and ("by its network name " .. cd.target)
      or ("on its " .. cd.target .. " side")) .. ". Saved - TAKE on the ME tab works now.")
end

-- 'mesetup' help: the bridge cannot reach the buffer
local function cannotReach(say)
  say("The ME Bridge cannot reach the buffer. Either put a WIRED MODEM on it (connected to")
  say("this computer's network, right-click it), or move the ME Bridge so it touches it.")
  say("Then type  mesetup  again.")
end

-- Inventory Managers without getItemsChest (cannot look into a chest): the
-- ONE item in the buffer is moved to the player and straight back to find
-- the side, then pulled into the ME network to find how the bridge reaches it.
local function meSetupByMoving(say)
  -- containers on the network (not the Inventory Manager / ME Bridge themselves)
  local contents = {}
  for _, n in ipairs(inventoriesOnNetwork()) do
    local okT, ty = pcall(peripheral.getType, n)
    ty = (okT and type(ty) == "string") and ty or ""
    if not (ty:find("inventory_manager", 1, true) or ty:find("inventoryManager", 1, true) or ty:find("me_bridge", 1, true)) then
      local okL, l = pcall(peripheral.call, n, "list")
      if okL and type(l) == "table" then contents[#contents + 1] = { name = n, list = l } end
    end
  end
  -- the marker item: a container holding exactly ONE item (else a stick)
  local single = {}
  for _, c in ipairs(contents) do
    local total, name = 0, nil
    for _, it in pairs(c.list) do
      if type(it) == "table" then total = total + (tonumber(it.count) or 0) name = it.name end
    end
    if total == 1 then single[#single + 1] = { name = c.name, item = name } end
  end
  local marker = (#single == 1) and single[1].item or "minecraft:stick"
  -- the containers on the network holding the marker: tried first (newer
  -- Inventory Managers only take network names, not sides)
  local netCand = {}
  for _, c in ipairs(contents) do
    for _, it in pairs(c.list) do
      if type(it) == "table" and it.name == marker then
        netCand[#netCand + 1] = { target = c.name, isName = true }
        break
      end
    end
  end
  local log = {}                       -- what each attempt answered (shown if it fails)
  local function toPlayer(side)
    local ok, r, e = transfer(inv, INV_TO_PLAYER, side, { name = marker, count = 1 })
    local moved = ok and (tonumber(r) or 0) > 0
    if not moved then log[#log + 1] = side .. ": " .. tostring(ok and (e or ("moved " .. tostring(r))) or r) end
    return moved
  end
  local function fromPlayer(side) transfer(inv, INV_FROM_PLAYER, side, { name = marker, count = 1 }) end
  say("Looking for the buffer with the item " .. marker .. " (it moves to you and straight back) ...")
  -- 1. which side of the Inventory Manager (world and relative side names)
  local side
  local ALL = {}
  for _, c in ipairs(netCand) do ALL[#ALL + 1] = c.target end
  for _, sd in ipairs({ "north", "south", "east", "west", "up", "down", "top", "bottom", "front", "back", "left", "right" }) do
    ALL[#ALL + 1] = sd
  end
  for _, sd in ipairs(ALL) do
    if toPlayer(sd) then
      fromPlayer(sd)
      side = sd
      break
    end
  end
  if not side then
    say("No container next to the Inventory Manager gave out the item. Check that:")
    say(" - the buffer touches the Inventory Manager and holds exactly ONE item (e.g. one stick),")
    say(" - you are online and have a free slot in your inventory.")
    -- details for finding the cause
    local fns = {}
    for k, v in pairs(inv) do if type(v) == "function" then fns[#fns + 1] = k end end
    table.sort(fns)
    say("DETAILS - the Inventory Manager offers: " .. table.concat(fns, ", "))
    say("DETAILS - marker item: " .. marker .. ((#single == 1) and (" (read from " .. single[1].name .. ")") or " (assumed)") ..
        " - containers on the network holding it: " .. (#netCand > 0 and #netCand or "none"))
    for i = 1, math.min(#log, 12) do say("DETAILS - " .. log[i]) end
    return
  end
  -- 2. how the ME Bridge reaches it: after the bridge takes the item, the buffer must be empty
  local cands = {}
  for _, c in ipairs(netCand) do cands[#cands + 1] = c end
  for _, sd in ipairs(SIDES) do cands[#cands + 1] = { target = sd } end
  for _, cd in ipairs(cands) do
    local ok, moved = transfer(bridge, ME_IN, cd.target, { name = marker, count = 1 })
    if ok and (tonumber(moved) or 0) > 0 then
      local stillThere = toPlayer(side)
      if stillThere then fromPlayer(side) end
      transfer(bridge, ME_OUT, cd.target, { name = marker, count = 1 })     -- put it back
      if not stillThere then
        saveSetup(side, cd, say)
        return
      end
    end
  end
  cannotReach(say)
end

-- 'mesetup': find the buffer chest (needs ONE item in it)
function meSetup(say)
  if not inv then say("No Inventory Manager found on this computer.") return end
  if not bridge then say("No ME Bridge found on this computer.") return end
  if not inv.getItemsChest then return meSetupByMoving(say) end
  -- 1. the chests touching the Inventory Manager
  local found, withItems, names = {}, {}, {}
  for _, s in ipairs(SIDES) do
    local ok, r = pcall(inv.getItemsChest, s)
    if ok and type(r) == "table" then
      local items = {}
      for _, it in pairs(r) do if type(it) == "table" and it.name then items[#items + 1] = it end end
      found[#found + 1] = { side = s, items = items }
      if #items > 0 then withItems[#withItems + 1] = found[#found] end
      names[#names + 1] = s .. (#items > 0 and " (has items)" or " (empty)")
    end
  end
  if #found == 0 then
    say("No chest touches the Inventory Manager. Place a chest directly next to it (any side),")
    say("put ONE item in it, then type  mesetup  again.")
    return
  end
  say("Chests next to the Inventory Manager: " .. table.concat(names, ", "))
  if #withItems == 0 then
    say("Put ONE item (e.g. a stick) into the chest you want as buffer, then type  mesetup  again.")
    return
  end
  if #withItems > 1 then
    say("More than one of them has items. Leave items only in the buffer chest, then type  mesetup  again.")
    return
  end
  local c = withItems[1]
  local marker = c.items[1].name
  local function countIn()
    local ok, r = pcall(inv.getItemsChest, c.side)
    local n = 0
    if ok and type(r) == "table" then
      for _, it in pairs(r) do if type(it) == "table" and it.name == marker then n = n + (tonumber(it.count) or 0) end end
    end
    return n
  end
  -- 2. how the ME Bridge reaches it: chests on the network with the same
  -- contents first, then each side of the bridge. Each try moves ONE item
  -- into the ME network and straight back; it only counts if that item
  -- really left THIS chest.
  local cands = {}
  local sig = chestSig(c.items)
  for _, n in ipairs(inventoriesOnNetwork()) do
    local okL, l = pcall(peripheral.call, n, "list")
    if okL and chestSig(l) == sig then cands[#cands + 1] = { target = n, isName = true } end
  end
  for _, s in ipairs(SIDES) do cands[#cands + 1] = { target = s } end
  local before = countIn()
  for _, cd in ipairs(cands) do
    local ok, moved = transfer(bridge, ME_IN, cd.target, { name = marker, count = 1 })
    if ok and (tonumber(moved) or 0) > 0 then
      local after = countIn()
      transfer(bridge, ME_OUT, cd.target, { name = marker, count = 1 })      -- put it back
      if after < before then
        local h = fs.open(SETUP_FILE, "w")
        if h then
          h.write(textutils.serialize({ managerSide = c.side, bridge = cd.target, bridgeIsName = cd.isName or false }))
          h.close()
        end
        loadMESetup()
        state.meChests, state.meChestsT = nil, nil
        say("SETUP DONE: the buffer chest is on the " .. c.side .. " side of the Inventory Manager;")
        say("the ME Bridge reaches it " .. (cd.isName and ("by its network name " .. cd.target)
            or ("on its " .. cd.target .. " side")) .. ". Saved - TAKE on the ME tab works now.")
        return
      end
    end
  end
  say("The ME Bridge cannot reach that chest. Either put a WIRED MODEM on the chest (connected to")
  say("this computer's network, right-click it), or move the ME Bridge so it touches the chest.")
  say("Then type  mesetup  again.")
end

loadMESetup()
