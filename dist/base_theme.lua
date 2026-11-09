


























local SLOTS = { colors.black, colors.gray, colors.magenta, colors.lightGray, colors.white,
colors.brown, colors.blue, colors.lightBlue, colors.cyan, colors.green,
colors.yellow, colors.orange, colors.red, colors.pink, colors.purple, colors.lime }

local FIXED = { 0x141414, 0x2E2E2E, 0x4A4A4A, 0x6F6F6F, 0xFFFFFF, 0xA89F92, 0x5A7CE6, 0xF2B33D,
0x52CFCF, 0x5CBF5C, 0xF0DE5C, 0xEE9F34, 0xE85C5C, 0xDE7BD6, 0xA374E6, 0x92D25C }
THEMES = {



stone     = { 0x121212, 0x262626, 0x3A3A3A, 0x505050, 0xFFFFFF, 0xA8A8A8, 0x5B7FE0, 0xF2B33D },
deepslate = { 0x0F0F13, 0x212129, 0x34343F, 0x4A4A57, 0xF2F2F8, 0x9A9AA8, 0x6A84E0, 0xF2B33D },
oak       = { 0x15100A, 0x2C2117, 0x433325, 0x5E4730, 0xFFF6E8, 0xC2AE94, 0x6A9A3C, 0xF5C451 },
nether    = { 0x130909, 0x281414, 0x3E1F1F, 0x572B2B, 0xFFEEEE, 0xC09898, 0xCC4433, 0xF5A93A },
ender     = { 0x0C0A12, 0x1B1725, 0x2D2640, 0x413758, 0xF6F0FF, 0xA89CC0, 0x8C62E8, 0xEFE39C },
ocean     = { 0x071116, 0x112129, 0x1C3640, 0x284E5A, 0xEAFBFF, 0x94B8C2, 0x2FA8B8, 0xF5C451 },


bedrock   = { 0x1B1B1C, 0x313233, 0x48494A, 0xD0D1D4, 0xFFFFFF, 0xA6A6AA, 0x5A7CE6, 0xFFFFFF },
}
THEME_ORDER = { "bedrock", "stone", "deepslate", "oak", "nether", "ender", "ocean" }




THEME_STYLE = { bedrock = { light = true, accent = colors.green } }
LIGHT_FG = nil
function themeStyle()
if not C then return end
local st = THEME_STYLE[THEME_NAME] or {}
C.accent = st.accent or colors.blue
if not st.light then LIGHT_FG = nil return end
local dark = {}
for _, c in ipairs({ C.text, C.label, colors.yellow, colors.lime, colors.cyan, colors.green,
colors.orange, colors.pink, colors.lightBlue }) do dark[c] = C.ink end
dark[C.dim] = C.head
local onAccent = { [C.text] = C.ink, [C.label] = C.ink, [C.dim] = C.ink, [colors.green] = C.ink }
LIGHT_FG = { [C.empty] = dark, [C.accent] = onAccent }
end
local THEME_FILE = "theme.dat"




local function chooseTheme()
local saved = {}
if fs.exists(THEME_FILE) then
local h = fs.open(THEME_FILE, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if type(t) == "table" then saved = t end
end
local want = saved.mode or CONFIG.theme or "random"
if THEMES[want] then return want, saved end
local pick
for _ = 1, 10 do
pick = THEME_ORDER[math.random(#THEME_ORDER)]
if pick ~= saved.last then break end
end
return pick, saved
end




local MAP_SLOTS = { [colors.green] = true, [colors.lime] = true, [colors.blue] = true, [colors.yellow] = true,
[colors.orange] = true, [colors.white] = true, [colors.brown] = true, [colors.red] = true,
[colors.cyan] = true, [colors.purple] = true, [colors.pink] = true }


function setTheme(name)
if not THEMES[name] then return false end
THEME_NAME = name
PALETTE = {}
for i, c in ipairs(SLOTS) do
PALETTE[c] = (MAP_SLOTS[c] or not THEMES[name][i]) and FIXED[i] or THEMES[name][i]
end
if mon then pcall(applyPalette, mon) end
if win then pcall(applyPalette, win) end
themeStyle()
shownRows = {}
return true
end


function saveTheme(mode)
local h = fs.open(THEME_FILE, "w")
if h then h.write(textutils.serialize({ mode = mode, last = THEME_NAME })) h.close() end
end

do
local name, saved = chooseTheme()
setTheme(name)
THEME_MODE = saved.mode or CONFIG.theme or "random"
saveTheme(saved.mode)
end

C = {
bg = colors.black, panel = colors.gray, empty = colors.lightGray, head = colors.magenta,
text = colors.white, dim = colors.brown, ink = colors.black,
accent = colors.blue, label = colors.lightBlue,
good = colors.green, warn = colors.yellow, bad = colors.red,
red = colors.red, purple = colors.purple,
}

themeStyle()


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

function saveFileSafe(path, text)
local dir = fs.getDir(path)
local okF, free = pcall(fs.getFreeSpace, dir == "" and "/" or dir)
if okF and type(free) == "number" and free < #text + 4096 then
state.diskLow = string.format("DISK ALMOST FULL: %s not saved (%d KB free, needs %d KB) - type disks",
path, math.floor(free / 1024), math.ceil(#text / 1024))
return false, state.diskLow
end
local tmp = path .. ".tmp"
local h = fs.open(tmp, "w")
if not h then return false, "cannot write " .. tmp end
local ok, err = pcall(h.write, text)
pcall(h.close)
if not ok then
pcall(fs.delete, tmp)
state.diskLow = "DISK FULL: " .. path .. " not saved (" .. tostring(err) .. ")"
return false, state.diskLow
end
if fs.exists(path) then fs.delete(path) end
fs.move(tmp, path)

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




function fill(x, y, w, h, bg)
if w < 1 or h < 1 then return end
win.setBackgroundColor(bg)
local line = (" "):rep(w)
for j = 0, h - 1 do
win.setCursorPos(x, y + j)
win.write(line)
end
end


function text(x, y, s, fg, bg)
if bg and LIGHT_FG and LIGHT_FG[bg] then fg = LIGHT_FG[bg][fg] or fg end
if bg then win.setBackgroundColor(bg) end
win.setTextColor(fg)
win.setCursorPos(x, y)
win.write(s)
end


function trunc(s, n)
if n <= 0 then return "" end
if #s <= n then return s end
if n == 1 then return s:sub(1, 1) end
return s:sub(1, n - 1) .. "."
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
return string.format("%.1fm", n / 1000000):gsub("%.0m$", "m")
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
if #word > w then word = trunc(word, w) end
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

