






function num(v)
return (string.format("%.1f", v):gsub("%.0$", ""))
end


function dimColor(dim)
local d = tostring(dim or ""):lower()
if d == "" then return C.dim end
if d:find("nether") then return C.red end
if d:find("end") then return C.purple end
if d:find("overworld") then return C.good end
return C.label
end



function dimLabel(dim, other)
if dim then return prettify(dim) end
return other and "Other dimension" or "Unknown"
end


function drawStatus(x, y, w, p, dim, showDim, other)
local hp, mx = p.health or 0, p.maxHealth or 20
local frac = mx > 0 and math.min(1, hp / mx) or 0
local col = frac > 0.6 and C.good or (frac > 0.3 and C.warn or C.bad)
meter(x, y, w, "Health", num(hp) .. " / " .. num(mx), frac, col)
local r = y + 2
if p.airSupply then
local af = math.max(0, math.min(1, p.airSupply / 300))
meter(x, r, w, "Air", af >= 1 and "full" or (math.floor(af * 100 + 0.5) .. "%"), af, C.info)
r = r + 2
end
if p.x then
kv(x, r, w, "Position", string.format("%d, %d, %d", math.floor(p.x), math.floor(p.y or 0), math.floor(p.z or 0)))
r = r + 1
end
if showDim then
kv(x, r, w, "Dimension", dimLabel(dim, other), other and not dim and C.label or dimColor(dim))
r = r + 1
end
if p.yaw then
local dirs = { "South", "West", "North", "East" }
kv(x, r, w, "Facing", dirs[math.floor((p.yaw % 360 + 45) / 90) % 4 + 1])
end
end


function drawPlayer(x, y, w, h)
local p = state.player
local ix, iy, iw = panel(x, y, w, h, "YOU" .. (state.owner and (": " .. state.owner) or ""),
{ right = p and dimLabel(state.playerDim, state.playerDimOther) or nil, rcol = dimColor(state.playerDim) })
if not p then
text(ix, iy, trunc(state.playerMsg or "No data", iw), C.warn, C.panel)
text(ix, iy + 1, trunc("Is the player inside the detector's range?", iw), C.dim, C.panel)
return
end
drawStatus(ix, iy, iw, p, state.playerDim, false, state.playerDimOther)
end


function drawPlayerCard(x, y, w, h, e)
local d = dimLabel(e.dim, e.dimOther)
local ix, iy, iw, ih = panel(x, y, w, h, e.name, { right = d, rcol = (e.dimOther and not e.dim) and C.label or dimColor(e.dim),
col = e.isOwner and C.accent or C.line, tcol = e.isOwner and C.accent or C.label })
if not e.p then
text(ix, iy, trunc(e.err or "No data", iw), C.warn, C.panel)
return
end
if state.rawView[e.name] then
text(ix, iy, "RAW DATA  (tap to close)", C.label, C.panel)
local keys = {}
for k in pairs(e.p) do keys[#keys + 1] = tostring(k) end
table.sort(keys)
local rowsAvail = math.max(1, ih - 1)
local colW = math.floor(iw / 2)
for i, k in ipairs(keys) do
local col = math.floor((i - 1) / rowsAvail)
if col > 1 then break end
local v = e.p[k]
local vs = type(v) == "table" and "{table}" or tostring(v)
text(ix + col * colW, iy + 1 + (i - 1) % rowsAvail, trunc(k .. " = " .. vs, colW - 1), C.dim, C.panel)
end
else
drawStatus(ix, iy, iw, e.p, e.dim, false)

local r = iy + (e.p.airSupply and 8 or 6)
local h0 = CONFIG.drone and CONFIG.drone.home
if h0 and e.p.x and r <= y + h - 2 then
kv(ix, r, iw, "From the base", math.floor(math.abs(e.p.x - h0.x) + math.abs(e.p.z - h0.z)) .. " blocks")
r = r + 2
end
if r + 2 <= y + h - 2 then
heading(ix, r, iw, "DETECTOR DATA")
r = r + 1
local keys = {}
for k in pairs(e.p) do keys[#keys + 1] = tostring(k) end
table.sort(keys)
local colW = math.floor((iw - 1) / 2)
local rowsAvail = (y + h - 2) - r + 1
for i, k in ipairs(keys) do
local col = math.floor((i - 1) / rowsAvail)
if col > 1 then break end
local v = e.p[k]
local vs = type(v) == "table" and "{...}" or tostring(v)
kv(ix + col * (colW + 1), r + (i - 1) % rowsAvail, colW, k, vs, C.dim)
end
end
end
end


function drawPlayersPage(G)
local y0 = G.y0
if not det then
drawMessage("NO PLAYER DETECTOR", deviceHelpLines("Player Detector"), C.warn)
return
end
if not state.t.players then
drawMessage("LOADING", { "Reading players..." }, C.label)
return
end
local list = state.players
if #list == 0 then
drawMessage("NO PLAYERS FOUND", { state.playerMsg or "The detector returned no players." }, C.warn)
return
end
local anyAir = false
for _, e in ipairs(list) do if e.p and e.p.airSupply then anyAir = true break end end
local cols = W >= 150 and 3 or 2
local ch = anyAir and 12 or 10
local cw = math.floor((W - 2 - (cols - 1)) / cols)

local need = math.ceil(#list / cols)
local fit = math.max(1, math.floor((G.bodyH - 1) / (ch + 1)))
if need <= fit then ch = math.max(ch, math.min(40, math.floor((G.bodyH - 1) / need) - 1)) end
local rows = math.max(1, math.floor((G.bodyH - 1) / (ch + 1)))
local per = rows * cols
local pages = math.max(1, math.ceil(#list / per))
state.playersPage = math.max(1, math.min(state.playersPage, pages))
text(2, y0, #list .. " PLAYERS", C.label, C.bg)
text(4 + #(#list .. " PLAYERS"), y0, "tap a card for everything the detector says", C.dim, C.bg)
drawPager(y0, "playersPage", pages)
for i = 1, per do
local e = list[(state.playersPage - 1) * per + i]
if not e then break end
local col = (i - 1) % cols
local row = math.floor((i - 1) / cols)
local cx = 2 + col * (cw + 1)
local cy = y0 + 1 + row * (ch + 1)
drawPlayerCard(cx, cy, (col == cols - 1) and (W - cx) or cw, ch, e)
CLIP = nil
addHit(cx, cy, cw, ch, "praw", e.name)
end
end
