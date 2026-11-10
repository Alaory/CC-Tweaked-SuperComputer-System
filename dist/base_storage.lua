












function isDistError(e)
e = tostring(e or "")
return e:find("invalid dist", 1, true) ~= nil
or e:find("net/minecraft/client", 1, true) ~= nil
end

DIST_LINES = {
"A mod on the server threw an error while an item was being read",
"(it tried to use client-only code on a dedicated server).",
"This is a bug in some modded item, not in this script.",
"Look in the server's logs/latest.log for 'invalid dist': the lines under it name the mod.",
}


function durability(it)
local c = type(it.components) == "table" and it.components or {}
local dmg = tonumber(c["minecraft:damage"] or it.damage)
local mx = tonumber(c["minecraft:max_damage"] or it.maxDamage)
if dmg and mx and mx > 0 then return math.max(0, mx - dmg), mx end
end





local CURIOS_FILE = "curios_last.dat"

KNOWN_BROKEN = CONFIG.knownBroken or { ["hazennstuff:pendant_of_harmony"] = "Pendant of Harmony (Hazen N Stuff)" }
do
if fs.exists(CURIOS_FILE) then
local h = fs.open(CURIOS_FILE, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if type(t) == "table" and type(t.rows) == "table" then state.curiosLast = t end
end
end

local function rememberCurios(rows)
local keep = {}
for _, r in ipairs(rows) do
local cells = {}
for pos, it in pairs(r.cells) do
cells[pos] = { name = it.name, displayName = it.displayName, count = it.count }
end
keep[#keep + 1] = { name = r.name, count = r.count, cells = cells }
end
local okS, text = pcall(textutils.serialize, keep)
if not okS then return end
if state.curiosLast and state.curiosLast.text == text then
state.curiosLast.t = os.epoch("utc")
return
end
state.curiosLast = { t = os.epoch("utc"), rows = keep, text = text }
local okF, all = pcall(textutils.serialize, { t = state.curiosLast.t, rows = keep })
if okF then saveFileSafe(CURIOS_FILE, all) end
end


function fetchCurios()
if not (inv.listCurios and inv.getCuriosSizes) then
return nil, "Curios functions not available on this Inventory Manager"
end
local okL, list, okS, sizes
parallel.waitForAll(
function() okL, list = pcall(inv.listCurios) end,
function() okS, sizes = pcall(inv.getCuriosSizes) end)
if not okL and isDistError(list) then

if okS and type(sizes) == "table" then

local last = {}
for _, r in ipairs((state.curiosLast and state.curiosLast.rows) or {}) do last[r.name] = r end
local names = {}
for n in pairs(sizes) do names[#names + 1] = n end
table.sort(names)
local rows = {}
for _, n in ipairs(names) do
local c = tonumber(sizes[n]) or 0
if c > 0 then
local lr = last[n]
local cells = {}
if lr then for pos, it in pairs(lr.cells or {}) do if tonumber(pos) and tonumber(pos) <= c then cells[tonumber(pos)] = it end end end
rows[#rows + 1] = { name = n, count = c, cells = cells, raw = {}, unreadable = not lr, stale = lr ~= nil }
end
end
local suspects = {}
for _, label in pairs(KNOWN_BROKEN) do suspects[#suspects + 1] = label end
table.sort(suspects)
local why = "a worn item cannot be read by the server" ..
(#suspects > 0 and (" (known: " .. table.concat(suspects, ", ") .. ")") or "") ..
" - take it off for a live view"
if state.curiosLast then
local mins = math.floor((os.epoch("utc") - (state.curiosLast.t or 0)) / 60000)
local ago = mins < 1 and "just now" or (mins < 120 and (mins .. " min ago") or (math.floor(mins / 60) .. " h ago"))
return rows, nil, "LAST KNOWN STATE (" .. ago .. "): " .. why
end
return rows, nil, "ITEMS UNREADABLE: " .. why
end
return nil, "invalid dist (client class loaded on the server)"
end
if not okL or type(list) ~= "table" then
return nil, tostring(okL and "listCurios returned nothing" or list)
end
if not okS or type(sizes) ~= "table" then sizes = {} end

local names, seen = {}, {}
for n in pairs(sizes) do if not seen[n] then seen[n] = true; names[#names + 1] = n end end
for n in pairs(list) do if not seen[n] then seen[n] = true; names[#names + 1] = n end end
table.sort(names)

local rows = {}
for _, n in ipairs(names) do
local items = type(list[n]) == "table" and list[n] or {}
local base = 1
for k in pairs(items) do if tonumber(k) == 0 then base = 0 end end

local cells, raw, maxPos = {}, {}, 0
for k, it in pairs(items) do
if type(it) == "table" and it.name and tonumber(k) then
it.displayName = cleanName(it.displayName or prettify(it.name))
local pos = tonumber(k) - base + 1
cells[pos], raw[pos] = it, k
if pos > maxPos then maxPos = pos end
end
end
local count = math.max(tonumber(sizes[n]) or 0, maxPos)
if count > 0 then
rows[#rows + 1] = { name = n, count = count, cells = cells, raw = raw, base = base }
end
end
pcall(rememberCurios, rows)
return rows, nil, nil
end

notStorage = {}


function inspectWrapped(w, it, where)
if type(w) ~= "table" then return nil end


local okV, valid, okI, isItem, okF, isFluid
parallel.waitForAll(
function()
if w.isValid then okV, valid = pcall(w.isValid) else okV, valid = true, true end
end,
function() if w.isItemStorage then okI, isItem = pcall(w.isItemStorage) end end,
function() if w.isFluidStorage then okF, isFluid = pcall(w.isFluidStorage) end end)
if not okV or not valid then return nil end
isItem = okI and isItem and true or false
isFluid = okF and isFluid and true or false
if not isItem and not isFluid then return nil end

local info = { name = it.name, display = it.displayName, where = where,
size = 0, used = 0, contents = {}, tanks = {},
isItem = isItem, isFluid = isFluid }


local okS, size, okL, l, okT, tk
parallel.waitForAll(
function() if isItem and w.size then okS, size = pcall(w.size) end end,
function() if isItem and w.list then okL, l = pcall(w.list) end end,
function() if isFluid and w.tanks then okT, tk = pcall(w.tanks) end end)

if okS and type(size) == "number" then info.size = size end

if isItem and w.list then
if not okL then
info.err = isDistError(l) and "Server error: a modded item in here cannot be read"
or tostring(l)
elseif type(l) == "table" then
local by = {}
for _, e in pairs(l) do
if type(e) == "table" and e.name then
info.used = info.used + 1
local t = by[e.name]
if not t then
t = { name = e.name, count = 0,
display = cleanName(e.displayName or prettify(e.name)) }
by[e.name] = t
info.contents[#info.contents + 1] = t
end
t.count = t.count + (e.count or 1)
end
end
table.sort(info.contents, function(a, b)
if a.count ~= b.count then return a.count > b.count end
return a.display < b.display
end)
end
end

if okT and type(tk) == "table" then
for _, f in pairs(tk) do
if type(f) == "table" and f.name and (tonumber(f.amount) or 0) > 0 then
info.tanks[#info.tanks + 1] = { name = f.name, display = prettify(f.name),
amount = tonumber(f.amount) or 0, capacity = tonumber(f.capacity) }
end
end
end
return info
end


function refreshStorage()
if not inv.wrapStorageItem then
state.storage = {}
state.storageMsg = "wrapStorageItem() is not available on this Inventory Manager"
state.t.storage = os.clock()
return
end
local items, base = state.rawItems, state.base
if not items then return end
local now = os.clock()

local keys = {}
for key in pairs(items) do keys[#keys + 1] = key end
table.sort(keys)

local cands = {}
for _, key in ipairs(keys) do
local it = items[key]
if type(it) == "table" and it.name then
local raw = it.slot or key
local idx = raw - base
if idx >= 0 and idx <= 35
and not (notStorage[it.name] and now < notStorage[it.name]) then
cands[#cands + 1] = { raw = raw, idx = idx, it = it }
end
end
end


local res = pmap(cands, function(c)
local ok, w = pcall(inv.wrapStorageItem, c.raw)
if not ok then return nil end
local info = inspectWrapped(w, c.it, "Slot " .. (c.idx + 1))
if info then info.ref = { kind = "slot", raw = c.raw } end
return info
end)

local list = {}
for i, c in ipairs(cands) do
if res[i] then list[#list + 1] = res[i]
else notStorage[c.it.name] = now + 300 end
end


if inv.wrapCuriosStorageItem then
local rows = fetchCurios()
local ccands = {}
for _, row in ipairs(rows or {}) do
for pos, it in pairs(row.cells) do
if not (notStorage[it.name] and now < notStorage[it.name]) then
ccands[#ccands + 1] = { row = row, pos = pos, it = it }
end
end
end
local cres = pmap(ccands, function(c)
local ok, w = pcall(inv.wrapCuriosStorageItem, c.row.name, c.row.raw[c.pos])
if not ok then return nil end
local info = inspectWrapped(w, c.it, "Curios: " .. prettify(c.row.name))
if info then info.ref = { kind = "curios", slot = c.row.name, idx = c.row.raw[c.pos] } end
return info
end)
for i, c in ipairs(ccands) do
if cres[i] then list[#list + 1] = cres[i]
else notStorage[c.it.name] = now + 300 end
end
end

state.storage, state.storageMsg = list, nil
state.t.storage = os.clock()
end

