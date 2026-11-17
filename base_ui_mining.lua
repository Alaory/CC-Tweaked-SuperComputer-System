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

-- one turtle in two lines: light, role, name, status badge, fuel gauge; then what it does
local function unitRow(x, y, w, u, role)
  local lab, col, why = MINE.status(u)
  local tag = role .. (u and u.idx and (" " .. u.idx) or "")
  led(x, y, col)
  text(x + 2, y, tag, C.dim, C.panel)
  local name = u and ((u.label or "?") .. " #" .. u.id .. (u.ver and (" " .. u.ver) or "")) or "-"
  local bwid = #lab + 2
  local fw = math.max(6, math.floor(w * 0.22))
  text(x + 11, y, trunc(name, w - 11 - bwid - fw - 2), C.text, C.panel)
  badge(x + w - bwid, y, lab, col)
  local fuel = u and tonumber(u.fuel)
  if fuel then
    gauge(x + w - bwid - fw - 1, y, fw, fuel / (tonumber(u.fuelMax) or 20000),
          (fuel < 500 and C.bad) or (fuel < 2000 and C.warn) or C.good)
  end
  local bad = (col == C.bad or col == C.warn)
  text(x + 2, y + 1, trunc(why, w - 2), bad and col or C.dim, C.panel)
end

-- the field: one cell per chunk in the order they are mined (rows go to the right);
-- done green, current yellow, still to do dark. Newest rows only.
local function fieldMap(x, y, w, h, ci, L)
  local cellW = 2
  local cols = math.max(1, math.floor((w + 1) / (cellW + 1)))
  local rows = math.floor(ci / L) + 1
  local first = math.max(0, rows - h)
  for r = first, rows - 1 do
    local yy = y + (r - first)
    for k = 0, math.min(L, cols) - 1 do
      local i = r * L + ((r % 2 == 0) and k or (L - 1 - k))
      local col = (i < ci and C.good) or (i == ci and C.warn) or C.line
      text(x + k * (cellW + 1), yy, (" "):rep(cellW), C.text, col)
    end
  end
end

local function teamCard(x, y, w, h, dim, team)
  local l, miners = team.loader, team.miners
  local T = MINE.totals(team)
  local runCol = (l and l.running) and C.good or C.warn
  local ix, iy, iw = panel(x, y, w, h, dim:upper() .. " MINING DIMENSION",
                           { right = "1 loader + " .. #miners .. " miner" .. (#miners == 1 and "" or "s") ..
                                     ((l and l.running) and "  -  RUNNING" or "  -  PAUSED"), rcol = runCol })
  local leftW = math.floor(iw * 0.64)
  local bx, bw = ix + leftW + 2, iw - leftW - 2
  local bottom = y + h - 2
  local half = math.floor((leftW - 2) * 0.56)
  -- the turtles
  local ry = iy
  unitRow(ix, ry, half, l, "LOADER")
  ry = ry + 3
  for k, m in ipairs(miners) do
    if ry + 1 > bottom - 4 then
      text(ix, ry, trunc("+" .. (#miners - k + 1) .. " more miners", half), C.dim, C.panel)
      ry = ry + 1
      break
    end
    unitRow(ix, ry, half, m, "MINER")
    ry = ry + 3
  end
  if #miners == 0 then text(ix, ry, trunc("No miner yet: run miner.lua on one (role m)", half), C.warn, C.panel) ry = ry + 1 end
  -- progress: the field, ores per hour (big), unloads
  local nx, nw = ix + half + 2, leftW - half - 2
  local ci = tonumber(T.ci) or 0
  local L = (l and tonumber(l.rowLength)) or tonumber(MINE.cfg("rowLength", 16)) or 16
  heading(nx, iy, nw, "FIELD")
  fieldMap(nx, iy + 1, math.min(nw, 3 * L), 3, ci, L)
  text(nx, iy + 5, trunc(T.moving and "moving away from the station" or ("chunk " .. ci .. "  -  " .. math.max(0, ci - 1) .. " done"), nw),
       T.moving and C.warn or C.text, C.panel)
  local bwid = big(nx, iy + 7, compact(math.floor(T.rate or 0)), C.label, C.panel)
  text(nx + bwid + 1, iy + 7, "ores", C.dim, C.panel)
  text(nx + bwid + 1, iy + 8, "an hour", C.dim, C.panel)
  text(nx, iy + 10, trunc(commas(T.ores) .. " ores, " .. T.dumps .. " unloads", nw), C.text, C.panel)
  text(nx, iy + 11, trunc((l and l.phase == "cross") and "crossing into the next chunk" or
       ((l and l.ready and #miners > 0) and (l.ready .. "/" .. #miners .. " at their lanes") or ""), nw), C.dim, C.panel)
  -- items
  local listY = math.max(ry + 1, iy + 13)
  if listY + 1 <= bottom then
    local rows = math.max(1, bottom - listY)
    local lw = math.floor((leftW - 2) / 2)
    heading(ix, listY, lw, "IN THE SHULKERS " .. commas(total(T.carry)))
    heading(ix + lw + 2, listY, leftW - lw - 2, "DELIVERED " .. commas(total(T.got)))
    itemList(ix, listY + 1, lw, rows, T.carry, "nothing yet")
    itemList(ix + lw + 2, listY + 1, leftW - lw - 2, rows, T.got, "nothing yet")
  end
  -- right: the buttons (to the loader = the whole team), what to do, the log
  for j = iy, bottom do cell(bx - 2, j, 1 + 4 + 16, C.line, C.panel) end       -- a thin divider
  local by = iy
  if l then
    if l.running then button(bx, by, bw, 3, "PAUSE TEAM", C.warn, "minecmd", { l.id, "pause" }, true)
    else button(bx, by, bw, 3, "START TEAM", C.good, "minecmd", { l.id, "start" }, true) end
    local hw = math.floor((bw - 1) / 2)
    button(bx, by + 4, hw, 3, "UNLOAD NOW", C.line, "minecmd", { l.id, "unload" })
    actButton(bx + hw + 1, by + 4, bw - hw - 1, 3, "NEW FIELD", { kind = "minecmd", name = l.id .. ":newfield", count = 0 }, false, C.orange)
    by = by + 8
    if MINE.upd then
      by = para(bx, by, bw, "UPDATING the miners - the team is paused until all have it", C.warn, 2) + 1
    elseif by + 3 <= bottom then
      actButton(bx, by, bw, 3, "UPDATE MINERS (" .. tostring(l.ver or "?") .. ")", { kind = "mineupdate", name = "all", count = 0 }, false, C.info)
      by = by + 4
    end
  end
  local hint, dropMe
  local function fuelLow(u, lim) return u and tonumber(u.fuel) and tonumber(u.fuel) < (lim or 500) end
  if not l then hint = "Run miner.lua on the loader turtle (role l), standing on the surface."
  elseif #miners == 0 then hint = "Run miner.lua on the miners (role m), next to the loader in its chunk."
  elseif fuelLow(l, 2000) then hint = "Loader: give it fuel - an endless fuel item if your pack has one, else coal (blocks)."
  elseif l.err and not l.running then hint = tostring(l.err) .. " - then START TEAM."
  else
    for _, m in ipairs(miners) do
      if not MINE.online(m) then
        local long = m.seenEpoch and os.epoch("utc") - m.seenEpoch > 1200000
        hint = (m.label or ("#" .. m.id)) .. " does not report: chunk loaded? look at its screen." ..
               (long and "  Gone for good (server crash)? DROP takes it out of the team." or "")
        if long then dropMe = m end
        break
      end
      if fuelLow(m) then hint = (m.label or ("#" .. m.id)) .. ": give it fuel (an endless fuel item or coal)." break end
      if m.station == false then hint = (m.label or ("#" .. m.id)) .. " has no unload station: put it on the station, type  miner station." break end
      if m.err and not m.running then hint = (m.label or ("#" .. m.id)) .. ": " .. tostring(m.err) break end
    end
  end
  if hint and by + 2 <= bottom then
    badge(bx, by, "TO DO", C.warn)
    by = para(bx, by + 1, bw, hint, C.warn, 3) + 1
    if dropMe and by + 2 <= bottom then
      actButton(bx, by, bw, 3, "DROP " .. (dropMe.label or ("#" .. dropMe.id)) .. " (gone for good)",
                { kind = "minedrop", name = tostring(dropMe.id), count = 0 }, false, C.bad)
      by = by + 4
    end
  end
  if by + 1 <= bottom then
    heading(bx, by, bw, "LOG (whole team)")
    local all = {}
    local function add(u, tag)
      for i, e in ipairs(u and u.log or {}) do all[#all + 1] = { t = e.t, e = e.e or 0, msg = tag .. e.msg, o = i } end
    end
    add(l, "L: ")
    for _, m in ipairs(miners) do add(m, (m.idx or "?") .. ": ") end
    table.sort(all, function(a1, b2) if a1.e ~= b2.e then return a1.e > b2.e end return a1.o < b2.o end)
    local yy = by + 1
    for _, e in ipairs(all) do
      if yy > bottom then break end
      for i, line in ipairs(wrap(e.msg, bw - 7, 2)) do
        if yy > bottom then break end
        text(bx, yy, (i == 1 and e.t or ""), C.dim, C.panel)
        text(bx + 7, yy, line, C.text, C.panel)
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
    panel(2, y0, W - 2, 22, "MINING TEAMS", { right = "none yet" })
    local lines = {
      "A team per mining dimension: ONE loader + up to 5 miners, all running miner.lua:",
      "  LOADER  Chunky upgrade + Ender Modem - the team leader; keeps the miners' chunk loaded",
      "  MINER   End Automata Core + pickaxe; carries an Ender Modem, a Geo Scanner, a shulker box and fuel",
      "",
      "1. The unload station's chunk must stay loaded (a chunk loader, or a player there).",
      "2. EACH miner once: put it on the unload station (facing the storage), run  miner , answer the questions",
      "   (y = standing on the station). Then pick it up.",
      "3. Put the LOADER on the SURFACE where mining starts, facing the way to mine; run  miner  (role l).",
      "4. Put the miners on the surface next to the loader - in the SAME chunk; type  miner here  on each.",
      "5. They join the loader by themselves. Then press START TEAM here.",
      "6. One more miner LATER, while they work: put it next to the loader (same chunk), type  miner here .",
    }
    for i, s in ipairs(lines) do text(4, y0 + 1 + i, trunc(s, W - 6), i == 1 and C.text or C.dim, C.panel) end
    return
  end
  local h = math.floor((bottom - y0 + 2) / #shown) - 1
  for i, d in ipairs(shown) do
    teamCard(2, y0 + (i - 1) * (h + 1), W - 2, h, d, teams[d])
  end
end
