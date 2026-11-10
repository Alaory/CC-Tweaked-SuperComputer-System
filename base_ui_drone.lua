-- base_ui_drone.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   DRONE(S) tab: the selected drone, its air, mission steps and log,
--   passenger / destination choice and the mission buttons.

-- page drawing
function stepMark(status)
  if status == "done" then return "[x]", C.good
  elseif status == "run" then return ">> ", C.warn
  elseif status == "fail" then return "[!]", C.bad end
  return "[ ]", C.dim
end

-- the DRONE(S) tab
function drawDronePage(G)
  if not state.drone then
    drawMessage("NO DRONE INTERFACE", deviceHelpLines("Drone Interface"), C.warn)
    return
  end

  -- drone selector (dot = connected, * = on a mission)
  local sx = 2
  text(sx, G.y0 + 1, "DRONE", C.dim, C.bg)
  sx = sx + 7
  for _, k in ipairs(droneOrder) do
    local dr = drones[k]
    local sel = dr == state.drone
    local bg = sel and C.accent or C.empty
    local lab = " " .. dr.label .. (dr.busy and " *" or "") .. " "
    tabButton(sx, G.y0, lab .. "  ", sel and C.ink or C.text, bg, "dsel", k)
    text(sx + #lab, G.y0 + 1, "\7", dr.conn and C.good or C.bad, bg)
    sx = sx + #lab + 3
  end

  if not state.t.drone then
    drawMessage("LOADING", { "Talking to the Drone Interface..." }, C.label)
    return
  end

  local D = state.drone
  local y0, bottom = G.y0 + 3, G.y1
  local lx = 2
  local leftW = math.floor((W - 3) * 0.40)
  local rx = lx + leftW + 1
  local rw = W - rx
  local ix, iw = lx + 2, leftW - 4
  local rix, riw = rx + 2, rw - 4
  local pass = D.passenger or state.owner or ""
  local d = D.dest
  local dx, dy, dz = destPosCached(D)

  ------------------------------------------------ STATUS (stat tiles)
  card(lx, y0, leftW, 11, D.label:upper())
  local pl = D.conn and "CONNECTED" or "NOT CONNECTED"
  pill(lx + leftW - #pl - 4, y0 + 1, pl, C.ink, D.conn and C.good or C.bad)
  if D.conn then
    local tw = math.floor((iw - 2) / 2)
    local c2 = ix + tw + 2
    local p = D.pressure
    stat(ix, y0 + 3, tw, "PRESSURE", p and string.format("%.1f bar", p) or "-",
         (p and p < CONFIG.drone.minPressure) and C.bad or C.text)
    if p then
      local f = math.max(0, math.min(1, p / CONFIG.drone.maxPressure))
      barW(ix, y0 + 5, tw, f * tw, f > 0.25 and C.good or C.bad)
    end
    local running = D.action and D.done == false
    local act = D.action and (tostring(D.action):gsub("^pneumaticcraft:", "")) or "idle"
    stat(c2, y0 + 3, tw, "ACTION", act .. (running and "  (running)" or ""),
         running and C.warn or C.text)
    stat(ix, y0 + 7, tw, "POSITION", D.pos and fmtPos(D.pos.x, D.pos.y, D.pos.z) or "-")
    stat(c2, y0 + 7, tw, "TO DESTINATION",
         (D.pos and dx) and (fl(dist3(D.pos.x, D.pos.y, D.pos.z, dx, dy, dz)) .. " blocks") or "-")
  else
    local msg = "No drone is connected. Program a drone with a ComputerCraft puzzle piece " ..
                "whose area contains the interface, then launch it."
    for i, l in ipairs(wrap(msg, iw, 5)) do text(ix, y0 + 2 + i, l, C.dim, C.panel) end
  end

  ------------------------------------------------ MISSION (sized to its steps)
  local my = y0 + 12
  local m = D.mission
  local errLines = (m and m.err) and wrap(m.err, iw, 3) or {}
  local extra = #errLines > 0 and (#errLines + 1) or 0
  local mh = math.max(7, math.min(18, 6 + (m and #m.steps or 0) + extra))
  card(lx, my, leftW, mh, "MISSION")
  if not m then
    text(ix, my + 3, "No mission yet.", C.dim, C.panel)
    text(ix, my + 4, trunc("Pick a passenger + a place, then FERRY.", iw), C.dim, C.panel)
  else
    local stc = (m.state == "done" and C.good) or (m.state == "running" and C.warn)
                or (m.state == "stopped" and C.dim) or C.bad
    pill(lx + leftW - #m.state - 4, my + 1, m.state:upper(), C.ink, stc)
    text(ix, my + 3, trunc(m.title, iw), C.text, C.panel)
    local last = my + mh - 2 - extra
    for i, st in ipairs(m.steps) do
      local ry = my + 4 + i
      if ry > last then break end
      local mark, col = stepMark(st.status)
      text(ix, ry, mark, col, C.panel)
      text(ix + 4, ry, trunc(st.text, iw - 5), st.status == "pending" and C.dim or C.text, C.panel)
    end
    for i, l in ipairs(errLines) do
      text(ix, my + mh - 1 - #errLines + i - 1, l, C.bad, C.panel)
    end
  end

  ------------------------------------------------ LOG (striped rows)
  local ly = my + mh + 1
  local lh = bottom - ly + 1
  if lh >= 5 then
    card(lx, ly, leftW, lh, "LOG")
    local rows = math.max(1, lh - 4)
    local off = scrollBar(lx, ly + 1, leftW, "dLogOff", #D.log, rows)
    for i = 1, math.min(rows, #D.log - off) do
      local e = D.log[off + i]
      local ry = ly + 2 + i
      local bg = (i % 2 == 0) and C.head or C.panel
      local stamp = e.r or e.t or ""
      fill(lx + 1, ry, leftW - 2, 1, bg)
      text(ix, ry, stamp, C.dim, bg)
      text(ix + #stamp + 2, ry, trunc(tostring(e.msg), iw - #stamp - 2), C.text, bg)
    end
    if #D.log == 0 then text(ix, ly + 3, "Nothing yet.", C.dim, C.panel) end
  end

  ------------------------------------------------ DESTINATION (two tiles)
  card(rx, y0, rw, 9, "DESTINATION")
  local half = math.floor((riw - 2) / 2)
  local dname = "not set"
  if d then
    dname = (d.kind == "player" and ("@" .. d.name)) or (d.kind == "waypoint" and d.name)
            or "coordinates"
  end
  stat(rix, y0 + 3, half, "GOING TO", dname, d and C.text or C.dim)
  local dsub = dx and fmtPos(dx, dy, dz) or ((d and d.kind == "player") and "position unknown" or "")
  if d and d.kind == "player" then dsub = dsub .. "  (live)" end
  text(rix, y0 + 5, trunc(dsub, half), C.dim, C.panel)
  stat(rix + half + 2, y0 + 3, half, "PASSENGER", pass ~= "" and pass or "-", C.label)
  text(rix + half + 2, y0 + 5, trunc("choose with PASSENGER below", half), C.dim, C.panel)
  text(rix, y0 + 7, trunc("Exact coordinates: type  dest <x> <y> <z>  on the computer", riw),
       C.dim, C.panel)
  if dx and d and d.kind ~= "waypoint" then
    drawButton(rx + rw - 19, y0 + 1, 17, 1, "SAVE WAYPOINT", C.empty, C.text, "dsave")
  end

  ------------------------------------------------ ACTIONS
  local ay = y0 + 10
  card(rx, ay, rw, 15, "ACTIONS")
  if not D.conn then
    text(rix, ay + 4, "Connect a drone first (see the left panel).", C.dim, C.panel)
  else
    local bw = math.floor((riw - 2) / 3)
    actButton(rix, ay + 3, bw, 3, "FLY TO DEST", { kind = "drone", name = "fly:", count = 0 })
    actButton(rix + bw + 1, ay + 3, bw, 3, "PICK UP " .. trunc(pass, bw - 10),
              { kind = "drone", name = "pickup:" .. pass, count = 0, pass = pass })
    actButton(rix + 2 * (bw + 1), ay + 3, bw, 3, "DROP AT DEST",
              { kind = "drone", name = "drop:", count = 0 })
    actButton(rix, ay + 7, bw * 2 + 1, 3,
              "FERRY  " .. trunc(pass, bw - 8) .. "  >  " .. trunc(dname, bw - 8),
              { kind = "drone", name = "ferry:" .. pass, count = 0, pass = pass }, true)
    drawButton(rix + 2 * (bw + 1), ay + 7, bw, 3, "STOP", C.bad, C.ink, "dstop")
    actButton(rix, ay + 11, bw, 3, "RELEASE DRONE", { kind = "drone", name = "release:", count = 0 })
    actButton(rix + bw + 1, ay + 11, bw, 3, "GO HOME", { kind = "drone", name = "home:", count = 0 })
  end

  ------------------------------------------------ PLAYERS + SAVED PLACES
  local py = ay + 16
  local rest = bottom - py + 1
  local ph = math.floor(rest * 0.58)
  local wy = py + ph + 1
  local wh = bottom - wy + 1

  card(rx, py, rw, ph, "PLAYERS")
  if not det then
    text(rix, py + 3, "No Player Detector connected.", C.warn, C.panel)
  else
    local list = state.players or {}
    if not state.t.players or #list == 0 then
      text(rix, py + 3, "Reading players...", C.dim, C.panel)
    end
    local rows = math.max(1, math.floor((ph - 4) / 3))
    local off = scrollBar(rx, py + 1, rw, "dPlayerOff", #list, rows)
    for i = 1, math.min(rows, #list - off) do
      local e = list[off + i]
      local ry = py + 3 + (i - 1) * 3
      local isPass = pass == e.name
      local isDest = d and d.kind == "player" and d.name == e.name
      if isPass or isDest then
        local mc = isPass and C.accent or C.good
        mark(rx + 1, ry, mc)
        mark(rx + 1, ry + 1, mc)
      end
      text(rix, ry, trunc(e.name, riw - 28), isPass and C.label or C.text, C.panel)
      local sub = e.p and fmtPos(e.p.x, e.p.y, e.p.z) or (e.err or "?")
      if e.p and D.pos then
        sub = sub .. "   " .. fl(dist3(D.pos.x, D.pos.y, D.pos.z, e.p.x, e.p.y, e.p.z)) .. " blocks away"
      end
      text(rix, ry + 1, trunc(sub, riw - 28), C.dim, C.panel)
      local bx2 = rx + rw - 2 - 8
      local bx1 = bx2 - 13
      drawButton(bx1, ry, 12, 2, "PASSENGER", isPass and C.accent or C.empty,
                 isPass and C.ink or C.text, "dpass", e.name)
      drawButton(bx2, ry, 8, 2, "DEST", isDest and C.good or C.empty,
                 isDest and C.ink or C.text, "ddest", e.name)
    end
  end

  if wh >= 5 then
    card(rx, wy, rw, wh, "SAVED PLACES")
    local wl = state.waypoints
    if #wl == 0 then
      text(rix, wy + 3, "None yet. Choose a destination and press SAVE WAYPOINT,", C.dim, C.panel)
      text(rix, wy + 4, "or type  save <name> <x> <y> <z>  on the computer.", C.dim, C.panel)
    end
    local rows = math.max(1, math.floor((wh - 4) / 3))
    local off = scrollBar(rx, wy + 1, rw, "dWpOff", #wl, rows)
    for i = 1, math.min(rows, #wl - off) do
      local w = wl[off + i]
      local ry = wy + 3 + (i - 1) * 3
      local isDest = d and d.kind == "waypoint" and d.name == w.name
      if isDest then
        mark(rx + 1, ry, C.good)
        mark(rx + 1, ry + 1, C.good)
      end
      text(rix, ry, trunc(w.name, riw - 26), C.text, C.panel)
      local sub = fmtPos(w.x, w.y, w.z)
      if D.pos then sub = sub .. "   " .. fl(dist3(D.pos.x, D.pos.y, D.pos.z, w.x, w.y, w.z)) .. " blocks away" end
      text(rix, ry + 1, trunc(sub, riw - 26), C.dim, C.panel)
      local bx2 = rx + rw - 2 - 10
      local bx1 = bx2 - 9
      drawButton(bx1, ry, 8, 2, "DEST", isDest and C.good or C.empty,
                 isDest and C.ink or C.text, "dwp", w.name)
      actButton(bx2, ry, 10, 2, "DELETE", { kind = "wpdel", name = w.name, count = 0 })
    end
  end
end
