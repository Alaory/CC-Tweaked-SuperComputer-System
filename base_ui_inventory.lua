-- base_ui_inventory.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   INVENTORY (CONTROL ROOM look): your backpack, hotbar, armour + offhand as sunken
--   slots (an item's colour as a stripe, the count in amber), how full you are; the item
--   list with amount gauges and SORT; DETAILS of the picked item with SEND > AE2.

function drawBackpack(x, y, w, h, G)
  local frac = (state.used or 0) / 36
  local fcol = frac < 0.6 and C.good or (frac < 0.85 and C.warn or C.bad)
  local ix, iy, iw = panel(x, y, w, h, "INVENTORY", { right = (state.used or 0) .. " / 36 slots", rcol = fcol })
  local pitch, cw, ch = G.pitch, G.cw, G.ch
  local gridW = pitch * 9 - 1
  local gx = x + 1 + math.floor((w - 2 - gridW) / 2)
  local gy = iy
  for row = 0, 2 do
    local cy = gy + row * (ch + 1)
    for col = 0, 8 do
      local idx = 9 + row * 9 + col
      local cx = gx + col * pitch
      local it = state.slots[idx]
      drawCell(cx, cy, cw, ch, it)
      addHit(cx, cy, cw, ch, "item", it and it.name)
    end
  end
  local hy = gy + 3 * (ch + 1) + 1
  heading(gx, hy, gridW, "HOTBAR")
  hy = hy + 1
  for col = 0, 8 do
    local cx = gx + col * pitch
    local it = state.slots[col]
    drawCell(cx, hy, cw, ch, it, tostring(col + 1))
    if state.heldIdx == col then frame(cx, hy, cw, ch, C.accent, C.bg) end      -- the item in your hand
    addHit(cx, hy, cw, ch, "item", it and it.name)
  end
  local ay = hy + ch + 1
  heading(gx, ay, gridW, "ARMOUR + OFFHAND")
  ay = ay + 1
  local labels = { "HELM", "CHEST", "LEGS", "BOOTS", "OFFHAND" }
  for i = 1, 5 do
    local cx = gx + (i - 1 + (i == 5 and 1 or 0)) * pitch
    local it = state.equip[i]
    drawCell(cx, ay, cw, ch, it, labels[i])
    addHit(cx, ay, cw, ch, "item", it and it.name)
  end
  -- how full: on the right of the armour row (big number + gauge)
  local bx = gx + 7 * pitch
  local bw = gridW - 7 * pitch
  if bw >= 8 then
    local free = tostring(36 - (state.used or 0))
    local nw = big(bx, ay, free, fcol, C.panel)
    if bw - nw - 1 >= 4 then text(bx + nw + 1, ay + 1, "free", C.dim, C.panel) end
    if ch >= 3 then gauge(bx, ay + ch - 1, bw, frac, fcol) end
  end
end

-- the item list with the SORT button
function drawList(x, y, w, h)
  local list = state.list or {}
  local ix, iy, iw, ih = panel(x, y, w, h, "ITEMS", { right = #list .. " kinds" })
  local label = "SORT: " .. tostring(sortMode):upper()
  button(ix + iw - #label - 4, iy, #label + 4, 2, label, C.line, "sort")
  local top = iy + 3
  local avail = (y + h - 2) - top + 1
  -- 2 = name + gauge row, 1 = compact (name + gauge on one row)
  local pitch = (#list * 2 <= avail) and 2 or 1
  local maxItems = (pitch == 2) and #list or math.min(#list, avail)
  local more = 0
  if pitch == 1 and #list > avail then maxItems = avail - 1 more = #list - maxItems end
  local maxCount = 1
  for _, t in ipairs(list) do if t.count > maxCount then maxCount = t.count end end
  if #list == 0 then text(ix, top, "Nothing in your inventory.", C.dim, C.panel) end
  for i = 1, maxItems do
    local t = list[i]
    local ry = top + (i - 1) * pitch
    local sel = selName == t.name
    local col = colorFor(t.name)
    local vs = commas(t.count)
    if pitch == 2 then
      local bg = sel and C.line or C.panel
      if sel then fill(ix, ry, iw, 2, C.line) end
      cell(ix, ry, 1 + 4 + 16, sel and C.accent or col, bg)
      cell(ix, ry + 1, 1 + 4 + 16, sel and C.accent or col, bg)
      text(ix + 2, ry, trunc(t.display, iw - #vs - 4), sel and C.accent or C.text, bg)
      text(ix + iw - #vs, ry, vs, C.label, bg)
      gauge(ix + 2, ry + 1, iw - 2, (t.count / maxCount) ^ 0.5, col, bg)
      addHit(ix, ry, iw, 2, "item", t.name)
    else
      drawBarRow(ix, ry, iw, t.display, vs, t.count / maxCount, col, sel, 8)
      addHit(ix, ry, iw, 1, "item", t.name)
    end
  end
  if more > 0 then text(ix, top + maxItems, "+" .. more .. " more...", C.dim, C.panel) end
end

-- details of the selected item
function drawDetail(x, y, w, h)
  local t
  for _, e in ipairs(state.list or {}) do if e.name == selName then t = e break end end
  local ix, iy, iw, ih = panel(x, y, w, h, "DETAILS")
  if not t then
    text(ix, iy, "Tap an item to look at it.", C.dim, C.panel)
    return
  end
  local bwid = bridge and 26 or 0
  local textW = iw - (bwid > 0 and bwid + 2 or 0)
  local col = colorFor(t.name)
  cell(ix, iy, 1 + 4 + 16, col, C.panel)
  cell(ix, iy + 1, 1 + 4 + 16, col, C.panel)
  text(ix + 2, iy, trunc(t.display, textW - 2), C.text, C.panel)
  text(ix + 2, iy + 1, trunc(t.name, textW - 2), C.dim, C.panel)
  local nw = big(ix, iy + 3, compact(t.count), C.label, C.panel)
  text(ix + nw + 1, iy + 4, "in " .. #t.slots .. " stack(s)", C.dim, C.panel)
  local sl = {}
  for _, sIdx in ipairs(t.slots) do sl[#sl + 1] = tostring(sIdx + 1) end
  local r = iy + 6
  kv(ix, r, textW, "Total", commas(t.count)) r = r + 1
  kv(ix, r, textW, "In slots", table.concat(sl, ", ")) r = r + 1
  if t.max then kv(ix, r, textW, "Max stack", tostring(t.max)) r = r + 1 end
  local dur, durMax = durability(t.sample or {})
  if dur and durMax and r + 1 <= y + h - 2 then
    local f = dur / durMax
    meter(ix, r, textW, "Durability", commas(dur) .. " / " .. commas(durMax), f, f > 0.5 and C.good or (f > 0.2 and C.warn or C.bad))
    r = r + 2
  end
  if (state.total or 0) > 0 and r + 1 <= y + h - 2 then
    local share = t.count / state.total
    meter(ix, r, textW, "Share of your items", math.floor(share * 100 + 0.5) .. "%", share, col)
  end
  if bridge then
    local bx = ix + iw - bwid
    local stack = math.min(t.count, t.max or 64)
    local bh = (ih >= 12) and 3 or 2
    local step = bh + 1
    actButton(bx, iy, bwid, bh, "SEND x1 > " .. bridgeKind, { kind = "send", name = t.name, count = 1 }, false, C.purple)
    actButton(bx, iy + step, bwid, bh, "SEND STACK > " .. bridgeKind, { kind = "send", name = t.name, count = stack }, false, C.purple)
    actButton(bx, iy + 2 * step, bwid, bh, "SEND ALL > " .. bridgeKind, { kind = "send", name = t.name, count = t.count }, false, C.purple)
  end
end
