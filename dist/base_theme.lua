

























local SLOTS = { colors.black, colors.gray, colors.magenta, colors.lightGray, colors.white,
colors.brown, colors.blue, colors.lightBlue, colors.cyan, colors.green,
colors.yellow, colors.orange, colors.red, colors.pink, colors.purple, colors.lime }
local FIXED = { 0x060A0B, 0x0C1315, 0x1E3A37, 0x6F8D87, 0xE6F2EE, 0x9C968C, 0x3D7BFF, 0xFFB238,
0x3FE0C8, 0x5BD46A, 0xFFD34D, 0xFF8A3D, 0xFF4D5E, 0xFF6FA8, 0xB18CFF, 0xA6E05A }

THEMES = {
teal     = { bg = 0x060A0B, panel = 0x0C1315, line = 0x1E3A37, dim = 0x6F8D87, title = 0xFFB238 },
amber    = { bg = 0x0A0805, panel = 0x130E08, line = 0x3D2D15, dim = 0x9E8862, title = 0xFFC14D },
ice      = { bg = 0x070A10, panel = 0x0D131C, line = 0x23364F, dim = 0x7D90AB, title = 0x8CC8FF },
violet   = { bg = 0x09070F, panel = 0x110D1B, line = 0x31264B, dim = 0x8F83AE, title = 0xF2C14E },
graphite = { bg = 0x0A0A0A, panel = 0x141414, line = 0x323232, dim = 0x8E8E8E, title = 0xFFB238 },
crimson  = { bg = 0x0D0607, panel = 0x170B0D, line = 0x47212B, dim = 0xA27E84, title = 0xFFB238 },
}
THEME_ORDER = { "teal", "amber", "ice", "violet", "graphite", "crimson" }
local FRAME = { [colors.black] = "bg", [colors.gray] = "panel", [colors.magenta] = "line",
[colors.lightGray] = "dim", [colors.lightBlue] = "title" }
LIGHT_FG = nil
function themeStyle() end
local THEME_FILE = "theme.dat"




local function chooseTheme()
local saved = {}
do
local t = readSafe(THEME_FILE)
if type(t) == "table" then saved = t end
end
local want = saved.mode or CONFIG.theme or "teal"
if THEMES[want] then return want, saved end
if want ~= "random" then return "teal", saved end
local pick
for _ = 1, 10 do
pick = THEME_ORDER[math.random(#THEME_ORDER)]
if pick ~= saved.last then break end
end
return pick, saved
end


function setTheme(name)
if not THEMES[name] then return false end
THEME_NAME = name
PALETTE = {}
for i, c in ipairs(SLOTS) do
PALETTE[c] = FRAME[c] and THEMES[name][FRAME[c]] or FIXED[i]
end
if mon then pcall(applyPalette, mon) end
if win then pcall(applyPalette, win) end
shownRows = {}
return true
end


function saveTheme(mode)
writeSafe(THEME_FILE, textutils.serialize({ mode = mode, last = THEME_NAME }))
end

do
local name, saved = chooseTheme()
setTheme(name)
THEME_MODE = saved.mode or CONFIG.theme or "random"
saveTheme(saved.mode)
end


C = {
bg = colors.black, panel = colors.gray, line = colors.magenta, dim = colors.lightGray,
text = colors.white, label = colors.lightBlue, accent = colors.cyan, info = colors.cyan,
good = colors.green, warn = colors.yellow, bad = colors.red, ink = colors.black,
orange = colors.orange, purple = colors.purple, pink = colors.pink, lime = colors.lime,
blue = colors.blue, red = colors.red,
head = colors.magenta, empty = colors.magenta,
}


ITEM_COLORS = {
colors.blue, colors.cyan, colors.green, colors.yellow, colors.orange,
colors.red, colors.pink, colors.purple, colors.lime,
}


function applyPalette(dev)
for c, rgb in pairs(PALETTE) do dev.setPaletteColor(c, rgb) end
end


function restorePalette()
for c in pairs(PALETTE) do
mon.setPaletteColor(c, term.nativePaletteColor(c))
end
end




win, W, H = nil





function serialSmall(t)
local ok, s = pcall(textutils.serialize, t, { compact = true })
if ok and type(s) == "string" then return s end
return textutils.serialize(t)
end













function voiceCacheFiles()
local out = {}
for _, d in ipairs(mountedDisks()) do
local dir = fs.combine(d.mount, "voice")
if fs.isDir(dir) then
for _, f in ipairs(fs.list(dir)) do
local p = fs.combine(dir, f)
local okA, at = pcall(fs.attributes, p)
out[#out + 1] = { path = p, size = fs.getSize(p) or 0, mount = d.mount,
at = okA and type(at) == "table" and (at.modified or at.created) or 0 }
end
end
end
table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.path < b.path end)
return out
end
function voiceCacheBytes(mount)
local n = 0
for _, f in ipairs(voiceCacheFiles()) do if not mount or f.mount == mount then n = n + f.size end end
return n
end

function floppyReserve()
if MAP and MAP.floppyKeep then
local ok, k = pcall(MAP.floppyKeep)
if ok and type(k) == "number" then return k end
end
return 16 * 1024
end

function freeFloppyRoom(mount, need)
if fs.getFreeSpace(mount) >= need then return true end
for _, f in ipairs(voiceCacheFiles()) do
if f.mount == mount then
pcall(fs.delete, f.path)
if fs.getFreeSpace(mount) >= need then return true end
end
end
return fs.getFreeSpace(mount) >= need
end


function trimVoiceCache()
local v = CONFIG.voice or {}
local max = (tonumber(v.cacheKB) or 200) * 1024
local files = voiceCacheFiles()
local total, n = 0, 0
for _, f in ipairs(files) do total = total + f.size end
local keep = floppyReserve()
for _, f in ipairs(files) do
local low = fs.getFreeSpace(f.mount) < keep
if total > max or low then
if pcall(fs.delete, f.path) then total, n = total - f.size, n + 1 end
end
end
return n, total
end

local MOVED_AT = {}
function moveDataFile(path, text)
local dir, name = fs.getDir(path), fs.getName(path)
local disks = mountedDisks()
local here
for _, d in ipairs(disks) do if d.data and d.mount == dir then here = d end end
if not here then return nil end

if freeFloppyRoom(dir, #text + 4096) then
if writeSafe(path, text) then return path end
end
if name:find("%.lua$") or name:find("%.log$") then return nil end




local need = 2 * #text + 8192
local best, bestRoom
for _, d in ipairs(disks) do
if d.data and d ~= here then
local room = (d.free or 0) + voiceCacheBytes(d.mount)
if room >= need and (not best or room > bestRoom) then best, bestRoom = d, room end
end
end
if not best then return nil end
if not freeFloppyRoom(best.mount, need) then return nil end
local np = fs.combine(best.mount, name)
if not writeSafe(np, text) then pcall(fs.delete, np) return nil end
pcall(fs.delete, path)
if dataPathReset then dataPathReset() end
if sysLog and os.clock() - (MOVED_AT[name] or -9999) > 3600 then
MOVED_AT[name] = os.clock()
sysLog(name .. " did not fit on " .. dir .. " any more - moved to " .. best.mount, "INFO")
end
return np
end

function saveFileSafe(path, text)
local dir = fs.getDir(path)
local okF, free = pcall(fs.getFreeSpace, dir == "" and "/" or dir)
if okF and type(free) == "number" and free < #text + 4096 then
local okM, np = pcall(moveDataFile, path, text)
if okM and np then
if state.diskLow and state.diskLow:find(path, 1, true) then state.diskLow = nil end
return true, np
end


state.offloadAt, state.offloadLeft = nil, nil
if os.queueEvent then pcall(os.queueEvent, "map_save") end
state.diskLow = string.format("DISK ALMOST FULL: %s not saved (%d KB free, needs %d KB) - type disks",
path, math.floor(free / 1024), math.ceil(#text / 1024))
return false, state.diskLow
end
local ok, err = writeSafe(path, text)
if not ok then
state.diskLow = "DISK FULL: " .. path .. " not saved (" .. tostring(err) .. ")"
return false, state.diskLow
end

if state.diskLow and state.diskLow:find(path, 1, true) then state.diskLow = nil end
return true
end




function mountedDisks()
local out = {}
if not disk then return out end
for _, n in ipairs(peripheral.getNames()) do
if peripheral.getType(n) == "drive" and disk.isPresent(n) and disk.hasData(n) then
local m = disk.getMountPath(n)
if m then
local okF, free = pcall(fs.getFreeSpace, m)
out[#out + 1] = { name = n, mount = m, label = disk.getLabel(n), free = okF and free or 0,
data = fs.exists(fs.combine(m, "base_data")),
installer = fs.exists(fs.combine(m, "turtle_installer")),
empty = #fs.list(m) == 0 }
end
end
end
table.sort(out, function(a, b) return a.mount < b.mount end)
return out
end







function dataFile(path, forSave)
local name = fs.getName(path)
local best
for _, d in ipairs(mountedDisks()) do
if d.data then
local p = fs.combine(d.mount, name)
if fs.exists(p) then return p end
if not best or d.free > best.free then best = d end
end
end
if best then
local p = fs.combine(best.mount, name)
if fs.exists(path) then
if fs.getSize(path) + 2048 < best.free then
pcall(fs.copy, path, p)
if fs.exists(p) then pcall(fs.delete, path) end
elseif not forSave then
return path
end
end
return p
end
return path
end





local DPATH = {}
function dataPath(name)
local c = DPATH[name]
if c and os.clock() - c.t < 60 and c.t <= os.clock() then return c.p end
local ok, p = pcall(dataFile, name)
p = (ok and p) or name
DPATH[name] = { p = p, t = os.clock() }
return p
end
function dataPathReset() DPATH = {} end


function logPaths(cur, old)
local cp = dataPath(cur)
local op = old
if cp ~= cur then
op = fs.combine(fs.getDir(cp), old)
if fs.exists(old) and not fs.exists(op) then pcall(fs.move, old, op) end
if fs.exists(old) then pcall(fs.delete, old) end
end
return cp, op
end

function freeAt(path)
local d = fs.getDir(path)
local ok, f = pcall(fs.getFreeSpace, d == "" and "/" or d)
return ok and type(f) == "number" and f or 0
end



function dropOldCopy(configPath, savedPath, nothingInMemory)
if nothingInMemory and fs.exists(configPath) and fs.getSize(configPath) > 1024 then
return
end
if savedPath ~= configPath and fs.exists(configPath) and fs.exists(savedPath) then
pcall(fs.delete, configPath)
end
end


function buildWindow()
applyPalette(mon)
W, H = mon.getSize()
win = window.create(mon, 1, 1, W, H, false)
applyPalette(win)
shownRows = {}
end




function flushWindow()
if not win.getLine or not mon.blit then win.setVisible(true) win.setVisible(false) return end
shownRows = shownRows or {}
for y = 1, H do
local t, f, b = win.getLine(y)
local key = t .. f .. b
if shownRows[y] ~= key then
mon.setCursorPos(1, y)
mon.blit(t, f, b)
shownRows[y] = key
end
end
end







CLIP = nil
function clip(x, y, w, h) CLIP = { x, y, x + w - 1, y + h - 1 } end
function unclip() CLIP = nil end
local function bounds()
local x1, y1, x2, y2 = 1, 1, W or 9999, H or 9999
if CLIP then
x1, y1 = math.max(x1, CLIP[1]), math.max(y1, CLIP[2])
x2, y2 = math.min(x2, CLIP[3]), math.min(y2, CLIP[4])
end
return x1, y1, x2, y2
end
function fill(x, y, w, h, bg)
local x1, y1, x2, y2 = bounds()
local a, b = math.max(x, x1), math.min(x + w - 1, x2)
if b < a then return end
win.setBackgroundColor(bg)
local line = (" "):rep(b - a + 1)
for j = math.max(y, y1), math.min(y + h - 1, y2) do
win.setCursorPos(a, j)
win.write(line)
end
end


function text(x, y, s, fg, bg)
s = tostring(s)
local x1, y1, x2, y2 = bounds()
if y < y1 or y > y2 then return end
if x < x1 then s = s:sub(x1 - x + 1) x = x1 end
local room = x2 - x + 1
if room <= 0 or #s == 0 then return end
if #s > room then
s = s:sub(1, room)
if room >= 3 and s:byte(room) < 128 and s:sub(room - 1, room) ~= "  " then s = s:sub(1, room - 1) .. "~" end
end
if bg then win.setBackgroundColor(bg) end
win.setTextColor(fg)
win.setCursorPos(x, y)
win.write(s)
end


function trunc(s, n)
if n <= 0 then return "" end
if #s <= n then return s end
if n == 1 then return s:sub(1, 1) end
return s:sub(1, n - 1) .. "~"
end


function shorten(s, n)
s = tostring(s)
if #s <= n then return s end
local a = s:gsub("%s*%b()%s*$", "")
if #a <= n and #a > 0 then return a end
local b = a:match("^(.-)%s+%-%s+.*$")
if b and #b > 0 and #b <= n then return b end
return trunc(a, n)
end


function commas(n)
local s = tostring(math.floor(n))
local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
return (r:gsub("^,", ""))
end


function compact(n)
if n < 1000 then return tostring(n) end
if n < 100000 then
local s = string.format("%.1f", n / 1000):gsub("%.0$", "")
return s .. "k"
end
if n < 1000000 then return math.floor(n / 1000) .. "k" end

if n < 1e9 then return (string.format("%.1fm", n / 1000000):gsub("%.0m$", "m")) end
if n < 1e12 then return (string.format("%.2fb", n / 1e9):gsub("%.?0+b$", "b")) end
return (string.format("%.2ft", n / 1e12):gsub("%.?0+t$", "t"))
end

function fmtBytes(n)
n = tonumber(n) or 0
local units = { "B", "KB", "MB", "GB", "TB", "PB" }
local i = 1
while n >= 1024 and i < #units do n, i = n / 1024, i + 1 end
if i == 1 then return math.floor(n) .. " B" end
return (string.format(n < 10 and "%.1f" or "%.0f", n):gsub("%.0$", "")) .. " " .. units[i]
end


assigned, usedBy = {}, {}

function colorFor(name)
local c = assigned[name]
if c then return c end
local h = 5381
for i = 1, #name do h = (h * 33 + name:byte(i)) % 2147483647 end
local n = #ITEM_COLORS
for i = 0, n - 1 do
local cand = ITEM_COLORS[(h + i) % n + 1]
if not usedBy[cand] then
assigned[name], usedBy[cand] = cand, name
return cand
end
end
c = ITEM_COLORS[h % n + 1]
assigned[name] = c
return c
end


function wrap(s, w, maxLines)
local lines, cur = {}, ""
for word in s:gmatch("%S+") do
if #word > w then word = (w > 1) and (word:sub(1, w - 1) .. ".") or word:sub(1, w) end
if cur == "" then
cur = word
elseif #cur + 1 + #word <= w then
cur = cur .. " " .. word
else
lines[#lines + 1] = cur
cur = word
end
end
if cur ~= "" then lines[#lines + 1] = cur end
if #lines > maxLines then
local last = lines[maxLines]
lines[maxLines] = (#last >= w) and (last:sub(1, w - 1) .. ".") or (last .. ".")
for i = #lines, maxLines + 1, -1 do lines[i] = nil end
end
return lines
end



function pmap(list, fn)
local results, fns = {}, {}
for i, v in ipairs(list) do
fns[#fns + 1] = function()
local ok, r = pcall(fn, v, i)
if ok then results[i] = r end
end
end
if #fns > 0 then parallel.waitForAll(table.unpack(fns)) end
return results
end


function waitFor(t, ...)
local id = os.startTimer(t)
local names = { ... }
local deadline = os.clock() + t
while true do
local ev, p = os.pullEventRaw()
if (ev == "timer" and p == id) or os.clock() >= deadline then return end
if ev == "terminate" then os.cancelTimer(id) return end
for _, n in ipairs(names) do
if ev == n then os.cancelTimer(id) return end
end
end
end





function removeOldFiles(dir)
local gone = {}
local function del(p)
if fs.exists(p) and not fs.isDir(p) and pcall(fs.delete, p) then gone[#gone + 1] = p end
end
dir = dir or ""
del(fs.combine(dir, "remote.lua"))
del(fs.combine(dir, "base_remote.lua"))
del("cloud.lua")
for _, d in ipairs(mountedDisks()) do del(fs.combine(d.mount, "cloud.lua")) end
local pp = fs.combine(dir, "pocket.lua")
if fs.exists(pp) then
local h = fs.open(pp, "r")
local text = h and h.readAll() or ""
if h then h.close() end
if text:find("POCKET_LOCAL", 1, true) then del(pp) end
end
return gone
end





VOICE_FILES = { "voice_addon.lua", "voice_talk.lua", "voice_talk2.lua", "voice_talk3.lua" }
function addonPath(file)
for _, d in ipairs(mountedDisks()) do
local p = fs.combine(d.mount, file)
if fs.exists(p) then return p end
end
local here = fs.combine(BASE_DIR or "", file)
if fs.exists(here) then return here end
return nil
end

local function loadOne(file)
local p = addonPath(file)
if not p then return false, "not installed" end
local h = fs.open(p, "r")
if not h then return false, "cannot read " .. p end
local text = h.readAll() or ""
h.close()
local fn, err = load(text, "@" .. p, "t", _ENV)
if not fn then return false, tostring(err) end
local ok, e = pcall(fn)
if not ok then return false, tostring(e) end
os.queueEvent("addon_loaded")
return true, p
end



function loadVoiceChain(file)
local res = {}
for i, f in ipairs(VOICE_FILES or {}) do
if addonPath(f) then
if i == 1 or (VOICE and VOICE.addIntents) then res[f] = { loadOne(f) } end
elseif i == 1 then
res[f] = { false, "not installed" }
break
end
end
local r = res[file or VOICE_FILES[1]] or { false, "not installed" }
return r[1], r[2]
end
function loadAddon(file)
for _, f in ipairs(VOICE_FILES or {}) do
if f == file then return loadVoiceChain(file) end
end
return loadOne(file)
end

function installAddon(file, group, log, noLoad)
log = log or function() end
local up = fs.combine(BASE_DIR or "", "upgrade.lua")
local fn = fs.exists(up) and loadfile(up, "t", _ENV)
if not fn then return false, "upgrade.lua is missing next to inventory.lua" end
local okR, done, body = pcall(fn, { fetch = file, group = group, dir = BASE_DIR or "", log = log })
if not (okR and done and type(body) == "string") then return false, "the download did not work (see above)" end
local old = addonPath(file)

if old then
local h = fs.open(old, "rb")
local cur = h and h.readAll()
if h then h.close() end
if cur == body then
if noLoad then return true, old, "same" end
local okL, where = loadAddon(file)
return okL, where, "same"
end
end



local need = #body + 5 * 1024
local function cacheBytes(m)
local dir, n = fs.combine(m, "voice"), 0
if fs.isDir(dir) then for _, f in ipairs(fs.list(dir)) do n = n + (fs.getSize(fs.combine(dir, f)) or 0) end end
return n
end
local best, bestRoom
for _, d in ipairs(mountedDisks()) do
if d.data then
local here = fs.combine(d.mount, file)
local room = (d.free or 0) + (fs.exists(here) and fs.getSize(here) or 0) + cacheBytes(d.mount)

if room >= need and (not best or (old == here) or (old ~= fs.combine(best.mount, file) and room > bestRoom)) then
best, bestRoom = d, room
end
end
end
if not best then
return false, "no DATA floppy with room (" .. math.ceil(need / 1024) .. " KB, counting old speech that can go) - add-ons are kept off the computer. Put an empty floppy in a drive and type  disks data"
end
local p = fs.combine(best.mount, file)

local function free() return fs.getFreeSpace(best.mount) end
if free() < need and fs.exists(p) then pcall(fs.delete, p) end
local vdir = fs.combine(best.mount, "voice")
if free() < need and fs.isDir(vdir) then
local list, age = fs.list(vdir), {}
for _, f in ipairs(list) do
local okA, at = pcall(fs.attributes, fs.combine(vdir, f))
age[f] = okA and type(at) == "table" and (at.modified or at.created) or 0
end
table.sort(list, function(a, b) return age[a] < age[b] end)
for _, f in ipairs(list) do
if free() >= need then break end
pcall(fs.delete, fs.combine(vdir, f))
end
end
if not saveFileSafe(p, body) then return false, "could not save it on " .. best.mount end
if old and old ~= p then pcall(fs.delete, old) end
if noLoad then return true, p end
return loadAddon(file)
end

function voiceUpdate(say)
say = say or function() end
local ok, msg, same = installAddon(VOICE_FILES[1], "voice", say, true)
say(ok and ((same and "Voice add-on: up to date (" or "Voice add-on: updated on ") .. tostring(msg) .. (same and ")" or ""))
or ("Voice add-on not installed: " .. tostring(msg)))
for i = 2, #VOICE_FILES do
if ok then
local okP, msgP, sameP = installAddon(VOICE_FILES[i], "voice", say, true)
say(okP and ("Talk pack " .. VOICE_FILES[i] .. (sameP and ": up to date" or (" on " .. tostring(msgP))))
or ("Talk pack " .. VOICE_FILES[i] .. " not installed: " .. tostring(msgP) .. " (the old copy stays)"))
end
end

local okL, errL = loadVoiceChain()
if ok and not okL then say("Voice add-on did not start: " .. tostring(errL)) end
return ok and okL, msg
end
function removeAddon(file)
local n = 0
while true do
local p = addonPath(file)
if not p then break end
if not pcall(fs.delete, p) or fs.exists(p) then break end
n = n + 1
end
return n
end
