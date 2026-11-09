-- DRIVE page (TURTLES group): take control of one turtle by hand. No picture
-- to decode: the turtle in the middle, one big TILE per direction (AHEAD, LEFT,
-- RIGHT, BEHIND, ABOVE, BELOW) saying in words what is there. TAP A TILE TO GO
-- THAT WAY (it digs first if something is in the way); LEFT / RIGHT turn it,
-- BEHIND turns it around. Every tap is ONE quick step on the turtle (it never
-- waits long). A turtle busy with a job refuses: press STOP first.

-- a block's name in words: "deepslate_iron_ore" -> "IRON ORE"
local function nice(name)
  local n = tostring(name):match(":(.+)$") or tostring(name)
  n = n:gsub("^deepslate_(.+_ore)$", "%1"):gsub("_", " ")
  return n:upper()
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
-- a block's colours and its name in words (tiles)
function blockColour(name)
  local n = tostring(name)
  local word = nice(n)
  if n:find("lava", 1, true) then return C.bad, C.ink, word end
  if n:find("water", 1, true) then return C.accent, C.ink, word end
  if n:find("_ore", 1, true) or n:find("ore_", 1, true) or n:find("debris", 1, true) then return C.warn, C.ink, word end
  if n:find("leaves", 1, true) or n:find("grass", 1, true) or n:find("log", 1, true) or n:find("moss", 1, true) then
    return C.good, C.ink, word
  end
  if keepName(n) then return C.purple or C.accent, C.ink, word end
  return C.empty, C.text, word
end
-- blocks a turtle never digs by hand (node.lua DRIVE_KEEP)
local KEEP = { "chest", "barrel", "shulker", "computer", "turtle", "drive", "storage", "ae2:", "spawner",
               "furnace", "hopper", "dispenser", "dropper", "crate", "drawer", "monitor", "modem", "bed" }
function keepName(name)
  local n = tostring(name):lower()
  for _, k in ipairs(KEEP) do if n:find(k, 1, true) then return true end end
  return false
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
  local ry = y0 + 3
  for _, t in ipairs(sorted) do
    if ry > bottom - 1 then break end
    local _, lab, col = TT.status(t)
    local isSel = sel and sel.id == t.id
    local bg = isSel and C.accent or C.panel
    -- 2 rows per turtle (+ a gap): easy to tap
    fill(3, ry, lw - 2, 2, isSel and bg or C.empty)
    local fg = isSel and C.ink or C.text
    text(4, ry, trunc(t.label, lw - 14), fg, isSel and bg or C.empty)
    text(4, ry + 1, trunc(lab, lw - 6), isSel and C.ink or (col or C.dim), isSel and bg or C.empty)
    addHit(3, ry, lw - 2, 2, "dsel", t.id)
    ry = ry + 3
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
  -- three grids, seen from above (north up, like the MAP): the layer ABOVE it,
  -- its own LEVEL, the layer BELOW it. Tap a block next to the turtle to go there.
  local v = t.view or {}
  local R = 2
  local CW = math.max(5, math.min(10, math.floor((w - 16) / (3 * (2 * R + 1)))))
  local CH = 3
  local gw = (2 * R + 1) * CW
  local gap = math.max(4, math.floor((w - 4 - 3 * gw) / 3))
  local gy = y0 + 6
  local codes, legend = {}, {}
  local plainSeen = false
  local PLAINS = { stone = true, deepslate = true, cobbled_deepslate = true, tuff = true, andesite = true, diorite = true,
                   granite = true, dirt = true, netherrack = true, calcite = true, smooth_basalt = true }
  local function code(name)
    local short = tostring(name):match(":(.+)$") or tostring(name)
    if PLAINS[short] then plainSeen = true return "" end
    local c = codes[name]
    if not c then
      local n = nice(name)
      c = n:gsub("[^%a]", ""):sub(1, 3)
      codes[name] = c
      legend[#legend + 1] = { c = c, name = name, word = n }
    end
    return c
  end
  local cells = type(v.cells) == "table" and v.cells or {}
  local known = p and p.x
  local face = ({ north = 0, east = 1, south = 2, west = 3 })[tostring(p and p.f)]
  local ARROW = { [0] = "^", ">", "v", "<" }
  local GO = { [0] = "gon", "goe", "gos", "gow" }
  local function grid(gx0, dy, title, centreAct, centreHint)
    text(gx0, gy, title, C.label, C.panel)
    text(gx0 + math.floor(gw / 2), gy + 1, "N", C.dim, C.panel)
    text(gx0 + math.floor(gw / 2), gy + 2 + (2 * R + 1) * CH, "S", C.dim, C.panel)
    text(gx0 - 2, gy + 2 + R * CH, "W", C.dim, C.panel)
    text(gx0 + gw + 1, gy + 2 + R * CH, "E", C.dim, C.panel)
    for dz = -R, R do
      for dx = -R, R do
        local cx, cy = gx0 + (dx + R) * CW, gy + 2 + (dz + R) * CH
        local name
        if known then name = cells[math.floor(p.x + dx) .. "," .. math.floor(p.y + dy) .. "," .. math.floor(p.z + dz)] end
        local bg, fg, s = C.head, C.dim, "?"
        if name == false then bg, fg, s = C.bg, C.dim, ""
        elseif name ~= nil then
          bg, fg = blockColour(name)
          s = code(name)
        end
        local act, hint
        if dx == 0 and dz == 0 then
          if dy == 0 then
            bg, fg, s = C.good, C.ink, (face and string.rep(ARROW[face], 3) or "TTT")
          else
            act, hint = centreAct, centreHint
          end
        elseif dy == 0 and face and math.abs(dx) + math.abs(dz) == 1 then
          local dir = (dz == -1 and 0) or (dx == 1 and 1) or (dz == 1 and 2) or 3
          act, hint = GO[dir], "go"
        end
        fill(cx, cy, CW - 1, CH - 1, bg)                    -- (a 1-row gap below each block)
        text(cx + math.max(0, math.floor((CW - 1 - #s) / 2)), cy, trunc(s, CW - 1), fg, bg)
        if act then
          local h = string.upper(hint)
          text(cx + math.max(0, math.floor((CW - 1 - #h) / 2)), cy + 1, trunc(h, CW - 1),
               (bg == C.bg or bg == C.head or bg == C.empty) and C.label or fg, bg)
          addHit(cx, cy, CW - 1, CH, "tdrive", { t.id, act })
        end
      end
    end
  end
  local gx = x + 4
  grid(gx, 1, "ABOVE IT", "mineu", "up")
  grid(gx + gw + gap, 0, "ITS LEVEL", nil, nil)
  grid(gx + 2 * (gw + gap), -1, "BELOW IT", "mined", "down")
  -- what the short names mean
  local ly = gy + 4 + (2 * R + 1) * CH
  table.sort(legend, function(a, b) return a.word < b.word end)
  text(x + 2, ly, "WHAT THE LETTERS MEAN:", C.label, C.panel)
  local lx, lcol = x + 2, 0
  local colW = math.floor((w - 4) / 4)
  for i, e in ipairs(legend) do
    if i > 12 then break end
    local bg, fg = blockColour(e.name)
    local ex = x + 2 + ((i - 1) % 4) * colW
    local ey = ly + 1 + math.floor((i - 1) / 4)
    text(ex, ey, " " .. e.c .. " ", fg, bg)
    text(ex + #e.c + 3, ey, trunc(e.word, colW - #e.c - 4), C.text, C.panel)
  end
  local nl = math.min(12, #legend)
  if plainSeen then
    local ex = x + 2 + (nl % 4) * colW
    local ey = ly + 1 + math.floor(nl / 4)
    text(ex, ey, "   ", C.text, C.empty)
    text(ex + 4, ey, "plain stone / dirt", C.text, C.panel)
  end
  if #legend == 0 and not plainSeen then text(x + 2, ly + 1, "(nothing seen yet - SCAN AROUND)", C.dim, C.panel) end
  -- (wrapped, never cut off)
  for i, l in ipairs(wrap("Tap a block marked GO / UP / DOWN to move there (it turns and digs first if needed). " ..
                          "Black = air, ? = not seen yet, green arrows = the turtle and the way it faces.", w - 4, 2)) do
    text(x + 2, ly + 3 + i, l, C.dim, C.panel)
  end
  -- buttons
  local by = ly + 6
  if by + 7 > bottom then by = bottom - 7 end
  local bw = math.floor((w - 4 - 4) / 5)
  local function bt(col, row, label, kind, value, bg, fg)
    drawButton(x + 2 + col * (bw + 1), by + row * 4, bw, 3, label, bg or C.empty, fg or C.text, kind, value)
  end
  bt(0, 0, "TURN LEFT", "tdrive", { t.id, "l" })
  bt(1, 0, "FORWARD", "tdrive", { t.id, "minef" }, C.accent, C.ink)
  bt(2, 0, "TURN RIGHT", "tdrive", { t.id, "r" })
  bt(3, 0, "UP", "tdrive", { t.id, "mineu" }, C.accent, C.ink)
  bt(4, 0, "DOWN", "tdrive", { t.id, "mined" }, C.accent, C.ink)
  bt(0, 1, "SCAN AROUND", "tdrive", { t.id, "look" }, C.label, C.ink)
  bt(1, 1, "STOP", "tcmd", { t.id, "stop", {} }, C.bad, C.ink)
  bt(2, 1, "GO HOME", "tcmd", { t.id, "home", {} }, C.good, C.ink)
  bt(3, 1, "BACK", "tdrive", { t.id, "b" })
  if tostring(t.gear or ""):find("pick", 1, true) then
    actButton(x + 2 + 4 * (bw + 1), by + 4, bw, 3, "MINE UP TO SURFACE", { kind = "tdigup", name = tostring(t.id), count = 0 })
  end
  if t.driveAnyway and by + 8 <= bottom then
    actButton(x + 2, by + 8, 2 * bw + 1, 1, "DIG ANYWAY (the block it refused)",
              { kind = "tdriveforce", name = t.id .. ":" .. t.driveAnyway, count = 0 })
  end
end

-- ===== shared by the monitor, the computer's keyboard and the pocket =====
-- what a direction holds, in words
function driveWord(name)
  if name == nil then return "not seen yet (scan)" end
  if name == false then return "air (empty)" end
  return nice(name)
end
-- the six directions: what is there, the key, what the key / tap does
function driveRows(t)
  local p = t.pos
  local known = p and p.x and FWD[tostring(p.f)]
  local function look(a, r, u) if known then return seen(t, a, r, u) end end
  local function go(name, verb)
    if name == false then return verb end
    if name ~= nil and keepName(name) then return "NO: never dug" end
    return (name == nil) and verb or ("DIG + " .. verb)
  end
  local ah, ab, bl = look(1, 0, 0), look(0, 0, 1), look(0, 0, -1)
  return {
    { dir = "AHEAD", name = ah, key = "W", act = "minef", does = go(ah, "GO FORWARD") },
    { dir = "ABOVE", name = ab, key = "SPACE", act = "mineu", does = go(ab, "GO UP") },
    { dir = "BELOW", name = bl, key = "SHIFT", act = "mined", does = go(bl, "GO DOWN") },
    { dir = "LEFT", name = look(0, -1, 0), key = "A", act = "l", does = "TURN LEFT", col = C.label },
    { dir = "RIGHT", name = look(0, 1, 0), key = "D", act = "r", does = "TURN RIGHT", col = C.label },
    { dir = "BEHIND", name = look(-1, 0, 0), key = "S", act = "b", does = "BACK UP", col = C.label },
  }
end
-- a key -> a step (keys.* names)
function driveKeyAct(k)
  if k == keys.w or k == keys.up then return "minef" end
  if k == keys.s or k == keys.down then return "b" end
  if k == keys.a or k == keys.left then return "l" end
  if k == keys.d or k == keys.right then return "r" end
  if k == keys.space then return "mineu" end
  if k == keys.leftShift or k == keys.rightShift then return "mined" end
  if k == keys.c then return "around" end
  if k == keys.x then return "look" end
  if k == keys.f then return "digf" end
  if k == keys.r then return "digu" end
  if k == keys.v then return "digd" end
end
-- DRIVE on the base computer's own screen + keyboard (console: drive <id>)
function driveTerminal(id)
  local t = state.turtles[id]
  if not t then print("No turtle #" .. tostring(id) .. " - type  turtles") return end
  local function draw()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    local p = t.pos
    term.write(("DRIVING " .. t.label .. " #" .. id .. "  facing " .. string.upper(tostring(p and p.f or "?")) ..
                "  fuel " .. tostring(t.fuel or "?")):sub(1, 51))
    local y = 3
    for _, r in ipairs(driveRows(t)) do
      term.setCursorPos(1, y)
      term.setTextColor(colors.lightGray)
      term.write(string.format("%-7s", r.dir))
      term.setTextColor(r.name == nil and colors.gray or colors.white)
      term.write(string.format("%-22s", driveWord(r.name):sub(1, 21)))
      term.setTextColor(colors.lightBlue)
      term.write(string.format("%-6s", r.key))
      term.setTextColor(colors.white)
      term.write(r.does:sub(1, 16))
      y = y + 1
    end
    term.setCursorPos(1, y + 1)
    term.setTextColor(colors.lightBlue)
    term.write("X scan  C turn around  H home  T stop  Q quit")
    term.setCursorPos(1, y + 2)
    term.write("F / R / V = only dig ahead / up / down")
    term.setCursorPos(1, y + 4)
    local m = t.driveMsg
    if t.driveSent and not m then
      term.setTextColor(colors.gray)
      term.write(("waiting for the turtle ... " .. math.floor(os.clock() - t.driveSent) .. " s"):sub(1, 51))
    elseif m then
      term.setTextColor(m.ok and colors.lime or colors.orange)
      term.write(((m.ok and "OK: " or "NO: ") .. m.msg):sub(1, 51))
      if t.driveAnyway then
        term.setCursorPos(1, y + 5)
        term.setTextColor(colors.yellow)
        term.write("G = DIG ANYWAY (press twice)")
      end
    end
  end
  local armed = false
  if TT.online(t) then TT.drive(id, "look") end              -- what is around it, at once
  local tick = os.startTimer(0.5)
  draw()
  while true do
    local ev, k = os.pullEvent()
    if ev == "key" then
      if k == keys.q or k == keys.backspace then break end
      local act = driveKeyAct(k)
      if act then
        if act == "look" or TT.online(t) then TT.drive(id, act) end
        armed = false
      elseif k == keys.h then TT.send(id, "home", {}) armed = false
      elseif k == keys.t then TT.send(id, "stop", {}) armed = false
      elseif k == keys.g and t.driveAnyway then
        if armed then TT.drive(id, t.driveAnyway, true) armed = false else armed = true end
      end
      draw()
    elseif ev == "timer" and k == tick then
      tick = os.startTimer(0.5)
      draw()
    elseif ev == "terminate" then
      break
    end
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Left DRIVE mode.")
end
