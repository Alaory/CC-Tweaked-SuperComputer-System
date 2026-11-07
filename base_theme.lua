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
-- Every theme gives each colour slot the same JOB (page background, cards,
-- text, accent, green = good / grass on the map, blue = water ...), only the
-- shades change - and only for the frame (see MAP_SLOTS below). All themes are dark (the pills write dark text on colours).
-- Slot order: bg, cards, lines, buttons, text, dim, accent, titles,
--             cyan, green, yellow, orange, red, pink, purple, lime
local SLOTS = { colors.black, colors.gray, colors.magenta, colors.lightGray, colors.white,
                colors.brown, colors.blue, colors.lightBlue, colors.cyan, colors.green,
                colors.yellow, colors.orange, colors.red, colors.pink, colors.purple, colors.lime }
THEMES = {
  midnight = { 0x0B0E14, 0x151A26, 0x1F2636, 0x262E42, 0xE8ECF4, 0x7D879F, 0x6C9CFF, 0x8ED1FF,
               0x40DCC4, 0x5EE38F, 0xF6C744, 0xFF9F5C, 0xFF6B6B, 0xFF7DC4, 0xB49CFF, 0xB5E35B },
  nord     = { 0x1F232B, 0x2A2F3A, 0x343A47, 0x3E4656, 0xECEFF4, 0x8C96A8, 0x88C0D0, 0x9DB6D6,
               0x8FBCBB, 0xA3BE8C, 0xEBCB8B, 0xD08770, 0xD06A73, 0xD291BC, 0xB48EAD, 0xC5D99B },
  dracula  = { 0x191A21, 0x242631, 0x30323F, 0x3D4052, 0xF8F8F2, 0x8890B5, 0xBD93F9, 0x8BE9FD,
               0x6FE3E3, 0x50FA7B, 0xF1FA8C, 0xFFB86C, 0xFF5555, 0xFF79C6, 0xC6A4FF, 0xA6E22E },
  forest   = { 0x0D1712, 0x15231C, 0x1E3128, 0x283F33, 0xE6F0E8, 0x86A394, 0x5FD39A, 0x9FE0C0,
               0x4FD1C5, 0x7EE787, 0xF2CC60, 0xF0A060, 0xF07070, 0xF08CC0, 0xB8A0F0, 0xC0E070 },
  ember    = { 0x140E0D, 0x201715, 0x2D211E, 0x3A2B27, 0xF5ECE6, 0xA8948A, 0xFF8A50, 0xFFC48A,
               0x5FD3C8, 0x8FD86A, 0xFFD25A, 0xFF9A55, 0xFF5F5F, 0xFF80B0, 0xC79BFF, 0xC8E05A },
  ocean    = { 0x07121D, 0x0E1C2B, 0x172839, 0x21364D, 0xE4F0FA, 0x7F97AE, 0x3FA9F5, 0x7FD4FF,
               0x2FD9D0, 0x4ADE9A, 0xF5D547, 0xFFA45B, 0xFF6A7A, 0xF58BD0, 0xA99CFF, 0xA8E063 },
}
THEME_ORDER = { "midnight", "nord", "dracula", "forest", "ember", "ocean" }
local THEME_FILE = "theme.dat"

-- the theme for this start: a fixed one (the 'theme' command, or
-- CONFIG.theme = "nord" in base_config.lua), or "random" (the default): a
-- different one on every start
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
    if pick ~= saved.last then break end            -- not the same as last time
  end
  return pick, saved
end

-- colours the MAP uses (grass, water, sand, stone, snow ...): the same in
-- every theme, so the map always looks the same and stays easy to read.
-- A theme only changes the frame: background, cards, lines, buttons, titles.
local MAP_SLOTS = { [colors.green] = true, [colors.lime] = true, [colors.blue] = true, [colors.yellow] = true,
                    [colors.orange] = true, [colors.white] = true, [colors.brown] = true, [colors.red] = true,
                    [colors.cyan] = true, [colors.purple] = true, [colors.pink] = true }

-- switch to a theme (also while running: the monitor gets the new colours)
function setTheme(name)
  if not THEMES[name] then return false end
  THEME_NAME = name
  PALETTE = {}
  for i, c in ipairs(SLOTS) do
    PALETTE[c] = MAP_SLOTS[c] and THEMES.midnight[i] or THEMES[name][i]
  end
  if mon then pcall(applyPalette, mon) end
  if win then pcall(applyPalette, win) end
  shownRows = {}                -- every row is drawn again
  return true
end

-- remember the choice: mode = a theme name or "random"
function saveTheme(mode)
  local h = fs.open(THEME_FILE, "w")
  if h then h.write(textutils.serialize({ mode = mode, last = THEME_NAME })) h.close() end
end

do
  local name, saved = chooseTheme()
  setTheme(name)
  THEME_MODE = saved.mode or CONFIG.theme or "random"
  saveTheme(saved.mode)                             -- remembers 'last' for the next pick
end

C = {
  bg = colors.black, panel = colors.gray, empty = colors.lightGray, head = colors.magenta,
  text = colors.white, dim = colors.brown, ink = colors.black,
  accent = colors.blue, label = colors.lightBlue,
  good = colors.green, warn = colors.yellow, bad = colors.red,
  red = colors.red, purple = colors.purple,
}

-- colours an item can be tinted with
ITEM_COLORS = {
  colors.blue, colors.cyan, colors.green, colors.yellow, colors.orange,
  colors.red, colors.pink, colors.purple, colors.lime,
  colors.lightBlue,
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
function fill(x, y, w, h, bg)
  if w < 1 or h < 1 then return end
  win.setBackgroundColor(bg)
  local line = (" "):rep(w)
  for j = 0, h - 1 do
    win.setCursorPos(x, y + j)
    win.write(line)
  end
end

-- write text into the off-screen window
function text(x, y, s, fg, bg)
  if bg then win.setBackgroundColor(bg) end
  win.setTextColor(fg)
  win.setCursorPos(x, y)
  win.write(s)
end

-- cut a text to n characters (ends with "." when cut)
function trunc(s, n)
  if n <= 0 then return "" end
  if #s <= n then return s end
  if n == 1 then return s:sub(1, 1) end
  return s:sub(1, n - 1) .. "."
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
  return string.format("%.1fm", n / 1000000):gsub("%.0m$", "m")
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
  while true do
    local ev, p = os.pullEventRaw()
    if ev == "timer" and p == id then return end
    if ev == "terminate" then os.cancelTimer(id) return end
    for _, n in ipairs(names) do
      if ev == n then os.cancelTimer(id) return end
    end
  end
end

