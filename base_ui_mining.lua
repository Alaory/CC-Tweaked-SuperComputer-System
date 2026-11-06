-- base_ui_mining.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MINING tab (TURTLES group): one card per mining dimension team (miner +
--   loader, miner.lua): what they do, what is in the shulker, what reached
--   the ME, and START / PAUSE / UNLOAD NOW / NEW FIELD.

local DIMS = { "overworld", "nether", "end" }

local function itemName(n)
  n = tostring(n):gsub("^[^:]+:", ""):gsub("_", " ")
  return n
end
local function mmss(s)
  s = math.max(0, math.floor(s))
  return math.floor(s / 60) .. ":" .. string.format("%02d", s % 60)
end

-- "name ....... 1,234" list, biggest first
local function itemList(x, y, w, rows, t, empty)
  local list = {}
  for k, v in pairs(t or {}) do list[#list + 1] = { k, v } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  if #list == 0 then text(x, y, trunc(empty, w), C.dim, C.panel) return end
  for i = 1, math.min(rows, #list) do
    kv(x, y + i - 1, w, trunc(itemName(list[i][1]), w - 10), commas(list[i][2]))
  end
end

local function unitLines(x, y, w, u, role)
  local lab, col, why = MINE.status(u)
  text(x, y, role, C.dim, C.panel)
  local name = u and ((u.label or "?") .. "  #" .. u.id .. (u.ver and ("  " .. u.ver) or "")) or "-"
  text(x + #role + 2, y, trunc(name, w - #role - #lab - 8), C.text, C.panel)
  pill(x + w - #lab - 2, y, lab, C.ink, col)
  text(x, y + 1, trunc(why, w), (col == C.bad or col == C.warn) and col or C.dim, C.panel)
  if u then
    local p = u.pos
    local where = (p and p.x) and fmtPos(p.x, p.y, p.z) or "position unknown"
    local fuel = (type(u.fuel) == "number") and commas(u.fuel) or tostring(u.fuel or "?")
    text(x, y + 2, trunc(where .. "   fuel " .. fuel .. (u.free and ("   free slots " .. u.free) or ""), w),
         C.dim, C.panel)
  end
end

local function teamCard(x, y, w, h, dim, team)
  card(x, y, w, h, dim:upper() .. " MINING DIMENSION")
  local m, l = team.miner, team.loader
  local ix, iw = x + 2, w - 4
  local leftW = math.floor(iw * 0.62)
  local bx, bw = ix + leftW + 2, iw - leftW - 2
  local half = math.floor((leftW - 2) / 2)
  unitLines(ix, y + 3, half, m, "MINER")
  unitLines(ix + half + 2, y + 3, leftW - half - 2, l, "LOADER")
  -- progress
  local yy = y + 7
  if m then
    local parts = {}
    if m.ci then parts[#parts + 1] = "chunk " .. m.ci .. (m.li and m.nl and m.phase == "layers" and
                                       (" (layer " .. m.li .. "/" .. m.nl .. ")") or "") end
    local st = m.stats or {}
    parts[#parts + 1] = "ores " .. commas(st.ores or 0)
    parts[#parts + 1] = "unloads " .. (st.dumps or 0)
    if m.nextDump and m.running then parts[#parts + 1] = "next unload in " .. mmss(m.nextDump - os.clock()) end
    text(ix, yy, trunc(table.concat(parts, "   "), leftW), C.text, C.panel)
    if m.station == false then
      text(ix, yy + 1, trunc("No unload station: everything stays in the shulker - put the miner on it and type  miner station", leftW),
           C.warn, C.panel)
    end
  end
  -- items
  local listY = yy + 3
  local rows = math.max(1, y + h - 2 - listY - 1)
  text(ix, listY, "IN THE SHULKER", C.label, C.panel)
  text(ix + half + 2, listY, "DELIVERED TO THE ME", C.label, C.panel)
  itemList(ix, listY + 1, half, rows, m and m.carry, "nothing yet")
  itemList(ix + half + 2, listY + 1, leftW - half - 2, rows, m and m.got, "nothing yet")
  -- buttons + log
  if m then
    local by = y + 3
    if m.running then
      drawButton(bx, by, bw, 3, "PAUSE", C.warn, C.ink, "minecmd", { m.id, "pause" })
    else
      drawButton(bx, by, bw, 3, "START", C.good, C.ink, "minecmd", { m.id, "start" })
    end
    local hw = math.floor((bw - 1) / 2)
    drawButton(bx, by + 4, hw, 1, "UNLOAD NOW", C.empty, C.text, "minecmd", { m.id, "unload" })
    drawButton(bx + hw + 1, by + 4, bw - hw - 1, 1, "NEW FIELD", C.empty, C.text, "minecmd", { m.id, "newfield" })
    local ly = by + 6
    text(bx, ly, "LOG", C.label, C.panel)
    local logs = {}
    for _, e in ipairs(m.log or {}) do logs[#logs + 1] = e end
    for i = 1, math.min(#logs, y + h - 2 - ly) do
      text(bx, ly + i, trunc(logs[i].t .. "  " .. logs[i].msg, bw), C.dim, C.panel)
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
      "  LOADER  Chunky upgrade + Ender Modem - keeps the miner's area loaded and follows it",
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
