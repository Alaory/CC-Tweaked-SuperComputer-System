-- base_map.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MAP tab data: top block of every scanned column and ores, from the turtles'
--   Geo Scanner scans. Stored per chunk in map.dat (oldest chunks dropped),
--   plus block colours, map rotation and the spots for a survey.

---------------------------------------------------------------------
-- MAP DATA  (top block of every scanned column + ores, from turtle scans)
---------------------------------------------------------------------
MAP = {
  cols = {},       -- cols[x][z] = { height, palette index }
  chunks = {},     -- [chunk key] = true
  order = {},      -- chunk keys, oldest first (for the size limit)
  names = {},      -- palette: index -> block name
  nameIdx = {},    -- block name -> index
  ores = {},       -- ["x,y,z"] = { x, y, z, b }
  scans = 0,
  version = 0,     -- goes up whenever the map data changes (the page caches its image)
}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
-- 0..4095 -> 2 characters (compact map file)
local function enc2(v)
  v = math.max(0, math.min(4095, math.floor(v)))
  local hi, lo = math.floor(v / 64), v % 64
  return B64:sub(hi + 1, hi + 1) .. B64:sub(lo + 1, lo + 1)
end
local DEC = {}
for i = 1, #B64 do DEC[B64:sub(i, i)] = i - 1 end
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

-- key of a chunk
local function ckey(cx, cz) return cx .. "," .. cz end

-- { height, block } of a map column, or nil
function MAP.get(x, z)
  local col = MAP.cols[x]
  return col and col[z]
end

-- set a map column (and note its chunk)
function MAP.set(x, z, h, b)
  MAP.version = MAP.version + 1
  local col = MAP.cols[x]
  if not col then col = {}; MAP.cols[x] = col end
  col[z] = { h, b }
  local k = ckey(math.floor(x / 16), math.floor(z / 16))
  if not MAP.chunks[k] then
    MAP.chunks[k] = true
    MAP.order[#MAP.order + 1] = k
  end
  if MAP.touched then MAP.touched[k] = true end
end

-- chunks touched by a scan move to the "newest" end, so the size limit drops
-- the chunks that were not scanned for the longest time
local function refreshOrder(touched)
  local keep, moved = {}, {}
  for _, k in ipairs(MAP.order) do
    if touched[k] then moved[#moved + 1] = k else keep[#keep + 1] = k end
  end
  for _, k in ipairs(moved) do keep[#keep + 1] = k end
  MAP.order = keep
end

-- is there anything to show on the MAP tab?
function MAP.hasData() return MAP.scans > 0 or #MAP.order > 0 end

-- forget everything (e.g. scans made with wrong coordinates)
function MAP.clear()
  MAP.version = MAP.version + 1
  MAP.cols, MAP.chunks, MAP.order, MAP.ores = {}, {}, {}, {}
  MAP.names, MAP.nameIdx = {}, {}
  MAP.scans = 0
  -- the map file wherever it is (computer and data floppy)
  for _, p in ipairs({ CONFIG.map.file, dataFile(CONFIG.map.file, true) }) do
    if fs.exists(p) then fs.delete(p) end
  end
end

-- keep at most CONFIG.map.maxChunks chunks (drop the oldest)
function MAP.trim()
  MAP.version = MAP.version + 1
  local max = CONFIG.map.maxChunks or 300
  while #MAP.order > max do
    local k = table.remove(MAP.order, 1)
    MAP.chunks[k] = nil
    local cx, cz = k:match("^(-?%d+),(-?%d+)$")
    cx, cz = tonumber(cx), tonumber(cz)
    for x = cx * 16, cx * 16 + 15 do
      local col = MAP.cols[x]
      if col then
        for z = cz * 16, cz * 16 + 15 do col[z] = nil end
      end
    end
  end
end

-- compact file: palette lines, one line per chunk (4 chars per column), ores
-- the whole map file as text
local function mapText()
  local lines = {}
  for _, n in ipairs(MAP.names) do lines[#lines + 1] = "P " .. n end
  for _, k in ipairs(MAP.order) do
    local cx, cz = k:match("^(-?%d+),(-?%d+)$")
    cx, cz = tonumber(cx), tonumber(cz)
    local parts = {}
    for z = cz * 16, cz * 16 + 15 do
      for x = cx * 16, cx * 16 + 15 do
        local c = MAP.get(x, z)
        parts[#parts + 1] = c and (enc2(c[1] + 64) .. enc2(c[2])) or "~~~~"
      end
    end
    lines[#lines + 1] = "K " .. cx .. " " .. cz .. " " .. table.concat(parts)
  end
  for _, o in pairs(MAP.ores) do
    lines[#lines + 1] = "O " .. o.x .. " " .. o.y .. " " .. o.z .. " " .. o.b
  end
  return table.concat(lines, "\n") .. "\n"
end

-- save safely; if the map does not fit on the disk, drop its oldest quarter
-- (up to four times) until it does - the old file stays intact meanwhile
function MAP.save()
  local path = dataFile(CONFIG.map.file, true)
  local ok = saveFileSafe(path, mapText())
  local tries = 0
  while not ok and #MAP.order > 20 and tries < 4 do
    tries = tries + 1
    local was = CONFIG.map.maxChunks
    CONFIG.map.maxChunks = math.floor(#MAP.order * 0.75)
    MAP.trim()
    CONFIG.map.maxChunks = was
    ok = saveFileSafe(path, mapText())
  end
  if ok then dropOldCopy(CONFIG.map.file, path, #MAP.order == 0) end
  if ok and tries > 0 then
    state.diskLow = "Disk was full: the map was reduced to its newest " .. #MAP.order .. " chunks"
  end
  return ok
end

-- read map.dat (wherever it is: computer or data floppy)
function MAP.load()
  local f = dataFile(CONFIG.map.file)
  if not fs.exists(f) then return end
  local h = fs.open(f, "r")
  if not h then return end
  while true do
    local line = h.readLine()
    if not line then break end
    local tag = line:sub(1, 1)
    if tag == "P" then
      MAP.pal(line:sub(3))
    elseif tag == "K" then
      local cx, cz, data = line:match("^K (-?%d+) (-?%d+) (.*)$")
      cx, cz = tonumber(cx), tonumber(cz)
      if cx and data and #data >= 1024 then
        local p = 1
        for z = cz * 16, cz * 16 + 15 do
          for x = cx * 16, cx * 16 + 15 do
            if data:sub(p, p) ~= "~" then
              local hh, bb = dec2(data, p), dec2(data, p + 2)
              if hh and bb then MAP.set(x, z, hh - 64, bb) end
            end
            p = p + 4
          end
        end
      end
    elseif tag == "O" then
      local x, y, z, b = line:match("^O (-?%d+) (-?%d+) (-?%d+) (%d+)$")
      if x then
        x, y, z, b = tonumber(x), tonumber(y), tonumber(z), tonumber(b)
        MAP.ores[x .. "," .. y .. "," .. z] = { x = x, y = y, z = z, b = b }
      end
    end
  end
  h.close()
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
      local old = MAP.get(x, z)
      if not old or h >= old[1] or old[1] <= top then
        MAP.set(x, z, h, b)
      end
    end
  end
  -- ores inside the scanned cube are replaced by what this scan found
  for k, o in pairs(MAP.ores) do
    if math.abs(o.x - x0) <= r and math.abs(o.y - y0) <= r and math.abs(o.z - z0) <= r then
      MAP.ores[k] = nil
    end
  end
  for _, o in ipairs(type(m.ores) == "table" and m.ores or {}) do
    if type(o) == "table" and tonumber(o[1]) then
      local x, y, z = x0 + o[1], y0 + o[2], z0 + o[3]
      MAP.ores[x .. "," .. y .. "," .. z] = { x = x, y = y, z = z, b = remap[o[4]] or MAP.pal("ore") }
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
      if MAP.chunks[k] then touched[k] = true end
    end
  end
  refreshOrder(touched)
  MAP.trim()
  pcall(MAP.save)
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
