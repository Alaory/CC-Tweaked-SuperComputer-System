-- Part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.

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

function card(x, y, w, h, label)
  fill(x, y, w, h, C.panel)
  round(x, y, w, h, C.panel, C.bg)
  if label then
    if rounded() then px(x + 1, y + 1, 149, C.accent, C.panel) end  -- slim accent marker
    text(x + 2, y + 1, label, C.label, C.panel)
  end
end

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

function drawHeader()
  fill(1, 1, W, 3, C.panel)
  -- slim separator line under the header (rounded style only)
  if rounded() then text(1, 4, string.char(131):rep(W), C.head, C.bg) end

  local title = CONFIG.title:gsub(".", "%0 "):sub(1, -2)
  text(3, 2, "\4", C.accent, C.panel)
  text(5, 2, title, C.text, C.panel)
  text(5, 3, "Advanced Peripherals", C.dim, C.panel)

  -- page tabs: pills, the active one filled and underlined
  local tabs = { { "inventory", "INVENTORY" }, { "players", "PLAYERS" } }
  if invCaps.storage then tabs[#tabs + 1] = { "storage", "STORAGE" } end
  if invCaps.curios then tabs[#tabs + 1] = { "curios", "CURIOS" } end
  if bridge then tabs[#tabs + 1] = { "me", bridgeKind } end
  if #droneOrder > 0 then
    tabs[#tabs + 1] = { "drone", #droneOrder > 1 and ("DRONES " .. #droneOrder) or "DRONE" }
  end
  if chatBox then tabs[#tabs + 1] = { "access", "CHAT" } end
  if state.tModem or next(state.turtles) then tabs[#tabs + 1] = { "turtles", "TURTLES" } end
  if state.tModem or next(state.turtles) or MAP.hasData() then tabs[#tabs + 1] = { "map", "MAP" } end
  local tx = 50
  for _, t in ipairs(tabs) do
    local active = state.page == t[1]
    local lab = "  " .. t[2] .. "  "
    local bg = active and C.accent or C.empty
    text(tx, 2, lab, active and C.ink or C.text, bg)
    round(tx, 2, #lab, 1, bg, C.panel)
    if active and rounded() then text(tx, 4, string.char(131):rep(#lab), C.accent, C.bg) end
    addHit(tx, 1, #lab, 3, "page", t[1])
    tx = tx + #lab + 1
  end

  local owner = state.owner or "no player"
  local dot = state.status == "ok" and C.good or C.bad
  text(W - #owner - 2, 2, owner, C.text, C.panel)
  text(W - #owner - 4, 2, "\7", dot, C.panel)
  local t = textutils.formatTime(os.time(), true)
  text(W - #t - 2, 3, t, C.dim, C.panel)
end

function drawMessage(title, lines, col)
  local boxW = math.min(W - 6, 58)
  local n = 0
  for _, l in ipairs(lines) do n = n + #wrap(l, boxW - 4, 4) end
  local boxH = n + 4
  local bx = math.floor((W - boxW) / 2) + 1
  local by = math.floor((H - boxH) / 2) + 1
  card(bx, by, boxW, boxH)
  text(bx + 2, by + 1, title, col, C.panel)
  local row = 0
  for _, l in ipairs(lines) do
    for _, wl in ipairs(wrap(l, boxW - 4, 4)) do
      row = row + 1
      text(bx + 2, by + 1 + row, wl, C.text, C.panel)
    end
  end
end

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

function drawFooter()
  -- slim separator line above the footer (rounded style only)
  if rounded() then text(1, H - 1, string.char(143):rep(W), C.bg, C.head) end
  fill(1, H, W, 1, C.panel)
  local hint = {
    players = "Touch a player to see raw data",
    storage = "Contents of backpacks and other storage items",
    curios  = "Curios slots (rings, charms, backpacks, ...)",
    me      = "Select an item, then use the buttons (tap twice to confirm)",
    access  = "Who may use the $drone chat commands (REMOVE needs a second tap)",
    map     = "Tap the map to inspect a spot. SURVEY maps the area on screen (needs a Geo Scanner in the turtle)",
    turtles = "Select a turtle, then use the pad. On the computer:  turtle <id> goto x y z",
    drone   = "Pick a passenger + destination, then FERRY (tap twice). Type 'help' on the computer for coordinates",
  }
  if state.diskLow then
    text(3, H, trunc("  " .. state.diskLow .. "  ", W - 24), C.ink, C.bad)
  elseif state.toast and os.clock() < state.toast.exp then
    local m = "  " .. trunc(state.toast.msg, W - 24) .. "  "
    text(3, H, m, C.ink, state.toast.col)
    round(3, H, #m, 1, state.toast.col, C.panel)
  else
    text(3, H, hint[state.page] or "Touch an item to highlight it", C.dim, C.panel)
  end
  local msg, col = "\7 LIVE", C.good
  if state.status ~= "ok" then msg, col = "\7 OFFLINE", C.bad
  elseif state.dropped > 0 then msg, col = "\7 SLOT MISMATCH (see slotBase)", C.warn end
  text(W - #msg - 2, H, msg, col, C.panel)
end

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
