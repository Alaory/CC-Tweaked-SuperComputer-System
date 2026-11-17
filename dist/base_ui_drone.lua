







function stepMark(status)
if status == "done" then return "DONE", C.good
elseif status == "run" then return " >> ", C.warn
elseif status == "fail" then return "FAIL", C.bad end
return "  - ", C.panel
end

local function pickRow(ix, ry, iw, name, sub, on, onCol)
local bg = on and C.line or C.panel
if on then
fill(ix - 1, ry, iw + 2, 2, C.line)
cell(ix - 1, ry, 1 + 4 + 16, onCol, C.line)
cell(ix - 1, ry + 1, 1 + 4 + 16, onCol, C.line)
end
return bg
end

function drawDronePage(G)
if not state.drone then
drawMessage("NO DRONE INTERFACE", deviceHelpLines("Drone Interface"), C.warn)
return
end

local sx = 2
for _, k in ipairs(droneOrder) do
local dr = drones[k]
local sel = dr == state.drone
local lab = "   " .. dr.label .. (dr.busy and "  *" or "") .. "  "
local bg = sel and C.accent or C.line
text(sx, G.y0, lab, sel and C.ink or C.text, bg)
led(sx + 1, G.y0, dr.conn and C.good or C.bad, bg)
hline(sx, G.y0 + 1, #lab, bg, C.bg, "top")
addHit(sx, G.y0, #lab, 2, "dsel", k)
sx = sx + #lab + 1
end
text(sx + 1, G.y0, trunc("pick a drone - its air, mission and the buttons below are for that one", W - sx - 2), C.dim, C.bg)
if not state.t.drone then
drawMessage("LOADING", { "Talking to the Drone Interface..." }, C.label)
return
end
local D = state.drone
local y0, bottom = G.y0 + 2, G.y1
local leftW = math.floor((W - 3) * 0.38)
local rx = 2 + leftW + 1
local rw = W - rx
local pass = D.passenger or state.owner or ""
local d = D.dest
local dx, dy, dz = destPosCached(D)


local sh = 13
local ix, iy, iw = panel(2, y0, leftW, sh, D.label:upper(), { right = D.conn and "CONNECTED" or "NOT CONNECTED",
rcol = D.conn and C.good or C.bad })
if D.conn then
local p = D.pressure
local maxP = CONFIG.drone.maxPressure or 10
local low = p and p < CONFIG.drone.minPressure
local bw = big(ix, iy, p and string.format("%.1f", p) or "-", low and C.bad or C.label, C.panel)
text(ix + bw + 1, iy + 1, "bar of air", C.dim, C.panel)
gauge(ix, iy + 3, iw, p and p / maxP or 0, low and C.bad or (p and p / maxP < 0.3 and C.warn or C.good))
local running = D.action and D.done == false
local act = D.action and (tostring(D.action):gsub("^pneumaticcraft:", "")) or "idle"
kv(ix, iy + 5, iw, "Doing", act .. (running and "  (running)" or ""), running and C.label or C.text)
kv(ix, iy + 6, iw, "Position", D.pos and fmtPos(D.pos.x, D.pos.y, D.pos.z) or "-")
kv(ix, iy + 7, iw, "To the destination", (D.pos and dx) and (fl(dist3(D.pos.x, D.pos.y, D.pos.z, dx, dy, dz)) .. " blocks") or "-")
kv(ix, iy + 8, iw, "On board", D.rider or "nobody", D.rider and C.label or C.dim)
else
para(ix, iy, iw, "No drone is connected. Program a drone with a ComputerCraft puzzle piece whose area holds the interface, then launch it.", C.dim, 6)
end


local my = y0 + sh + 1
local m = D.mission
local errLines = (m and m.err) and wrap(m.err, iw, 3) or {}
local mh = math.max(8, math.min(20, 6 + (m and #m.steps or 0) + (#errLines > 0 and #errLines + 1 or 0)))
local stc = m and ((m.state == "done" and C.good) or (m.state == "running" and C.warn) or (m.state == "stopped" and C.dim) or C.bad)
local mx, mmy, mw = panel(2, my, leftW, mh, "MISSION", { right = m and m.state:upper() or "none", rcol = stc or C.dim })
if not m then
para(mx, mmy, mw, "No mission yet. Pick a passenger and a place, then FERRY.", C.dim)
else
text(mx, mmy, trunc(m.title, mw), C.text, C.panel)
local last = my + mh - 2 - (#errLines > 0 and #errLines + 1 or 0)
for i, st in ipairs(m.steps) do
local ry = mmy + 1 + i
if ry > last then break end
local mk, col = stepMark(st.status)
text(mx, ry, mk, st.status == "pending" and C.dim or C.ink, col)
text(mx + 5, ry, trunc(st.text, mw - 5), st.status == "pending" and C.dim or C.text, C.panel)
end
for i, l in ipairs(errLines) do text(mx, my + mh - 1 - #errLines + i - 1, l, C.bad, C.panel) end
end


local ly = my + mh + 1
local lh = bottom - ly + 1
if lh >= 5 then
local lx, lly, lw, llh = panel(2, ly, leftW, lh, "LOG")
local rows = math.max(1, llh)
local off = scrollBar(2, ly, leftW, "dLogOff", #D.log, rows)
for i = 1, math.min(rows, #D.log - off) do
local e = D.log[off + i]
local ry = lly + i - 1
local stamp = e.r or e.t or ""
text(lx, ry, stamp, C.dim, C.panel)
text(lx + #stamp + 1, ry, trunc(tostring(e.msg), lw - #stamp - 1), C.text, C.panel)
end
if #D.log == 0 then text(lx, lly, "Nothing yet.", C.dim, C.panel) end
end


local dh = 9
local half = math.floor((rw - 1) / 2)
local dname = "not set"
if d then dname = (d.kind == "player" and ("@" .. d.name)) or (d.kind == "waypoint" and d.name) or "coordinates" end
local gx, gy, gw = panel(rx, y0, half, dh, "GOING TO", { col = d and C.accent or C.line })
text(gx, gy, trunc(dname, gw), d and C.text or C.dim, C.panel)
local dsub = dx and fmtPos(dx, dy, dz) or ((d and d.kind == "player") and "position unknown" or "pick one below")
if d and d.kind == "player" then dsub = dsub .. "  (follows them)" end
text(gx, gy + 1, trunc(dsub, gw), C.dim, C.panel)
if dx and d and d.kind ~= "waypoint" then
button(gx, gy + 3, math.min(gw, 20), 2, "SAVE AS A PLACE", C.line, "dsave")
else
para(gx, gy + 3, gw, "exact spot: dest <x> <y> <z> (console)", C.dim, 2)
end
local px2, py2, pw2 = panel(rx + half + 1, y0, rw - half - 1, dh, "PASSENGER", { col = pass ~= "" and C.accent or C.line })
text(px2, py2, trunc(pass ~= "" and pass or "-", pw2), C.label, C.panel)
para(px2, py2 + 1, pw2, "pick with PASSENGER in the list below", C.dim, 2)


local ay = y0 + dh + 1
local ah = 14
local ax, aay, aw = panel(rx, ay, rw, ah, "ACTIONS", { right = "two taps" })
if not D.conn then
text(ax, aay, "Connect a drone first (see the left).", C.dim, C.panel)
else
local bw = math.floor((aw - 2) / 3)
local last = aw - 2 * (bw + 1)
actButton(ax, aay, bw, 3, "FLY TO DEST", { kind = "drone", name = "fly:", count = 0 })
actButton(ax + bw + 1, aay, bw, 3, "PICK UP " .. pass, { kind = "drone", name = "pickup:" .. pass, count = 0, pass = pass })
actButton(ax + 2 * (bw + 1), aay, last, 3, "DROP AT DEST", { kind = "drone", name = "drop:", count = 0 })
actButton(ax, aay + 4, bw * 2 + 1, 3, "FERRY  " .. trunc(pass, bw - 8) .. "  >  " .. trunc(dname, bw - 8),
{ kind = "drone", name = "ferry:" .. pass, count = 0, pass = pass }, true)
button(ax + 2 * (bw + 1), aay + 4, last, 3, "STOP", C.bad, "dstop", nil, true)
actButton(ax, aay + 8, bw, 3, "RELEASE DRONE", { kind = "drone", name = "release:", count = 0 }, false, C.warn)
actButton(ax + bw + 1, aay + 8, bw, 3, "GO HOME", { kind = "drone", name = "home:", count = 0 }, false, C.good)
button(ax + 2 * (bw + 1), aay + 8, last, 3, "DRONE WORK >", C.line, "page", "work")
end


local py = ay + ah + 1
local rest = bottom - py + 1
local ph = math.max(6, math.floor(rest * 0.55))
local wy = py + ph + 1
local wh = bottom - wy + 1
local list = state.players or {}
local lx2, ly2, lw2, lh2 = panel(rx, py, rw, ph, "PLAYERS", { right = #list .. " seen" })
if not det then
text(lx2, ly2, "No Player Detector connected.", C.warn, C.panel)
else
if not state.t.players or #list == 0 then text(lx2, ly2, "Reading players...", C.dim, C.panel) end
local rows = math.max(1, math.floor((lh2 + 1) / 3))
local off = scrollBar(rx, py, rw, "dPlayerOff", #list, rows)
for i = 1, math.min(rows, #list - off) do
local e = list[off + i]
local ry = ly2 + (i - 1) * 3
local isPass = pass == e.name
local isDest = d and d.kind == "player" and d.name == e.name
local bg = pickRow(lx2, ry, lw2, nil, nil, isPass or isDest, isPass and C.accent or C.good)
text(lx2, ry, trunc(e.name, lw2 - 28), isPass and C.accent or C.text, bg)
local sub = e.p and fmtPos(e.p.x, e.p.y, e.p.z) or (e.err or "?")
if e.p and D.pos then sub = sub .. "  " .. fl(dist3(D.pos.x, D.pos.y, D.pos.z, e.p.x, e.p.y, e.p.z)) .. " away" end
text(lx2, ry + 1, trunc(sub, lw2 - 28), C.dim, bg)
button(lx2 + lw2 - 25, ry, 14, 2, "PASSENGER", isPass and C.accent or C.line, "dpass", e.name, isPass)
button(lx2 + lw2 - 10, ry, 10, 2, "DEST", isDest and C.good or C.line, "ddest", e.name, isDest)
end
end
if wh >= 5 then
local wl = state.waypoints
local wx, wyy, ww, whh = panel(rx, wy, rw, wh, "SAVED PLACES", { right = #wl .. " places" })
if #wl == 0 then
para(wx, wyy, ww, "None yet. Stand on a block and type  $drone mark <name>  in chat, or pick a destination and SAVE AS A PLACE.", C.dim)
end
local rows = math.max(1, math.floor((whh + 1) / 3))
local off = scrollBar(rx, wy, rw, "dWpOff", #wl, rows)
for i = 1, math.min(rows, #wl - off) do
local w = wl[off + i]
local ry = wyy + (i - 1) * 3
local isDest = d and d.kind == "waypoint" and d.name == w.name
local bg = pickRow(wx, ry, ww, nil, nil, isDest, C.good)
text(wx, ry, trunc(w.name, ww - 24), C.text, bg)
local sub = fmtPos(w.x, w.y, w.z)
if D.pos then sub = sub .. "  " .. fl(dist3(D.pos.x, D.pos.y, D.pos.z, w.x, w.y, w.z)) .. " away" end
text(wx, ry + 1, trunc(sub, ww - 24), C.dim, bg)
button(wx + ww - 21, ry, 10, 2, "DEST", isDest and C.good or C.line, "dwp", w.name, isDest)
if w.name ~= "Base" then actButton(wx + ww - 10, ry, 10, 2, "DELETE", { kind = "wpdel", name = w.name, count = 0 }, false, C.bad) end
end
end
end
