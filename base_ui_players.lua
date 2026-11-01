-- base_ui_players.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   PLAYERS tab: one box per online player (name, dimension, health, air,
--   position, facing). Tap a box to see the detector's raw data for that player.

-- page drawing
function num(v)
  return (string.format("%.1f", v):gsub("%.0$", ""))
end

-- label colour for a dimension (overworld green, nether red, end purple)
function dimColor(dim)
  local d = tostring(dim or ""):lower()
  if d == "" then return C.dim end
  if d:find("nether") then return C.red end
  if d:find("end") then return C.purple end
  if d:find("overworld") then return C.good end
  return C.label
end

-- health / air / position / dimension / facing rows (card starts at y)
-- label for a dimension: its name, "Other dimension" or "Unknown"
function dimLabel(dim, other)
  if dim then return prettify(dim) end
  return other and "Other dimension" or "Unknown"
end

-- health / air / position / dimension / facing rows
function drawStatus(x, y, w, p, dim, showDim, other)
  local ix, iw = x + 2, w - 4

  local hp, mx = p.health or 0, p.maxHealth or 20
  local frac = mx > 0 and math.min(1, hp / mx) or 0
  local col = frac > 0.6 and C.good or (frac > 0.3 and C.warn or C.bad)
  kv(ix, y + 3, iw, "Health", num(hp) .. " / " .. num(mx), col)
  barW(ix, y + 4, iw, math.floor(frac * iw + 0.5), col)

  if p.airSupply then
    local af = math.max(0, math.min(1, p.airSupply / 300))
    kv(ix, y + 6, iw, "Air",
       af >= 1 and "Full" or (math.floor(af * 100 + 0.5) .. "%"), colors.cyan)
    barW(ix, y + 7, iw, math.floor(af * iw + 0.5), colors.cyan)
  end

  local r = p.airSupply and (y + 9) or (y + 6)
  if p.x then
    kv(ix, r, iw, "Position",
       string.format("%d, %d, %d", math.floor(p.x), math.floor(p.y or 0), math.floor(p.z or 0)))
    r = r + 1
  end
  if showDim then
    kv(ix, r, iw, "Dimension", dimLabel(dim, other), other and not dim and C.label or dimColor(dim))
    r = r + 1
  end
  if p.yaw then
    local dirs = { "South", "West", "North", "East" }
    kv(ix, r, iw, "Facing", dirs[math.floor((p.yaw % 360 + 45) / 90) % 4 + 1])
  end
end

-- page 1: the owner's status card
function drawPlayer(x, y, w, h)
  card(x, y, w, h, "PLAYER")
  local p = state.player
  if not p then
    text(x + 2, y + 3, trunc(state.playerMsg or "No data", w - 4), C.warn, C.panel)
    text(x + 2, y + 4, trunc("Is the player inside the detector's range?", w - 4),
         C.dim, C.panel)
    return
  end
  drawStatus(x, y, w, p, state.playerDim, true, state.playerDimOther)
end

-- page 2: one card per online player
function drawPlayerCard(x, y, w, h, e)
  card(x, y, w, h)
  local ix, iw = x + 2, w - 4
  local name = (e.isOwner and "\7 " or "") .. e.name
  text(x + 2, y + 1, trunc(name, iw - 20), C.text, C.panel)
  if e.isOwner then text(x + 2, y + 1, "\7", C.accent, C.panel) end

  local d = dimLabel(e.dim, e.dimOther)
  text(x + w - #d - 4, y + 1, " " .. d .. " ", C.ink, (e.dimOther and not e.dim) and C.label or dimColor(e.dim))

  if not e.p then
    text(ix, y + 4, trunc(e.err or "No data", iw), C.warn, C.panel)
    return
  end

  if state.rawView[e.name] then
    text(ix, y + 3, "RAW DATA  (touch to close)", C.label, C.panel)
    local keys = {}
    for k in pairs(e.p) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local rowsAvail = math.max(1, h - 6)
    local colW = math.floor(iw / 2)
    for i, k in ipairs(keys) do
      local col = math.floor((i - 1) / rowsAvail)
      if col > 1 then break end
      local row = (i - 1) % rowsAvail
      local v = e.p[k]
      local vs = type(v) == "table" and "{table}" or tostring(v)
      text(ix + col * colW, y + 5 + row, trunc(k .. " = " .. vs, colW - 1), C.dim, C.panel)
    end
  else
    drawStatus(x, y, w, e.p, e.dim, false)
  end
end

-- the PLAYERS tab: one box per online player
function drawPlayersPage(G)
  local y0 = G.y0
  if not det then
    local lines = deviceHelpLines("Player Detector")
    drawMessage("NO PLAYER DETECTOR", lines, C.warn)
    return
  end

  if not state.t.players then
    drawMessage("LOADING", { "Reading players..." }, C.label)
    return
  end
  local list = state.players
  if #list == 0 then
    drawMessage("NO PLAYERS FOUND", { state.playerMsg or "The detector returned no players." }, C.warn)
    return
  end

  local anyAir = false
  for _, e in ipairs(list) do
    if e.p and e.p.airSupply then anyAir = true break end
  end
  local cols, ch = 2, anyAir and 13 or 11
  local cw = math.floor((W - 3) / cols)
  local rows = math.max(1, math.floor((G.bodyH - 2 + 1) / (ch + 1)))
  local per = rows * cols
  local pages = math.max(1, math.ceil(#list / per))
  state.playersPage = math.max(1, math.min(state.playersPage, pages))

  text(2, y0, "ONLINE PLAYERS: " .. #list, C.label, C.bg)
  drawPager(y0, "playersPage", pages)

  for i = 1, per do
    local e = list[(state.playersPage - 1) * per + i]
    if not e then break end
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local cx = 2 + col * (cw + 1)
    local cy = y0 + 2 + row * (ch + 1)
    drawPlayerCard(cx, cy, cw, ch, e)
    addHit(cx, cy, cw, ch, "praw", e.name)
  end
end
