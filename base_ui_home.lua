-- base_ui_home.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   HOME (the start page, CONTROL ROOM look): a row of live numbers (turtles, drones,
--   AE2, mining, map, players - whatever is connected), NEEDS YOU (each problem with a
--   button to its page), SYSTEM at a glance, LATELY (the newest messages), QUICK
--   ACTIONS (two taps) and GO TO (every page). Uses all the room the monitor has.

local function kb(b) return b and (math.floor(b / 1024) .. " KB") or "..." end
local function pct(a, b) return (b and b > 0) and math.floor(a / b * 100 + 0.5) or 0 end

-- the numbers for the top row: { title, big, unit, line1, line2, share, colour, page }
local function kpis()
  local out = {}
  -- turtles
  local all, on, work, bad, fuel = 0, 0, 0, 0, 0
  for _, t in pairs(state.turtles or {}) do
    all = all + 1
    if TT.online(t) then
      on = on + 1
      fuel = fuel + (tonumber(t.fuel) or 0)
      local key = TT.status(t)
      if key == "busy" or key == "trouble" then work = work + 1 end
      if key == "stuck" or key == "nofuel" or key == "still" then bad = bad + 1 end
    end
  end
  if all > 0 or state.tModem then
    out[#out + 1] = { "TURTLES", on .. "/" .. all, "online", work .. " working" .. (bad > 0 and (", " .. bad .. " need you") or ""),
                      "fuel " .. compact(fuel) .. " all together", all > 0 and on / all or 0,
                      bad > 0 and C.warn or C.good, "turtles" }
  end
  -- drones
  if #(droneOrder or {}) > 0 then
    local ready, minP, busy = 0, nil, 0
    for _, k in ipairs(droneOrder) do
      local dr = drones[k]
      if dr.conn then ready = ready + 1 end
      if dr.busy then busy = busy + 1 end
      if dr.pressure then minP = math.min(minP or 99, dr.pressure) end
    end
    out[#out + 1] = { "DRONES", ready .. "/" .. #droneOrder, "ready", busy > 0 and (busy .. " on a job") or "all docked",
                      minP and string.format("lowest air %.1f bar", minP) or "air not known", minP and minP / 10 or 0,
                      (minP and minP < 3) and C.warn or C.orange, "drone" }
  end
  -- AE2
  if bridge and type(state.me) == "table" and not state.me.err then
    local me = state.me
    local n = 0
    for _, it in ipairs(me.items or {}) do n = n + (tonumber(it.count or it.amount) or 0) end
    local used, total = tonumber(me.usedItem or me.used), tonumber(me.totalItem or me.total)
    out[#out + 1] = { "AE2 STORAGE", compact(n), "items", #(me.items or {}) .. " kinds, " .. #(me.fluids or {}) .. " fluids",
                      (used and total and total > 0) and (pct(used, total) .. "% of the space used") or (me.online == false and "OFFLINE" or "online"),
                      (used and total and total > 0) and used / total or 0, me.online == false and C.bad or C.purple, "me" }
  end
  -- mining
  if MINE and next(MINE.units or {}) then
    local rate, ores, teams, running = 0, 0, 0, 0
    for _, team in pairs(MINE.teams()) do
      local T = MINE.totals(team)
      teams = teams + 1
      rate, ores = rate + (T.rate or 0), ores + (T.ores or 0)
      if team.loader and team.loader.running then running = running + 1 end
    end
    out[#out + 1] = { "MINING", compact(math.floor(rate)), "ores/h", running .. " of " .. teams .. " team(s) running",
                      compact(ores) .. " ores so far", teams > 0 and running / teams or 0, C.pink, "mining" }
  end
  -- map
  if MAP.hasData and MAP.hasData() then
    local frac = MAP.surveyProgress and MAP.surveyProgress()
    out[#out + 1] = { "MAP", compact(MAP.ovN or 0), "chunks", "auto-map " .. ((MAP.auto and MAP.auto.on) and "ON" or "OFF"),
                      frac and ("survey " .. math.floor(frac * 100) .. "% done") or "no survey running", frac or 0, C.lime, "map" }
  end
  -- players
  if det then
    local n, allowed = #(state.players or {}), 0
    for _ in pairs(state.access and state.access.allowed or {}) do allowed = allowed + 1 end
    local online = 0
    for _ in pairs(state.online or {}) do online = online + 1 end
    out[#out + 1] = { "PLAYERS", tostring(n), "seen", (AWAY and AWAY.on) and "you are AWAY" or "you are here",
                      allowed .. " may use the drones", n > 0 and math.min(1, online / n) or 0, C.info, "players" }
  end
  return out
end

-- what needs the owner: { colour, title, detail, page, button }
local function needs()
  local out = {}
  for _, t in ipairs(TT.list and TT.list() or {}) do
    local key, lab, _, why = TT.status(t)
    if key == "stuck" or key == "nofuel" or key == "still" or key == "missing" then
      out[#out + 1] = { key == "missing" and C.bad or C.warn, t.label .. ": " .. lab, why or "", "turtles", "OPEN" }
    end
    if TT.dupText and TT.dupText(t) then out[#out + 1] = { C.warn, t.label .. ": HAS COPIES", TT.dupText(t), "turtles", "OPEN" } end
  end
  local lost = TT.lostList and #TT.lostList() or 0
  if lost > 0 and not TT.party then out[#out + 1] = { C.warn, lost .. " turtle(s) lost", "the search party can look for them", "turtles", "OPEN" } end
  if MINE then
    for _, u in pairs(MINE.units or {}) do
      local lab, col, line = MINE.status(u)
      if lab == "STOPPED" or lab == "BLOCKED" or lab == "NO FUEL" or (lab == "OFFLINE" and u.seenEpoch) then
        out[#out + 1] = { col, (u.label or ("#" .. u.id)) .. ": " .. lab, line or "", "mining", "OPEN" }
      end
    end
  end
  for _, k in ipairs(droneOrder or {}) do
    local dr = drones[k]
    if dr.mission and dr.mission.state == "failed" then
      out[#out + 1] = { C.warn, dr.label .. ": " .. tostring(dr.mission.title) .. " failed", tostring(dr.mission.err or ""), "drone", "OPEN" }
    end
  end
  if DW and DW.job and DW.job.paused then out[#out + 1] = { C.warn, "Drone build paused", DW.job.paused, "work", "OPEN" } end
  if state.diskLow then out[#out + 1] = { C.bad, "Disk almost full", state.diskLow, "system", "OPEN" } end
  local s = state.sys or {}
  if s.mapFree and s.mapFloppies and s.mapFloppies > 0 and s.mapFree < 40960 then
    out[#out + 1] = { C.warn, "Data floppies almost full", kb(s.mapFree) .. " left - put in an empty floppy", "system", "OPEN" }
  end
  if bridge and type(state.me) == "table" and state.me.online == false then
    out[#out + 1] = { C.bad, "AE2 network offline", "the ME Bridge sees no network", "me", "OPEN" }
  end
  return out
end

local function kpiPanel(x, y, w, h, k)
  local ix, iy, iw = panel(x, y, w, h, k[1], { col = C.line })
  addHit(x, y, w, h, "page", k[8])
  local bw = big(ix, iy + 1, k[2], k[7] == C.good and C.text or k[7], C.panel)
  if iw - bw - 1 >= #k[3] then text(ix + bw + 1, iy + 2, k[3], C.dim, C.panel) end
  text(ix, iy + 4, trunc(k[4], iw), C.text, C.panel)
  if h >= 9 then text(ix, iy + 5, trunc(k[5], iw), C.dim, C.panel) end
  gauge(ix, y + h - 2, iw, k[6], k[7])
end

local function quickActs()
  local acts = {}
  if next(state.turtles or {}) then
    acts[#acts + 1] = { "STOP ALL TURTLES", { kind = "quick", name = "allstop", count = 0 }, C.bad }
    acts[#acts + 1] = { "ALL TURTLES HOME", { kind = "quick", name = "allhome", count = 0 }, C.warn }
    acts[#acts + 1] = { "UPDATE TURTLES", { kind = "sysupdate", name = "all", count = 0 }, C.info }
    if TT.party then
      acts[#acts + 1] = { "CALL BACK SEARCH", { kind = "quick", name = "party", count = 0 }, C.orange }
    elseif #TT.lostList() > 0 then
      acts[#acts + 1] = { "FIND LOST (" .. #TT.lostList() .. ")", { kind = "quick", name = "party", count = 0 }, C.orange }
    end
  end
  if #(droneOrder or {}) > 0 then
    acts[#acts + 1] = { "DRONE: TAKE ME HOME", { kind = "quick", name = "ride", args = { "base" }, count = 0 }, C.orange }
  end
  acts[#acts + 1] = { "SAVE THE MAP", { kind = "syssave", name = "map", count = 0 }, C.good }
  return acts
end

function drawHomePage(G)
  local y0, y1 = G.y0, G.y1
  local gap = 1
  ------------------------------------------------ the numbers
  local K = kpis()
  local maxN = W >= 150 and 6 or (W >= 120 and 5 or 4)
  while #K > maxN do table.remove(K) end
  local kh = 10
  local y = y0
  if #K > 0 then
    local kw = math.floor((W - 2 - (#K - 1) * gap) / #K)
    for i, k in ipairs(K) do
      local x = 2 + (i - 1) * (kw + gap)
      kpiPanel(x, y, (i == #K) and (W - x) or kw, kh, k)
    end
    y = y + kh + gap
  end
  ------------------------------------------------ needs you + system
  local leftW = math.floor((W - 3) * 0.6)
  local rx, rw = 2 + leftW + gap, W - (2 + leftW + gap) + 1 - 1
  local rest = y1 - y + 1
  local N = needs()
  -- as tall as what is in it (the system list or the problems), at most half the rest
  local midH = math.max(12, math.min(#N * 3 + 3, math.floor((rest - gap) * 0.5)))
  local ix, iy, iw, ih = panel(2, y, leftW, midH, "NEEDS YOU", { right = #N > 0 and (#N .. " open") or "all clear",
                                                                 rcol = #N > 0 and C.warn or C.good, col = #N > 0 and C.warn or C.line })
  if #N == 0 then
    led(ix, iy, C.good)
    text(ix + 2, iy, "Nothing needs you - every turtle, drone and team is fine.", C.good, C.panel)
  else
    local per = 3
    local rows = math.floor((ih - 1) / per)
    for i, n in ipairs(N) do
      if i > rows then
        text(ix, iy + ih - 1, "+" .. (#N - rows + 1) .. " more - open their pages", C.dim, C.panel)
        break
      end
      local ry = iy + (i - 1) * per
      if i == rows and #N > rows then break end
      cell(ix, ry, 1 + 4 + 16, n[1], C.panel)
      cell(ix, ry + 1, 1 + 4 + 16, n[1], C.panel)
      text(ix + 2, ry, trunc(n[2], iw - 14), C.text, C.panel)
      text(ix + 2, ry + 1, trunc(n[3], iw - 14), C.dim, C.panel)
      button(ix + iw - 10, ry, 10, 2, n[5], n[1], "page", n[4])
    end
  end
  -- system
  local s = state.sys or {}
  local A = BASE_ALIVE or {}
  local now = os.epoch("utc")
  local sx, sy, sw = panel(rx, y, rw, midH, "SYSTEM", { right = (THEME_NAME or "") .. " theme" })
  local lines = {
    { "Base running", fmtSpan and fmtSpan((now - (A.since or now)) / 1000) or "?", C.text },
    { "Computer disk", (s.pcFree and s.pcCap) and (kb(s.pcFree) .. " free of " .. kb(s.pcCap)) or "...",
      (s.pcFree and s.pcFree < 65536) and C.bad or C.text, s.pcCap and (1 - (s.pcFree or 0) / s.pcCap) },
    { "Data floppies", s.mapFloppies and (s.mapFloppies .. " (" .. kb(s.mapFree) .. " free)") or "none",
      (s.mapFree and s.mapFree < 40960) and C.warn or C.text },
    { "Turtle program", (CODE and TT.verName(CODE.ver) or "none") ..
      ((s.turtlesAll and s.turtlesAll > 0) and ("  " .. s.turtlesUp .. "/" .. s.turtlesAll .. " up to date") or ""), C.text },
    { "AE2 bridge", bridge and ((type(state.me) == "table" and state.me.online ~= false) and "online" or "offline") or "not connected",
      bridge and C.good or C.dim },
    { "Player detector", det and "connected" or "not connected", det and C.good or C.dim },
    { "Away mode", (AWAY and AWAY.on) and "ON - you are away" or "off", (AWAY and AWAY.on) and C.label or C.dim },
    { "Factory", FACTORY and (FACTORY.statusLine()) or "-", C.text },
    { "Messages", #state.noteLog .. " kept" .. ((state.noteUnread or 0) > 0 and (", " .. state.noteUnread .. " new") or ""),
      (state.noteUnread or 0) > 0 and C.warn or C.text },
  }
  local r = sy
  for _, l in ipairs(lines) do
    if r > y + midH - 2 then break end
    kv(sx, r, sw, l[1], l[2], l[3])
    r = r + 1
    if l[4] and r <= y + midH - 2 then gauge(sx, r, sw, l[4], (l[4] > 0.9) and C.bad or C.accent) r = r + 1 end
  end
  y = y + midH + gap
  ------------------------------------------------ lately + quick actions + go to
  local bh = y1 - y + 1
  if bh < 6 then return end
  local lx, ly, lw, lh = panel(2, y, leftW, bh, "LATELY", { right = "MESSAGES page: all of them" })
  addHit(2, y, 20, 1, "page", "events")
  local rr = ly
  for _, e in ipairs(state.noteLog or {}) do
    if rr > y + bh - 2 then break end
    local when = tostring(e.when or ""):match("(%d+:%d+)") or tostring(e.when or "")
    text(lx, rr, when, C.dim, C.panel)
    led(lx + 6, rr, e.col or C.dim)
    local s2 = (e.title and (e.title .. ": ") or "") .. tostring(e.msg or "")
    text(lx + 8, rr, trunc((s2:gsub("%s+", " ")), lw - 8), C.text, C.panel)
    rr = rr + 1
  end
  if rr == ly then text(lx, rr, "No messages yet.", C.dim, C.panel) end
  local qx, qy, qw, qh = panel(rx, y, rw, bh, "QUICK ACTIONS", { right = "two taps" })
  local acts = quickActs()
  local cols = 2
  local bw = math.floor((qw - (cols - 1)) / cols)
  local by = qy
  for i, a in ipairs(acts) do
    local c = (i - 1) % cols
    local rrow = math.floor((i - 1) / cols)
    local yy = by + rrow * 4
    if yy + 2 > y + bh - 2 then break end
    actButton(qx + c * (bw + 1), yy, (c == cols - 1) and (qw - c * (bw + 1)) or bw, 3, a[1], a[2], false, a[3])
  end
  -- every page, small (under the actions, when there is room)
  local gy = by + math.ceil(#acts / cols) * 4 + 1
  if gy + 3 <= y + bh - 2 then
    heading(qx, gy, qw, "GO TO")
    gy = gy + 1
    local pages = {}
    for _, g in ipairs(headerTabs()) do
      for _, m in ipairs(g.members) do if m[1] ~= "home" then pages[#pages + 1] = m end end
    end
    local pcols = qw >= 60 and 4 or 3
    local pw = math.floor((qw - (pcols - 1)) / pcols)
    local nrows = math.ceil(#pages / pcols)
    local tall = nrows * 4 <= (y + bh - 2) - gy + 1           -- framed buttons when they fit
    local step, hh = tall and 4 or 3, tall and 3 or 2
    for i, m in ipairs(pages) do
      local c = (i - 1) % pcols
      local yy = gy + math.floor((i - 1) / pcols) * step
      if yy + hh - 1 > y + bh - 2 then break end
      local label = (PAGE_INFO[m[1]] and PAGE_INFO[m[1]][1] or m[2]) .. ((m[3] and m[3] ~= "") and (" " .. m[3]) or "")
      button(qx + c * (pw + 1), yy, (c == pcols - 1) and (qw - c * (pw + 1)) or pw, hh, label, m[4] or C.line, "page", m[1], m[4] ~= nil)
    end
  end
end
