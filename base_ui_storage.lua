-- base_ui_storage.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   STORAGE tab (inside backpacks / tanks) and CURIOS tab (worn curios slots).

-- page drawing
function me_available() return bridge ~= nil and inv ~= nil end

-- one storage item (backpack, tank ...) and what is inside
function drawStorageCard(x, y, w, h, sInfo)
  card(x, y, w, h)
  local ix, iw = x + 2, w - 4
  local where = " " .. sInfo.where .. " "
  fill(ix, y + 1, 1, 1, colorFor(sInfo.name))
  text(ix + 2, y + 1, trunc(sInfo.display, iw - #where - 4), C.text, C.panel)
  text(x + w - #where - 2, y + 1, where, C.ink, C.accent)

  local r = y + 3
  if sInfo.isItem and sInfo.size > 0 and not sInfo.err then
    local frac = sInfo.used / sInfo.size
    local col = frac < 0.6 and C.good or (frac < 0.85 and C.warn or C.bad)
    kv(ix, r, iw, "Slots used", sInfo.used .. " / " .. sInfo.size)
    barW(ix, r + 1, iw, math.floor(frac * iw + 0.5), col)
    r = r + 3
  end

  -- fluid containers: EMPTY INTO ME / TOP UP FROM ME at the bottom of the card
  local fbtn = sInfo.isFluid and sInfo.ref and me_available and me_available() and h >= 12
  local bottom = y + h - 2 - (fbtn and 4 or 0)
  local tankRows = #sInfo.tanks > 0 and (#sInfo.tanks + 2) or 0

  if sInfo.isItem then
    if sInfo.err then
      text(ix, r, trunc(sInfo.err, iw), C.warn, C.panel)
      r = r + 1
    elseif #sInfo.contents == 0 then
      text(ix, r, "Empty", C.dim, C.panel)
      r = r + 1
    else
      local maxRows = math.max(2, bottom - r + 1 - tankRows)
      local list = sInfo.contents
      local shown, more = #list, 0
      if #list > maxRows then shown = maxRows - 1; more = #list - shown end
      local top = list[1].count
      for i = 1, shown do
        local c = list[i]
        drawBarRow(ix, r, iw, c.display, commas(c.count), c.count / top, colorFor(c.name))
        r = r + 1
      end
      if more > 0 then
        text(ix, r, "+ " .. more .. " more...", C.dim, C.panel)
        r = r + 1
      end
    end
  end

  if sInfo.isFluid then
    r = r + 1
    if r <= bottom then text(ix, r, "FLUIDS", C.label, C.panel); r = r + 1 end
    if #sInfo.tanks == 0 and r <= bottom then
      text(ix, r, "Empty", C.dim, C.panel)
    end
    for _, tk in ipairs(sInfo.tanks) do
      if r > bottom then break end
      local frac = (tk.capacity and tk.capacity > 0) and (tk.amount / tk.capacity) or 1
      drawBarRow(ix, r, iw, tk.display, commas(tk.amount) .. " mB", frac, colors.cyan)
      r = r + 1
    end
  end

  if fbtn then
    local tk
    for _, t in ipairs(sInfo.tanks) do if (t.amount or 0) > 0 and t.name then tk = t break end end
    local by, bw = y + h - 5, math.floor((iw - 1) / 2)
    if tk then
      actButton(ix, by, bw, 3, "EMPTY INTO ME",
                { kind = "fempty1", name = tk.name, count = tk.amount, ref = sInfo.ref })
      local room = (tk.capacity or 0) - tk.amount
      if room > 0 then
        actButton(ix + bw + 1, by, bw, 3, "TOP UP FROM ME",
                  { kind = "ftop1", name = tk.name, count = room, ref = sInfo.ref })
      end
    else
      text(ix, by + 1, trunc("Empty - fill it from the ME tab (FLUIDS)", iw), C.dim, C.panel)
    end
  end
end

-- the STORAGE tab
function drawStoragePage(G)
  local y0 = G.y0
  if not state.t.storage then
    drawMessage("LOADING", { "Looking inside your storage items..." }, C.label)
    return
  end
  local list = state.storage
  if state.storageMsg then
    drawMessage("STORAGE UNAVAILABLE", { state.storageMsg }, C.warn)
    return
  end
  if #list == 0 then
    drawMessage("NO STORAGE ITEMS",
      { "No backpacks or other storage items found in your inventory." }, C.warn)
    return
  end

  local cols = 2
  local cw = math.floor((W - 3) / cols)
  local maxRows = math.max(1, math.floor((G.bodyH - 2 + 1) / 25))
  local rows = math.min(maxRows, math.ceil(#list / cols))
  local ch = math.min(60, math.floor((G.bodyH - 2 - (rows - 1)) / rows))
  local per = rows * cols
  local pages = math.max(1, math.ceil(#list / per))
  state.storagePage = math.max(1, math.min(state.storagePage, pages))

  text(2, y0, "STORAGE ITEMS: " .. #list, C.label, C.bg)
  drawPager(y0, "storagePage", pages)

  for i = 1, per do
    local sInfo = list[(state.storagePage - 1) * per + i]
    if not sInfo then break end
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    drawStorageCard(2 + col * (cw + 1), y0 + 2 + row * (ch + 1), cw, ch, sInfo)
  end
end

-- the CURIOS tab
-- the CURIOS tab: every slot type with all its slots (boxes wrap onto more
-- lines, pages when they do not fit), and on the right the selected slot
-- with its actions: STORE IN ME / TO INVENTORY, or what fits from the ME network
function drawCuriosPage(G)
  local rows = state.curios
  if not rows then
    if not state.t.curios then
      drawMessage("LOADING", { "Reading curios slots..." }, C.label)
      return
    end
    if state.curiosMsg and isDistError(state.curiosMsg) then
      drawMessage("CURIOS UNAVAILABLE", DIST_LINES, C.warn)
    else
      drawMessage("CURIOS UNAVAILABLE",
        { state.curiosMsg or "Could not read the curios inventory." }, C.warn)
    end
    return
  end
  if #rows == 0 then
    drawMessage("NO CURIOS SLOTS", { "The player has no curios slots." }, C.warn)
    return
  end

  local y0 = G.y0
  local sideW = 44
  local lw = W - 3 - sideW
  local rx = 2 + lw + 1

  local equipped, slots = 0, 0
  for _, row in ipairs(rows) do
    slots = slots + row.count
    for _ in pairs(row.cells) do equipped = equipped + 1 end
  end
  local title = string.format("CURIOS: %d slot types, %d slots, %d worn", #rows, slots, equipped)
  text(2, y0, title, C.label, C.bg)
  if state.curiosNote then text(2 + #title + 3, y0, trunc(state.curiosNote, lw - #title - 4), C.warn, C.bg) end

  -- layout: one box per slot type, as wide as its slots need (up to a full
  -- line); small types sit side by side, big ones wrap onto more lines.
  -- Pages when they do not fit.
  local cw, ch, pitch = 13, 3, 14
  local perLine = math.max(1, math.floor((lw - 4) / pitch))
  local function sizeOf(row)
    local across = math.min(row.count, perLine)
    local w = math.max(4 + across * pitch, #row.name + 22)
    return math.min(lw, w), 2 + math.ceil(row.count / perLine) * (ch + 1)
  end
  local top, bottom = y0 + 2, G.y1
  local pages = { {} }
  local x, y, lineH = 2, top, 0
  for _, row in ipairs(rows) do
    local w, h = sizeOf(row)
    if x > 2 and x + w - 1 > 2 + lw - 1 then          -- next line of boxes
      x, y, lineH = 2, y + lineH + 1, 0
    end
    if y > top and y + h - 1 > bottom then            -- next page
      pages[#pages + 1] = {}
      x, y, lineH = 2, top, 0
    end
    local pg = pages[#pages]
    pg[#pg + 1] = { row = row, x = x, y = y, w = w, h = math.min(h, bottom - y + 1) }
    x = x + w + 1
    if h > lineH then lineH = h end
  end
  state.curiosPage = math.max(1, math.min(state.curiosPage or 1, #pages))
  drawPager(y0, "curiosPage", #pages, 2 + lw)

  local sel = state.curiosSel
  for _, b in ipairs(pages[state.curiosPage]) do
    local row, bx, by, h = b.row, b.x, b.y, b.h
    card(bx, by, b.w, h)
    local worn = 0
    for _ in pairs(row.cells) do worn = worn + 1 end
    text(bx + 2, by + 1, prettify(row.name):upper(), C.label, C.panel)
    text(bx + 3 + #row.name, by + 1, row.count .. (row.count == 1 and " slot" or " slots") ..
         ", " .. worn .. " worn" .. (row.stale and " (last known)" or ""), C.dim, C.panel)
    for pos = 1, row.count do
      local line, col = math.floor((pos - 1) / perLine), (pos - 1) % perLine
      local cx, cy = bx + 2 + col * pitch, by + 2 + line * (ch + 1)
      if cy + ch - 1 > by + h - 1 then break end
      local it = row.cells[pos]
      drawCell(cx, cy, cw, ch, it, row.unreadable and "?" or "empty")
      if sel and sel.type == row.name and sel.pos == pos then
        fill(cx - 1, cy, 1, ch, C.accent)                     -- the selected slot
      end
      if not row.unreadable then addHit(cx, cy, cw, ch, "csel", { row.name, pos }) end
    end
  end

  ------------------------------------------------ right: the selected slot
  local rw = W - rx
  local ix, iw = rx + 2, rw - 4
  card(rx, top, rw, bottom - top + 1, "SELECTED")
  -- the selection may be gone (slot removed) or its item changed
  local row
  for _, r in ipairs(rows) do if sel and r.name == sel.type then row = r end end
  if not row or sel.pos > row.count then
    state.curiosSel = nil
    text(ix, top + 3, "Tap a slot.", C.dim, C.panel)
    text(ix, top + 5, trunc("Worn item: store it in the ME network", iw), C.dim, C.panel)
    text(ix, top + 6, trunc("or move it into your inventory.", iw), C.dim, C.panel)
    text(ix, top + 8, trunc("Empty slot: see what fits from the", iw), C.dim, C.panel)
    text(ix, top + 9, trunc("ME network and put it on.", iw), C.dim, C.panel)
    return
  end
  local it = row.cells[sel.pos]
  sel.item = it and it.name or nil
  -- the slot number as listCurios counts it (from 0 or from 1)
  local slotNo = (row.raw and row.raw[sel.pos]) or (sel.pos - 1 + (row.base or 1))
  kv(ix, top + 3, iw, "Slot", prettify(row.name) .. " " .. sel.pos .. " of " .. row.count)
  local by = top + 6
  if it then
    kv(ix, top + 4, iw, "Worn", trunc(it.displayName or prettify(it.name), iw - 8))
    local n = tonumber(it.count) or 1
    if bridge then
      actButton(ix, by, iw, 3, "STORE IN ME", { kind = "cstore", name = it.name, count = n,
                                                 slotType = row.name, slotNo = slotNo }, true)
      by = by + 4
    end
    actButton(ix, by, iw, 3, "TO INVENTORY", { kind = "cunequip", name = it.name, count = n,
                                               slotType = row.name, slotNo = slotNo })
    text(ix, by + 4, "Tap twice to confirm.", C.dim, C.panel)
    return
  end

  kv(ix, top + 4, iw, "Worn", "nothing")
  if not bridge then
    text(ix, by, trunc("No ME Bridge: nothing to put on from it.", iw), C.dim, C.panel)
    return
  end
  text(ix, by, "FITS HERE (in the ME network)", C.label, C.panel)
  local me = state.me
  if not me or not me.items then
    text(ix, by + 2, "Reading the ME network...", C.dim, C.panel)
    return
  end
  local fits = {}
  for _, e in ipairs(me.items) do
    if e.curios and e.curios[row.name] and (e.count or 0) > 0 then fits[#fits + 1] = e end
  end
  table.sort(fits, function(a, b) return a.display:lower() < b.display:lower() end)
  if #fits == 0 then
    text(ix, by + 2, trunc("Nothing tagged curios:" .. row.name, iw), C.dim, C.panel)
    text(ix, by + 3, trunc("in the network.", iw), C.dim, C.panel)
    return
  end
  local per = math.max(1, math.floor((bottom - by - 3) / 2))
  local pages2 = math.max(1, math.ceil(#fits / per))
  state.curiosFitPage = math.max(1, math.min(state.curiosFitPage or 1, pages2))
  if pages2 > 1 then
    text(ix, bottom - 1, "page " .. state.curiosFitPage .. "/" .. pages2, C.dim, C.panel)
    drawButton(ix + iw - 17, bottom - 1, 8, 1, "< PREV", C.empty, C.text, "pg", { "curiosFitPage", -1 })
    drawButton(ix + iw - 8, bottom - 1, 8, 1, "NEXT >", C.empty, C.text, "pg", { "curiosFitPage", 1 })
  end
  local first = (state.curiosFitPage - 1) * per
  for k = 1, per do
    local e = fits[first + k]
    if not e then break end
    local ry = by + 2 + (k - 1) * 2
    text(ix, ry, trunc(e.display, iw - 12), C.text, C.panel)
    text(ix, ry + 1, compact(e.count) .. " in the network", C.dim, C.panel)
    actButton(ix + iw - 10, ry, 10, 2, "PUT ON", { kind = "cequip", name = e.name, count = 1,
                                                   slotType = row.name, slotNo = slotNo })
  end
end
