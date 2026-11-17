







function hashColor(name)
local h = 5381
for i = 1, #name do h = (h * 33 + name:byte(i)) % 2147483647 end
return ITEM_COLORS[h % #ITEM_COLORS + 1]
end






FLUID_MAX = 2147483647
function FLUID_ALL(n) return math.max(1, tonumber(n) or 0) end


function keepRow(x, y, w, sel, kind)
heading(x, y, w, "KEEP A STORAGE FILLED")
local list = (SUPPLY.cache or {})[kind] or {}
if #list == 0 then
text(x, y + 1, trunc("No storage for this on the cable - wired modem on it, then type supply", w), C.dim, C.panel)
return
end
state.supIdx = state.supIdx or {}
local i = state.supIdx[kind] or 1
if i > #list then i = 1 end
local target = list[i]
local tw = math.floor(w * 0.42)
button(x, y + 1, tw, 3, trunc(target, tw - (#list > 1 and 3 or 1)) .. (#list > 1 and " >" or ""), C.line, "supnext", kind)
local r = SUPPLY.ruleFor(target, kind, sel.name)
local bx, bw = x + tw + 1, w - tw - 1
if r then
actButton(bx, y + 1, bw, 3, "KEPT AT " .. SUPPLY.amount(r, r.keep) .. " - STOP",
{ kind = "supplystop", name = sel.name, count = 0, target = target, skind = kind }, false, C.warn)
else
local am = (kind == "fluid") and { { "16 B", 16000 }, { "256 B", 256000 }, { "FULL", SUPPLY.FULL } }
or { { "x64", 64 }, { "x1000", 1000 }, { "FULL", SUPPLY.FULL } }
local ew = math.floor((bw - 2) / 3)
for k, a in ipairs(am) do
actButton(bx + (k - 1) * (ew + 1), y + 1, (k == 3) and (bw - 2 * (ew + 1)) or ew, 3, a[1],
{ kind = "supplyset", name = sel.name, count = a[2], target = target, skind = kind }, false, C.purple)
end
end
end

function fmtBuckets(mb)
mb = tonumber(mb) or 0
if mb >= 1000 then return commas(math.floor(mb / 1000)) .. " B" end
return commas(mb) .. " mB"
end


function meView()
local me = state.me
local key = table.concat({ state.meVersion, state.meSort, tostring(state.meType),
tostring(state.meCraftOnly), tostring(state.meLetter) }, "|")
if state.meViewKey == key and state.meView then return state.meView end
local out = {}
local src = (state.meType == "fluids" and me.fluids) or (state.meType == "chemicals" and me.chemicals) or me.items
for _, it in ipairs(src or {}) do
local okLetter = true
if state.meLetter then
local c = it.display:sub(1, 1):upper()
if state.meLetter == "#" then okLetter = not c:match("%a")
else okLetter = (c == state.meLetter) end
end
if okLetter and (not state.meCraftOnly or it.craftable) then out[#out + 1] = it end
end
local byCount = state.meSort == "count"
table.sort(out, function(a, b)
if byCount and a.count ~= b.count then return a.count > b.count end
return a.display:lower() < b.display:lower()
end)
state.meView, state.meViewKey = out, key
return out
end



local function amountRow(x, yy, w, label, kind, name, amounts, col, maxCount)
heading(x, yy, w, label)
local n = #amounts
local bw = math.floor((w - (n - 1)) / n)
for i, a in ipairs(amounts) do
local cnt = a[2]
if maxCount and kind == "take" and cnt > maxCount then cnt = math.max(1, maxCount) end
actButton(x + (i - 1) * (bw + 1), yy + 1, (i == n) and (w - (n - 1) * (bw + 1)) or bw, 3, a[1],
{ kind = a[3] or kind, name = name, count = cnt }, false, col)
end
return yy + 5
end




function drawMEPage(G)
local y0, y1 = G.y0, G.y1
if not bridge then
drawMessage("NO ME / RS BRIDGE", deviceHelpLines("ME/RS Bridge"), C.warn)
return
end
local me = state.me
if not me then
drawMessage("LOADING", { "Reading the storage network..." }, C.label)
return
end
if me.err then
drawMessage(bridgeKind .. " BRIDGE", { me.err }, C.warn)
return
end
local leftW = math.floor((W - 3) * 0.6)
local rx = 2 + leftW + 1
local rw = W - rx
local mtype = state.meType or "items"
local liquid = mtype ~= "items"

local view = meView()
local ix, iy, iw, ih = panel(2, y0, leftW, y1 - y0 + 1, bridgeKind .. " " .. mtype:upper(),
{ right = commas(#view) .. " shown" })
local types = { { "items", "ITEMS " .. #me.items }, { "fluids", "FLUIDS " .. #(me.fluids or {}) } }
if me.hasChem then types[#types + 1] = { "chemicals", "CHEMICALS " .. #(me.chemicals or {}) } end
local tx = ix
for _, t in ipairs(types) do
local on = mtype == t[1]
local w = #t[2] + 4
button(tx, iy, w, 2, t[2], on and C.accent or C.line, "metype", t[1], on)
tx = tx + w + 1
end
local b2 = state.meCraftOnly and "CRAFTABLE ONLY" or "ALL ITEMS"
local b1 = "SORT: " .. state.meSort:upper()
local bx2 = ix + iw - #b2 - 4
local bx1 = bx2 - #b1 - 5
button(bx1, iy, #b1 + 4, 2, b1, C.line, "mesort")
button(bx2, iy, #b2 + 4, 2, b2, state.meCraftOnly and C.good or C.line, "mecraft", nil, state.meCraftOnly)

local tokens = { { "ALL", false } }
for c = 65, 90 do tokens[#tokens + 1] = { string.char(c), string.char(c) } end
tokens[#tokens + 1] = { "#", "#" }
local lx = ix
local lw = math.max(3, math.floor((iw - 2) / #tokens))
for k, t in ipairs(tokens) do
local w = (k == 1) and math.max(lw, 5) or lw
if lx + w - 1 > ix + iw - 1 then break end
local active = (state.meLetter == (t[2] or nil))
button(lx, iy + 3, w, 2, t[1], active and C.accent or C.line, "meletter", t[2], active)
lx = lx + w
end
local ry0 = iy + 6
if me.partial and not liquid then
text(ix, ry0, trunc("PARTIAL VIEW: an item breaks the server's list - " .. tostring(me.partialCount or 0) ..
" items found by their tags", iw), C.warn, C.panel)
local where = me.brokenName and ("BROKEN ITEM: " .. me.brokenName .. " - take it out of the network")
or (me.brokenTags and #me.brokenTags > 0)
and ("the broken item has tag " .. table.concat(me.brokenTags, " ") .. " - take it out of the network")
or "the broken item has none of the common tags - recently added modded items are suspects"
text(ix, ry0 + 1, trunc(where, iw), C.warn, C.panel)
ry0 = ry0 + 3
end
local per = math.max(1, (y1 - 1) - ry0)
local pages = math.max(1, math.ceil(#view / per))
state.meItemsPage = math.max(1, math.min(state.meItemsPage, pages))
drawPager(y0, "meItemsPage", pages, 2 + leftW - 2)
local maxCount = 1
for _, it in ipairs(view) do if it.count > maxCount then maxCount = it.count end end
if #view == 0 then text(ix, ry0, "No " .. mtype .. " match this filter.", C.dim, C.panel) end
for i = 1, per do
local it = view[(state.meItemsPage - 1) * per + i]
if not it then break end
local ry = ry0 + i - 1
local vs = (liquid and fmtBuckets(it.count) or commas(it.count)) .. (it.craftable and "  CRAFT" or "")
drawBarRow(ix, ry, iw, it.display, vs, it.count / maxCount, hashColor(it.name), state.meSel == it.name, 20)
addHit(ix, ry, iw, 1, "meitem", it.name)
end

local storages = {}
local function addStore(label, st, buckets)
if st and st.used and st.max and st.max > 0 then storages[#storages + 1] = { label, st, buckets } end
end
addStore("Item storage", me.storage, false)
addStore("Fluid storage", me.fstorage, true)
addStore("Chemical storage", me.cstorage, true)
local en = me.energy or {}
local hasEn = en.stored and en.cap and en.cap > 0
local nh = 3 + (hasEn and 3 or 0) + 3 * #storages + ((en.usage or en.inj) and 1 or 0) + 4
local online = me.online ~= false
local nx, ny, nw = panel(rx, y0, rw, nh, "NETWORK", { right = online and "ONLINE" or "OFFLINE", rcol = online and C.good or C.bad })
local r = ny
if hasEn then
meter(nx, r, nw, "Energy", compact(en.stored) .. " / " .. compact(en.cap), en.stored / en.cap, C.warn)
r = r + 3
end
for _, sto in ipairs(storages) do
local st = sto[2]
local f = math.min(1, st.used / st.max)
local v = sto[3] and (fmtBuckets(st.used) .. " / " .. fmtBuckets(st.max)) or (compact(st.used) .. " / " .. compact(st.max))
meter(nx, r, nw, sto[1], v, f, f < 0.6 and C.good or (f < 0.85 and C.warn or C.bad))
r = r + 3
end
if en.usage or en.inj then
kv(nx, r, nw, "Energy use / injection", (en.usage and (compact(en.usage) .. "/t") or "?") .. "  /  " ..
(en.inj and (compact(en.inj) .. "/t") or "?"))
r = r + 1
end
local owed, kinds = 0, 0
if owedCount then owed, kinds = owedCount() end
if owed > 0 then text(nx, r, trunc(owed .. " item(s) of " .. kinds .. " kinds wait in the buffer - retried by itself", nw), C.warn, C.panel) end
local fb = me.fluidBuf and (" + " .. me.fluidBuf) or ""
actButton(nx, y0 + nh - 4, nw, 3, "BUFFER -> ME  (empties " .. tostring(chestBridge("give")) .. fb .. ")",
{ kind = "flushbuf", name = "buffer", count = 0 }, false, C.purple)

local selMap = (mtype == "fluids" and me.byNameF) or (mtype == "chemicals" and me.byNameC) or me.byName
local sel = state.meSel and (selMap or {})[state.meSel]
local py = y0 + nh + 1
local ph
if not sel then ph = 7
elseif liquid then
ph = (mtype == "fluids" and me.fluidBuf) and (12 + 5 * 3 + (sel.craftable and 5 or 0) + (SUPPLY and 5 or 0)) or 16
else
ph = 10 + 5 + (sel.craftable and 5 or 0) + (SUPPLY and 5 or 0) + 3
end
ph = math.min(ph, y1 - py + 1)
local sx, sy, sw = panel(rx, py, rw, ph, "SELECTED", { right = sel and (sel.craftable and "craftable" or "") or nil, rcol = C.good })
if not sel then
text(sx, sy, "Tap an item in the list.", C.dim, C.panel)
else
cell(sx, sy, 1 + 4 + 16, hashColor(sel.name), C.panel)
cell(sx, sy + 1, 1 + 4 + 16, hashColor(sel.name), C.panel)
text(sx + 2, sy, trunc(sel.display, sw - 2), C.text, C.panel)
text(sx + 2, sy + 1, trunc(sel.name, sw - 2), C.dim, C.panel)
local bw = big(sx, sy + 3, liquid and fmtBuckets(sel.count):gsub(" ", "") or compact(sel.count), C.label, C.panel)
text(sx + bw + 1, sy + 4, liquid and "in the network" or (commas(sel.count) .. " in the network"), C.dim, C.panel)
local yy = sy + 6
if liquid and mtype == "fluids" and me.fluidBuf then
local inBuf = 0
for _, tk in pairs(me.fluidBufTanks or {}) do
if type(tk) == "table" and tk.name == sel.name then inBuf = inBuf + (tonumber(tk.amount) or 0) end
end
local inTanks, nTanks = 0, 0
for _, st in ipairs(state.storage or {}) do
if st.isFluid and st.ref then
nTanks = nTanks + 1
for _, tk in ipairs(st.tanks or {}) do if tk.name == sel.name then inTanks = inTanks + (tonumber(tk.amount) or 0) end end
end
end
kv(sx, yy, sw, "In the fluid storage", fmtBuckets(inBuf))
kv(sx, yy + 1, sw, "In your containers", nTanks > 0 and fmtBuckets(inTanks) or "none carried")
yy = yy + 3
yy = amountRow(sx, yy, sw, "TAKE TO THE FLUID STORAGE", "ftake", sel.name,
{ { "1 B", 1000 }, { "16 B", 16000 }, { "64 B", 64000 }, { "ALL", FLUID_ALL(sel.count) } }, C.info)
if nTanks > 0 then
yy = amountRow(sx, yy, sw, "FILL MY CONTAINERS", "ftank", sel.name,
{ { "1 B", 1000 }, { "16 B", 16000 }, { "ALL", FLUID_ALL(sel.count) } }, C.info)
end
local store = { { "16 B", 16000 }, { "ALL", FLUID_ALL(inBuf) } }
if inTanks > 0 then store[#store + 1] = { "FROM MINE", inTanks, "fempty" } end
yy = amountRow(sx, yy, sw, "STORE IN AE2", "fstore", sel.name, store, C.purple)
if sel.craftable then
yy = amountRow(sx, yy, sw, "CRAFT", "fcraft", sel.name, { { "1 B", 1000 }, { "16 B", 16000 }, { "64 B", 64000 }, { "256 B", 256000 } }, C.good)
end
if SUPPLY then keepRow(sx, yy, sw, sel, "fluid") end
elseif liquid then
yy = para(sx, yy, sw, mtype == "fluids" and ("Fluids cannot be moved: " .. tostring(me.fluidBufErr or "no fluid storage") ..
((not me.fluidBuf) and " - connect a tank or fluid storage to the wired network" or ""))
or ("View only: " .. mtype .. " cannot be moved from here"), C.warn, 3) + 1
if sel.craftable and mtype == "fluids" then
amountRow(sx, yy, sw, "CRAFT", "fcraft", sel.name, { { "1 B", 1000 }, { "16 B", 16000 }, { "64 B", 64000 }, { "256 B", 256000 } }, C.good)
end
else
yy = amountRow(sx, yy, sw, "TAKE TO MY INVENTORY", "take", sel.name,
{ { "x1", 1 }, { "x16", 16 }, { "x64", 64 }, { "ALL", FLUID_ALL(sel.count) } }, C.info, sel.count)
if sel.craftable then
yy = amountRow(sx, yy, sw, "CRAFT", "craft", sel.name, { { "x1", 1 }, { "x16", 16 }, { "x64", 64 }, { "x256", 256 } }, C.good)
end
if SUPPLY then keepRow(sx, yy, sw, sel, "item") yy = yy + 5 end
local chests = me.chests or {}
local function chestLine(w, label, ly)
local c = chests[w]
local mdir = chestManagerDir(w)
local manual = (w == "give") and CONFIG.me.giveChest or CONFIG.me.takeChest
local auto = state.meAuto and state.meAuto[w]
local how = manual and tostring(manual) or (auto and (auto .. " (found)")) or
(bufBridge() .. (CONFIG.me.buffer and "" or " of bridge") .. " - put an item in it once to find it")
if c and c.ok == false then
text(sx, ly, trunc("NO " .. label .. " CHEST on the " .. mdir .. " side of the Inventory Manager - type mesetup", sw), C.bad, C.panel)
else
text(sx, ly, trunc(label .. " chest: " .. mdir .. " of the manager, bridge: " .. how, sw), C.dim, C.panel)
end
end
if chestManagerDir("give") == chestManagerDir("take") then chestLine("give", "BUFFER", py + ph - 3)
else chestLine("give", "GIVE", py + ph - 3) chestLine("take", "TAKE", py + ph - 2) end
end
end

local cy = py + ph + 1
if #(me.cellTypes or {}) > 0 then
local ch2 = 3 + #me.cellTypes * 2
if y1 - cy + 1 >= ch2 + 5 then
local cx2, cyy, cw2 = panel(rx, cy, rw, ch2, "DRIVES & CELLS")
for i, ct in ipairs(me.cellTypes) do
local f = ct.total > 0 and math.min(1, ct.used / ct.total) or 0
meter(cx2, cyy + (i - 1) * 2, cw2, ct.n .. "x " .. ct.label, math.floor(f * 100 + 0.5) .. "% full", f,
f < 0.6 and C.good or (f < 0.85 and C.warn or C.bad))
end
cy = cy + ch2 + 1
end
end
local chh = y1 - cy + 1
if chh >= 5 then
local tasks = me.tasks or {}
local jx, jy, jw, jh = panel(rx, cy, rw, chh, "CRAFTING JOBS", { right = #tasks .. " running" })
if #tasks == 0 then
text(jx, jy, "No crafting jobs running.", C.dim, C.panel)
else
local rows = math.max(1, math.floor((jh + 1) / 3))
for i = 1, math.min(rows, #tasks) do
local t = tasks[i]
meter(jx, jy + (i - 1) * 3, jw, t.name, commas(t.crafted) .. " / " .. commas(t.quantity),
math.max(0, math.min(1, t.completion)), C.good)
end
if #tasks > rows then text(jx, cy + chh - 2, "+" .. (#tasks - rows) .. " more", C.dim, C.panel) end
end
end
end
