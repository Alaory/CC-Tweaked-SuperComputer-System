-- base_ui_mining.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MINING tab (TURTLES group): one card per mining dimension team (miner +
--   loader, miner.lua). Left: both turtles (status, fuel bar, position), the
--   progress (field map of the chunks, layer bar, ores per hour, unload
--   countdown) and the items (in the shulker / delivered). Right: buttons, a
--   "what to do" hint when something is wrong, and the log.

local DIMS = { "overworld", "nether", "end" }

local function itemName(n)
  n = tostring(n):gsub("^[^:]+:", ""):gsub("_", " ")
  return n
end
local function mmss(s)
  s = math.max(0, math.floor(s))
  if s >= 3600 then return math.floor(s / 3600) .. "h " .. string.format("%02d", math.floor(s % 3600 / 60)) .. "m" end
  return math.floor(s / 60) .. ":" .. string.format("%02d", s % 60)
end
local function total(t)
  local n = 0
  for _, v in pairs(t or {}) do n = n + (tonumber(v) or 0) end
  return n
end
-- words into lines of at most w
local function wrap(s, w, maxLines)
  local lines, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    if #line == 0 then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else lines[#lines + 1] = line line = word end
  end
  if #line > 0 then lines[#lines + 1] = line end
  if maxLines and #lines > maxLines then
    lines[maxLines] = trunc(lines[maxLines] .. " " .. table.concat(lines, " ", maxLines + 1), w)
    for i = #lines, maxLines + 1, -1 do lines[i] = nil end
  end
  return lines
end

-- "name ....... 1,234" list, biggest first
local function itemList(x, y, w, rows, t, empty)
  local list = {}
  for k, v in pairs(t or {}) do list[#list + 1] = { k, v } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  if #list == 0 then text(x, y, trunc(empty, w), C.dim, C.panel) return end
  for i = 1, math.min(rows, #list) do
    if i == rows and #list > rows then
      text(x, y + i - 1, trunc("+ " .. (#list - rows + 1) .. " more kinds", w), C.dim, C.panel)
    else
      kv(x, y + i - 1, w, trunc(itemName(list[i][1]), w - 10), commas(list[i][2]))
    end
  end
end

-- one turtle: name, status pill, why (2 lines), fuel bar, position
local function unitBox(x, y, w, u, role)
  local lab, col, why = MINE.status(u)
  text(x, y, role, C.dim, C.panel)
  local name = u and ((u.label or "?") .. " #" .. u.id .. (u.ver and ("  " .. u.ver) or "")) or "-"
  text(x + #role + 1, y, trunc(name, w - #role - #lab - 5), C.text, C.panel)
  pill(x + w - #lab - 2, y, lab, C.ink, col)
  local bad = (col == C.bad or col == C.warn)
  for i, line in ipairs(wrap(why, w, 2)) do text(x, y + i, line, bad and col or C.dim, C.panel) end
  if not u then return end
  local fuel = tonumber(u.fuel)
  local fmax = tonumber(u.fuelMax) or 20000
  if fuel then
    local f = math.max(0, math.min(1, fuel / fmax))
    local fc = (fuel < 500 and C.bad) or (fuel < 2000 and C.warn) or C.good
    local lbl = "fuel " .. commas(fuel)
    text(x, y + 3, lbl, C.dim, C.panel)
    barW(x + #lbl + 1, y + 3, w - #lbl - 1, f * (w - #lbl - 1), fc)
  else
    text(x, y + 3, "fuel " .. tostring(u.fuel or "?"), C.dim, C.panel)
  end
  local p = u.pos
  local where = (p and p.x) and fmtPos(p.x, p.y, p.z) or "position unknown"
  text(x, y + 4, trunc(where .. (p and p.f and ("  facing " .. p.f) or "") ..
       (u.free and ("   " .. u.free .. " free slots") or ""), w), C.dim, C.panel)
end

-- the field: one cell per chunk in the order they are mined (rows go to the
-- right); done green, current yellow, still to do dark. Newest rows only.
local function fieldMap(x, y, w, h, m)
  local L = tonumber(m.rowLength) or tonumber(MINE.cfg("rowLength", 16)) or 16
  local ci = tonumber(m.ci) or 0
  local cellW = 2
  local cols = math.max(1, math.floor((w + 1) / (cellW + 1)))
  local rows = math.floor(ci / L) + 1
  local first = math.max(0, rows - h)
  for r = first, rows - 1 do
    local yy = y + (r - first)
    for k = 0, math.min(L, cols) - 1 do
      local i = r * L + ((r % 2 == 0) and k or (L - 1 - k))
      local col = (i < ci and C.good) or (i == ci and C.warn) or C.empty
      text(x + k * (cellW + 1), yy, (" "):rep(cellW), C.text, col)
    end
  end
end

local function teamCard(x, y, w, h, dim, team)
  card(x, y, w, h, dim:upper() .. " MINING DIMENSION")
  local m, l = team.miner, team.loader
  local ix, iw = x + 2, w - 4
  local leftW = math.floor(iw * 0.64)
  local bx, bw = ix + leftW + 2, iw - leftW - 2
  local half = math.floor((leftW - 2) / 2)
  local bottom = y + h - 2
  unitBox(ix, y + 3, half, m, "MINER")
  unitBox(ix + half + 2, y + 3, leftW - half - 2, l, "LOADER")

  -- progress: field map on the left, numbers + bars on the right
  local py = y + 9
  if m and py + 4 <= bottom then
    text(ix, py, "FIELD", C.label, C.panel)
    local mapW = math.min(half, 3 * (tonumber(m.rowLength) or tonumber(MINE.cfg("rowLength", 16)) or 16))
    fieldMap(ix, py + 1, mapW, 3, m)
    local nx, nw = ix + half + 2, leftW - half - 2
    local st = m.stats or {}
    local ci = tonumber(m.ci) or 0
    text(nx, py, trunc("chunk " .. ci .. "   " .. math.max(0, ci - 1) .. " done   " .. commas(st.ores or 0) .. " ores", nw),
         C.text, C.panel)
    if m.phase == "layers" and m.li and m.nl then
      local lbl = "layer " .. math.min(m.li, m.nl) .. "/" .. m.nl
      text(nx, py + 1, lbl, C.dim, C.panel)
      barW(nx + #lbl + 1, py + 1, nw - #lbl - 1, (math.min(m.li, m.nl) - 1) / m.nl * (nw - #lbl - 1), C.accent)
    else
      text(nx, py + 1, trunc(m.phase == "exit" and "on to the next chunk" or (m.phase == "go" and "tunnel to the chunk centre") or "", nw),
           C.dim, C.panel)
    end
    local rate = ""
    if m.runT0 and os.clock() - m.runT0 > 300 then
      local per = ((tonumber(st.ores) or 0) - (m.ores0 or 0)) / ((os.clock() - m.runT0) / 3600)
      rate = commas(math.floor(per)) .. " ores/hour   "
    end
    text(nx, py + 2, trunc(rate .. (st.dumps or 0) .. " unloads", nw), C.dim, C.panel)
    if m.nextDump and m.running then
      local left = math.max(0, m.nextDump - os.clock())
      local every = tonumber(MINE.cfg("dumpEvery", 600)) or 600
      local lbl = "unload in " .. mmss(left)
      text(nx, py + 3, lbl, C.dim, C.panel)
      barW(nx + #lbl + 1, py + 3, nw - #lbl - 1, (1 - left / every) * (nw - #lbl - 1), C.purple)
    elseif m.station == false then
      text(nx, py + 3, trunc("no unload station (miner station)", nw), C.warn, C.panel)
    end
  end

  -- items
  local listY = py + 6
  if listY + 1 <= bottom then
    local rows = math.max(1, bottom - listY)
    text(ix, listY, trunc("IN THE SHULKER  " .. commas(total(m and m.carry)), half), C.label, C.panel)
    text(ix + half + 2, listY, trunc("DELIVERED  " .. commas(total(m and m.got)), leftW - half - 2), C.label, C.panel)
    itemList(ix, listY + 1, half, rows, m and m.carry, "nothing yet")
    itemList(ix + half + 2, listY + 1, leftW - half - 2, rows, m and m.got, "nothing yet")
  end

  -- right: buttons, hint, log
  local by = y + 3
  if m then
    if m.running then
      drawButton(bx, by, bw, 3, "PAUSE", C.warn, C.ink, "minecmd", { m.id, "pause" })
    else
      drawButton(bx, by, bw, 3, "START", C.good, C.ink, "minecmd", { m.id, "start" })
    end
    local hw = math.floor((bw - 1) / 2)
    drawButton(bx, by + 4, hw, 1, "UNLOAD NOW", C.empty, C.text, "minecmd", { m.id, "unload" })
    actButton(bx + hw + 1, by + 4, bw - hw - 1, 1, "NEW FIELD",
              { kind = "minecmd", name = m.id .. ":newfield", count = 0 })
    by = by + 6
  end
  -- what to do (the first problem found)
  local hint
  local function fuelLow(u, lim) return u and tonumber(u.fuel) and tonumber(u.fuel) < (lim or 500) end
  if not m then hint = "Run miner.lua on the miner turtle (role m)."
  elseif not l then hint = "Run miner.lua on the loader turtle (role l), right behind the miner."
  elseif not MINE.online(m) then hint = "The miner does not report: is its chunk loaded? Look at its screen (bottom line)."
  elseif fuelLow(m) then hint = "Miner: put coal in it, type  refuel all  on it."
  elseif fuelLow(l, 2000) then hint = "Loader: give it a stack of coal (blocks), type  refuel all  - it cannot refuel itself."
  elseif not m.partner then hint = "Not paired yet: both turtles need the same dimension and key; restart both."
  elseif m.err and not m.running then hint = "Fix the problem above, then press START."
  elseif m.station == false then hint = "No unload station: put the miner on it (facing the storage) and type  miner station."
  end
  if hint and by + 2 <= bottom then
    for i, line in ipairs(wrap("TO DO: " .. hint, bw, 3)) do text(bx, by + i - 1, line, C.warn, C.panel) end
    by = by + 4
  end
  if m and by + 1 <= bottom then
    text(bx, by, "LOG", C.label, C.panel)
    local yy = by + 1
    for _, e in ipairs(m.log or {}) do
      if yy > bottom then break end
      local lines = wrap(e.msg, bw - 7, 2)
      for i, line in ipairs(lines) do
        if yy > bottom then break end
        text(bx, yy, (i == 1 and e.t or "") , C.dim, C.panel)
        text(bx + 7, yy, line, C.dim, C.panel)
        yy = yy + 1
      end
    end
  end
end

function drawMiningPage(G)
  local y0, bottom = G.y0, G.y1
  local teams = MINE.teams()
  local shown = {}
  for _, d in ipairs(DIMS) do if teams[d] then shown[#shown + 1] = d end end
  for d in pairs(teams) do
    local known = false
    for _, k in ipairs(DIMS) do if k == d then known = true end end
    if not known then shown[#shown + 1] = d end
  end
  if #shown == 0 then
    card(2, y0, W - 2, 22, "MINING TEAMS")
    local lines = {
      "Two turtles per mining dimension, both running miner.lua:",
      "  MINER   End Automata Core (stays on) + pickaxe; carries an Ender Modem, a Geo Scanner and a shulker box",
      "  LOADER  Chunky upgrade + Ender Modem - keeps the miner's chunk loaded and follows it",
      "",
      "1. The unload station's chunk must stay loaded (a chunk loader, or a player there).",
      "2. Put the MINER on its unload station (facing an empty block with an AE2 Import Bus next to it,",
      "   or facing an ME Interface), copy miner.lua onto it, run  miner  and answer the questions.",
      "3. Pick it up, put it where mining should start (facing the way to mine, away from your base),",
      "   type  miner here  and its new position. Put the LOADER right BEHIND it and run  miner  there.",
      "4. They pair by themselves. Then press START here.",
    }
    for i, s in ipairs(lines) do text(4, y0 + 2 + i, trunc(s, W - 6), i == 1 and C.text or C.dim, C.panel) end
    return
  end
  local h = math.floor((bottom - y0 + 2) / #shown) - 1
  for i, d in ipairs(shown) do
    teamCard(2, y0 + (i - 1) * (h + 1), W - 2, h, d, teams[d])
  end
end
