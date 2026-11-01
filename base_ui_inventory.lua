-- Part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.

-- page drawing
function drawBackpack(x, y, w, h, G)
  card(x, y, w, h)
  text(x + 2, y + 1, "BACKPACK", C.label, C.panel)
  local info = state.used .. " / 36 slots"
  text(x + w - #info - 2, y + 1, info, C.dim, C.panel)

  local pitch, cw, ch = G.pitch, G.cw, G.ch
  local gridW = pitch * 9 - 1
  local gx = x + 1 + math.floor((w - 2 - gridW) / 2)
  local gy = y + 3

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

  local hy = gy + 3 * (ch + 1) + 2
  text(gx, hy - 2, "HOTBAR", C.label, C.panel)
  if state.heldIdx then
    fill(gx + state.heldIdx * pitch, hy - 1, cw, 1, C.accent)
  end
  for col = 0, 8 do
    local cx = gx + col * pitch
    local it = state.slots[col]
    drawCell(cx, hy, cw, ch, it, tostring(col + 1))
    addHit(cx, hy, cw, ch, "item", it and it.name)
  end
end

function drawEquip(x, y, w, h, G)
  card(x, y, w, h, "EQUIPMENT")
  local labels = { "Helm", "Chest", "Legs", "Boots", "Offhand" }
  local sx = x + 1 + math.floor((w - 2 - (G.pitch * 5 - 1)) / 2)
  for i = 1, 5 do
    local cx = sx + (i - 1) * G.pitch
    local it = state.equip[i]
    drawCell(cx, y + 3, G.cw, G.ch, it, labels[i])
    addHit(cx, y + 3, G.cw, G.ch, "item", it and it.name)
  end
end

function drawOverview(x, y, w, h)
  card(x, y, w, h, "OVERVIEW")
  local ix, iw = x + 2, w - 4
  local frac = state.used / 36
  local col = frac < 0.6 and C.good or (frac < 0.85 and C.warn or C.bad)
  local s = h >= 12 and 2 or 1

  kv(ix, y + 3, iw, "Slots used", state.used .. "/36")
  barW(ix, y + 4, iw, math.floor(frac * iw + 0.5), col)
  local r = y + 4 + s
  kv(ix, r, iw, "Free slots", tostring(36 - state.used))
  kv(ix, r + s, iw, "Total items", commas(state.total))
  kv(ix, r + 2 * s, iw, "Unique types", tostring(#state.list))
end

function drawList(x, y, w, h)
  card(x, y, w, h, "ITEMS")
  local label = "SORT: " .. sortMode:upper()
  local bx = x + w - #label - 4
  text(bx, y + 1, " " .. label .. " ", C.ink, C.accent)
  addHit(bx, y + 1, #label + 2, 1, "sort")

  local ix, iw = x + 2, w - 4
  local list = state.list
  local avail = h - 4

  -- 3 = name row + bar row + gap, 2 = bar behind text + gap, 1 = compact
  local pitch = 1
  if #list * 3 - 1 <= avail then pitch = 3
  elseif #list * 2 - 1 <= avail then pitch = 2 end

  local maxItems = pitch > 1 and #list or avail
  local more = 0
  if pitch == 1 and #list > avail then
    maxItems = avail - 1
    more = #list - maxItems
  end

  local maxCount = 1
  for _, t in ipairs(list) do if t.count > maxCount then maxCount = t.count end end

  for i = 1, math.min(maxItems, #list) do
    local t = list[i]
    local ry = y + 3 + (i - 1) * pitch
    local sel = selName == t.name
    local col = sel and C.text or colorFor(t.name)
    local vs = commas(t.count)
    local n = math.max(1, math.floor(t.count / maxCount * iw + 0.5))

    if pitch == 3 then
      fill(ix, ry, 1, 1, col)                                   -- swatch
      text(ix + 2, ry, trunc(t.display, iw - #vs - 4), C.text, C.panel)
      text(ix + iw - #vs, ry, vs, col, C.panel)
      barW(ix, ry + 1, iw, n, col)
      addHit(ix, ry, iw, 2, "item", t.name)
    else
      local str = " " .. trunc(t.display, iw - #vs - 2)
      str = str .. (" "):rep(iw - #str - #vs - 1) .. vs .. " "
      text(ix, ry, str:sub(1, n), C.ink, col)
      if n < iw then text(ix + n, ry, str:sub(n + 1), C.text, C.empty) end
      addHit(ix, ry, iw, 1, "item", t.name)
    end
  end

  if more > 0 then
    text(ix, y + 3 + maxItems, "+ " .. more .. " more...", C.dim, C.panel)
  end
end

function drawDetail(x, y, w, h)
  card(x, y, w, h, "DETAILS")
  local ix, iw = x + 2, w - 4
  local t
  for _, e in ipairs(state.list) do if e.name == selName then t = e break end end

  if not t then
    local msg = "Touch an item to inspect it"
    text(x + math.floor((w - #msg) / 2), y + math.floor(h / 2),
         msg, C.dim, C.panel)
    return
  end

  local textW = bridge and (iw - 28) or iw
  text(ix, y + 3, trunc(t.display, textW), colorFor(t.name), C.panel)
  text(ix, y + 4, trunc(t.name, textW), C.dim, C.panel)

  local sl = {}
  for _, sIdx in ipairs(t.slots) do sl[#sl + 1] = tostring(sIdx + 1) end

  local fields = {
    { "Total", commas(t.count) },
    { "Stacks", tostring(#t.slots) },
    { "In slots", trunc(table.concat(sl, ", "), textW - 11) },
  }
  if t.max then fields[#fields + 1] = { "Max stack", tostring(t.max) } end
  local dur, durMax = durability(t.sample or {})
  if dur and durMax then
    fields[#fields + 1] = { "Durability",
      string.format("%s / %s  (%d%%)", commas(dur), commas(durMax),
                    math.floor(dur / durMax * 100 + 0.5)) }
  end

  local r = y + 6
  local n = #fields
  local step = (r + n * 2 <= y + h - 2) and 2 or 1
  for i, f in ipairs(fields) do
    field(ix, r + (i - 1) * step, f[1], f[2])
  end

  if bridge then
    local bw = 24
    local bx = x + w - bw - 2
    local stack = math.min(t.count, t.max or 64)
    local bh = h >= 16 and 3 or 2
    actButton(bx, y + 3, bw, bh, "SEND x1 > " .. bridgeKind, { kind = "send", name = t.name, count = 1 })
    actButton(bx, y + 4 + bh, bw, bh, "SEND STACK > " .. bridgeKind, { kind = "send", name = t.name, count = stack })
    actButton(bx, y + 5 + 2 * bh, bw, bh, "SEND ALL > " .. bridgeKind, { kind = "send", name = t.name, count = t.count })
  end

  local sy = r + n * step
  if sy <= y + h - 2 and state.total > 0 then
    local share = t.count / state.total
    local bw = math.min(30, iw - 20)
    text(ix, sy, "Share", C.dim, C.panel)
    barW(ix + 11, sy, bw, math.max(1, math.floor(share * bw + 0.5)), colorFor(t.name))
    text(ix + 12 + bw, sy, string.format("%d%%", math.floor(share * 100 + 0.5)),
         C.text, C.panel)
  end
end
