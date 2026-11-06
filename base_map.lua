-- base_map.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MAP tab data, from the turtles' Geo Scanner scans, in two layers:
--   - DETAIL: the top block of every column, for the newest chunks
--     (CONFIG.map.maxChunks; the oldest are dropped, also when the disks are full)
--   - OVERVIEW: one value per chunk (its most common top block, average
--     height), kept for every chunk ever scanned - never dropped. Used when
--     zoomed out, and wherever the detail was dropped.
--   Saved as small region files in a "map" folder, on the data floppies first:
--   detail <rx>_<rz>.dat (4 x 4 chunks), overview o<ox>_<oz>.dat (32 x 32
--   chunks). Only changed regions are written, at most once a minute (and on exit).
--   Plus block colours, map rotation and survey spots.

---------------------------------------------------------------------
-- MAP DATA
---------------------------------------------------------------------
-- In memory every layer is TEXT, 4 bytes per cell (height + 64, block number;
-- block 0 = nothing there): text costs the same in every Lua, numbers in
-- tables cost much more in the game's Lua.
--   detail chunk   = { cx, cz, k, r, s, d = 1024 bytes (256 columns), e = edits }
--   overview region = { ox, oz, r, d = 4096 bytes (1024 chunks), e = edits }
--   e = changed cells not yet packed into d (packed after each scan)
MAP = {
  ch = {},         -- [chunk key] = detail chunk
  order = {},      -- detail chunk keys, oldest first (for the size limit)
  ov = {},         -- [overview key] = overview region
  names = {},      -- palette: index -> block name
  nameIdx = {},    -- block name -> index
  scans = 0,
  ovN = 0,         -- chunks in the overview
  tick = 0,        -- goes up with every scan (chunk age)
  version = 0,     -- goes up whenever the map data changes (the page caches its image)
  dirty = {},      -- [file key] = true: must be saved
  where = {},      -- [file key] = path of its file
  savedAt = -1000, -- os.clock() of the last save
}
local REGION = 4           -- detail: chunks per file side (one file = 64 x 64 blocks)
local OVR = 32             -- overview: chunks per file side (one file = 512 x 512 blocks)
local DIR = "map"          -- folder of the map files (computer and data floppies)
local SAVE_EVERY = 60      -- seconds between saves
local floor, char = math.floor, string.char

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, #B64 do DEC[B64:sub(i, i)] = i - 1 end
local function c1(v) return B64:sub(v + 1, v + 1) end
-- 0..4095 -> 2 characters
local function enc2(v)
  v = math.max(0, math.min(4095, floor(v)))
  return c1(floor(v / 64)) .. c1(v % 64)
end
-- 2 characters at position p -> 0..4095 (nil if broken)
local function dec2(s, p)
  local a, b = DEC[s:sub(p, p)], DEC[s:sub(p + 1, p + 1)]
  if not a or not b then return nil end
  return a * 64 + b
end

-- one cell as 4 bytes
-- partial = true (overview only): the chunk was only touched at its edge by a
-- neighbouring scan; kept in the top bit of the height (heights stay < 32768)
local function cell(h, b, partial)
  local v = math.max(0, math.min(32767, floor(h) + 64))
  if partial then v = v + 32768 end
  return char(floor(v / 256), v % 256, floor(b / 256), b % 256)
end
local EMPTY = "\0\0\0\0"
-- cell i (0-based) of a layer: height, block - or nil
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
-- put the edits into the text (after a scan)
local function pack(L, n)
  if not L.e then return end
  local parts, d = {}, L.d
  for i = 0, n - 1 do parts[i + 1] = L.e[i] or d:sub(i * 4 + 1, i * 4 + 4) end
  L.d, L.e = table.concat(parts), nil
end

-- number of a block name in the map's name list (added if new)
function MAP.pal(name)
  local i = MAP.nameIdx[name]
  if not i then
    i = #MAP.names + 1
    MAP.names[i], MAP.nameIdx[name] = name, i
  end
  return i
end

-- key of a chunk (a number: faster than text when drawing)
local function ckey(cx, cz) return (cx + 2097152) * 4194304 + (cz + 2097152) end
-- file keys: detail "rx_rz", overview "o" .. "ox_oz"
local function rkey(cx, cz) return floor(cx / REGION) .. "_" .. floor(cz / REGION) end
local function okey(cx, cz) return "o" .. floor(cx / OVR) .. "_" .. floor(cz / OVR) end

-- the detail chunk at cx, cz (made if `make`)
local function chunkAt(cx, cz, make)
  local k = ckey(cx, cz)
  local c = MAP.ch[k]
  if c or not make then return c end
  c = { cx = cx, cz = cz, k = k, r = rkey(cx, cz), s = MAP.tick, d = EMPTY:rep(256) }
  MAP.ch[k] = c
  MAP.order[#MAP.order + 1] = k
  return c
end

-- the overview region holding chunk cx, cz (made if `make`)
local function ovAt(cx, cz, make)
  local r = okey(cx, cz)
  local o = MAP.ov[r]
  if o or not make then return o end
  o = { ox = floor(cx / OVR), oz = floor(cz / OVR), r = r, d = EMPTY:rep(OVR * OVR) }
  MAP.ov[r] = o
  return o
end

-- height, block of a column (detail), or nil
function MAP.get(x, z)
  local c = MAP.ch[ckey(floor(x / 16), floor(z / 16))]
  if not c then return nil end
  return cellAt(c, (z % 16) * 16 + (x % 16))
end

-- height, block of the chunk that holds x, z (overview), or nil
-- is the chunk of x z really scanned (not just touched at its edge)?
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

-- set a column (detail; the chunk's overview is updated after the scan)
function MAP.set(x, z, h, b)
  MAP.version = MAP.version + 1
  local c = chunkAt(floor(x / 16), floor(z / 16), true)
  c.e = c.e or {}
  c.e[(z % 16) * 16 + (x % 16)] = cell(math.max(-64, h), math.min(65535, b))
  MAP.dirty[c.r] = true
  if MAP.touched then MAP.touched[c.k] = true end
end

-- a chunk's overview value from its detail: most common top block, average
-- height. A chunk only partly scanned (a scan reaches 1 column into the next
-- chunk) only fills an empty overview cell, never replaces a real one.
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
  if had and n < 128 and not wasPartial then return end     -- a real overview: keep it
  if not had then MAP.ovN = MAP.ovN + 1 end
  o.e = o.e or {}
  -- under half the chunk known (only the edge a neighbouring scan reaches):
  -- shown, but marked PARTIAL - the survey still scans this chunk
  o.e[i] = cell(floor(sum / n + 0.5), best, n < 128)
  MAP.dirty[o.r] = true
end

-- chunks scanned again move to the "newest" end, so the size limit drops
-- the chunks that were not scanned for the longest time
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

-- is there anything to show on the MAP tab?
function MAP.hasData() return MAP.scans > 0 or #MAP.order > 0 or next(MAP.ov) ~= nil end

-- number of chunks in the overview (counted on loading, then kept up to date)
local function countOverview()
  local n = 0
  for _, o in pairs(MAP.ov) do
    for i = 0, OVR * OVR - 1 do if cellAt(o, i) then n = n + 1 end end
  end
  MAP.ovN = n
end

-- keep at most `max` detail chunks (default CONFIG.map.maxChunks): drop the
-- oldest (they stay in the overview)
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

-- ===== files =====
-- the "map" folders: data floppies, then the computer. On the computer the
-- map may use at most CONFIG.map.computerKB (default 200 KB).
-- files can be on this computer, a data floppy, or a storage helper
-- ("store:<id>/map/<key>.dat", base_store.lua)
local function dirOf(p) return tostring(p):match("^(.*)/[^/]*$") or "" end
local function mExists(p) if STORE and STORE.isRemote(p) then return true end return fs.exists(p) end
local function mDelete(p)
  if STORE and STORE.isRemote(p) then pcall(STORE.delete, p) else pcall(fs.delete, p) end
end
MAP.rsize = {}        -- sizes of the files on storage helpers (key -> bytes)

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
  out[#out + 1] = { dir = DIR, free = math.max(0, math.min(free, cap)), floppy = false }
  -- storage helpers (after the floppies, before this computer)
  for id, h in pairs(STORE and STORE.helpers or {}) do
    if not h.refused then out[#out + 1] = { dir = "store:" .. id .. "/" .. DIR, free = h.free or 0, remote = id } end
  end
  return out
end

-- n cells as text: per cell the height as the change from the cell before
-- (1 char; "A" + 2 chars = exact height) and the block (1 char; "/" + 2 chars
-- for big numbers), "~" = nothing, "*n" = the cell before n more times,
-- "!" before a cell = PARTIAL (overview: only the edge of the chunk is known)
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

-- text -> n cells as 4-byte text (glob: the file's block numbers -> the map's)
local function readCells(s, n, glob)
  local out, p, i, ph, len = {}, 1, 0, 64, #s
  local last, lastDh, lastAbs, lastB, lastP, nextP = EMPTY, 0, false, 0, false, false
  while p <= len and i < n do
    local ch = s:sub(p, p)
    if ch == "!" then
      nextP, p = true, p + 1                -- the next cell is partial
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

-- the text of one file: its own block-name list, then its lines
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

-- read one map file into memory (old "O" ore lines are skipped)
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
end

-- write one file where it fits: a data floppy first (the one it is on, else
-- the one with the most room), the computer last. true if saved.
local function writeFile(key, text, plc)
  local old = MAP.where[key]
  local need = #text + 4096                       -- the same check as saveFileSafe
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

-- save the changed files (toDisks = also the files still on the computer, so
-- they move onto the data floppies). The overview is saved first; when the
-- detail does not fit, its oldest quarter is dropped (up to four times - the
-- overview keeps those chunks). noTrim = never drop anything.
function MAP.save(toDisks, noTrim)
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
      else                                           -- nothing left in it: delete the file
        if MAP.where[k] and mExists(MAP.where[k]) then mDelete(MAP.where[k]) end
        MAP.where[k], MAP.dirty[k] = nil, nil
      end
    end
    -- overview first: it is the part that is never dropped
    table.sort(keys, function(a, b)
      local ao, bo = a:sub(1, 1) == "o", b:sub(1, 1) == "o"
      if ao ~= bo then return ao end
      return a < b
    end)
    local plc = places()                             -- free space as it is now
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
    -- full: first use any new empty floppy (then simply try again), only then
    -- drop the oldest detail (the overview keeps those chunks)
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

-- save if something changed and the last save is a minute ago (comms worker)
function MAP.autoSave()
  if next(MAP.dirty) and os.clock() - MAP.savedAt >= SAVE_EVERY then
    pcall(MAP.save)
    pcall(MAP.checkSpace)
  end
end

-- ===== floppy space: new empty floppies become map disks, and the owner is
-- told (popup + chat + footer) when the data floppies run low =====
local LOW_KB = 40                 -- warn below this much free on all data floppies together
local lastWarn = -100000

-- make empty floppies data disks (keeps one empty floppy for the turtle
-- installer when there is no installer disk yet). Returns how many
function MAP.claimEmptyFloppies()
  local disks = mountedDisks()
  local hasInstaller = false
  for _, d in ipairs(disks) do if d.installer then hasInstaller = true end end
  local n = 0
  local installDrive = TT and TT.installDrive and TT.installDrive()
  if installDrive then hasInstaller = true end          -- the install drive is for that
  for _, d in ipairs(disks) do
    if d.empty and not d.installer and not d.data and d.name ~= installDrive then
      if not hasInstaller then
        hasInstaller = true          -- this one stays free for the installer
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

-- free room on the data floppies (bytes) and how many there are
function MAP.floppySpace()
  local free, count = 0, 0
  for _, d in ipairs(mountedDisks()) do
    if d.data then free, count = free + (d.free or 0), count + 1 end
  end
  -- storage helpers count as room for the map too
  if STORE then
    local hf, hn = STORE.space()
    free, count = free + hf, count + hn
  end
  return free, count
end

-- after a save: room left? (empty floppies are claimed first)
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
  local dropping = (MAP.lastDrop or 0) > 0             -- room was made by dropping detail
  -- no room for more map: auto-map pauses (MAP.autoTick) until there is
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
  state.diskLow = msg                                  -- stays in the footer until there is room
  if os.clock() - lastWarn >= 1800 or failed and os.clock() - lastWarn >= 300 then
    lastWarn = os.clock()
    setPopup("MAP FLOPPIES", msg, failed and C.bad or C.warn)
    if sysLog then sysLog(msg, failed and "ERROR" or "WARNING") end
    if state.owner then chatTell(state.owner, msg) end
  end
end

-- how much room the map files take: total bytes, on the computer, files
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

-- forget everything (e.g. scans made with wrong coordinates)
function MAP.clear()
  MAP.version = MAP.version + 1
  for _, p in pairs(MAP.where) do if mExists(p) then mDelete(p) end end
  MAP.ch, MAP.order, MAP.ov, MAP.where, MAP.dirty = {}, {}, {}, {}, {}
  MAP.names, MAP.nameIdx = {}, {}
  MAP.scans, MAP.tick, MAP.ovN = 0, 0, 0
  for _, p in ipairs({ CONFIG.map.file, dataFile(CONFIG.map.file, true) }) do
    if fs.exists(p) then pcall(fs.delete, p) end
  end
end

-- the old single map file (map.dat, before region files): read it once
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
        MAP.tick = MAP.tick + 1                      -- the file lists chunks oldest first
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
    end                                              -- ores ("O" lines) are not kept
  end
  h.close()
  return true
end

-- read every map file (computer and data floppies); convert an old map.dat;
-- build the overview of chunks that have none yet
function MAP.load()
  -- the storage helpers first (their list is needed for places())
  if STORE and next(STORE.known) then pcall(STORE.find, true) end   -- only helpers seen before (fast)
  for _, p in ipairs(places()) do
    if p.remote then
      -- a storage helper: list its map files, read them in a few big requests
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
        if got == 0 then break end                 -- helper gone: the rest stays unread this time
        i = i + got
      end
    elseif fs.exists(p.dir) and fs.isDir(p.dir) then
      for _, f in ipairs(fs.list(p.dir)) do
        local k = f:match("^(o?%-?%d+_%-?%d+)%.dat$")
        if k and not MAP.where[k] then              -- a file twice: the first one counts
          MAP.where[k] = fs.combine(p.dir, f)
          pcall(readFile, MAP.where[k])
          -- an old detail file with ore lines: write it again without them
          if k:sub(1, 1) ~= "o" then
            local h = fs.open(MAP.where[k], "r")
            local t = h and h.readAll() or ""
            if h then h.close() end
            if t:find("\nO ", 1, true) then MAP.dirty[k] = true end
          end
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
  -- every detail chunk must be in the overview (older saves had no overview)
  countOverview()
  -- and older saves stored edge-only chunks as if they were fully mapped:
  -- summarize again (marks them partial, so a survey scans them properly)
  for _, c in pairs(MAP.ch) do
    local h, _, partial = MAP.getOverview(c.cx * 16, c.cz * 16)
    if not h or not partial then summarize(c) end
  end
  for _, o in pairs(MAP.ov) do pack(o, OVR * OVR) end
  table.sort(MAP.order, function(a, b) return MAP.ch[a].s < MAP.ch[b].s end)
  MAP.trim()
  if next(oldFiles) then
    -- the old file goes once everything is saved; if the map does not fit next
    -- to it, it goes first (everything is in memory) and the map gets its room
    local ok = MAP.save(false, true)
    for f in pairs(oldFiles) do pcall(fs.delete, f) end
    if not ok then MAP.save() end
  end
  MAP.version = MAP.version + 1
end

-- a scan summary from a turtle (node.lua): absolute centre + relative data
-- (the ores it also sends are not kept)
function MAP.addScan(m)
  if type(m.cols) ~= "table" or type(m.names) ~= "table" then return end
  local x0, y0, z0 = tonumber(m.x), tonumber(m.y), tonumber(m.z)
  if not (x0 and y0 and z0) then return end
  local r = floor(tonumber(m.r) or 8)
  local n = 2 * r + 1
  local remap = {}
  for i, nm in ipairs(m.names) do remap[i] = MAP.pal(tostring(nm)) end
  MAP.tick = MAP.tick + 1
  MAP.touched = {}
  -- Merge by height: each column keeps the HIGHEST block ever seen. A scan
  -- only sees y0-r .. y0+r, so a lower result replaces the stored one only if
  -- this scan could see the stored height (then that block is really gone).
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
  -- pack the changed chunks and update their overview
  for k in pairs(touched) do
    local c = MAP.ch[k]
    pack(c, 256)
    summarize(c)
  end
  for _, o in pairs(MAP.ov) do pack(o, OVR * OVR) end
  -- the scanned square also counts as fresh where nothing new was stored
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

-- map colour of a block (cached: the same names come up thousands of times)
local colorCache = {}
-- screen colour of a block (cached)
function MAP.colorOf(name)
  local c = colorCache[name]
  if c then return c end
  c = MAP.colorOfRaw(name)
  colorCache[name] = c
  return c
end
-- screen colour of a block, guessed from its name
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
  return colors.brown       -- stone, deepslate, buildings: neutral grey-blue
end

-- the map view (centre, zoom, layers, rotation 0 north up .. 3 west up)
local UPS = { north = 0, east = 1, south = 2, west = 3 }
local VIEW_FILE = "map_view.dat"

-- the map view (centre, zoom, rotation); starts at Base
function MAP.view()
  if not state.mapView then
    local h = CONFIG.drone and CONFIG.drone.home
    local rot = UPS[tostring(CONFIG.map.up or "north"):lower()] or 0
    local cx, cz, zoom = h and h.x or 0, h and h.z or 0, 1
    if fs.exists(VIEW_FILE) then                    -- rotation, zoom and position survive restarts
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

-- save the map rotation (ROTATE) for the next start
-- remember rotation, zoom and position (MAP tab) for the next start
function MAP.saveView()
  local V = MAP.view()
  saveFileSafe(VIEW_FILE, textutils.serialize({ rot = V.rot, zoom = V.zoom, cx = V.cx, cz = V.cz }))
end

-- the world area the map currently shows (x1, z1, x2, z2)
function MAP.viewArea()
  local g, V = state.mapGeom, MAP.view()
  if not g then return nil end
  local B = MAP.basis()
  local hw, hh = g.mw / 2 * V.zoom, g.mh / 2 * V.zoom * 1.5
  local hx = math.floor(math.abs(B.rx) * hw + math.abs(B.dx) * hh)
  local hz = math.floor(math.abs(B.rz) * hw + math.abs(B.dz) * hh)
  return V.cx - hx, V.cz - hz, V.cx + hx, V.cz + hz
end

-- scan spots (one per scan-width) for an area, leaving out the ones that are
-- already mapped; returns the spots and how many were skipped
function MAP.surveySpots(x1, z1, x2, z2, r)
  local step = 2 * r + 1
  local spots, skipped = {}, 0
  local need = CONFIG.map.skipKnown or 0.8
  for z = z1 + r, z2 + r, step do
    for x = x1 + r, x2 + r, step do
      local known, total = 0, 0
      for dx = -r, r, 2 do                 -- every 2nd column is plenty to judge
        for dz = -r, r, 2 do
          total = total + 1
          if MAP.get(x + dx, z + dz) then known = known + 1 end
        end
      end
      if known / total >= need or MAP.scanned(x, z) then skipped = skipped + 1
      else spots[#spots + 1] = { x, z } end
    end
  end
  return spots, skipped
end

-- ===== SURVEY QUEUE: big areas, handed to the turtles in batches =====
-- A big area has far too many scan spots to send at once (a turtle takes at
-- most 400 per order). The base keeps the area and a cursor; every idle turtle
-- gets the next BATCH spots, until the area is done. Spots whose chunk is
-- already in the map (overview) are skipped. Kept in a file: continues after
-- a restart.
local QUEUE_FILE = "survey_queue.dat"
local BATCH = 64
MAP.queue = nil      -- { x1, z1, x2, z2, r, cols, rows, cursor, sent, skipped, ids = {...} }

local function saveQueue()
  if MAP.queue then saveFileSafe(QUEUE_FILE, textutils.serialize(MAP.queue))
  elseif fs.exists(QUEUE_FILE) then pcall(fs.delete, QUEUE_FILE) end
end
do
  if fs.exists(QUEUE_FILE) then
    local h = fs.open(QUEUE_FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" and t.cols then MAP.queue = t end
  end
end

-- start a queued survey of an area (ids = the turtles to use, nil = all free ones)
function MAP.queueSurvey(x1, z1, x2, z2, r, ids)
  -- you started it: the turtles it uses are no longer held by an old STOP
  for _, id in ipairs(ids or TT.available()) do
    local t = state.turtles[id]
    if t and t.held then t.held = nil TT.listDirty = true end
  end
  local step = 2 * r + 1
  local old = MAP.queue
  if old and old.auto then MAP.auto.cursor = old.cursor MAP.saveAuto() end     -- auto-map goes on later from here
  MAP.queue = { x1 = x1, z1 = z1, x2 = x2, z2 = z2, r = r, step = step,
                cols = math.max(1, math.floor((x2 - x1) / step) + 1),
                rows = math.max(1, math.floor((z2 - z1) / step) + 1),
                cursor = 0, sent = 0, skipped = 0, ids = ids }
  if old then MAP.queue.redo, MAP.queue.out = old.redo, old.out end   -- nothing handed out is lost
  saveQueue()
  return MAP.queue.cols * MAP.queue.rows
end

-- is a survey spot done? Its own scan arrived (the spot's column is in the
-- detail layer), or its chunk is fully in the overview. (Spots are 17 blocks
-- apart, chunks 16: a done spot's chunk can stay half-covered until the
-- neighbouring spot is scanned - that is not "undone".)
function MAP.spotDone(x, z)
  return MAP.get(x, z) ~= nil or MAP.scanned(x, z)
end

-- n-th position (0, 1, 2 ...) of a square spiral around 0,0: the centre first,
-- then ring after ring outward
local function spiral(n)
  if n == 0 then return 0, 0 end
  local k = math.ceil((math.sqrt(n + 1) - 1) / 2)    -- the ring
  local side = 2 * k
  local first = (2 * k - 1) * (2 * k - 1)            -- index of the ring's first spot
  local m = n - first
  if m < side then return k, -k + 1 + m end           -- right side, going up
  m = m - side
  if m < side then return k - 1 - m, k end            -- top, going left
  m = m - side
  if m < side then return -k, k - 1 - m end           -- left side, going down
  m = m - side
  return -k + 1 + m, -k                               -- bottom, going right
end
MAP.spiral = spiral

-- ===== AUTO-MAP: always a survey running, from the base outward =====
-- When no survey is running, the base starts (or continues) one that spirals
-- out from the base over the whole world, and hands it out like any survey.
-- Paused while the map floppies are full; ends at the world border. Your own
-- surveys go first; auto-map continues where it was afterwards.
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
function MAP.saveAuto() saveFileSafe(AUTO_FILE, textutils.serialize(MAP.auto)) end
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

-- comms worker: start / continue auto-map when nothing else runs
function MAP.autoTick()
  local a = MAP.auto
  if not a.on or a.done or MAP.queue or MAP.full then return end
  local c = CONFIG.drone.home or state.basePos
  if not (c and c.x) or #TT.available() == 0 then return end
  local r = CONFIG.map.scanRadius or 8
  local step = 2 * r + 1
  local border = tonumber(CONFIG.map.border) or 20000
  local rad = math.ceil((border + math.max(math.abs(c.x), math.abs(c.z))) / step)
  MAP.queue = { auto = true, spiral = true, cx = math.floor(c.x), cz = math.floor(c.z), r = r, step = step,
                cols = 2 * rad + 1, rows = 2 * rad + 1, cursor = a.cursor or 0, sent = 0, skipped = 0 }
  saveQueue()
  setToast("Auto-map: surveying on from the base outward (" ..
           math.floor(MAP.autoRadius() + 0.5) .. " blocks done around it)", C.label)
end

-- how far around the base auto-map has got (blocks)
function MAP.autoRadius()
  local q = MAP.queue
  local cur = (q and q.auto) and q.cursor or (MAP.auto.cursor or 0)
  local step = (q and q.step) or (2 * (CONFIG.map.scanRadius or 8) + 1)
  return math.max(0, math.ceil((math.sqrt(cur + 1) - 1) / 2) - 1) * step
end

function MAP.stopSurvey()
  if MAP.queue and MAP.queue.auto then
    -- stopping auto-map = turning it off (else it would start again at once)
    MAP.auto.cursor, MAP.auto.on = MAP.queue.cursor, false
    MAP.saveAuto()
  end
  MAP.queue = nil
  saveQueue()
end

-- the next batch of spots not yet in the map (checks a limited number per call)
local function nextBatch(q)
  local total = q.cols * q.rows
  local out, checked = {}, 0
  -- first the spots a turtle gave back unscanned (see MAP.reclaim)
  while q.redo and #q.redo > 0 and #out < BATCH do
    local p = table.remove(q.redo, 1)
    if not MAP.spotDone(p[1], p[2]) then out[#out + 1] = p end
  end
  if #out >= BATCH then return out end
  while #out < BATCH and q.cursor < total and checked < 3000 do
    local i = q.cursor
    q.cursor = q.cursor + 1
    checked = checked + 1
    local x, z
    if q.spiral then
      -- auto-map: a spiral from the base outward
      local dx, dz = spiral(i)
      x, z = q.cx + dx * q.step, q.cz + dz * q.step
    else
      -- snake order: every other row backwards, so a turtle never jumps back
      local row, col = math.floor(i / q.cols), i % q.cols
      if row % 2 == 1 then col = q.cols - 1 - col end
      x, z = q.x1 + q.r + col * q.step, q.z1 + q.r + row * q.step
    end
    local border = tonumber(CONFIG.map.border) or 20000
    if math.abs(x) > border or math.abs(z) > border then
      -- outside the world border: nothing to do
    elseif MAP.spotDone(x, z) then q.skipped = q.skipped + 1
    else out[#out + 1] = { x, z } end
  end
  return out
end

-- A turtle stopped working on its batch (finished, failed, low on fuel, gave
-- up after restarts, result lost ...): every spot of it that is still not in
-- the map goes back into the queue (q.redo) for the next free turtle. Safe to
-- call any time - scanned spots are simply dropped.
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

-- a turtle answered its survey batch (TT.receive): done -> forget the batch;
-- failed -> its unscanned spots go back into the queue
function MAP.batchResult(id, ok)
  local q = MAP.queue
  if not (q and q.out and q.out[id]) then return end
  local n = MAP.reclaim(id)
  if n > 0 then
    local t = state.turtles[id]
    TT.log(t, n .. " survey spot(s) not done - back in the queue for the next free turtle")
  end
end

-- a survey of a small area (SURVEY: ALL): its spots join the running survey,
-- or become a new one - either way kept in the queue file and handed out in
-- batches, so nothing is lost when a turtle stops
function MAP.addSurvey(x1, z1, x2, z2, r)
  local spots, skipped = MAP.surveySpots(x1, z1, x2, z2, r)
  if #spots == 0 then return 0, skipped end
  local q = MAP.queue
  if not q then
    MAP.queueSurvey(x1, z1, x2, z2, r, nil)
    return #spots, skipped
  end
  q.redo = q.redo or {}
  for i = #spots, 1, -1 do table.insert(q.redo, 1, spots[i]) end    -- before the rest
  for _, id in ipairs(TT.available()) do
    local t = state.turtles[id]
    if t and t.held then t.held = nil TT.listDirty = true end
  end
  saveQueue()
  return #spots, skipped
end

-- hand batches to idle turtles (comms worker, every few seconds)
function MAP.feedSurvey()
  local q = MAP.queue
  if not q then return end
  if q.auto and MAP.full then return end           -- auto-map waits for room on the floppies
  local total = q.cols * q.rows
  local minFuel = tonumber(CONFIG.map.surveyMinFuel) or 500
  local busy, why, anyFree = false, {}, false
  local list = q.ids or TT.available()
  for _, id in ipairs(list) do
    local t = state.turtles[id]
    local free = t and TT.online(t) and t.pos and t.pos.x and (t.task == nil or t.task == "idle") and not t.anchor
                 and not (q.excluded and q.excluded[id])      -- stopped by the owner
                 and not t.rescuerRole and not t.held         -- the rescuer stays free; STOPPED stays stopped
    local fuel = t and tonumber(t.fuel)
    if free and t.queueAt and os.clock() - t.queueAt < 15 then free = false busy = true end
    if free and fuel and fuel < minFuel then free = false end
    if t and not free and t.task and t.task ~= "idle" then busy = true end
    -- why this turtle gets nothing (told to you when nobody works)
    if t and not free then
      local w
      if not TT.online(t) then w = "offline"
      elseif not (t.pos and t.pos.x) then w = "position unknown"
      elseif t.task and t.task ~= "idle" then w = "busy"
      elseif t.held or (q.excluded and q.excluded[id]) then w = "STOPPED - give it a command first"
      elseif fuel and fuel < minFuel then w = "fuel " .. fuel .. " (needs " .. minFuel .. ")"
      elseif t.anchor then w = "anchor" elseif t.rescuerRole then w = "rescuer" end
      if w then why[#why + 1] = (t.label or ("#" .. id)) .. ": " .. w end
    end
    if free then anyFree = true end
    -- idle while the base still counts a batch as theirs: take it back
    -- (whatever was scanned is dropped; the rest is handed out again)
    if t and q.out and q.out[id] and TT.online(t) and (t.task == nil or t.task == "idle")
       and (not t.queueAt or os.clock() - t.queueAt > 30) then
      MAP.reclaim(id)
    end
    if free and (q.cursor < total or (q.redo and #q.redo > 0)) then
      local spots = nextBatch(q)
      if #spots > 0 then
        TT.sendSpots(id, spots, q.r)
        q.out = q.out or {}
        q.out[id] = spots
        t.queueAt = os.clock()
        q.sent = q.sent + #spots
        busy = true
      end
    end
  end
  -- no turtle CAN work on it: say why - once, again only when the reason
  -- changes or after 10 minutes (a free turtle that is just skipping
  -- already-mapped spots is not a problem)
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
  saveQueue()
end

-- progress for the screen: done fraction, spots total
function MAP.surveyProgress()
  local q = MAP.queue
  if not q then return nil end
  local total = q.cols * q.rows
  local again = q.redo and #q.redo or 0
  return q.cursor / total, total, q.sent, q.skipped, again
end

-- one screen cell to the right (r) and one down (d), as world x/z steps
local BASIS = {
  [0] = { rx = 1,  rz = 0,  dx = 0,  dz = 1 },   -- up north: right = east,  down = south
  [1] = { rx = 0,  rz = 1,  dx = -1, dz = 0 },   -- up east:  right = south, down = west
  [2] = { rx = -1, rz = 0,  dx = 0,  dz = -1 },  -- up south: right = west,  down = north
  [3] = { rx = 0,  rz = -1, dx = 1,  dz = 0 },   -- up west:  right = north, down = east
}
-- direction vectors for the current rotation
function MAP.basis() return BASIS[(MAP.view().rot or 0) % 4] end

-- screen offset (cells from the centre) -> world x, z
-- (a cell is about 1.5x taller than wide, so one row covers 1.5x more ground)
function MAP.toWorld(sx, sy)
  local V, B = MAP.view(), MAP.basis()
  local a, b = sx * V.zoom, sy * V.zoom * 1.5
  return V.cx + math.floor(a * B.rx + b * B.dx), V.cz + math.floor(a * B.rz + b * B.dz)
end

-- world x, z -> screen offset (cells from the centre)
function MAP.toCell(x, z)
  local V, B = MAP.view(), MAP.basis()
  local ddx, ddz = x - V.cx, z - V.cz
  return (ddx * B.rx + ddz * B.rz) / V.zoom, (ddx * B.dx + ddz * B.dz) / (V.zoom * 1.5)
end

local DIRL = { [0] = "N", "E", "S", "W" }
local DIRN = { [0] = "NORTH", "EAST", "SOUTH", "WEST" }
-- letters for the top, right, bottom and left edge, and the name of "up"
function MAP.compass()
  local r = (MAP.view().rot or 0) % 4
  return DIRL[r], DIRL[(r + 1) % 4], DIRL[(r + 2) % 4], DIRL[(r + 3) % 4], DIRN[r]
end

MAP.load()
