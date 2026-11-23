-- base_ui_events.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   EVENTS tab: every message the program showed (newest first), with its
--   date and time. Filter by kind, page through them, clear the list.
--   The list (state.noteLog, see pushNote in base_me.lua) is also written to
--   events.log and read back on start.

local FILTERS = {
  { "all", "ALL" }, { "error", "ERRORS" }, { "warning", "WARNINGS" },
  { "done", "DONE" }, { "info", "INFO" },
}

-- the messages that match the chosen filter
local function filtered()
  local f = state.eventsFilter or "all"
  if f == "all" then return state.noteLog end
  local out = {}
  for _, e in ipairs(state.noteLog) do
    if noteKind(e.col):lower() == f then out[#out + 1] = e end
  end
  return out
end

-- the MESSAGES page: filter buttons with counts, CLEAR; the list newest first (time,
-- kind badge, title; the message wrapped to 2 rows), two columns on a wide monitor
function drawEventsPage(G)
  local y0, bottom = G.y0, G.y1
  local counts = { all = #state.noteLog }
  for _, e in ipairs(state.noteLog) do
    local k = noteKind(e.col):lower()
    counts[k] = (counts[k] or 0) + 1
  end
  local KCOL = { all = C.accent, error = C.bad, warning = C.warn, done = C.good, info = C.info }
  local fx = 2
  for _, f in ipairs(FILTERS) do
    local on = (state.eventsFilter or "all") == f[1]
    local label = f[2] .. "  " .. (counts[f[1]] or 0)
    button(fx, y0, #label + 4, 3, label, KCOL[f[1]] or C.line, "evfilter", f[1], on)
    fx = fx + #label + 5
  end
  local cl = "CLEAR LIST"
  button(W - #cl - 5, y0, #cl + 4, 3, cl, C.bad, "evclear")
  local list = filtered()
  local cy = y0 + 4
  local cardH = bottom - cy + 1
  local cols = W >= 150 and 2 or 1
  local per1 = 4
  local ix, iy, iw, ih = panel(2, cy, W - 2, cardH, "MESSAGES", { right = "also in events.log - type  events  for older ones" })
  local colW = math.floor((iw - (cols - 1) * 3) / cols)
  local rowsPer = math.max(1, math.floor((ih + 1) / per1))
  local per = rowsPer * cols
  local pages = math.max(1, math.ceil(#list / per))
  state.eventsPage = math.max(1, math.min(state.eventsPage or 1, pages))
  CLIP = nil
  drawPager(y0 + 1, "eventsPage", pages, W - #cl - 7)
  clip(3, cy, W - 4, cardH)
  if #list == 0 then
    text(ix, iy, (#state.noteLog == 0) and "No messages yet." or "No messages of this kind.", C.dim, C.panel)
    return
  end
  local first = (state.eventsPage - 1) * per
  for i = 1, per do
    local e = list[first + i]
    if not e then break end
    local c = math.floor((i - 1) / rowsPer)
    local r = (i - 1) % rowsPer
    local ex, ry = ix + c * (colW + 3), iy + r * per1
    local kind = noteKind(e.col)
    for k = 0, 2 do cell(ex, ry + k, 1 + 4 + 16, e.col, C.panel) end
    text(ex + 2, ry, e.when, C.dim, C.panel)
    local kw = badge(ex + 3 + #e.when, ry, kind, e.col)
    if e.title then text(ex + 4 + #e.when + kw, ry, trunc(e.title, colW - 4 - #e.when - kw), C.text, C.panel) end
    local lines = wrap(tostring(e.msg), colW - 2, 2)
    for k, l in ipairs(lines) do text(ex + 2, ry + k, l, C.text, C.panel) end
  end
end
