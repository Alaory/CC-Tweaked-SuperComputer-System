-- base_ui_turtles.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   TURTLES tab: the turtle list, the selected turtle's status and control pad.

-- FLEET overview (no turtle selected): counts per status, what needs you
-- (tap a line to select that turtle), fuel, program, survey, mining teams
local ORDER = { "busy", "trouble", "still", "stuck", "nofuel", "held", "idle", "offline", "missing" }
local NAMES = { busy = "WORKING", trouble = "FINDING A WAY", still = "NOT MOVING", stuck = "STUCK",
                nofuel = "NO FUEL", held = "STOPPED", idle = "IDLE", offline = "OFFLINE", missing = "MISSING" }
function drawFleet(x, y, w, h, list)
  card(x, y, w, h, "FLEET   (tap a turtle on the left for its controls)")
  local ix, iw = x + 2, w - 4
  local count, col, need = {}, {}, {}
  local fuelSum, low, up = 0, nil, 0
  for _, t in ipairs(list) do
    local key, lab, c, why = TT.status(t)
    count[key] = (count[key] or 0) + 1
    col[key] = col[key] or c
    -- FINDING A WAY is a turtle already working around something: not listed
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
  -- status pills
  local px, py = ix, y + 3
  for _, k in ipairs(ORDER) do
    if count[k] then
      local lbl = NAMES[k] .. " " .. count[k]
      if px + #lbl + 3 > ix + iw then px, py = ix, py + 2 end
      px = px + pill(px, py, lbl, C.ink, col[k] or C.label) + 1
    end
  end
  local ry = py + 2
  -- numbers
  kv(ix, ry, iw, "Turtles", #list .. "   (" .. (#list - (count.offline or 0)) .. " online)")
  kv(ix, ry + 1, iw, "Fuel, all together", commas(fuelSum) .. (low and ("   lowest: " .. low.label .. " " .. commas(low.fuel)) or ""),
     (low and tonumber(low.fuel) < 2000) and C.warn or C.text)
  kv(ix, ry + 2, iw, "Turtle program", CODE and (up .. "/" .. #list .. " on " .. TT.verName(CODE.ver) ..
     (TT.updWaiting and "  (updates wait until you are offline)" or "")) or "?", (CODE and up < #list) and C.warn or C.text)
  local frac, total, sent = MAP.surveyProgress()
  if frac then
    local q = MAP.queue
    kv(ix, ry + 3, iw, q.auto and "Auto-map" or "Survey", math.floor(frac * 100 + 0.5) .. "%   " .. commas(sent or 0) ..
       " spots sent" .. (q.auto and ("   " .. math.floor(MAP.autoRadius() + 0.5) .. " blocks around the base") or ""))
    barW(ix, ry + 4, iw, frac * iw, C.accent)
  else
    kv(ix, ry + 3, iw, "Survey", (MAP.auto and MAP.auto.on) and "auto-map waits for a free turtle" or "none running", C.dim)
  end
  -- the turtle factory (AE2 parts)
  if FACTORY then
    local fl, fc = FACTORY.statusLine()
    kv(ix, ry + 5, iw, "Factory", trunc(fl, iw - 12), fc)
  end
  -- mining teams
  local my = ry + 7
  if MINE and next(MINE.units) then
    text(ix, my, "MINING TEAMS", C.label, C.panel)
    my = my + 1
    for dim, team in pairs(MINE.teams()) do
      local ll = team.loader and MINE.status(team.loader) or "MISSING"
      local working, bad = 0, 0
      for _, m in ipairs(team.miners) do
        local lab = MINE.status(m)
        if lab == "MINING" or lab == "UNLOADING" or lab == "WAITING" then working = working + 1
        elseif lab ~= "PAUSED" then bad = bad + 1 end
      end
      text(ix, my, trunc(dim .. ":  " .. working .. "/" .. #team.miners .. " miners working   loader " .. ll ..
           (bad > 0 and ("   " .. bad .. " need a look") or ""), iw), bad > 0 and C.warn or C.dim, C.panel)
      my = my + 1
    end
    my = my + 1
  end
  -- what needs you (tap = select)
  text(ix, my, #need > 0 and ("NEEDS A LOOK (" .. #need .. ")") or "NOTHING NEEDS YOU", #need > 0 and C.warn or C.good, C.panel)
  local ny = my + 1
  for _, n in ipairs(need) do
    if ny > y + h - 2 then break end
    local lbl = n.lab
    pill(ix, ny, lbl, C.ink, n.c)
    text(ix + #lbl + 3, ny, trunc(n.t.label .. " #" .. n.t.id .. "  " .. tostring(n.why), iw - #lbl - 3), C.text, C.panel)
    addHit(ix, ny, iw, 1, "tsel", n.t.id)
    ny = ny + 1
  end
end

-- page drawing
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
  local lx = 2
  local leftW = math.floor((W - 3) * 0.38)
  local rx = lx + leftW + 1
  local rw = W - rx
  local ix, iw = lx + 2, leftW - 4
  local rix, riw = rx + 2, rw - 4

  ------------------------------------------------ list of turtles
  card(lx, y0, leftW, bottom - y0 + 1, "TURTLES (" .. #list .. ")" ..
       (CODE and ("   program " .. TT.verName(CODE.ver)) or ""))
  -- does a turtle keep the base running while you are offline?
  do
    local at, inChunk = TT.anchorInfo()
    local msg, col
    if not at then
      msg, col = "No ANCHOR: the base stops when you log off", C.warn
    elseif inChunk == true then
      msg, col = at.label .. " is the ANCHOR: the base keeps running when you leave", C.good
    elseif inChunk == false then
      msg, col = at.label .. " is the ANCHOR but NOT in this computer's chunk", C.bad
    else
      msg, col = at.label .. " is the ANCHOR (this computer's position unknown - GPS?)", C.label
    end
    text(lx + 2, bottom - 1, trunc(msg, leftW - 4), col, C.panel)
  end
  -- lost turtles nobody knows the position of: search around the base
  actButton(lx + 2, bottom - 4, leftW - 4, 2, "FIND LOST TURTLES (search around the base)",
            { kind = "findlost", name = "all", count = 0 }, true)
  if #list == 0 then
    text(ix, y0 + 3, "Waiting for turtles...", C.dim, C.panel)
    text(ix, y0 + 4, trunc("Run node.lua on a turtle (same key).", iw), C.dim, C.panel)
  end
  local rows = math.max(1, math.floor((bottom - y0 - 3) / 5))
  local off = scrollBar(lx, y0 + 1, leftW, "tListOff", #list, rows)
  for i = 1, math.min(rows, #list - off) do
    local t = list[off + i]
    local ry = y0 + 3 + (i - 1) * 5
    local sel = state.tSel == t.id
    local on = TT.online(t)
    if sel then
      for k = 0, 3 do mark(lx + 1, ry + k, C.accent) end
    end
    local vn = TT.verName(t.ver)
    local old = on and TT.outdated(t)
    local ready = old and CODE and t.updReady == CODE.ver
    local forcedU = TT.updateForce and os.clock() < TT.updateForce
    local upd = old and (t.updState == "sending" and "SENDING UPDATE" or (t.updState == "retry" and "RETRY UPDATE")
                         or (ready and "UPDATE AFTER JOB")
                         or ((not forcedU and (TT.updWaiting or not CONFIG.turtles.autoUpdate)) and "UPDATE WAITS")
                         or "UPDATE QUEUED")
    -- the real state first (stuck / not moving / working / idle + why); an
    -- update in progress only shows when nothing is wrong
    local key, st, stc, why = TT.status(t)
    if upd and (key == "idle" or key == "busy") then
      st, stc = ready and "UPDATE READY" or upd, C.label
    end
    pill(lx + leftW - #st - 4, ry, st, C.ink, stc)
    -- name + program version (green = the newest, yellow = older), in the room left of the pill
    local name = trunc(t.label .. "  #" .. t.id, math.max(6, iw - #st - #vn - 6))
    text(ix, ry, name, sel and C.label or C.text, C.panel)
    text(ix + #name + 2, ry, vn, (CODE and t.ver == CODE.ver) and C.good or C.warn, C.panel)
    if type(t.fuel) == "number" and type(t.fuelMax) == "number" and t.fuelMax > 0 then
      local f = math.max(0, math.min(1, t.fuel / t.fuelMax))
      -- colours by the amount itself (1,000 / 5,000), not by the share of a
      -- 100,000 tank - 9,000 fuel is plenty
      local fc = (t.fuel < 1000 and C.bad) or (t.fuel < 5000 and C.warn) or C.good
      kv(ix, ry + 1, iw, "Fuel", commas(t.fuel) .. " / " .. commas(t.fuelMax), t.fuel < 1000 and C.bad or C.text)
      barW(ix, ry + 2, iw, math.max(f * iw, t.fuel > 0 and 1 or 0), fc)
    else
      kv(ix, ry + 1, iw, "Fuel", tostring(t.fuel or "?"))
    end
    local where = t.pos and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "position unknown"
    local bad = key ~= "idle" and key ~= "busy"
    text(ix, ry + 3, trunc(where .. "   " .. why, iw), bad and stc or C.dim, C.panel)
    addHit(lx + 1, ry, leftW - 2, 4, "tsel", t.id)
  end

  ------------------------------------------------ selected turtle
  local t = state.tSel and state.turtles[state.tSel]
  if not t then
    drawFleet(rx, y0, rw, bottom - y0 + 1, list)
    return
  end
  local ch = 27
  card(rx, y0, rw, ch, t.label:upper() .. "  #" .. t.id)
  local q = math.floor((riw - 8) / 5)
  stat(rix, y0 + 3, q, "POSITION", t.pos and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "unknown",
       t.pos and C.text or C.warn)
  stat(rix + q + 2, y0 + 3, q, "FACING", (t.pos and t.pos.f) or "unknown")
  stat(rix + 2 * (q + 2), y0 + 3, q, "HOME",
       t.home and fmtPos(t.home.x, t.home.y, t.home.z) or "not set", t.home and C.text or C.warn)
  stat(rix + 3 * (q + 2), y0 + 3, q, "TASK", t.task or "idle", t.task and t.task ~= "idle" and C.warn or C.text)
  stat(rix + 4 * (q + 2), y0 + 3, q, "ITEMS", tostring(t.items or "?"))
  local sKey, sLab, sCol, sWhy = TT.status(t)
  if TT.dupText(t) then
    text(rix, y0 + 5, trunc(TT.dupText(t), riw), C.warn, C.panel)
  elseif sKey ~= "idle" and sKey ~= "busy" and sKey ~= "held" then
    text(rix, y0 + 5, trunc(sLab .. ": " .. sWhy, riw), sCol, C.panel)
  elseif CODE and TT.online(t) and TT.outdated(t) then
    local msg = (t.updReady == CODE.ver) and ("Has " .. TT.verName(CODE.ver) .. " ready - installs when its job is done")
                or (t.updState == "sending") and ("Sending " .. TT.verName(CODE.ver) .. " now (" .. #CODE.pieces .. " pieces)")
                or (t.updState == "retry") and ("Update: " .. tostring(t.updNote or "failed") .. " - next try in " ..
                     math.max(0, math.floor((t.updRetry or 0) - os.clock())) .. " s")
                or ("Waiting for its turn to get " .. TT.verName(CODE.ver) ..
                    ((not CONFIG.turtles.autoUpdate and not (TT.updateForce and os.clock() < TT.updateForce))
                     and " (automatic updates are OFF - press UPDATE TURTLES)"
                     or (TT.updWaiting and " (waits until you are offline - or press UPDATE TURTLES)") or ""))
    text(rix, y0 + 5, trunc(msg, riw), C.label, C.panel)
  elseif t.held then
    text(rix, y0 + 5, trunc("STOPPED by you - automatic jobs skip it. Any button (e.g. PING) releases it.", riw),
         C.warn, C.panel)
  elseif not t.pos or not t.pos.f then
    text(rix, y0 + 5, trunc("Position unknown: press GPS LOCATE, or type  turtle " .. t.id ..
         " setpos <x> <y> <z> <north|south|east|west>", riw), C.warn, C.panel)
  else
    text(rix, y0 + 5, trunc(sLab .. ": " .. sWhy, riw), sCol == C.label and C.dim or sCol, C.panel)
  end

  local function cmdBtn(x, y, w, h, label, cmd, args, bg, fg)
    drawButton(x, y, w, h, label, bg or C.empty, fg or C.text, "tcmd", { t.id, cmd, args or {} })
  end
  local bw = math.floor((riw - 3) / 4)
  local r1, r2, r3 = y0 + 7, y0 + 11, y0 + 15
  cmdBtn(rix,                r1, bw, 3, "UP",         "move", { "up", 1 })
  cmdBtn(rix + bw + 1,       r1, bw, 3, "FORWARD",    "move", { "forward", 1 })
  cmdBtn(rix + 2 * (bw + 1), r1, bw, 3, "DOWN",       "move", { "down", 1 })
  cmdBtn(rix + 3 * (bw + 1), r1, bw, 3, "STOP",       "stop", {}, C.bad, C.ink)
  cmdBtn(rix,                r2, bw, 3, "TURN LEFT",  "move", { "left", 1 })
  cmdBtn(rix + bw + 1,       r2, bw, 3, "BACK",       "move", { "back", 1 })
  cmdBtn(rix + 2 * (bw + 1), r2, bw, 3, "TURN RIGHT", "move", { "right", 1 })
  cmdBtn(rix + 3 * (bw + 1), r2, bw, 3, "GO HOME",    "home", {}, C.accent, C.ink)
  if TT.online(t) then
    cmdBtn(rix,              r3, bw, 1, "PING",       "ping")
  else
    -- offline (or MISSING - deleted by a server crash?): take it off the list
    actButton(rix, r3, bw, 1, "FORGET", { kind = "tforget", name = tostring(t.id), count = 0 })
  end
  cmdBtn(rix + bw + 1,       r3, bw, 1, "SET HOME",   "sethome")
  cmdBtn(rix + 2 * (bw + 1), r3, bw, 1, "REFUEL",     "refuel")
  cmdBtn(rix + 3 * (bw + 1), r3, bw, 1, "GPS LOCATE", "locate")
  -- finding a lost turtle
  local r4 = y0 + 17
  local q3 = math.floor((riw - 3) / 4)
  drawButton(rix, r4, q3, 2, "SHOW ON MAP", C.empty, C.text, "tmap", t.id)
  drawButton(rix + q3 + 1, r4, q3, 2, t.anchor and "ANCHOR: ON" or "ANCHOR: OFF",
             t.anchor and C.purple or C.empty, t.anchor and C.ink or C.text, "tcmd",
             { t.id, "anchor", { t.anchor and "off" or "on" } })
  -- the permanent rescue job (kept on the base)
  drawButton(rix + 2 * (q3 + 1), r4, q3, 2, t.rescuerRole and "RESCUER: ON" or "RESCUER: OFF",
             t.rescuerRole and C.warn or C.empty, t.rescuerRole and C.ink or C.text, "trescuer", t.id)
  actButton(rix + 3 * (q3 + 1), r4, riw - 3 * (q3 + 1), 2,
            state.drone and ("FLY ME THERE (" .. state.drone.label .. ")") or "DRONE: FLY ME THERE",
            { kind = "tflyme", name = tostring(t.id), count = 0 }, true)

  -- the exit route out of the base (shared by all turtles)
  local r5 = y0 + 20
  local hw2 = math.floor((riw - 1) / 2)
  -- with a pickaxe: MINE UP (straight up to the surface, natural blocks only) - two taps
  local pick = tostring(t.gear or ""):find("pick", 1, true) and TT.online(t)
  local ew = pick and math.floor((riw - 2) / 3) or hw2
  local ew2 = pick and ew or (riw - hw2 - 1)
  if t.rec then
    drawButton(rix, r5, ew, 2, "EXIT: RECORDING (" .. t.rec .. ")", C.warn, C.ink, "tcmd", { t.id, "exitrec", {} })
    drawButton(rix + ew + 1, r5, ew2, 2, "EXIT: SAVE ROUTE", C.good, C.ink, "tcmd",
               { t.id, "exitsave", {} })
  else
    drawButton(rix, r5, ew, 2, "EXIT: START RECORDING", C.empty, C.text, "tcmd", { t.id, "exitrec", {} })
    drawButton(rix + ew + 1, r5, ew2, 2, "EXIT: SAVE ROUTE", C.empty, C.dim, "tcmd",
               { t.id, "exitsave", {} })
  end
  if pick then
    actButton(rix + 2 * (ew + 1), r5, riw - 2 * (ew + 1), 2, "MINE UP TO THE SURFACE",
              { kind = "tdigup", name = tostring(t.id), count = 0 }, true)
  end
  local info
  if t.rec then
    info = "Drive the turtle OUT of the base into the open, then SAVE"
  elseif EXITROUTE then
    info = "Exit route: " .. (EXITROUTE.n or "?") .. " corners, saved " ..
           math.floor((os.epoch("utc") - (EXITROUTE.t or 0)) / 60000) .. " min ago - used by all turtles"
  else
    info = "No exit route: put a turtle at home, START, drive it out, SAVE"
  end
  text(rix, y0 + 22, trunc(info, riw), t.rec and C.warn or C.dim, C.panel)

  -- lost or stuck: send another turtle to help
  local r6 = y0 + 24
  local needHelp = (not TT.online(t)) or t.stuck
  if needHelp then
    actButton(rix, r6, hw2, 2, t.rescuer and "RESCUE ON ITS WAY" or "SEND RESCUE TURTLE",
              { kind = "trescue", name = tostring(t.id), count = 0 }, true)
    local why = TT.online(t) and "stuck - a turtle brings fuel / a pickaxe"
                or ("offline" .. (t.seenEpoch and (", last seen " .. TT.ago(t.seenEpoch)) or "") ..
                    " - a turtle goes there (that wakes it up) or reinstalls it")
    text(rix + hw2 + 2, r6, trunc(why, riw - hw2 - 2), C.dim, C.panel)
  else
    -- what this turtle could do as the RESCUER (only matters for that one)
    local okR, msgR = TT.rescueReady(t)
    text(rix, r6, trunc("As rescuer: " .. msgR, riw),
         (okR and C.good) or (t.rescuerRole and C.warn) or C.dim, C.panel)
  end
  text(rix, r6 + 1, trunc("Gear: " .. ((t.gear and t.gear ~= "") and t.gear or "?"), riw), C.dim, C.panel)

  ------------------------------------------------ go to a saved place
  local gy = y0 + ch + 1
  local rest = bottom - gy + 1
  local wl = state.waypoints
  -- only as tall as the saved places need (the rest goes to the log)
  local gh = math.max(6, math.min(math.floor(rest * 0.45), 4 + 2 * #wl))
  card(rx, gy, rw, gh, "GO TO")
  if #wl == 0 then
    text(rix, gy + 3, trunc("No saved places. On the computer:  turtle " .. t.id ..
         " goto <x> <y> <z>", riw), C.dim, C.panel)
  end
  local grows = math.max(1, math.floor((gh - 4) / 2))
  local goff = scrollBar(rx, gy + 1, rw, "tGoOff", #wl, grows)
  for i = 1, math.min(grows, #wl - goff) do
    local w = wl[goff + i]
    local ry = gy + 2 + i * 2 - 1
    text(rix, ry, trunc(w.name, 20), C.text, C.panel)
    local sub = fmtPos(w.x, w.y, w.z)
    if t.pos then sub = sub .. "   " .. fl(dist3(t.pos.x, t.pos.y, t.pos.z, w.x, w.y, w.z)) .. " blocks" end
    text(rix + 22, ry, trunc(sub, riw - 34), C.dim, C.panel)
    cmdBtn(rx + rw - 2 - 8, ry, 8, 1, "GO", "goto", { fl(w.x), fl(w.y), fl(w.z) }, C.accent, C.ink)
  end

  ------------------------------------------------ log
  local ly = gy + gh + 1
  local lh = bottom - ly + 1
  if lh >= 5 then
    card(rx, ly, rw, lh, "LOG")
    -- newest first; a long line wraps onto up to 3 rows
    local ry, last = ly + 3, ly + lh - 2
    local mw = riw - 8
    for i = 1, #t.log do
      if ry > last then break end
      local e = t.log[i]
      local msg = tostring(e.msg)
      local bg = (i % 2 == 0) and C.head or C.panel
      local parts = {}
      while #msg > 0 and #parts < 3 do
        if #msg <= mw then parts[#parts + 1] = msg msg = ""
        else
          local cut = msg:sub(1, mw):match("^.*() ") or (mw + 1)      -- break at the last space
          if cut < mw / 2 then cut = mw + 1 end
          parts[#parts + 1] = msg:sub(1, cut - 1)
          msg = msg:sub(cut):gsub("^ +", "")
        end
      end
      if #msg > 0 then parts[#parts] = trunc(parts[#parts] .. " " .. msg, mw) end
      for k, line in ipairs(parts) do
        if ry > last then break end
        fill(rx + 1, ry, rw - 2, 1, bg)
        if k == 1 then text(rix, ry, e.t, C.dim, bg) end
        text(rix + 7, ry, line, C.text, bg)
        ry = ry + 1
      end
    end
  end
end
