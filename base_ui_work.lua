-- DRONE WORK page (DRONES group): the work chest, fuel runs to turtles, saved places and
-- schematic builds - everything by tapping (base_dronework.lua DW does the work; this page
-- only reads DW.view / DW.job / state - DW.refreshView reads the cable in the comms worker).

local function row(x, y, w, s, fg) text(x, y, trunc(s, w), fg or C.text, C.panel) end
local function done1(s)
  local _, n = tostring(s or ""):gsub("1", "")
  return n
end

-- WORK CHEST card
local function chestCard(x, y, w, h)
  card(x, y, w, h, "WORK CHEST")
  local name, at = DW.chestName(), { DW.chestAt() }
  local ix, iw = x + 2, w - 4
  local yy = y + 3
  for _, l in ipairs(wrap("An EMPTY chest / barrel on the cable near the drones. Only the base and the drones use it: " ..
                          "AE2 items go in, the drone takes them, what comes back goes into AE2.", iw, 3)) do
    row(ix, yy, iw, l, C.dim)
    yy = yy + 1
  end
  yy = yy + 1
  if name then
    row(ix, yy, iw, name .. (at[1] and ("  at " .. fmtPos(at[1], at[2], at[3])) or "  -  position NOT set"),
        at[1] and C.text or C.warn)
  else
    row(ix, yy, iw, "Not set yet: tap CHEST to pick one, stand ON it, tap BLOCK UNDER ME.", C.warn)
  end
  local bad = DW.view.bad
  if bad and name then row(ix, yy + 1, iw, bad, C.warn) end
  local bw = math.floor((iw - 1) / 2)
  local n = #(DW.view.cands or {})
  drawButton(ix, y + h - 3, bw, 2, "CHEST: " .. (name or "pick one") .. (n > 1 and " >" or ""), C.empty, C.text, "dwnext")
  actButton(ix + bw + 1, y + h - 3, iw - bw - 1, 2, "BLOCK UNDER ME", { kind = "dwchesthere", name = "", count = 0 }, name ~= nil and not at[1])
end

-- FUEL RUNS card: turtles with no fuel, AUTO on / off, SEND FUEL
local function fuelCard(x, y, w, h)
  card(x, y, w, h, "FUEL RUNS FOR TURTLES")
  local ix, iw = x + 2, w - 4
  local item, count = DW.fuelItem()
  local on = DW.autoOn()
  drawButton(ix + iw - 12, y + 1, 12, 2, on and "AUTO: ON" or "AUTO: OFF", on and C.good or C.empty, on and C.ink or C.text, "dwauto")
  row(ix, y + 4, iw - 14, "A turtle with NO FUEL gets " .. count .. " " .. prettify(item) .. " by drone.", C.dim)
  local list = {}
  for _, t in pairs(state.turtles) do
    local f = tonumber(t.fuel)
    if (TT.online(t) and f and f < 20) or DW.runs[t.id] then list[#list + 1] = t end
  end
  table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
  local yy = y + 6
  if #list == 0 then
    row(ix, yy, iw, "No turtle is out of fuel.", C.good)
    return
  end
  for _, t in ipairs(list) do
    if yy + 1 > y + h - 2 then break end
    local r = DW.runs[t.id]
    local st = r and (r.state == "flying" and "a drone is on its way" or r.state == "delivered" and "fuel delivered - burning it"
               or ("failed: " .. tostring(r.why or "?"))) or (TT.online(t) and "no fuel" or "offline (not loaded)")
    row(ix, yy, iw - 14, t.label .. "  fuel " .. tostring(t.fuel or "?"), C.text)
    row(ix, yy + 1, iw - 14, st, r and r.state == "failed" and C.warn or C.dim)
    if not r and TT.online(t) then
      actButton(ix + iw - 12, yy, 12, 2, "SEND FUEL", { kind = "dwfuel", name = tostring(t.id), count = 0 })
    end
    yy = yy + 3
  end
end

-- PLACES card: saved places (stand on a block: SAVE WHERE I STAND)
local function placesCard(x, y, w, h)
  card(x, y, w, h, "PLACES")
  local ix, iw = x + 2, w - 4
  actButton(ix + iw - 22, y + 1, 22, 2, "SAVE WHERE I STAND", { kind = "dwmark", name = "", count = 0 })
  row(ix, y + 4, iw, "The block under you. Name one in chat:  $" .. tostring(CONFIG.chat and CONFIG.chat.command or "drone") .. " mark <name>", C.dim)
  local yy = y + 6
  local shown = 0
  for _, wp in ipairs(state.waypoints or {}) do
    if yy + 1 > y + h - 2 then
      row(ix, yy - 1, iw, "... " .. (#state.waypoints - shown) .. " more (console: list)", C.dim)
      break
    end
    row(ix, yy, iw - 12, wp.name, C.text)
    row(ix, yy + 1, iw - 12, fmtPos(wp.x, wp.y, wp.z), C.dim)
    if wp.name ~= "Base" then
      actButton(ix + iw - 10, yy, 10, 2, "DELETE", { kind = "dwunmark", name = wp.name, count = 0 })
    end
    yy = yy + 3
    shown = shown + 1
  end
end

-- BUILD card: a running build, or pick a schematic + where + BUILD
local function buildCard(x, y, w, h)
  card(x, y, w, h, "BUILD A SCHEMATIC (BY DRONE)")
  local ix, iw = x + 2, w - 4
  local J = DW.job
  if J then
    local total, placed = #J.done, done1(J.done)
    row(ix, y + 3, iw, J.name .. "  at " .. fmtPos(J.x, J.y, J.z) .. (J.rot ~= 0 and ("  turned " .. J.rot) or ""), C.text)
    barW(ix, y + 5, iw, total > 0 and iw * placed / total or iw, C.good)
    row(ix, y + 6, iw, placed .. " of " .. total .. " blocks" ..
        (J.clear and ("   cleared " .. done1(J.dug) .. " of " .. #J.dug) or "") ..
        (J.skippedN > 0 and ("   " .. J.skippedN .. " spots were taken") or ""), C.dim)
    local yy = y + 8
    if J.paused then row(ix, yy, iw, "PAUSED: " .. J.paused, C.warn) yy = yy + 1 end
    if DW.trip and DW.trip.title then row(ix, yy, iw, "Now: " .. DW.trip.title, C.label) yy = yy + 1 end
    if J.why then
      for _, l in ipairs(wrap(J.why, iw, 2)) do row(ix, yy, iw, l, C.warn) yy = yy + 1 end
    end
    local a = J.anchor and state.turtles[J.anchor]
    if a then row(ix, yy, iw, a.label .. " keeps the site loaded", C.dim) yy = yy + 1 end
    local bw = math.floor((iw - 1) / 2)
    drawButton(ix, y + h - 3, bw, 2, J.paused and "RESUME" or "PAUSE", C.empty, C.text, "dwpause")
    actButton(ix + bw + 1, y + h - 3, iw - bw - 1, 2, "STOP THE BUILD", { kind = "dwstop", name = "", count = 0 })
    return
  end
  local list = DW.view.schems or {}
  if #list == 0 then
    for i, l in ipairs(wrap("No schematics yet. Save one with Create's Schematic and Quill, then drag the .nbt file " ..
                            "(from .minecraft/schematics on your PC) onto this computer's screen.", iw, 4)) do
      row(ix, y + 2 + i, iw, l, C.dim)
    end
    return
  end
  -- the list (2-row buttons), the chosen one's details, the options, BUILD
  local sel = DW.sel and DW.sel.name
  local cols = iw >= 50 and 2 or 1
  local cw = math.floor((iw - (cols - 1)) / cols)
  local maxRows = math.max(1, math.floor((h - 18) / 3))
  local rows = math.min(maxRows, math.ceil(#list / cols))
  local per = rows * cols
  local yy = y + 3
  for i, name in ipairs(list) do
    if i > per then break end
    local c = (i - 1) % cols
    local r = math.floor((i - 1) / cols)
    local on = (name == sel)
    drawButton(ix + c * (cw + 1), yy + r * 3, cw, 2, name, on and C.accent or C.empty, on and C.ink or C.text, "dwsel", name)
  end
  yy = y + 3 + rows * 3
  if #list > per then row(ix, yy, iw, "... " .. (#list - per) .. " more (console: schem)", C.dim) yy = yy + 1 end
  yy = yy + 1
  local s = DW.sel
  if s and s.err then
    row(ix, yy, iw, s.err, C.warn)
  elseif s then
    row(ix, yy, iw, s.name .. ": " .. s.size.x .. " x " .. s.size.y .. " x " .. s.size.z .. "  (" .. s.place .. " blocks, " ..
        s.air .. " air)" .. (s.short > 0 and ("  -  " .. s.short .. " item(s) short in AE2") or "  -  AE2 has everything"),
        s.short > 0 and C.warn or C.good)
    local my = yy + 1
    for k, r in ipairs(s.rows) do
      if my > y + h - 8 then break end
      local half = math.floor(iw / 2)
      local cx = ix + ((k - 1) % 2) * half
      row(cx, my, half - 1, string.format("%5d %s%s", r.need, prettify(r.item), r.have < r.need and ("  (AE2 " .. r.have .. ")") or ""),
          r.have < r.need and C.warn or C.dim)
      if k % 2 == 0 then my = my + 1 end
    end
  else
    row(ix, yy, iw, "Tap a schematic to see what it needs.", C.dim)
  end
  -- options: where, turned, clear
  local oy = y + h - 6
  local where = "UNDER YOU"
  if (DW.ui.at or 0) > 0 and state.waypoints[DW.ui.at] then where = state.waypoints[DW.ui.at].name end
  local bw = math.floor((iw - 2) / 3)
  drawButton(ix, oy, bw, 2, "AT: " .. where .. " >", C.empty, C.text, "dwat")
  drawButton(ix + bw + 1, oy, bw, 2, "TURN: " .. (DW.ui.rot or 0) .. " >", C.empty, C.text, "dwrot")
  drawButton(ix + 2 * (bw + 1), oy, iw - 2 * (bw + 1), 2, DW.ui.clear and "CLEAR FIRST: ON" or "CLEAR FIRST: OFF",
             DW.ui.clear and C.warn or C.empty, DW.ui.clear and C.ink or C.text, "dwclear")
  if sel then
    actButton(ix, y + h - 3, iw, 2, "BUILD " .. sel .. " (lowest north-west corner = " .. where:lower() .. ")",
              { kind = "dwbuild", name = sel, count = 0 }, true)
  else
    row(ix, y + h - 2, iw, "Blocks are placed the default way round (stairs / logs may face another way).", C.dim)
  end
end

function drawWorkPage(G)
  local y0, bottom = G.y0, G.y1
  local lw = math.floor((W - 3) / 2)
  local rx, rw = 2 + lw + 1, W - 2 - lw - 1
  local th = bottom - y0 + 1
  local ch = 12
  local rest = th - ch - 1
  local fh = math.floor(rest / 2)
  chestCard(2, y0, lw, ch)
  fuelCard(2, y0 + ch + 1, lw, fh)
  placesCard(2, y0 + ch + 1 + fh + 1, lw, th - ch - fh - 2)
  buildCard(rx, y0, rw, th)
end
