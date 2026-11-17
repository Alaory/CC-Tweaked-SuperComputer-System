-- base_ui_players.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   PLAYERS tab: the list of players (online first, then who left this run) and
--   EVERYTHING about the picked one: dimension and for how long, position, distance
--   + direction from the base, under ground / in the air (the MAP), nearest turtle /
--   place, health, air, moving speed, body (sneaking ...), looking, online for, what
--   the drones / turtles do about them, bed, "$drone back" spot, and every raw
--   value the Player Detector gave.

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

-- health / air / position / dimension / facing rows inside a panel (from row y)
function drawStatus(x, y, w, p, dim, showDim, other)
  local hp, mx = p.health or 0, p.maxHealth or 20
  local frac = mx > 0 and math.min(1, hp / mx) or 0
  local col = frac > 0.6 and C.good or (frac > 0.3 and C.warn or C.bad)
  meter(x, y, w, "Health", num(hp) .. " / " .. num(mx), frac, col)
  local r = y + 2
  if p.airSupply then
    local af = math.max(0, math.min(1, p.airSupply / 300))
    meter(x, r, w, "Air", af >= 1 and "full" or (math.floor(af * 100 + 0.5) .. "%"), af, C.info)
    r = r + 2
  end
  if p.x then
    kv(x, r, w, "Position", string.format("%d, %d, %d", math.floor(p.x), math.floor(p.y or 0), math.floor(p.z or 0)))
    r = r + 1
  end
  if showDim then
    kv(x, r, w, "Dimension", dimLabel(dim, other), other and not dim and C.label or dimColor(dim))
    r = r + 1
  end
  if p.yaw then
    local dirs = { "South", "West", "North", "East" }
    kv(x, r, w, "Facing", dirs[math.floor((p.yaw % 360 + 45) / 90) % 4 + 1])
  end
end

-- the owner's status card (INVENTORY page)
function drawPlayer(x, y, w, h)
  local p = state.player
  local ix, iy, iw = panel(x, y, w, h, "YOU" .. (state.owner and (": " .. state.owner) or ""),
                           { right = p and dimLabel(state.playerDim, state.playerDimOther) or nil, rcol = dimColor(state.playerDim) })
  if not p then
    text(ix, iy, trunc(state.playerMsg or "No data", iw), C.warn, C.panel)
    text(ix, iy + 1, trunc("Is the player inside the detector's range?", iw), C.dim, C.panel)
    return
  end
  drawStatus(ix, iy, iw, p, state.playerDim, false, state.playerDimOther)
end

-- ===== the PLAYERS page: the list (left) + EVERYTHING about the picked player (right) =====
local COMPASS = { "south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east" }
-- "north-east" etc. for a step dx dz (north = -z)
local function compass(dx, dz)
  if dx == 0 and dz == 0 then return "here" end
  local a = math.atan2 and math.atan2(-dx, dz) or math.atan(-dx, dz)        -- 0 = south, like the game's yaw
  return COMPASS[math.floor((math.deg(a) % 360 + 22.5) / 45) % 8 + 1]
end
local function home() return CONFIG.drone and CONFIG.drone.home end
local function overworld(e) return e.dim == (DRONE_DIM or "minecraft:overworld") or (not e.dim and not e.dimOther) end
local function round(v) return math.floor((tonumber(v) or 0) + 0.5) end
-- a detector value as text (a position table as "x, y, z")
local function valText(v)
  if type(v) == "table" then
    if v.x and v.y and v.z then return string.format("%d, %d, %d", round(v.x), round(v.y), round(v.z)) end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. (type(x) == "table" and "{..}" or tostring(x)) end
    table.sort(parts)
    return "{" .. table.concat(parts, " ") .. "}"
  end
  if type(v) == "number" and v ~= math.floor(v) then return string.format("%.2f", v) end
  return tostring(v)
end
local function ago(ms) return fmtSpan(math.max(0, (os.epoch("utc") - ms) / 1000)) end

-- every player for the list: online ones (detector), then the ones who left this run
local function playerRows()
  local rows, seen = {}, {}
  for _, e in ipairs(state.players or {}) do
    local k = tostring(e.name):lower()
    local i = PLAYER_INFO and PLAYER_INFO[k]
    local online = (state.online and state.online[k]) or (not state.online and e.p ~= nil)
    if online or e.p then rows[#rows + 1] = { e = e, i = i, online = true } seen[k] = true end
  end
  local gone = {}
  for k, i in pairs(PLAYER_INFO or {}) do
    if not seen[k] and not i.online then gone[#gone + 1] = { e = { name = i.name, dim = i.dim }, i = i, online = false } end
  end
  table.sort(gone, function(a, b) return (a.i.left or 0) > (b.i.left or 0) end)
  for _, r in ipairs(gone) do rows[#rows + 1] = r end
  return rows
end

-- one line of facts about a player: what the numbers mean in plain words
local function facts(r)
  local e, i, p = r.e, r.i or {}, r.e.p or {}
  local F = {}
  local function add(k, v, col) F[#F + 1] = { k, v, col } end
  -- where
  add("Dimension", dimLabel(e.dim, e.dimOther), (e.dimOther and not e.dim) and C.label or dimColor(e.dim))
  if i.dimSince and r.online then add("In it for", ago(i.dimSince)) end
  if p.x then add("Position", string.format("%d, %d, %d", round(p.x), round(p.y), round(p.z))) end
  local h0 = home()
  if p.x and h0 and h0.x and overworld(e) then
    local dx, dz = p.x - h0.x, p.z - h0.z
    local d = math.floor(math.sqrt(dx * dx + dz * dz))
    add("From the base", d <= 2 and "at the base" or (commas(d) .. " blocks " .. compass(dx, dz)), d <= 96 and C.good or C.text)
  end
  if p.x and overworld(e) and MAP and MAP.get then
    local top = MAP.get(math.floor(p.x), math.floor(p.z))
    if top then
      local dy = math.floor(p.y) - top - 1
      if dy < -3 then add("Height", "underground, " .. -dy .. " below the surface (Y " .. round(p.y) .. ")", C.label)
      elseif dy > 6 then add("Height", "in the air, " .. dy .. " above the ground (Y " .. round(p.y) .. ")", C.info)
      else add("Height", "on the surface (Y " .. round(p.y) .. ")") end
    else
      add("Height", "Y " .. round(p.y) .. "  (the map has no data there yet)", C.dim)
    end
  end
  if p.x and overworld(e) then
    local bt, bd
    for _, t in pairs(state.turtles or {}) do
      if t.pos and t.pos.x and TT and TT.online and TT.online(t) then
        local d = math.sqrt((t.pos.x - p.x) ^ 2 + (t.pos.y - p.y) ^ 2 + (t.pos.z - p.z) ^ 2)
        if not bd or d < bd then bt, bd = t, d end
      end
    end
    if bt then add("Nearest turtle", (bt.label or ("#" .. bt.id)) .. "  " .. commas(math.floor(bd)) .. " blocks") end
    local bw, bwd
    for _, w in ipairs(state.waypoints or {}) do
      if w.x then
        local d = math.sqrt((w.x - p.x) ^ 2 + ((w.y or p.y) - p.y) ^ 2 + (w.z - p.z) ^ 2)
        if not bwd or d < bwd then bw, bwd = w, d end
      end
    end
    if bw then add("Nearest place", bw.name .. "  " .. commas(math.floor(bwd)) .. " blocks") end
  end
  if not e.isOwner and p.x and state.player and state.player.x and e.dim == state.playerDim then
    add("From you", commas(math.floor(math.sqrt((p.x - state.player.x) ^ 2 + (p.z - state.player.z) ^ 2))) .. " blocks")
  end
  return F
end

local function moving(i)
  if not i or not i.speed then return nil end
  local v = i.speed
  local w = (v < 0.3 and "standing still") or (v < 4.8 and "walking") or (v < 7 and "running") or
            (v < 15 and "riding / swimming / flying") or (v < 60 and "flying fast (elytra?)") or "teleported"
  local up = i.vy and ((i.vy > 1 and ", going up") or (i.vy < -1 and ", going down")) or ""
  return w .. up .. string.format("  (%.1f blocks/s)", v)
end
local function posture(eye)
  eye = tonumber(eye)
  if not eye then return nil end
  if eye >= 1.5 then return "standing" end
  if eye >= 1.1 then return "sneaking" end
  if eye >= 0.3 then return "swimming / crawling / gliding" end
  return "lying down (asleep?)"
end
local function looking(p)
  local dirs = { "south", "west", "north", "east" }
  local f = p.yaw and dirs[math.floor((p.yaw % 360 + 45) / 90) % 4 + 1]
  local pt = tonumber(p.pitch)
  local up = pt and ((pt < -30 and ", looking up") or (pt > 30 and ", looking down") or "") or ""
  return f and ("facing " .. f .. up) or nil
end

-- the list: 3 rows per player (name, health / where, gap); tap = pick
local function drawPlayerList(x, y, w, h, rows)
  local on = 0
  for _, r in ipairs(rows) do if r.online then on = on + 1 end end
  local ix, iy, iw, ih = panel(x, y, w, h, "PLAYERS", { right = on .. " online" })
  local per = math.max(1, math.floor((ih + 1) / 3))
  local off = scrollBar(x, y, w, "playersOff", #rows, per)
  for n = 1, per do
    local r = rows[off + n]
    if not r then break end
    local e, i = r.e, r.i or {}
    local ry = iy + (n - 1) * 3
    local sel = state.playerSel == e.name
    local bg = sel and C.line or C.panel
    if sel then fill(ix - 1, ry, iw + 2, 2, C.line) end
    local mk = r.online and dimColor(e.dim) or C.dim
    cell(ix - 1, ry, 1 + 4 + 16, mk, bg)
    cell(ix - 1, ry + 1, 1 + 4 + 16, mk, bg)
    local right
    local p = e.p
    local h0 = home()
    if not r.online then right = "left " .. (i.left and ago(i.left) or "?") .. " ago"
    elseif p and p.x and h0 and h0.x and overworld(e) then
      right = commas(math.floor(math.sqrt((p.x - h0.x) ^ 2 + (p.z - h0.z) ^ 2))) .. " away"
    else right = "" end                                  -- (the dimension is on the 2nd line)
    local tag = e.isOwner and "  YOU" or ((state.access and state.access.allowed and state.access.allowed[tostring(e.name):lower()]) and "  allowed" or "")
    text(ix + 1, ry, trunc(e.name, iw - #right - #tag - 3), r.online and (e.isOwner and C.accent or C.text) or C.dim, bg)
    if #tag > 0 then text(ix + 1 + math.min(#e.name, iw - #right - #tag - 3), ry, tag, e.isOwner and C.accent or C.good, bg) end
    text(ix + iw - #right, ry, right, C.dim, bg)
    if r.online and p and p.health then
      local mx = tonumber(p.maxHealth) or 20
      local f = mx > 0 and math.min(1, (tonumber(p.health) or 0) / mx) or 0
      local hs = num(p.health) .. "/" .. num(mx)
      local dl = trunc(dimLabel(e.dim, e.dimOther), math.max(0, math.floor(iw * 0.4)))
      text(ix + 1, ry + 1, dl, dimColor(e.dim), bg)
      gauge(ix + 2 + #dl, ry + 1, math.max(1, iw - #dl - #hs - 3), f, f > 0.6 and C.good or (f > 0.3 and C.warn or C.bad), bg)
      text(ix + iw - #hs, ry + 1, hs, C.dim, bg)
    elseif r.online then
      text(ix + 1, ry + 1, trunc(e.err or "no data from the detector", iw - 1), C.warn, bg)
    else
      text(ix + 1, ry + 1, trunc("last in " .. dimLabel(i.dim, false), iw - 1), C.dim, bg)
    end
    addHit(ix - 1, ry, iw + 2, 2, "psel", e.name)
  end
end

-- everything about one player
local function drawPlayerDetail(x, y, w, h, r)
  local e, i = r.e, r.i or {}
  local p = e.p or {}
  local role = e.isOwner and "OWNER" or ((state.access and state.access.allowed and state.access.allowed[tostring(e.name):lower()])
               and "ALLOWED" or "VISITOR")
  local ix, iy, iw, ih = panel(x, y, w, h, e.name .. "  -  " .. role, {
    right = r.online and dimLabel(e.dim, e.dimOther) or "offline", rcol = r.online and dimColor(e.dim) or C.dim,
    col = e.isOwner and C.accent or C.line, tcol = e.isOwner and C.accent or C.label })
  local bottom = y + h - 2
  if not r.online then
    local rr = iy
    kv(ix, rr, iw, "Left the server", i.left and (ago(i.left) .. " ago") or "?") rr = rr + 1
    if i.dim then kv(ix, rr, iw, "Last dimension", dimLabel(i.dim, false), dimColor(i.dim)) rr = rr + 1 end
    if i.x then kv(ix, rr, iw, "Last seen at", string.format("%d, %d, %d", round(i.x), round(i.y), round(i.z))) rr = rr + 1 end
    para(ix, rr + 1, iw, "The detector only sees players who are on the server.", C.dim, 2)
    return
  end
  if not e.p then
    para(ix, iy, iw, tostring(e.err or "The detector gave no data for this player."), C.warn, 3)
    return
  end
  -- two columns when there is room: WHERE | NOW
  local two = iw >= 70
  local cw = two and math.floor((iw - 3) / 2) or iw
  local lx, rx2 = ix, two and (ix + cw + 3) or ix
  local F = facts(r)
  heading(lx, iy, cw, "WHERE")
  local ly = iy + 1
  for _, f in ipairs(F) do
    if ly > bottom then break end
    kv(lx, ly, cw, f[1], f[2], f[3])
    ly = ly + 1
  end
  local ry = two and iy or (ly + 1)
  if ry + 1 <= bottom then heading(rx2, ry, cw, "NOW") ry = ry + 1 end
  local hp, mx = tonumber(p.health) or 0, tonumber(p.maxHealth) or 20
  if p.health and ry + 1 <= bottom then
    local f = mx > 0 and math.min(1, hp / mx) or 0
    meter(rx2, ry, cw, "Health", num(hp) .. " / " .. num(mx) .. "  (" .. num(hp / 2) .. " hearts)", f,
          f > 0.6 and C.good or (f > 0.3 and C.warn or C.bad))
    ry = ry + 2
  end
  if p.airSupply and ry + 1 <= bottom then
    local af = math.max(0, math.min(1, (tonumber(p.airSupply) or 0) / 300))
    meter(rx2, ry, cw, "Air", af >= 1 and "full" or (math.floor(af * 100 + 0.5) .. "%  - under water!"), af,
          af >= 1 and C.info or C.warn)
    ry = ry + 2
  end
  local now = {
    { "Moving", moving(i) or "- (needs two readings)" },
    { "Body", posture(p.eyeHeight) },
    { "Looking", looking(p) },
    { i.joined and "Joined" or "Online for", i.first and (ago(i.first) .. (i.joined and " ago" or "")) or nil },
  }
  for _, f in ipairs(now) do
    if f[2] and ry <= bottom then kv(rx2, ry, cw, f[1], f[2]) ry = ry + 1 end
  end
  -- what the base does about them; their bed and their "$drone back" spot
  local y2 = math.max(ly, ry) + 1
  local extra = {}
  local threat = false
  if TT and TT.threats then
    local ok, list = pcall(TT.threats)
    for _, t in ipairs(ok and list or {}) do if t.name == e.name then threat = true end end
  end
  extra[#extra + 1] = { "Drones", (e.isOwner or role == "ALLOWED") and "can ride and call them" or "need your OK (CHAT & RIDES)",
                        (e.isOwner or role == "ALLOWED") and C.good or C.dim }
  extra[#extra + 1] = { "Turtles", threat and ("stop map work within " .. tostring(CONFIG.turtles.avoidRange or 100) .. " blocks of them")
                        or "ignore them", threat and C.warn or C.dim }
  if type(p.respawnPosition) == "table" and p.respawnPosition.x then
    extra[#extra + 1] = { "Respawn (bed)", valText(p.respawnPosition) .. (p.respawnDimension and ("  " .. dimLabel(tostring(p.respawnDimension))) or "") }
  end
  local b = backSpots and backSpots[tostring(e.name):lower()]
  if b and b.x then
    extra[#extra + 1] = { "Back spot", string.format("%d, %d, %d", b.x, b.y, b.z) .. "  " .. tostring(b.why or "") ..
                          (b.t and (", " .. ago(b.t) .. " ago") or "") }
  end
  if y2 + 1 <= bottom then
    heading(ix, y2, iw, "THE BASE AND " .. tostring(e.name):upper())
    y2 = y2 + 1
    for _, f in ipairs(extra) do
      if y2 > bottom then break end
      kv(ix, y2, iw, f[1], f[2], f[3])
      y2 = y2 + 1
    end
  end
  -- and every value the detector gave, as it gave it
  y2 = y2 + 1
  if y2 + 1 <= bottom then
    heading(ix, y2, iw, "DETECTOR DATA (as it came)")
    y2 = y2 + 1
    local keys = {}
    for k in pairs(p) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local rowsAvail = bottom - y2 + 1
    local cols = math.max(1, math.min(two and 2 or 1, math.ceil(#keys / math.max(1, rowsAvail))))
    local dw = math.floor((iw - (cols - 1) * 3) / cols)
    for n, k in ipairs(keys) do
      local c = math.floor((n - 1) / rowsAvail)
      if c >= cols then break end
      kv(ix + c * (dw + 3), y2 + (n - 1) % rowsAvail, dw, k, valText(p[k]), C.dim)
    end
  end
end

function drawPlayersPage(G)
  local y0 = G.y0
  if not det then
    drawMessage("NO PLAYER DETECTOR", deviceHelpLines("Player Detector"), C.warn)
    return
  end
  if not state.t.players then
    drawMessage("LOADING", { "Reading players..." }, C.label)
    return
  end
  local rows = playerRows()
  if #rows == 0 then
    drawMessage("NO PLAYERS FOUND", { state.playerMsg or "The detector returned no players." }, C.warn)
    return
  end
  -- the picked player (the owner first, else the first in the list)
  local pick
  for _, r in ipairs(rows) do if r.e.name == state.playerSel then pick = r end end
  if not pick then
    for _, r in ipairs(rows) do if r.e.isOwner then pick = r end end
    pick = pick or rows[1]
    state.playerSel = pick.e.name
  end
  local lw = math.max(30, math.min(46, math.floor((W - 3) * 0.32)))
  drawPlayerList(2, y0, lw, G.bodyH, rows)
  CLIP = nil
  drawPlayerDetail(2 + lw + 1, y0, W - (2 + lw + 1), G.bodyH, pick)
  CLIP = nil
end
