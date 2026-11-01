-- base_ui_events.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   EVENTS tab: every message the program showed (newest first), with its
--   date and time. Filter by kind, page through them, clear the list.
--   The list lives in memory only (state.noteLog, see pushNote in base_me.lua).

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

-- the EVENTS tab
function drawEventsPage(G)
  local y0, bottom = G.y0, G.y1

  -- top row: filter buttons with counts, CLEAR on the right
  local counts = { all = #state.noteLog }
  for _, e in ipairs(state.noteLog) do
    local k = noteKind(e.col):lower()
    counts[k] = (counts[k] or 0) + 1
  end
  local fx = 2
  for _, f in ipairs(FILTERS) do
    local on = (state.eventsFilter or "all") == f[1]
    local label = " " .. f[2] .. " " .. (counts[f[1]] or 0) .. " "
    drawButton(fx, y0, #label, 1, label, on and C.accent or C.empty, on and C.ink or C.text,
               "evfilter", f[1])
    fx = fx + #label + 1
  end
  local cl = " CLEAR LIST "
  drawButton(W - #cl - 1, y0, #cl, 1, cl, C.empty, C.text, "evclear")

  -- the list: 3 rows per message (time + kind + title / message / gap)
  local list = filtered()
  local cy = y0 + 2
  local cardH = bottom - cy + 1
  card(2, cy, W - 3, cardH)
  local per = math.max(1, math.floor((cardH - 2) / 3))
  local pages = math.max(1, math.ceil(#list / per))
  state.eventsPage = math.max(1, math.min(state.eventsPage or 1, pages))
  drawPager(y0, "eventsPage", pages, W - #cl - 3)

  if #list == 0 then
    text(5, cy + 2, (#state.noteLog == 0) and "No messages yet." or "No messages of this kind.",
         C.dim, C.panel)
    return
  end

  local ix, iw = 5, W - 9
  local first = (state.eventsPage - 1) * per
  for i = 1, per do
    local e = list[first + i]
    if not e then break end
    local ry = cy + 1 + (i - 1) * 3
    local kind = noteKind(e.col)
    fill(3, ry, 1, 2, e.col)                                  -- coloured marker
    text(ix, ry, e.when, C.dim, C.panel)
    text(ix + #e.when + 2, ry, " " .. kind .. " ", C.ink, e.col)
    if e.title then
      text(ix + #e.when + #kind + 6, ry, trunc(e.title, iw - #e.when - #kind - 6), C.text, C.panel)
    end
    text(ix, ry + 1, trunc(e.msg, iw), C.text, C.panel)
  end
end
