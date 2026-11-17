-- base_ui_turtles.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   TURTLES (CONTROL ROOM look): the fleet list on the left (status light, version, fuel
--   gauge, where + why). Right: nothing picked = the FLEET board (a counter per status,
--   the numbers, mining teams, search party, what needs a look); a turtle picked = its
--   card (info, the control pad, extras, exit route, rescue), GO TO places and its LOG.

local ORDER = { "busy", "trouble", "still", "stuck", "nofuel", "held", "idle", "offline", "missing" }
local NAMES = { busy = "WORKING", trouble = "FINDING WAY", still = "NOT MOVING", stuck = "STUCK",
                nofuel = "NO FUEL", held = "STOPPED", idle = "IDLE", offline = "OFFLINE", missing = "MISSING" }

local function fuelCol(f) return (f < 1000 and C.bad) or (f < 5000 and C.warn) or C.good end

-- the FLEET board (no turtle picked)
function drawFleet(x, y, w, h, list)
  local count, col, need = {}, {}, {}
  local fuelSum, low, up = 0, nil, 0
  for _, t in ipairs(list) do
    local key, lab, c, why = TT.status(t)
    count[key] = (count[key] or 0) + 1
    col[key] = col[key] or c
    if key == "stuck" or key == "nofuel" or key == "still" or key == "missing" or (key == "idle" and c == C.warn) then
      need[#need + 1] = { t = t, lab = lab, c = c, why = why }
    end
    if TT.dupText(t) then need[#need + 1] = { t = t, lab = "HAS COPIES", c = C.warn, why = TT.dupText(t) } end
    local f = tonumber(t.fuel)
    if f and TT.online(t) then
      fuelSum = fuelSum + f
      if not low or f < tonumber(low.fuel) then low = t end
    end
    if CODE and t.ver == CODE.ver then up = up + 1 end
  end
  -- the counters: one small tile per status that has turtles
  local tiles = {}
  for _, k in ipairs(ORDER) do if count[k] then tiles[#tiles + 1] = k end end
  local th = 6
  local ix, iy, iw = panel(x, y, w, th + 3, "FLEET", { right = #list .. " turtles  -  tap one on the left" })
  if #tiles == 0 then
    text(ix, iy + 1, "No turtles yet - run node.lua on a turtle (same key).", C.dim, C.panel)
  else
    local n = math.max(#tiles, 4)
    local tw = math.floor((iw - (n - 1)) / n)
    for i, k in ipairs(tiles) do
      local tx = ix + (i - 1) * (tw + 1)
      fill(tx, iy, tw, th, C.bg)
      cell(tx, iy, 1 + 4 + 16, col[k] or C.label, C.bg)
      for j = iy + 1, iy + th - 1 do cell(tx, j, 1 + 4 + 16, col[k] or C.label, C.bg) end
      big(tx + 2, iy + 1, tostring(count[k]), col[k] or C.text, C.bg)
      text(tx + 2, iy + 4, trunc(NAMES[k], tw - 3), C.dim, C.bg)
    end
  end
  -- the numbers (left) and what needs a look (right)
  local y2 = y + th + 4
  local h2 = y + h - y2
  local lw = math.floor((w - 1) * 0.5)
  local ax, ay, aw, ah = panel(x, y2, lw, h2, "NUMBERS")
  local r = ay
  kv(ax, r, aw, "Turtles online", (#list - (count.offline or 0) - (count.missing or 0)) .. " of " .. #list) r = r + 1
  kv(ax, r, aw, "Fuel, all together", commas(fuelSum), C.text) r = r + 1
  if low then
    kv(ax, r, aw, "Lowest fuel", low.label .. "  " .. commas(low.fuel), fuelCol(tonumber(low.fuel) or 0)) r = r + 1
  end
  kv(ax, r, aw, "Turtle program", CODE and (up .. "/" .. #list .. " on " .. TT.verName(CODE.ver)) or "none",
     (CODE and up < #list) and C.warn or C.text) r = r + 1
  if TT.updWaiting then text(ax, r, trunc("updates wait until you are offline", aw), C.dim, C.panel) r = r + 1 end
  r = r + 1
  local frac, _, sent = MAP.surveyProgress()
  if frac then
    local q = MAP.queue
    meter(ax, r, aw, q.auto and "Auto-map" or "Survey", math.floor(frac * 100 + 0.5) .. "%  " .. commas(sent or 0) .. " spots", frac, C.accent)
    r = r + 2
  else
    kv(ax, r, aw, "Survey", (MAP.auto and MAP.auto.on) and "auto-map waits for a free turtle" or "none running", C.dim) r = r + 1
  end
  if FACTORY then
    local fl, fc = FACTORY.statusLine()
    kv(ax, r, aw, "Factory", fl, fc) r = r + 1
  end
  local at, inChunk = TT.anchorInfo()
  kv(ax, r, aw, "Anchor", at and (at.label .. (inChunk == false and " - NOT in this chunk" or "")) or "none - the base stops when you leave",
     (not at or inChunk == false) and C.warn or C.good) r = r + 1
  -- mining teams
  if MINE and next(MINE.units) and r + 2 < ay + ah then
    r = r + 1
    heading(ax, r, aw, "MINING TEAMS") r = r + 1
    for dim, team in pairs(MINE.teams()) do
      if r >= ay + ah then break end
      local ll = team.loader and MINE.status(team.loader) or "MISSING"
      local working, bad = 0, 0
      for _, m in ipairs(team.miners) do
        local lab = MINE.status(m)
        if lab == "MINING" or lab == "UNLOADING" or lab == "WAITING" then working = working + 1
        elseif lab ~= "PAUSED" then bad = bad + 1 end
      end
      led(ax, r, bad > 0 and C.warn or C.good)
      text(ax + 2, r, trunc(dim .. ": " .. working .. "/" .. #team.miners .. " mining, loader " .. ll, aw - 2), C.text, C.panel)
      addHit(ax, r, aw, 1, "page", "mining")
      r = r + 1
    end
  end
  -- the search party
  local pl = TT.partyLine and TT.partyLine()
  if pl and r + 1 < ay + ah then
    r = r + 1
    r = para(ax, r, aw, pl, C.label, 3)
  end
  -- right: what needs a look (tap = pick it), turtles silent at the base
  local nx = x + lw + 1
  local bx, by, bw, bh = panel(nx, y2, w - lw - 1, h2, "NEEDS A LOOK", { right = #need > 0 and tostring(#need) or "none",
                                                                         rcol = #need > 0 and C.warn or C.good })
  local ny = by
  local atb = TT.lostAtBase and TT.lostAtBase() or {}
  if #atb > 0 then
    text(bx, ny, trunc(#atb .. " silent AT THE BASE - picked up? (no rescue is sent)", bw), C.warn, C.panel)
    actButton(bx, ny + 1, math.min(bw, 28), 3, "FORGET THEM (" .. #atb .. ")", { kind = "forgetbase", name = "all", count = 0 }, false, C.warn)
    ny = ny + 5
  end
  if #need == 0 then
    led(bx, ny, C.good)
    text(bx + 2, ny, "Nothing needs you.", C.good, C.panel)
  end
  for _, n in ipairs(need) do
    if ny + 1 > by + bh - 1 then break end
    local lw2 = badge(bx, ny, n.lab, n.c)
    text(bx + lw2 + 1, ny, trunc(n.t.label .. "  #" .. n.t.id, bw - lw2 - 1), C.text, C.panel)
    text(bx, ny + 1, trunc(tostring(n.why), bw), C.dim, C.panel)
    addHit(bx, ny, bw, 2, "tsel", n.t.id)
    ny = ny + 3
  end
end

-- the list on the left: 3 rows per turtle
local function drawList(x, y, w, h, list)
  local ix, iy, iw, ih = panel(x, y, w, h, "TURTLES " .. #list, { right = CODE and ("program " .. TT.verName(CODE.ver)) or nil })
  -- buttons at the bottom: find lost ones
  local hw = math.floor((iw - 1) / 2)
  local byy = y + h - 4
  actButton(ix, byy, hw, 3, "FIND LOST NEAR BASE", { kind = "findlost", name = "all", count = 0 }, false, C.info)
  if TT.party then
    actButton(ix + hw + 1, byy, iw - hw - 1, 3, "CALL BACK PARTY", { kind = "party", name = "stop", count = 0 }, false, C.orange)
  else
    actButton(ix + hw + 1, byy, iw - hw - 1, 3, "SEARCH PARTY", { kind = "party", name = "start", count = 0 }, false, C.orange)
  end
  if #list == 0 then
    para(ix, iy + 1, iw, "Waiting for turtles... Run node.lua on a turtle (same key as CONFIG.turtles.key).", C.dim)
    return
  end
  local per = 4
  local rows = math.max(1, math.floor((byy - 1 - iy) / per))
  local off = scrollBar(x, y, w, "tListOff", #list, rows)
  for i = 1, math.min(rows, #list - off) do
    local t = list[off + i]
    local ry = iy + (i - 1) * per
    local sel = state.tSel == t.id
    local on = TT.online(t)
    local bg = sel and C.line or C.panel
    if sel then fill(ix - 1, ry, iw + 2, 3, C.line) end
    local vn = TT.verName(t.ver)
    local old = on and TT.outdated(t)
    local ready = old and CODE and t.updReady == CODE.ver
    local forcedU = TT.updateForce and os.clock() < TT.updateForce
    local upd = old and (t.updState == "sending" and "SENDING UPDATE" or (t.updState == "retry" and "RETRY UPDATE")
                         or (ready and "UPDATE AFTER JOB")
                         or ((not forcedU and (TT.updWaiting or not CONFIG.turtles.autoUpdate)) and "UPDATE WAITS")
                         or "UPDATE QUEUED")
    local key, st, stc, why = TT.status(t)
    if upd and (key == "idle" or key == "busy") then st, stc = ready and "UPDATE READY" or upd, C.label end
    -- row 1: light, name, version, status badge
    led(ix - 1, ry, stc, bg)
    local bwid = #st + 2
    local name = trunc(t.label .. " #" .. t.id, math.max(6, iw - bwid - #vn - 3))
    text(ix + 1, ry, name, sel and C.accent or C.text, bg)
    text(ix + 2 + #name, ry, vn, (CODE and t.ver == CODE.ver) and C.good or C.warn, bg)
    badge(ix + iw - bwid, ry, st, stc)
    -- row 2: fuel gauge + number
    local fs = tonumber(t.fuel) and commas(t.fuel) or tostring(t.fuel or "?")
    if type(t.fuel) == "number" and type(t.fuelMax) == "number" and t.fuelMax > 0 then
      gauge(ix + 1, ry + 1, iw - #fs - 3, t.fuel / t.fuelMax, fuelCol(t.fuel), bg)
    end
    text(ix + iw - #fs, ry + 1, fs, (tonumber(t.fuel) or 0) < 1000 and C.bad or C.dim, bg)
    -- row 3: where + why
    local where = t.pos and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "position unknown"
    local bad = key ~= "idle" and key ~= "busy"
    text(ix + 1, ry + 2, trunc(where .. "  " .. tostring(why or ""), iw - 1), bad and stc or C.dim, bg)
    addHit(ix - 1, ry, iw + 2, 3, "tsel", t.id)
  end
end

-- the picked turtle's card
local function drawCard(x, y, w, t)
  local function cmdBtn(bx, by, bw, bh, label, cmd, args, col, solid)
    button(bx, by, bw, bh, label, col or C.line, "tcmd", { t.id, cmd, args or {} }, solid)
  end
  local sKey, sLab, sCol, sWhy = TT.status(t)
  local ch = 36                                       -- (status, info, fuel, 4 pad rows, exit, rescue)
  local ix, iy, iw = panel(x, y, w, ch, t.label:upper() .. "  #" .. t.id, { right = TT.online(t) and "online" or "OFFLINE",
                                                                          rcol = TT.online(t) and C.good or C.bad, col = sCol == C.bad and C.bad or C.line })
  -- status line
  local bw0 = badge(ix, iy, sLab, sCol)
  local line
  if TT.dupText(t) then line = TT.dupText(t)
  elseif CODE and TT.online(t) and TT.outdated(t) then
    line = (t.updReady == CODE.ver) and ("has " .. TT.verName(CODE.ver) .. " ready - installs when its job is done")
           or (t.updState == "sending") and ("sending " .. TT.verName(CODE.ver) .. " now (" .. #CODE.pieces .. " pieces)")
           or (t.updState == "retry") and ("update: " .. tostring(t.updNote or "failed") .. " - next try in " ..
               math.max(0, math.floor((t.updRetry or 0) - os.clock())) .. " s")
           or ("waits for its turn to get " .. TT.verName(CODE.ver) ..
               ((not CONFIG.turtles.autoUpdate and not (TT.updateForce and os.clock() < TT.updateForce))
                and " (automatic updates OFF - UPDATE TURTLES on HOME)" or (TT.updWaiting and " (until you are offline)" or "")))
  elseif t.held then line = "STOPPED by you - automatic jobs skip it; any button releases it"
  elseif not t.pos or not t.pos.f then line = "position unknown - press GPS LOCATE"
  else line = sWhy end
  text(ix + bw0 + 1, iy, trunc(tostring(line or ""), iw - bw0 - 1), C.text, C.panel)
  -- info grid: 3 columns x 2 rows
  local cw = math.floor((iw - 2) / 3)
  local function cellInfo(c, r, label, value, col)
    stat(ix + c * (cw + 1), iy + 2 + r * 3, cw, label, value, col)
  end
  cellInfo(0, 0, "POSITION", t.pos and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "unknown", t.pos and C.text or C.warn)
  cellInfo(1, 0, "FACING", (t.pos and t.pos.f) or "unknown")
  cellInfo(2, 0, "HOME", t.home and fmtPos(t.home.x, t.home.y, t.home.z) or "not set", t.home and C.text or C.warn)
  cellInfo(0, 1, "TASK", t.task or "idle", (t.task and t.task ~= "idle") and C.label or C.text)
  cellInfo(1, 1, "ITEMS", tostring(t.items or "?") .. (t.freeSlots and ("  (" .. t.freeSlots .. " slots free)") or ""))
  cellInfo(2, 1, "PROGRAM", TT.verName(t.ver), (CODE and t.ver == CODE.ver) and C.good or C.warn)
  local fy = iy + 8
  if type(t.fuel) == "number" and type(t.fuelMax) == "number" and t.fuelMax > 0 then
    meter(ix, fy, iw, "FUEL", commas(t.fuel) .. " / " .. commas(t.fuelMax) .. (t.endless and "  (endless fuel)" or ""),
          t.fuel / t.fuelMax, fuelCol(t.fuel))
  else
    kv(ix, fy, iw, "FUEL", tostring(t.fuel or "?"))
  end
  text(ix, fy + 2, trunc("Gear: " .. ((t.gear and t.gear ~= "") and t.gear or "?"), iw), C.dim, C.panel)
  -- the pad: 4 x 4 framed buttons
  local bw = math.floor((iw - 3) / 4)
  local px = function(c) return ix + c * (bw + 1) end
  local lastW = iw - 3 * (bw + 1)
  local r1 = fy + 4
  cmdBtn(px(0), r1, bw, 3, "UP", "move", { "up", 1 })
  cmdBtn(px(1), r1, bw, 3, "FORWARD", "move", { "forward", 1 })
  cmdBtn(px(2), r1, bw, 3, "DOWN", "move", { "down", 1 })
  cmdBtn(px(3), r1, lastW, 3, "STOP", "stop", {}, C.bad, true)
  local r2 = r1 + 4
  cmdBtn(px(0), r2, bw, 3, "TURN LEFT", "move", { "left", 1 })
  cmdBtn(px(1), r2, bw, 3, "BACK", "move", { "back", 1 })
  cmdBtn(px(2), r2, bw, 3, "TURN RIGHT", "move", { "right", 1 })
  cmdBtn(px(3), r2, lastW, 3, "GO HOME", "home", {}, C.accent, true)
  local r3 = r2 + 4
  if TT.online(t) then cmdBtn(px(0), r3, bw, 3, "PING", "ping")
  else actButton(px(0), r3, bw, 3, "FORGET", { kind = "tforget", name = tostring(t.id), count = 0 }, false, C.bad) end
  cmdBtn(px(1), r3, bw, 3, "SET HOME", "sethome")
  cmdBtn(px(2), r3, bw, 3, "REFUEL", "refuel")
  cmdBtn(px(3), r3, lastW, 3, "GPS LOCATE", "locate")
  local r4 = r3 + 4
  button(px(0), r4, bw, 3, "SHOW ON MAP", C.lime, "tmap", t.id)
  button(px(1), r4, bw, 3, t.anchor and "ANCHOR: ON" or "ANCHOR: OFF", t.anchor and C.purple or C.line, "tcmd",
         { t.id, "anchor", { t.anchor and "off" or "on" } }, t.anchor)
  button(px(2), r4, bw, 3, t.rescuerRole and "RESCUER: ON" or "RESCUER: OFF", t.rescuerRole and C.warn or C.line,
         "trescuer", t.id, t.rescuerRole)
  actButton(px(3), r4, lastW, 3, "DRONE: FLY ME THERE", { kind = "tflyme", name = tostring(t.id), count = 0 }, false, C.orange)
  -- exit route + mine up
  local r5 = r4 + 4
  local pick = tostring(t.gear or ""):find("pick", 1, true) and TT.online(t)
  local n5 = pick and 3 or 2
  local ew = math.floor((iw - (n5 - 1)) / n5)
  if t.rec then
    button(ix, r5, ew, 3, "EXIT: RECORDING " .. t.rec, C.warn, "tcmd", { t.id, "exitrec", {} }, true)
    button(ix + ew + 1, r5, pick and ew or (iw - ew - 1), 3, "EXIT: SAVE ROUTE", C.good, "tcmd", { t.id, "exitsave", {} }, true)
  else
    button(ix, r5, ew, 3, "EXIT: RECORD", C.line, "tcmd", { t.id, "exitrec", {} })
    button(ix + ew + 1, r5, pick and ew or (iw - ew - 1), 3, "EXIT: SAVE ROUTE", C.line, "tcmd", { t.id, "exitsave", {} })
  end
  if pick then
    actButton(ix + 2 * (ew + 1), r5, iw - 2 * (ew + 1), 3, "MINE UP TO SURFACE", { kind = "tdigup", name = tostring(t.id), count = 0 }, false, C.orange)
  end
  local info
  if t.rec then info = "Drive the turtle OUT of the base into the open, then SAVE"
  elseif EXITROUTE then
    info = "Exit route: " .. (EXITROUTE.n or "?") .. " corners, saved " ..
           math.floor((os.epoch("utc") - (EXITROUTE.t or 0)) / 60000) .. " min ago - every turtle uses it"
  else info = "No exit route: put a turtle at home, RECORD, drive it out, SAVE" end
  text(ix, r5 + 3, trunc(info, iw), t.rec and C.warn or C.dim, C.panel)
  -- rescue
  local r6 = r5 + 4
  if (not TT.online(t)) or t.stuck then
    local hw2 = math.floor((iw - 1) / 2)
    actButton(ix, r6, hw2, 2, t.rescuer and "RESCUE ON ITS WAY" or "SEND RESCUE TURTLE",
              { kind = "trescue", name = tostring(t.id), count = 0 }, true, C.warn)
    local why = TT.online(t) and "stuck - a turtle brings fuel / a pickaxe"
                or ("offline" .. (t.seenEpoch and (", last seen " .. TT.ago(t.seenEpoch)) or "") .. " - a turtle goes there")
    text(ix + hw2 + 2, r6, trunc(why, iw - hw2 - 2), C.dim, C.panel)
  else
    local okR, msgR = TT.rescueReady(t)
    text(ix, r6, trunc("As rescuer: " .. msgR, iw), (okR and C.good) or (t.rescuerRole and C.warn) or C.dim, C.panel)
  end
  return ch
end

function drawTurtlesPage(G)
  local y0, bottom = G.y0, G.y1
  if not state.tModem and not next(state.turtles) then
    drawMessage("NO WIRELESS MODEM", {
      "Put an Ender Modem (any distance) or a Wireless Modem (~64 blocks) on a free",
      "side of this computer, then run node.lua on each turtle.",
      "protocol, hostname and key must match CONFIG.turtles." }, C.warn)
    return
  end
  local list = TT.list()
  local leftW = math.floor((W - 3) * 0.36)
  local rx = 2 + leftW + 1
  local rw = W - rx
  drawList(2, y0, leftW, bottom - y0 + 1, list)
  local t = state.tSel and state.turtles[state.tSel]
  if not t then
    drawFleet(rx, y0, rw, bottom - y0 + 1, list)
    return
  end
  local ch = drawCard(rx, y0, rw, t)
  -- GO TO a saved place + the log, side by side under the card
  local gy = y0 + ch + 1
  local gh = bottom - gy + 1
  if gh < 5 then return end
  local gw = math.floor((rw - 1) * 0.42)
  local wl = state.waypoints or {}
  local gx, giy, giw, gih = panel(rx, gy, gw, gh, "GO TO", { right = #wl .. " places" })
  if #wl == 0 then
    para(gx, giy, giw, "No saved places yet. Stand on a block and type  $drone mark <name>  in chat.", C.dim)
  end
  local grows = math.max(1, math.floor(gih / 3))
  local goff = scrollBar(rx, gy, gw, "tGoOff", #wl, grows)
  for i = 1, math.min(grows, #wl - goff) do
    local w = wl[goff + i]
    local ry = giy + (i - 1) * 3
    text(gx, ry, trunc(w.name, giw - 8), C.text, C.panel)
    local sub = fmtPos(w.x, w.y, w.z)
    if t.pos then sub = sub .. "  " .. fl(dist3(t.pos.x, t.pos.y, t.pos.z, w.x, w.y, w.z)) .. " away" end
    text(gx, ry + 1, trunc(sub, giw - 8), C.dim, C.panel)
    button(gx + giw - 6, ry, 6, 2, "GO", C.accent, "tcmd", { t.id, "goto", { fl(w.x), fl(w.y), fl(w.z) } }, true)
  end
  -- log: newest first, long lines wrap (up to 3 rows)
  local lx, ly, lw, lh = panel(rx + gw + 1, gy, rw - gw - 1, gh, "LOG", { right = #(t.log or {}) .. " lines" })
  local ry, last = ly, ly + lh - 1
  for _, e in ipairs(t.log or {}) do
    if ry > last then break end
    text(lx, ry, tostring(e.t or ""), C.dim, C.panel)
    for k, line in ipairs(wrap(tostring(e.msg), lw - 7, 3)) do
      if ry > last then break end
      text(lx + 7, ry, line, C.text, C.panel)
      ry = ry + 1
    end
  end
end
