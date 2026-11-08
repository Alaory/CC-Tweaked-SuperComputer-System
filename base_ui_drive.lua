-- DRIVE page (TURTLES group): take control of one turtle by hand - see the
-- blocks around it, move, turn, dig / mine in any direction. Every tap is ONE
-- quick step on the turtle (it never waits long), then it says what it sees.
-- A turtle busy with a job refuses: press STOP first.

-- Everything is drawn from the TURTLE'S point of view (not north-up like a
-- map): AHEAD is always up / right on the screen, so the pictures match the
-- FORWARD / TURN / UP / DOWN buttons. Blocks are named in words.

-- a block's name in words: "deepslate_iron_ore" -> "IRON ORE"
local function nice(name)
  local n = tostring(name):match(":(.+)$") or tostring(name)
  n = n:gsub("^deepslate_(.+_ore)$", "%1"):gsub("_", " ")
  return n:upper()
end
-- colours: background, text
local function blockCol(name)
  if name == nil then return C.panel, C.dim end                    -- not seen yet
  if name == false then return C.bg, C.dim end                     -- air
  local n = tostring(name)
  if n:find("lava", 1, true) then return C.bad, C.ink end
  if n:find("water", 1, true) then return C.accent, C.ink end
  if n:find("_ore", 1, true) or n:find("ore_", 1, true) or n:find("debris", 1, true) then return C.warn, C.ink end
  if n:find("leaves", 1, true) or n:find("grass", 1, true) or n:find("log", 1, true) or n:find("moss", 1, true) then
    return C.good, C.ink
  end
  if n:find("chest", 1, true) or n:find("barrel", 1, true) or n:find("turtle", 1, true) or n:find("computer", 1, true) then
    return C.purple or C.accent, C.ink
  end
  return C.empty, C.text
end
-- one block: a box cw x ch with its name (2 lines if it needs them)
local function box(x, y, cw, ch, name, label)
  local bg, fg = blockCol(name)
  fill(x, y, cw - 1, ch, bg)
  local words
  if label then words = label
  elseif name == nil then words = "?"
  elseif name == false then words = ""
  else words = nice(name) end
  local l1, l2 = words, nil
  if #words > cw - 1 then
    local cut = words:sub(1, cw - 1):match("^(.*) ") or words:sub(1, cw - 1)
    l1, l2 = cut, words:sub(#cut + 1):gsub("^ ", "")
  end
  local mid = y + math.floor((ch - (l2 and 2 or 1)) / 2)
  text(x + math.max(0, math.floor((cw - 1 - #l1) / 2)), mid, trunc(l1, cw - 1), fg, bg)
  if l2 and ch >= 2 then text(x + math.max(0, math.floor((cw - 1 - #l2) / 2)), mid + 1, trunc(l2, cw - 1), fg, bg) end
end
local FWD = { north = { 0, -1 }, east = { 1, 0 }, south = { 0, 1 }, west = { -1, 0 } }
-- the block at (ahead, right, up) from the turtle; nil = not seen yet, false = air
local function seen(t, ahead, right, up)
  local p, v = t.pos, t.view
  if not (p and p.x and v and type(v.cells) == "table") then return nil end
  local f = FWD[tostring(p.f)]
  if not f then return nil end
  local x = p.x + f[1] * ahead - f[2] * right
  local z = p.z + f[2] * ahead + f[1] * right
  return v.cells[math.floor(x) .. "," .. math.floor(p.y + up) .. "," .. math.floor(z)]
end
-- TOP VIEW: 5 x 5 at the turtle's height, AHEAD is up
local function topView(x, y, t, cw, ch)
  text(x, y, "SEEN FROM ABOVE  (ahead = up)", C.label, C.panel)
  text(x + 2 * cw + math.floor((cw - 6) / 2), y + 1, "AHEAD", C.dim, C.panel)
  text(x + math.floor((cw - 5) / 2), y + 1, "LEFT", C.dim, C.panel)
  text(x + 4 * cw + math.floor((cw - 6) / 2), y + 1, "RIGHT", C.dim, C.panel)
  for r = 2, -2, -1 do                                   -- r = blocks ahead (top row = 2 ahead)
    for c = -2, 2 do                                     -- c = blocks to the right
      local bx, by = x + (c + 2) * cw, y + 2 + (2 - r) * ch
      if r == 0 and c == 0 then box(bx, by, cw, ch, "x", "TURTLE") fill(bx, by, cw - 1, ch, C.good)
        text(bx + math.floor((cw - 7) / 2), by + math.floor((ch - 1) / 2), "TURTLE", C.ink, C.good)
      else box(bx, by, cw, ch, seen(t, r, c, 0)) end
    end
  end
  text(x + 2 * cw + math.floor((cw - 7) / 2), y + 2 + 5 * ch, "BEHIND", C.dim, C.panel)
end
-- SIDE VIEW: behind it, the turtle, 4 ahead; 2 above to 2 below
local function sideView(x, y, t, cw, ch)
  text(x, y, "SEEN FROM THE SIDE  (ahead = right)", C.label, C.panel)
  local heads = { "BEHIND", "TURTLE", "1 AHEAD", "2 AHEAD", "3 AHEAD" }
  for i, h in ipairs(heads) do text(x + (i - 1) * cw + 1, y + 1, trunc(h, cw - 1), C.dim, C.panel) end
  for u = 2, -2, -1 do
    local by = y + 2 + (2 - u) * ch
    for a = -1, 3 do
      local bx = x + (a + 1) * cw
      if a == 0 and u == 0 then
        fill(bx, by, cw - 1, ch, C.good)
        text(bx + math.floor((cw - 7) / 2), by + math.floor((ch - 1) / 2), "TURTLE", C.ink, C.good)
      else box(bx, by, cw, ch, seen(t, a, 0, u)) end
    end
    text(x + 5 * cw + 1, by + math.floor((ch - 1) / 2), (u > 0 and ("+" .. u .. " up")) or (u < 0 and (-u .. " down")) or "level",
         C.dim, C.panel)
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
       "    (SCAN AROUND sees the blocks to the sides too)")), w - 4), C.text, C.panel)
  local gy = y0 + 7
  -- block size: as big as the card allows
  local cw = math.max(8, math.min(13, math.floor((w - 22) / 10)))
  local ch = math.max(2, math.min(3, math.floor((bottom - y0 - 30) / 5)))
  topView(x + 3, gy, t, cw, ch)
  sideView(x + 3 + 5 * cw + 6, gy, t, cw, ch)
  text(x + 3, gy + 4 + 5 * ch, trunc("? = not seen yet: SCAN AROUND     black = air     yellow = ore     red = lava     " ..
       "blue = water     purple = never dug", w - 6), C.dim, C.panel)
  -- the controls
  local by = gy + 5 * ch + 6
  if by + 13 > bottom then by = bottom - 13 end
  if by + 14 > bottom then by = math.max(gy + 9, bottom - 14) end
  local bw = math.floor((w - 4 - 4) / 5)
  local function b(col, row, label, act, bg, fg)
    drawButton(x + 2 + col * (bw + 1), by + row * 4, bw, 3, label, bg or C.empty, fg or C.text, "tdrive", { t.id, act })
  end
  b(0, 0, "MINE UP", "mineu")
  b(1, 0, "UP", "u", C.accent, C.ink)
  b(2, 0, "DIG UP", "digu")
  b(3, 0, "SCAN AROUND", "look", C.label, C.ink)
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
