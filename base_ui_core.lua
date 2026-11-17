-- base_ui_core.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   The CONTROL ROOM kit (rules in CLAUDE.md "UI rules"): panels with thin frames,
--   buttons, gauges, lights, badges, big numbers, key / value rows, lists, slots;
--   the header (group tabs, page tabs, clock), the footer, message boxes and draw(),
--   which draws the open page. A page is only listed when its block is connected.
--   Every panel() clips what is drawn inside it (base_theme.lua clip / text / fill):
--   nothing runs out of its box.

---------------------------------------------------------------------
-- SUB-PIXELS
---------------------------------------------------------------------
-- ComputerCraft's characters 128-159 split a cell into 2 x 3 "pixels":
--   1 = top left, 2 = top right, 4 = middle left, 8 = middle right, 16 = bottom left,
--   32 = bottom right (32 is drawn by swapping the colours). Thin lines, gauges,
--   lights and the big font are made of them.
function cell(x, y, bits, fg, bg)
  if bits >= 32 then bits, fg, bg = 63 - bits, bg, fg end
  text(x, y, string.char(128 + bits), fg, bg)
end
function px(x, y, code, fg, bg) text(x, y, string.char(code), fg, bg) end
function rounded() return CONFIG.style ~= "plain" end
local TOP, MID, BOT = 1 + 2, 4 + 8, 16 + 32
local LEFT, RIGHT = 1 + 4 + 16, 2 + 8 + 32
-- a hairline across: "top", "mid" (default) or "bot" of the cell row
function hline(x, y, w, col, bg, where)
  local b = (where == "top" and TOP) or (where == "bot" and BOT) or MID
  if w < 1 then return end
  if b >= 32 then text(x, y, string.char(128 + 63 - b):rep(w), bg, col)
  else text(x, y, string.char(128 + b):rep(w), col, bg) end
end
-- a thin outline: the frame sits on the OUTER pixels of the box
function frame(x, y, w, h, col, bg)
  if w < 2 or h < 2 or CONFIG.style == "plain" then return end
  hline(x + 1, y, w - 2, col, bg, "top")
  hline(x + 1, y + h - 1, w - 2, col, bg, "bot")
  for j = y + 1, y + h - 2 do
    cell(x, j, LEFT, col, bg)
    cell(x + w - 1, j, RIGHT, col, bg)
  end
  cell(x, y, 1 + 2 + 4 + 16, col, bg)                  -- (corners: the two lines together)
  cell(x + w - 1, y, 1 + 2 + 8 + 32, col, bg)
  cell(x, y + h - 1, 1 + 4 + 16 + 32, col, bg)
  cell(x + w - 1, y + h - 1, 2 + 8 + 16 + 32, col, bg)
end
-- old names (the Block UI look): no-ops now
function round() end
function inset() end
function outline(x, y, w, h, inner, edge) frame(x, y, w, h, edge or C.line, inner or C.panel) end

---------------------------------------------------------------------
-- BIG NUMBERS (3 x 5 pixel font: 2 cells wide, 2 rows tall per character)
---------------------------------------------------------------------
local FONT = {
  ["0"] = "### #.# #.# #.# ###", ["1"] = ".#. ##. .#. .#. ###", ["2"] = "### ..# ### #.. ###",
  ["3"] = "### ..# .## ..# ###", ["4"] = "#.# #.# ### ..# ..#", ["5"] = "### #.. ### ..# ###",
  ["6"] = "### #.. ### #.# ###", ["7"] = "### ..# .#. .#. .#.", ["8"] = "### #.# ### #.# ###",
  ["9"] = "### #.# ### ..# ###", A = "### #.# ### #.# #.#", B = "##. #.# ##. #.# ##.",
  C = "### #.. #.. #.. ###", D = "##. #.# #.# #.# ##.", E = "### #.. ##. #.. ###",
  F = "### #.. ##. #.. #..", G = "### #.. #.# #.# ###", H = "#.# #.# ### #.# #.#",
  I = "### .#. .#. .#. ###", J = "..# ..# ..# #.# ###", K = "#.# #.# ##. #.# #.#",
  L = "#.. #.. #.. #.. ###", M = "#...# ##.## #.#.# #...# #...#", N = "#...# ##..# #.#.# #..## #...#",
  O = "### #.# #.# #.# ###", P = "### #.# ### #.. #..", Q = "### #.# #.# ### ..#",
  R = "##. #.# ##. #.# #.#", S = "### #.. ### ..# ###", T = "### .#. .#. .#. .#.",
  U = "#.# #.# #.# #.# ###", V = "#.# #.# #.# #.# .#.", W = "#...# #...# #.#.# ##.## #...#",
  X = "#.# #.# .#. #.# #.#", Y = "#.# #.# .#. .#. .#.", Z = "### ..# .#. #.. ###",
  [" "] = "... ... ... ... ...", ["/"] = "..# ..# .#. #.. #..", ["%"] = "#.# ..# .#. #.. #.#",
  [":"] = "... .#. ... .#. ...", ["."] = "... ... ... ... .#.", [","] = "... ... ... .#. #..",
  ["-"] = "... ... ### ... ...", ["+"] = "... .#. ### .#. ...", ["!"] = ".#. .#. .#. ... .#.",
  ["?"] = "### ..# .## ... .#.", ["#"] = "#.# ### #.# ### #.#", ["x"] = "... #.# .#. #.# ...",
}
for k, v in pairs(FONT) do
  local rows = {}
  for r in v:gmatch("%S+") do rows[#rows + 1] = r end
  FONT[k] = rows
end
-- a glyph's width in cells: 3 pixels wide = 2 cells, 5 pixels (M N W) = 3 cells
-- (always one free pixel column after it)
local function glyphOf(ch)
  return FONT[ch] or FONT[ch:upper()] or FONT["?"]
end
local function cellsOf(g) return math.floor(#g[1] / 2) + 1 end
-- width of big text in cells
function bigW(s)
  s = tostring(s)
  local n = 0
  for i = 1, #s do n = n + cellsOf(glyphOf(s:sub(i, i))) end
  return n
end
-- big text at x y (2 rows); returns its width
function big(x, y, s, col, bg)
  s = tostring(s)
  local at = x
  for i = 1, #s do
    local g = glyphOf(s:sub(i, i))
    local n = cellsOf(g)
    for cy = 0, 1 do
      for cx = 0, n - 1 do
        local bits, k = 0, 1
        for py = 0, 2 do
          for pxl = 0, 1 do
            local r = g[cy * 3 + py + 1]
            local c = cx * 2 + pxl + 1
            if r and c <= #r and r:sub(c, c) == "#" then bits = bits + k end
            k = k * 2
          end
        end
        cell(at + cx, y + cy, bits, col, bg)
      end
    end
    at = at + n
  end
  return at - x
end

---------------------------------------------------------------------
-- PANELS
---------------------------------------------------------------------
hits = hits or {}
-- make an area touchable (handled in base_input.lua)
function addHit(x, y, w, h, kind, value)
  hits[#hits + 1] = { x, y, x + w - 1, y + h - 1, kind, value }
end
-- a panel: inside colour, thin frame, the title cut into the top line (amber), an
-- optional note on the right of the top line. Clips everything drawn after it to its
-- inside (rows y .. y+h-1, columns x+1 .. x+w-2). Returns the inner box x, y, w, h
-- (2 columns of padding; content starts one row under the title line).
function panel(x, y, w, h, title, opt)
  opt = opt or {}
  CLIP = nil
  fill(x, y, w, h, C.panel)
  frame(x, y, w, h, opt.col or C.line, C.panel)
  if title and title ~= "" and w > 8 then
    local room = w - 6 - (opt.right and (#opt.right + 3) or 0)
    text(x + 2, y, " " .. trunc(title, math.max(3, room)) .. " ", opt.tcol or C.label, C.panel)
  end
  if opt.right and w > #opt.right + 10 then
    text(x + w - #opt.right - 4, y, " " .. opt.right .. " ", opt.rcol or C.dim, C.panel)
  end
  clip(x + 1, y, w - 2, h)
  return x + 2, y + 2, w - 4, h - 3
end
-- the older name: a panel with a title
function card(x, y, w, h, label) return panel(x, y, w, h, label) end
-- a thin separator across a panel
function sep(x, y, w) hline(x, y, w, C.line, C.panel, "mid") end

---------------------------------------------------------------------
-- TEXT HELPERS
---------------------------------------------------------------------
-- key on the left (dim), value on the right, dotted leader between
function kv(x, y, w, k, v, vcol, bg)
  bg = bg or C.panel
  k, v = tostring(k), tostring(v)
  if #k + #v + 2 > w and #k + 5 <= w * 0.5 then
    v = shorten(v, w - #k - 2)                       -- a short key stays whole; the value loses its hint
  end
  if #k + #v + 2 > w then
    -- too long: the key keeps up to 40% of the row (all it needs when the value is short),
    -- the value gets the rest
    local kmax = math.max(3, math.min(#k, math.floor(w * 0.4)))
    if #v + kmax + 2 <= w then kmax = w - #v - 2 end
    k = trunc(k, math.max(3, math.min(#k, kmax)))
    v = shorten(v, math.max(1, w - #k - 2))
  end
  text(x, y, k, C.dim, bg)
  local gap = w - #k - #v - 2
  if gap > 0 then text(x + #k + 1, y, ("."):rep(gap), C.line, bg) end
  text(x + w - #v, y, v, vcol or C.text, bg)
end
-- a small dim label with the value under it
function stat(x, y, w, label, value, vcol)
  text(x, y, trunc(tostring(label), w), C.dim, C.panel)
  text(x, y + 1, trunc(tostring(value), w), vcol or C.text, C.panel)
end
-- label + value at a fixed column
function field(x, y, label, value, col)
  text(x, y, label, C.dim, C.panel)
  text(x + 11, y, value, col or C.text, C.panel)
end
-- a filled tag: " TEXT " in dark text on a colour; returns its width
function badge(x, y, s, col, fg)
  local l = " " .. tostring(s) .. " "
  text(x, y, l, fg or C.ink, col)
  return #l
end
function pill(x, y, label, fg, bg) return badge(x, y, label, bg, fg) end
-- a status light (a short bar in the middle of the cell)
function led(x, y, col, bg) cell(x, y, MID, col, bg or C.panel) end
-- the marker in front of a selected row
function mark(x, y, col) cell(x, y, LEFT, col or C.accent, C.panel) end
-- a heading inside a panel: amber, with a hairline to the right
function heading(x, y, w, s, col)
  s = trunc(tostring(s), w)
  text(x, y, s, col or C.label, C.panel)
  if w - #s - 1 > 0 then hline(x + #s + 1, y, w - #s - 1, C.line, C.panel) end
end
-- print wrapped lines; returns the next free row
function para(x, y, w, s, col, maxLines, bg)
  for _, l in ipairs(wrap(tostring(s), w, maxLines or 99)) do
    text(x, y, l, col or C.text, bg or C.panel)
    y = y + 1
  end
  return y
end

---------------------------------------------------------------------
-- GAUGES
---------------------------------------------------------------------
-- a segmented gauge: one tick per cell; share 0..1 lit in col
function gauge(x, y, w, share, col, bg)
  if w < 1 then return end
  share = math.max(0, math.min(1, tonumber(share) or 0))
  local n = math.floor(w * share + 0.5)
  if share > 0 and n == 0 then n = 1 end
  local tick = string.char(128 + LEFT)
  if n > 0 then text(x, y, tick:rep(n), col or C.accent, bg or C.panel) end
  if w - n > 0 then text(x + n, y, tick:rep(w - n), C.line, bg or C.panel) end
end
-- the older bar: `filled` cells of w
function barW(x, y, w, filled, col, track)
  gauge(x, y, w, w > 0 and (tonumber(filled) or 0) / w or 0, col)
end
-- label + value on one row, the gauge under it (2 rows)
function meter(x, y, w, label, value, share, col)
  kv(x, y, w, label, value, C.text)
  gauge(x, y + 1, w, share, col)
end
-- a sparkline (values -> bars 3 pixels high per cell row, h rows)
function spark(x, y, w, h, values, col)
  local n = #values
  if n == 0 or w < 1 then return end
  local top = 0
  for _, v in ipairs(values) do top = math.max(top, tonumber(v) or 0) end
  if top <= 0 then top = 1 end
  for i = 1, w do
    local v = tonumber(values[math.max(1, n - w + i)]) or 0
    if n < w and i <= w - n then v = 0 end
    local lvl = math.floor(v / top * h * 3 + 0.5)              -- pixels high
    for r = 0, h - 1 do
      local fromBottom = (h - 1 - r) * 3
      local p = math.max(0, math.min(3, lvl - fromBottom))
      local bits = (p >= 1 and BOT or 0) + (p >= 2 and MID or 0) + (p >= 3 and TOP or 0)
      cell(x + i - 1, y + r, bits, col, C.panel)
    end
  end
end

---------------------------------------------------------------------
-- BUTTONS
---------------------------------------------------------------------
-- A button. 3+ rows: a thin frame in `col` with the label in the middle (ghost), or
-- filled with `col` and dark text (solid). 2 rows: a face in the line colour (or `col`
-- when solid) with the label, a thin edge under it. Tap area = the whole box.
-- a label that fits w: whole as long as it fits; else without a "WORD: " prefix, then
-- word by word from the end (never cut mid-word unless one word is too long)
function fitLabel(s, w)
  s = tostring(s)
  if #s <= w then return s end
  local short = s:gsub("^[%w%s]+:%s+", "", 1)
  if #short <= w then return short end
  while #short > w and short:find(" ", 1, true) do short = short:gsub("%s*%S+$", "") end
  if #short <= w and #short > 0 then return short end
  return trunc(s, w)
end
function button(x, y, w, h, label, col, kind, value, solid)
  col = col or C.accent
  label = tostring(label)
  local l = (#label + 2 <= w) and label or fitLabel(label, math.max(1, w - 2))
  local ly = y + math.floor((h - 1) / 2)
  if h >= 3 then
    if solid then
      fill(x, y, w, h, col)
      text(x + math.floor((w - #l) / 2), ly, l, C.ink, col)
    else
      fill(x, y, w, h, C.panel)
      frame(x, y, w, h, col, C.panel)
      text(x + math.floor((w - #l) / 2), ly, l, col == C.line and C.text or col, C.panel)
    end
  else
    local face = solid and col or C.line
    fill(x, y, w, 1, face)
    text(x + math.floor((w - #l) / 2), y, l, solid and C.ink or (col == C.line and C.text or col), face)
    if h >= 2 then hline(x, y + 1, w, face, C.panel, "top") end
  end
  if kind then addHit(x, y, w, h, kind, value) end
end
-- the older call: bg / fg colours -> ghost or solid
local QUIET = {}
function drawButton(x, y, w, h, label, bg, fg, kind, value)
  QUIET[C.panel], QUIET[C.line], QUIET[C.bg] = true, true, true
  if bg and not QUIET[bg] then
    button(x, y, w, h, label, bg, kind, value, true)
  else
    button(x, y, w, h, label, (fg == C.dim) and C.line or (fg and fg ~= C.text and fg or C.line), kind, value, false)
  end
end
-- a button that needs a SECOND tap (it asks CONFIRM? first). col = its colour
-- (e.g. C.bad for STOP / DELETE), primary = solid accent.
function actButton(x, y, w, h, label, act, primary, col)
  act.key = act.kind .. ":" .. tostring(act.name) .. ":" .. tostring(act.count)
  local pend = state.pending and state.pending.key == act.key and os.clock() < state.pending.exp
  if pend then
    button(x, y, w, h, "CONFIRM?", C.warn, "act", act, true)
  elseif primary then
    button(x, y, w, h, label, col or C.accent, "act", act, true)
  else
    button(x, y, w, h, label, col or C.accent, "act", act, false)
  end
end
-- a TAB on a strip: label (2 rows to tap); the open one in the accent with a bar
function tabButton(x, y, label, fg, bg, kind, value)
  local on = (bg == C.label or bg == C.accent)
  text(x, y, label, on and C.ink or C.text, on and C.accent or C.line)
  hline(x, y + 1, #label, on and C.accent or C.line, C.bg, "top")
  addHit(x, y, #label, 2, kind, value)
end
-- PREV / NEXT for a list with several pages
function drawPager(y0, key, pages, xr)
  if pages <= 1 then return end
  local pl = string.format(" %d/%d ", state[key], pages)
  local bx = (xr or W) - #pl - 16
  text(bx, y0, " < PREV ", C.ink, C.accent)
  addHit(bx, y0, 8, 1, "pg", { key, -1 })
  text(bx + 8, y0, pl, C.text, C.line)
  text(bx + 8 + #pl, y0, " NEXT > ", C.ink, C.accent)
  addHit(bx + 8 + #pl, y0, 8, 1, "pg", { key, 1 })
end
-- scroll arrows in a panel's top line (row y); returns the clamped offset
function scrollBar(x, y, w, key, total, rows)
  local maxOff = math.max(0, total - rows)
  local off = math.max(0, math.min(state[key] or 0, maxOff))
  state[key] = off
  if maxOff > 0 then
    local info = string.format(" %d-%d / %d ", off + 1, math.min(off + rows, total), total)
    local bx = x + w - 2 - 11
    text(bx - #info, y, info, C.dim, C.panel)
    text(bx, y, "  \30  ", off > 0 and C.ink or C.dim, off > 0 and C.accent or C.line)
    addHit(bx, y, 5, 1, "dscroll", { key, -rows })
    text(bx + 6, y, "  \31  ", off < maxOff and C.ink or C.dim, off < maxOff and C.accent or C.line)
    addHit(bx + 6, y, 5, 1, "dscroll", { key, rows })
  end
  return off
end

---------------------------------------------------------------------
-- LISTS
---------------------------------------------------------------------
-- a list row: colour marker, name, amount gauge (own column), number. frac = amount /
-- largest amount (shown on a compressed scale so small amounts stay visible)
function drawBarRow(x, y, w, name, vs, frac, col, selected, numW)
  local bg = selected and C.line or C.panel
  numW = math.max(#vs, numW or 14)
  text(x, y, (" "):rep(w), C.text, bg)
  cell(x, y, LEFT, col, bg)
  local bw = math.max(6, math.floor(w * 0.18))
  local nameW = math.max(4, w - 3 - bw - numW - 2)
  text(x + 2, y, trunc(name, nameW), selected and C.accent or C.text, bg)
  local f = math.max(0, math.min(1, tonumber(frac) or 0)) ^ 0.35
  gauge(x + w - numW - 2 - bw, y, bw, f, col, bg)
  text(x + w - #vs, y, vs, selected and C.text or C.dim, bg)
end
-- a selectable row: highlighted when on (line colour + accent marker)
function rowBg(x, y, w, on)
  if on then
    fill(x, y, w, 1, C.line)
    cell(x, y, LEFT, C.accent, C.line)
  end
  return on and C.line or C.panel
end

---------------------------------------------------------------------
-- SLOTS (inventory, AE2, curios)
---------------------------------------------------------------------
-- one item slot: sunken (page colour), a stripe in the item's colour on the left, the
-- name, the count bottom right, a durability gauge on worn tools; selected = accent frame
function drawCell(x, y, w, h, item, emptyLabel)
  fill(x, y, w, h, C.bg)
  if not item then
    if emptyLabel and h >= 1 then
      local l = trunc(emptyLabel, w)
      text(x + math.floor((w - #l) / 2), y + math.floor((h - 1) / 2), l, C.line, C.bg)
    end
    return
  end
  local selected = selName and item.name == selName
  local col = colorFor(item.name)
  local bg = selected and C.line or C.bg
  if selected then fill(x, y, w, h, bg) end
  for j = y, y + h - 1 do cell(x, j, LEFT, selected and C.accent or col, bg) end
  local count = (item.count or 1) > 1 and compact(item.count) or nil
  local dur, durMax = durability(item)
  local showBar = dur and durMax and dur < durMax and h >= 3
  local tw = w - 2
  local maxLines = h - ((count or showBar) and 1 or 0)
  if maxLines >= 1 and tw >= 2 then
    local lines = wrap(item.displayName or item.name, tw, math.min(maxLines, 4))
    for i, l in ipairs(lines) do text(x + 1, y + i - 1, l, selected and C.accent or C.text, bg) end
  end
  if showBar then
    local f = dur / durMax
    gauge(x + 1, y + h - 1, math.max(1, w - 2 - (count and #count + 1 or 0)), f, f > 0.5 and C.good or (f > 0.2 and C.warn or C.bad), bg)
  end
  if count then text(x + w - #count, y + h - 1, count, C.label, bg) end
end

---------------------------------------------------------------------
-- PAGES AND GROUPS
---------------------------------------------------------------------
-- every page: its name and what it is for (HOME menu, the strip under the tabs)
PAGE_INFO = {                          -- (short: the HOME buttons show it whole, 30 characters)
  home      = { "HOME", "Everything at a glance" },
  inventory = { "INVENTORY", "Backpack, hotbar, armour" },
  storage   = { "BACKPACKS", "Inside backpacks and tanks" },
  curios    = { "CURIOS", "Rings, belts, charms you wear" },
  me        = { "AE2 STORAGE", "Find, take, store, craft" },
  players   = { "PLAYERS", "Who is online, where, health" },
  access    = { "CHAT & RIDES", "Chat commands, ride requests" },
  drone     = { "DRONES", "Rides: passenger, place, air" },
  work      = { "DRONE WORK", "Builds, fuel runs, work chest" },
  turtles   = { "TURTLES", "What each turtle does, fuel" },
  drive     = { "DRIVE", "Steer one turtle by hand" },
  map       = { "MAP", "The mapped world, surveys" },
  mining    = { "MINING", "Mining teams" },
  events    = { "MESSAGES", "Every message, newest first" },
  system    = { "STATUS", "Disk, logs, base off-times" },
  settings  = { "SETTINGS", "Change how things work" },
}
function pageName(p) return PAGE_INFO[p] and PAGE_INFO[p][1] or string.upper(tostring(p)) end

-- the pages there are: { page, label, badge, badge colour } (only when its block is there)
function pageTabs()
  local tabs = { { "home", "HOME" }, { "inventory", "INVENTORY" } }
  local np = det and #(state.players or {}) or 0
  tabs[#tabs + 1] = { "players", "PLAYERS", np > 0 and tostring(np) or nil }
  if invCaps.storage then tabs[#tabs + 1] = { "storage", "BACKPACKS" } end
  if invCaps.curios then tabs[#tabs + 1] = { "curios", "CURIOS" } end
  if bridge then tabs[#tabs + 1] = { "me", bridgeKind == "ME" and "AE2 STORAGE" or (bridgeKind .. " STORAGE") } end
  if #droneOrder > 0 then
    tabs[#tabs + 1] = { "drone", #droneOrder > 1 and "DRONES" or "DRONE",
                        #droneOrder > 1 and tostring(#droneOrder) or nil }
    local busy = DW and (DW.job or DW.trip) and "\7" or nil
    tabs[#tabs + 1] = { "work", "DRONE WORK", busy, busy and C.good or nil }
  end
  if chatBox then
    local req = 0
    for _ in pairs(state.rideRequests or {}) do req = req + 1 end
    tabs[#tabs + 1] = { "access", "CHAT & RIDES", req > 0 and tostring(req) or nil, req > 0 and C.warn or nil }
  end
  if state.tModem or next(state.turtles) then
    local on, all = 0, 0
    for _, t in pairs(state.turtles) do
      all = all + 1
      if TT.online(t) then on = on + 1 end
    end
    tabs[#tabs + 1] = { "turtles", "TURTLES", all > 0 and (on .. "/" .. all) or nil }
    if all > 0 then tabs[#tabs + 1] = { "drive", "DRIVE" } end
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
  tabs[#tabs + 1] = { "events", "MESSAGES", unread > 0 and tostring(unread) or nil,
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
  { id = "home",    label = "HOME",    pages = { "home" } },
  { id = "you",     label = "YOU",     pages = { "inventory", "storage", "curios" } },
  { id = "me",      label = "AE2",     pages = { "me" } },
  { id = "people",  label = "PLAYERS", pages = { "players", "access" } },
  { id = "drone",   label = nil,       pages = { "drone", "work" } },
  { id = "turtles", label = "TURTLES", pages = { "turtles", "drive", "map", "mining" } },
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


---------------------------------------------------------------------
-- THE HEADER
---------------------------------------------------------------------
-- rows 1-3: the title, the GROUP tabs (label on row 2, the open one teal with a bar under
-- it on row 3, a hairline across), the owner and a big clock on the right.
-- rows 4-5: the open group's PAGES as chips (when it has several) + what this page is for.
function drawHeader()
  CLIP = nil
  fill(1, 1, W, 5, C.bg)
  -- right: big clock, owner + link light
  local t = textutils.formatTime(os.time(), true)
  local tw = bigW(t)
  local owner = state.owner or "no player"
  local rightW = tw + 2 + math.max(#owner, 7) + 3
  local cx = W - tw
  big(cx, 1, t, C.label, C.bg)
  local ox = cx - 2 - math.max(#owner, 7)
  text(ox, 1, owner, C.text, C.bg)
  local live = state.status == "ok"
  led(ox, 2, live and C.good or C.bad, C.bg)
  text(ox + 2, 2, live and "LIVE" or "OFFLINE", live and C.good or C.bad, C.bg)
  -- left: the title, then the tabs
  local title = tostring(CONFIG.title or "BASE"):gsub("^%s+", ""):gsub("%s+$", "")
  local tabs = headerTabs()
  local avail = ox - 3
  local function tabsW(pad, badges, cut)
    local s = 0
    for _, g in ipairs(tabs) do
      s = s + (cut and math.min(#g[2], cut) or #g[2]) + 2 * pad + ((badges and g[3]) and (#g[3] + 3) or 0)
    end
    return s
  end
  local tx = 3
  local bigTitle = bigW(title) + 4 + tabsW(2, true) <= avail
  if bigTitle then
    big(3, 1, title, C.accent, C.bg)
    tx = 3 + bigW(title) + 3
  elseif #title + 3 + tabsW(2, true) <= avail then
    text(3, 2, title, C.accent, C.bg)
    tx = 3 + #title + 3
  end
  local pad, badges, cut = 2, true, nil
  if tx + tabsW(pad, badges) > avail then pad = 1 end
  if tx + tabsW(pad, badges) > avail then badges = false end
  if tx + tabsW(pad, badges) > avail then cut = 4 end
  hline(1, 3, W, C.line, C.bg, "mid")                 -- (mid: a gap above the page chips)
  for _, g in ipairs(tabs) do
    local on = groupOf(state.page) == g[1]
    local label = cut and g[2]:sub(1, cut) or g[2]
    local w = #label + 2 * pad + ((badges and g[3]) and (#g[3] + 3) or 0)
    text(tx + pad, 2, label, on and C.accent or C.dim, C.bg)
    if badges and g[3] then
      badge(tx + pad + #label + 1, 2, g[3], g[4] or (on and C.accent or C.line), (g[4] or on) and C.ink or C.text)
    end
    if on then hline(tx, 3, w, C.accent, C.bg, "mid") end
    addHit(tx, 1, w, 3, "group", g[1])
    tx = tx + w + 1
  end
  -- row 4: the group's pages (chips) + what this page is for
  local sx = 3
  for _, g in ipairs(tabs) do
    if groupOf(state.page) == g[1] and #g.members > 1 then
      for _, m in ipairs(g.members) do
        local on = state.page == m[1]
        local label = " " .. m[2] .. ((m[3] and m[3] ~= "") and (" " .. m[3]) or "") .. " "
        local bg = on and C.accent or (m[4] or C.line)
        text(sx, 4, label, (on or m[4]) and C.ink or C.text, bg)
        hline(sx, 5, #label, bg, C.bg, "top")
        addHit(sx, 4, #label, 2, "page", m[1])
        sx = sx + #label + 1
      end
      sx = sx + 2
    end
  end
  local info = PAGE_INFO[state.page]
  if info then
    if sx == 3 then
      text(sx, 4, info[1], C.label, C.bg)
      sx = sx + #info[1] + 2
    end
    text(sx, 4, trunc(info[2], W - sx - 1), C.dim, C.bg)
  end
end

-- a box in the middle with a title and text (loading, errors)
function drawMessage(title, lines, col)
  local boxW = math.min(W - 6, 72)
  local n = 0
  for _, l in ipairs(lines) do n = n + #wrap(l, boxW - 4, 8) end
  local boxH = math.min(H - 8, n + 4)
  local bx = math.floor((W - boxW) / 2) + 1
  local by = math.floor((H - boxH) / 2) + 1
  local ix, iy, iw = panel(bx, by, boxW, boxH, title, { col = col or C.line, tcol = col or C.label })
  local row = iy + 1
  for _, l in ipairs(lines) do
    for _, wl in ipairs(wrap(l, iw, 8)) do
      if row < by + boxH - 1 then text(ix, row, wl, C.text, C.panel) end
      row = row + 1
    end
  end
  CLIP = nil
end

-- layout numbers shared by the pages: the body is rows y0 .. y1
function geometry()
  local G = {}
  G.y0, G.y1 = 6, H - 1
  G.bodyH = G.y1 - G.y0 + 1
  G.leftW = math.floor((W - 3) * 0.64)
  G.pitch = math.max(3, math.floor((G.leftW - 2) / 9))
  G.cw = G.pitch - 1
  local ch = math.floor(G.cw * 0.62 + 0.5)
  ch = math.min(ch, math.floor((G.bodyH - 11 - 13) / 5))
  G.ch = math.max(3, ch)
  G.backH = 5 * G.ch + 11
  G.detailH = G.bodyH - G.backH - 1
  return G
end

---------------------------------------------------------------------
-- THE FOOTER + MESSAGE BOXES
---------------------------------------------------------------------
FOOT_HINT = {
  players = "Tap a player for everything the detector knows",
  storage = "What is inside your backpacks and tanks",
  curios  = "Tap a slot: store a worn item in AE2 / move it to you, or put on what fits (two taps)",
  me      = "Pick an item, then use the buttons - buttons that do something ask CONFIRM? first",
  access  = "Who may use the $drone chat commands. REMOVE asks CONFIRM? first",
  map     = "Tap the map to look at a spot. SURVEY maps what is on screen (turtles with a Geo Scanner)",
  turtles = "Pick a turtle for its controls. Console:  turtle <id> goto x y z",
  drone   = "Pick a passenger and a place, then FERRY (two taps)",
  work    = "Far from the screen? Stand ON the chest and type  $drone workchest  in chat",
  events  = "Every message, newest first - tap a filter to see one kind",
  system  = "How the base is doing; the system log keeps system things only",
  settings = "Pick a group, then tap - / + or the value. RESET = back to base_config.lua",
  mining  = "START / PAUSE / NEW FIELD go to the loader - it tells the miners",
  drive   = "Tap a block next to the turtle to go there, or use the pad",
}
function drawFooter()
  CLIP = nil
  fill(1, H, W, 1, C.bg)
  local msg, col = "LIVE", C.good
  if state.status ~= "ok" then msg, col = "OFFLINE", C.bad
  elseif (state.dropped or 0) > 0 then msg, col = "SLOT MISMATCH (see slotBase)", C.warn end
  local rx = W - #msg - 1
  led(rx - 2, H, col, C.bg)
  text(rx, H, msg, col, C.bg)
  if state.diskLow then
    badge(2, H, trunc(state.diskLow, rx - 8), C.bad)
  else
    local h = FOOT_HINT[state.page] or (PAGE_INFO[state.page] and PAGE_INFO[state.page][2]) or ""
    text(3, H, trunc(h, rx - 7), C.dim, C.bg)
  end
  drawNotes()
end

-- the message boxes (pushNote): framed in their colour, stacked bottom-right (or top:
-- CONFIG.notes.where = "top"). A tap closes one; each closes by itself (the gauge at
-- its bottom shows the time left).
function drawNotes()
  local now = os.clock()
  for i = #state.notes, 1, -1 do
    local n = state.notes[i]
    if n.exp and now >= n.exp then table.remove(state.notes, i) end
  end
  if #state.notes == 0 or state.page == "events" then return end
  local nw = math.min(60, math.max(38, math.floor(W * 0.32)))
  local x = W - nw - 1
  local atTop = CONFIG.notes and CONFIG.notes.where == "top"
  local list, used = {}, 0
  local room = H - 10
  for _, n in ipairs(state.notes) do
    if #list >= 3 then break end
    local lines = wrap(n.msg, nw - 4, 3)
    local h = #lines + 3
    if used + h + 1 > room and #list > 0 then break end
    list[#list + 1] = { n = n, lines = lines, h = h }
    used = used + h + 1
  end
  local more = #state.notes - #list
  local footer = (more > 0 or #state.notes > 1)
  local y
  if atTop then
    y = 6
    for _, b in ipairs(list) do b.y = y y = y + b.h + 1 end
  else
    y = H - 1 - (footer and 1 or 0)
    for _, b in ipairs(list) do b.y = y - b.h y = b.y - 1 end
    y = H - 1
  end
  for _, b in ipairs(list) do
    local n, by, h = b.n, b.y, b.h
    CLIP = nil
    fill(x - 1, by, nw + 2, h, C.bg)
    local ix, iy, iw = panel(x, by, nw, h, nil, { col = n.col })
    local kind = noteKind(n.col)
    local kw = badge(x + 2, by, kind, n.col)
    local right = n.when .. ((n.times and n.times > 1) and (" x" .. n.times) or "")
    text(x + 3 + kw, by, " " .. trunc(n.title or "", nw - kw - #right - 12) .. " ", C.text, C.panel)
    text(x + nw - #right - 7, by, " " .. right .. " ", C.dim, C.panel)
    text(x + nw - 4, by, " x ", C.ink, n.col)
    for k, l in ipairs(b.lines) do text(ix, iy + k, l, C.text, C.panel) end
    if n.exp and n.life and n.life > 0 then
      gauge(ix, by + h - 1, iw, (n.exp - now) / n.life, n.col)
    end
    CLIP = nil
    addHit(x, by, nw, h, "ndismiss", n.id)
  end
  if footer then
    if more > 0 then text(x, y, "+" .. more .. " more", C.dim, C.bg) end
    local ca = " CLOSE ALL "
    text(x + nw - #ca, y, ca, C.text, C.line)
    addHit(x + nw - #ca, y, #ca, 1, "nclear")
  end
end

---------------------------------------------------------------------
-- DRAW
---------------------------------------------------------------------
-- draw the whole screen for the open page
function draw()
  win.setVisible(false)
  hits = {}
  CLIP = nil
  win.setBackgroundColor(C.bg)
  win.clear()
  drawHeader()

  local G = geometry()

  if W < 100 or G.bodyH < 36 then
    drawMessage("MONITOR TOO SMALL",
      { "Use a bigger monitor, or set textScale to 0.5 in CONFIG." }, C.warn)
  elseif state.page == "home" then
    drawHomePage(G)
  elseif state.page == "players" then
    drawPlayersPage(G)
  elseif state.page == "me" then
    drawMEPage(G)
  elseif state.page == "drone" then
    drawDronePage(G)
  elseif state.page == "work" then
    drawWorkPage(G)
  elseif state.page == "access" then
    drawAccessPage(G)
  elseif state.page == "turtles" then
    drawTurtlesPage(G)
  elseif state.page == "drive" then
    drawDrivePage(G)
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
      CLIP = nil
      drawFooter()
      flushWindow()
      return
    elseif state.page == "curios" then
      drawCuriosPage(G)
      CLIP = nil
      drawFooter()
      flushWindow()
      return
    end

    local lx, leftW = 2, G.leftW
    local rx = lx + leftW + 1
    local rw = W - rx

    drawBackpack(lx, G.y0, leftW, G.backH, G)

    drawDetail(lx, G.y0 + G.backH + 1, leftW, G.detailH)
    if det then
      local ph = (state.player and state.player.airSupply) and 14 or 11
      drawPlayer(rx, G.y0, rw, ph)
      drawList(rx, G.y0 + ph + 1, rw, G.bodyH - ph - 1)
    else
      drawList(rx, G.y0, rw, G.bodyH)
    end
  end

  CLIP = nil
  drawFooter()
  CLIP = nil
  flushWindow()
end
