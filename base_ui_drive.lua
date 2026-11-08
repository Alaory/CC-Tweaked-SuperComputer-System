-- DRIVE page (TURTLES group): take control of one turtle by hand - see the
-- blocks around it, move, turn, dig / mine in any direction. Every tap is ONE
-- quick step on the turtle (it never waits long), then it says what it sees.
-- A turtle busy with a job refuses: press STOP first.

-- a block's colour and letter on the little grids
local function blockLook(name)
  if name == nil then return C.panel, C.dim, " .  " end         -- unknown
  if name == false then return C.bg, C.dim, "    " end           -- air
  local n = tostring(name)
  local bg = C.empty
  if n:find("lava", 1, true) then bg = C.bad
  elseif n:find("water", 1, true) then bg = C.accent
  elseif n:find("_ore", 1, true) or n:find("ore_", 1, true) or n:find("debris", 1, true) then bg = C.warn
  elseif n:find("leaves", 1, true) or n:find("grass", 1, true) or n:find("log", 1, true) or n:find("moss", 1, true) then bg = C.good
  elseif n:find("turtle", 1, true) or n:find("computer", 1, true) then bg = C.purple or C.accent
  end
  local short = (n:match(":(.+)$") or n)
  return bg, (bg == C.empty) and C.text or C.ink, (short:sub(1, 1):upper() .. short:sub(2, 3) .. " ")
end

-- 7 x 7 blocks around the turtle at height dy (north is up); each block 4 x 2
local CW, CH = 4, 2
local function grid(x, y, t, dy, title)
  local v = t.view or {}
  local cells = type(v.cells) == "table" and v.cells or {}
  local p = t.pos
  text(x, y, title, C.label, C.panel)
  for gz = -3, 3 do
    for gx = -3, 3 do
      local cx, cy = x + (gx + 3) * CW, y + 1 + (gz + 3) * CH
      if gx == 0 and gz == 0 and dy == 0 then
        local arrow = ({ north = " ^^ ", east = " >> ", south = " vv ", west = " << " })[tostring(p and p.f)] or " TT "
        text(cx, cy, arrow, C.ink, C.good)
        text(cx, cy + 1, "    ", C.ink, C.good)
      else
        local name
        if p and p.x then name = cells[math.floor(p.x + gx) .. "," .. math.floor(p.y + dy) .. "," .. math.floor(p.z + gz)] end
        local bg, fg, s = blockLook(name)
        text(cx, cy, s, fg, bg)
        text(cx, cy + 1, "    ", fg, bg)
      end
    end
  end
end

function drawDrivePage(G)
  local y0, bottom = G.y0, G.y1
  local list = TT.list()
  -- left: choose the turtle (online ones first)
  local lw = 28
  card(2, y0, lw, bottom - y0 + 1, "TAKE CONTROL OF")
  local sorted = {}
  for _, t in ipairs(list) do sorted[#sorted + 1] = t end
  table.sort(sorted, function(a, b)
    local oa, ob = TT.online(a) and 0 or 1, TT.online(b) and 0 or 1
    if oa ~= ob then return oa < ob end
    return tostring(a.label) < tostring(b.label)
  end)
  local sel = state.tSel and state.turtles[state.tSel]
  if not sel then
    for _, t in ipairs(sorted) do if TT.online(t) then sel = t break end end
  end
  local ry = y0 + 2
  for _, t in ipairs(sorted) do
    if ry > bottom - 1 then break end
    local _, lab, col = TT.status(t)
    local isSel = sel and sel.id == t.id
    local bg = isSel and C.accent or C.panel
    fill(3, ry, lw - 2, 1, bg)
    text(4, ry, trunc(t.label, lw - 14), isSel and C.ink or C.text, bg)
    text(lw - 9, ry, trunc(lab, 9), isSel and C.ink or (col or C.dim), bg)
    addHit(3, ry, lw - 2, 1, "dsel", t.id)
    ry = ry + 1
  end
  local x = lw + 4
  local w = W - x - 1
  if not sel then
    card(x, y0, w, 8, "DRIVE")
    text(x + 2, y0 + 2, "No turtle online.", C.dim, C.panel)
    return
  end
  local t = sel
  card(x, y0, w, bottom - y0 + 1, "DRIVE: " .. t.label .. "  #" .. t.id)
  local on = TT.online(t)
  local p = t.pos
  text(x + 2, y0 + 2, trunc((p and p.x and ("at " .. p.x .. " " .. p.y .. " " .. p.z .. "  facing " .. tostring(p.f or "?")) or
       "position unknown - GPS LOCATE first") .. "   fuel " .. tostring(t.fuel or "?") .. "   " ..
       (on and ("task: " .. tostring(t.task or "idle")) or "OFFLINE"), w - 4), on and C.text or C.bad, C.panel)
  -- the answer to the last step
  local msg, mcol
  if t.driveSent and not t.driveMsg then
    local ago = math.floor(os.clock() - t.driveSent)
    if ago >= 6 then msg, mcol = "no answer for " .. ago .. " s - is it busy or out of range? STOP, then try again", C.warn
    else msg, mcol = "sent ...", C.dim end
  elseif t.driveMsg then
    msg, mcol = (t.driveMsg.ok and "OK: " or "NO: ") .. t.driveMsg.msg, t.driveMsg.ok and C.good or C.warn
  else
    msg, mcol = "Tap a button: each tap is one step. A busy turtle needs STOP first.", C.dim
  end
  text(x + 2, y0 + 3, trunc(msg, w - 4), mcol, C.panel)
  -- what it sees
  local v = t.view or {}
  local function nm(s) return s and tostring(s):gsub("^minecraft:", "") or "?" end
  text(x + 2, y0 + 5, trunc("FRONT: " .. nm(v.front) .. "    UP: " .. nm(v.up) .. "    DOWN: " .. nm(v.down) ..
       (v.scanErr and ("    (" .. v.scanErr .. ")") or (v.scanAt and ("    scan " .. math.floor(os.clock() - v.scanAt) .. " s ago") or
       "    (LOOK AROUND for the blocks around it)")), w - 4), C.text, C.panel)
  local gy = y0 + 7
  local gw = 7 * CW + 3
  grid(x + 2, gy, t, 1, "ABOVE IT")
  grid(x + 2 + gw, gy, t, 0, "ITS LEVEL")
  grid(x + 2 + 2 * gw, gy, t, -1, "BELOW IT")
  local lx = x + 2 + 3 * gw
  if lx + 20 < x + w then
    text(lx, gy + 1, "north is up", C.dim, C.panel)
    text(lx, gy + 3, ">> = the turtle", C.dim, C.panel)
    text(lx, gy + 4, "     (its facing)", C.dim, C.panel)
    text(lx, gy + 6, " .  = not seen yet", C.dim, C.panel)
    text(lx, gy + 7, "      LOOK AROUND", C.dim, C.panel)
    text(lx, gy + 9, "yellow = ore", C.dim, C.panel)
    text(lx, gy + 10, "red = lava", C.dim, C.panel)
    text(lx, gy + 11, "blue = water", C.dim, C.panel)
    text(lx, gy + 12, "black = air", C.dim, C.panel)
  end
  -- the controls
  local by = gy + 7 * CH + 3
  if by + 14 > bottom then by = math.max(gy + 9, bottom - 14) end
  local bw = math.floor((w - 4 - 4) / 5)
  local function b(col, row, label, act, bg, fg)
    drawButton(x + 2 + col * (bw + 1), by + row * 4, bw, 3, label, bg or C.empty, fg or C.text, "tdrive", { t.id, act })
  end
  b(0, 0, "MINE UP", "mineu")
  b(1, 0, "UP", "u", C.accent, C.ink)
  b(2, 0, "DIG UP", "digu")
  b(3, 0, "LOOK AROUND", "look", C.label, C.ink)
  drawButton(x + 2 + 4 * (bw + 1), by, bw, 3, "STOP", C.bad, C.ink, "tcmd", { t.id, "stop", {} })
  b(0, 1, "TURN LEFT", "l")
  b(1, 1, "FORWARD", "f", C.accent, C.ink)
  b(2, 1, "TURN RIGHT", "r")
  b(3, 1, "MINE FORWARD", "minef")
  b(4, 1, "DIG FRONT", "digf")
  b(0, 2, "MINE DOWN", "mined")
  b(1, 2, "DOWN", "d", C.accent, C.ink)
  b(2, 2, "DIG DOWN", "digd")
  b(3, 2, "BACK", "b")
  drawButton(x + 2 + 4 * (bw + 1), by + 8, bw, 3, "GO HOME", C.good, C.ink, "tcmd", { t.id, "home", {} })
  local ly = by + 12
  if ly <= bottom - 1 then
    if t.driveAnyway then
      local what = ({ digf = "DIG FRONT", digu = "DIG UP", digd = "DIG DOWN", minef = "MINE FORWARD",
                      mineu = "MINE UP", mined = "MINE DOWN" })[t.driveAnyway] or t.driveAnyway
      actButton(x + 2, ly, 2 * bw + 1, 1, "DIG ANYWAY: " .. what,
                { kind = "tdriveforce", name = t.id .. ":" .. t.driveAnyway, count = 0 })
    end
    if tostring(t.gear or ""):find("pick", 1, true) then
      actButton(x + 2 + 2 * (bw + 1), ly, 2 * bw + 1, 1, "MINE UP TO THE SURFACE",
                { kind = "tdigup", name = tostring(t.id), count = 0 })
    else
      text(x + 2 + 2 * (bw + 1), ly, trunc("no pickaxe: it can move, not dig", 2 * bw + 1), C.dim, C.panel)
    end
  end
end
