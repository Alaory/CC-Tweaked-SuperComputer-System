-- base_ui_me.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   ME tab (shows 'RS' with an RS Bridge): network status, item / fluid browser,
--   and the buttons to take, store and craft.

-- page drawing
-- colour from the name only (does not use up the inventory's colour slots)
function hashColor(name)
  local h = 5381
  for i = 1, #name do h = (h * 33 + name:byte(i)) % 2147483647 end
  return ITEM_COLORS[h % #ITEM_COLORS + 1]
end

-- filtered + sorted list of ME items (cached until something changes)
-- mB -> "12,345 B" (buckets), small amounts in mB
function fmtBuckets(mb)
  mb = tonumber(mb) or 0
  if mb >= 1000 then return commas(math.floor(mb / 1000)) .. " B" end
  return commas(mb) .. " mB"
end

-- the ME list as shown (sorted / filtered), cached until something changes
function meView()
  local me = state.me
  local key = table.concat({ state.meVersion, state.meSort, tostring(state.meType),
                             tostring(state.meCraftOnly), tostring(state.meLetter) }, "|")
  if state.meViewKey == key and state.meView then return state.meView end
  local out = {}
  local src = (state.meType == "fluids" and me.fluids) or (state.meType == "chemicals" and me.chemicals) or me.items
  for _, it in ipairs(src or {}) do
    local okLetter = true
    if state.meLetter then
      local c = it.display:sub(1, 1):upper()
      if state.meLetter == "#" then okLetter = not c:match("%a")
      else okLetter = (c == state.meLetter) end
    end
    if okLetter and (not state.meCraftOnly or it.craftable) then out[#out + 1] = it end
  end
  local byCount = state.meSort == "count"
  table.sort(out, function(a, b)
    if byCount and a.count ~= b.count then return a.count > b.count end
    return a.display:lower() < b.display:lower()
  end)
  state.meView, state.meViewKey = out, key
  return out
end

-- the ME tab
function drawMEPage(G)
  local y0 = G.y0
  if not bridge then
    drawMessage("NO ME / RS BRIDGE", deviceHelpLines("ME/RS Bridge"), C.warn)
    return
  end
  local me = state.me
  if not me then
    drawMessage("LOADING", { "Reading the storage network..." }, C.label)
    return
  end
  if me.err then
    drawMessage(bridgeKind .. " BRIDGE", { me.err }, C.warn)
    return
  end

  local lx = 2
  local leftW = math.floor((W - 3) * 0.62)
  local rx = lx + leftW + 1
  local rw = W - rx

  -- title
  text(2, y0, bridgeKind .. " NETWORK", C.label, C.bg)
  local online = me.online ~= false
  text(2 + #bridgeKind + 10, y0, online and "\7 ONLINE" or "\7 OFFLINE",
       online and C.good or C.bad, C.bg)
  -- items that could not be delivered yet (retried automatically)
  if owedCount then
    local n, kinds = owedCount()
    if n > 0 then
      text(2 + #bridgeKind + 22, y0, string.format(" %d item(s) of %d type(s) waiting in the buffer - retried automatically ", n, kinds),
           C.ink, C.warn)
    end
  end

  ------------------------------------------------ left: item browser
  local lh = G.bodyH - 1
  local mtype = state.meType or "items"
  local liquid = mtype ~= "items"
  card(lx, y0 + 1, leftW, lh, mtype:upper())
  local ix, iw = lx + 2, leftW - 4
  -- what to show: items, fluids, chemicals (when the server has them)
  local types = { { "items", " ITEMS (" .. #me.items .. ") " }, { "fluids", " FLUIDS (" .. #(me.fluids or {}) .. ") " } }
  if me.hasChem then types[#types + 1] = { "chemicals", " CHEMICALS (" .. #(me.chemicals or {}) .. ") " } end
  local tbx = ix + 10
  for _, t in ipairs(types) do
    local on = mtype == t[1]
    text(tbx, y0 + 2, t[2], on and C.ink or C.text, on and C.accent or C.empty)
    addHit(tbx, y0 + 2, #t[2], 1, "metype", t[1])
    tbx = tbx + #t[2] + 1
  end

  local b1 = " SORT: " .. state.meSort:upper() .. " "
  local b2 = state.meCraftOnly and " CRAFTABLE: ON " or " CRAFTABLE: OFF "
  local bx2 = lx + leftW - #b2 - 2
  local bx1 = bx2 - #b1 - 1
  text(bx1, y0 + 2, b1, C.ink, C.accent)
  addHit(bx1, y0 + 2, #b1, 1, "mesort")
  text(bx2, y0 + 2, b2, C.ink, state.meCraftOnly and C.good or C.accent)
  addHit(bx2, y0 + 2, #b2, 1, "mecraft")

  -- letter filter strip
  local tokens = { { "ALL", false } }
  for c = 65, 90 do tokens[#tokens + 1] = { string.char(c), string.char(c) } end
  tokens[#tokens + 1] = { "#", "#" }
  local tx = ix
  for _, t in ipairs(tokens) do
    local lab = " " .. t[1] .. " "
    if tx + #lab > ix + iw then break end
    local active = (state.meLetter == (t[2] or nil))
    text(tx, y0 + 4, lab, active and C.ink or C.text, active and C.accent or C.empty)
    addHit(tx, y0 + 4, #lab, 1, "meletter", t[2])
    tx = tx + #lab
  end

  local extra = 0
  if me.partial and not liquid then
    -- two lines: what happened, and where the broken item is
    text(ix, y0 + 5, trunc("PARTIAL VIEW: an item breaks the server's list - " ..
                           tostring(me.partialCount or 0) .. " items found by their tags", iw), C.warn, C.panel)
    local where = me.brokenName and ("BROKEN ITEM: " .. me.brokenName .. " - take it out of the network")
                  or (me.brokenTags and #me.brokenTags > 0)
                  and ("Broken item has tag " .. table.concat(me.brokenTags, " ") .. " - take it out of the network")
                  or "The broken item has none of the common tags - recently added modded items are suspects"
    text(ix, y0 + 6, trunc(where, iw), C.warn, C.panel)
    extra = 1
  end

  local view = meView()
  local ry0 = y0 + 6 + extra
  local per = math.max(1, (y0 + lh - 1) - ry0 + 1)
  local pages = math.max(1, math.ceil(#view / per))
  state.meItemsPage = math.max(1, math.min(state.meItemsPage, pages))
  drawPager(y0, "meItemsPage", pages, lx + leftW - 1)

  local maxCount = 1
  for _, it in ipairs(view) do if it.count > maxCount then maxCount = it.count end end

  if #view == 0 then
    text(ix, ry0, "No items match this filter", C.dim, C.panel)
  end
  for i = 1, per do
    local it = view[(state.meItemsPage - 1) * per + i]
    if not it then break end
    local ry = ry0 + i - 1
    local sel = state.meSel == it.name
    local vs = (liquid and fmtBuckets(it.count) or commas(it.count)) .. (it.craftable and "  [C]" or "")
    drawBarRow(ix, ry, iw, it.display, vs, it.count / maxCount, hashColor(it.name), sel, 18)
    addHit(ix, ry, iw, 1, "meitem", it.name)
  end

  ------------------------------------------------ right column
  -- network status
  local storages = {}
  local function addStore(label, st, buckets)
    if st and st.used and st.max and st.max > 0 then storages[#storages + 1] = { label, st, buckets } end
  end
  addStore("Item storage", me.storage, false)
  addStore("Fluid storage", me.fstorage, true)
  addStore("Chemical storage", me.cstorage, true)
  local sy, sh = y0 + 1, 3 + 3 + 3 * #storages + 2 + 1 + 4
  card(rx, sy, rw, sh, "NETWORK")
  local rix, riw = rx + 2, rw - 4
  local r = sy + 3
  local en = me.energy or {}
  if en.stored and en.cap and en.cap > 0 then
    kv(rix, r, riw, "Energy", compact(en.stored) .. " / " .. compact(en.cap))
    barW(rix, r + 1, riw, math.floor(math.min(1, en.stored / en.cap) * riw + 0.5), C.warn)
    r = r + 3
  end
  for _, sto in ipairs(storages) do
    local st = sto[2]
    local f = math.min(1, st.used / st.max)
    local col = f < 0.6 and C.good or (f < 0.85 and C.warn or C.bad)
    local v = sto[3] and (fmtBuckets(st.used) .. " / " .. fmtBuckets(st.max))
              or (compact(st.used) .. " / " .. compact(st.max))
    kv(rix, r, riw, sto[1], v)
    barW(rix, r + 1, riw, math.floor(f * riw + 0.5), col)
    r = r + 3
  end
  if en.usage and r <= sy + sh - 2 then
    kv(rix, r, riw, "Energy use", compact(en.usage) .. "/t"); r = r + 1
  end
  if en.inj and r <= sy + sh - 2 then
    kv(rix, r, riw, "Injection", compact(en.inj) .. "/t")
  end
  -- everything in the buffer(s) back into the network (needs a double tap)
  local fb = me.fluidBuf and (" + " .. me.fluidBuf) or ""
  actButton(rix, sy + sh - 4, riw, 3, trunc("BUFFER -> ME  (empties " .. tostring(chestBridge("give")) .. fb .. ")", riw - 2),
            { kind = "flushbuf", name = "buffer", count = 0 })

  -- selected item + actions
  local py, ph = sy + sh + 1, (mtype == "fluids") and 28 or 21   -- fluids: more rows
  card(rx, py, rw, ph, "SELECTED ITEM")
  local selMap = (mtype == "fluids" and me.byNameF) or (mtype == "chemicals" and me.byNameC) or me.byName
  local sel = state.meSel and (selMap or {})[state.meSel]
  if sel and liquid then
    -- a fluid / chemical: details only (moving it would need a tank as buffer)
    text(rix, py + 3, trunc(sel.display, riw), hashColor(sel.name), C.panel)
    text(rix, py + 4, trunc(sel.name, riw), C.dim, C.panel)
    kv(rix, py + 5, riw, "In network", fmtBuckets(sel.count) .. (sel.craftable and "   craftable" or ""))
    if mtype == "fluids" and me.fluidBuf then
      local inBuf = 0
      for _, tk in pairs(me.fluidBufTanks or {}) do
        if type(tk) == "table" and tk.name == sel.name then inBuf = inBuf + (tonumber(tk.amount) or 0) end
      end
      kv(rix, py + 6, riw, "In the fluid storage", fmtBuckets(inBuf))
      -- in the player's own fluid containers (tanks in the inventory / curios)
      local inTanks, nTanks = 0, 0
      for _, st in ipairs(state.storage or {}) do
        if st.isFluid and st.ref then
          nTanks = nTanks + 1
          for _, tk in ipairs(st.tanks or {}) do if tk.name == sel.name then inTanks = inTanks + (tonumber(tk.amount) or 0) end end
        end
      end
      kv(rix, py + 7, riw, "In your containers", nTanks > 0 and fmtBuckets(inTanks) or "no fluid container carried")
      local function frow(yy, label, kind, amounts)
        text(rix, yy, label, C.label, C.panel)
        local n = #amounts
        local bw = math.floor((riw - (n - 1)) / n)
        for i, a in ipairs(amounts) do
          -- a[3]: this button's own action (else the row's)
          actButton(rix + (i - 1) * (bw + 1), yy + 1, bw, 3, a[1], { kind = a[3] or kind, name = sel.name, count = a[2] })
        end
      end
      frow(py + 9, "TAKE TO FLUID STORAGE", "ftake",
           { { "1 B", 1000 }, { "16 B", 16000 }, { "64 B", 64000 }, { "ALL", math.max(1, sel.count) } })
      if nTanks > 0 then
        frow(py + 13, "FILL MY CONTAINERS", "ftank",
             { { "1 B", 1000 }, { "16 B", 16000 }, { "ALL", math.max(1, sel.count) } })
      end
      -- "16 B" / "ALL" come from the fluid storage, "FROM MINE" from your own containers
      local store = { { "16 B", 16000 }, { "ALL", math.max(1, inBuf) } }
      if inTanks > 0 then store[#store + 1] = { "FROM MINE", inTanks, "fempty" } end
      frow(py + 17, "STORE IN ME", "fstore", store)
      if sel.craftable then
        frow(py + 21, "CRAFT", "fcraft", { { "1 B", 1000 }, { "16 B", 16000 }, { "64 B", 64000 }, { "256 B", 256000 } })
      end
      text(rix, py + ph - 2, trunc("Fluid storage: " .. me.fluidBuf, riw), C.dim, C.panel)
    elseif mtype == "fluids" then
      text(rix, py + 8, trunc("Fluids cannot be moved: " .. tostring(me.fluidBufErr or "no fluid storage"), riw), C.warn, C.panel)
      text(rix, py + 9, trunc("Connect a tank or fluid storage to the wired network.", riw), C.dim, C.panel)
      if sel.craftable then           -- crafting needs no fluid storage
        text(rix, py + 11, "CRAFT", C.label, C.panel)
        local amounts = { { "1 B", 1000 }, { "16 B", 16000 }, { "64 B", 64000 }, { "256 B", 256000 } }
        local bw = math.floor((riw - 3) / 4)
        for i, a in ipairs(amounts) do
          actButton(rix + (i - 1) * (bw + 1), py + 12, bw, 3, a[1], { kind = "fcraft", name = sel.name, count = a[2] })
        end
      end
    else
      text(rix, py + 8, trunc("View only: " .. mtype .. " cannot be moved from here", riw), C.dim, C.panel)
    end
  elseif not sel then
    local msg = "Touch an item in the list"
    text(rx + math.floor((rw - #msg) / 2), py + math.floor(ph / 2), msg, C.dim, C.panel)
  else
    text(rix, py + 3, trunc(sel.display, riw), hashColor(sel.name), C.panel)
    text(rix, py + 4, trunc(sel.name, riw), C.dim, C.panel)
    kv(rix, py + 5, riw, "In network", commas(sel.count) ..
       (sel.craftable and "   craftable" or ""))

    local function row(yy, label, kind, amounts)
      text(rix, yy, label, C.label, C.panel)
      local n = #amounts
      local bw = math.floor((riw - (n - 1)) / n)
      for i, a in ipairs(amounts) do
        local cnt = a[2]
        if kind == "take" and cnt > sel.count then cnt = math.max(1, sel.count) end
        actButton(rix + (i - 1) * (bw + 1), yy + 1, bw, 3, a[1],
                  { kind = kind, name = sel.name, count = cnt })
      end
    end
    row(py + 7, "TAKE TO INVENTORY", "take",
        { { "x1", 1 }, { "x16", 16 }, { "x64", 64 }, { "ALL", math.max(1, sel.count) } })
    if sel.craftable then
      row(py + 12, "CRAFT", "craft",
          { { "x1", 1 }, { "x16", 16 }, { "x64", 64 }, { "x256", 256 } })
    end
    -- the chests the transfers go through (give = to the player, take = from the player)
    local chests = me.chests or {}
    local function chestLine(w, label, yy)
      local c = chests[w]
      local mdir = chestManagerDir(w)
      local manual = (w == "give") and CONFIG.me.giveChest or CONFIG.me.takeChest
      local auto = state.meAuto and state.meAuto[w]
      local how = manual and tostring(manual) or (auto and (auto .. " (found)")) or
                  (bufBridge() .. (CONFIG.me.buffer and "" or " of bridge") .. " - put an item in it once to find it")
      local msg, col
      if c and c.ok == false then
        msg, col = "NO " .. label .. " CHEST on the " .. mdir .. " side of the Inventory Manager - type mesetup", C.bad
      else
        msg, col = label .. " chest: " .. mdir .. " of manager, bridge: " .. how, C.dim
      end
      text(rix, yy, trunc(msg, riw), col, C.panel)
    end
    local same = chestManagerDir("give") == chestManagerDir("take")
    if same then
      chestLine("give", "BUFFER", py + ph - 3)
    else
      chestLine("give", "GIVE", py + ph - 4)
      chestLine("take", "TAKE", py + ph - 3)
    end
    text(rix, py + ph - 2, trunc("Items go to " .. tostring(state.owner or "the Memory Card owner") ..
         " (the player of the Memory Card)", riw), C.dim, C.panel)
  end

  -- drives & cells: every kind of storage cell (items, fluids, chemicals,
  -- Applied Flux ...), how many and how full
  local cy = py + ph + 1
  if #(me.cellTypes or {}) > 0 then
    local ch2 = 4 + #me.cellTypes * 2
    if G.y1 - cy + 1 >= ch2 then
      card(rx, cy, rw, ch2, "DRIVES & CELLS")
      for i, ct in ipairs(me.cellTypes) do
        local yy = cy + 3 + (i - 1) * 2
        local f = ct.total > 0 and math.min(1, ct.used / ct.total) or 0
        kv(rix, yy, riw, ct.n .. "x " .. ct.label, math.floor(f * 100 + 0.5) .. "% full")
        barW(rix, yy + 1, riw, math.floor(f * riw + 0.5), f < 0.6 and C.good or (f < 0.85 and C.warn or C.bad))
      end
      cy = cy + ch2 + 1
    end
  end

  -- crafting jobs
  local chh = G.y1 - cy + 1
  if chh >= 6 then
    card(rx, cy, rw, chh, "CRAFTING JOBS")
    if #me.tasks == 0 then
      text(rix, cy + 3, "No active crafting jobs", C.dim, C.panel)
    else
      local rows = math.floor((chh - 4) / 3)
      for i = 1, math.min(rows, #me.tasks) do
        local t = me.tasks[i]
        local yy = cy + 3 + (i - 1) * 3
        kv(rix, yy, riw, trunc(t.name, riw - 16),
           commas(t.crafted) .. " / " .. commas(t.quantity))
        barW(rix, yy + 1, riw, math.floor(math.max(0, math.min(1, t.completion)) * riw + 0.5), C.good)
      end
      if #me.tasks > rows then
        text(rix, cy + chh - 2, "+ " .. (#me.tasks - rows) .. " more...", C.dim, C.panel)
      end
    end
  end
end
