-- base_map.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MAP tab data: top block of every scanned column and ores, from the turtles'
--   Geo Scanner scans, plus block colours, map rotation and survey spots.
--   Saved as small REGION FILES (4 x 4 chunks each) in a "map" folder, on the
--   data floppies first (the one with the most room), else on the computer.
--   Only changed regions are written, at most once a minute (and on exit).

---------------------------------------------------------------------
-- MAP DATA  (top block of every scanned column + ores, from turtle scans)
---------------------------------------------------------------------
-- In memory one chunk = { cx, cz, k, r, s, d = 256 numbers, o = ores }:
--   d[i] = (height + 64) * 4096 + block (0 = not scanned), i = z*16 + x + 1
--   o    = list of (x + 16 z + 256 (y + 64)) * 4096 + block   (x, z in the chunk)
--   s    = when it was last scanned (MAP.tick): the oldest are dropped first
MAP = {
  ch = {},         -- [chunk key] = chunk
  order = {},      -- chunk keys, oldest first (for the size limit)
  names = {},      -- palette: index -> block name
  nameIdx = {},    -- block name -> index
  scans = 0,
  tick = 0,        -- goes up with every scan (chunk age)
  version = 0,     -- goes up whenever the map data changes (the page caches its image)
  dirty = {},      -- [region key] = true: must be saved
  where = {},      -- [region key] = path of its file
  savedAt = -1000, -- os.clock() of the last save
}
local REGION = 4           -- chunks per region side (one file = 64 x 64 blocks)
local DIR = "map"          -- folder of the region files (computer and data floppies)
local SAVE_EVERY = 60      -- seconds between saves

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, #B64 do DEC[B64:sub(i, i)] = i - 1 end
local function c1(v) return B64:sub(v + 1, v + 1) end
-- 0..4095 -> 2 characters
local function enc2(v)
  v = math.max(0, math.min(4095, math.floor(v)))
  return c1(math.floor(v / 64)) .. c1(v % 64)
end
-- 2 characters at position p -> 0..4095 (nil if broken)
local function dec2(s, p)
  local a, b = DEC[s:sub(p, p)], DEC[s:sub(p + 1, p + 1)]
  if not a or not b then return nil end
  return a * 64 + b
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
-- key of the region a chunk is in ("rx_rz", also the file name)
local function rkey(cx, cz) return math.floor(cx / REGION) .. "_" .. math.floor(cz / REGION) end

-- the chunk at cx, cz (made if `make` and it does not exist)
local function chunkAt(cx, cz, make)
  local k = ckey(cx, cz)
  local c = MAP.ch[k]
  if c or not make then return c end
  local d = {}
  for i = 1, 256 do d[i] = 0 end
  c = { cx = cx, cz = cz, k = k, r = rkey(cx, cz), s = MAP.tick, d = d, o = {} }
  MAP.ch[k] = c
  MAP.order[#MAP.order + 1] = k
  return c
end

-- height, block of a map column, or nil
function MAP.get(x, z)
  local c = MAP.ch[ckey(math.floor(x / 16), math.floor(z / 16))]
  if not c then return nil end
  local v = c.d[(z % 16) * 16 + (x % 16) + 1]
  if v == 0 then return nil end
  return math.floor(v / 4096) - 64, v % 4096
end

-- set a map column (and note its chunk)
function MAP.set(x, z, h, b)
  MAP.version = MAP.version + 1
  local c = chunkAt(math.floor(x / 16), math.floor(z / 16), true)
  h = math.max(-64, math.min(4031, math.floor(h)))
  c.d[(z % 16) * 16 + (x % 16) + 1] = (h + 64) * 4096 + math.min(4095, b)
  MAP.dirty[c.r] = true
  if MAP.touched then MAP.touched[c.k] = true end
end

-- add an ore (world x, y, z) to its chunk
local function addOre(x, y, z, b)
  local c = chunkAt(math.floor(x / 16), math.floor(z / 16), true)
  local pos = (x % 16) + 16 * (z % 16) + 256 * math.max(0, math.min(383, y + 64))
  c.o[#c.o + 1] = pos * 4096 + math.min(4095, b)
  MAP.dirty[c.r] = true
end

-- every ore: fn(x, y, z, block index)
function MAP.eachOre(fn)
  for _, c in pairs(MAP.ch) do
    for _, v in ipairs(c.o) do
      local pos = math.floor(v / 4096)
      fn(c.cx * 16 + pos % 16, math.floor(pos / 256) - 64, c.cz * 16 + math.floor(pos / 16) % 16, v % 4096)
    end
  end
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
function MAP.hasData() return MAP.scans > 0 or #MAP.order > 0 end

-- keep at most `max` chunks (default CONFIG.map.maxChunks): drop the oldest,
-- with their ores
function MAP.trim(max)
  max = max or CONFIG.map.maxChunks or 300
  if #MAP.order <= max then return end
  MAP.version = MAP.version + 1
  while #MAP.order > max do
    local c = MAP.ch[table.remove(MAP.order, 1)]
    if c then
      MAP.ch[c.k] = nil
      MAP.dirty[c.r] = true
    end
  end
end

-- ===== files =====
-- the "map" folders: the computer's and every data floppy's
-- (returns a list of { dir, free, floppy })
local function places()
  local out = {}
  for _, d in ipairs(mountedDisks()) do
    if d.data then out[#out + 1] = { dir = fs.combine(d.mount, DIR), free = d.free, floppy = true } end
  end
  local okF, free = pcall(fs.getFreeSpace, "/")
  out[#out + 1] = { dir = DIR, free = okF and free or 0, floppy = false }
  return out
end

-- one chunk's 256 columns as text: per column the height as the change from
-- the column before (1 char; "A" + 2 chars = exact height) and the block
-- (1 char; "/" + 2 chars for big numbers), "~" = not scanned, "*n" = the
-- column before n more times
local function colsText(d, loc)
  local out, prev, run, ph = {}, nil, 0, 64
  for i = 1, 256 do
    local v, tok = d[i], "~"
    if v ~= 0 then
      local h, b = math.floor(v / 4096) - 64, loc(v % 4096)
      local dh = h - ph
      ph = h
      tok = ((dh >= -31 and dh <= 31) and c1(dh + 32) or ("A" .. enc2(h + 64))) ..
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

-- text -> the 256 columns (glob: the file's block numbers -> the map's)
local function readCols(s, d, glob)
  local p, i, ph, n = 1, 1, 64, #s
  local lastV, lastDh, lastAbs = 0, 0, false
  local function block(q)
    local ch = s:sub(q, q)
    if ch == "/" then return glob[dec2(s, q + 1) or 0] or MAP.pal("unknown"), q + 3 end
    return glob[DEC[ch] or 0] or MAP.pal("unknown"), q + 1
  end
  while p <= n and i <= 256 do
    local ch = s:sub(p, p)
    if ch == "*" then
      for _ = 1, DEC[s:sub(p + 1, p + 1)] or 0 do
        if i > 256 then break end
        if lastV ~= 0 and not lastAbs then
          ph = ph + lastDh
          lastV = (ph + 64) * 4096 + lastV % 4096
        end
        d[i], i = lastV, i + 1
      end
      p = p + 2
    elseif ch == "~" then
      d[i], i, p, lastV = 0, i + 1, p + 1, 0
    else
      local h
      if ch == "A" then
        h, lastAbs = (dec2(s, p + 1) or 64) - 64, true
        p = p + 3
      else
        lastDh, lastAbs = (DEC[ch] or 32) - 32, false
        h, p = ph + lastDh, p + 1
      end
      ph = h
      local b
      b, p = block(p)
      lastV = (math.max(-64, h) + 64) * 4096 + b
      d[i], i = lastV, i + 1
    end
  end
end

-- the text of one region file (its chunks, with their own block-name list)
local function regionText(list)
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
  for _, c in ipairs(list) do
    body[#body + 1] = "K " .. c.cx .. " " .. c.cz .. " " .. c.s .. " " .. colsText(c.d, loc)
    if #c.o > 0 then
      local o = {}
      for _, v in ipairs(c.o) do
        local b = loc(v % 4096)
        local pos = math.floor(v / 4096)
        o[#o + 1] = c1(math.floor(pos / 4096)) .. enc2(pos % 4096) .. ((b < 63) and c1(b) or ("/" .. enc2(b)))
      end
      body[#body + 1] = "O " .. c.cx .. " " .. c.cz .. " " .. table.concat(o)
    end
  end
  local head = { "M2" }
  for _, nm in ipairs(names) do head[#head + 1] = "P " .. nm end
  return table.concat(head, "\n") .. "\n" .. table.concat(body, "\n") .. "\n"
end

-- read one region file into memory
local function readRegion(path)
  local h = fs.open(path, "r")
  if not h then return end
  local glob, nloc = {}, 0
  while true do
    local line = h.readLine()
    if not line then break end
    local tag = line:sub(1, 1)
    if tag == "P" then
      glob[nloc] = MAP.pal(line:sub(3))
      nloc = nloc + 1
    elseif tag == "K" then
      local cx, cz, s, data = line:match("^K (-?%d+) (-?%d+) (%d+) (.*)$")
      if data then
        local c = chunkAt(tonumber(cx), tonumber(cz), true)
        c.s = tonumber(s)
        if c.s > MAP.tick then MAP.tick = c.s end
        readCols(data, c.d, glob)
      end
    elseif tag == "O" then
      local cx, cz, data = line:match("^O (-?%d+) (-?%d+) (.*)$")
      local c = data and MAP.ch[ckey(tonumber(cx), tonumber(cz))]
      local p = 1
      while c and p + 3 <= #data do
        local pos = (DEC[data:sub(p, p)] or 0) * 4096 + (dec2(data, p + 1) or 0)
        local ch, b = data:sub(p + 3, p + 3), nil
        if ch == "/" then b, p = glob[dec2(data, p + 4) or 0], p + 6
        else b, p = glob[DEC[ch] or 0], p + 4 end
        c.o[#c.o + 1] = pos * 4096 + (b or MAP.pal("ore"))
      end
    end
  end
  h.close()
end

-- write one region where it fits: a data floppy first (the one it is on, else
-- the one with the most room), the computer last. true if saved.
local function writeRegion(r, text, plc)
  local old = MAP.where[r]
  local need = #text + 4096                       -- the same check as saveFileSafe
  local order = {}
  for _, p in ipairs(plc) do order[#order + 1] = p end
  -- prefer floppies: the computer only when no floppy has room
  table.sort(order, function(a, b)
    if a.floppy ~= b.floppy then return a.floppy end
    local aOld, bOld = old and fs.getDir(old) == a.dir, old and fs.getDir(old) == b.dir
    if aOld ~= bOld then return aOld end
    return a.free > b.free
  end)
  for _, p in ipairs(order) do
    local path = fs.combine(p.dir, r .. ".dat")
    if p.free >= need then
      pcall(fs.makeDir, p.dir)
      if saveFileSafe(path, text) then
        if old and old ~= path and fs.exists(old) then pcall(fs.delete, old) end
        MAP.where[r] = path
        p.free = p.free - #text
        return true
      end
    end
  end
  return false
end

-- save the changed regions (toDisks = also the regions still on the computer,
-- so they move onto the data floppies). If something does not fit anywhere,
-- the oldest quarter of the map is dropped (up to four times).
-- noTrim = never drop anything (returns false instead).
function MAP.save(toDisks, noTrim)
  if toDisks then
    for r, p in pairs(MAP.where) do if fs.getDir(p) == DIR then MAP.dirty[r] = true end end
  end
  if not next(MAP.dirty) then return true end
  for tries = 0, 4 do
    local byRegion = {}
    for _, c in pairs(MAP.ch) do
      if MAP.dirty[c.r] then
        local l = byRegion[c.r]
        if not l then l = {}; byRegion[c.r] = l end
        l[#l + 1] = c
      end
    end
    -- empty regions first: deleting their files makes room for the others
    for r in pairs(MAP.dirty) do
      if not byRegion[r] then
        if MAP.where[r] and fs.exists(MAP.where[r]) then pcall(fs.delete, MAP.where[r]) end
        MAP.where[r], MAP.dirty[r] = nil, nil
      end
    end
    local plc = places()                             -- free space as it is now
    local failed = false
    for r in pairs(MAP.dirty) do
      local l = byRegion[r]
      table.sort(l, function(a, b) return a.k < b.k end)
      if writeRegion(r, regionText(l), plc) then MAP.dirty[r] = nil else failed = true end
    end
    if not failed then break end
    if noTrim then return false end
    if tries == 4 or #MAP.order <= 20 then
      state.diskLow = "Map not fully saved: no room on the computer or the data floppies"
      break
    end
    MAP.trim(math.floor(#MAP.order * 0.75))
    state.diskLow = "Disk was full: the map was reduced to its newest " .. #MAP.order .. " chunks"
  end
  MAP.savedAt = os.clock()
  return not next(MAP.dirty)
end

-- save if something changed and the last save is a minute ago (comms worker)
function MAP.autoSave()
  if next(MAP.dirty) and os.clock() - MAP.savedAt >= SAVE_EVERY then pcall(MAP.save) end
end

-- how much room the map files take: total bytes, on the computer, files
function MAP.diskUse()
  local total, onPc, files = 0, 0, 0
  for _, p in pairs(MAP.where) do
    if fs.exists(p) then
      local s = fs.getSize(p)
      total, files = total + s, files + 1
      if fs.getDir(p) == DIR then onPc = onPc + s end
    end
  end
  return total, onPc, files
end

-- forget everything (e.g. scans made with wrong coordinates)
function MAP.clear()
  MAP.version = MAP.version + 1
  for _, p in pairs(MAP.where) do if fs.exists(p) then pcall(fs.delete, p) end end
  MAP.ch, MAP.order, MAP.where, MAP.dirty = {}, {}, {}, {}
  MAP.names, MAP.nameIdx = {}, {}
  MAP.scans, MAP.tick = 0, 0
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
      local cx, cz, data = line:match("^K (-?%d+) (-?%d+) (.*)$")
      cx, cz = tonumber(cx), tonumber(cz)
      if cx and data and #data >= 1024 then
        MAP.tick = MAP.tick + 1                      -- the file lists chunks oldest first
        local c = chunkAt(cx, cz, true)
        c.s = MAP.tick
        for i = 1, 256 do
          local p = (i - 1) * 4 + 1
          if data:sub(p, p) ~= "~" then
            local hh, bb = dec2(data, p), dec2(data, p + 2)
            if hh and bb then c.d[i] = hh * 4096 + (idx[bb] or MAP.pal("unknown")) end
          end
        end
        MAP.dirty[c.r] = true
      end
    elseif tag == "O" then
      local x, y, z, b = line:match("^O (-?%d+) (-?%d+) (-?%d+) (%d+)$")
      x, z = tonumber(x), tonumber(z)
      -- only ores in chunks that are still mapped (old files kept them forever)
      if x and MAP.ch[ckey(math.floor(x / 16), math.floor(z / 16))] then
        addOre(x, tonumber(y), z, idx[tonumber(b)] or MAP.pal("ore"))
      end
    end
  end
  h.close()
  return true
end

-- read every region file (computer and data floppies); convert an old map.dat
function MAP.load()
  for _, p in ipairs(places()) do
    if fs.exists(p.dir) and fs.isDir(p.dir) then
      for _, f in ipairs(fs.list(p.dir)) do
        local r = f:match("^(%-?%d+_%-?%d+)%.dat$")
        if r and not MAP.where[r] then              -- a region twice: the first one counts
          MAP.where[r] = fs.combine(p.dir, f)
          pcall(readRegion, MAP.where[r])
        end
      end
    end
  end
  local oldFiles = {}
  for _, f in ipairs({ CONFIG.map.file, dataFile(CONFIG.map.file) }) do
    if fs.exists(f) and not oldFiles[f] then oldFiles[f] = true end
  end
  if next(oldFiles) and not next(MAP.where) then
    for f in pairs(oldFiles) do pcall(loadOld, f) break end
    MAP.trim()
    -- the old file is deleted when every region is saved. If they do not fit
    -- next to it, it goes first (everything is in memory) and the regions get
    -- its room; only then would the oldest chunks be dropped.
    local ok = MAP.save(false, true)
    for f in pairs(oldFiles) do pcall(fs.delete, f) end
    if not ok then MAP.save() end
  end
  table.sort(MAP.order, function(a, b) return MAP.ch[a].s < MAP.ch[b].s end)
  MAP.version = MAP.version + 1
end

-- a scan summary from a turtle (node.lua): absolute centre + relative data
function MAP.addScan(m)
  if type(m.cols) ~= "table" or type(m.names) ~= "table" then return end
  local x0, y0, z0 = tonumber(m.x), tonumber(m.y), tonumber(m.z)
  if not (x0 and y0 and z0) then return end
  local r = math.floor(tonumber(m.r) or 8)
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
      local x, z = x0 + (i % n - r), z0 + (math.floor(i / n) - r)
      local h, b = y0 + v[1], remap[v[2]] or MAP.pal("unknown")
      local oldH = MAP.get(x, z)
      if not oldH or h >= oldH or oldH <= top then
        MAP.set(x, z, h, b)
      end
    end
  end
  -- ores inside the scanned cube are replaced by what this scan found
  for cx = math.floor((x0 - r) / 16), math.floor((x0 + r) / 16) do
    for cz = math.floor((z0 - r) / 16), math.floor((z0 + r) / 16) do
      local c = MAP.ch[ckey(cx, cz)]
      if c and #c.o > 0 then
        local keep = {}
        for _, v in ipairs(c.o) do
          local pos = math.floor(v / 4096)
          local ox, oy, oz = cx * 16 + pos % 16, math.floor(pos / 256) - 64, cz * 16 + math.floor(pos / 16) % 16
          if math.abs(ox - x0) > r or math.abs(oy - y0) > r or math.abs(oz - z0) > r then keep[#keep + 1] = v end
        end
        c.o = keep
        MAP.dirty[c.r] = true
      end
    end
  end
  for _, o in ipairs(type(m.ores) == "table" and m.ores or {}) do
    if type(o) == "table" and tonumber(o[1]) then
      addOre(x0 + o[1], y0 + o[2], z0 + o[3], remap[o[4]] or MAP.pal("ore"))
    end
  end
  MAP.scans = MAP.scans + 1
  MAP.lastScan = os.clock()
  local touched = MAP.touched
  MAP.touched = nil
  -- the scanned square also counts as fresh where nothing new was stored
  for dx = -r, r, 8 do
    for dz = -r, r, 8 do
      local k = ckey(math.floor((x0 + dx) / 16), math.floor((z0 + dz) / 16))
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

-- colour of an ore marker
function MAP.oreColor(name)
  local n = tostring(name):lower()
  if n:find("diamond") then return colors.lightBlue end
  if n:find("emerald") then return colors.green end
  if n:find("gold") then return colors.yellow end
  if n:find("redstone") then return colors.red end
  if n:find("lapis") then return colors.blue end
  if n:find("copper") then return colors.orange end
  if n:find("iron") then return colors.pink end
  if n:find("debris") or n:find("quartz") then return colors.purple end
  return colors.white
end

-- the map view (centre, zoom, layers, rotation 0 north up .. 3 west up)
local UPS = { north = 0, east = 1, south = 2, west = 3 }
local VIEW_FILE = "map_view.dat"

-- the map view (centre, zoom, rotation); starts at Base
function MAP.view()
  if not state.mapView then
    local h = CONFIG.drone and CONFIG.drone.home
    local rot = UPS[tostring(CONFIG.map.up or "north"):lower()] or 0
    if fs.exists(VIEW_FILE) then                    -- ROTATE choice survives restarts
      local f = fs.open(VIEW_FILE, "r")
      if f then
        local t = textutils.unserialize(f.readAll() or "")
        f.close()
        if type(t) == "table" and tonumber(t.rot) then rot = tonumber(t.rot) % 4 end
      end
    end
    state.mapView = { cx = h and h.x or 0, cz = h and h.z or 0, zoom = 1, ores = true, rot = rot }
  end
  return state.mapView
end

-- save the map rotation (ROTATE) for the next start
function MAP.saveView()
  local f = fs.open(VIEW_FILE, "w")
  if f then
    f.write(textutils.serialize({ rot = MAP.view().rot }))
    f.close()
  end
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
      if known / total >= need then skipped = skipped + 1
      else spots[#spots + 1] = { x, z } end
    end
  end
  return spots, skipped
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
