-- base_ui_map.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MAP tab: the terrain from turtle scans, zoom (1 - 512 blocks per cell: the
--   whole 40k x 40k world fits) / rotate, survey. Zoomed in it
--   shows every column (detail); from 16 blocks per cell up, and wherever the
--   detail was dropped, one colour per chunk (overview).

-- page drawing: MAP
local BLIT = {}
-- colour -> blit character (cached)
local function blitc(c)
  local v = BLIT[c]
  if not v then
    v = string.format("%x", math.floor(math.log(c) / math.log(2) + 0.5))
    BLIT[c] = v
  end
  return v
end

-- world -> screen position (follows the map rotation)
local function toScreen(g, V, x, z)
  local sx, sy = MAP.toCell(x, z)
  local i = math.floor(sx + g.mw / 2 + 0.5)
  local j = math.floor(sy + g.mh / 2 + 0.5)
  if i >= 0 and i < g.mw and j >= 0 and j < g.mh then return g.mx0 + i, g.my0 + j end
end

-- world x, z under a touch on the map
function mapWorldAt(tx, ty)
  local g = state.mapGeom
  if not g then return nil end
  return MAP.toWorld(tx - g.mx0 - g.mw / 2, ty - g.my0 - g.mh / 2)
end

-- the MAP tab
function drawMapPage(G)
  local y0, bottom = G.y0, G.y1
  local V = MAP.view()
  local sideW = W >= 150 and 44 or 38
  local lx = 2
  local mapW = W - 3 - sideW
  local rx = lx + mapW + 1
  local rw = W - rx
  local rix, riw = rx + 2, rw - 4

  ------------------------------------------------ the map
  local cTop, cRight, cBottom, cLeft, upName = MAP.compass()
  local scale = "UP: " .. upName .. "   " .. (V.zoom == 1 and "1 cell = 1 block" or ("1 cell = " .. V.zoom .. " blocks"))
  panel(lx, y0, mapW, bottom - y0 + 1, "MAP", { right = scale })
  CLIP = nil
  local g = { mx0 = lx + 1, my0 = y0 + 2, mw = mapW - 2, mh = bottom - y0 - 2 }
  state.mapGeom = g
  local bgEmpty = blitc(C.bg)
  local fgGrid = blitc(C.head)
  -- the map image is rebuilt only when the map data or the view changed;
  -- otherwise the rows from last time are put on the screen again
  -- (new scans alone: at most every 5 s - with many turtles scanning the map
  -- changes all the time; moving / zooming the map redraws at once)
  local key = table.concat({ V.cx, V.cz, V.zoom, V.rot or 0, g.mx0, g.my0, g.mw, g.mh }, ",")
  local cache = state.mapImage
  if not cache or cache.key ~= key or (cache.ver ~= MAP.version and os.clock() - cache.t >= 5) then
    cache = { key = key, rows = {}, ver = MAP.version, t = os.clock() }
    local B = MAP.basis()
    local zx, zy = V.zoom, V.zoom * 1.5
    local cxs, czs = V.cx, V.cz
    local floor, names, colorOf = math.floor, MAP.names, MAP.colorOf
    local detail, overview = MAP.get, MAP.getOverview
    local zoomedOut = V.zoom >= 16
    -- the world border (CONFIG.map.border, e.g. 20000 for -20000..20000): outside
    -- it the empty map is drawn a little lighter
    local border = tonumber(CONFIG.map.border)
    local bgOutside = blitc(C.head)
    for j = 0, g.mh - 1 do
      local tx, fg, bg = {}, {}, {}
      local b2 = (j - g.mh / 2) * zy
      for i = 0, g.mw - 1 do
        local a2 = (i - g.mw / 2) * zx
        local wx = cxs + floor(a2 * B.rx + b2 * B.dx)
        local wz = czs + floor(a2 * B.rz + b2 * B.dz)
        local hgt, blk
        if not zoomedOut then hgt, blk = detail(wx, wz) end
        if not hgt then hgt, blk = overview(wx, wz) end
        -- far out a cell covers 2x2 chunks or more: look at a few more of them, so
        -- a partly scanned area does not show as scattered dots
        if not hgt and V.zoom >= 32 then
          local hz = floor(V.zoom / 2)
          hgt, blk = overview(wx + hz, wz)
          if not hgt then hgt, blk = overview(wx, wz + hz) end
          if not hgt then hgt, blk = overview(wx + hz, wz + hz) end
        end
        if hgt then
          tx[i + 1] = " "
          fg[i + 1] = fgGrid
          bg[i + 1] = blitc(colorOf(names[blk] or ""))
        else
          -- unscanned: dark, with faint dots on chunk borders (zoomed in)
          local edge = V.zoom == 1 and (wx % 16 == 0 or wz % 16 == 0)
          tx[i + 1] = edge and "." or " "
          fg[i + 1] = fgGrid
          bg[i + 1] = (border and (wx > border or wx < -border or wz > border or wz < -border)) and bgOutside or bgEmpty
        end
      end
      cache.rows[j] = { table.concat(tx), table.concat(fg), table.concat(bg) }
    end
    state.mapImage = cache
  end
  for j = 0, g.mh - 1 do
    local r = cache.rows[j]
    win.setCursorPos(g.mx0, g.my0 + j)
    win.blit(r[1], r[2], r[3])
  end
  addHit(g.mx0, g.my0, g.mw, g.mh, "mapcell")
  -- nothing mapped at all yet: say how to start
  if not MAP.loaded or ((MAP.ovN or 0) == 0 and #MAP.order == 0) then
    local m1 = MAP.loaded and "Nothing mapped yet." or "Loading the map ..."
    local m2 = MAP.loaded and "Select a turtle with a Geo Scanner, then SURVEY (right)."
               or "(from the floppies and helper computers - everything else works meanwhile)"
    local cy = g.my0 + math.floor(g.mh / 2) - 3
    text(g.mx0 + math.floor((g.mw - #m1) / 2), cy, m1, C.text, C.bg)
    text(g.mx0 + math.max(0, math.floor((g.mw - #m2) / 2)), cy + 1, trunc(m2, g.mw), C.dim, C.bg)
  end

  -- compass letters on the four edges
  local midX, midY = g.mx0 + math.floor(g.mw / 2), g.my0 + math.floor(g.mh / 2)
  text(midX, g.my0, cTop, C.ink, C.accent)
  text(midX, g.my0 + g.mh - 1, cBottom, C.text, C.empty)
  text(g.mx0, midY, cLeft, C.text, C.empty)
  text(g.mx0 + g.mw - 1, midY, cRight, C.text, C.empty)

  -- the WORK AREA (SETTINGS > MAP): its edge, so you see where the turtles may go
  local ax1, az1, ax2, az2 = MAP.area()
  if ax1 then
    local stepA = math.max(1, V.zoom)
    local function mark(x, z)
      local sx, sy = toScreen(g, V, x, z)
      if sx then text(sx, sy, "+", C.warn, C.bg) end
    end
    local n = 0
    for x = ax1, ax2, stepA do mark(x, az1) mark(x, az2) n = n + 1 if n > 4000 then break end end
    for z = az1, az2, math.max(1, math.floor(stepA * 1.5)) do mark(ax1, z) mark(ax2, z) n = n + 1 if n > 8000 then break end end
  end
  -- overlays: ores, base, players, drones, turtles, selection
  local h = CONFIG.drone.home
  if h then
    local sx, sy = toScreen(g, V, h.x, h.z)
    if sx then text(sx, sy, "B", C.ink, C.warn) end
  end
  for _, e in ipairs(state.players or {}) do
    if e.p and e.p.x then
      local sx, sy = toScreen(g, V, e.p.x, e.p.z)
      if sx then text(sx, sy, "@", C.ink, e.name == state.owner and C.accent or C.label) end
    end
  end
  for _, k in ipairs(droneOrder) do
    local dr = drones[k]
    if dr.pos then
      local sx, sy = toScreen(g, V, dr.pos.x, dr.pos.z)
      if sx then text(sx, sy, "D", C.ink, colors.pink) end
    end
  end
  for _, t in pairs(state.turtles) do
    if t.pos and t.pos.x then
      local sx, sy = toScreen(g, V, t.pos.x, t.pos.z)
      if sx then
        if t.stuck then text(sx, sy, "!", C.ink, C.bad)
        else text(sx, sy, "T", C.ink, state.tSel == t.id and C.accent or C.good) end
      end
    end
  end
  local sel = state.mapSel
  if sel then
    local sx, sy = toScreen(g, V, sel.x, sel.z)
    if sx then text(sx, sy, "+", C.text, C.bad) end
  end

  ------------------------------------------------ right column: view controls
  local vx, vy, vw = panel(rx, y0, rw, 18, "VIEW", { right = V.cx .. ", " .. V.cz })
  kv(vx, vy, vw, "Chunks mapped", commas(MAP.ovN or 0) .. "  (" .. #MAP.order .. " in detail)")
  local bw = math.floor((vw - 3) / 4)
  local lastW = vw - 3 * (bw + 1)
  local b1 = vy + 2
  button(vx, b1, bw, 3, "\27", C.line, "mpan", { -1, 0 })
  button(vx + bw + 1, b1, bw, 3, "\24", C.line, "mpan", { 0, -1 })
  button(vx + 2 * (bw + 1), b1, bw, 3, "\25", C.line, "mpan", { 0, 1 })
  button(vx + 3 * (bw + 1), b1, lastW, 3, "\26", C.line, "mpan", { 1, 0 })
  local b2 = b1 + 4
  button(vx, b2, bw, 3, "ZOOM: OUT -", C.line, "mzoom", 1)       -- (narrow: "OUT -" / "IN +")
  button(vx + bw + 1, b2, bw, 3, "ZOOM: IN +", C.line, "mzoom", -1)
  button(vx + 2 * (bw + 1), b2, vw - 2 * (bw + 1), 3, "ROTATE", C.line, "mrot")
  local b3 = b2 + 4
  -- widths by label (BASE / ME are short, TURTLE is not)
  local c1 = math.floor((vw - 3) * 6 / 25)
  local c2 = math.floor((vw - 3) * 8 / 25)
  local c3 = math.floor((vw - 3) * 4 / 25)
  button(vx, b3, c1, 3, "BASE", C.warn, "mcenter", "base")
  button(vx + c1 + 1, b3, c2, 3, "TURTLE", C.good, "mcenter", "turtle")
  button(vx + c1 + c2 + 2, b3, c3, 3, "ME", C.accent, "mcenter", "me")
  actButton(vx + c1 + c2 + c3 + 3, b3, vw - (c1 + c2 + c3 + 3), 3, "CLEAR", { kind = "mapclear", name = "map", count = 0 }, false, C.bad)
  ------------------------------------------------ selected spot
  local sy0 = y0 + 19
  local sx, ssy, sw = panel(rx, sy0, rw, 7, "SELECTED", { right = sel and (sel.x .. ", " .. sel.z) or nil })
  if sel then
    local hgt, blk = MAP.get(sel.x, sel.z)
    local whole = false
    if not hgt then
      hgt, blk = MAP.getOverview(sel.x, sel.z)
      whole = hgt ~= nil
    end
    if hgt then
      kv(sx, ssy, sw, whole and "Mostly (chunk)" or "Top block", prettify(MAP.names[blk] or "?"))
      kv(sx, ssy + 1, sw, whole and "Average height" or "Height", "Y " .. hgt)
    else
      text(sx, ssy, "Not scanned yet", C.dim, C.panel)
    end
  else
    text(sx, ssy, "Tap the map to look at a spot.", C.dim, C.panel)
  end
  ------------------------------------------------ turtle actions
  local ty0 = sy0 + 8
  if ty0 + 12 > bottom then return end
  local t = state.tSel and state.turtles[state.tSel]
  local tx, tyy, tw = panel(rx, ty0, rw, 13, "TURTLE", { right = t and (TT.online(t) and "online" or "OFFLINE") or nil,
                                                          rcol = t and (TT.online(t) and C.good or C.bad) or nil })
  local nfree = #TT.available()
  if not t then
    para(tx, tyy, tw, "Pick a turtle on the TURTLES page to scan or survey with it alone.", C.dim, 2)
    if next(state.turtles) then
      actButton(tx, tyy + 6, tw, 3, "SURVEY: ALL TURTLES (" .. nfree .. ")", { kind = "surveyall", name = "all", count = 0 }, true)
    end
  else
    text(tx, tyy, trunc(t.label .. "  -  " .. tostring(t.task or "idle"), tw), C.text, C.panel)
    local w3 = math.floor((tw - 2) / 3)
    button(tx, tyy + 2, w3, 3, "SCAN HERE", C.line, "tcmd", { t.id, "scan", { CONFIG.map.scanRadius } })
    button(tx + w3 + 1, tyy + 2, w3, 3, "STOP", C.bad, "tcmd", { t.id, "stop", {} })
    button(tx + 2 * (w3 + 1), tyy + 2, tw - 2 * (w3 + 1), 3, "STOP ALL", C.bad, "tstopall", nil, true)
    local hw = math.floor((tw - 1) / 2)
    actButton(tx, tyy + 6, hw, 3, "SURVEY: ALL (" .. nfree .. ")", { kind = "surveyall", name = "all", count = 0 }, true)
    actButton(tx + hw + 1, tyy + 6, tw - hw - 1, 3, "SURVEY: THIS ONE", { kind = "survey", name = tostring(t.id), count = 0 }, false, C.accent)
  end
  ------------------------------------------------ a survey in progress / auto-map
  local ly = ty0 + 14
  local frac, total, sent, skipped, again = MAP.surveyProgress()
  local q = MAP.queue
  if ly + 8 > bottom then
    -- (a short monitor: no room for the survey box and the legend)
  elseif frac and not q.auto then
    local bx, by, bw2 = panel(rx, ly, rw, 9, "BIG SURVEY", { right = math.floor(frac * 100) .. "%" })
    button(bx + bw2 - 8, by - 1, 8, 2, "STOP", C.bad, "mqstop", nil, true)
    gauge(bx, by + 1, bw2, frac, C.good)
    text(bx, by + 2, trunc(string.format("%d%% of %s spots", math.floor(frac * 100), compact(total)), bw2), C.text, C.panel)
    text(bx, by + 3, trunc(string.format("%s sent, %s mapped before", compact(sent), compact(skipped)) ..
         ((again or 0) > 0 and (", " .. again .. " to redo") or ""), bw2), C.dim, C.panel)
    -- what it is doing right now (the owner waited with "0 sent" and could not tell why)
    local L = MAP.looking
    if MAP.feedErr then
      para(bx, by + 4, bw2, "ERROR: " .. MAP.feedErr, C.bad, 2)
    elseif L then
      para(bx, by + 4, bw2, "looking past mapped land for unmapped rings: ring " .. L.r .. " of " .. L.rad ..
           " (" .. L.found .. " of " .. L.want .. " found)", C.label, 2)
    else
      text(bx, by + 4, trunc(MAP.auto.on and "auto-map goes on after this one" or "", bw2), C.dim, C.panel)
    end
    ly = ly + 10
  else
    local on = MAP.auto.on
    local ax, ay, aw = panel(rx, ly, rw, 8, "AUTO-MAP", { right = on and "ON" or "OFF", rcol = on and C.good or C.dim })
    button(ax + aw - 12, ay, 12, 3, on and "TURN OFF" or "TURN ON", on and C.line or C.good, "mauto", nil, not on)
    local radius = math.floor(MAP.autoRadius())
    local line1, col1
    if not on then line1, col1 = "Off - turtles survey only when you tell them", C.dim
    elseif MAP.auto.done then line1, col1 = "Done: the whole world is surveyed", C.good
    elseif MAP.full then line1, col1 = "Paused: the map floppies are full - add an EMPTY floppy", C.warn
    elseif q and q.auto then line1, col1 = "Surveying from the base outward", C.good
    else line1, col1 = "Waiting for a free turtle", C.dim end
    para(ax, ay, aw - 14, line1, col1, 2)
    text(ax, ay + 3, trunc(radius .. " blocks around the base are done" ..
         (q and q.auto and (again or 0) > 0 and (", " .. again .. " to redo") or ""), aw), C.dim, C.panel)
    ly = ly + 9
  end
  ------------------------------------------------ what the colours mean
  local lh = bottom - ly + 1
  if lh >= 6 then
    local gx, gy, gw = panel(rx, ly, rw, lh, "LEGEND")
    local mk = { { "B", C.warn, "base" }, { "@", C.accent, "you" }, { "D", colors.pink, "drone" }, { "T", C.good, "turtle" },
                 { "!", C.bad, "stuck" } }
    local mx = gx
    for _, m in ipairs(mk) do
      if mx + 3 + #m[3] > gx + gw then break end
      text(mx, gy, m[1], C.ink, m[2])
      text(mx + 2, gy, m[3], C.dim, C.panel)
      mx = mx + 4 + #m[3]
    end
    local items = {
      { colors.green, "Grass, plants" }, { colors.lime, "Trees, leaves" }, { colors.blue, "Water" },
      { colors.yellow, "Sand, gravel" }, { colors.orange, "Dirt, wood, clay" }, { colors.white, "Snow, ice" },
      { colors.brown, "Stone, buildings" }, { colors.red, "Lava, nether" }, { colors.cyan, "Warped, prismarine" },
      { colors.purple, "Obsidian, amethyst" },
    }
    local half = math.floor((gw - 1) / 2)
    local cols = 2
    for _, it in ipairs(items) do if #it[2] > half - 3 then cols = 1 end end   -- (one column: nothing cut)
    if cols == 1 then half = gw end
    for i, it in ipairs(items) do
      local ry = gy + 2 + math.floor((i - 1) / cols)
      if ry > ly + lh - 2 then break end
      local cx = gx + ((i - 1) % cols) * (half + 1)
      text(cx, ry, "  ", C.text, it[1])
      text(cx + 3, ry, trunc(it[2], half - 3), C.text, C.panel)
    end
  end
end
