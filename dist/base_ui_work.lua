







local function done1(s)
local _, n = tostring(s or ""):gsub("1", "")
return n
end

local function chestPanel(x, y, w, h)
local name, at = DW.chestName(), { DW.chestAt() }
local bad = DW.view.bad
local ok = name and at[1] and not bad
local ix, iy, iw = panel(x, y, w, h, "WORK CHEST", { right = ok and "READY" or "NOT READY", rcol = ok and C.good or C.warn,
col = ok and C.line or C.warn })
local r = para(ix, iy, iw, "An EMPTY chest / barrel on the cable near the drones. AE2 items go in, the drone takes " ..
"them; what comes back goes into AE2. Only the base and the drones use it.", C.dim, 3)
r = r + 1
led(ix, r, ok and C.good or C.warn)
if name then
text(ix + 2, r, trunc(name .. (at[1] and ("  at " .. fmtPos(at[1], at[2], at[3])) or ("  -  spot NOT set: stand ON it, chat $" ..
tostring(CONFIG.chat and CONFIG.chat.command or "drone") .. " workchest")), iw - 2),
at[1] and C.text or C.warn, C.panel)
else
para(ix + 2, r, iw - 2, "not set: stand ON it and type  $" .. tostring(CONFIG.chat and CONFIG.chat.command or "drone") ..
" workchest  in chat (or CHEST > here)", C.warn, 2)
end
if bad and name then text(ix + 2, r + 1, trunc(bad, iw - 2), C.warn, C.panel) end
local bw = math.floor((iw - 1) / 2)
local n = #(DW.view.cands or {})
button(ix, y + h - 4, bw, 3, "CHEST: " .. (name or "pick one") .. (n > 1 and " >" or ""), C.line, "dwnext")
actButton(ix + bw + 1, y + h - 4, iw - bw - 1, 3, "BLOCK UNDER ME", { kind = "dwchesthere", name = "", count = 0 },
name ~= nil and not at[1], C.accent)
end

local function fuelPanel(x, y, w, h)
local item, count = DW.fuelItem()
local on = DW.autoOn()
local list = {}
for _, t in pairs(state.turtles) do
local f = tonumber(t.fuel)
if (TT.online(t) and f and f < 20) or DW.runs[t.id] then list[#list + 1] = t end
end
table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
local ix, iy, iw, ih = panel(x, y, w, h, "FUEL RUNS FOR TURTLES", { right = #list > 0 and (#list .. " out of fuel") or "none out of fuel",
rcol = #list > 0 and C.warn or C.good })
button(ix + iw - 14, iy, 14, 3, on and "AUTO: ON" or "AUTO: OFF", on and C.good or C.line, "dwauto", nil, on)
para(ix, iy, iw - 16, "A turtle with NO FUEL is still on (its Chunky keeps it loaded): a drone brings it " ..
count .. " " .. prettify(item) .. " from AE2.", C.dim, 3)

local nf = #(DW.view.fuels or {})
local fw = math.floor((iw - 1) * 0.68)
local have
for _, e in ipairs(DW.view.fuels or {}) do if e.name == item then have = e.have end end
button(ix, iy + 4, fw, 3, "FUEL: " .. prettify(item) .. (nf > 1 and " >" or "") .. (have and ("  (" .. compact(have) .. " in AE2)") or ""),
have == 0 and C.warn or C.line, "dwfuelnext")
button(ix + fw + 1, iy + 4, iw - fw - 1, 3, "x" .. count .. " PER RUN >", C.line, "dwfuelcount")
local yy = iy + 8
if #list == 0 then
led(ix, yy, C.good)
text(ix + 2, yy, "No turtle is out of fuel.", C.good, C.panel)
return
end
for _, t in ipairs(list) do
if yy + 1 > y + h - 2 then break end
local r = DW.runs[t.id]
local st = r and (r.state == "flying" and "a drone is on its way" or r.state == "delivered" and "fuel delivered - burning it"
or ("failed: " .. tostring(r.why or "?"))) or (TT.online(t) and "no fuel" or "offline (not loaded)")
local col = r and (r.state == "failed" and C.bad or C.label) or C.warn
led(ix, yy, col)
text(ix + 2, yy, trunc(t.label .. "   fuel " .. tostring(t.fuel or "?"), iw - 16), C.text, C.panel)
text(ix + 2, yy + 1, trunc(st, iw - 16), r and r.state == "failed" and C.bad or C.dim, C.panel)
if not r and TT.online(t) then
actButton(ix + iw - 14, yy, 14, 2, "SEND FUEL", { kind = "dwfuel", name = tostring(t.id), count = 0 }, false, C.orange)
end
yy = yy + 3
end
end

local function placesPanel(x, y, w, h)
local wl = state.waypoints or {}
local ix, iy, iw, ih = panel(x, y, w, h, "PLACES", { right = #wl .. " saved" })
actButton(ix + iw - 22, iy, 22, 3, "SAVE WHERE I STAND", { kind = "dwmark", name = "", count = 0 }, false, C.accent)
para(ix, iy, iw - 24, "The block under you. Name one in chat:  $" .. tostring(CONFIG.chat and CONFIG.chat.command or "drone") ..
" mark <name>", C.dim, 3)
local yy = iy + 4
local shown = 0
for _, wp in ipairs(wl) do
if yy + 1 > y + h - 2 then
text(ix, y + h - 2, "+" .. (#wl - shown) .. " more (console: list)", C.dim, C.panel)
break
end
text(ix, yy, trunc(wp.name, iw - 12), C.text, C.panel)
text(ix, yy + 1, trunc(fmtPos(wp.x, wp.y, wp.z), iw - 12), C.dim, C.panel)
if wp.name ~= "Base" then
actButton(ix + iw - 10, yy, 10, 2, "DELETE", { kind = "dwunmark", name = wp.name, count = 0 }, false, C.bad)
end
yy = yy + 3
shown = shown + 1
end
end

local function buildPanel(x, y, w, h)
local J = DW.job
local ix, iy, iw, ih = panel(x, y, w, h, "BUILD A SCHEMATIC (BY DRONE)", { right = J and (J.paused and "PAUSED" or "BUILDING") or "ready",
rcol = J and (J.paused and C.warn or C.good) or C.dim })
if J then
local total, placed = #J.done, done1(J.done)
text(ix, iy, trunc(J.name, iw), C.label, C.panel)
text(ix, iy + 1, trunc("at " .. fmtPos(J.x, J.y, J.z) .. (J.rot ~= 0 and ("  turned " .. J.rot) or "") ..
(J.clear and "  -  clearing first" or ""), iw), C.dim, C.panel)
local share = total > 0 and placed / total or 1
local bw = big(ix, iy + 3, math.floor(share * 100) .. "%", C.text, C.panel)
text(ix + bw + 2, iy + 3, placed .. " of " .. total .. " blocks", C.text, C.panel)
text(ix + bw + 2, iy + 4, trunc((J.clear and ("cleared " .. done1(J.dug) .. " of " .. #J.dug .. "   ") or "") ..
(J.skippedN > 0 and (J.skippedN .. " spots were taken") or ""), iw - bw - 2), C.dim, C.panel)
gauge(ix, iy + 6, iw, share, C.good)
local yy = iy + 8
if J.paused then yy = para(ix, yy, iw, "PAUSED: " .. J.paused, C.warn, 2) end
if DW.trip and DW.trip.title then text(ix, yy, trunc("Now: " .. DW.trip.title, iw), C.label, C.panel) yy = yy + 1 end
if J.why then yy = para(ix, yy, iw, J.why, C.warn, 3) end
local a = J.anchor and state.turtles[J.anchor]
if a then text(ix, yy, trunc(a.label .. " keeps the site loaded", iw), C.dim, C.panel) end

local rows = DW.materials(J)
local my = yy + 2
if my + 2 < y + h - 5 then
heading(ix, my, iw, "STILL NEEDED")
my = my + 1
local half = math.floor((iw - 1) / 2)
for k, r in ipairs(rows) do
local ry = my + math.floor((k - 1) / 2)
if ry > y + h - 6 then break end
local cx = ix + ((k - 1) % 2) * (half + 1)
kv(cx, ry, half, prettify(r.item), r.need .. (r.have < r.need and ("  (AE2 " .. r.have .. ")") or ""),
r.have < r.need and C.warn or C.text)
end
end
local bw2 = math.floor((iw - 1) / 2)
button(ix, y + h - 4, bw2, 3, J.paused and "RESUME" or "PAUSE", J.paused and C.good or C.warn, "dwpause")
actButton(ix + bw2 + 1, y + h - 4, iw - bw2 - 1, 3, "STOP THE BUILD", { kind = "dwstop", name = "", count = 0 }, false, C.bad)
return
end
local list = DW.view.schems or {}
if #list == 0 then
para(ix, iy, iw, "No schematics yet. Save one with Create's Schematic and Quill, then drag the .nbt file " ..
"(from .minecraft/schematics on your PC) onto this computer's screen.", C.dim, 4)
return
end

local sel = DW.sel and DW.sel.name
local cols = iw >= 60 and 3 or (iw >= 36 and 2 or 1)
local cw = math.floor((iw - (cols - 1)) / cols)
local maxRows = math.max(1, math.floor((ih - 20) / 4))
local rowsN = math.min(maxRows, math.ceil(#list / cols))
local per = rowsN * cols
for i, name in ipairs(list) do
if i > per then break end
local c = (i - 1) % cols
local r = math.floor((i - 1) / cols)
local on = (name == sel)
button(ix + c * (cw + 1), iy + r * 4, (c == cols - 1) and (iw - c * (cw + 1)) or cw, 3, name, on and C.accent or C.line, "dwsel", name, on)
end
local yy = iy + rowsN * 4
if #list > per then text(ix, yy, "+" .. (#list - per) .. " more (console: schem)", C.dim, C.panel) yy = yy + 1 end
yy = yy + 1
local s = DW.sel
local pl, plWhy
if s and not s.err then pl, plWhy = DW.buildSpot(s) end
local bottomY = y + h - 12
if s and s.err then
yy = para(ix, yy, iw, s.err, C.warn, 3)
elseif s then
heading(ix, yy, iw, s.name:upper())

local lw2 = (iw >= 50) and math.floor((iw - 1) / 2) or iw
text(ix, yy + 1, trunc(s.size.x .. " x " .. s.size.y .. " x " .. s.size.z .. " blocks - " .. s.place .. " to place", lw2), C.text, C.panel)
text(ix, yy + 2, s.short > 0 and (s.short .. " item(s) short in AE2") or "AE2 has everything", s.short > 0 and C.warn or C.good, C.panel)
for k, r in ipairs(s.rows) do
local ry = yy + 3 + k
if ry > bottomY then break end
kv(ix, ry, lw2, prettify(r.item), r.need .. (r.have < r.need and ("  (AE2 " .. r.have .. ")") or ""),
r.have < r.need and C.warn or C.text)
end
if lw2 < iw and bottomY - yy >= 6 then
drawBuildPreview(ix + lw2 + 1, yy + 1, iw - lw2 - 1, bottomY - yy, s, DW.ui.rot or 0, pl)
end
else
text(ix, yy, "Tap a schematic to see what it needs and where it goes.", C.dim, C.panel)
end

local oy = y + h - 8
local where = "IN FRONT OF YOU"
if (DW.ui.at or 0) > 0 and state.waypoints[DW.ui.at] then where = state.waypoints[DW.ui.at].name:upper() end
local tw = math.max(8, math.floor((iw - 3) / 5))
local ww = iw - 3 * (tw + 1)
button(ix, oy, ww, 3, "WHERE: " .. where .. " >", C.line, "dwat")
button(ix + ww + 1, oy, tw, 3, "TURN LEFT", C.line, "dwrotl")
button(ix + ww + tw + 2, oy, tw, 3, "TURN RIGHT", C.line, "dwrot")
button(ix + ww + 2 * (tw + 1), oy, iw - ww - 2 * (tw + 1), 3, DW.ui.clear and "CLEAR: ON" or "CLEAR: OFF",
DW.ui.clear and C.warn or C.line, "dwclear", nil, DW.ui.clear)
if sel and pl then
para(ix, oy - 3, iw, pl.text, C.label, 3)
actButton(ix, y + h - 4, iw, 3, "BUILD " .. sel:upper() .. " THERE", { kind = "dwbuild", name = sel, count = 0 }, true)
elseif sel then
para(ix, y + h - 4, iw, "Where? " .. tostring(plWhy), C.warn, 2)
else
text(ix, y + h - 3, trunc("Blocks are placed the default way round (stairs / logs may face another way).", iw), C.dim, C.panel)
end
end




function drawBuildPreview(x, y, w, h, sel, rot, pl)
heading(x, y, w, "SEEN FROM ABOVE")
local fw, fd = DW.footprint(sel, rot)
local aw, ah = w - 2, h - 4
if aw < 3 or ah < 3 then return end

local sc = math.max(1, math.ceil(fw / aw), math.ceil(fd / ah))
local zh = (sc == 1) and math.max(1, math.min(math.floor(aw / (fw * 2)), math.floor(ah / fd), 4)) or 1
local zw = (sc == 1) and 2 * zh or 1
if sc == 1 and fw * 2 > aw then zw, zh = 1, 1 end
local cw, ch = math.ceil(fw / sc) * zw, math.ceil(fd / sc) * zh
local x0 = x + 1 + math.floor((aw - cw) / 2)
local y0 = y + 2 + math.floor((ah - ch) / 2)
for cy = 0, ch - 1 do
for cx = 0, cw - 1 do
local bx = math.min(fw - 1, math.floor(cx / zw) * sc + math.floor(sc / 2))
local bz = math.min(fd - 1, math.floor(cy / zh) * sc + math.floor(sc / 2))
local it = DW.topAt(sel, rot, bx, bz)
if it then text(x0 + cx, y0 + cy, " ", C.text, colorFor(it)) else text(x0 + cx, y0 + cy, ".", C.line, C.panel) end
end
end
text(x + w - 3, y + 1, "N^", C.label, C.panel)

if pl and pl.how == "front" then
local look = pl.look or 2
local mx, my = x0 + math.floor(cw / 2), y0 + math.floor(ch / 2)
if look == 2 then text(mx, y0 - 1, "@", C.good, C.panel)
elseif look == 0 then text(mx, y0 + ch, "@", C.good, C.panel)
elseif look == 1 then text(x0 - 1, my, "@", C.good, C.panel)
else text(x0 + cw, my, "@", C.good, C.panel) end
end
local note = (pl and pl.how == "front" and "@ = you" or (pl and "centred on the place" or "")) ..
(sc > 1 and ("  (1 dot = " .. sc .. " blocks)") or "") .. "  " .. DW.turnText(rot):gsub(" %(.*$", "")
text(x, y + h - 1, trunc(note, w), C.dim, C.panel)
end

function drawWorkPage(G)
local y0, bottom = G.y0, G.y1
local lw = math.floor((W - 3) * 0.42)
local rx, rw = 2 + lw + 1, W - (2 + lw + 1)
local th = bottom - y0 + 1
local ch = 13
local rest = th - ch - 1
local nf = 0
for _, t in pairs(state.turtles) do
if (TT.online(t) and tonumber(t.fuel) and tonumber(t.fuel) < 20) or DW.runs[t.id] then nf = nf + 1 end
end
local fh = math.max(14, math.min(13 + nf * 3, math.floor((rest - 1) / 2)))
chestPanel(2, y0, lw, ch)
fuelPanel(2, y0 + ch + 1, lw, fh)
placesPanel(2, y0 + ch + 1 + fh + 1, lw, th - ch - fh - 2)
buildPanel(rx, y0, rw, th)
end
