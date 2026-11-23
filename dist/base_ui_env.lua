








local KCOL = { hostile = "bad", animal = "good", player = "accent", other = "dim" }
local function kcol(k) return C[KCOL[k] or "dim"] end
local COMPASS = { "S", "SW", "W", "NW", "N", "NE", "E", "SE" }
local function dirOf(x, z)
if math.abs(x) < 1 and math.abs(z) < 1 then return "here" end
local a = math.atan2 and math.atan2(-x, z) or math.atan(-x, z)
return COMPASS[math.floor((math.deg(a) % 360 + 22.5) / 45) % 8 + 1]
end




local function moon(x, y, id, col, bg)
local cw, ch = 6, 4
local W2, H2 = cw * 2, ch * 3
local f = (1 + math.cos((tonumber(id) or 0) * math.pi / 4)) / 2
local waxing = (tonumber(id) or 0) >= 5
local function disc(px, py)
local u = (px + 0.5) / W2 * 2 - 1
local v = (py + 0.5) / H2 * 2 - 1
return u * u + v * v <= 1, u, v
end
local function lit(px, py)
local inside, u, v = disc(px, py)
if not inside then return false end
local hw = math.sqrt(math.max(0, 1 - v * v))
if waxing then return u > hw * (1 - 2 * f) end
return u < -hw * (1 - 2 * f)
end
for cy = 0, ch - 1 do
for cx = 0, cw - 1 do
local litBits, discBits, k = 0, 0, 1
for py = 0, 2 do
for pxl = 0, 1 do
local px, pyy = cx * 2 + pxl, cy * 3 + py
if lit(px, pyy) then litBits = litBits + k end
if disc(px, pyy) then discBits = discBits + k end
k = k * 2
end
end
if litBits > 0 then

cell(x + cx, y + cy, litBits, col, (discBits ~= litBits) and C.line or bg)
else
cell(x + cx, y + cy, discBits, C.line, bg)
end
end
end
end

local function topPanels(y, h)
local d = ENV.data or {}
local gap = 1
local n = 4
local pw = math.floor((W - 2 - (n - 1) * gap) / n)
local xs = {}
for i = 1, n do xs[i] = 2 + (i - 1) * (pw + gap) end
local function wOf(i) return (i == n) and (W - xs[i]) or pw end

local c = ENV.clock(d.time)
local ix, iy, iw = panel(xs[1], y, wOf(1), h, "GAME TIME", { right = c and ("day " .. commas(c.day)) or nil })
if c then
local bw = big(ix, iy, c.hhmm, c.night and C.info or C.label, C.panel)
text(ix + bw + 1, iy + 1, c.night and "NIGHT" or "DAY", c.night and C.info or C.warn, C.panel)
para(ix, iy + 3, iw, (c.night and "Mobs spawn now - day in " or "Night (mobs) in ") .. fmtSpan(c.secs), C.dim, 2)
else
text(ix, iy, "not known", C.dim, C.panel)
end

ix, iy, iw = panel(xs[2], y, wOf(2), h, "WEATHER")
local word, wcol = "?", C.dim
if d.thunder then word, wcol = "THUNDER", C.purple
elseif d.rain then word, wcol = "RAIN", C.info
elseif d.sunny or d.rain == false then word, wcol = "CLEAR", C.warn end
local bw = (bigW(word) <= iw) and big(ix, iy, word, wcol, C.panel) or 0
if bw == 0 then text(ix, iy, word, wcol, C.panel) end
if d.sleep ~= nil then
text(ix, iy + 3, d.sleep and "You can sleep now" or "Too early to sleep", d.sleep and C.good or C.dim, C.panel)
end
if d.thunder then para(ix, iy + 4, iw, "Thunder: mobs spawn in the day too", C.warn, 1) end

ix, iy, iw = panel(xs[3], y, wOf(3), h, "MOON")
if d.moonId then
moon(ix, iy, d.moonId, C.text, C.panel)
para(ix + 8, iy, iw - 8, tostring(d.moonName or ("phase " .. d.moonId)), C.text, 2)
if d.moonId == 0 then para(ix + 8, iy + 2, iw - 8, "more slimes and harder mobs", C.dim, 2) end
else
text(ix, iy, "not known", C.dim, C.panel)
end

ix, iy, iw = panel(xs[4], y, wOf(4), h, "LIGHT AT THE DETECTOR")
local r = iy
for _, l in ipairs({ { "Block light", d.block, C.warn }, { "Sky light", d.sky, C.info }, { "Daylight", d.daylight, C.label } }) do
if l[2] and r + 1 <= y + h - 2 then
meter(ix, r, iw, l[1], tostring(l[2]) .. " / 15", (tonumber(l[2]) or 0) / 15, l[3])
r = r + 2
end
end
if r == iy then text(ix, iy, "not known", C.dim, C.panel) end
end

local function aroundPanel(x, y, w, h)
local d = ENV.data or {}
local cnt = d.count
local ix, iy, iw, ih = panel(x, y, w, h, "AROUND THE BASE", {
right = d.range and ("within " .. d.range .. " blocks") or nil,
col = (cnt and cnt.hostile > 0) and C.warn or C.line })
if not cnt then
para(ix, iy, iw, d.scanErr and ("The scan did not work: " .. d.scanErr) or
(envDet and envDet.scanEntities and "Scanning ..." or "This detector cannot scan for mobs (an older Advanced Peripherals)."),
d.scanErr and C.warn or C.dim, 3)
return
end

local bx = ix
for _, k in ipairs({ { "hostile", "HOSTILE" }, { "animal", "ANIMALS" }, { "player", "PLAYERS" }, { "other", "OTHER" } }) do
local n = cnt[k[1]] or 0
bx = bx + badge(bx, iy, n .. " " .. k[2], n > 0 and kcol(k[1]) or C.line, n > 0 and C.ink or C.dim) + 1
end
if d.scanErr then text(bx + 1, iy, trunc("(last scan: " .. d.scanErr .. ")", math.max(0, ix + iw - bx - 1)), C.warn, C.panel) end

local ents = d.ents or {}
local r0 = iy + 2
local rows = (y + h - 2) - r0 + 1
if #ents == 0 then text(ix, r0, "Nothing alive near the detector.", C.dim, C.panel) return end
local hpW = math.max(6, math.floor(iw * 0.22))
for i, e in ipairs(ents) do
if i > rows then
text(ix, y + h - 2, "+" .. (#ents - rows + 1) .. " more", C.dim, C.panel)
break
end
local ry = r0 + i - 1
if i == rows and #ents > rows then
text(ix, ry, "+" .. (#ents - rows + 1) .. " more", C.dim, C.panel)
break
end
led(ix, ry, kcol(e.kind))
local where = string.format("%d %s", math.floor(e.dist + 0.5), dirOf(e.x, e.z))
local dy = math.floor(e.y + 0.5)
if dy > 2 then where = where .. "  " .. dy .. " up" elseif dy < -2 then where = where .. "  " .. -dy .. " down" end
local name = e.name .. (e.baby and " (baby)" or "")
local nameW = iw - 2 - hpW - 1 - #where - 2
text(ix + 2, ry, trunc(name, math.max(1, nameW)), e.kind == "hostile" and C.bad or C.text, C.panel)
text(ix + iw - hpW - 1 - #where, ry, where, C.dim, C.panel)
if e.hp and e.max and e.max > 0 then
local f = math.max(0, math.min(1, e.hp / e.max))
gauge(ix + iw - hpW, ry, hpW, f, f > 0.6 and C.good or (f > 0.3 and C.warn or C.bad))
end
end
end

local function herePanel(x, y, w, h)
local d = ENV.data or {}
local ix, iy, iw = panel(x, y, w, h, "HERE")
local r = iy
local function row(k, v, col) if v ~= nil and r <= y + h - 2 then kv(ix, r, iw, k, v, col) r = r + 1 end end
row("Biome", d.biome and prettify(tostring(d.biome)))
row("Dimension", d.dim and prettify(tostring(d.dim)), d.dim and dimColor(d.dim))
row("Slime chunk", d.slime == nil and nil or (d.slime and "YES - slimes spawn below Y 40" or "no"), d.slime and C.good or nil)

local radTxt = d.rad or (d.radRaw and (string.format("%.2f", d.radRaw) .. " Sv/h"))
if radTxt and d.radRaw and d.radRaw <= 0.000001 then radTxt = radTxt .. " (normal)" end
row("Radiation", radTxt, (d.radRaw and d.radRaw > 0.0001) and C.warn or nil)
row("Detector", picked and picked.env or "?", C.dim)
end

local function dimsPanel(x, y, w, h)
local d = ENV.data or {}
local all = d.dims or {}

local who, unknown = {}, 0
for _, p in ipairs(state.players or {}) do
if p.dim then who[p.dim] = who[p.dim] or {} table.insert(who[p.dim], p.name)
elseif p.p or (state.online and state.online[tostring(p.name):lower()]) then unknown = unknown + 1 end
end


local dims, private = {}, 0
for _, dn in ipairs(all) do
if ENV.privateDim(dn) and not who[dn] then private = private + 1 else dims[#dims + 1] = dn end
end
local function rank(dn) return (who[dn] and (1000 + #who[dn])) or (dn == d.dim and 500) or 0 end
table.sort(dims, function(a, b)
local ra, rb = rank(a), rank(b)
if ra ~= rb then return ra > rb end
return ENV.dimName(a) < ENV.dimName(b)
end)
local ix, iy, iw = panel(x, y, w, h, "DIMENSIONS", { right = #all > 0 and (#all .. " in this world") or nil })
if #all == 0 then text(ix, iy, "not known", C.dim, C.panel) return end
local bottom = y + h - 2
local r = iy
for i, dn in ipairs(dims) do
if r > bottom then break end
if r == bottom and i < #dims then
text(ix, r, "+" .. (#dims - i + 1) .. " more" .. (private > 0 and (", " .. private .. " private") or ""), C.dim, C.panel)
private = 0
r = r + 1
break
end
local list = who[dn]
led(ix, r, list and dimColor(dn) or C.line)
kv(ix + 2, r, iw - 2, ENV.dimName(dn) .. (d.dim == dn and "  (base)" or ""),
list and (#list .. (#list == 1 and " player" or " players")) or "-", list and C.text or C.dim)
r = r + 1
if list and r <= bottom then
table.sort(list, function(a, b) return a:lower() < b:lower() end)
r = para(ix + 2, r, iw - 2, table.concat(list, ", "), C.dim, math.min(3, bottom - r + 1))
end
end
if private > 0 and r <= bottom then
led(ix, r, C.line)
kv(ix + 2, r, iw - 2, private .. " private dimensions", "spatial cells, rooms ...", C.dim)
r = r + 1
end
if unknown > 0 and r <= bottom then
para(ix, r, iw, unknown .. " player(s) in a dimension the detector cannot name", C.dim, 2)
end
end

function drawEnvPage(G)
if not envDet then
drawMessage("NO ENVIRONMENT DETECTOR", deviceHelpLines("Environment Detector"), C.warn)
return
end
if not ENV.data then
drawMessage("LOADING", { "Reading the Environment Detector..." }, C.label)
return
end
local y0, y1 = G.y0, G.y1
local th = 9
topPanels(y0, th)
CLIP = nil
local y = y0 + th + 1
local lw = math.floor((W - 3) * 0.6)
local rx = 2 + lw + 1
local rw = W - rx
aroundPanel(2, y, lw, y1 - y + 1)
CLIP = nil
local hh = 9
herePanel(rx, y, rw, hh)
CLIP = nil
if y1 - (y + hh + 1) + 1 >= 5 then dimsPanel(rx, y + hh + 1, rw, y1 - (y + hh + 1) + 1) end
CLIP = nil
end
