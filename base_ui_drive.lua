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
-- ===== the 3D view: what the turtle sees =====
-- A small ray-caster over the blocks the turtle reported (t.view.cells). The
-- camera is just behind the turtle at its height, looking the way it faces (a
-- little down): the turtle is the green block at the bottom middle, AHEAD is
-- into the screen. Everything BEHIND the turtle is see-through (it would block
-- the camera). X-RAY: plain stone / dirt / gravel ... are see-through too, so
-- ores, lava, water and caves show. Rendered only when something changed
-- (state.driveImg), 2 characters per pixel (about square on the monitor).
local BLITC = {}
local function bc(c)
  local v = BLITC[c]
  if not v then v = string.format("%x", math.floor(math.log(c) / math.log(2) + 0.5)) BLITC[c] = v end
  return v
end
local PLAIN = {}
for _, n in ipairs({ "stone", "deepslate", "cobbled_deepslate", "dirt", "coarse_dirt", "rooted_dirt", "grass_block", "podzol",
                     "mycelium", "gravel", "sand", "red_sand", "sandstone", "red_sandstone", "clay", "mud", "tuff", "andesite",
                     "diorite", "granite", "calcite", "dripstone_block", "smooth_basalt", "basalt", "blackstone", "netherrack",
                     "soul_sand", "soul_soil", "end_stone", "cobblestone", "terracotta", "moss_block", "snow_block", "bedrock" }) do
  PLAIN[n] = true
end
local MATS = {}
-- per block name: lit colour, shaded colour (blit chars), see-through in X-RAY
local function mat(name)
  local m = MATS[name]
  if m then return m end
  local n = tostring(name)
  local short = n:match(":(.+)$") or n
  local lit, sh = C.empty, C.panel
  if n:find("lava", 1, true) then lit, sh = colors.orange, colors.red
  elseif n:find("water", 1, true) then lit, sh = colors.cyan, colors.blue
  elseif n:find("_ore", 1, true) or n:find("ore_", 1, true) or n:find("debris", 1, true) then lit, sh = colors.yellow, colors.orange
  elseif n:find("leaves", 1, true) or n:find("grass", 1, true) or n:find("moss", 1, true) then lit, sh = colors.lime, colors.green
  elseif n:find("log", 1, true) or n:find("planks", 1, true) or n:find("wood", 1, true) then lit, sh = colors.brown, colors.brown
  elseif n:find("dirt", 1, true) or n:find("mud", 1, true) or n:find("clay", 1, true) then lit, sh = colors.brown, colors.brown
  elseif n:find("chest", 1, true) or n:find("barrel", 1, true) or n:find("turtle", 1, true) or n:find("computer", 1, true) then
    lit, sh = colors.pink, colors.purple
  elseif n:find("sand", 1, true) then lit, sh = colors.yellow, colors.brown
  end
  m = { bc(lit), bc(sh), PLAIN[short] or false, (lit == C.empty) and bc(C.bg) or bc(sh) }
  MATS[name] = m
  return m
end
function driveRender(t, PW, PH, xray)
  local p, v = t.pos, t.view
  local f = FWD[tostring(p.f)]
  local fx, fz = f[1], f[2]
  local rx, rz = -fz, fx
  local R, S = 5, 11
  local vox = {}
  for k, name in pairs(v.cells or {}) do
    local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
    if x then
      local lx, ly, lz = tonumber(x) - p.x, tonumber(y) - p.y, tonumber(z) - p.z
      if lx >= -R and lx <= R and ly >= -R and ly <= R and lz >= -R and lz <= R then
        vox[(lx + R) + (ly + R) * S + (lz + R) * S * S] = name
      end
    end
  end
  -- camera: 3 blocks behind the turtle's middle, a bit above it, looking a little down
  local ox, oy, oz = 0.5 - fx * 2.9, 3.3, 0.5 - fz * 2.9
  local dx0, dy0, dz0 = fx, -0.72, fz
  local dl = math.sqrt(dx0 * dx0 + dy0 * dy0 + dz0 * dz0)
  dx0, dy0, dz0 = dx0 / dl, dy0 / dl, dz0 / dl
  -- camera up = right x dir
  local ux, uy, uz = 0 * dz0 - rz * dy0, rz * dx0 - rx * dz0, rx * dy0 - 0 * dx0
  if uy < 0 then ux, uy, uz = -ux, -uy, -uz end
  local tanH = 0.78
  local vScale = tanH * (PH * 0.75) / PW            -- a pixel (2 chars) is ~12 x 9 screen dots
  local cBg, cEdge, cTurtle, cTurtleS, cWire = bc(C.bg), bc(C.bg), bc(colors.lime), bc(colors.green), bc(C.dim)
  local floor, abs, huge = math.floor, math.abs, math.huge
  local rows = {}
  for j = 0, PH - 1 do
    local vv = (1 - (j + 0.5) / PH * 2) * vScale
    local tx, fg, bg = {}, {}, {}
    for i = 0, PW - 1 do
      local uu = ((i + 0.5) / PW * 2 - 1) * tanH
      local dx, dy, dz = dx0 + rx * uu + ux * vv, dy0 + uy * vv, dz0 + rz * uu + uz * vv
      local cx, cy, cz = floor(ox), floor(oy), floor(oz)
      local sx, sy, sz = dx > 0 and 1 or -1, dy > 0 and 1 or -1, dz > 0 and 1 or -1
      local tdx = dx ~= 0 and abs(1 / dx) or huge
      local tdy = dy ~= 0 and abs(1 / dy) or huge
      local tdz = dz ~= 0 and abs(1 / dz) or huge
      local tmx = dx ~= 0 and ((dx > 0 and (cx + 1 - ox) or (ox - cx)) * tdx) or huge
      local tmy = dy ~= 0 and ((dy > 0 and (cy + 1 - oy) or (oy - cy)) * tdy) or huge
      local tmz = dz ~= 0 and ((dz > 0 and (cz + 1 - oz) or (oz - cz)) * tdz) or huge
      local ch, cf, cb = " ", cBg, cBg
      for _ = 1, 40 do
        local tt, axis
        if tmx < tmy and tmx < tmz then tt, axis = tmx, 1 cx = cx + sx tmx = tmx + tdx
        elseif tmy < tmz then tt, axis = tmy, 2 cy = cy + sy tmy = tmy + tdy
        else tt, axis = tmz, 3 cz = cz + sz tmz = tmz + tdz end
        if cx < -R or cx > R or cy < -R or cy > R or cz < -R or cz > R then break end
        if cx * fx + cz * fz >= 0 and cy <= 0 then          -- (behind it / above its level: roof off)
          local lit, shade, edgeC
          if cx == 0 and cy == 0 and cz == 0 then
            -- the turtle: only its outline (you see through it to what is ahead)
            local hx, hy, hz = ox + dx * tt, oy + dy * tt, oz + dz * tt
            local a1, a2
            if axis == 1 then a1, a2 = hy - floor(hy), hz - floor(hz)
            elseif axis == 2 then a1, a2 = hx - floor(hx), hz - floor(hz)
            else a1, a2 = hx - floor(hx), hy - floor(hy) end
            if a1 < 0.09 or a1 > 0.91 or a2 < 0.09 or a2 > 0.91 then ch, cf, cb = " ", cTurtle, cTurtle break end
          else
            local name = vox[(cx + R) + (cy + R) * S + (cz + R) * S * S]
            if name == nil then
              if not xray then break end                    -- not seen yet: stays dark
            elseif name ~= false then
              local m = mat(name)
              if not (xray and m[3]) then lit, shade, edgeC = m[1], m[2], m[4]
              else
                -- X-RAY: plain stone is only a faint wireframe (you still see where things are)
                local hx, hy, hz = ox + dx * tt, oy + dy * tt, oz + dz * tt
                local a1, a2
                if axis == 1 then a1, a2 = hy - floor(hy), hz - floor(hz)
                elseif axis == 2 then a1, a2 = hx - floor(hx), hz - floor(hz)
                else a1, a2 = hx - floor(hx), hy - floor(hy) end
                if (a1 < 0.05 or a1 > 0.95) and (a2 < 0.05 or a2 > 0.95) then cb = cWire cf = cb break end
                if (a1 < 0.04 or a1 > 0.96 or a2 < 0.04 or a2 > 0.96) and tt < 4 then cb = cWire cf = cb break end
              end
            end
          end
          if lit then
            -- where on the face: near an edge = an outline (like Minecraft's block lines)
            local hx, hy, hz = ox + dx * tt, oy + dy * tt, oz + dz * tt
            local a1, a2
            if axis == 1 then a1, a2 = hy - floor(hy), hz - floor(hz)
            elseif axis == 2 then a1, a2 = hx - floor(hx), hz - floor(hz)
            else a1, a2 = hx - floor(hx), hy - floor(hy) end
            local e = 0.07
            if a1 < e or a1 > 1 - e or a2 < e or a2 > 1 - e then cb = edgeC or cEdge
            elseif axis == 2 and sy < 0 then cb = lit                   -- a top face
            elseif (axis == 1 and fx ~= 0) or (axis == 3 and fz ~= 0) then cb = lit   -- facing the camera
            else cb = shade end
            cf = cb
            break
          end
        end
      end
      tx[#tx + 1] = ch tx[#tx + 1] = ch
      fg[#fg + 1] = cf fg[#fg + 1] = cf
      bg[#bg + 1] = cb bg[#bg + 1] = cb
    end
    rows[j] = { table.concat(tx), table.concat(fg), table.concat(bg) }
  end
  return rows
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
  -- the controls go at the bottom; the 3D view fills the space above them
  local by = bottom - 13
  local vw = math.min(w - 4, 140)
  local PW, PH = math.floor(vw / 2), math.max(8, by - gy - 3)
  local vx = x + 2 + math.floor((w - 4 - PW * 2) / 2)
  if not (p and p.x and FWD[tostring(p.f)]) then
    text(x + 2, gy + 2, "Position or facing unknown - press GPS LOCATE on the TURTLES page first.", C.warn, C.panel)
  elseif not (v.cells and next(v.cells)) then
    text(x + 2, gy + 2, "Nothing seen yet - press SCAN AROUND (or take a step).", C.dim, C.panel)
  else
    local key = table.concat({ t.id, tostring(v.at), p.x, p.y, p.z, tostring(p.f), tostring(state.driveXray), PW, PH }, ":")
    local img = state.driveImg
    if not img or img.key ~= key then
      img = { key = key, rows = driveRender(t, PW, PH, state.driveXray) }
      state.driveImg = img
    end
    for j = 0, PH - 1 do
      local r = img.rows[j]
      if r then win.setCursorPos(vx, gy + j) win.blit(r[1], r[2], r[3]) end
    end
    text(vx + 1, gy, "LOOKING " .. string.upper(tostring(p.f)) .. " - the way it faces. Green box = the turtle.", C.dim, C.bg)
    text(vx + 1, gy + 1, "Roof cut away (above it: see ABOVE below). " ..
         (state.driveXray and "X-RAY: plain stone / dirt as lines, ores & caves solid." or "Dark = air or not seen yet."),
         C.dim, C.bg)
  end
  -- in words, around it (left / right / behind need a SCAN AROUND)
  local function say(n) if n == nil then return "?" elseif n == false then return "air" end return nice(n):lower() end
  text(x + 2, by - 2, trunc("AHEAD: " .. say(seen(t, 1, 0, 0)) .. "    ABOVE: " .. say(seen(t, 0, 0, 1)) ..
       "    BELOW: " .. say(seen(t, 0, 0, -1)) .. "    LEFT: " .. say(seen(t, 0, -1, 0)) .. "    RIGHT: " ..
       say(seen(t, 0, 1, 0)) .. "    BEHIND: " .. say(seen(t, -1, 0, 0)), w - 30), C.text, C.panel)
  drawButton(x + w - 26, by - 2, 22, 1, state.driveXray and "X-RAY: ON" or "X-RAY: OFF",
             state.driveXray and C.warn or C.empty, state.driveXray and C.ink or C.text, "dxray", true)
  -- the controls
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
