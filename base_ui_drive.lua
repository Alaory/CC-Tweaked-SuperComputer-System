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
  -- the tiles
  local v = t.view or {}
  local tw = math.max(16, math.min(30, math.floor((w - 12) / 4)))
  local th = math.max(5, math.min(9, math.floor((bottom - y0 - 20) / 3) - 1))
  local c0 = x + 2
  local c1, c2 = c0 + tw + 1, c0 + 2 * (tw + 1)
  local c3 = c2 + tw + 5
  local r0 = y0 + 6
  local r1, r2 = r0 + th + 1, r0 + 2 * (th + 1)
  local known = p and p.x and FWD[tostring(p.f)]
  local function look(ahead, right, up) if known then return seen(t, ahead, right, up) end end
  -- one direction: what is there (big), and what a tap does
  local function tile(tx, ty, title, name, act, hint)
    local bg, fg, word = C.panel, C.dim, "NOT SEEN YET"
    if name == false then bg, fg, word = C.bg, C.text, "AIR  (empty)"
    elseif name ~= nil then
      bg, fg, word = blockColour(name)
    end
    fill(tx, ty, tw, th, bg)
    round(tx, ty, tw, th, bg, C.panel)
    text(tx + 2, ty + 1, title, fg, bg)
    local mid = ty + math.floor(th / 2)
    text(tx + math.max(1, math.floor((tw - #word) / 2)), mid, trunc(word, tw - 2), fg, bg)
    if name == nil and title ~= "THE TURTLE" then
      text(tx + math.max(1, math.floor((tw - 22) / 2)), mid + 1, trunc("(tap SCAN AROUND)", tw - 2), fg, bg)
    end
    if hint then text(tx + math.max(1, math.floor((tw - #hint) / 2)), ty + th - 2, trunc(hint, tw - 2), fg, bg) end
    if act then addHit(tx, ty, tw, th, "tdrive", { t.id, act }) end
  end
  local function goHint(name, verb)
    if name == false then return "TAP = " .. verb end
    if name == nil then return "TAP = " .. verb .. " (digs if needed)" end
    if keepName(name) then return "WILL NOT DIG THIS" end
    return "TAP = DIG IT + " .. verb
  end
  local ah, le, ri, be = look(1, 0, 0), look(0, -1, 0), look(0, 1, 0), look(-1, 0, 0)
  local ab, bl = look(0, 0, 1), look(0, 0, -1)
  if not known then
    text(c0, r0, "Position or facing unknown - press GPS LOCATE on the TURTLES page first.", C.warn, C.panel)
  end
  tile(c1, r0, "AHEAD", ah, "minef", goHint(ah, "GO FORWARD"))
  tile(c0, r1, "ON ITS LEFT", le, "l", "TAP = TURN LEFT")
  tile(c2, r1, "ON ITS RIGHT", ri, "r", "TAP = TURN RIGHT")
  tile(c1, r2, "BEHIND IT", be, "around", "TAP = TURN AROUND")
  -- the turtle itself
  fill(c1, r1, tw, th, C.good)
  round(c1, r1, tw, th, C.good, C.panel)
  local fw = "facing " .. string.upper(tostring(p and p.f or "?"))
  text(c1 + math.floor((tw - 6) / 2), r1 + math.floor(th / 2) - 1, "TURTLE", C.ink, C.good)
  text(c1 + math.max(1, math.floor((tw - #fw) / 2)), r1 + math.floor(th / 2), fw, C.ink, C.good)
  -- up / down (a column of their own: above and below the turtle)
  if c3 + tw <= x + w - 1 then
    tile(c3, r0, "ABOVE IT", ab, "mineu", goHint(ab, "GO UP"))
    fill(c3, r1, tw, th, C.good)
    round(c3, r1, tw, th, C.good, C.panel)
    text(c3 + math.floor((tw - 6) / 2), r1 + math.floor(th / 2), "TURTLE", C.ink, C.good)
    tile(c3, r2, "BELOW IT", bl, "mined", goHint(bl, "GO DOWN"))
  end
  -- the rest
  local by = r2 + th + 2
  local bw = math.floor((w - 4 - 4) / 5)
  local function bt(col, label, kind, value, bg, fg)
    drawButton(x + 2 + col * (bw + 1), by, bw, 3, label, bg or C.empty, fg or C.text, kind, value)
  end
  bt(0, "SCAN AROUND", "tdrive", { t.id, "look" }, C.label, C.ink)
  bt(1, "STOP", "tcmd", { t.id, "stop", {} }, C.bad, C.ink)
  bt(2, "GO HOME", "tcmd", { t.id, "home", {} }, C.good, C.ink)
  bt(3, "BACK UP (no turn)", "tdrive", { t.id, "b" })
  if tostring(t.gear or ""):find("pick", 1, true) then
    actButton(x + 2 + 4 * (bw + 1), by, bw, 3, "MINE UP TO SURFACE", { kind = "tdigup", name = tostring(t.id), count = 0 })
  end
  local ly = by + 4
  if ly <= bottom - 1 then
    if t.driveAnyway then
      local what = ({ digf = "AHEAD", digu = "ABOVE", digd = "BELOW", minef = "AHEAD", mineu = "ABOVE",
                      mined = "BELOW" })[t.driveAnyway] or t.driveAnyway
      actButton(x + 2, ly, 2 * bw + 1, 1, "DIG ANYWAY: the block " .. what,
                { kind = "tdriveforce", name = t.id .. ":" .. t.driveAnyway, count = 0 })
    end
    local help = { "HOW IT WORKS:",
      "Tap a tile to go that way. If a block is in the way it is dug first - natural blocks only",
      "(stone, dirt, gravel, ores ...). Anything built needs DIG ANYWAY; chests, computers and turtles: never.",
      "LEFT / RIGHT turn the turtle (the side tile becomes AHEAD). BEHIND turns it around.",
      "SCAN AROUND (needs a Geo Scanner) shows the sides; AHEAD / ABOVE / BELOW update after every step." }
    for i, l in ipairs(help) do
      if ly + 2 + i <= bottom - 1 then text(x + 2, ly + 2 + i, trunc(l, w - 4), i == 1 and C.label or C.dim, C.panel) end
    end
    text(x + 2 + 2 * (bw + 1), ly, trunc(v.scanAt and ("Sides seen " .. math.floor(os.clock() - v.scanAt) .. " s ago") or
         (v.scanErr or "Left / right / behind: SCAN AROUND first"), w - 2 * bw - 6), C.dim, C.panel)
  end
end
