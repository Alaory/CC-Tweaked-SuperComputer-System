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
    if type(t) == "table" then
      saved = { mode = type(t.mode) == "string" and t.mode or nil, last = type(t.last) == "string" and t.last or nil }
    end
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

-- a data file (dataFile / dataPath: the top of a data floppy) that no longer fits on
-- its floppy moves to the data floppy with the most room (the old copy goes; the
-- dataPath cache is reset so the next save / read finds it). Not program files
-- (.lua), logs (they keep their .old partner) or anything in a folder (map ...).
-- Returns the new path, or nil.
-- ===== the voice add-on's SPEECH CACHE (voice/*.dfpwm on the data floppies) =====
-- It is only a cache (fetched again when needed), so data files always come first. The old
-- add-on capped it PER FLOPPY and wrote to the floppy with the most room - every time that
-- changed it started a new cache there, so it crept over EVERY floppy and filled each to its
-- last ~16 KB (the owner: "disk12/drone_logs.dat not saved (7 KB free)" with the map already
-- off the floppies). These run on the base, also with an old add-on.
-- every cached phrase on every floppy, oldest first: { path, size, at, mount }
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
-- what a floppy keeps free for data files (the map keeps it too)
function floppyReserve()
  if MAP and MAP.floppyKeep then
    local ok, k = pcall(MAP.floppyKeep)
    if ok and type(k) == "number" then return k end
  end
  return 16 * 1024
end
-- delete the oldest cached speech on one floppy until `need` bytes are free there
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
-- the whole cache at most CONFIG.voice.cacheKB (all floppies together), and no floppy
-- under its reserve because of it. Returns how many phrases went.
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

local MOVED_AT = {}                 -- [file name] = when its move was last logged
function moveDataFile(path, text)
  local dir, name = fs.getDir(path), fs.getName(path)
  local disks = mountedDisks()
  local here
  for _, d in ipairs(disks) do if d.data and d.mount == dir then here = d end end
  if not here then return nil end
  -- first: cached speech on its OWN floppy makes room (any file there, also .lua / .log)
  if freeFloppyRoom(dir, #text + 4096) then
    if writeSafe(path, text) then return path end
  end
  if name:find("%.lua$") or name:find("%.log$") then return nil end
  -- else: the data floppy with the most room, counting the cached speech there. Room for TWO copies:
  -- a save writes the new copy before the old one goes - with room for one, the NEXT save did not fit
  -- there either and moved it back (the owner's log: "terrain.dat did not fit on disk11 - moved to
  -- disk18", then disk18 -> disk11, every minute)
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
  if sysLog and os.clock() - (MOVED_AT[name] or -9999) > 3600 then  -- (once an hour per file in the log)
    MOVED_AT[name] = os.clock()
    sysLog(name .. " did not fit on " .. dir .. " any more - moved to " .. best.mount, "INFO")
  end
  return np
end

-- a path on a floppy that is no longer in its drive ("disk2/turtles.dat": dataPath keeps a place for a
-- minute): writing there would make a FOLDER "disk2" on the computer - the file lost on the computer's
-- disk, and the floppy, put back, mounted under another name. Such a save goes to where the file
-- belongs now (dataFile: another data floppy, else the computer).
local function goneFloppy(path)
  local top = tostring(path):match("^([^/]+)/")
  if not top or not top:find("^disk%d*$") or not fs.isDriveRoot then return false end
  if not fs.exists(top) then return true end           -- (isDriveRoot says true for a path that is not there)
  local okR, root = pcall(fs.isDriveRoot, top)
  return okR and root == false
end
function saveFileSafe(path, text)
  if goneFloppy(path) then
    if dataPathReset then dataPathReset() end
    local np = dataFile(fs.getName(path), true)
    if np ~= path and not goneFloppy(np) then
      local ok, err = saveFileSafe(np, text)
      if ok then return true, np end
      return false, err
    end
  end
  local dir = fs.getDir(path)
  local okF, free = pcall(fs.getFreeSpace, dir == "" and "/" or dir)
  if okF and type(free) == "number" and free < #text + 4096 then
    local okM, np = pcall(moveDataFile, path, text)
    if okM and np then
      if state.diskLow and state.diskLow:find(path, 1, true) then state.diskLow = nil end
      return true, np
    end
    -- no floppy has room: the map worker moves map files off the floppies NOW
    -- (fullest first) instead of at its next turn - the next save then fits
    state.offloadAt, state.offloadLeft = nil, nil
    if os.queueEvent then pcall(os.queueEvent, "map_save") end
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
        local okI, id = pcall(disk.getID or function() end, n)        -- (which floppy: another one put in = new)
        out[#out + 1] = { name = n, mount = m, label = disk.getLabel(n), free = okF and free or 0, id = okI and id or nil,
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
        -- (the computer's copy goes only when the floppy's is WHOLE - a copy cut off by a full floppy
        -- left a half file there and none on the computer)
        if fs.exists(p) and fs.getSize(p) == fs.getSize(path) then pcall(fs.delete, path)
        else pcall(fs.delete, p) return path end
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
-- (+ LINES PACKS voice_lines / voice_idle: 100+ ways to say each thing; LORE PACK voice_lore: why drones not /tp, modpack tips)
VOICE_FILES = { "voice_addon.lua", "voice_talk.lua", "voice_talk2.lua", "voice_talk3.lua", "voice_lines.lua", "voice_idle.lua", "voice_lore.lua", "voice_vary.lua", "voice_spawn.lua" }
-- VOICE FILES ON STORAGE HELPERS (the owner's screen: "Voice add-on not installed: no DATA floppy with room (123 KB)"
-- even after `disks data` - the add-on is ~120 KB of a 125 KB floppy and the map / data files fill the floppies).
-- A storage helper has ~1 MB: installAddon puts a voice file on a HELPER first (CONFIG.voice.onHelpers, default on),
-- on a data floppy only when no helper has room. VOICE_WHERE (voice_where.dat, tiny, on the computer):
-- { [file] = "store:<id>/voice/<file>" }. A file there is read over the cable (STORE.read) - only where a short wait
-- is fine: the add-on worker ~15 s after start (loadVoiceChain(nil, true)), `voice update`, installs.
VOICE_WHERE_FILE = "voice_where.dat"
VOICE_WHERE = {}
do
  local t = readSafe and readSafe(VOICE_WHERE_FILE)
  if type(t) == "table" then
    for k, v in pairs(t) do
      if type(k) == "string" and type(v) == "string" and v:match("^store:%d+/") then VOICE_WHERE[k] = v end
    end
  end
end
local function saveVoiceWhere() saveFileSafe(VOICE_WHERE_FILE, textutils.serialize(VOICE_WHERE)) end
-- installed anywhere: a floppy / next to inventory.lua, or a storage helper
function addonInstalled(file) return addonPath(file) ~= nil or (VOICE_WHERE[file] ~= nil) end
-- a helper with room for `body` (the one holding the old copy first); writes it, reads it back: path or nil, why
local function voiceToHelper(file, body)
  if not STORE then return nil, "no storage helpers" end
  if not next(STORE.helpers or {}) then pcall(STORE.find, true) end
  local oldId = VOICE_WHERE[file] and STORE.parse(VOICE_WHERE[file])
  local list = {}
  for id, h in pairs(STORE.helpers or {}) do
    local room = (h.free or 0) + (id == oldId and #body or 0)
    if STORE.usable(h) and room >= #body + 16 * 1024 then list[#list + 1] = { id = id, room = room } end
  end
  table.sort(list, function(a, b) if (a.id == oldId) ~= (b.id == oldId) then return a.id == oldId end return a.room > b.room end)
  for _, c in ipairs(list) do
    local path = "store:" .. c.id .. "/voice/" .. file
    local okW = STORE.write(path, body)
    local back = okW and STORE.read(path)
    if back == body then return path end
    pcall(STORE.delete, path)
  end
  return nil, #list == 0 and "no storage helper with room" or "the storage helper did not keep it"
end
function addonPath(file)
  for _, d in ipairs(mountedDisks()) do
    local p = fs.combine(d.mount, file)
    if fs.exists(p) then return p end
  end
  local here = fs.combine(BASE_DIR or "", file)
  if fs.exists(here) then return here end
  return nil
end
-- load ONE file (no chain)
local function loadOne(file, remoteOK)
  local p = addonPath(file)
  local text
  if p then
    local h = fs.open(p, "r")
    if not h then return false, "cannot read " .. p end
    text = h.readAll() or ""
    h.close()
  elseif VOICE_WHERE[file] and remoteOK and STORE then
    p = VOICE_WHERE[file]
    if not next(STORE.helpers or {}) then pcall(STORE.find, true) end
    local okR, t = pcall(STORE.read, p)
    if not (okR and type(t) == "string" and #t > 0) then return false, "the storage helper with " .. file .. " did not answer" end
    text = t
  else
    return false, VOICE_WHERE[file] and "on a storage helper - loaded a little after start" or "not installed"
  end
  local fn, err = load(text, "@" .. p, "t", _ENV)
  if not fn then return false, tostring(err) end
  local ok, e = pcall(fn)
  if not ok then return false, tostring(e) end
  os.queueEvent("addon_loaded")
  return true, p
end
-- the talking base = a CHAIN (VOICE_FILES): the add-on empties every hook list when it loads, then each talk
-- pack adds its own. A pack loaded ALONE added its hooks a second time (every chat counted twice) - so any
-- voice file loads the whole chain, in order, once. Returns the result for `file` (nil = for the add-on).
function loadVoiceChain(file, remoteOK)
  local res = {}
  for i, f in ipairs(VOICE_FILES or {}) do
    if addonPath(f) or (remoteOK and VOICE_WHERE[f]) then
      if i == 1 or (VOICE and VOICE.addIntents) then res[f] = { loadOne(f, remoteOK) } end
    elseif i == 1 then
      res[f] = { false, "not installed" }
      break
    end
  end
  local r = res[file or VOICE_FILES[1]] or { false, "not installed" }
  return r[1], r[2]
end
function loadAddon(file, remoteOK)
  for _, f in ipairs(VOICE_FILES or {}) do
    if f == file then return loadVoiceChain(file, remoteOK) end
  end
  return loadOne(file, remoteOK)
end
-- download an add-on (upgrade.lua fetch mode: checked + compiles) onto a data floppy
function installAddon(file, group, log, noLoad)
  log = log or function() end
  local up = fs.combine(BASE_DIR or "", "upgrade.lua")
  local fn = fs.exists(up) and loadfile(up, "t", _ENV)
  if not fn then return false, "upgrade.lua is missing next to inventory.lua" end
  local okR, done, body = pcall(fn, { fetch = file, group = group, dir = BASE_DIR or "", log = log })
  if not (okR and done and type(body) == "string") then return false, "the download did not work (see above)" end
  local old = addonPath(file)
  local oldRemote = VOICE_WHERE[file]
  -- the same as the copy already there: nothing to write
  if not old and oldRemote and STORE then
    local okC, cur = pcall(STORE.read, oldRemote)
    if okC and cur == body then
      if noLoad then return true, oldRemote, "same" end
      local okL, where = loadAddon(file, true)
      return okL, where, "same"
    end
  end
  -- a STORAGE HELPER first (a floppy is 125 KB, the add-on alone ~120 KB): the old floppy copy goes - room for data
  if group == "voice" and (type(CONFIG.voice) ~= "table" or CONFIG.voice.onHelpers ~= false) and STORE and not (old and (function()
        local h = fs.open(old, "rb") local cur = h and h.readAll() if h then h.close() end return cur == body end)()) then
    local hp = voiceToHelper(file, body)
    if hp then
      if old then pcall(fs.delete, old) end
      if oldRemote and oldRemote ~= hp then pcall(STORE.delete, oldRemote) end
      VOICE_WHERE[file] = hp
      saveVoiceWhere()
      if noLoad then return true, hp end
      return loadAddon(file, true)
    end
  end
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
  -- (the owner: "on each update I have to run disks" - the map fills the data floppies, and the new copy
  --  needed a floppy with room for ALL of it while the old copy and the voice cache sat there. Now the room
  --  of the old copy and of the speech cache (voice/*.dfpwm, made again when needed) counts too)
  local need = #body + 5 * 1024                    -- (saveFileSafe keeps 4 KB free)
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
      -- (the floppy that holds the old copy first, else the one with the most room)
      if room >= need and (not best or (old == here) or (old ~= fs.combine(best.mount, file) and room > bestRoom)) then
        best, bestRoom = d, room
      end
    end
  end
  if not best then
    return false, "no storage helper and no DATA floppy with room (" .. math.ceil(need / 1024) .. " KB, counting old speech that can go) - add-ons are kept off the computer. Type  store  to check the helpers, or put an empty floppy in a drive and type  disks data"
  end
  local p = fs.combine(best.mount, file)
  -- make room: the old copy here (the new one is in memory), then the oldest cached speech
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
  if oldRemote then pcall(STORE.delete, oldRemote) VOICE_WHERE[file] = nil saveVoiceWhere() end
  if noLoad then return true, p end
  return loadAddon(file, true)
end
-- every voice file (the add-on + its talk packs): download, save, load. say(line) tells what happened.
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
  -- everything written: the whole chain loads once (a pack that could not be updated: its old copy)
  local okL, errL = loadVoiceChain(nil, true)
  if ok and not okL then say("Voice add-on did not start: " .. tostring(errL)) end
  return ok and okL, msg
end
-- AFTER AN UPGRADE (the owner: "base, fun fact" still opened the games menu after `upgrade`): `upgrade` runs with the
-- OLD program in memory - its VOICE_FILES did not know the new voice files, so they were never installed, and nothing
-- installed them later. Now: baseUpgrade leaves voice_update.flag; at the next start (addonWorker, after 15 s) the NEW
-- program updates the voice files once - also whenever one of VOICE_FILES is missing from the floppies. The result goes
-- to the SYSTEM log; a file that could not be installed (no room) = a WARNING.
VOICE_FLAG = "voice_update.flag"
function voiceRepair()
  if not (VOICE_FILES and addonInstalled and addonInstalled(VOICE_FILES[1])) then return false, "the voice add-on is not installed" end
  local missing = {}
  for _, f in ipairs(VOICE_FILES) do if not addonInstalled(f) then missing[#missing + 1] = f end end
  local flag = fs.combine(BASE_DIR or "", VOICE_FLAG)
  local flagged = fs.exists(flag)
  if #missing == 0 and not flagged then return false, "nothing to do" end
  local lines = {}
  local okU = pcall(voiceUpdate, function(l) lines[#lines + 1] = tostring(l) end)
  pcall(fs.delete, flag)
  local bad = {}
  for _, l in ipairs(lines) do if l:find("not installed", 1, true) or l:find("did not start", 1, true) then bad[#bad + 1] = l end end
  local why = flagged and "after the upgrade" or ("missing: " .. table.concat(missing, ", "))
  if sysLog then pcall(sysLog, "Voice files updated (" .. why .. "): " .. table.concat(lines, "; "), #bad > 0 and "WARNING" or "INFO") end
  if #bad > 0 and pushNote then
    pcall(pushNote, "WARNING", "Voice update: " .. table.concat(bad, "; ") .. " - type  disks  to see where there is room, then  voice update", C and C.warn)
  end
  return okU and #bad == 0, table.concat(lines, "; ")
end
function removeAddon(file)
  local n = 0
  if VOICE_WHERE[file] then
    if STORE then pcall(STORE.delete, VOICE_WHERE[file]) end
    VOICE_WHERE[file] = nil
    saveVoiceWhere()
    n = n + 1
  end
  while true do
    local p = addonPath(file)
    if not p then break end
    if not pcall(fs.delete, p) or fs.exists(p) then break end
    n = n + 1
  end
  return n
end
