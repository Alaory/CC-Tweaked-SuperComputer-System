






















MAP = {
ch = {},
order = {},
ov = {},
names = {},
nameIdx = {},
scans = 0,
ovN = 0,
tick = 0,
version = 0,
dirty = {},
where = {},
savedAt = -1000,
}
local REGION = 4
local OVR = 32
local DIR = "map"
local SAVE_EVERY = 60
local floor, char = math.floor, string.char

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, #B64 do DEC[B64:sub(i, i)] = i - 1 end
local function c1(v) return B64:sub(v + 1, v + 1) end

local function enc2(v)
v = math.max(0, math.min(4095, floor(v)))
return c1(floor(v / 64)) .. c1(v % 64)
end

local function dec2(s, p)
local a, b = DEC[s:sub(p, p)], DEC[s:sub(p + 1, p + 1)]
if not a or not b then return nil end
return a * 64 + b
end




local function cell(h, b, partial)
local v = math.max(0, math.min(32767, floor(h) + 64))
if partial then v = v + 32768 end
return char(floor(v / 256), v % 256, floor(b / 256), b % 256)
end
local EMPTY = "\0\0\0\0"

local function cellAt(L, i)
local e = L.e and L.e[i]
local a, b, c, d
if e then a, b, c, d = e:byte(1, 4) else a, b, c, d = L.d:byte(i * 4 + 1, i * 4 + 4) end
if not d or (c == 0 and d == 0) then return nil end
local v = a * 256 + b
local partial = v >= 32768
if partial then v = v - 32768 end
return v - 64, c * 256 + d, partial
end

local function pack(L, n)
if not L.e then return end
local parts, d = {}, L.d
for i = 0, n - 1 do parts[i + 1] = L.e[i] or d:sub(i * 4 + 1, i * 4 + 4) end
L.d, L.e = table.concat(parts), nil
end


function MAP.pal(name)
local i = MAP.nameIdx[name]
if not i then
i = #MAP.names + 1
MAP.names[i], MAP.nameIdx[name] = name, i
end
return i
end


local function ckey(cx, cz) return (cx + 2097152) * 4194304 + (cz + 2097152) end

local function rkey(cx, cz) return floor(cx / REGION) .. "_" .. floor(cz / REGION) end


local OKEYS = {}
local function okey(cx, cz)
local ox, oz = floor(cx / OVR), floor(cz / OVR)
local nk = (ox + 65536) * 131072 + (oz + 65536)
local k = OKEYS[nk]
if not k then
k = "o" .. ox .. "_" .. oz
OKEYS[nk] = k
end
return k
end


local function chunkAt(cx, cz, make)
local k = ckey(cx, cz)
local c = MAP.ch[k]
if c or not make then return c end
c = { cx = cx, cz = cz, k = k, r = rkey(cx, cz), s = MAP.tick, d = EMPTY:rep(256) }
MAP.ch[k] = c
MAP.order[#MAP.order + 1] = k
return c
end


local function ovAt(cx, cz, make)
local r = okey(cx, cz)
local o = MAP.ov[r]
if o or not make then return o end
o = { ox = floor(cx / OVR), oz = floor(cz / OVR), r = r, d = EMPTY:rep(OVR * OVR) }
MAP.ov[r] = o
return o
end


function MAP.get(x, z)
local c = MAP.ch[ckey(floor(x / 16), floor(z / 16))]
if not c then return nil end
return cellAt(c, (z % 16) * 16 + (x % 16))
end



function MAP.scanned(x, z)
local h, _, partial = MAP.getOverview(x, z)
return h ~= nil and not partial
end

function MAP.getOverview(x, z)
local cx, cz = floor(x / 16), floor(z / 16)
local o = MAP.ov[okey(cx, cz)]
if not o then return nil end
return cellAt(o, (cz % OVR) * OVR + (cx % OVR))
end


function MAP.set(x, z, h, b)
MAP.version = MAP.version + 1
local c = chunkAt(floor(x / 16), floor(z / 16), true)
c.e = c.e or {}
c.e[(z % 16) * 16 + (x % 16)] = cell(math.max(-64, h), math.min(65535, b))
MAP.dirty[c.r] = true
if MAP.touched then MAP.touched[c.k] = true end
end




local function summarize(c)
local count, sum, n, best, bestN = {}, 0, 0, nil, 0
for i = 0, 255 do
local h, b = cellAt(c, i)
if h then
sum, n = sum + h, n + 1
local k = (count[b] or 0) + 1
count[b] = k
if k > bestN then best, bestN = b, k end
end
end
if n == 0 then return end
local o = ovAt(c.cx, c.cz, true)
local i = (c.cz % OVR) * OVR + (c.cx % OVR)
local had, _, wasPartial = cellAt(o, i)
if had and n < 128 and not wasPartial then return end
if not had then MAP.ovN = MAP.ovN + 1 end
o.e = o.e or {}


o.e[i] = cell(floor(sum / n + 0.5), best, n < 128)
MAP.dirty[o.r] = true
end



local function refreshOrder(touched)
local keep, moved = {}, {}
for _, k in ipairs(MAP.order) do
if touched[k] then moved[#moved + 1] = k else keep[#keep + 1] = k end
end
for _, k in ipairs(moved) do
keep[#keep + 1] = k
MAP.ch[k].s = MAP.tick
MAP.dirty[MAP.ch[k].r] = true
end
MAP.order = keep
end


function MAP.hasData() return MAP.scans > 0 or #MAP.order > 0 or next(MAP.ov) ~= nil end


local function countOverview()
local n = 0
for _, o in pairs(MAP.ov) do
for i = 0, OVR * OVR - 1 do if cellAt(o, i) then n = n + 1 end end
end
MAP.ovN = n
end



function MAP.trim(max)
max = max or CONFIG.map.maxChunks or 300
if #MAP.order <= max then return 0 end
MAP.version = MAP.version + 1
local n = 0
while #MAP.order > max do
local c = MAP.ch[table.remove(MAP.order, 1)]
if c then
MAP.ch[c.k] = nil
MAP.dirty[c.r] = true
n = n + 1
end
end
return n
end






local function dirOf(p) return tostring(p):match("^(.*)/[^/]*$") or "" end
local function mExists(p) if STORE and STORE.isRemote(p) then return true end return fs.exists(p) end
local function mDelete(p)
if STORE and STORE.isRemote(p) then pcall(STORE.delete, p) else pcall(fs.delete, p) end
end
MAP.rsize = {}

local function places()
local out = {}
for _, d in ipairs(mountedDisks()) do
if d.data then out[#out + 1] = { dir = fs.combine(d.mount, DIR), free = d.free, floppy = true } end
end
local okF, free = pcall(fs.getFreeSpace, "/")
free = okF and free or 0
local onPc = 0
for _, p in pairs(MAP.where) do
if dirOf(p) == DIR and fs.exists(p) then onPc = onPc + fs.getSize(p) end
end
local cap = (tonumber(CONFIG.map.computerKB) or 200) * 1024 - onPc

local keep = (tonumber(CONFIG.map.keepFreeKB) or 96) * 1024
out[#out + 1] = { dir = DIR, free = math.max(0, math.min(free - keep, cap)), floppy = false }

for id, h in pairs(STORE and STORE.helpers or {}) do
if not h.refused then out[#out + 1] = { dir = "store:" .. id .. "/" .. DIR, free = h.free or 0, remote = id } end
end
return out
end





local function cellsText(L, n, loc)
local out, prev, run, ph = {}, nil, 0, 64
for i = 0, n - 1 do
local h, b, partial = cellAt(L, i)
local tok = "~"
if h then
b = loc(b)
local dh = h - ph
ph = h
tok = (partial and "!" or "") ..
((dh >= -31 and dh <= 31) and c1(dh + 32) or ("A" .. enc2(h + 64))) ..
((b < 63) and c1(b) or ("/" .. enc2(b)))
end
if tok == prev and run < 63 then
run = run + 1
else
if run > 0 then out[#out + 1] = "*" .. c1(run) end
out[#out + 1], prev, run = tok, tok, 0
end
end
if run > 0 then out[#out + 1] = "*" .. c1(run) end
return table.concat(out)
end


local function readCells(s, n, glob)
local out, p, i, ph, len = {}, 1, 0, 64, #s
local last, lastDh, lastAbs, lastB, lastP, nextP = EMPTY, 0, false, 0, false, false
while p <= len and i < n do
local ch = s:sub(p, p)
if ch == "!" then
nextP, p = true, p + 1
elseif ch == "*" then
for _ = 1, DEC[s:sub(p + 1, p + 1)] or 0 do
if i >= n then break end
if last ~= EMPTY and not lastAbs then
ph = ph + lastDh
last = cell(ph, lastB, lastP)
end
out[i + 1], i = last, i + 1
end
p = p + 2
elseif ch == "~" then
out[i + 1], i, p, last = EMPTY, i + 1, p + 1, EMPTY
else
if ch == "A" then
ph, lastAbs = (dec2(s, p + 1) or 64) - 64, true
p = p + 3
else
lastDh, lastAbs = (DEC[ch] or 32) - 32, false
ph, p = ph + lastDh, p + 1
end
local bch, b = s:sub(p, p), nil
if bch == "/" then b, p = glob[dec2(s, p + 1) or 0], p + 3
else b, p = glob[DEC[bch] or 0], p + 1 end
lastB = b or MAP.pal("unknown")
lastP, nextP = nextP, false
last = cell(ph, lastB, lastP)
out[i + 1], i = last, i + 1
end
end
for j = i + 1, n do out[j] = EMPTY end
return table.concat(out)
end


local function fileText(key)
local locOf, names = {}, {}
local function loc(g)
local l = locOf[g]
if not l then
l = #names
names[l + 1] = MAP.names[g] or "unknown"
locOf[g] = l
end
return l
end
local body = {}
if key:sub(1, 1) == "o" then
local o = MAP.ov[key]
if not o then return nil end
pack(o, OVR * OVR)
body[1] = "V " .. o.ox .. " " .. o.oz .. " " .. cellsText(o, OVR * OVR, loc)
else
local list = {}
for _, c in pairs(MAP.ch) do if c.r == key then list[#list + 1] = c end end
if #list == 0 then return nil end
table.sort(list, function(a, b) return a.k < b.k end)
for _, c in ipairs(list) do
pack(c, 256)
body[#body + 1] = "K " .. c.cx .. " " .. c.cz .. " " .. c.s .. " " .. cellsText(c, 256, loc)
end
end
local head = { "M2" }
for _, nm in ipairs(names) do head[#head + 1] = "P " .. nm end
return table.concat(head, "\n") .. "\n" .. table.concat(body, "\n") .. "\n"
end


local function readText(text)
local glob, nloc = {}, 0
for line in tostring(text or ""):gmatch("[^\n]+") do
local tag = line:sub(1, 1)
if tag == "P" then
glob[nloc] = MAP.pal(line:sub(3))
nloc = nloc + 1
elseif tag == "K" then
local cx, cz, s, data = line:match("^K (%-?%d+) (%-?%d+) (%d+) (.*)$")
if data then
local c = chunkAt(tonumber(cx), tonumber(cz), true)
c.s = tonumber(s)
if c.s > MAP.tick then MAP.tick = c.s end
c.d = readCells(data, 256, glob)
end
elseif tag == "V" then
local ox, oz, data = line:match("^V (%-?%d+) (%-?%d+) (.*)$")
if data then
local o = ovAt(tonumber(ox) * OVR, tonumber(oz) * OVR, true)
o.d = readCells(data, OVR * OVR, glob)
end
end
end
end
local function readFile(path)
local h = fs.open(path, "r")
if not h then return end
local t = h.readAll()
h.close()
readText(t)
return t
end


local function loadYield()
if MAP.loading and MAP.canYield and TT and TT.yieldCo == coroutine.running() then
os.queueEvent("map_loading")
os.pullEvent("map_loading")
end
end



local function writeFile(key, text, plc)
local old = MAP.where[key]
local need = #text + 4096
local order = {}
for _, p in ipairs(plc) do order[#order + 1] = p end
local function rank(p) return p.floppy and 3 or (p.remote and 2 or 1) end
table.sort(order, function(a, b)
if rank(a) ~= rank(b) then return rank(a) > rank(b) end
local aOld, bOld = old and dirOf(old) == a.dir, old and dirOf(old) == b.dir
if aOld ~= bOld then return aOld end
return a.free > b.free
end)
for _, p in ipairs(order) do
local path = p.dir .. "/" .. key .. ".dat"
if p.free >= need then
local ok
if p.remote then
ok = STORE.write(path, text)
if ok then MAP.rsize[key] = #text end
else
pcall(fs.makeDir, p.dir)
ok = saveFileSafe(path, text)
end
if ok then
if old and old ~= path and mExists(old) then mDelete(old) end
if not p.remote then MAP.rsize[key] = nil end
MAP.where[key] = path
p.free = p.free - #text
return true
end
end
end
return false
end





function MAP.save(toDisks, noTrim)
if not MAP.loaded then return false end
if toDisks then
for k, p in pairs(MAP.where) do if dirOf(p) == DIR then MAP.dirty[k] = true end end
end
if not next(MAP.dirty) then return true end
local dropped = 0
for tries = 0, 4 do
local keys, texts = {}, {}
for k in pairs(MAP.dirty) do
local t = fileText(k)
if t then
keys[#keys + 1], texts[k] = k, t
else
if MAP.where[k] and mExists(MAP.where[k]) then mDelete(MAP.where[k]) end
MAP.where[k], MAP.dirty[k] = nil, nil
end
end

table.sort(keys, function(a, b)
local ao, bo = a:sub(1, 1) == "o", b:sub(1, 1) == "o"
if ao ~= bo then return ao end
return a < b
end)
local plc = places()
local failed, ovFailed = false, false
for _, k in ipairs(keys) do
if writeFile(k, texts[k], plc) then MAP.dirty[k] = nil
else
failed = true
if k:sub(1, 1) == "o" then ovFailed = true end
end
end
if not failed then break end
if noTrim then return false end


if MAP.claimEmptyFloppies() > 0 then
setToast("A new floppy disk is now used for the map", C.good)
elseif ovFailed or tries == 4 or #MAP.order <= 20 then
state.diskLow = "Map not fully saved - the data floppies are full. Add a Disk Drive with an EMPTY floppy."
break
else
dropped = dropped + MAP.trim(floor(#MAP.order * 0.75))
end
end
MAP.lastDrop = dropped
if dropped > 0 then
setToast("Map: the disks are full - dropped the detail of the " .. dropped ..
" oldest chunks (the overview keeps them)", C.label, 10)
end
MAP.savedAt = os.clock()
return not next(MAP.dirty)
end






function MAP.offload()
if not MAP.loaded then return 0 end
local before = 0
for _, p in pairs(MAP.where) do if dirOf(p) == DIR then before = before + 1 end end
if before == 0 then return 0 end
local room = 0
for _, pl in ipairs(places()) do if pl.floppy or pl.remote then room = room + (pl.free or 0) end end
if room < 8192 then return 0 end
pcall(MAP.save, true, true)
local after = 0
for _, p in pairs(MAP.where) do if dirOf(p) == DIR then after = after + 1 end end
local moved = before - after
if moved > 0 and sysLog then
sysLog("Map: moved " .. moved .. " map file(s) off this computer onto the floppies / storage helpers" ..
(after > 0 and (" (" .. after .. " still here - no room left)") or ""), "INFO")
end
return moved
end


function MAP.autoSave()
if next(MAP.dirty) and os.clock() - MAP.savedAt >= SAVE_EVERY then
pcall(MAP.save)
pcall(MAP.checkSpace)
end
end



local LOW_KB = 40
local lastWarn = -100000



function MAP.claimEmptyFloppies()
local disks = mountedDisks()
local hasInstaller = false
for _, d in ipairs(disks) do if d.installer then hasInstaller = true end end
local n = 0
local installDrive = TT and TT.installDrive and TT.installDrive()
if installDrive then hasInstaller = true end
for _, d in ipairs(disks) do
if d.empty and not d.installer and not d.data and d.name ~= installDrive then
if not hasInstaller then
hasInstaller = true
else
local h = fs.open(fs.combine(d.mount, "base_data"), "w")
if h then h.write("data floppy of the base") h.close() end
pcall(disk.setLabel, d.name, "Base data")
n = n + 1
end
end
end
return n
end


function MAP.floppySpace()
local free, count = 0, 0
for _, d in ipairs(mountedDisks()) do
if d.data then free, count = free + (d.free or 0), count + 1 end
end

if STORE then
local hf, hn = STORE.space()
free, count = free + hf, count + hn
end
return free, count
end


function MAP.checkSpace()
local free, count = MAP.floppySpace()
if free < LOW_KB * 1024 then
local got = MAP.claimEmptyFloppies()
if got > 0 then
setToast(got .. " new floppy disk(s) are now used for the map", C.good)
if sysLog then sysLog(got .. " new floppy disk(s) are now used for the map", "DONE") end
free, count = MAP.floppySpace()
end
end
local failed = next(MAP.dirty) ~= nil
local dropping = (MAP.lastDrop or 0) > 0

MAP.full = failed or (dropping and free < LOW_KB * 1024)
if free >= LOW_KB * 1024 and not failed and not dropping then
if state.diskLow and state.diskLow:find("floppies", 1, true) then state.diskLow = nil end
return
end
local msg = failed and "Map not fully saved - the data floppies are full. Add a Disk Drive with an EMPTY floppy."
or dropping and ("Map floppies full - the oldest map detail is being dropped (the overview stays). " ..
"Add a Disk Drive with an EMPTY floppy.")
or string.format("Map floppies almost full (%d KB free on %d). Add a Disk Drive with an EMPTY floppy.",
math.floor(free / 1024), count)
state.diskLow = msg
if os.clock() - lastWarn >= 1800 or failed and os.clock() - lastWarn >= 300 then
lastWarn = os.clock()
setPopup("MAP FLOPPIES", msg, failed and C.bad or C.warn)
if sysLog then sysLog(msg, failed and "ERROR" or "WARNING") end
if state.owner then chatTell(state.owner, msg) end
end
end


function MAP.diskUse()
local total, onPc, files = 0, 0, 0
for k, p in pairs(MAP.where) do
if STORE and STORE.isRemote(p) then
total, files = total + (MAP.rsize[k] or 0), files + 1
elseif fs.exists(p) then
local s = fs.getSize(p)
total, files = total + s, files + 1
if dirOf(p) == DIR then onPc = onPc + s end
end
end
return total, onPc, files
end


function MAP.clear()
if not MAP.loaded then return false end
MAP.version = MAP.version + 1
for _, p in pairs(MAP.where) do if mExists(p) then mDelete(p) end end
MAP.ch, MAP.order, MAP.ov, MAP.where, MAP.dirty = {}, {}, {}, {}, {}
MAP.names, MAP.nameIdx = {}, {}
MAP.scans, MAP.tick, MAP.ovN = 0, 0, 0
for _, p in ipairs({ CONFIG.map.file, dataFile(CONFIG.map.file, true) }) do
if fs.exists(p) then pcall(fs.delete, p) end
end
return true
end


local function loadOld(f)
local h = fs.open(f, "r")
if not h then return false end
local idx = {}
while true do
local line = h.readLine()
if not line then break end
local tag = line:sub(1, 1)
if tag == "P" then
idx[#idx + 1] = MAP.pal(line:sub(3))
elseif tag == "K" then
local cx, cz, data = line:match("^K (%-?%d+) (%-?%d+) (.*)$")
cx, cz = tonumber(cx), tonumber(cz)
if cx and data and #data >= 1024 then
MAP.tick = MAP.tick + 1
local c = chunkAt(cx, cz, true)
c.s = MAP.tick
local parts = {}
for i = 1, 256 do
local p = (i - 1) * 4 + 1
local hh, bb = dec2(data, p), dec2(data, p + 2)
parts[i] = (data:sub(p, p) ~= "~" and hh and bb)
and cell(hh - 64, idx[bb] or MAP.pal("unknown")) or EMPTY
end
c.d = table.concat(parts)
MAP.dirty[c.r] = true
end
end
end
h.close()
return true
end



function MAP.load()

if STORE and next(STORE.known) then pcall(STORE.find, true) end
for _, p in ipairs(places()) do
if p.remote then

local okL, list = pcall(STORE.list, p.remote, DIR)
local want = {}
for f, size in pairs(okL and list or {}) do
local k = f:match("^(o?%-?%d+_%-?%d+)%.dat$")
if k and not MAP.where[k] then
want[#want + 1] = f
MAP.where[k] = p.dir .. "/" .. f
MAP.rsize[k] = size
end
end
local i = 1
while i <= #want do
local batch = {}
for j = i, math.min(#want, i + 19) do batch[#batch + 1] = DIR .. "/" .. want[j] end
local okR, files = pcall(STORE.readMany, p.remote, batch)
local got = 0
for name, text in pairs(okR and files or {}) do pcall(readText, text) got = got + 1 end
loadYield()
if got == 0 then break end
i = i + got
end
elseif fs.exists(p.dir) and fs.isDir(p.dir) then
for _, f in ipairs(fs.list(p.dir)) do
local k = f:match("^(o?%-?%d+_%-?%d+)%.dat$")
if k and not MAP.where[k] then
MAP.where[k] = fs.combine(p.dir, f)
local okR, t = pcall(readFile, MAP.where[k])

if okR and type(t) == "string" and k:sub(1, 1) ~= "o" and t:find("\nO ", 1, true) then MAP.dirty[k] = true end
loadYield()
end
end
end
end
local oldFiles = {}
for _, f in ipairs({ CONFIG.map.file, dataFile(CONFIG.map.file) }) do
if fs.exists(f) then oldFiles[f] = true end
end
if next(oldFiles) and not next(MAP.ch) then
for f in pairs(oldFiles) do pcall(loadOld, f) break end
end

countOverview()


for _, c in pairs(MAP.ch) do
local h, _, partial = MAP.getOverview(c.cx * 16, c.cz * 16)
if not h or not partial then summarize(c) end
end
for _, o in pairs(MAP.ov) do pack(o, OVR * OVR) end
table.sort(MAP.order, function(a, b) return MAP.ch[a].s < MAP.ch[b].s end)
MAP.trim()
if next(oldFiles) then


MAP.loaded = true
local ok = MAP.save(false, true)
for f in pairs(oldFiles) do pcall(fs.delete, f) end
if not ok then MAP.save() end
end
MAP.version = MAP.version + 1
end



MAP.loaded = false
MAP.pendingScans = {}
function MAP.loadNow()
if MAP.loaded then return end
MAP.loading = true
local ok, err = pcall(MAP.load)
MAP.loading = false
MAP.loaded = true
if not ok and setToast then setToast("Map loading error: " .. tostring(err), C.bad) end
local list = MAP.pendingScans
MAP.pendingScans = {}
for _, m in ipairs(list) do pcall(MAP.addScan, m) end
MAP.version = MAP.version + 1
os.queueEvent("inv_update")
end



function MAP.addScan(m)
if type(m.cols) ~= "table" or type(m.names) ~= "table" then return end
if not MAP.loaded then

if #MAP.pendingScans < 300 then MAP.pendingScans[#MAP.pendingScans + 1] = m end
return
end
local x0, y0, z0 = tonumber(m.x), tonumber(m.y), tonumber(m.z)
if not (x0 and y0 and z0) then return end
local r = floor(tonumber(m.r) or 8)
local n = 2 * r + 1
local remap = {}
for i, nm in ipairs(m.names) do remap[i] = MAP.pal(tostring(nm)) end
MAP.tick = MAP.tick + 1
MAP.touched = {}



local top = y0 + r
for idx, v in pairs(m.cols) do
if type(idx) == "number" and type(v) == "table" and tonumber(v[1]) then
local i = idx - 1
local x, z = x0 + (i % n - r), z0 + (floor(i / n) - r)
local h, b = y0 + v[1], remap[v[2]] or MAP.pal("unknown")
local oldH = MAP.get(x, z)
if not oldH or h >= oldH or oldH <= top then
MAP.set(x, z, h, b)
end
end
end
MAP.scans = MAP.scans + 1
MAP.lastScan = os.clock()
local touched = MAP.touched
MAP.touched = nil

for k in pairs(touched) do
local c = MAP.ch[k]
pack(c, 256)
summarize(c)
end
for _, o in pairs(MAP.ov) do pack(o, OVR * OVR) end

for dx = -r, r, 8 do
for dz = -r, r, 8 do
local k = ckey(floor((x0 + dx) / 16), floor((z0 + dz) / 16))
if MAP.ch[k] then touched[k] = true end
end
end
refreshOrder(touched)
MAP.trim()
MAP.version = MAP.version + 1
end


local colorCache = {}

function MAP.colorOf(name)
local c = colorCache[name]
if c then return c end
c = MAP.colorOfRaw(name)
colorCache[name] = c
return c
end

function MAP.colorOfRaw(name)
local n = tostring(name):lower()
if n:find("lava") or n:find("magma") then return colors.red end
if n:find("water") or n:find("kelp") or n:find("seagrass") or n:find("bubble") then return colors.blue end
if n:find("ice") or n:find("snow") then return colors.white end
if n:find("leaves") or n:find("vine") or n:find("bush") or n:find("azalea") or n:find("cactus")
or n:find("bamboo") or n:find("sugar_cane") or n:find("lily") then return colors.lime end
if n:find("grass") or n:find("moss") or n:find("fern") or n:find("flower") or n:find("tulip")
or n:find("dandelion") or n:find("poppy") or n:find("mycelium") then return colors.green end
if n:find("sand") or n:find("gravel") then return colors.yellow end
if n:find("dirt") or n:find("mud") or n:find("podzol") or n:find("farmland") or n:find("path")
or n:find("terracotta") or n:find("clay") or n:find("log") or n:find("wood")
or n:find("plank") then return colors.orange end
if n:find("netherrack") or n:find("crimson") or n:find("nether_wart") then return colors.red end
if n:find("warped") or n:find("prismarine") then return colors.cyan end
if n:find("_ore") or n:find("debris") then return colors.pink end
if n:find("obsidian") or n:find("purpur") or n:find("amethyst") then return colors.purple end
return colors.brown
end


local UPS = { north = 0, east = 1, south = 2, west = 3 }
local VIEW_FILE = "map_view.dat"


function MAP.view()
if not state.mapView then
local h = CONFIG.drone and CONFIG.drone.home
local rot = UPS[tostring(CONFIG.map.up or "north"):lower()] or 0
local cx, cz, zoom = h and h.x or 0, h and h.z or 0, 1
if fs.exists(VIEW_FILE) then
local f = fs.open(VIEW_FILE, "r")
if f then
local t = textutils.unserialize(f.readAll() or "")
f.close()
if type(t) == "table" then
if tonumber(t.rot) then rot = tonumber(t.rot) % 4 end
local z = tonumber(t.zoom)
if z and z >= 1 and z <= 512 then zoom = z end
if tonumber(t.cx) and tonumber(t.cz) and math.abs(t.cx) <= 30000000 and math.abs(t.cz) <= 30000000 then
cx, cz = math.floor(tonumber(t.cx)), math.floor(tonumber(t.cz))
end
end
end
end
state.mapView = { cx = cx, cz = cz, zoom = zoom, rot = rot }
end
return state.mapView
end



function MAP.saveView()
local V = MAP.view()
saveFileSafe(VIEW_FILE, serialSmall({ rot = V.rot, zoom = V.zoom, cx = V.cx, cz = V.cz }))
end


function MAP.viewArea()
local g, V = state.mapGeom, MAP.view()
if not g then return nil end
local B = MAP.basis()
local hw, hh = g.mw / 2 * V.zoom, g.mh / 2 * V.zoom * 1.5
local hx = math.floor(math.abs(B.rx) * hw + math.abs(B.dx) * hh)
local hz = math.floor(math.abs(B.rz) * hw + math.abs(B.dz) * hh)
return V.cx - hx, V.cz - hz, V.cx + hx, V.cz + hz
end



function MAP.surveySpots(x1, z1, x2, z2, r)
local step = 2 * r + 1
local spots, skipped = {}, 0
local need = CONFIG.map.skipKnown or 0.8
for z = z1 + r, z2 + r, step do
for x = x1 + r, x2 + r, step do
local known, total = 0, 0
for dx = -r, r, 2 do
for dz = -r, r, 2 do
total = total + 1
if MAP.get(x + dx, z + dz) then known = known + 1 end
end
end
if not MAP.inArea(x, z) then

elseif known / total >= need or MAP.scanned(x, z) then skipped = skipped + 1
else spots[#spots + 1] = { x, z } end
end
end
return spots, skipped
end







local QUEUE_FILE = "survey_queue.dat"
local BATCH = 64
MAP.queue = nil



local function saveQueue()
local p = dataFile(QUEUE_FILE, true)
if MAP.queue then
local text = serialSmall(MAP.queue)
local ok = saveFileSafe(p, text)
if not ok and p ~= QUEUE_FILE then ok = saveFileSafe(QUEUE_FILE, text) p = QUEUE_FILE end
if ok and p ~= QUEUE_FILE and fs.exists(QUEUE_FILE) then pcall(fs.delete, QUEUE_FILE) end
else
if fs.exists(p) then pcall(fs.delete, p) end
if fs.exists(QUEUE_FILE) then pcall(fs.delete, QUEUE_FILE) end
end
end
do
local qf = dataFile(QUEUE_FILE)
if not fs.exists(qf) then qf = QUEUE_FILE end
if fs.exists(qf) then
local h = fs.open(qf, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if type(t) == "table" and t.cols then MAP.queue = t end
end
end



function MAP.area()
local a, b = CONFIG.map.areaA, CONFIG.map.areaB
if type(a) == "table" and a.x and a.z and type(b) == "table" and b.x and b.z then
return math.min(a.x, b.x), math.min(a.z, b.z), math.max(a.x, b.x), math.max(a.z, b.z)
end
end
function MAP.areaKey()
local x1, z1, x2, z2 = MAP.area()
return x1 and (x1 .. "," .. z1 .. "," .. x2 .. "," .. z2) or "world"
end
function MAP.inArea(x, z)
local border = tonumber(CONFIG.map.border) or 20000
if math.abs(x) > border or math.abs(z) > border then return false end
local x1, z1, x2, z2 = MAP.area()
return not x1 or (x >= x1 and x <= x2 and z >= z1 and z <= z2)
end


function MAP.queueSurvey(x1, z1, x2, z2, r, ids)

for _, id in ipairs(ids or TT.available()) do
local t = state.turtles[id]
if t and t.held then t.held = nil TT.listDirty = true end
end
local step = 2 * r + 1
local old = MAP.queue
if old and old.auto then MAP.auto.cursor = old.cursor MAP.saveAuto() end

local border = tonumber(CONFIG.map.border) or 20000
x1, z1 = math.max(x1, -border), math.max(z1, -border)
x2, z2 = math.min(x2, border), math.min(z2, border)

local ax1, az1, ax2, az2 = MAP.area()
if ax1 then
x1, z1, x2, z2 = math.max(x1, ax1), math.max(z1, az1), math.min(x2, ax2), math.min(z2, az2)
end
if x2 < x1 or z2 < z1 then return 0 end


local c = CONFIG.drone.home or state.basePos
if not (c and c.x) then
for _, id in ipairs(ids or TT.available()) do
local t = state.turtles[id]
if t and t.pos and t.pos.x then c = t.pos break end
end
end
local cx = (c and c.x) and math.floor(c.x) or math.floor((x1 + x2) / 2)
local cz = (c and c.z) and math.floor(c.z) or math.floor((z1 + z2) / 2)
cx, cz = math.max(x1, math.min(x2, cx)), math.max(z1, math.min(z2, cz))
local rad = math.ceil(math.max(cx - x1, x2 - cx, cz - z1, z2 - cz) / step)
MAP.queue = { x1 = x1, z1 = z1, x2 = x2, z2 = z2, r = r, step = step,
spiral = true, rect = true, cx = cx, cz = cz,
cols = 2 * rad + 1, rows = 2 * rad + 1,
cursor = 0, sent = 0, skipped = 0, ids = ids }
if old then MAP.queue.redo, MAP.queue.out = old.redo, old.out end
saveQueue()
return (math.floor((x2 - x1) / step) + 1) * (math.floor((z2 - z1) / step) + 1)
end





function MAP.spotDone(x, z)
return MAP.get(x, z) ~= nil or MAP.scanned(x, z)
end



local function spiral(n)
if n == 0 then return 0, 0 end
local k = math.ceil((math.sqrt(n + 1) - 1) / 2)
local side = 2 * k
local first = (2 * k - 1) * (2 * k - 1)
local m = n - first
if m < side then return k, -k + 1 + m end
m = m - side
if m < side then return k - 1 - m, k end
m = m - side
if m < side then return -k, k - 1 - m end
m = m - side
return -k + 1 + m, -k
end
MAP.spiral = spiral






local AUTO_FILE = "auto_survey.dat"
MAP.auto = { on = (CONFIG.map.autoSurvey ~= false), cursor = 0 }
do
if fs.exists(AUTO_FILE) then
local h = fs.open(AUTO_FILE, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if type(t) == "table" then MAP.auto = t end
end
end
function MAP.saveAuto() saveFileSafe(AUTO_FILE, serialSmall(MAP.auto)) end
function MAP.setAuto(on)
MAP.auto.on = on and true or false
MAP.auto.done = nil
if not on and MAP.queue and MAP.queue.auto then
MAP.auto.cursor = MAP.queue.cursor
MAP.queue = nil
saveQueue()
end
MAP.saveAuto()
end


function MAP.autoTick()
local a = MAP.auto

if (a.areaKey or "world") ~= MAP.areaKey() and not MAP.queue then
a.done, a.cursor, a.areaKey = nil, 0, MAP.areaKey()
MAP.saveAuto()
end
if not a.on or a.done or MAP.queue or MAP.full or not MAP.loaded then return end
local c = CONFIG.drone.home or state.basePos
if not (c and c.x) or #TT.available() == 0 then return end
local r = CONFIG.map.scanRadius or 8
local step = 2 * r + 1
local border = tonumber(CONFIG.map.border) or 20000
local cx, cz = math.floor(c.x), math.floor(c.z)
local rad = math.ceil((border + math.max(math.abs(c.x), math.abs(c.z))) / step)
local ax1, az1, ax2, az2 = MAP.area()
if ax1 then

cx, cz = math.max(ax1, math.min(ax2, cx)), math.max(az1, math.min(az2, cz))
rad = math.ceil(math.max(cx - ax1, ax2 - cx, cz - az1, az2 - cz) / step) + 1
end
a.areaKey = MAP.areaKey()
MAP.queue = { auto = true, spiral = true, cx = cx, cz = cz, r = r, step = step, areaKey = a.areaKey,
cols = 2 * rad + 1, rows = 2 * rad + 1, cursor = a.cursor or 0, sent = 0, skipped = 0 }
saveQueue()
setToast("Auto-map: surveying on from the base outward (" ..
math.floor(MAP.autoRadius() + 0.5) .. " blocks done around it)", C.label)
end


function MAP.autoRadius()
local q = MAP.queue
local cur = (q and q.auto) and q.cursor or (MAP.auto.cursor or 0)
local step = (q and q.step) or (2 * (CONFIG.map.scanRadius or 8) + 1)
return math.max(0, math.ceil((math.sqrt(cur + 1) - 1) / 2) - 1) * step
end

function MAP.stopSurvey()
if MAP.queue and MAP.queue.auto then

MAP.auto.cursor, MAP.auto.on = MAP.queue.cursor, false
MAP.saveAuto()
end
MAP.queue = nil
saveQueue()
end


local function nextBatch(q, want)
local BATCH = want or BATCH
local total = q.cols * q.rows
local out, checked = {}, 0

local threats, range = {}, 0
if TT and TT.threats then threats, range = TT.threats() end
local why = { near = 0, done = 0, redo = 0 }
local function nearPlayer(x, z)
if #threats == 0 then return false end
local who = TT.nearThreat(x, z, threats, range)
if who then why.near, why.who = why.near + 1, who end
return who ~= nil
end
q.lastWhy = why
q.redo = q.redo or {}

local n0 = #q.redo
for _ = 1, n0 do
if #out >= BATCH then break end
local p = table.remove(q.redo, 1)
if MAP.spotDone(p[1], p[2]) or not MAP.inArea(p[1], p[2]) then

elseif nearPlayer(p[1], p[2]) then q.redo[#q.redo + 1] = p
else out[#out + 1] = p end
end
if #out >= BATCH then return out end
local outside = 0
while #out < BATCH and q.cursor < total and checked < 3000 and outside < 40000 do
local i = q.cursor
q.cursor = q.cursor + 1
checked = checked + 1
local x, z
if q.spiral then

local dx, dz = spiral(i)
x, z = q.cx + dx * q.step, q.cz + dz * q.step


if q.rect and (x < q.x1 or x > q.x2 or z < q.z1 or z > q.z2) then
checked, outside, x = checked - 1, outside + 1, nil
end
else

local row, col = math.floor(i / q.cols), i % q.cols
if row % 2 == 1 then col = q.cols - 1 - col end
x, z = q.x1 + q.r + col * q.step, q.z1 + q.r + row * q.step
end
if x and not MAP.inArea(x, z) then
checked, outside, x = checked - 1, outside + 1, nil
end
if not x then

elseif MAP.spotDone(x, z) then q.skipped = q.skipped + 1 why.done = why.done + 1
elseif nearPlayer(x, z) then q.redo[#q.redo + 1] = { x, z }
else out[#out + 1] = { x, z } end
end
why.redo = #q.redo
return out
end





function MAP.reclaim(id)
local q = MAP.queue
if not (q and q.out and q.out[id]) then return 0 end
local n = 0
q.redo = q.redo or {}
for _, p in ipairs(q.out[id]) do
if not MAP.spotDone(p[1], p[2]) then q.redo[#q.redo + 1] = p n = n + 1 end
end
q.out[id] = nil
saveQueue()
return n
end



function MAP.batchResult(id, ok)
local q = MAP.queue
if not (q and q.out and q.out[id]) then return end

local t = state.turtles[id]
if ok and t and t.queueAt and os.clock() - t.queueAt > 1 then
local r = #q.out[id] / (os.clock() - t.queueAt)
t.packRate = t.packRate and (t.packRate * 0.5 + r * 0.5) or r
end
local n = MAP.reclaim(id)
if n > 0 then
local t = state.turtles[id]
TT.log(t, n .. " survey spot(s) not done - back in the queue for the next free turtle")
end
end




function MAP.addSurvey(x1, z1, x2, z2, r)
local spots, skipped = MAP.surveySpots(x1, z1, x2, z2, r)
if #spots == 0 then return 0, skipped end
local q = MAP.queue
if not q then
MAP.queueSurvey(x1, z1, x2, z2, r, nil)
return #spots, skipped
end
q.redo = q.redo or {}
for i = #spots, 1, -1 do table.insert(q.redo, 1, spots[i]) end
for _, id in ipairs(TT.available()) do
local t = state.turtles[id]
if t and t.held then t.held = nil TT.listDirty = true end
end
saveQueue()
return #spots, skipped
end


function MAP.feedSurvey()
local q = MAP.queue
if not q or not MAP.loaded then return end


if not q.spiral and not q.auto and q.x1 then
local oldOut, sent, skipped, ids, excl = q.out, q.sent, q.skipped, q.ids, q.excluded
local held = {}
for id, t in pairs(state.turtles) do held[id] = t.held end
MAP.queue = nil
MAP.queueSurvey(q.x1, q.z1, q.x2, q.z2, q.r, ids)
for id, t in pairs(state.turtles) do t.held = held[id] end
q = MAP.queue



q.sent, q.skipped, q.excluded = sent or 0, skipped or 0, excl
for id in pairs(oldOut or {}) do
local t = state.turtles[id]
if t then
t.recall = true
TT.listDirty = true
TT.log(t, "Its survey batch was far away (old survey order) - called back home")
end
end
q.changed = true
end
if q.auto and (q.areaKey or "world") ~= MAP.areaKey() then

MAP.auto.cursor, MAP.auto.done = 0, nil
MAP.saveAuto()
MAP.queue = nil
saveQueue()
return
end
if q.auto and MAP.full then return end
local total = q.cols * q.rows
local minFuel = tonumber(CONFIG.map.surveyMinFuel) or 500
local busy, why, anyFree = false, {}, false
local list = q.ids or TT.available()


local pack = CONFIG.map.pack ~= false
local packFree = {}
for _, id in ipairs(list) do
local t = state.turtles[id]
local free = t and TT.online(t) and t.pos and t.pos.x and (t.task == nil or t.task == "idle") and not t.anchor
and not (q.excluded and q.excluded[id])
and not t.rescuerRole and not t.held
and not TT.factoryRole(t)
local fuel = t and tonumber(t.fuel)
if t then t.packWait = nil end
if free and t.queueAt and os.clock() - t.queueAt < 15 then free = false busy = true end
if free and fuel and fuel < minFuel then free = false end



if free and q.out and q.out[id] then free = false busy = true end
if t and not free and t.task and t.task ~= "idle" then busy = true end

if t and not free then
local w
if not TT.online(t) then w = "offline"
elseif not (t.pos and t.pos.x) then w = "position unknown"
elseif t.task and t.task ~= "idle" then w = "busy"
elseif t.held or (q.excluded and q.excluded[id]) then w = "STOPPED - give it a command first"
elseif fuel and fuel < minFuel then w = "fuel " .. fuel .. " (needs " .. minFuel .. ")"
elseif t.anchor then w = "anchor" elseif t.rescuerRole then w = "rescuer"
elseif TT.factoryRole(t) then w = "factory " .. TT.factoryRole(t) end
if w then why[#why + 1] = (t.label or ("#" .. id)) .. ": " .. w end
end
if free then anyFree = true end


if t and q.out and q.out[id] and TT.online(t) and (t.task == nil or t.task == "idle")
and (not t.queueAt or os.clock() - t.queueAt > 30) then
MAP.reclaim(id)
end
if free and pack then
packFree[#packFree + 1] = id
elseif free and (q.cursor < total or (q.redo and #q.redo > 0)) then
local spots = nextBatch(q)
if #spots > 0 then
TT.sendSpots(id, spots, q.r)
q.out = q.out or {}
q.out[id] = spots
t.queueAt = os.clock()
q.sent = q.sent + #spots
busy = true
q.changed = true
end
end
end


local nowE = os.epoch("utc")
for id in pairs(q.out or {}) do
local t = state.turtles[id]
if not t or (not TT.online(t) and t.seenEpoch and nowE - t.seenEpoch > (tonumber(CONFIG.map.reclaimOffline) or 600) * 1000) then
MAP.reclaim(id)
q.changed = true
end
end


if pack and #packFree > 0 and (q.cursor < total or (q.redo and #q.redo > 0)) then
local open = false
if q.wave then
for _, wid in ipairs(q.wave.ids or {}) do if q.out and q.out[wid] then open = true end end
if open and os.clock() - (q.wave.t or 0) > (tonumber(CONFIG.map.packWait) or 300) then open = false end
end
if open then
busy = true
for _, id in ipairs(packFree) do state.turtles[id].packWait = true end
else
table.sort(packFree)
local n = math.min(#packFree, tonumber(CONFIG.map.packSize) or 8)
local k = tonumber(CONFIG.map.packSpots) or 3
local spots = nextBatch(q, n * k)
n = math.min(n, #spots)
local ids = {}


local lists, cnt = {}, {}
for i = 1, n do lists[i], cnt[i] = {}, 0 end
for _, p in ipairs(spots) do
local best, bestV
for i = 1, n do
local rate = tonumber(state.turtles[packFree[i]].packRate) or 0.01
local v = (cnt[i] + 1) / rate
if not best or v < bestV then best, bestV = i, v end
end
cnt[best] = cnt[best] + 1
lists[best][#lists[best] + 1] = p
end
for i = 1, n do
local mine = lists[i]
local id = packFree[i]
local t = state.turtles[id]
if #mine == 0 then mine = nil end
if mine then
TT.sendSpots(id, mine, q.r)
q.out = q.out or {}
q.out[id] = mine
t.queueAt, t.packWait = os.clock(), nil
q.sent = q.sent + #mine
ids[#ids + 1] = id
end
end
if n > 0 then
q.wave = { t = os.clock(), ids = ids }
busy, q.changed = true, true
end
end
end



if not busy and not anyFree and (q.cursor < total or (q.redo and #q.redo > 0)) then
local msg = (#list == 0) and "No turtle can survey (online, idle, position known, not anchor/rescuer)."
or ("No turtle takes a batch - " .. table.concat(why, ", "))
if msg ~= MAP.queueToldMsg or os.clock() - (MAP.queueToldAt or 0) > 600 then
MAP.queueToldAt, MAP.queueToldMsg = os.clock(), msg
setPopup("SURVEY WAITING", msg, C.warn)
end
else
MAP.queueToldMsg = nil
end
local open = (q.redo and #q.redo > 0) or (q.out and next(q.out) ~= nil)
if q.cursor >= total and not busy and not open and q.auto then
MAP.auto.done, MAP.auto.cursor = true, q.cursor
MAP.saveAuto()
setPopup("AUTO-MAP DONE", "The whole world up to the border is surveyed.", C.good)
if sysLog then sysLog("Auto-map done: the whole world up to the border is surveyed", "DONE") end
MAP.queue = nil
elseif q.cursor >= total and not busy and not open then
setToast("Survey finished: " .. q.sent .. " scans, " .. q.skipped .. " spots were already mapped", C.good)
MAP.queue = nil
end

if not MAP.queue or q.changed or os.clock() - (MAP.queueSavedAt or 0) > 60 then
q.changed = nil
MAP.queueSavedAt = os.clock()
saveQueue()
end
end


function MAP.surveyProgress()
local q = MAP.queue
if not q then return nil end
local total = q.cols * q.rows
if q.rect then


local inArea = math.max(1, (math.floor((q.x2 - q.x1) / q.step) + 1) * (math.floor((q.z2 - q.z1) / q.step) + 1))
local k = math.max(0, math.ceil((math.sqrt(q.cursor + 1) - 1) / 2))
local half = k * q.step
local w = math.min(q.x2, q.cx + half) - math.max(q.x1, q.cx - half)
local h = math.min(q.z2, q.cz + half) - math.max(q.z1, q.cz - half)
local passed = (math.floor(math.max(0, w) / q.step) + 1) * (math.floor(math.max(0, h) / q.step) + 1)
if q.cursor >= total then passed = inArea end
local again = q.redo and #q.redo or 0
return math.min(1, passed / inArea), inArea, q.sent, q.skipped, again
end
local again = q.redo and #q.redo or 0
return q.cursor / total, total, q.sent, q.skipped, again
end


local BASIS = {
[0] = { rx = 1,  rz = 0,  dx = 0,  dz = 1 },
[1] = { rx = 0,  rz = 1,  dx = -1, dz = 0 },
[2] = { rx = -1, rz = 0,  dx = 0,  dz = -1 },
[3] = { rx = 0,  rz = -1, dx = 1,  dz = 0 },
}

function MAP.basis() return BASIS[(MAP.view().rot or 0) % 4] end



function MAP.toWorld(sx, sy)
local V, B = MAP.view(), MAP.basis()
local a, b = sx * V.zoom, sy * V.zoom * 1.5
return V.cx + math.floor(a * B.rx + b * B.dx), V.cz + math.floor(a * B.rz + b * B.dz)
end


function MAP.toCell(x, z)
local V, B = MAP.view(), MAP.basis()
local ddx, ddz = x - V.cx, z - V.cz
return (ddx * B.rx + ddz * B.rz) / V.zoom, (ddx * B.dx + ddz * B.dz) / (V.zoom * 1.5)
end

local DIRL = { [0] = "N", "E", "S", "W" }
local DIRN = { [0] = "NORTH", "EAST", "SOUTH", "WEST" }

function MAP.compass()
local r = (MAP.view().rot or 0) % 4
return DIRL[r], DIRL[(r + 1) % 4], DIRL[(r + 2) % 4], DIRL[(r + 3) % 4], DIRN[r]
end


