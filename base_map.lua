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
-- (cached by number: the map draws look this up thousands of times, and
-- building the text every time is slow in the game's Lua)
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
-- copies on a helper that could not be deleted (it did not answer): an OLD copy -
-- never read again, deleted once the helper answers (map_stale.dat)
local STALE_FILE = "map_stale.dat"
MAP.stale = readSafe(STALE_FILE)
if type(MAP.stale) ~= "table" then MAP.stale = {} end
for k in pairs(MAP.stale) do if type(k) ~= "string" then MAP.stale[k] = nil end end
local function saveStale() writeSafe(STALE_FILE, serialSmall(MAP.stale)) end
local function mDelete(p)
  if STORE and STORE.isRemote(p) then
    local okD, done = pcall(STORE.delete, p)
    if not (okD and done) then MAP.stale[p] = true saveStale() end
  else pcall(fs.delete, p) end
end
MAP.rsize = {}        -- sizes of the files on storage helpers (key -> bytes)

-- storage helpers FIRST (CONFIG.map.helpersFirst, default on): 1 MB each, and the
-- data floppies stay free for the other data files (drone logs, turtles, mining,
-- voice ...). Before, the map filled the floppies to the last KB and the helpers
-- got nothing until then - "DISK ALMOST FULL: disk/drone_logs.dat not saved" with
-- 4 empty helpers.
function MAP.helpersFirst()
  local m = CONFIG.map or {}
  if m.helpersFirst == false then return false end
  local hf = STORE and STORE.space() or 0
  return hf >= 64 * 1024
end
-- room the map leaves on every data floppy for the other data files
function MAP.floppyKeep()
  local m = CONFIG.map or {}
  local kb = tonumber(m.floppyKeepKB)
  if not kb then kb = MAP.helpersFirst() and 48 or 16 end
  return kb * 1024
end
-- the places whose map files were READ this run (MAP.readAt[dir] = the floppy's id / true): only those
-- are written to - a helper that did not answer at the start, or a floppy that was out of its drive, still
-- holds older files of the same names; writing there first would overwrite them unread
MAP.readAt = {}
MAP.extra = {}        -- [key] = { paths } - more copies of a file found (joined; deleted once it is saved)
local function floppyId(d) return d.id ~= nil and tostring(d.id) or true end
local function isRead(dir, id)
  local r = MAP.readAt[dir]
  return r ~= nil and (id == nil or r == true or id == true or r == id)
end
local function places()
  local out = {}
  local fkeep = MAP.floppyKeep()
  for _, d in ipairs(mountedDisks()) do
    if d.data then
      local dir = fs.combine(d.mount, DIR)
      local id = floppyId(d)
      -- (a floppy without a map folder has nothing to overwrite: it counts as read)
      if MAP.loaded and not isRead(dir, id) and not fs.exists(dir) then MAP.readAt[dir] = id end
      if not MAP.loaded or isRead(dir, id) then
        out[#out + 1] = { dir = dir, free = math.max(0, (d.free or 0) - fkeep), floppy = true, id = id }
      end
    end
  end
  local okF, free = pcall(fs.getFreeSpace, "/")
  free = okF and free or 0
  local onPc = 0
  for _, p in pairs(MAP.where) do
    if dirOf(p) == DIR and fs.exists(p) then onPc = onPc + fs.getSize(p) end
  end
  local cap = (tonumber(CONFIG.map.computerKB) or 200) * 1024 - onPc
  -- never the last KB: the other data files (turtles, survey queue, logs ...) need them
  local keep = (tonumber(CONFIG.map.keepFreeKB) or 96) * 1024
  out[#out + 1] = { dir = DIR, free = math.max(0, math.min(free - keep, cap)), floppy = false }
  -- storage helpers (after the floppies, before this computer)
  for id, h in pairs(STORE and STORE.helpers or {}) do
    local dir = "store:" .. id .. "/" .. DIR
    if STORE.usable(h) and (not MAP.loaded or isRead(dir)) then out[#out + 1] = { dir = dir, free = h.free or 0, remote = id } end
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

-- two layers of 4-byte cells -> one: what memory has stays (it is newer), its EMPTY cells - and its
-- partial ones where the file knows the whole chunk - come from the file. Returns the text, took anything
local function mergeCells(old, new, n)
  if old == new then return old, false end
  local parts, took = {}, false
  for i = 0, n - 1 do
    local a = old:sub(i * 4 + 1, i * 4 + 4)
    local b = new:sub(i * 4 + 1, i * 4 + 4)
    local use = a
    if b ~= a and #b == 4 then
      local b3, b4 = b:byte(3, 4)
      if b3 ~= 0 or b4 ~= 0 then                      -- (the file knows this cell)
        local a3, a4 = a:byte(3, 4)
        if (a3 == 0 and a4 == 0) or (a:byte(1) >= 128 and b:byte(1) < 128) then use = b end
      end
    end
    if use ~= a then took = true end
    parts[i + 1] = use
  end
  return table.concat(parts), took
end

-- read one map file into memory (old "O" ore lines are skipped). A key already in memory (the same
-- file found TWICE, or read LATE - a helper / floppy that was away at the start, while new scans came in)
-- is JOINED with it, never replaced: before, the copy read first "counted" and the other one was lost.
-- Returns true when the file added something to what was in memory already.
local function readText(text)
  local glob, nloc = {}, 0
  local took = false
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local tag = line:sub(1, 1)
    if tag == "P" then
      glob[nloc] = MAP.pal(line:sub(3))
      nloc = nloc + 1
    elseif tag == "K" then
      local cx, cz, s, data = line:match("^K (%-?%d+) (%-?%d+) (%d+) (.*)$")
      if data then
        local had = chunkAt(tonumber(cx), tonumber(cz))
        local c = chunkAt(tonumber(cx), tonumber(cz), true)
        local fs_, d = tonumber(s), readCells(data, 256, glob)
        if not had then
          c.s, c.d = fs_, d
        else
          pack(c, 256)
          if not MAP.loaded and fs_ > (c.s or 0) then        -- (two copies at the start: the newer scan)
            if c.d ~= d then took = true end
            c.s, c.d = fs_, d
          else
            local t
            c.d, t = mergeCells(c.d, d, 256)
            took = took or t
          end
        end
        if fs_ > MAP.tick then MAP.tick = fs_ end
      end
    elseif tag == "V" then
      local ox, oz, data = line:match("^V (%-?%d+) (%-?%d+) (.*)$")
      if data then
        local had = ovAt(tonumber(ox) * OVR, tonumber(oz) * OVR)
        local o = ovAt(tonumber(ox) * OVR, tonumber(oz) * OVR, true)
        local d = readCells(data, OVR * OVR, glob)
        if not had then o.d = d
        else
          pack(o, OVR * OVR)
          local t
          o.d, t = mergeCells(o.d, d, OVR * OVR)
          took = took or t
        end
      end
    end
  end
  return took
end
local function readFile(path)
  local h = fs.open(path, "r")
  if not h then return end
  local t = h.readAll()
  h.close()
  local took = readText(t)
  return t, took
end
-- loading in the background (map worker): let the screen and the other
-- workers run between files (no sleep - an event comes back at once)
local function loadYield()
  if MAP.loading and MAP.canYield and TT and TT.yieldCo == coroutine.running() then   -- (only in the map worker)
    os.queueEvent("map_loading")
    os.pullEvent("map_loading")
  end
end

-- write one file where it fits: a data floppy first (the one it is on, else
-- the one with the most room), the computer last. true if saved.
local function writeFile(key, text, plc)
  local old = MAP.where[key]
  local need = #text + 4096                       -- the same check as saveFileSafe
  local order = {}
  for _, p in ipairs(plc) do order[#order + 1] = p end
  local hFirst = MAP.helpersFirst()
  local function rank(p)
    if p.remote then return hFirst and 4 or 2 end
    return p.floppy and 3 or 1
  end
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
        if not ok then p.free = 0 end                 -- (no answer / full: not again in this save)
        if ok then
          MAP.rsize[key] = #text
          if MAP.stale[path] then MAP.stale[path] = nil saveStale() end   -- (current again)
        end
      else
        pcall(fs.makeDir, p.dir)
        ok = saveFileSafe(path, text)
      end
      if ok then
        if old and old ~= path and mExists(old) then
          mDelete(old)
          if not (STORE and STORE.isRemote(old)) and fs.exists(old) then pcall(fs.delete, old) end   -- (two copies: the old one read first)
        end
        if not p.remote then MAP.rsize[key] = nil end
        -- more copies found at the start / read late: joined into this one - they go now
        for _, xp in ipairs(MAP.extra[key] or {}) do
          if xp ~= path and mExists(xp) then mDelete(xp) end
        end
        MAP.extra[key] = nil
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
  if not MAP.loaded then return false end          -- half-read map: never written over the files
  pcall(MAP.readLate)                              -- (a place back since the start: read it first)
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
    -- NOT a lack of room (a storage helper did not answer in time, ...): the files stay changed and
    -- are written at the next save - nothing is dropped. (Before: one slow helper = "the floppies
    -- are full" AND the oldest quarter of the map detail thrown away.)
    local need, room = 0, 0
    for k in pairs(MAP.dirty) do need = need + #(texts[k] or "") + 4096 end
    for _, pl in ipairs(places()) do room = room + (pl.free or 0) end
    if STORE then room = room + STORE.space(true) - STORE.space() end   -- (quiet helpers: room still there)
    if room >= need * 2 + 64 * 1024 then
      MAP.saveWhy = (STORE and STORE.quietList() ~= "") and ("storage helper(s) " .. STORE.quietList() .. " did not answer")
                    or "could not write every file"
      break
    end
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

-- map files on THIS computer move to the data floppies / storage helpers when
-- they have room: only CHANGED files are written, so the ones saved on the
-- computer before (no floppy / helper yet, or they were full) stayed there and
-- filled its 1 MB. mapWorker: every 10 min, every minute when the disk is low.
-- Returns how many moved.
-- With storage helpers (MAP.helpersFirst) the map files on the DATA FLOPPIES move
-- onto them too, at most `max` (60) per call: the floppies are then free for the
-- other data files.
function MAP.offload(max)
  if not MAP.loaded then return 0, nil end
  local before, onFloppy = 0, {}
  local hFirst = MAP.helpersFirst()
  for k, p in pairs(MAP.where) do
    if dirOf(p) == DIR then before = before + 1
    elseif hFirst and not (STORE and STORE.isRemote(p)) then onFloppy[#onFloppy + 1] = k end
  end
  if before == 0 and #onFloppy == 0 then return 0, 0 end
  local room = 0
  for _, pl in ipairs(places()) do if pl.floppy or pl.remote then room = room + (pl.free or 0) end end
  if room < 8192 then return 0, 0 end
  -- the FULLEST floppy first (the owner: "disk2/mining.dat not saved (5 KB free)" while
  -- the files went in name order, a few a minute, from every floppy at once)
  local freeOf = {}
  for _, d in ipairs(mountedDisks()) do freeOf[d.mount] = d.free or 0 end
  local function fr(k) return freeOf[tostring(MAP.where[k]):match("^([^/]+)/") or ""] or 0 end
  table.sort(onFloppy, function(a, b)
    local fa, fb = fr(a), fr(b)
    if fa ~= fb then return fa < fb end
    return a < b                                   -- (the same order every time)
  end)
  local limit = max or 60
  local picked = {}
  local wasDirty = {}
  local hRoom = (STORE and STORE.space() or 0) - 32 * 1024   -- (only what fits on the helpers)
  local nPick = 0
  for i = 1, math.min(limit, #onFloppy) do
    local k = onFloppy[i]
    local okS, sz = pcall(fs.getSize, MAP.where[k])   -- (its floppy may be out of the drive)
    local size = (okS and tonumber(sz) or 0) + 4096
    if size > hRoom then break end
    hRoom = hRoom - size
    nPick = nPick + 1
    picked[k] = MAP.where[k]
    wasDirty[k] = MAP.dirty[k]
    MAP.dirty[k] = true
  end
  pcall(MAP.save, true, true)                      -- (never drops anything)
  for k, was in pairs(picked) do                   -- no room for it: it simply stays where it is
    if MAP.dirty[k] and not wasDirty[k] and MAP.where[k] == was and fs.exists(was) then MAP.dirty[k] = nil end
  end
  local after, toHelpers = 0, 0
  for k, p in pairs(MAP.where) do if dirOf(p) == DIR then after = after + 1 end end
  for k, was in pairs(picked) do
    if MAP.where[k] ~= was and STORE and STORE.isRemote(MAP.where[k] or "") then toHelpers = toHelpers + 1 end
  end
  local moved = before - after
  if moved > 0 and sysLog then
    sysLog("Map: moved " .. moved .. " map file(s) off this computer onto the " ..
           (hFirst and "storage helpers / floppies" or "floppies / storage helpers") ..
           (after > 0 and (" (" .. after .. " still here - no room left)") or ""), "INFO")
  end
  if toHelpers > 0 and sysLog then
    sysLog("Map: moved " .. toHelpers .. " map file(s) from the data floppies onto the storage helpers" ..
           (#onFloppy > toHelpers and (" (" .. (#onFloppy - toHelpers) .. " to go)") or ""), "INFO")
  end
  if nPick == 0 then return moved, 0 end             -- the helpers are full: nothing more moves
  return moved + toHelpers, #onFloppy - toHelpers
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
  -- storage helpers count as room for the map too (also one that is quiet right now: not "full")
  if STORE then
    local hf, hn = STORE.space(true)
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
  -- not saved, but there IS room (a storage helper did not answer in time): say THAT, and only when
  -- it lasts 10 min - not "the floppies are full, add a floppy" (the owner: "I have a lot of storage,
  -- why do I keep getting that error")
  if failed and free >= LOW_KB * 1024 * 4 then
    MAP.full = false
    MAP.failSince = MAP.failSince or os.clock()
    local msg = "Map: some changes wait to be saved - " .. tostring(MAP.saveWhy or "a write did not work") ..
                " (tries again every minute)"
    if os.clock() - MAP.failSince >= 600 then
      state.diskLow = msg
      if os.clock() - lastWarn >= 1800 then
        lastWarn = os.clock()
        if sysLog then sysLog(msg, "WARNING") end
      end
    end
    return
  end
  if not failed then MAP.failSince, MAP.saveWhy = nil, nil end
  if state.diskLow and state.diskLow:find("wait to be saved", 1, true) and not failed then state.diskLow = nil end
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
  local total, onPc, files, remote, rfiles = 0, 0, 0, 0, 0
  for k, p in pairs(MAP.where) do
    if STORE and STORE.isRemote(p) then
      total, files = total + (MAP.rsize[k] or 0), files + 1
      remote, rfiles = remote + (MAP.rsize[k] or 0), rfiles + 1
    elseif fs.exists(p) then
      local s = fs.getSize(p)
      total, files = total + s, files + 1
      if dirOf(p) == DIR then onPc = onPc + s end
    end
  end
  return total, onPc, files, remote, rfiles      -- (remote = on the storage helpers)
end

-- forget everything (e.g. scans made with wrong coordinates)
function MAP.clear()
  if not MAP.loaded then return false end          -- still reading it: the rest would come back
  MAP.version = MAP.version + 1
  for _, p in pairs(MAP.where) do if mExists(p) then mDelete(p) end end
  for _, list in pairs(MAP.extra) do for _, p in ipairs(list) do if mExists(p) then mDelete(p) end end end
  MAP.ch, MAP.order, MAP.ov, MAP.where, MAP.dirty, MAP.extra = {}, {}, {}, {}, {}, {}
  MAP.names, MAP.nameIdx = {}, {}
  MAP.scans, MAP.tick, MAP.ovN = 0, 0, 0
  for _, p in ipairs({ CONFIG.map.file, dataFile(CONFIG.map.file, true) }) do
    if fs.exists(p) then pcall(fs.delete, p) end
  end
  return true
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
-- the map files of ONE place (a data floppy, the computer, a storage helper) into memory. Only files that
-- really came back count as read (before: a helper that stopped answering half way had ALL its files
-- marked as read - the next save wrote over the unread ones). A file of a key that is already known
-- (found twice / read late) is JOINED (readText) and the extra copy goes once the key is saved again.
-- true = every file of that place was read.
local function noteFile(k, path, took, size)
  local cur = MAP.where[k]
  if not cur then
    MAP.where[k] = path
    if STORE and STORE.isRemote(path) then MAP.rsize[k] = size end
    if took then MAP.dirty[k] = true end            -- (joined with new scans: written back)
  elseif cur ~= path then
    MAP.extra[k] = MAP.extra[k] or {}
    local seen = false
    for _, p in ipairs(MAP.extra[k]) do if p == path then seen = true end end
    if not seen then MAP.extra[k][#MAP.extra[k] + 1] = path end
    MAP.dirty[k] = true                            -- (the joined file is written, the extra copy deleted)
  end
end
local function readPlace(p)
  if p.remote then
    local okL, list = pcall(STORE.list, p.remote, DIR)
    if not okL or type(list) ~= "table" then return false end   -- (no answer: read on a later turn)
    local want, sizes = {}, {}
    local staleGone = false
    for f, size in pairs(list) do
      local k = f:match("^(o?%-?%d+_%-?%d+)%.dat$")
      local path = p.dir .. "/" .. f
      if k and MAP.stale[path] then                  -- an old copy (the newer one is elsewhere): never read
        local okD, done = pcall(STORE.delete, path)
        if okD and done then MAP.stale[path] = nil staleGone = true end
      elseif k and MAP.where[k] ~= path then
        want[#want + 1] = f
        sizes[f] = size
      end
    end
    if staleGone then saveStale() end
    table.sort(want)
    local left = want
    while #left > 0 do
      local batch = {}
      for j = 1, math.min(#left, 20) do batch[#batch + 1] = DIR .. "/" .. left[j] end
      local okR, files = pcall(STORE.readMany, p.remote, batch)
      local got, rest = {}, {}
      for name, text in pairs(okR and type(files) == "table" and files or {}) do
        local f = tostring(name):match("([^/]+)$")
        if type(text) == "string" and f and sizes[f] then
          local okT, took = pcall(readText, text)
          if okT then
            noteFile(f:match("^(o?%-?%d+_%-?%d+)%.dat$"), p.dir .. "/" .. f, took, #text)
            got[f] = true
          end
        end
      end
      for _, f in ipairs(left) do if not got[f] then rest[#rest + 1] = f end end
      loadYield()
      if #rest == #left then return false end       -- (no answer: the rest stays unread - read on a later turn)
      left = rest
    end
    MAP.readAt[p.dir] = true
    return true
  end
  if fs.exists(p.dir) and fs.isDir(p.dir) then
    for _, f in ipairs(fs.list(p.dir)) do
      local k = f:match("^(o?%-?%d+_%-?%d+)%.dat$")
      local path = fs.combine(p.dir, f)
      if k and MAP.where[k] ~= path then
        local okR, t, took = pcall(readFile, path)
        if okR and type(t) == "string" then
          noteFile(k, path, took)
          -- an old detail file with ore lines: write it again without them
          if k:sub(1, 1) ~= "o" and t:find("\nO ", 1, true) then MAP.dirty[k] = true end
        end
        loadYield()
      end
    end
  end
  MAP.readAt[p.dir] = p.id or true
  return true
end

-- after reading: every detail chunk in the overview, the order by age
local function afterRead()
  -- every detail chunk must be in the overview (older saves had no overview)
  countOverview()
  -- and older saves stored edge-only chunks as if they were fully mapped:
  -- summarize again (marks them partial, so a survey scans them properly)
  for _, c in pairs(MAP.ch) do
    local h, _, partial = MAP.getOverview(c.cx * 16, c.cz * 16)
    if not h or not partial then summarize(c) end
  end
  for _, o in pairs(MAP.ov) do pack(o, OVR * OVR) end
  countOverview()
  table.sort(MAP.order, function(a, b) return MAP.ch[a].s < MAP.ch[b].s end)
end

-- places that were away when the map was read (a storage helper that did not answer, a floppy out of its
-- drive - or another floppy put in) are read NOW and joined with what came in since; until then nothing is
-- written there (places()). Map worker (every turn, and before every save / move). Returns how many read.
function MAP.readLate()
  if not MAP.loaded then return 0 end
  local n = 0
  for _, d in ipairs(mountedDisks()) do
    if d.data then
      local dir = fs.combine(d.mount, DIR)
      local id = floppyId(d)
      if not isRead(dir, id) and readPlace({ dir = dir, floppy = true, id = id }) then n = n + 1 end
    end
  end
  for id, h in pairs(STORE and STORE.helpers or {}) do
    local dir = "store:" .. id .. "/" .. DIR
    if STORE.usable(h) and not isRead(dir) and readPlace({ dir = dir, remote = id }) then n = n + 1 end
  end
  if n > 0 then
    afterRead()
    MAP.version = MAP.version + 1
    if sysLog then sysLog("Map: read " .. n .. " storage place(s) that were away at the start - joined with the new scans", "INFO") end
  end
  return n
end

-- read every map file (computer and data floppies); convert an old map.dat;
-- build the overview of chunks that have none yet
function MAP.load()
  -- the storage helpers first (their list is needed for places())
  if STORE and next(STORE.known) then pcall(STORE.find, true) end   -- only helpers seen before (fast)
  for _, p in ipairs(places()) do readPlace(p) end
  local oldFiles = {}
  for _, f in ipairs({ CONFIG.map.file, dataFile(CONFIG.map.file) }) do
    if fs.exists(f) then oldFiles[f] = true end
  end
  if next(oldFiles) and not next(MAP.ch) then
    for f in pairs(oldFiles) do pcall(loadOld, f) break end
  end
  afterRead()
  MAP.trim()
  if next(oldFiles) then
    -- the old file goes once everything is saved; if the map does not fit next
    -- to it, it goes first (everything is in memory) and the map gets its room
    MAP.loaded = true
    local ok = MAP.save(false, true)
    for f in pairs(oldFiles) do pcall(fs.delete, f) end
    if not ok then MAP.save() end
  end
  MAP.version = MAP.version + 1
end

-- the map is read in the background after the start (map worker); until then
-- scans wait here, nothing is saved and no survey is handed out
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

-- a scan summary from a turtle (node.lua): absolute centre + relative data
-- (the ores it also sends are not kept)
function MAP.addScan(m)
  if type(m.cols) ~= "table" or type(m.names) ~= "table" then return end
  if not MAP.loaded then
    -- the map is still being read: this scan is added afterwards
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
  saveFileSafe(VIEW_FILE, serialSmall({ rot = V.rot, zoom = V.zoom, cx = V.cx, cz = V.cz }))
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
      if not MAP.inArea(x, z) then
        -- outside the work area: never
      elseif known / total >= need or MAP.scanned(x, z) then skipped = skipped + 1
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

-- kept on a data floppy when there is one (it can get big: the handed-out
-- spots); the computer's copy only when no floppy takes it
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
  do
    local t = readSafe(qf)
    -- (an odd / old file: a queue whose numbers are not numbers is dropped - a new one starts)
    local good = type(t) == "table" and tonumber(t.cols) and tonumber(t.rows or 0)
    if good then
      for _, k in ipairs({ "cursor", "sent", "skipped", "step", "x1", "z1", "x2", "z2", "cx", "cz", "r", "y" }) do
        if t[k] ~= nil and type(t[k]) ~= "number" then good = false end
      end
      for _, k in ipairs({ "out", "redo", "rr", "rect" }) do
        if t[k] ~= nil and type(t[k]) ~= "table" then good = false end
      end
    end
    if good then MAP.queue = t end
  end
end

-- the WORK AREA (SETTINGS > MAP: corner 1 + corner 2, x / z): turtles never
-- get survey spots outside it. Not set = the whole world (up to the border).
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
  -- never past the world border (a zoomed-out view shows far more than the world)
  local border = tonumber(CONFIG.map.border) or 20000
  x1, z1 = math.max(x1, -border), math.max(z1, -border)
  x2, z2 = math.min(x2, border), math.min(z2, border)
  -- and to the work area: nothing outside it
  local ax1, az1, ax2, az2 = MAP.area()
  if ax1 then
    x1, z1, x2, z2 = math.max(x1, ax1), math.max(z1, az1), math.min(x2, ax2), math.min(z2, az2)
  end
  if x2 < x1 or z2 < z1 then return 0 end              -- nothing of it is in the work area: no survey
  -- a SPIRAL from the point of the area nearest to the base (or the turtles):
  -- the turtles start close to home and work outward - not at the far corner
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
  if old then MAP.queue.redo, MAP.queue.out = old.redo, old.out end   -- nothing handed out is lost
  saveQueue()
  return (math.floor((x2 - x1) / step) + 1) * (math.floor((z2 - z1) / step) + 1)     -- spots in the area
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
-- ring r of the spiral: its first index, its number of spots; the ring of index i
function MAP.ringStart(r) if r <= 0 then return 0 end return (2 * r - 1) * (2 * r - 1) end
function MAP.ringLen(r) if r <= 0 then return 1 end return 8 * r end
function MAP.ringOf(i) if i <= 0 then return 0 end return math.ceil((math.sqrt(i + 1) - 1) / 2) end

-- ===== AUTO-MAP: always a survey running, from the base outward =====
-- When no survey is running, the base starts (or continues) one that spirals
-- out from the base over the whole world, and hands it out like any survey.
-- Paused while the map floppies are full; ends at the world border. Your own
-- surveys go first; auto-map continues where it was afterwards.
local AUTO_FILE = "auto_survey.dat"
MAP.auto = { on = (CONFIG.map.autoSurvey ~= false), cursor = 0 }
do
  local t = readSafe(AUTO_FILE)
  if type(t) == "table" then
    MAP.auto = { on = t.on and true or false, cursor = tonumber(t.cursor) or 0, done = t.done and true or nil }
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

-- comms worker: start / continue auto-map when nothing else runs
function MAP.autoTick()
  local a = MAP.auto
  -- the work area changed since auto-map finished / started: start over in the new one
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
    -- a work area: the spiral from the base (or the area's point nearest to it) out to the area's far corner
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

-- how far around the base auto-map has got (blocks)
function MAP.autoRadius()
  local q = MAP.queue
  local cur = (q and q.auto) and MAP.queuePos(q) or (MAP.auto.cursor or 0)
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
local function nextBatch(q, want)
  local BATCH = want or BATCH
  local total = q.cols * q.rows
  local out, checked = {}, 0
  -- spots near a player to avoid wait (back into q.redo, tried again later)
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
  -- pack mode was on (a band of rings open): go on from that band's first ring
  -- (done spots are skipped - nothing of the band is lost)
  -- pack mode was on (rings handed out): go on from the first ring not finished (done spots are
  -- skipped - nothing of the rings is lost)
  if q.rr then
    local minR = q.rr.next or 0
    for _, rec in pairs(q.rr.own or {}) do if rec.i < rec.j then minR = math.min(minR, rec.r) end end
    for _, rec in ipairs(q.rr.loose or {}) do if rec.i < rec.j then minR = math.min(minR, rec.r) end end
    q.cursor = math.min(q.cursor, MAP.ringStart(minR))
    q.rr = nil
  end
  q.band, q.pend, q.wave = nil, nil, nil
  -- first the spots a turtle gave back unscanned (see MAP.reclaim) - each looked at once
  local n0 = #q.redo
  for _ = 1, n0 do
    if #out >= BATCH then break end
    local p = table.remove(q.redo, 1)
    if MAP.spotDone(p[1], p[2]) or not MAP.inArea(p[1], p[2]) then
      -- done meanwhile / outside the work area now
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
      -- a spiral from the base (or the area's nearest point) outward
      local dx, dz = spiral(i)
      x, z = q.cx + dx * q.step, q.cz + dz * q.step
      -- a survey of an area: the spiral's spots outside it are skipped (cheap -
      -- no map lookup, not counted against the 3000)
      if q.rect and (x < q.x1 or x > q.x2 or z < q.z1 or z > q.z2) then
        checked, outside, x = checked - 1, outside + 1, nil
      end
    else
      -- snake order: every other row backwards, so a turtle never jumps back
      local row, col = math.floor(i / q.cols), i % q.cols
      if row % 2 == 1 then col = q.cols - 1 - col end
      x, z = q.x1 + q.r + col * q.step, q.z1 + q.r + row * q.step
    end
    if x and not MAP.inArea(x, z) then
      checked, outside, x = checked - 1, outside + 1, nil     -- outside the work area / border: cheap skip
    end
    if not x then
      -- outside the surveyed area
    elseif MAP.spotDone(x, z) then q.skipped = q.skipped + 1 why.done = why.done + 1
    elseif nearPlayer(x, z) then q.redo[#q.redo + 1] = { x, z }       -- later
    else out[#out + 1] = { x, z } end
  end
  why.redo = #q.redo
  return out
end

-- ===== PACK: every turtle its own RING of the spiral =====
-- The old pack dealt one round's spots in turn along ONE line of the spiral
-- (A B C A B C ...): every turtle hopped 51 blocks over the others' spots (over
-- 48 = up to the sky highway and down again for every hop) and they followed
-- each other in a line - the one in front scanned, the rest were travelling.
-- Now a BAND of n rings (one per turtle; rings with nothing left are left out)
-- is swept round together: turtle j keeps ring j, and each round every turtle
-- gets the next ~k spots of its own
-- ring (the same stretch of the way round), so they move side by side, 17
-- blocks apart, each hop 17 blocks on the ground, never across another's spots.
-- q.band = { rings = { r1, r2 .. }, f = how far round (0..1), own = { [j] = id } }
-- (q.cursor stays at or before the band's first ring while it is open: an auto-map cursor
--  saved from it, or pack mode turned off, goes on from there - nothing lost)
local function near(a, b) return math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) end

-- EVERY free turtle a share: the spots in rows (snake), cut into one piece per turtle (by
-- measured speed), each piece to the free turtle nearest to it. (SURVEY: ALL on a small
-- area put its spots in q.redo, and they were dealt in a CHAIN - nearest turtle with room,
-- 6 each: all turtles start at the base, so 30 spots went to 5 turtles and the rest of the
-- fleet waited; without PACK the first free turtle took everything.)
local function dealEven(spots, ids, step)
  local out = {}
  if #spots == 0 or #ids == 0 then return out end
  step = step or 17
  table.sort(spots, function(a, b)
    local ra, rb = math.floor(a[2] / step), math.floor(b[2] / step)
    if ra ~= rb then return ra < rb end
    if ra % 2 == 0 then return a[1] < b[1] end
    return a[1] > b[1]
  end)
  local n = math.min(#ids, #spots)
  local rate, rs = {}, 0
  for _, id in ipairs(ids) do
    local t = state.turtles[id]
    rate[id] = (t and tonumber(t.packRate)) or 0.01
  end
  -- the n fastest share (all of them when there are spots enough)
  local use = {}
  for _, id in ipairs(ids) do use[#use + 1] = id end
  table.sort(use, function(a, b) return rate[a] > rate[b] end)
  while #use > n do table.remove(use) end
  for _, id in ipairs(use) do rs = rs + rate[id] end
  -- the pieces, in order along the rows
  local pieces, at, acc = {}, 1, 0
  for i = 1, n do
    acc = acc + rate[use[i]]
    local upto = (i == n) and #spots or math.max(at, math.floor(#spots * acc / rs + 0.5))
    local piece = {}
    for c = at, upto do piece[#piece + 1] = spots[c] end
    if #piece > 0 then pieces[#pieces + 1] = piece end
    at = upto + 1
  end
  -- each piece to the nearest turtle still without one (biggest pieces first)
  local left = {}
  for _, id in ipairs(use) do left[id] = true end
  for _, piece in ipairs(pieces) do
    local mid = piece[math.floor((#piece + 1) / 2)]
    local best, bd
    for id in pairs(left) do
      local t = state.turtles[id]
      local d = (t and t.pos and t.pos.x) and near({ t.pos.x, t.pos.z }, mid) or 1e9
      if not best or d < bd or (d == bd and id < best) then best, bd = id, d end
    end
    if best then out[best], left[best] = piece, nil end
  end
  return out
end
MAP.dealEven = dealEven

-- ===== PACK: every turtle its OWN RING of the spiral, at its own pace =====
-- The turtles followed each other (the owner, more than once: "they move in mapped chunks in a
-- line, only the one in front maps"). Rounds made the whole pack wait for its slowest member and
-- then jump over mapped land together; where land was mapped in patches a turtle with nothing on
-- its own ring took HALF OF ANOTHER RING - two turtles on one straight line, one behind the other.
-- Now: a turtle owns a ring (a square round the base, 17 blocks from the next) and walks it at its
-- own pace - from the ring's unmapped spot NEAREST to it, all the way round - k spots per hand-out,
-- mapped stretches skipped; nobody waits. Ring done -> the next ring nobody had (a turtle that went
-- away leaves its ring "loose"). A loose ring / no ring left -> the NEAREST stretch of a ring with work
-- left, split there (the helper owns the part from there on: never one behind the other).
-- Two turtles are never on the same ring line, so none flies over land another just mapped.
-- q.rr = { next = the next ring nobody had, own = { [id] = { r, s0, i, j } }, loose = { ... } }
-- (offsets i .. j-1 from s0 round ring r are still to do, walked forward by the owner)
local function ringSpot(q, r, s0, off)
  local dx, dz = spiral(MAP.ringStart(r) + (s0 + off) % MAP.ringLen(r))
  return q.cx + dx * q.step, q.cz + dz * q.step
end

MAP.REDO_NEAR = 800
local function ringDeal(q, ids, k)
  local total = q.cols * q.rows
  local rad = math.floor((q.cols - 1) / 2)
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
  q.band, q.pend, q.wave = nil, nil, nil            -- (older pack data in a saved queue)
  local rr = q.rr or { next = MAP.ringOf(q.cursor) }
  q.rr = rr
  rr.own, rr.loose = rr.own or {}, rr.loose or {}
  MAP.looking = nil
  local pos = {}
  for _, id in ipairs(ids) do
    local t = state.turtles[id]
    pos[id] = { t.pos.x, t.pos.z }
  end
  -- rings of turtles that went away (gone, offline 10 min, STOPPED): loose, for the others
  local nowE = os.epoch("utc")
  for oid, rec in pairs(rr.own) do
    local t = state.turtles[oid]
    if not t or t.held or (q.excluded and q.excluded[oid])
       or (not TT.online(t) and t.seenEpoch and nowE - t.seenEpoch > (tonumber(CONFIG.map.reclaimOffline) or 600) * 1000) then
      rr.own[oid] = nil
      if rec.i < rec.j then rr.loose[#rr.loose + 1] = rec end
    end
  end
  -- spots out with a turtle are never handed out twice
  local busySpot = {}
  for _, l in pairs(q.out or {}) do for _, p in ipairs(l) do busySpot[p[1] .. "," .. p[2]] = true end end
  local out, solo = {}, {}
  -- 1. spots given back unscanned / a small SURVEY: ALL first: shared out EVENLY (dealEven), a
  --    short share each, the ones nearest the turtles first; those turtles are done for now
  local n0, cand = #q.redo, {}
  local cap = #ids * 2 * k
  local cx, cz = 0, 0
  for _, id in ipairs(ids) do cx, cz = cx + pos[id][1], cz + pos[id][2] end
  cx, cz = cx / #ids, cz / #ids
  for _ = 1, n0 do
    local p = table.remove(q.redo, 1)
    if MAP.spotDone(p[1], p[2]) or not MAP.inArea(p[1], p[2]) or busySpot[p[1] .. "," .. p[2]] then
      -- done meanwhile / outside the work area now / out with a turtle
    elseif nearPlayer(p[1], p[2]) then q.redo[#q.redo + 1] = p
    else cand[#cand + 1] = p end
  end
  -- GIVEN BACK BY A TURTLE (lost, failed, stopped for a player ...): only spots within MAP.REDO_NEAR of a free turtle,
  -- shared out evenly, and a share only to a turtle that near. Dealt to anyone, a turtle 8,000 blocks round the map flew there for a few
  -- spots and back to its ring (test_survey_far.lua). The rest waits for a turtle working near them (the lost turtle's
  -- loose ring brings one) - or for no ring work left. Spots of a SURVEY: ALL you started (p[3]) go to anyone.
  local nearR = MAP.REDO_NEAR
  local function dist(p, id) return math.abs(p[1] - pos[id][1]) + math.abs(p[2] - pos[id][2]) end
  local take = {}
  for _, p in ipairs(cand) do
    local ok = p[3]
    if not ok then for _, id in ipairs(ids) do if dist(p, id) <= nearR then ok = true break end end end
    if ok then take[#take + 1] = p else q.redo[#q.redo + 1] = p end
  end
  if #take > 0 then
    table.sort(take, function(a, b) return math.abs(a[1] - cx) + math.abs(a[2] - cz) < math.abs(b[1] - cx) + math.abs(b[2] - cz) end)
    for i = #take, cap + 1, -1 do q.redo[#q.redo + 1] = table.remove(take, i) end
    for id, l in pairs(dealEven(take, ids, q.step)) do
      local got = {}
      for _, p in ipairs(l) do
        if p[3] or dist(p, id) <= nearR then got[#got + 1] = p else q.redo[#q.redo + 1] = p end
      end
      if #got > 0 then out[id] = got end
    end
  end
  if #cand > 0 then
    local rest = {}
    for _, id in ipairs(ids) do if not out[id] then rest[#rest + 1] = id else solo[id] = true end end
    ids = rest
  end
  why.redo = #q.redo
  -- how much is looked at per call: by TIME (0.3 s, at least 3000 spots) - a big mapped area
  -- round the base takes a while to look past
  local checked, outside = 0, 0
  local stopAt = os.clock() + (tonumber(CONFIG.map.lookTime) or 0.3)
  local function outOfTime()
    return (checked >= 3000 and os.clock() >= stopAt) or checked >= 60000 or outside >= 200000
  end
  local function skip(x, z)
    return (q.rect and (x < q.x1 or x > q.x2 or z < q.z1 or z > q.z2)) or not MAP.inArea(x, z)
  end
  local function usable(x, z)
    if skip(x, z) then outside = outside + 1 return false end
    checked = checked + 1
    if busySpot[x .. "," .. z] then return false end
    if MAP.spotDone(x, z) then q.skipped = q.skipped + 1 why.done = why.done + 1 return false end
    if nearPlayer(x, z) then q.redo[#q.redo + 1] = { x, z } return false end
    return true
  end
  -- NEAREST WORK FIRST (the owner: "200 chunks surveyed while 350 chunks mined"; turtles flew 1,500-3,600 blocks on
  -- the sky highway between hand-outs). A loose ring was taken at the spot where its LOST turtle stopped (rec.i) -
  -- however far, before any new ring - and a helper took a ring's FAR END: at 2,400 blocks out a ring is ~19,000
  -- blocks round. Now the ring's still-to-do stretch is looked at for its spot NEAREST to the turtle and SPLIT there:
  -- the turtle owns from there on, the part before stays loose for another. test_survey_far.lua.
  -- (offset in i .. j-1 of rec nearest to p, at least `from`; stride 4 then the spots round the best)
  local function nearestOff(rec, p, from)
    local lo = math.max(rec.i, from or rec.i)
    if lo >= rec.j then return nil end
    local best, bd
    local function try(off)
      if off < lo or off >= rec.j then return end
      local x, z = ringSpot(q, rec.r, rec.s0, off)
      local d = math.abs(x - p[1]) + math.abs(z - p[2])
      if not bd or d < bd then best, bd = off, d end
    end
    for off = lo, rec.j - 1, 4 do try(off) end
    try(rec.j - 1)
    if best then local b0 = best for off = b0 - 3, b0 + 3 do try(off) end end
    return best, bd
  end
  -- rec split at m: [i, m) stays where it was (keep), [m, j) is returned
  local function splitAt(rec, m)
    local tail = { r = rec.r, s0 = rec.s0, i = m, j = rec.j }
    rec.j = m
    return tail
  end
  -- a ring with work for this turtle: the nearest stretch of a loose ring, or the next ring nobody had (from its
  -- unmapped spot nearest to the turtle) - whichever is NEARER
  local function newRing(id)
    local p = pos[id]
    local bi, bm, bd
    for i, rec in ipairs(rr.loose) do
      if rec.i < rec.j then
        local m, d = nearestOff(rec, p)
        if m and (not bd or d < bd) then bi, bm, bd = i, m, d end
      end
    end
    local function takeLoose()
      local rec = rr.loose[bi]
      if bm > rec.i then return splitAt(rec, bm) end          -- (the part before it stays loose)
      return table.remove(rr.loose, bi)
    end
    if bi and bd <= 400 then return takeLoose() end
    local fresh
    while rr.next <= rad do
      if outOfTime() then
        MAP.looking = { r = rr.next, rad = rad, found = 0, want = 1 }
        return nil
      end
      local r = rr.next
      rr.next = r + 1
      local P, best, bdist = MAP.ringLen(r), nil, nil
      for s = 0, P - 1 do
        local dx, dz = spiral(MAP.ringStart(r) + s)
        local x, z = q.cx + dx * q.step, q.cz + dz * q.step
        if skip(x, z) then outside = outside + 1
        else
          checked = checked + 1
          if not MAP.spotDone(x, z) then
            local d = math.abs(x - p[1]) + math.abs(z - p[2])
            if not best or d < bdist then best, bdist = s, d end
          end
        end
      end
      if best then fresh = { r = r, s0 = best, i = 0, j = P, d = bdist } break end
    end
    if fresh and (not bi or fresh.d <= bd) then
      fresh.d = nil
      return fresh
    end
    if fresh then fresh.d = nil rr.loose[#rr.loose + 1] = fresh end   -- (nothing lost: someone nearer takes it)
    if bi then return takeLoose() end
    return nil
  end
  -- up to n usable spots of a ring: forward (its owner) or from the far end (a helper)
  local function walk(rec, n, backward)
    local got = {}
    while rec.i < rec.j and #got < n do
      local off
      if backward then rec.j = rec.j - 1 off = rec.j else off = rec.i rec.i = rec.i + 1 end
      local x, z = ringSpot(q, rec.r, rec.s0, off)
      if usable(x, z) then
        got[#got + 1] = { x, z }
        busySpot[x .. "," .. z] = true
      end
      if outOfTime() then break end
    end
    return got
  end
  -- 2. every free turtle: the next k spots of ITS ring; ring done -> a new one
  table.sort(ids)
  local helpers = {}
  for _, id in ipairs(ids) do
    local mine, tries = {}, 0
    while #mine == 0 and tries < 4 and not outOfTime() do
      tries = tries + 1
      local rec = rr.own[id]
      if not rec or rec.i >= rec.j then
        rec = newRing(id)
        rr.own[id] = rec
        if not rec then break end
      end
      mine = walk(rec, k)
    end
    if #mine > 0 then out[id] = mine else helpers[#helpers + 1] = id end
  end
  -- 3. no ring left: the NEAREST stretch of a ring with work left (its owner keeps at least 2 hand-outs in front of
  --    it), split there - the helper owns the rest (before: the ring's far end, up to half a ring away)
  for _, id in ipairs(helpers) do
    local best, bm, bd
    for _, rec in pairs(rr.own) do
      if rec.j - rec.i > 3 * k then
        local m, d = nearestOff(rec, pos[id], rec.i + 2 * k)
        if m and (not bd or d < bd) then best, bm, bd = rec, m, d end
      end
    end
    for _, rec in ipairs(rr.loose) do
      if rec.i < rec.j then
        local m, d = nearestOff(rec, pos[id])
        if m and (not bd or d < bd) then best, bm, bd = rec, m, d end
      end
    end
    if best and not outOfTime() then
      local mine = (bm > best.i) and splitAt(best, bm) or best
      if mine == best then for i2, r2 in ipairs(rr.loose) do if r2 == best then table.remove(rr.loose, i2) break end end end
      rr.own[id] = mine
      local m = walk(mine, k)
      if #m > 0 then out[id] = m end
    end
    -- nothing on any ring: the given-back spots that waited for someone near them, nearest first
    if not out[id] and #q.redo > 0 then
      local p0 = pos[id]
      table.sort(q.redo, function(a, b)
        return math.abs(a[1] - p0[1]) + math.abs(a[2] - p0[2]) < math.abs(b[1] - p0[1]) + math.abs(b[2] - p0[2])
      end)
      local got = {}
      while #q.redo > 0 and #got < 2 * k do
        local p = table.remove(q.redo, 1)
        if not MAP.spotDone(p[1], p[2]) and not busySpot[p[1] .. "," .. p[2]] then got[#got + 1] = p end
      end
      if #got > 0 then out[id] = got solo[id] = true end
    end
  end
  -- 4. how far the survey is: the first ring not finished (auto-map / plain mode go on from there)
  local minR = rr.next
  for _, rec in pairs(rr.own) do if rec.i < rec.j then minR = math.min(minR, rec.r) end end
  for i = #rr.loose, 1, -1 do
    local rec = rr.loose[i]
    if rec.i < rec.j then minR = math.min(minR, rec.r) else table.remove(rr.loose, i) end
  end
  if minR > rad then q.cursor = total
  else q.cursor = math.max(q.cursor, math.min(total, MAP.ringStart(minR))) end
  why.redo = #q.redo
  return out, solo
end
MAP.ringDeal = ringDeal

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
function MAP.batchResult(id, ok, msg)
  local q = MAP.queue
  if not (q and q.out and q.out[id]) then return end
  -- how fast is this turtle (spots per second)? the pack shares out by it
  local t = state.turtles[id]
  -- REFUSED its spots at once (position / facing unknown, the anchor, ...): it would get spots
  -- again every round and refuse them again - looking as if the base sent it nothing ("only
  -- half get sent"). Kept out for 2 min with the reason shown (TURTLES list, SURVEY: ALL report).
  -- ("busy: ..." = it took another order a moment before - not a refusal of THESE spots: no 2-min wait)
  if not ok and t and t.queueAt and os.clock() - t.queueAt < 30 and not tostring(msg or ""):find("^busy") then
    t.surveyFail = { msg = tostring(msg or "no reason given"), at = os.clock() }
    if MAP.press then MAP.press.failed[id] = t.surveyFail.msg end
    TT.log(t, "Refused its survey spots: " .. t.surveyFail.msg)
  elseif ok and t then
    t.surveyFail = nil
  end
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
  -- (pressed again: spots already waiting or out with a turtle are not added twice)
  local have = {}
  for _, p in ipairs(q.redo) do have[p[1] .. "," .. p[2]] = true end
  for _, l in pairs(q.out or {}) do for _, p in ipairs(l) do have[p[1] .. "," .. p[2]] = true end end
  for i = #spots, 1, -1 do
    if not have[spots[i][1] .. "," .. spots[i][2]] then
      spots[i][3] = 1                                       -- (asked for: any turtle may go - ringDeal)
      table.insert(q.redo, 1, spots[i])                     -- before the rest
    end
  end
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
  if not q or not MAP.loaded then return end      -- (map still loading: done spots unknown)
  -- a survey saved by an older version (row by row from the far corner):
  -- once into the spiral from the base (done spots are skipped anyway)
  if not q.spiral and not q.auto and q.x1 then
    local oldOut, sent, skipped, ids, excl = q.out, q.sent, q.skipped, q.ids, q.excluded
    local held = {}
    for id, t in pairs(state.turtles) do held[id] = t.held end
    MAP.queue = nil
    MAP.queueSurvey(q.x1, q.z1, q.x2, q.z2, q.r, ids)
    for id, t in pairs(state.turtles) do t.held = held[id] end         -- (no release: you did not start it now)
    q = MAP.queue
    -- the old batches (and spots given back) were far out at the corner: dropped
    -- (the spiral gets there in its turn); the turtles on their way there are
    -- called back - also when they come back online later (t.recall, saved)
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
    -- the work area was changed: auto-map starts again inside the new one
    MAP.auto.cursor, MAP.auto.done = 0, nil
    MAP.saveAuto()
    MAP.queue = nil
    saveQueue()
    return
  end
  if q.auto and MAP.full then return end           -- auto-map waits for room on the floppies
  local total = q.cols * q.rows
  local minFuel = tonumber(CONFIG.map.surveyMinFuel) or 500
  local busy, why, anyFree = false, {}, false
  local list = q.ids or TT.available()
  -- PACK: the turtles work close together (neighbouring spots), so when one is
  -- unloaded the others are near it - one visit wakes them all
  local pack = CONFIG.map.pack ~= false
  local packFree = {}
  for _, id in ipairs(list) do
    local t = state.turtles[id]
    local free = t and TT.online(t) and t.pos and t.pos.x and (t.task == nil or t.task == "idle") and not t.anchor
                 and not (q.excluded and q.excluded[id])      -- stopped by the owner
                 and not t.rescuerRole and not t.held         -- the rescuer stays free; STOPPED stays stopped
                 and not TT.factoryRole(t)                    -- the factory builder / crafter stays at the factory
                 and not TT.copyStays(t)                      -- a copy: moving it unloads its twin's chunk
    local fuel = t and tonumber(t.fuel)
    if free and t.queueAt and os.clock() - t.queueAt < 15 then free = false busy = true end
    if free and fuel and fuel < TT.surveyFuelNeed(t) then free = false end   -- (the way home + a batch)
    local refused = t and t.surveyFail and os.clock() - t.surveyFail.at < 120
    if free and refused then free = false end
    -- still holding a batch (idle without its result yet): not free - after 30 s
    -- idle the batch is taken back below, THEN it gets new spots (never overwrite:
    -- its unscanned spots would be lost)
    if free and q.out and q.out[id] then free = false busy = true end
    if t and not free and t.task and t.task ~= "idle" then busy = true end
    -- why this turtle gets nothing (told to you when nobody works)
    if t and not free then
      local w
      if not TT.online(t) then w = "offline"
      elseif not (t.pos and t.pos.x) then w = "position unknown"
      elseif t.task and t.task ~= "idle" then w = "busy"
      elseif t.held or (q.excluded and q.excluded[id]) then w = "STOPPED - give it a command first"
      elseif fuel and fuel < TT.surveyFuelNeed(t) then w = "fuel " .. fuel .. " (needs " .. TT.surveyFuelNeed(t) .. ": the way home + a batch)"
      elseif t.anchor then w = "anchor" elseif t.rescuerRole then w = "rescuer"
      elseif TT.factoryRole(t) then w = "factory " .. TT.factoryRole(t)
      elseif refused then w = "refused its spots: " .. t.surveyFail.msg end
      if MAP.press and w then MAP.press.why[id] = w end
      if w then why[#why + 1] = (t.label or ("#" .. id)) .. ": " .. w end
    end
    if free then anyFree = true end
    -- idle while the base still counts a batch as theirs: take it back
    -- (whatever was scanned is dropped; the rest is handed out again)
    if t and q.out and q.out[id] and TT.online(t) and (t.task == nil or t.task == "idle")
       and (not t.queueAt or os.clock() - t.queueAt > 30) then
      MAP.reclaim(id)
    end
    if free then
      packFree[#packFree + 1] = id                -- handed out together below (pack or not)
    end
  end
  -- a turtle silent for 10 min (unloaded, or deleted by a server crash) still
  -- holding spots: they go to the others (if it comes back, it just scans twice)
  local nowE = os.epoch("utc")
  for id in pairs(q.out or {}) do
    local t = state.turtles[id]
    if not t or (not TT.online(t) and t.seenEpoch and nowE - t.seenEpoch > (tonumber(CONFIG.map.reclaimOffline) or 600) * 1000) then
      MAP.reclaim(id)
      q.changed = true
    end
  end
  -- no pack: every free turtle its own batch - the next spots cut EVENLY between them
  -- (before, the first free turtle took up to 64 and a small survey left the rest idle)
  if not pack and #packFree > 0 and (q.cursor < total or (q.redo and #q.redo > 0)) then
    table.sort(packFree)
    local spots = nextBatch(q, BATCH * #packFree)
    local lists = dealEven(spots, packFree, q.step)
    for _, id in ipairs(packFree) do
      local mine = lists[id]
      if mine and #mine > 0 then
        local t = state.turtles[id]
        TT.sendSpots(id, mine, q.r)
        q.out = q.out or {}
        q.out[id] = mine
        t.queueAt = os.clock()
        q.sent = q.sent + #mine
        if MAP.press then MAP.press.sent[id] = true end
        busy, q.changed = true, true
      end
    end
  end
  -- the pack: every free turtle the next spots of its OWN ring (see ringDeal) - nobody waits
  if pack and #packFree > 0 and (q.cursor < total or (q.redo and #q.redo > 0)) then
    -- 16 a hand-out (was 4): every hand-out costs the turtle 6-10 s (report idle, the base's 2-s tick, start,
    -- ask what is known there); the travel model with that delay: 4 = 3086 spots, 8 = 3540, 16 = 3674 - the
    -- same blocks per spot and overflights
    local k = math.max(1, tonumber(CONFIG.map.packSpots) or 16)
    table.sort(packFree)
    local lists, solo = {}, {}
    if q.spiral then
      lists, solo = ringDeal(q, packFree, k)
    else
      -- (a row-by-row queue: one piece of the line each, never in turn)
      local spots = nextBatch(q, #packFree * k)
      lists = dealEven(spots, packFree, q.step)
    end
    for _, id in ipairs(packFree) do
      local mine = lists[id]
      local t = state.turtles[id]
      if mine and #mine > 0 then
        TT.sendSpots(id, mine, q.r)
        q.out = q.out or {}
        q.out[id] = mine
        t.queueAt = os.clock()
        q.sent = q.sent + #mine
        if MAP.press then MAP.press.sent[id] = true end
        busy, q.changed = true, true
      end
    end
  end
  MAP.pressReport()
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
  -- written when something changed (or once a minute for the cursor), not every 2 s
  if not MAP.queue or q.changed or os.clock() - (MAP.queueSavedAt or 0) > 60 then
    q.changed = nil
    MAP.queueSavedAt = os.clock()
    saveQueue()
  end
end

-- SURVEY: ALL pressed: which free turtles really went, and why the others did not - told
-- ~20 s after the press (the owner: "only half get sent" - the base saw no reason)
function MAP.pressStart()
  MAP.press = { at = os.clock(), free = TT.available(), sent = {}, failed = {}, why = {} }
end
function MAP.pressReport()
  local P = MAP.press
  if not P or os.clock() - P.at < 20 then return end
  MAP.press = nil
  local went, not_ = 0, {}
  for _, id in ipairs(P.free) do
    local t = state.turtles[id]
    if P.sent[id] and not P.failed[id] then went = went + 1
    elseif t then
      local w = P.failed[id] and ("refused: " .. P.failed[id]) or P.why[id]
      if not w and t.task and t.task ~= "idle" then w = "busy (" .. tostring(t.task) .. ") - joins when free" end
      not_[#not_ + 1] = (t.label or ("#" .. id)) .. ": " .. (w or "free, got nothing yet")
    end
  end
  local msg = went .. " of " .. #P.free .. " free turtles went."
  if #not_ > 0 then msg = msg .. " Not: " .. table.concat(not_, "; ") end
  if sysLog then sysLog("SURVEY: ALL - " .. msg, #not_ > 0 and "WARNING" or "INFO") end
  setPopup("SURVEY: ALL", msg, #not_ > 0 and C.warn or C.good)
end

-- progress for the screen: done fraction, spots total
-- how far the queue got, as a spiral index (a pack band counts as far as it went round)
function MAP.queuePos(q)
  if not q then return 0 end
  local rr = q.rr
  if not rr then return q.cursor end
  -- the rings handed out so far, minus what is still to do on them
  local pos = MAP.ringStart(rr.next or 0)
  for _, rec in pairs(rr.own or {}) do pos = pos - math.max(0, rec.j - rec.i) end
  for _, rec in ipairs(rr.loose or {}) do pos = pos - math.max(0, rec.j - rec.i) end
  return math.max(q.cursor, math.min(q.cols * q.rows, pos))
end

function MAP.surveyProgress()
  local q = MAP.queue
  if not q then return nil end
  local total = q.cols * q.rows
  local cur = MAP.queuePos(q)
  if q.rect then
    -- spots of the area only (the spiral square is bigger): done = how far the
    -- spiral got, as a share of the area's spots it has passed
    local inArea = math.max(1, (math.floor((q.x2 - q.x1) / q.step) + 1) * (math.floor((q.z2 - q.z1) / q.step) + 1))
    local k = math.max(0, (math.sqrt(cur + 1) - 1) / 2)                      -- the ring it is on
    local half = k * q.step
    local w = math.min(q.x2, q.cx + half) - math.max(q.x1, q.cx - half)
    local h = math.min(q.z2, q.cz + half) - math.max(q.z1, q.cz - half)
    local passed = (math.floor(math.max(0, w) / q.step) + 1) * (math.floor(math.max(0, h) / q.step) + 1)
    if cur >= total then passed = inArea end
    local again = q.redo and #q.redo or 0
    return math.min(1, passed / inArea), inArea, q.sent, q.skipped, again
  end
  local again = q.redo and #q.redo or 0
  return cur / total, total, q.sent, q.skipped, again
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

-- (MAP.load runs in the map worker: MAP.loadNow)
