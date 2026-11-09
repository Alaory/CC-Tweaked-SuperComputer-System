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
  local sideW = 38
  local lx = 2
  local mapW = W - 3 - sideW
  local rx = lx + mapW + 1
  local rw = W - rx
  local rix, riw = rx + 2, rw - 4

  ------------------------------------------------ the map
  card(lx, y0, mapW, bottom - y0 + 1, "MAP")
  local cTop, cRight, cBottom, cLeft, upName = MAP.compass()
  local scale = "UP: " .. upName .. "   " ..
                (V.zoom == 1 and "1 cell = 1 block" or ("1 cell = " .. V.zoom .. " blocks"))
  text(lx + mapW - #scale - 3, y0 + 1, scale, C.dim, C.panel)
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
  card(rx, y0, rw, 17, "VIEW")
  actButton(rx + rw - 15, y0 + 1, 13, 2, "CLEAR MAP", { kind = "mapclear", name = "map", count = 0 })
  kv(rix, y0 + 3, riw, "Centre", V.cx .. ", " .. V.cz)
  kv(rix, y0 + 4, riw, "Chunks (overview)", tostring(MAP.ovN))
  kv(rix, y0 + 5, riw, "Chunks (detail)", tostring(#MAP.order))

  local bw = math.floor((riw - 3) / 4)
  local b1 = y0 + 7
  drawButton(rix,                b1, bw, 2, "\27",  C.empty, C.text, "mpan", { -1, 0 })
  drawButton(rix + bw + 1,       b1, bw, 2, "\24",  C.empty, C.text, "mpan", { 0, -1 })
  drawButton(rix + 2 * (bw + 1), b1, bw, 2, "\25",  C.empty, C.text, "mpan", { 0, 1 })
  drawButton(rix + 3 * (bw + 1), b1, bw, 2, "\26",  C.empty, C.text, "mpan", { 1, 0 })
  local b2 = y0 + 10
  drawButton(rix,                b2, bw, 2, "ZOOM -", C.empty, C.text, "mzoom", 1)
  drawButton(rix + bw + 1,       b2, bw, 2, "ZOOM +", C.empty, C.text, "mzoom", -1)
  drawButton(rix + 2 * (bw + 1), b2, bw * 2 + 1, 2, "ROTATE", C.empty, C.text, "mrot")
  local b3 = y0 + 13
  text(rix, b3, "CENTRE ON", C.dim, C.panel)
  local cw = math.floor((riw - 2) / 3)
  drawButton(rix,                b3 + 1, cw, 2, "BASE",   C.empty, C.text, "mcenter", "base")
  drawButton(rix + cw + 1,       b3 + 1, cw, 2, "TURTLE", C.empty, C.text, "mcenter", "turtle")
  drawButton(rix + 2 * (cw + 1), b3 + 1, cw, 2, "ME",     C.empty, C.text, "mcenter", "me")

  ------------------------------------------------ selected block
  local sy0 = y0 + 18
  card(rx, sy0, rw, 7, "SELECTED")
  if sel then
    local hgt, blk = MAP.get(sel.x, sel.z)
    local whole = false
    if not hgt then
      hgt, blk = MAP.getOverview(sel.x, sel.z)
      whole = hgt ~= nil
    end
    kv(rix, sy0 + 3, riw, whole and "Chunk (overview)" or "Column", sel.x .. ", " .. sel.z)
    if hgt then
      kv(rix, sy0 + 4, riw, whole and "Mostly" or "Top block", trunc(prettify(MAP.names[blk] or "?"), riw - 12))
      kv(rix, sy0 + 5, riw, whole and "Average height" or "Height", "Y " .. hgt)
    else
      text(rix, sy0 + 4, "Not scanned yet", C.dim, C.panel)
    end
  else
    text(rix, sy0 + 3, "Tap the map to inspect a spot", C.dim, C.panel)
  end

  ------------------------------------------------ turtle actions
  local ty0 = sy0 + 8
  card(rx, ty0, rw, 11, "TURTLE")
  local t = state.tSel and state.turtles[state.tSel]
  if not t then
    text(rix, ty0 + 3, trunc("Select a turtle on the TURTLES tab", riw), C.dim, C.panel)
    if next(state.turtles) then
      actButton(rix, ty0 + 8, riw, 2, "SURVEY: ALL TURTLES (" .. #TT.available() .. ")",
                { kind = "surveyall", name = "all", count = 0 }, true)
    end
  else
    kv(rix, ty0 + 3, riw, trunc(t.label, riw - 12), TT.online(t) and "online" or "OFFLINE",
       TT.online(t) and C.good or C.bad)
    text(rix, ty0 + 4, trunc(tostring(t.task or "idle"), riw), C.dim, C.panel)
    local tw = math.floor((riw - 2) / 3)
    drawButton(rix, ty0 + 5, tw, 2, "SCAN HERE", C.empty, C.text, "tcmd",
               { t.id, "scan", { CONFIG.map.scanRadius } })
    drawButton(rix + tw + 1, ty0 + 5, tw, 2, "STOP", C.bad, C.ink, "tcmd", { t.id, "stop", {} })
    drawButton(rix + 2 * (tw + 1), ty0 + 5, riw - 2 * (tw + 1), 2, "STOP ALL", C.bad, C.ink, "tstopall")
    local hw = math.floor((riw - 1) / 2)
    local nfree = #TT.available()
    actButton(rix, ty0 + 8, hw, 2, "SURVEY: ALL (" .. nfree .. ")",
              { kind = "surveyall", name = "all", count = 0 }, true)
    actButton(rix + hw + 1, ty0 + 8, riw - hw - 1, 2, "SURVEY: THIS ONE",
              { kind = "survey", name = tostring(t.id), count = 0 }, true)
  end

  ------------------------------------------------ a survey in progress / auto-map
  local ly = ty0 + 12
  local frac, total, sent, skipped, again = MAP.surveyProgress()
  local q = MAP.queue
  if frac and not q.auto then
    card(rx, ly, rw, 7, "BIG SURVEY")
    drawButton(rix + riw - 8, ly + 1, 8, 2, "STOP", C.bad, C.ink, "mqstop")
    barW(rix, ly + 3, riw, math.floor(frac * riw + 0.5), C.good)
    text(rix, ly + 4, trunc(string.format("%d%% of %s spots", math.floor(frac * 100), compact(total)), riw), C.text, C.panel)
    text(rix, ly + 5, trunc(string.format("%s sent, %s mapped before", compact(sent), compact(skipped)) ..
         ((again or 0) > 0 and (", " .. again .. " to redo") or ""), riw), C.dim, C.panel)
    text(rix, ly + 6, trunc(MAP.auto.on and "Auto-map goes on after this one" or "", riw), C.dim, C.panel)
    ly = ly + 8
  else
    -- auto-map: always a survey running, spiralling out from the base
    local on = MAP.auto.on
    card(rx, ly, rw, 6, "AUTO-MAP")
    drawButton(rix + riw - 10, ly + 1, 10, 2, on and "ON" or "OFF", on and C.good or C.empty,
               on and C.ink or C.text, "mauto")
    local radius = math.floor(MAP.autoRadius())
    local line1, col1
    if not on then line1, col1 = "Off - turtles only survey when you tell them", C.dim
    elseif MAP.auto.done then line1, col1 = "Done: the whole world is surveyed", C.good
    elseif MAP.full then line1, col1 = "Paused: the map floppies are full - add an EMPTY floppy", C.warn
    elseif q and q.auto then line1, col1 = "Surveying from the base outward", C.good
    else line1, col1 = "Waiting for a free turtle", C.dim end
    text(rix, ly + 3, trunc(line1, riw), col1, C.panel)
    text(rix, ly + 4, trunc("Done around the base: " .. radius .. " blocks" ..
         (q and q.auto and (again or 0) > 0 and (", " .. again .. " to redo") or ""), riw), C.dim, C.panel)
    ly = ly + 7
  end

  ------------------------------------------------ what the colours mean
  local lh = bottom - ly + 1
  if lh >= 5 then
    card(rx, ly, rw, lh, "LEGEND")
    -- the letters on the map
    local mk = { { "B", C.warn, "base" }, { "@", C.accent, "you" }, { "D", colors.pink, "drone" },
                 { "T", C.good, "turtle" } }
    local mx = rix
    for _, m in ipairs(mk) do
      if mx + 3 + #m[3] > rix + riw then break end
      text(mx, ly + 2, m[1], C.ink, m[2])
      text(mx + 2, ly + 2, m[3], C.dim, C.panel)
      mx = mx + 4 + #m[3]
    end
    local items = {
      { colors.green, "Grass, plants" }, { colors.lime, "Trees, leaves" },
      { colors.blue, "Water" }, { colors.yellow, "Sand, gravel" },
      { colors.orange, "Dirt, wood, clay" }, { colors.white, "Snow, ice" },
      { colors.brown, "Stone, buildings" }, { colors.red, "Lava, nether" },
      { colors.cyan, "Warped, prismarine" }, { colors.purple, "Obsidian, amethyst" },
    }
    for i = 1, math.min(#items, lh - 5) do
      local it = items[i]
      text(rix, ly + 3 + i, "  ", C.text, it[1])
      text(rix + 3, ly + 3 + i, it[2], C.text, C.panel)
    end
  end
end
