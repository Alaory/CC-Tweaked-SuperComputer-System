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
  -- what is around it: one row per direction - what is there, and the key /
  -- tap that goes there (the same list on the pocket and the computer's keyboard)
  local v = t.view or {}
  local rows = driveRows(t)
  local ry = y0 + 6
  local dw, ww = 12, math.max(20, math.min(34, math.floor((w - 20) / 2)))
  local aw = w - 4 - dw - ww - 2
  text(x + 2, ry - 1, "DIRECTION", C.label, C.panel)
  text(x + 2 + dw + 1, ry - 1, "WHAT IS THERE", C.label, C.panel)
  text(x + 2 + dw + ww + 2, ry - 1, "TAP TO ...                       (keyboard key)", C.label, C.panel)
  local rh = math.max(3, math.min(5, math.floor((bottom - y0 - 26) / 6)))
  for _, r in ipairs(rows) do
    fill(x + 2, ry, dw, rh, C.head)
    text(x + 3, ry + math.floor(rh / 2), r.dir, C.text, C.head)
    local bg, fg = C.panel, C.dim
    if r.name == false then bg, fg = C.bg, C.text
    elseif r.name ~= nil then bg, fg = blockColour(r.name) end
    fill(x + 2 + dw + 1, ry, ww, rh, bg)
    text(x + 3 + dw + 1, ry + math.floor(rh / 2), trunc(driveWord(r.name), ww - 2), fg, bg)
    drawButton(x + 2 + dw + ww + 2, ry, aw, rh, r.does .. "   (" .. r.key .. ")", r.col or C.accent, C.ink,
               "tdrive", { t.id, r.act })
    ry = ry + rh + 1
  end
  -- the rest
  local by = ry + 1
  local bw = math.floor((w - 4 - 4) / 5)
  local function bt(col, label, kind, value, bg, fg)
    drawButton(x + 2 + col * (bw + 1), by, bw, 3, label, bg or C.empty, fg or C.text, kind, value)
  end
  bt(0, "SCAN AROUND  (X)", "tdrive", { t.id, "look" }, C.label, C.ink)
  bt(1, "STOP  (T)", "tcmd", { t.id, "stop", {} }, C.bad, C.ink)
  bt(2, "GO HOME  (H)", "tcmd", { t.id, "home", {} }, C.good, C.ink)
  bt(3, "TURN AROUND  (C)", "tdrive", { t.id, "around" })
  if tostring(t.gear or ""):find("pick", 1, true) then
    actButton(x + 2 + 4 * (bw + 1), by, bw, 3, "MINE UP TO SURFACE", { kind = "tdigup", name = tostring(t.id), count = 0 })
  end
  local ly = by + 4
  if ly <= bottom - 1 and t.driveAnyway then
    local what = ({ digf = "AHEAD", digu = "ABOVE", digd = "BELOW", minef = "AHEAD", mineu = "ABOVE",
                    mined = "BELOW" })[t.driveAnyway] or t.driveAnyway
    actButton(x + 2, ly, 2 * bw + 1, 1, "DIG ANYWAY: the block " .. what,
              { kind = "tdriveforce", name = t.id .. ":" .. t.driveAnyway, count = 0 })
  end
  local help = { "Drive it like you play Minecraft - on the BASE COMPUTER'S KEYBOARD (type  drive " .. t.id .. " ) or on your",
                 "POCKET computer (BOTS > the turtle > DRIVE): W forward, A / D turn, S back, SPACE up, SHIFT down.",
                 "W / SPACE / SHIFT dig first when a block is in the way (natural blocks; built ones need DIG ANYWAY).",
                 "LEFT / RIGHT / BEHIND need a SCAN AROUND (Geo Scanner); AHEAD / ABOVE / BELOW update every step." }
  for i, l in ipairs(help) do
    if ly + 1 + i <= bottom - 1 then text(x + 2, ly + 1 + i, trunc(l, w - 4), C.dim, C.panel) end
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
