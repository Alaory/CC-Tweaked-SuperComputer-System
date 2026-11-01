-- Part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.

---------------------------------------------------------------------
-- THEME
---------------------------------------------------------------------
PALETTE = {
  [colors.black]     = 0x0B0E14, -- page background
  [colors.gray]      = 0x151A26, -- cards
  [colors.magenta]   = 0x1F2636, -- separator lines
  [colors.lightGray] = 0x262E42, -- empty slots / bar tracks / idle buttons
  [colors.white]     = 0xE8ECF4, -- main text
  [colors.brown]     = 0x7D879F, -- dim text
  [colors.blue]      = 0x6C9CFF, -- accent
  [colors.lightBlue] = 0x8ED1FF, -- titles
  [colors.cyan]      = 0x40DCC4,
  [colors.green]     = 0x5EE38F,
  [colors.yellow]    = 0xF6C744,
  [colors.orange]    = 0xFF9F5C,
  [colors.red]       = 0xFF6B6B,
  [colors.pink]      = 0xFF7DC4,
  [colors.purple]    = 0xB49CFF,
  [colors.lime]      = 0xB5E35B,
}

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

function applyPalette(dev)
  for c, rgb in pairs(PALETTE) do dev.setPaletteColor(c, rgb) end
end

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
function saveFileSafe(path, text)
  local dir = fs.getDir(path)
  local okF, free = pcall(fs.getFreeSpace, dir == "" and "/" or dir)
  if okF and type(free) == "number" and free < #text + 4096 then
    state.diskLow = string.format("DISK ALMOST FULL: %s not saved (%d KB free, needs %d KB)",
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

function text(x, y, s, fg, bg)
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

-- every item gets its own colour while there are free ones
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

