-- base_ui_turtles.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   TURTLES tab: the turtle list, the selected turtle's status and control pad.

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
      msg, col = "No ANCHOR: this computer stops when you leave the server", C.warn
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
    local name = trunc(t.label .. "  #" .. t.id, iw - 30)
    text(ix, ry, name, sel and C.label or C.text, C.panel)
    -- its program version: green = the newest, yellow = older
    local vn = TT.verName(t.ver)
    text(ix + #name + 2, ry, vn, (CODE and t.ver == CODE.ver) and C.good or C.warn, C.panel)
    local old = on and TT.outdated(t)
    local ready = old and CODE and t.updReady == CODE.ver
    local st = (on and t.stuck) and "STUCK" or ready and "UPDATE READY" or old and "UPDATING"
               or (on and t.anchor) and "ANCHOR" or (on and t.rescuerRole) and "RESCUER"
               or (on and "ONLINE" or "OFFLINE")
    local stc = (on and t.stuck) and C.warn or old and C.label or (on and t.anchor) and C.purple
                or (on and t.rescuerRole) and C.warn or (on and C.good or C.bad)
    pill(lx + leftW - #st - 4, ry, st, C.ink, stc)
    if type(t.fuel) == "number" and type(t.fuelMax) == "number" and t.fuelMax > 0 then
      local f = math.max(0, math.min(1, t.fuel / t.fuelMax))
      kv(ix, ry + 1, iw, "Fuel", commas(t.fuel) .. " / " .. commas(t.fuelMax),
         f < 0.1 and C.bad or C.text)
      barW(ix, ry + 2, iw, f * iw, f < 0.1 and C.bad or (f < 0.3 and C.warn or C.good))
    else
      kv(ix, ry + 1, iw, "Fuel", tostring(t.fuel or "?"))
    end
    local where = t.pos and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "position unknown"
    local doing = on and tostring(t.task or "idle")
                  or ("offline - last seen " .. TT.ago(t.seenEpoch) .. (t.rescuer and " - rescue on its way" or ""))
    text(ix, ry + 3, trunc(where .. "   " .. doing, iw), on and C.dim or C.warn, C.panel)
    addHit(lx + 1, ry, leftW - 2, 4, "tsel", t.id)
  end

  ------------------------------------------------ selected turtle
  local t = state.tSel and state.turtles[state.tSel]
  if not t then
    card(rx, y0, rw, 7, "CONTROL")
    text(rix, y0 + 3, "Select a turtle on the left.", C.dim, C.panel)
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
  if t.stuck then
    text(rix, y0 + 5, trunc("STUCK: " .. tostring(t.stuck), riw), C.warn, C.panel)
  elseif not t.pos or not t.pos.f then
    text(rix, y0 + 5, trunc("Position unknown: press GPS LOCATE, or type  turtle " .. t.id ..
         " setpos <x> <y> <z> <north|south|east|west>", riw), C.warn, C.panel)
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
  cmdBtn(rix,                r3, bw, 1, "PING",       "ping")
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
  if t.rec then
    drawButton(rix, r5, hw2, 2, "EXIT: RECORDING (" .. t.rec .. ")", C.warn, C.ink, "tcmd", { t.id, "exitrec", {} })
    drawButton(rix + hw2 + 1, r5, riw - hw2 - 1, 2, "EXIT: SAVE ROUTE", C.good, C.ink, "tcmd",
               { t.id, "exitsave", {} })
  else
    drawButton(rix, r5, hw2, 2, "EXIT: START RECORDING", C.empty, C.text, "tcmd", { t.id, "exitrec", {} })
    drawButton(rix + hw2 + 1, r5, riw - hw2 - 1, 2, "EXIT: SAVE ROUTE", C.empty, C.dim, "tcmd",
               { t.id, "exitsave", {} })
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
                or ("offline, last seen " .. TT.ago(t.seenEpoch) .. " - a turtle reinstalls it")
    text(rix + hw2 + 2, r6, trunc(why, riw - hw2 - 2), C.dim, C.panel)
  else
    local okR, msgR = TT.rescueReady(t)
    text(rix, r6, trunc("Rescue: " .. msgR, riw), okR and C.good or C.dim, C.panel)
    text(rix, r6 + 1, trunc("Carries: " .. ((t.gear and t.gear ~= "") and t.gear or "nothing for rescues"), riw),
         C.dim, C.panel)
  end

  ------------------------------------------------ go to a saved place
  local gy = y0 + ch + 1
  local rest = bottom - gy + 1
  local gh = math.max(6, math.floor(rest * 0.45))
  card(rx, gy, rw, gh, "GO TO")
  local wl = state.waypoints
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
    for i = 1, math.min(#t.log, lh - 4) do
      local e = t.log[i]
      local ry = ly + 2 + i
      local bg = (i % 2 == 0) and C.head or C.panel
      fill(rx + 1, ry, rw - 2, 1, bg)
      text(rix, ry, e.t, C.dim, bg)
      text(rix + 7, ry, trunc(tostring(e.msg), riw - 8), C.text, bg)
    end
  end
end
