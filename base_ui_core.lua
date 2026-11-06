-- base_ui_core.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   Shared drawing pieces: header with the tabs, boxes, buttons, bars, pager,
--   footer (hints + toasts), the popup, and draw() which draws the visible tab.
--   A tab is only shown when its block is connected.

---------------------------------------------------------------------
-- DRAWING
---------------------------------------------------------------------
-- ---- design primitives -------------------------------------------------
-- ComputerCraft's characters 128-159 split a cell into 2x3 "pixels"; they are
-- used for rounded corners, pill shapes and thin bars.
function px(x, y, code, fg, bg)
  win.setCursorPos(x, y)
  win.setTextColor(fg)
  win.setBackgroundColor(bg)
  win.write(string.char(code))
end

-- is the "rounded" style on?
function rounded() return CONFIG.style == "rounded" end

-- round the corners of a box filled with `inner` that sits on `outer`
-- (only in the "rounded" style; "flat" keeps clean square blocks)
function round(x, y, w, h, inner, outer)
  if not rounded() then return end
  if w < 2 or h < 1 then return end
  if h == 1 then
    px(x, y, 145, outer, inner)              -- left: top + bottom pixel cut
    px(x + w - 1, y, 157, inner, outer)      -- right: top + bottom pixel cut
    return
  end
  px(x, y, 129, outer, inner)                -- top-left
  px(x + w - 1, y, 130, outer, inner)        -- top-right
  px(x, y + h - 1, 144, outer, inner)        -- bottom-left
  px(x + w - 1, y + h - 1, 159, inner, outer) -- bottom-right
end

-- a bar: solid ("flat") or thin, the lower two thirds of the row ("rounded")
function barW(x, y, w, filled, col, track)
  if w < 1 then return end
  filled = math.max(0, math.min(w, math.floor((tonumber(filled) or 0) + 0.5)))
  local ch = rounded() and string.char(131) or " "
  if filled > 0 then text(x, y, ch:rep(filled), C.panel, col) end
  if filled < w then text(x + filled, y, ch:rep(w - filled), C.panel, track or C.empty) end
end

-- the marker in front of a selected/highlighted row
function mark(x, y, col)
  if rounded() then px(x, y, 149, col, C.panel)
  else text(x, y, " ", C.text, col) end
end

-- a box (panel) with an optional title
function card(x, y, w, h, label)
  fill(x, y, w, h, C.panel)
  round(x, y, w, h, C.panel, C.bg)
  if label then
    if rounded() then px(x + 1, y + 1, 149, C.accent, C.panel) end  -- slim accent marker
    text(x + 2, y + 1, label, C.label, C.panel)
  end
end

-- make an area touchable (handled in base_input.lua)
function addHit(x, y, w, h, kind, value)
  hits[#hits + 1] = { x, y, x + w - 1, y + h - 1, kind, value }
end

-- one inventory slot
function drawCell(x, y, w, h, item, emptyLabel)
  if not item then
    fill(x, y, w, h, C.empty)
    round(x, y, w, h, C.empty, C.panel)
    if emptyLabel then
      local l = trunc(emptyLabel, w)
      text(x + math.floor((w - #l) / 2), y + math.floor((h - 1) / 2),
           l, C.dim, C.empty)
    end
    return
  end

  local selected = selName and item.name == selName
  local bg = selected and C.text or colorFor(item.name)
  fill(x, y, w, h, bg)
  round(x, y, w, h, bg, C.panel)

  local pad = w >= 10 and 1 or 0
  local tw = w - pad * 2
  local count = (item.count or 1) > 1 and compact(item.count) or nil
  local top = h >= 5 and 1 or 0

  -- durability bar on damaged tools (bottom row, only if no count is shown)
  local dur, durMax = durability(item)
  local showBar = dur and durMax and dur < durMax and not count and h >= 3
  if showBar then
    local f = dur / durMax
    local bc = f > 0.5 and C.good or (f > 0.2 and C.warn or C.bad)
    fill(x, y + h - 1, w, 1, C.ink)
    fill(x, y + h - 1, math.max(1, math.floor(f * w + 0.5)), 1, bc)
  end

  local maxLines = h - top - ((count or showBar) and 1 or 0)
  if maxLines >= 1 then
    local lines = wrap(item.displayName or item.name, tw, math.min(maxLines, 4))
    for i, l in ipairs(lines) do
      text(x + pad, y + top + i - 1, l, C.ink, bg)
    end
  end
  if count then
    text(x + w - #count - pad, y + h - 1, count, C.ink, bg)
  end
end

-- the pages there are: { page, label, badge, badge colour } (only when its block is there)
function pageTabs()
  local tabs = { { "inventory", "INVENTORY" } }
  local np = det and #(state.players or {}) or 0
  tabs[#tabs + 1] = { "players", "PLAYERS", np > 0 and tostring(np) or nil }
  if invCaps.storage then tabs[#tabs + 1] = { "storage", "STORAGE" } end
  if invCaps.curios then tabs[#tabs + 1] = { "curios", "CURIOS" } end
  if bridge then tabs[#tabs + 1] = { "me", bridgeKind } end
  if #droneOrder > 0 then
    tabs[#tabs + 1] = { "drone", #droneOrder > 1 and "DRONES" or "DRONE",
                        #droneOrder > 1 and tostring(#droneOrder) or nil }
  end
  if chatBox then
    local req = 0
    for _ in pairs(state.rideRequests or {}) do req = req + 1 end
    tabs[#tabs + 1] = { "access", "CHAT", req > 0 and tostring(req) or nil, req > 0 and C.warn or nil }
  end
  if state.tModem or next(state.turtles) then
    local on, all = 0, 0
    for _, t in pairs(state.turtles) do
      all = all + 1
      if TT.online(t) then on = on + 1 end
    end
    tabs[#tabs + 1] = { "turtles", "TURTLES", all > 0 and (on .. "/" .. all) or nil }
  end
  if state.tModem or next(state.turtles) or MAP.hasData() then tabs[#tabs + 1] = { "map", "MAP" } end
  if state.tModem or next(MINE.units) then
    local bad = false
    for _, u in pairs(MINE.units) do
      local lab = MINE.status(u)
      if lab == "STOPPED" or lab == "BLOCKED" or (lab == "OFFLINE" and u.seenEpoch) then bad = true end
    end
    tabs[#tabs + 1] = { "mining", "MINING", bad and "!" or nil, bad and C.warn or nil }
  end
  -- EVENTS: the number of new messages (red if one of them is an error)
  local unread = state.noteUnread or 0
  local anyErr = false
  for i = 1, math.min(unread, #state.noteLog) do
    if state.noteLog[i].col == C.bad then anyErr = true break end
  end
  tabs[#tabs + 1] = { "events", "EVENTS", unread > 0 and tostring(unread) or nil,
                      unread > 0 and (anyErr and C.bad or C.warn) or nil }
  -- SYSTEM: a dot when the base was off / crashed since you last looked
  local sysNew = (state.sysSeen or 0) < #SYSLOG and SYSLOG[1] and SYSLOG[1].kind ~= "INFO" and SYSLOG[1].kind ~= "DONE"
  tabs[#tabs + 1] = { "system", "STATUS", sysNew and "!" or nil, sysNew and C.warn or nil }
  tabs[#tabs + 1] = { "settings", "SETTINGS" }
  return tabs
end

-- the top row: pages GROUPED, so it fits on any monitor. A group with more
-- than one page shows its pages as a second row of small tabs (row 5).
local GROUPS = {
  { id = "you",     label = "YOU",     pages = { "inventory", "storage", "curios" } },
  { id = "people",  label = "PLAYERS", pages = { "players", "access" } },
  { id = "me",      label = nil,       pages = { "me" } },
  { id = "drone",   label = nil,       pages = { "drone" } },
  { id = "turtles", label = "TURTLES", pages = { "turtles", "map", "mining" } },
  { id = "system",  label = "SYSTEM",  pages = { "system", "events", "settings" } },
}
-- the group a page belongs to
function groupOf(page)
  for _, g in ipairs(GROUPS) do
    for _, p in ipairs(g.pages) do if p == page then return g.id end end
  end
end
function headerTabs()
  local byPage = {}
  for _, t in ipairs(pageTabs()) do byPage[t[1]] = t end
  local out = {}
  for _, g in ipairs(GROUPS) do
    local members = {}
    for _, p in ipairs(g.pages) do if byPage[p] then members[#members + 1] = byPage[p] end end
    if #members > 0 then
      -- the group's badge: the first member badge (a coloured one wins)
      local badge, bcol
      for _, m in ipairs(members) do
        if m[3] and (not badge or (m[4] and not bcol)) then badge, bcol = m[3], m[4] end
      end
      out[#out + 1] = { g.id, g.label or members[1][2], badge, bcol, members = members }
    end
  end
  return out
end

-- the title, the tabs, the owner and the clock
function drawHeader()
  fill(1, 1, W, 3, C.panel)

  local title = CONFIG.title:gsub(".", "%0 "):sub(1, -2)
  text(3, 2, "\4", C.accent, C.panel)
  text(5, 2, title, C.text, C.panel)
  text(5, 3, "Advanced Peripherals", C.dim, C.panel)

  -- right side: owner and clock
  local owner = state.owner or "no player"
  local ex = W - math.max(#owner + 4, 8) - 1
  local dot = state.status == "ok" and C.good or C.bad
  text(W - #owner - 2, 2, owner, C.text, C.panel)
  text(W - #owner - 4, 2, "\7", dot, C.panel)
  local t = textutils.formatTime(os.time(), true)
  text(W - #t - 2, 3, t, C.dim, C.panel)

  -- the tabs: full header height; the active one is filled and joins the page
  local tabs = headerTabs()
  local x0 = 5 + math.max(#title, 20) + 3
  local avail = ex - 2 - x0
  local function widthOf(t, pad, badges)
    local w = #t[2] + 2 * pad
    if badges and t[3] then w = w + #t[3] + 3 end
    return w
  end
  local pad, badges = 3, true
  local function total()
    local s = 0
    for _, t in ipairs(tabs) do s = s + widthOf(t, pad, badges) + 1 end
    return s - 1
  end
  -- too wide for the monitor: less padding, then no title, then no badges,
  -- then short names
  while total() > avail and pad > 1 do pad = pad - 1 end
  if total() > avail then
    x0 = 2
    avail = ex - 2 - x0
    fill(1, 1, ex - 1, 3, C.panel)                            -- hide the title
  end
  if total() > avail then badges = false end
  if total() > avail then
    for _, t in ipairs(tabs) do t[2] = t[2]:sub(1, 4) end
  end

  local tx = x0
  for _, t in ipairs(tabs) do
    local active = groupOf(state.page) == t[1]
    local w = widthOf(t, pad, badges)
    local bg = active and C.accent or C.head
    local fg = active and C.ink or C.text
    fill(tx, 1, w, 3, bg)
    round(tx, 1, w, 3, bg, C.panel)
    text(tx + pad, 2, t[2], fg, bg)
    if badges and t[3] then
      local bcol = t[4] or (active and C.ink or C.label)
      local bbg = active and C.label or C.empty
      if t[4] then bbg = t[4]; bcol = C.ink end
      text(tx + pad + #t[2] + 1, 2, " " .. t[3] .. " ", bcol, bbg)
    end
    -- the active tab runs into the page: a thin line in its colour under it
    if active then text(tx, 4, string.char(131):rep(w), C.accent, C.bg) end
    addHit(tx, 1, w, 3, "group", t[1])
    tx = tx + w + 1
  end
  -- the pages of the open group: small tabs on row 5
  for _, t in ipairs(tabs) do
    if groupOf(state.page) == t[1] and #t.members > 1 then
      local sx = 2
      for _, m in ipairs(t.members) do
        local on = state.page == m[1]
        local label = " " .. m[2] .. ((m[3] and m[3] ~= "") and (" " .. m[3]) or "") .. " "
        text(sx, 5, label, on and C.ink or C.text, on and C.label or (m[4] or C.empty))
        addHit(sx, 5, #label, 1, "page", m[1])
        sx = sx + #label + 1
      end
    end
  end
end

-- open a group: the page used last in it (or its first page)
function openGroup(id)
  for _, t in ipairs(headerTabs()) do
    if t[1] == id then
      local want = state.groupLast and state.groupLast[id]
      for _, m in ipairs(t.members) do if m[1] == want then return want end end
      return t.members[1][1]
    end
  end
end

-- a box in the middle with a title and text (loading, errors)
function drawMessage(title, lines, col)
  local boxW = math.min(W - 6, 64)
  -- every line is shown in full (up to 8 rows each), with a gap under the title
  local n = 0
  for _, l in ipairs(lines) do n = n + #wrap(l, boxW - 4, 8) end
  local boxH = math.min(H - 4, n + 5)
  local bx = math.floor((W - boxW) / 2) + 1
  local by = math.floor((H - boxH) / 2) + 1
  card(bx, by, boxW, boxH)
  text(bx + 2, by + 1, title, col, C.panel)
  local row = 0
  for _, l in ipairs(lines) do
    for _, wl in ipairs(wrap(l, boxW - 4, 8)) do
      row = row + 1
      if 2 + row < boxH - 1 then text(bx + 2, by + 2 + row, wl, C.text, C.panel) end
    end
  end
end

-- "Key ........ value" row
function kv(x, y, w, k, v, vcol)
  text(x, y, k, C.dim, C.panel)
  local gap = w - #k - #v - 2
  if gap > 0 then text(x + #k + 1, y, ("."):rep(gap), C.empty, C.panel) end  -- leader
  text(x + w - #v, y, v, vcol or C.text, C.panel)
end

-- small grey label with the value right underneath
function stat(x, y, w, label, value, vcol)
  text(x, y, trunc(label, w), C.dim, C.panel)
  text(x, y + 1, trunc(tostring(value), w), vcol or C.text, C.panel)
end

-- rounded label pill; returns its width
function pill(x, y, label, fg, bg, outer)
  local l = " " .. label .. " "
  text(x, y, l, fg, bg)
  round(x, y, #l, 1, bg, outer or C.panel)
  return #l
end

-- label + value at a fixed column
function field(x, y, label, value, col)
  text(x, y, label, C.dim, C.panel)
  text(x + 11, y, value, col or C.text, C.panel)
end

-- layout numbers shared by all cards
function geometry()
  local G = {}
  G.y0, G.y1 = 6, H - 2
  G.bodyH = G.y1 - G.y0 + 1
  G.leftW = math.floor((W - 3) * 0.64)
  G.pitch = math.max(3, math.floor((G.leftW - 2) / 9))
  G.cw = G.pitch - 1
  local ch = math.floor(G.cw * 0.95)
  ch = math.min(ch, math.floor((G.bodyH - 26) / 5))
  G.ch = math.max(3, ch)
  G.backH = 4 * G.ch + 9
  G.equipH = math.max(G.ch + 4, 11)
  G.detailH = G.bodyH - G.backH - 1 - G.equipH - 1
  return G
end

-- a touchable button
function drawButton(x, y, w, h, label, bg, fg, kind, value)
  fill(x, y, w, h, bg)
  round(x, y, w, h, bg, C.panel)
  local l = trunc(label, (w >= #label + 2) and w - 2 or w)
  text(x + math.floor((w - #l) / 2), y + math.floor((h - 1) / 2), l, fg, bg)
  addHit(x, y, w, h, kind, value)
end

-- action button with a two-tap confirmation
function actButton(x, y, w, h, label, act, primary)
  act.key = act.kind .. ":" .. act.name .. ":" .. act.count
  local pend = state.pending and state.pending.key == act.key
               and os.clock() < state.pending.exp
  if pend then
    drawButton(x, y, w, h, "CONFIRM?", C.warn, C.ink, "act", act)
  else
    drawButton(x, y, w, h, label, primary and C.accent or C.empty,
               primary and C.ink or C.text, "act", act)
  end
end

-- PREV / NEXT buttons for a list with several pages
function drawPager(y0, key, pages, xr)
  if pages <= 1 then return end
  local pl = string.format("PAGE %d/%d", state[key], pages)
  local bx = (xr or W) - #pl - 20
  text(bx, y0, " < PREV ", C.ink, C.accent)
  addHit(bx, y0, 8, 1, "pg", { key, -1 })
  text(bx + 9, y0, pl, C.text, C.bg)
  text(bx + 10 + #pl, y0, " NEXT > ", C.ink, C.accent)
  addHit(bx + 10 + #pl, y0, 8, 1, "pg", { key, 1 })
end

-- one row: item name left, value right, coloured bar behind the text
-- a list row: colour marker, name, amount bar (own column), number.
-- frac = amount / largest amount; shown on a compressed scale so small
-- amounts stay visible next to huge ones.
function drawBarRow(x, y, w, name, vs, frac, col, selected, numW)
  local bg = selected and C.head or C.panel
  numW = math.max(#vs, numW or 16)                            -- same for every row: bars line up
  text(x, y, (" "):rep(w), C.text, bg)
  text(x, y, " ", C.text, col)                                -- colour marker
  local bw = math.max(6, math.floor(w * 0.16))                -- the bar column
  local nameW = math.max(4, w - 3 - bw - numW - 2)
  text(x + 2, y, trunc(name, nameW), selected and C.accent or C.text, bg)
  local bx = x + w - numW - 2 - bw
  local f = math.max(0, math.min(1, tonumber(frac) or 0)) ^ 0.35
  barW(bx, y, bw, math.max(1, math.floor(f * bw + 0.5)), col, C.empty)
  text(x + w - #vs - 1, y, vs, selected and C.text or C.dim, bg)   -- right-aligned
end

-- scroll buttons in a card's title row; returns the clamped offset
function scrollBar(x, y, w, key, total, rows)
  local maxOff = math.max(0, total - rows)
  local off = math.max(0, math.min(state[key] or 0, maxOff))
  state[key] = off
  if maxOff > 0 then
    local info = string.format("%d-%d of %d", off + 1, math.min(off + rows, total), total)
    local bx = x + w - 2 - 11
    text(bx - #info - 1, y, info, C.dim, C.panel)
    drawButton(bx, y, 5, 1, " \30 ", off > 0 and C.accent or C.empty,
               off > 0 and C.ink or C.dim, "dscroll", { key, -rows })
    drawButton(bx + 6, y, 5, 1, " \31 ", off < maxOff and C.accent or C.empty,
               off < maxOff and C.ink or C.dim, "dscroll", { key, rows })
  end
  return off
end

-- the bottom line: hint, toast or disk warning, LIVE status (+ the popup)
function drawFooter()
  -- slim separator line above the footer (rounded style only)
  if rounded() then text(1, H - 1, string.char(143):rep(W), C.bg, C.head) end
  fill(1, H, W, 1, C.panel)
  local hint = {
    players = "Touch a player to see raw data",
    storage = "Contents of backpacks and other storage items",
    curios  = "Tap a slot: store a worn item in ME / move it to your inventory, or put on what fits from ME (tap twice)",
    me      = "Select an item, then use the buttons (tap twice to confirm)",
    access  = "Who may use the $drone chat commands (REMOVE needs a second tap)",
    map     = "Tap the map to inspect a spot. SURVEY maps the area on screen (needs a Geo Scanner in the turtle)",
    turtles = "Select a turtle, then use the pad. On the computer:  turtle <id> goto x y z",
    drone   = "Pick a passenger + destination, then FERRY (tap twice). Type 'help' on the computer for coordinates",
    events  = "Every message, newest first. Tap a filter to show one kind only",
    system  = "How the base is doing. The SYSTEM LOG keeps system things only (not pushed out by everyday messages)",
    settings = "Pick a group on the left, then tap - / + or the value. RESET = back to base_config.lua",
    mining = "START / PAUSE reach the miner at its next report (up to 30 s). Unload interval: SETTINGS > MINING",
  }
  if state.diskLow then
    text(3, H, trunc("  " .. state.diskLow .. "  ", W - 24), C.ink, C.bad)
  else
    text(3, H, hint[state.page] or "Touch an item to highlight it", C.dim, C.panel)
  end
  local msg, col = "\7 LIVE", C.good
  if state.status ~= "ok" then msg, col = "\7 OFFLINE", C.bad
  elseif state.dropped > 0 then msg, col = "\7 SLOT MISMATCH (see slotBase)", C.warn end
  text(W - #msg - 2, H, msg, col, C.panel)
  drawNotes()
end

-- the message boxes (pushNote), stacked top-right under the tabs. A tap on a
-- box closes it; each also closes by itself (the bar at its bottom shows the
-- time left).
function drawNotes()
  local now = os.clock()
  for i = #state.notes, 1, -1 do
    local n = state.notes[i]
    if n.exp and now >= n.exp then table.remove(state.notes, i) end
  end
  if #state.notes == 0 or state.page == "events" then return end
  local nw = math.min(56, math.max(36, math.floor(W * 0.3)))
  local x = W - nw - 1
  -- where: at the BOTTOM (default - away from what you read most) or the top
  local atTop = CONFIG.notes and CONFIG.notes.where == "top"
  local maxBoxes = 3

  -- which boxes fit (always at least the newest one), newest nearest the edge
  local list, used = {}, 0
  local room = H - 10
  for _, n in ipairs(state.notes) do
    if #list >= maxBoxes then break end
    local lines = wrap(n.msg, nw - 6, 3)
    local h = #lines + 3
    if used + h + 1 > room and #list > 0 then break end
    list[#list + 1] = { n = n, lines = lines, h = h }
    used = used + h + 1
  end
  local more = #state.notes - #list
  local footer = (more > 0 or #state.notes > 1)
  local top, y
  if atTop then
    top = 6
    y = top
    for _, b in ipairs(list) do b.y = y y = y + b.h + 1 end
  else
    -- stacked upward from just above the footer line
    local base = H - 2 - (footer and 1 or 0)
    y = base + 1
    for _, b in ipairs(list) do b.y = y - b.h y = b.y - 1 end
    top = y + 1
    y = base + 2                         -- the "+N more / CLOSE ALL" row goes under the boxes
  end

  -- solid backing, so the page behind does not show between the boxes
  local backH = atTop and ((y - top) + (footer and 1 or 0)) or (H - 1 - top)
  fill(x - 1, top - 1, nw + 2, backH + 1, C.bg)

  for _, b in ipairs(list) do
    local n, by, h = b.n, b.y, b.h
    fill(x, by, nw, h, C.empty)
    round(x, by, nw, h, C.empty, C.bg)
    fill(x, by, 1, h, n.col)                                  -- coloured stripe
    local kind = noteKind(n.col)
    text(x + 2, by, " " .. kind .. " ", C.ink, n.col)
    local title = n.title and trunc(n.title, nw - #kind - 16) or ""
    text(x + #kind + 5, by, title, C.text, C.empty)
    local right = n.when .. ((n.times and n.times > 1) and (" x" .. n.times) or "")
    text(x + nw - #right - 5, by, right, C.dim, C.empty)
    text(x + nw - 3, by, " x ", C.text, C.panel)              -- close mark
    for k, l in ipairs(b.lines) do text(x + 2, by + 1 + k, l, C.text, C.empty) end
    if n.exp and n.life and n.life > 0 then                    -- time left: a thin bar
      local left = math.max(0, math.min(1, (n.exp - now) / n.life))
      local bw = math.floor((nw - 1) * left + 0.5)
      if bw > 0 then text(x + 1, by + h - 1, string.char(143):rep(bw), C.empty, n.col) end
    end
    addHit(x, by, nw, h, "ndismiss", n.id)                    -- tap the box = close it
  end

  if footer then
    if more > 0 then text(x, y - 1, "+" .. more .. " more", C.dim, C.bg) end
    local ca = " CLOSE ALL "
    text(x + nw - #ca, y - 1, ca, C.text, C.head)
    addHit(x + nw - #ca, y - 1, #ca, 1, "nclear")
  end
end

-- draw the whole screen for the visible tab
function draw()
  win.setVisible(false)
  hits = {}
  win.setBackgroundColor(C.bg)
  win.clear()
  drawHeader()

  local G = geometry()

  if W < 100 or G.bodyH < 36 then
    drawMessage("MONITOR TOO SMALL",
      { "Use a bigger monitor, or set textScale to 0.5 in CONFIG." }, C.warn)
  elseif state.page == "players" then
    drawPlayersPage(G)
  elseif state.page == "me" then
    drawMEPage(G)
  elseif state.page == "drone" then
    drawDronePage(G)
  elseif state.page == "access" then
    drawAccessPage(G)
  elseif state.page == "turtles" then
    drawTurtlesPage(G)
  elseif state.page == "map" then
    drawMapPage(G)
  elseif state.page == "mining" then
    drawMiningPage(G)
  elseif state.page == "events" then
    drawEventsPage(G)
  elseif state.page == "system" then
    state.sysSeen = #SYSLOG
    drawSystemPage(G)
  elseif state.page == "settings" then
    drawSettingsPage(G)
  elseif state.status == "nocard" then
    drawMessage("NO PLAYER LINKED",
      { "Bind a Memory Card to yourself (right-click with it),",
        "then put it into the Inventory Manager." }, C.warn)
  elseif state.status == "offline" then
    drawMessage("PLAYER UNAVAILABLE",
      { "Could not read the inventory of " .. (state.owner or "the owner") .. ".",
        "Error: " .. tostring(state.err) }, C.bad)
  elseif state.status == "loading" then
    drawMessage("LOADING", { "Reading inventory..." }, C.label)
  else
    if state.page == "storage" then
      drawStoragePage(G)
      drawFooter()
      flushWindow()
      return
    elseif state.page == "curios" then
      drawCuriosPage(G)
      drawFooter()
      flushWindow()
      return
    end

    local lx, leftW = 2, G.leftW
    local rx = lx + leftW + 1
    local rw = W - rx

    drawBackpack(lx, G.y0, leftW, G.backH, G)

    local ey = G.y0 + G.backH + 1
    local eqW = G.pitch * 5 + 3
    drawEquip(lx, ey, eqW, G.equipH, G)
    drawOverview(lx + eqW + 1, ey, leftW - eqW - 1, G.equipH)

    drawDetail(lx, ey + G.equipH + 1, leftW, G.detailH)
    if det then
      local ph = (state.player and state.player.airSupply) and 14 or 11
      drawPlayer(rx, G.y0, rw, ph)
      drawList(rx, G.y0 + ph + 1, rw, G.bodyH - ph - 1)
    else
      drawList(rx, G.y0, rw, G.bodyH)
    end
  end

  drawFooter()
  flushWindow()
end
