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
  local equipped = 0
  for _, row in ipairs(rows) do
    for _ in pairs(row.cells) do equipped = equipped + 1 end
  end
  local title = string.format("CURIOS: %d slot types, %d equipped", #rows, equipped)
  if state.curiosNote then title = string.format("CURIOS: %d slot types", #rows) end
  text(2, y0, title, C.label, C.bg)
  if state.curiosNote then
    text(2 + #title + 3, y0, state.curiosNote, C.warn, C.bg)
  end

  local n = #rows
  local avail = G.bodyH - 2
  local cardH = math.max(4, math.min(10, math.floor((avail + 1) / n) - 1))
  local cellH = cardH - 2
  local labelW, pitch, cw = 18, 15, 14
  local maxCells = math.floor((W - 2 - labelW - 3) / pitch)

  for i, row in ipairs(rows) do
    local cy = y0 + 2 + (i - 1) * (cardH + 1)
    if cy + cardH - 1 > G.y1 then break end
    card(2, cy, W - 2, cardH)
    text(4, cy + 1, prettify(row.name):upper(), C.label, C.panel)
    text(4, cy + 2, row.count .. (row.count == 1 and " slot" or " slots"), C.dim, C.panel)
    if row.stale and cardH >= 4 then text(4, cy + 3, "last known", C.warn, C.panel) end
    for pos = 1, math.min(row.count, maxCells) do
      local it = row.cells[pos]
      drawCell(2 + labelW + (pos - 1) * pitch, cy + 1, cw, cellH, it,
               row.unreadable and "?" or "empty")
    end
  end
end
