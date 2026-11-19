-- base_theme.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   Colours, the off-screen window and small helpers used everywhere.
--   - flushWindow(): copies only the changed rows to the monitor (keep it: speed)
--   - saveFileSafe(): writes a data file only if it fits, through a temp file
--   - dataFile() / mountedDisks(): big data files can live on data floppies
--   - pmap(): runs game calls at the same time;  waitFor(): sleep or wake on an event

---------------------------------------------------------------------
-- THEME
---------------------------------------------------------------------
-- CONTROL ROOM (the look of every page - rules in CLAUDE.md "UI rules"; the owner's pick
-- of three mockups, "B": an operations console). Near-black page, panels a shade lighter
-- with THIN outline frames (2x3 sub-pixel lines) and the title cut into the top line,
-- AMBER titles, a TEAL accent, status lights, segmented gauges, big numbers.
-- Colour slots (16): a THEME only changes the frame slots - page bg, panel, lines, dim
-- text, titles. Every other slot is FIXED: text, the accent / status colours and the
-- MAP's colours (grass, water, sand, snow ...) look the same in every theme.
--   black     bg      the page
--   gray      panel   inside a panel (a shade lighter than the page)
--   magenta   line    frames, gauge tracks, separators, quiet button faces
--   lightGray dim     secondary text
--   lightBlue label   amber titles, big numbers
--   white     text    (fixed)        cyan  accent / info (fixed, teal)
--   green good  yellow warn  red bad  orange  purple  pink  lime  blue  brown (fixed)
local SLOTS = { colors.black, colors.gray, colors.magenta, colors.lightGray, colors.white,
                colors.brown, colors.blue, colors.lightBlue, colors.cyan, colors.green,
                colors.yellow, colors.orange, colors.red, colors.pink, colors.purple, colors.lime }
local FIXED = { 0x060A0B, 0x0C1315, 0x1E3A37, 0x6F8D87, 0xE6F2EE, 0x9C968C, 0x3D7BFF, 0xFFB238,
                0x3FE0C8, 0x5BD46A, 0xFFD34D, 0xFF8A3D, 0xFF4D5E, 0xFF6FA8, 0xB18CFF, 0xA6E05A }
-- the frame of each theme: page, panel, lines, dim text, titles
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
LIGHT_FG = nil                       -- (no light buttons in this look)
function themeStyle() end
local THEME_FILE = "theme.dat"

-- the theme for this start: a fixed one (the 'theme' command, or
-- CONFIG.theme = "stone" in base_config.lua), or "random" (the default): a
-- different one on every start
local function chooseTheme()
  local saved = {}
  do
    local t = readSafe(THEME_FILE)
    if type(t) == "table" then saved = t end
  end
  local want = saved.mode or CONFIG.theme or "teal"
  if THEMES[want] then return want, saved end
  if want ~= "random" then return "teal", saved end           -- (a theme of the old look)
  local pick
  for _ = 1, 10 do
    pick = THEME_ORDER[math.random(#THEME_ORDER)]
    if pick ~= saved.last then break end            -- not the same as last time
  end
  return pick, saved
end

-- switch to a theme (also while running: the monitor gets the new colours)
function setTheme(name)
  if not THEMES[name] then return false end
  THEME_NAME = name
  PALETTE = {}
  for i, c in ipairs(SLOTS) do
    PALETTE[c] = FRAME[c] and THEMES[name][FRAME[c]] or FIXED[i]
  end
  if mon then pcall(applyPalette, mon) end
  if win then pcall(applyPalette, win) end
  shownRows = {}                -- every row is drawn again
  return true
end

-- remember the choice: mode = a theme name or "random"
function saveTheme(mode)
  writeSafe(THEME_FILE, textutils.serialize({ mode = mode, last = THEME_NAME }))
end

do
  local name, saved = chooseTheme()
  setTheme(name)
  THEME_MODE = saved.mode or CONFIG.theme or "random"
  saveTheme(saved.mode)                             -- remembers 'last' for the next pick
end

-- what each colour is FOR (pages use these names, never a slot directly)
C = {
  bg = colors.black, panel = colors.gray, line = colors.magenta, dim = colors.lightGray,
  text = colors.white, label = colors.lightBlue, accent = colors.cyan, info = colors.cyan,
  good = colors.green, warn = colors.yellow, bad = colors.red, ink = colors.black,
  orange = colors.orange, purple = colors.purple, pink = colors.pink, lime = colors.lime,
  blue = colors.blue, red = colors.red,
  head = colors.magenta, empty = colors.magenta,      -- (older names: lines / quiet faces)
}

-- colours an item can be tinted with
ITEM_COLORS = {                      -- (fixed colours only: lightBlue = the amber titles)
  colors.blue, colors.cyan, colors.green, colors.yellow, colors.orange,
  colors.red, colors.pink, colors.purple, colors.lime,
}

-- set the program's colours on a monitor or window
function applyPalette(dev)
  for c, rgb in pairs(PALETTE) do dev.setPaletteColor(c, rgb) end
end

-- give the monitor its normal colours back (on exit)
function restorePalette()
  for c in pairs(PALETTE) do
    mon.setPaletteColor(c, term.nativePaletteColor(c))
  end
end

---------------------------------------------------------------------
-- WINDOW (double buffer = no flicker)
---------------------------------------------------------------------
win, W, H = nil

-- Write a whole data file safely: only if it fits on the disk, and through a
-- temporary file - a failed write never destroys the old file. Returns
-- true, or false + the reason (also shown in the footer as a warning).
-- textutils.serialize without the spaces and line breaks (a third of the size)
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
  local ok, err = writeSafe(path, text)              -- (complete or not at all)
  if not ok then
    state.diskLow = "DISK FULL: " .. path .. " not saved (" .. tostring(err) .. ")"
    return false, state.diskLow
  end
  -- a warning about this very file is out of date now
  if state.diskLow and state.diskLow:find(path, 1, true) then state.diskLow = nil end
  return true
end

-- ===== floppy disks (Disk Drives next to the computer or on the network) =====
-- data floppies (marked with a "base_data" file) hold the big data files;
-- the install floppy (marked "turtle_installer") holds the turtle program
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

-- where a big data file lives: on a data floppy if there is one (the one it
-- is already on, else the one with the most room - the computer's copy is
-- moved there), otherwise on the computer.
-- forSave = false (reading): a computer copy too big to move is READ from the
-- computer (all of it). forSave = true: it is written to the floppy (the
-- save trims it to fit); the computer copy is removed after that save.
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
        return path                -- too big to move as it is: read the computer's copy
      end
    end
    return p
  end
  return path
end

-- where a data file lives NOW (a data floppy first - dataFile moves the
-- computer's copy there), remembered for a minute: dataFile looks at every
-- drive, too slow for every log line. Logs, mining.dat, turtles.dat ... use it
-- so the computer's 1 MB is left for the program.
local DPATH = {}
function dataPath(name)
  local c = DPATH[name]
  if c and os.clock() - c.t < 60 and c.t <= os.clock() then return c.p end
  local ok, p = pcall(dataFile, name)
  p = (ok and p) or name
  DPATH[name] = { p = p, t = os.clock() }
  return p
end
function dataPathReset() DPATH = {} end                 -- (look again now: a floppy was put in)
-- a log file and its ".old" partner in the same place (a floppy); an old
-- partner still on the computer moves along
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
-- free space where a path lives
function freeAt(path)
  local d = fs.getDir(path)
  local ok, f = pcall(fs.getFreeSpace, d == "" and "/" or d)
  return ok and type(f) == "number" and f or 0
end

-- a data file was saved somewhere else (a data floppy): the old copy on the
-- computer is not needed any more
function dropOldCopy(configPath, savedPath, nothingInMemory)
  if nothingInMemory and fs.exists(configPath) and fs.getSize(configPath) > 1024 then
    return                         -- safety: never replace real data by an empty save
  end
  if savedPath ~= configPath and fs.exists(configPath) and fs.exists(savedPath) then
    pcall(fs.delete, configPath)
  end
end

-- (re)create the off-screen window at the monitor's size
function buildWindow()
  applyPalette(mon)
  W, H = mon.getSize()
  win = window.create(mon, 1, 1, W, H, false)
  applyPalette(win)
  shownRows = {}                -- what the monitor shows now (see flushWindow)
end

-- Put the drawn frame on the monitor: only the rows that changed. Redrawing
-- the whole window re-sends every row to the monitor (and to every player
-- near it) every second; usually only a few rows change.
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

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
-- CLIP: drawing never leaves the screen, nor the box set with clip() (every panel() sets
-- its own inside) - the owner: "fix text going out of bound". Text cut by the clip
-- ends in "~" so you can see there was more.
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

-- write text into the off-screen window (clipped)
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

-- cut a text to n characters (ends with "~" when cut)
function trunc(s, n)
  if n <= 0 then return "" end
  if #s <= n then return s end
  if n == 1 then return s:sub(1, 1) end
  return s:sub(1, n - 1) .. "~"
end
-- shorten a value that does not fit: first without a "(hint)" at the end, then
-- without a " - note" at the end, only then cut (ends in "~")
function shorten(s, n)
  s = tostring(s)
  if #s <= n then return s end
  local a = s:gsub("%s*%b()%s*$", "")
  if #a <= n and #a > 0 then return a end
  local b = a:match("^(.-)%s+%-%s+.*$")
  if b and #b > 0 and #b <= n then return b end
  return trunc(a, n)
end

-- 1234567 -> "1,234,567"
function commas(n)
  local s = tostring(math.floor(n))
  local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (r:gsub("^,", ""))
end

-- 1234 -> "1.2k", 2500000 -> "2.5m"
function compact(n)
  if n < 1000 then return tostring(n) end
  if n < 100000 then
    local s = string.format("%.1f", n / 1000):gsub("%.0$", "")
    return s .. "k"
  end
  if n < 1000000 then return math.floor(n / 1000) .. "k" end
  -- (an AE2 network reaches billions: "8862.2m" read as millions - it is 8.86b)
  if n < 1e9 then return (string.format("%.1fm", n / 1000000):gsub("%.0m$", "m")) end
  if n < 1e12 then return (string.format("%.2fb", n / 1e9):gsub("%.?0+b$", "b")) end
  return (string.format("%.2ft", n / 1e12):gsub("%.?0+t$", "t"))
end
-- bytes as B / KB / MB / GB / TB (AE2 crafting CPUs, cells)
function fmtBytes(n)
  n = tonumber(n) or 0
  local units = { "B", "KB", "MB", "GB", "TB", "PB" }
  local i = 1
  while n >= 1024 and i < #units do n, i = n / 1024, i + 1 end
  if i == 1 then return math.floor(n) .. " B" end
  return (string.format(n < 10 and "%.1f" or "%.0f", n):gsub("%.0$", "")) .. " " .. units[i]
end

-- every item gets its own colour while there are free ones
assigned, usedBy = {}, {}
-- a colour for an item, different from the other items shown where possible
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

-- word-wrap into at most maxLines lines of width w (words are never split)
function wrap(s, w, maxLines)
  local lines, cur = {}, ""
  for word in s:gmatch("%S+") do
    if #word > w then word = (w > 1) and (word:sub(1, w - 1) .. ".") or word:sub(1, w) end   -- (an abbreviation)
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

-- Run fn(item, index) for every item AT THE SAME TIME. Game calls overlap
-- instead of costing a game tick each, one after the other.
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

-- Wait up to t seconds, or until one of the named events arrives.
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


-- files of a feature that was taken out again (remote access in a web browser): removed once at
-- start, they only took room on the 1 MB computer. pocket.lua next to inventory.lua only when it is
-- the copy that feature put there (its "local" mode) - the owner's own copy is left alone.
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

-- ===== OPTIONAL ADD-ONS (kept on a DATA FLOPPY, not on the 1 MB computer) =====
-- voice_addon.lua (the base talks): `voice install` downloads it onto a data floppy, the base
-- loads it at start when it finds it there (or next to inventory.lua), `voice remove` deletes it.
-- the talking base = the add-on + its TALK PACKS (more things to say; each on a data floppy with room)
VOICE_FILES = { "voice_addon.lua", "voice_talk.lua", "voice_talk2.lua" }
function addonPath(file)
  for _, d in ipairs(mountedDisks()) do
    local p = fs.combine(d.mount, file)
    if fs.exists(p) then return p end
  end
  local here = fs.combine(BASE_DIR or "", file)
  if fs.exists(here) then return here end
  return nil
end
function loadAddon(file)
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
-- download an add-on (upgrade.lua fetch mode: checked + compiles) onto a data floppy
function installAddon(file, group, log)
  log = log or function() end
  local up = fs.combine(BASE_DIR or "", "upgrade.lua")
  local fn = fs.exists(up) and loadfile(up, "t", _ENV)
  if not fn then return false, "upgrade.lua is missing next to inventory.lua" end
  local okR, done, body = pcall(fn, { fetch = file, group = group, dir = BASE_DIR or "", log = log })
  if not (okR and done and type(body) == "string") then return false, "the download did not work (see above)" end
  local best
  for _, d in ipairs(mountedDisks()) do
    if d.data and (d.free or 0) > #body + 16 * 1024 and (not best or d.free > best.free) then best = d end
  end
  if not best then
    return false, "no DATA floppy with room (" .. math.ceil(#body / 1024 + 16) .. " KB) - add-ons are kept off the computer. Put a floppy in a drive and type  disks data"
  end
  local old = addonPath(file)
  local p = fs.combine(best.mount, file)
  if not saveFileSafe(p, body) then return false, "could not save it on " .. best.mount end
  if old and old ~= p then pcall(fs.delete, old) end
  return loadAddon(file)
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
