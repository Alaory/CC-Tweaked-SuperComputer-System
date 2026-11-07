-- base_schem.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   SCHEMATICS for the builder turtles: Create's Schematic and Quill saves
--   `.nbt` files (the same format as Minecraft's own structures) in
--   .minecraft/schematics on your PC. Drag one onto the base computer's screen:
--   it is stored (on a data floppy when one has room, else in schematics/ on
--   the computer) and can be read here:
--     SCHEM.load(name) -> { size = {x, y, z}, palette = { {name, props}, ... },
--                           blocks = { {x, y, z, p}, ... } (p = palette index) }
--   AIR in a schematic means "must be air" (cleared); a position that is not in
--   the file at all (structure void) is left as it is.
--   The files are gzip-compressed NBT - ComputerCraft has no unpacker, so this
--   file has its own (inflate, RFC 1951) and an NBT reader. No bit operators
--   (the game's Lua has none): plain arithmetic.

SCHEM = { dir = "schematics", cache = {} }

----------------------------------------------------------------- inflate (RFC 1951)
local floor, byte, char = math.floor, string.byte, string.char
local POW = {}
for i = 0, 31 do POW[i] = 2 ^ i end

local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- a Huffman table from code lengths (lens[0..n-1]): count per length + symbols in code order
local function huff(lens, n)
  local h = { count = {}, symbol = {} }
  for l = 0, 15 do h.count[l] = 0 end
  for s = 0, n - 1 do h.count[lens[s] or 0] = h.count[lens[s] or 0] + 1 end
  local offs = { [1] = 0 }
  for l = 1, 14 do offs[l + 1] = offs[l] + h.count[l] end
  for s = 0, n - 1 do
    local l = lens[s] or 0
    if l ~= 0 then
      h.symbol[offs[l]] = s
      offs[l] = offs[l] + 1
    end
  end
  return h
end

-- data: the whole string, pos: where the deflate stream starts (1-based).
-- Returns the unpacked string (and the position after the stream).
function SCHEM.inflate(data, pos, yield)
  local bitbuf, bitcnt = 0, 0
  pos = pos or 1
  local out, n = {}, 0
  local function bits(k)
    while bitcnt < k do
      local b = byte(data, pos)
      if not b then error("schematic: the file ends too early (cut off?)", 0) end
      pos = pos + 1
      bitbuf = bitbuf + b * POW[bitcnt]
      bitcnt = bitcnt + 8
    end
    local v = bitbuf % POW[k]
    bitbuf = (bitbuf - v) / POW[k]
    bitcnt = bitcnt - k
    return v
  end
  local function decode(h)
    local code, first, index = 0, 0, 0
    local count = h.count
    for len = 1, 15 do
      code = code + bits(1)
      local c = count[len]
      if code - c < first then return h.symbol[index + (code - first)] end
      index = index + c
      first = (first + c) * 2
      code = code * 2
    end
    error("schematic: broken compressed data", 0)
  end
  local fixedL, fixedD
  local blocks = 0
  repeat
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      -- stored: byte aligned, LEN, NLEN, raw bytes
      bitbuf, bitcnt = 0, 0
      local lo, hi = byte(data, pos, pos + 1)
      local len = lo + hi * 256
      pos = pos + 4
      for i = 0, len - 1 do n = n + 1 out[n] = byte(data, pos + i) end
      pos = pos + len
    elseif kind == 1 or kind == 2 then
      local lh, dh
      if kind == 1 then
        if not fixedL then
          local l = {}
          for s = 0, 143 do l[s] = 8 end
          for s = 144, 255 do l[s] = 9 end
          for s = 256, 279 do l[s] = 7 end
          for s = 280, 287 do l[s] = 8 end
          fixedL = huff(l, 288)
          local d = {}
          for s = 0, 29 do d[s] = 5 end
          fixedD = huff(d, 30)
        end
        lh, dh = fixedL, fixedD
      else
        local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
        local cl = {}
        for i = 1, 19 do cl[CLORDER[i]] = 0 end
        for i = 1, ncode do cl[CLORDER[i]] = bits(3) end
        local ch = huff(cl, 19)
        local lens, i = {}, 0
        while i < nlen + ndist do
          local sym = decode(ch)
          if sym < 16 then
            lens[i] = sym
            i = i + 1
          else
            local rep, val = 0, 0
            if sym == 16 then
              if i == 0 then error("schematic: broken compressed data", 0) end
              val, rep = lens[i - 1], 3 + bits(2)
            elseif sym == 17 then rep = 3 + bits(3)
            else rep = 11 + bits(7) end
            for _ = 1, rep do lens[i] = val i = i + 1 end
          end
        end
        local ll, dl = {}, {}
        for s = 0, nlen - 1 do ll[s] = lens[s] end
        for s = 0, ndist - 1 do dl[s] = lens[nlen + s] end
        lh, dh = huff(ll, nlen), huff(dl, ndist)
      end
      while true do
        local sym = decode(lh)
        if sym < 256 then
          n = n + 1
          out[n] = sym
        elseif sym == 256 then
          break
        else
          sym = sym - 257
          local len = LBASE[sym + 1] + bits(LEXT[sym + 1])
          local ds = decode(dh)
          local dist = DBASE[ds + 1] + bits(DEXT[ds + 1])
          local from = n - dist
          for k = 1, len do out[n + k] = out[from + k] end
          n = n + len
        end
      end
    else
      error("schematic: unknown compressed block type", 0)
    end
    blocks = blocks + 1
    if yield and blocks % 4 == 0 then yield() end
  until last == 1
  -- bytes -> string, in pieces (unpack has a limit)
  local parts = {}
  local unpack = table.unpack or unpack
  for i = 1, n, 4096 do parts[#parts + 1] = char(unpack(out, i, math.min(n, i + 4095))) end
  return table.concat(parts), pos
end

-- gzip (1f 8b) or zlib (78 ..) or plain NBT
function SCHEM.unpack(data, yield)
  local b1, b2, method, flags = byte(data, 1, 4)
  if b1 == 0x1f and b2 == 0x8b then
    if method ~= 8 then error("schematic: unknown compression", 0) end
    local pos = 11
    local function flag(bit) return floor(flags / POW[bit]) % 2 == 1 end
    if flag(2) then local lo, hi = byte(data, pos, pos + 1) pos = pos + 2 + lo + hi * 256 end   -- FEXTRA
    if flag(3) then pos = (data:find("\0", pos, true) or pos) + 1 end                          -- FNAME
    if flag(4) then pos = (data:find("\0", pos, true) or pos) + 1 end                          -- FCOMMENT
    if flag(1) then pos = pos + 2 end                                                         -- FHCRC
    return (SCHEM.inflate(data, pos, yield))
  elseif b1 == 0x78 then
    return (SCHEM.inflate(data, 3, yield))
  end
  return data
end

----------------------------------------------------------------- NBT
-- returns the root compound as a Lua table: compounds = tables by name,
-- lists / arrays = Lua arrays, numbers = numbers (longs as doubles: exact up to 2^53)
function SCHEM.nbt(s, yield)
  local pos = 1
  local reads = 0
  local function u8() local b = byte(s, pos) pos = pos + 1 return b end
  local function int(nb, signed)
    local v = 0
    for i = 0, nb - 1 do v = v * 256 + byte(s, pos + i) end
    pos = pos + nb
    if signed and v >= POW[nb * 8 - 1] then v = v - 2 ^ (nb * 8) end
    return v
  end
  local function float(nb)
    local b = { byte(s, pos, pos + nb - 1) }
    pos = pos + nb
    local sign = b[1] >= 128 and -1 or 1
    local mbits = (nb == 4) and 23 or 52
    -- exponent / mantissa from the bytes (big-endian), arithmetic only
    local e, m = 0, 0
    if nb == 4 then
      e = (b[1] % 128) * 2 + floor(b[2] / 128)
      m = ((b[2] % 128) * 256 + b[3]) * 256 + b[4]
    else
      e = (b[1] % 128) * 16 + floor(b[2] / 16)
      m = (b[2] % 16)
      for i = 3, 8 do m = m * 256 + b[i] end
    end
    local bias = (nb == 4) and 127 or 1023
    if e == 0 then
      if m == 0 then return 0 end
      return sign * m * 2 ^ (1 - bias - mbits)
    elseif e == (nb == 4 and 255 or 2047) then
      return (m == 0) and sign * math.huge or 0 / 0
    end
    return sign * (1 + m / 2 ^ mbits) * 2 ^ (e - bias)
  end
  local function str()
    local len = int(2)
    local v = s:sub(pos, pos + len - 1)
    pos = pos + len
    return v
  end
  local read
  read = function(t)
    reads = reads + 1
    if yield and reads % 2000 == 0 then yield() end
    if t == 1 then return int(1, true)
    elseif t == 2 then return int(2, true)
    elseif t == 3 then return int(4, true)
    elseif t == 4 then return int(8, true)
    elseif t == 5 then return float(4)
    elseif t == 6 then return float(8)
    elseif t == 7 then
      local n = int(4, true)
      local a = { byte(s, pos, pos + n - 1) }
      pos = pos + n
      return a
    elseif t == 8 then return str()
    elseif t == 9 then
      local et, n = u8(), int(4, true)
      local a = {}
      for i = 1, n do a[i] = read(et) end
      return a
    elseif t == 10 then
      local c = {}
      while true do
        local tt = u8()
        if tt == 0 or tt == nil then break end
        local name = str()
        c[name] = read(tt)
      end
      return c
    elseif t == 11 then
      local n = int(4, true)
      local a = {}
      for i = 1, n do a[i] = int(4, true) end
      return a
    elseif t == 12 then
      local n = int(4, true)
      local a = {}
      for i = 1, n do a[i] = int(8, true) end
      return a
    end
    error("schematic: unknown NBT tag " .. tostring(t), 0)
  end
  local rootType = u8()
  if rootType ~= 10 then error("schematic: not an NBT file", 0) end
  str()                                     -- root name (empty)
  return read(10)
end

----------------------------------------------------------------- the structure format
-- (Create's Schematic and Quill / structure blocks / Minecraft's own structures)
function SCHEM.parse(data, yield)
  local root = SCHEM.nbt(SCHEM.unpack(data, yield), yield)
  local size = root.size
  local pal = root.palette or (type(root.palettes) == "table" and root.palettes[1])
  if type(size) ~= "table" or type(pal) ~= "table" or type(root.blocks) ~= "table" then
    if root.Schematic or root.Regions then error("this is a Litematica / WorldEdit file - save it with Create's Schematic and Quill (.nbt)", 0) end
    error("not a structure / Create schematic (.nbt) file", 0)
  end
  local s = { size = { x = size[1], y = size[2], z = size[3] }, palette = {}, blocks = {}, data = root.DataVersion }
  for i, e in ipairs(pal) do s.palette[i] = { name = tostring(e.Name), props = e.Properties or {} } end
  for _, b in ipairs(root.blocks) do
    local p = b.pos
    if type(p) == "table" then s.blocks[#s.blocks + 1] = { p[1], p[2], p[3], (b.state or 0) + 1 } end
  end
  return s
end

-- block -> the item that places it (nil = nothing to place: air, a part of a
-- two-block thing, fluids ...)
local SKIP = { ["minecraft:air"] = true, ["minecraft:cave_air"] = true, ["minecraft:void_air"] = true,
               ["minecraft:structure_void"] = true, ["minecraft:piston_head"] = true, ["minecraft:moving_piston"] = true,
               ["minecraft:fire"] = true, ["minecraft:soul_fire"] = true, ["minecraft:nether_portal"] = true,
               ["minecraft:end_portal"] = true, ["minecraft:end_gateway"] = true, ["minecraft:bubble_column"] = true }
local ITEM = { ["minecraft:wall_torch"] = "minecraft:torch", ["minecraft:soul_wall_torch"] = "minecraft:soul_torch",
               ["minecraft:redstone_wall_torch"] = "minecraft:redstone_torch", ["minecraft:redstone_wire"] = "minecraft:redstone",
               ["minecraft:tripwire"] = "minecraft:string", ["minecraft:water"] = "minecraft:water_bucket",
               ["minecraft:lava"] = "minecraft:lava_bucket", ["minecraft:farmland"] = "minecraft:dirt",
               ["minecraft:dirt_path"] = "minecraft:dirt" }
function SCHEM.itemOf(e)
  local n = e.name
  if SKIP[n] then return nil end
  local pr = e.props or {}
  -- two-block things: only one half needs an item
  if pr.half == "upper" and (n:find("_door", 1, true) or n:find("sunflower") or n:find("lilac") or n:find("peony")
     or n:find("rose_bush") or n:find("tall_grass") or n:find("large_fern")) then return nil end
  if pr.part == "head" and n:find("_bed", 1, true) then return nil end
  if ITEM[n] then return ITEM[n] end
  if n:find("_wall_sign", 1, true) then return (n:gsub("_wall_sign", "_sign")) end
  if n:find("_wall_hanging_sign", 1, true) then return (n:gsub("_wall_hanging_sign", "_hanging_sign")) end
  if n:find("_wall_banner", 1, true) then return (n:gsub("_wall_banner", "_banner")) end
  if n:find("_wall_head", 1, true) then return (n:gsub("_wall_head", "_head")) end
  if n:find("_wall_skull", 1, true) then return (n:gsub("_wall_skull", "_skull")) end
  if n:find("_wall_fan", 1, true) then return (n:gsub("_wall_fan", "_fan")) end
  if n:find("potted_", 1, true) then return "minecraft:flower_pot" end
  return n
end
function SCHEM.isAir(e) return e.name == "minecraft:air" or e.name == "minecraft:cave_air" or e.name == "minecraft:void_air" end

-- what a schematic needs: { [item] = count }, blocks to place, air to clear
function SCHEM.materials(s)
  local need, place, air = {}, 0, 0
  local slabs = {}
  for _, b in ipairs(s.blocks) do
    local e = s.palette[b[4]]
    if SCHEM.isAir(e) then
      air = air + 1
    else
      local it = SCHEM.itemOf(e)
      if it then
        local c = 1
        if e.props.type == "double" and it:find("_slab", 1, true) then c = 2 end      -- a double slab = 2 slabs
        need[it] = (need[it] or 0) + c
        place = place + 1
      end
    end
  end
  return need, place, air
end

----------------------------------------------------------------- the library
-- where schematic files can be: data floppies (schematics/) and this computer
local function dirs()
  local out = {}
  for _, d in ipairs(mountedDisks and mountedDisks() or {}) do
    if d.data then out[#out + 1] = { dir = fs.combine(d.mount, SCHEM.dir), free = d.free, floppy = true } end
  end
  local okF, free = pcall(fs.getFreeSpace, "/")
  out[#out + 1] = { dir = SCHEM.dir, free = okF and free or 0 }
  return out
end
-- every schematic: { [name] = path }
function SCHEM.list()
  local out = {}
  for _, d in ipairs(dirs()) do
    if fs.exists(d.dir) and fs.isDir(d.dir) then
      for _, f in ipairs(fs.list(d.dir)) do
        local name = f:match("^(.+)%.nbt$")
        if name and not out[name] then out[name] = fs.combine(d.dir, f) end
      end
    end
  end
  return out
end
-- a clean file name (letters, digits, - _)
function SCHEM.cleanName(n)
  n = tostring(n):gsub("%.nbt$", ""):gsub("[^%w%-_]", "_")
  return n:sub(1, 40)
end
-- store a schematic (bytes): a data floppy with room first, else this computer
-- (leaving 96 KB free). Checked first: it must read as a schematic.
function SCHEM.store(name, data)
  name = SCHEM.cleanName(name)
  local okP, s = pcall(SCHEM.parse, data)
  if not okP then return false, tostring(s) end
  for _, d in ipairs(dirs()) do
    local room = d.floppy and (d.free - 2048) or (d.free - 96 * 1024)
    if room > #data then
      pcall(fs.makeDir, d.dir)
      local path = fs.combine(d.dir, name .. ".nbt")
      local tmp = path .. ".tmp"
      local h = fs.open(tmp, "wb")
      if h then
        local okW = pcall(h.write, data)
        pcall(h.close)
        if okW then
          if fs.exists(path) then fs.delete(path) end
          fs.move(tmp, path)
          SCHEM.cache[name] = { s = s, path = path }
          return true, path, s
        end
        pcall(fs.delete, tmp)
      end
    end
  end
  return false, "no room for it (" .. math.ceil(#data / 1024) .. " KB) - put an empty floppy in and type  disks data"
end
-- read one (cached)
function SCHEM.load(name)
  local c = SCHEM.cache[name]
  if c then return c.s end
  local path = SCHEM.list()[name]
  if not path then return nil, "no schematic '" .. tostring(name) .. "'" end
  local h = fs.open(path, "rb")
  if not h then return nil, "cannot open " .. path end
  local data = h.readAll()
  h.close()
  local ok, s = pcall(SCHEM.parse, data, TT and TT.workYield)
  if not ok then return nil, tostring(s) end
  SCHEM.cache[name] = { s = s, path = path }
  return s
end
function SCHEM.delete(name)
  local path = SCHEM.list()[name]
  if not path then return false end
  fs.delete(path)
  SCHEM.cache[name] = nil
  return true
end

-- a file dropped onto the computer's screen (event "file_transfer")
function SCHEM.onTransfer(transfer)
  local files = {}
  if type(transfer) == "table" and type(transfer.getFiles) == "function" then files = transfer.getFiles() or {} end
  for _, f in ipairs(files) do
    local name = (type(f.getName) == "function" and f.getName()) or "schematic"
    local data = f.readAll() or ""
    pcall(f.close)
    name = fs.getName(name)
    if name:lower():match("%.nbt$") then
      local ok, where, s = SCHEM.store(name, data)
      if ok then
        local _, place = SCHEM.materials(s)
        pushNote("DONE", "Schematic '" .. SCHEM.cleanName(name) .. "' stored: " .. s.size.x .. " x " .. s.size.y .. " x " ..
                 s.size.z .. ", " .. place .. " blocks - type  schem  on the computer", C.good)
        if sysLog then sysLog("Schematic stored: " .. where, "INFO") end
      else
        pushNote("WARNING", "Schematic " .. name .. " not stored: " .. tostring(where), C.warn)
      end
    else
      pushNote("WARNING", name .. ": only Create schematics (.nbt) can be dropped here", C.warn)
    end
  end
end
