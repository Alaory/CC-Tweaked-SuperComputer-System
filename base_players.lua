-- base_players.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   Player Detector data: online players, positions, health, and which
--   dimension each one is in (saved in player_dims.dat). The owner's armour and
--   hands via the Inventory Manager. '$drone back' tracking: remembers where a
--   player was before a big jump or where they died (overworld only).

---------------------------------------------------------------------
-- PLAYER DATA (Player Detector)
---------------------------------------------------------------------
DIM_KEYS = { "dimension", "dim", "dimensionName", "dimensionId", "world", "level" }

-- a dimension name from a text or a {location/name/id} table
local function dimValue(v)
  if type(v) == "string" and v ~= "" then return v end
  if type(v) == "table" then
    local sv = v.location or v.name or v.id
    if type(sv) == "string" and sv ~= "" then return sv end
  end
end

-- the dimension in the detector's data for a player (nil if it has none)
function dimFromData(p)
  if type(p) ~= "table" then return nil end
  for _, k in ipairs(DIM_KEYS) do
    local v = dimValue(p[k])
    if v then return v end
  end
  -- other spellings ("Dimension", "currentDimension" ...), but never the
  -- respawn / spawn dimension: that is where the bed is, not where they are
  for k, v in pairs(p) do
    if type(k) == "string" then
      local lk = k:lower()
      if (lk:find("dim") or lk == "world" or lk == "level") and not lk:find("spawn") then
        local d = dimValue(v)
        if d then return d end
      end
    end
  end
end

-- dimensions from playerJoin / playerChangedDimension events, kept in a small
-- file so a restart does not forget players who are already in another dimension
DIM_FILE = "player_dims.dat"
do
  local h = fs.exists(DIM_FILE) and fs.open(DIM_FILE, "r")
  local t = h and textutils.unserialize(h.readAll() or "")
  if h then h.close() end
  if type(t) == "table" then
    for n, d in pairs(t) do
      if type(n) == "string" and type(d) == "string" then dimCache[n] = d end
    end
  end
end

-- write the known dimensions to player_dims.dat
local function saveDims()
  saveFileSafe(DIM_FILE, serialSmall(dimCache))
end

-- remember (and save) which dimension a player is in
function rememberDim(name, dim)
  if type(name) ~= "string" or type(dim) ~= "string" or dim == "" then return end
  if dimCache[name] == dim then return end
  dimCache[name] = dim
  saveDims()
end

-- forget a player's dimension (they left the server)
function forgetDim(name)
  if type(name) ~= "string" or dimCache[name] == nil then return end
  dimCache[name] = nil
  saveDims()
end

-- the dimension the base is in (Environment Detector, else CONFIG.homeDimension)
function homeDimension()
  if envDet then
    local fn = envDet.getDimensionPaN or envDet.getDimension
    if fn then
      local ok, d = pcall(fn)
      if ok and type(d) == "string" then return d end
    end
  end
  return CONFIG.homeDimension
end

-- players the detector can reach in its own dimension
-- (2nd result: true when the full CONFIG.detectRange was searched)
function playersInRangeSet()
  local set = {}
  if not det.getPlayersInRange then return set, false end
  for i, r in ipairs({ CONFIG.detectRange, 1024, 256 }) do
    local ok, list = pcall(det.getPlayersInRange, r)
    if ok and type(list) == "table" then
      for _, n in pairs(list) do
        if type(n) == "string" then set[n] = true
        elseif type(n) == "table" and n.name then set[n.name] = true end
      end
      return set, (i == 1)
    end
  end
  return set, false
end

-- full = every online player (PLAYERS page); otherwise only the owner
function refreshPlayers(full)
  if not det then return end
  local owner = state.owner
  local fn = det.getPlayer or det.getPlayerPos
  if not fn then
    state.playerMsg = "Detector has no getPlayer()"
    state.t.players, state.t.owner = os.clock(), os.clock()
    return
  end

  local names = {}
  if full and det.getOnlinePlayers then
    local ok, r = pcall(det.getOnlinePlayers)
    if ok and type(r) == "table" then
      for _, n in pairs(r) do
        if type(n) == "string" then names[#names + 1] = n end
      end
    end
  end
  if not full then names = owner and { owner } or {} end
  if #names == 0 and owner then names[1] = owner end

  table.sort(names, function(a, b)
    local ao, bo = a == owner, b == owner
    if ao ~= bo then return ao end
    return a:lower() < b:lower()
  end)

  -- ask about every player at the same time
  local res = pmap(names, function(name)
    local ok, pl = pcall(fn, name)
    return { ok = ok, pl = pl }
  end)

  -- the "same dimension as the detector" fallback is only read if needed
  local needRange = false
  for i, name in ipairs(names) do
    local r = res[i]
    if r and r.ok and type(r.pl) == "table" and next(r.pl)
       and not dimFromData(r.pl) and not dimCache[name] then
      needRange = true
    end
  end
  local inRange, home, fullRange = {}, nil, false
  if needRange then
    if state.inRange and state.inRangeT and os.clock() - state.inRangeT < 5 then
      inRange, fullRange = state.inRange, state.inRangeFull
    else
      inRange, fullRange = playersInRangeSet()
      state.inRange, state.inRangeT, state.inRangeFull = inRange, os.clock(), fullRange
    end
    home = homeDimension()
  end

  local entries, ownerE = {}, nil
  for i, name in ipairs(names) do
    local e = { name = name, isOwner = (name == owner) }
    local r = res[i]
    if r and r.ok and type(r.pl) == "table" and next(r.pl) then
      e.p = r.pl
      local fromData = dimFromData(r.pl)
      if fromData then rememberDim(name, fromData) end
      e.dim = fromData or dimCache[name] or (inRange[name] and home) or nil
      -- not in the detector's own dimension, but which one is not known yet
      e.dimOther = (not e.dim) and fullRange and not inRange[name] or nil
    else
      e.err = (r and r.ok) and "Not found by detector" or tostring(r and r.pl or "no data")
      e.dim = dimCache[name]            -- known from an earlier portal trip / join
    end
    entries[#entries + 1] = e
    if e.isOwner then ownerE = e end
  end

  if full then
    state.players = entries
    state.t.players = os.clock()
  end
  if ownerE then
    state.player, state.playerDim, state.playerMsg = ownerE.p, ownerE.dim, ownerE.err
    state.playerDimOther = ownerE.dimOther
  else
    state.player, state.playerDim, state.playerMsg = nil, nil, nil
    state.playerDimOther = nil
  end
  state.t.owner = os.clock()
end

-- owner + inventory + equipment + held slot
function refreshInventory()
  if not inv then
    state.status = "offline"
    state.err = "Inventory Manager disconnected - waiting for it to come back..."
    state.t.inv = os.clock()
    return
  end
  -- getOwner() may return "uuid, name" on newer builds
  local okO, a, b = pcall(inv.getOwner)
  local owner = okO and (b or a) or nil
  state.ownerUuid = (okO and b and type(a) == "string") and a or nil
  if type(owner) == "string" then
    local stripped = owner:gsub("^%x+%-%x+%-%x+%-%x+%-%x+%s*", "")
    if stripped ~= "" then owner = stripped end
  end
  state.owner = owner
  if not owner then
    state.status = "nocard"
    state.t.inv = os.clock()
    return
  end

  -- read everything at the same time
  local rOK, rItems, rErr, autoBase
  local armorR, offR, handR, handSlotR
  parallel.waitForAll(
    function() rOK, rItems, rErr, autoBase = readInventory() end,
    function()
      if inv.getArmor then
        local ok, r = pcall(inv.getArmor); if ok then armorR = r end
      end
    end,
    function()
      if inv.getItemInOffHand then
        local ok, r = pcall(inv.getItemInOffHand); if ok then offR = r end
      end
    end,
    function()
      if inv.getItemInHand then
        local ok, r = pcall(inv.getItemInHand); if ok then handR = r end
      end
    end,
    function()
      if inv.getHandSlot then
        local ok, r = pcall(inv.getHandSlot); if ok then handSlotR = r end
      end
    end)

  if not rOK or type(rItems) ~= "table" then
    state.status = "offline"
    if not rOK then
      state.err = tostring(rItems)
    else
      state.err = tostring(rErr or ("inventory read returned " .. type(rItems)))
    end
    state.t.inv = os.clock()
    return
  end
  local items = rItems
  local base = CONFIG.slotBase or autoBase

  local slots, totals, order = {}, {}, {}
  local total, used, dropped = 0, 0, 0
  local equip = {}

  for key, it in pairs(items) do
    if type(it) == "table" and it.name then
      it.displayName = cleanName(it.displayName or prettify(it.name))
      local idx = (it.slot or key) - base
      if idx >= 0 and idx <= 35 then
        slots[idx] = it
        used = used + 1
        total = total + (it.count or 1)
        local t = totals[it.name]
        if not t then
          t = { name = it.name, display = it.displayName,
                count = 0, slots = {}, firstSlot = idx,
                max = tonumber(it.maxStackSize), sample = it }
          totals[it.name] = t
          order[#order + 1] = t
        end
        t.count = t.count + (it.count or 1)
        t.slots[#t.slots + 1] = idx
        if idx < t.firstSlot then t.firstSlot = idx end
      elseif idx >= 36 and idx <= 39 then
        equip[4 - (idx - 36)] = it   -- 36 boots .. 39 helmet -> helm first
      elseif idx == 40 then
        equip[5] = it
      elseif idx >= 100 and idx <= 103 then
        equip[4 - (idx - 100)] = it
      else
        dropped = dropped + 1
      end
    end
  end

  for _, t in ipairs(order) do table.sort(t.slots) end

  -- extra equipment sources (only if this build has them)
  if type(armorR) == "table" then
    local pos = 0
    for _, ar in pairs(armorR) do
      if type(ar) == "table" and ar.name then
        ar.displayName = cleanName(ar.displayName or prettify(ar.name))
        pos = pos + 1
        local sl = ar.slot
        local piece
        if sl and sl >= 100 then piece = sl - 100
        elseif sl and sl >= 36 and sl <= 39 then piece = sl - 36 end
        if piece and piece >= 0 and piece <= 3 then
          equip[4 - piece] = equip[4 - piece] or ar
        else
          equip[pos] = equip[pos] or ar
        end
      end
    end
  end
  if not equip[5] and type(offR) == "table" and offR.name then
    offR.displayName = cleanName(offR.displayName or prettify(offR.name))
    equip[5] = offR
  end

  -- which hotbar slot is selected: getHandSlot(), checked against the
  -- item in hand so we also cope with 0- vs 1-based numbering
  local heldIdx
  local hand = (type(handR) == "table" and handR.name) and handR or nil
  if type(handSlotR) == "number" then
    local i1 = handSlotR - base
    local i2 = handSlotR - (base == 1 and 0 or 1)
    local function valid(i) return i >= 0 and i <= 8 end
    if hand then
      if valid(i1) and slots[i1] and slots[i1].name == hand.name then heldIdx = i1
      elseif valid(i2) and slots[i2] and slots[i2].name == hand.name then heldIdx = i2 end
    elseif valid(i1) then
      heldIdx = i1
    end
  end
  if not heldIdx and hand then
    local cand = {}
    for i = 0, 8 do
      local it = slots[i]
      if it and it.name == hand.name and (it.count or 1) == (hand.count or 1) then
        cand[#cand + 1] = i
      end
    end
    if #cand == 1 then heldIdx = cand[1] end
  end

  -- free colours of items that are gone
  local present = {}
  for n in pairs(totals) do present[n] = true end
  for _, e in pairs(equip) do present[e.name] = true end
  for n, c in pairs(assigned) do
    if not present[n] then assigned[n] = nil; usedBy[c] = nil end
  end

  -- publish everything at once (the screen never sees a half-updated state)
  state.slots, state.list = slots, order
  state.total, state.used, state.dropped = total, used, dropped
  state.equip, state.heldIdx = equip, heldIdx
  state.rawItems, state.base = items, base
  state.status = "ok"
  state.t.inv = os.clock()
  sortList()

  if selName and not totals[selName] then selName = nil end
end



---------------------------------------------------------------------
-- "$drone back": remember where a player was before a big jump (teleport,
-- /home ...) or where they died. Overworld only.
---------------------------------------------------------------------
backSpots = {}                 -- [lower name] = { x, y, z, t = epoch ms, why, name }
local trackLast = {}           -- [lower name] = last position + health
local OVERWORLD = "minecraft:overworld"

-- write the '$drone back' spots to their file
local function backSave()
  local h = fs.open(CONFIG.back.file, "w")
  if h then h.write(textutils.serialize(backSpots)) h.close() end
end
if fs.exists(CONFIG.back.file) then
  local h = fs.open(CONFIG.back.file, "r")
  local t = h and textutils.unserialize(h.readAll() or "")
  if h then h.close() end
  if type(t) == "table" then backSpots = t end
end

-- the dimension a player is in (nil = not known)
function playerDim(name, pl)
  return (pl and dimFromData(pl)) or dimCache[name]
end

-- check every player's position: remember the spot before a big jump or a death
function trackPlayers()
  if not det or not CONFIG.back then return end
  local now = os.epoch("utc")
  -- the player list the pages read moments ago is reused (no extra detector
  -- calls); only when it is older than the check interval are they asked again
  local samples = {}
  if state.players and state.t.players and os.clock() - state.t.players < CONFIG.back.every then
    for _, e in ipairs(state.players) do
      if e.p then samples[#samples + 1] = { name = e.name, pl = e.p, dim = e.dim } end
    end
  else
    local okL, list = pcall(det.getOnlinePlayers)
    if not okL or type(list) ~= "table" then return end
    local fn = det.getPlayer or det.getPlayerPos
    if not fn then return end
    local names = {}
    for _, n in pairs(list) do names[#names + 1] = tostring(n) end
    local res = pmap(names, function(n)
      local okP, pl = pcall(fn, n)
      return okP and pl or false
    end)
    for i, n in ipairs(names) do
      if type(res[i]) == "table" then samples[#samples + 1] = { name = n, pl = res[i] } end
    end
  end
  for _, sm in ipairs(samples) do
    local name, pl = sm.name, sm.pl
    local k = name:lower()
    if type(pl) == "table" and tonumber(pl.x) then
      local dim = sm.dim or playerDim(name, pl)
      if dim and dim ~= OVERWORLD then
        trackLast[k] = nil                       -- not in the overworld: no jumps through portals
      else
        local cur = { x = pl.x, y = pl.y, z = pl.z, h = tonumber(pl.health), m = tonumber(pl.maxHealth) }
        local prev = trackLast[k]
        if prev then
          local d = math.abs(cur.x - prev.x) + math.abs(cur.z - prev.z)
          local hurt = prev.h and prev.m and prev.m > 0 and prev.h <= prev.m * CONFIG.back.lowHealth
          local healed = cur.h and cur.m and cur.m > 0 and cur.h >= cur.m * 0.9
          local died = hurt and healed and d > CONFIG.back.deathJump
          if d > CONFIG.back.jump or died then
            backSpots[k] = { x = math.floor(prev.x), y = math.floor(prev.y), z = math.floor(prev.z), t = now,
                             why = (hurt and "where you died" or "where you were before the jump"), name = name }
            backSave()
          end
        end
        trackLast[k] = cur
      end
    end
  end
end
