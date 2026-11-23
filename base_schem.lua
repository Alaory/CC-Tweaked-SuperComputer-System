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
  local blocks, syms = 0, 0
  repeat
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      -- stored: byte aligned, LEN, NLEN, raw bytes
      bitbuf, bitcnt = 0, 0
      local lo, hi, nlo, nhi = byte(data, pos, pos + 3)
      if not nhi then error("schematic: the file ends too early (cut off?)", 0) end
      local len = lo + hi * 256
      if len + nlo + nhi * 256 ~= 65535 then error("schematic: broken compressed data", 0) end
      pos = pos + 4
      if pos + len - 1 > #data then error("schematic: the file ends too early (cut off?)", 0) end
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
        syms = syms + 1
        if yield and syms % 16384 == 0 then yield() end      -- (one block can hold a lot)
        if not sym or sym > 285 then error("schematic: broken compressed data", 0) end
        if sym < 256 then
          n = n + 1
          out[n] = sym
        elseif sym == 256 then
          break
        else
          sym = sym - 257
          local len = LBASE[sym + 1] + bits(LEXT[sym + 1])
          local ds = decode(dh)
          if not ds or ds > 29 then error("schematic: broken compressed data", 0) end
          local dist = DBASE[ds + 1] + bits(DEXT[ds + 1])
          local from = n - dist
          if from < 0 then error("schematic: broken compressed data", 0) end
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
  local function short() error("schematic: the file ends too early (cut off?)", 0) end
  local function u8() local b = byte(s, pos) pos = pos + 1 return b end
  -- (a LONG is 8 bytes: 2 ^ 63 - POW stops at 2 ^ 31; POW[63] = nil made every file with a long tag fail -
  --  Create's machines keep their network id as one)
  local function int(nb, signed)
    if pos + nb - 1 > #s then short() end
    local v = 0
    if signed and byte(s, pos) >= 128 then
      -- negative: from the inverted bytes (exact for small ones; 2 ^ 64 - 1 as a double is not)
      for i = 0, nb - 1 do v = v * 256 + (255 - byte(s, pos + i)) end
      v = -v - 1
    else
      for i = 0, nb - 1 do v = v * 256 + byte(s, pos + i) end
    end
    pos = pos + nb
    return v
  end
  local function float(nb)
    if pos + nb - 1 > #s then short() end
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
    if pos + len - 1 > #s then short() end
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
      if n < 0 or pos + n - 1 > #s then short() end
      local a = {}
      for i = 0, n - 1, 4000 do                        -- (string.byte gives at most a few thousand at once)
        local part = { byte(s, pos + i, pos + math.min(n - 1, i + 3999)) }
        for k = 1, #part do a[i + k] = part[k] end
      end
      pos = pos + n
      return a
    elseif t == 8 then return str()
    elseif t == 9 then
      local et, n = u8(), int(4, true)
      if n > 0 and et == 0 then error("schematic: broken NBT list", 0) end
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
  local sx, sy, sz = tonumber(size[1]), tonumber(size[2]), tonumber(size[3])
  if not (sx and sy and sz and sx >= 1 and sy >= 1 and sz >= 1) then error("schematic: its size is missing / broken", 0) end
  local s = { size = { x = sx, y = sy, z = sz }, palette = {}, blocks = {}, data = root.DataVersion }
  for i, e in ipairs(pal) do
    if type(e) ~= "table" then e = {} end
    s.palette[i] = { name = tostring(e.Name), props = type(e.Properties) == "table" and e.Properties or {} }
  end
  -- (a block whose palette number or spot is not in the file is left out: one odd entry stopped the
  --  materials list / the build with a Lua error)
  for _, b in ipairs(root.blocks) do
    local p = type(b) == "table" and b.pos
    local st = type(b) == "table" and tonumber(b.state or 0)
    if type(p) == "table" and st and s.palette[st + 1] then
      local x, y, z = tonumber(p[1]), tonumber(p[2]), tonumber(p[3])
      if x and y and z and x >= 0 and y >= 0 and z >= 0 and x < sx and y < sy and z < sz then
        s.blocks[#s.blocks + 1] = { x, y, z, st + 1 }
      end
    end
  end
  return s
end

-- block -> the item that places it (nil = nothing to place: air, a part of a
-- two-block thing, fluids ...)
local SKIP = { ["minecraft:air"] = true, ["minecraft:cave_air"] = true, ["minecraft:void_air"] = true,
               ["minecraft:structure_void"] = true, ["minecraft:piston_head"] = true, ["minecraft:moving_piston"] = true,
               ["minecraft:fire"] = true, ["minecraft:soul_fire"] = true, ["minecraft:nether_portal"] = true,
               ["minecraft:end_portal"] = true, ["minecraft:end_gateway"] = true, ["minecraft:bubble_column"] = true,
               ["minecraft:frosted_ice"] = true, ["minecraft:light"] = true }
local ITEM = { ["minecraft:wall_torch"] = "minecraft:torch", ["minecraft:soul_wall_torch"] = "minecraft:soul_torch",
               ["minecraft:redstone_wall_torch"] = "minecraft:redstone_torch", ["minecraft:redstone_wire"] = "minecraft:redstone",
               ["minecraft:tripwire"] = "minecraft:string", ["minecraft:water"] = "minecraft:water_bucket",
               ["minecraft:lava"] = "minecraft:lava_bucket", ["minecraft:farmland"] = "minecraft:dirt",
               ["minecraft:dirt_path"] = "minecraft:dirt",
               -- (a block whose name is not an item: a build waited for "carrots" in AE2 for ever)
               ["minecraft:carrots"] = "minecraft:carrot", ["minecraft:potatoes"] = "minecraft:potato",
               ["minecraft:wheat"] = "minecraft:wheat_seeds", ["minecraft:beetroots"] = "minecraft:beetroot_seeds",
               ["minecraft:cocoa"] = "minecraft:cocoa_beans", ["minecraft:sweet_berry_bush"] = "minecraft:sweet_berries",
               ["minecraft:melon_stem"] = "minecraft:melon_seeds", ["minecraft:attached_melon_stem"] = "minecraft:melon_seeds",
               ["minecraft:pumpkin_stem"] = "minecraft:pumpkin_seeds", ["minecraft:attached_pumpkin_stem"] = "minecraft:pumpkin_seeds",
               ["minecraft:torchflower_crop"] = "minecraft:torchflower_seeds", ["minecraft:pitcher_crop"] = "minecraft:pitcher_pod",
               ["minecraft:kelp_plant"] = "minecraft:kelp", ["minecraft:cave_vines"] = "minecraft:glow_berries",
               ["minecraft:cave_vines_plant"] = "minecraft:glow_berries", ["minecraft:twisting_vines_plant"] = "minecraft:twisting_vines",
               ["minecraft:weeping_vines_plant"] = "minecraft:weeping_vines", ["minecraft:big_dripleaf_stem"] = "minecraft:big_dripleaf",
               ["minecraft:bamboo_sapling"] = "minecraft:bamboo", ["minecraft:tall_seagrass"] = "minecraft:seagrass",
               ["minecraft:water_cauldron"] = "minecraft:cauldron", ["minecraft:lava_cauldron"] = "minecraft:cauldron",
               ["minecraft:powder_snow_cauldron"] = "minecraft:cauldron", ["minecraft:candle_cake"] = "minecraft:cake",
               ["minecraft:powder_snow"] = "minecraft:powder_snow_bucket" }
-- a fluid block (water, lava, a modded fluid): only "level" as its property - not by drone
function SCHEM.isFluid(e)
  local n, pr = tostring(e.name), e.props or {}
  if n == "minecraft:water" or n == "minecraft:lava" then return true end
  if pr.level == nil or n:find("cauldron", 1, true) or n:find("composter", 1, true) then return false end
  for k in pairs(pr) do if k ~= "level" then return false end end
  return true
end
function SCHEM.itemOf(e)
  local n = e.name
  if SKIP[n] then return nil end
  local pr = e.props or {}
  -- two-block things: only one half needs an item (doors, tall flowers / grass, seagrass, dripleaf, pitcher plants,
  -- modded ones - stairs and trapdoors say top / bottom, not upper)
  if pr.half == "upper" then return nil end
  if SCHEM.isFluid(e) and not ITEM[n] then return n .. "_bucket" end
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

-- what a schematic needs: { [item] = count }, blocks to place, air to clear, fluid blocks left out (drones
-- place no fluids - the same as DW.plan; a water block was listed as "short: water bucket")
function SCHEM.materials(s)
  local need, place, air, fluids = {}, 0, 0, 0
  for _, b in ipairs(s.blocks) do
    local e = s.palette[b[4]]
    if not e then
      -- (not in the palette: left out)
    elseif SCHEM.isAir(e) then
      air = air + 1
    else
      local it = SCHEM.itemOf(e)
      if it and it:find("_bucket", 1, true) then
        fluids = fluids + 1
      elseif it then
        local c = 1
        if e.props.type == "double" and it:find("_slab", 1, true) then c = 2 end      -- a double slab = 2 slabs
        need[it] = (need[it] or 0) + c
        place = place + 1
      end
    end
  end
  return need, place, air, fluids
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
-- ON A STORAGE HELPER (the owner: "how do I upload a schematic when the main computer does not have enough storage"):
-- the computer keeps 96 KB free and the data floppies are full of map / voice files - a dropped schematic was refused.
-- A storage helper (store.lua, megabytes free) takes it FIRST. store.lua reads / writes text, a schematic is binary
-- (gzip): it goes there as base64 ("store:<id>/schematics/<name>.b64"). Which helper holds which one is kept HERE
-- (schem_where.dat) - listing them never asks the cable (the page / the comms worker must not wait).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64C, B64V = {}, {}
for i = 1, 64 do B64C[i - 1] = B64:sub(i, i) B64V[B64:byte(i)] = i - 1 end
function SCHEM.enc(data, yield)
  local out, part, n = {}, {}, 0
  for i = 1, #data, 3 do
    local a, b, c = byte(data, i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    n = n + 1
    part[n] = B64C[floor(v / 262144) % 64] .. B64C[floor(v / 4096) % 64] .. (b and B64C[floor(v / 64) % 64] or "=") .. (c and B64C[v % 64] or "=")
    if n >= 2048 then out[#out + 1] = table.concat(part) part, n = {}, 0 if yield then yield() end end
  end
  out[#out + 1] = table.concat(part)
  return table.concat(out)
end
function SCHEM.dec(text, yield)
  local out, part, n, k = {}, {}, 0, 0
  local v, got = 0, 0
  for i = 1, #text do
    local x = B64V[byte(text, i)]
    if x then
      v, got = v * 64 + x, got + 1
      if got == 4 then
        n = n + 1
        part[n] = char(floor(v / 65536) % 256, floor(v / 256) % 256, v % 256)
        v, got = 0, 0
        if n >= 4096 then out[#out + 1] = table.concat(part) part, n = {}, 0 if yield then yield() end end
      end
    end
  end
  if got == 3 then n = n + 1 part[n] = char(floor(v / 1024) % 256, floor(v / 4) % 256)          -- (one "=")
  elseif got == 2 then n = n + 1 part[n] = char(floor(v / 16) % 256) end                      -- (two "=")
  out[#out + 1] = table.concat(part)
  return table.concat(out)
end
SCHEM.WHERE_FILE = "schem_where.dat"
function SCHEM.remote()
  if not SCHEM.where then
    local t = readSafe and readSafe(SCHEM.WHERE_FILE)
    SCHEM.where = {}
    if type(t) == "table" then
      for k, v in pairs(t) do if type(k) == "string" and type(v) == "string" and v:match("^store:%d+/") then SCHEM.where[k] = v end end
    end
  end
  return SCHEM.where
end
local function saveWhere()
  local w = SCHEM.remote()
  if next(w) == nil then pcall(fs.delete, SCHEM.WHERE_FILE) return end
  if writeSafe then writeSafe(SCHEM.WHERE_FILE, serialSmall and serialSmall(w) or textutils.serialize(w)) end
end
local function isRemote(p) return type(p) == "string" and p:match("^store:%d+/") ~= nil end
local function delAny(p)
  if isRemote(p) then if STORE and STORE.delete then pcall(STORE.delete, p) end else pcall(fs.delete, p) end
end
-- a helper with room: the encoded text written and read back; nil, why when none could take it
local function toHelper(name, data, yield)
  if not (STORE and type(STORE.helpers) == "table" and STORE.write and STORE.read) then return nil end
  local enc = SCHEM.enc(data, yield)
  local ids = {}
  for id, h in pairs(STORE.helpers) do
    if (not STORE.usable or STORE.usable(h)) and (tonumber(h.free) or 0) >= #enc + 32 * 1024 then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b) return (tonumber(STORE.helpers[a].free) or 0) > (tonumber(STORE.helpers[b].free) or 0) end)
  for _, id in ipairs(ids) do
    local p = "store:" .. id .. "/" .. SCHEM.dir .. "/" .. name .. ".b64"
    local okW = STORE.write(p, enc)
    if okW and STORE.read(p) == enc then return p end
  end
  return nil
end
-- every file of one name in every place (a copy on another floppy, on a helper)
local function allPaths(name)
  local out = {}
  for _, d in ipairs(dirs()) do
    local p = fs.combine(d.dir, name .. ".nbt")
    if fs.exists(p) then out[#out + 1] = p end
  end
  local r = SCHEM.remote()[name]
  if r then out[#out + 1] = r end
  return out
end
-- the parsed schematics kept in memory: the newest few (a big one is megabytes of tables) + the one being built
SCHEM.KEEP = 4
function SCHEM.remember(name, s, path)
  SCHEM.cache[name] = { s = s, path = path, used = os.clock() }
  local n, oldest, oldT = 0, nil, nil
  for k, c in pairs(SCHEM.cache) do
    n = n + 1
    if k ~= name and not (DW and DW.job and DW.job.name == k) and (not oldT or (c.used or 0) < oldT) then oldest, oldT = k, c.used or 0 end
  end
  if n > SCHEM.KEEP and oldest then SCHEM.cache[oldest] = nil end
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
  for name, p in pairs(SCHEM.remote()) do if not out[name] then out[name] = p end end
  return out
end
-- a clean file name (letters, digits, - _)
function SCHEM.cleanName(n)
  n = tostring(n):gsub("%.nbt$", ""):gsub("[^%w%-_]", "_")
  return n:sub(1, 40)
end
-- store a schematic (bytes): a data floppy with room first, else this computer
-- (leaving 96 KB free). Checked first: it must read as a schematic.
function SCHEM.store(name, data, yield)
  name = SCHEM.cleanName(name)
  local okP, s = pcall(SCHEM.parse, data, yield)
  if not okP then return false, tostring(s) end
  local rp = toHelper(name, data, yield)
  if rp then
    for _, other in ipairs(allPaths(name)) do if other ~= rp then delAny(other) end end
    SCHEM.remote()[name] = rp
    saveWhere()
    SCHEM.remember(name, s, rp)
    return true, rp, s
  end
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
          -- (an older file of the same name somewhere else goes: SCHEM.list takes the first one it finds - after a
          --  restart the OLD schematic came back)
          for _, other in ipairs(allPaths(name)) do delAny(other) end
          if SCHEM.remote()[name] then SCHEM.remote()[name] = nil saveWhere() end
          fs.move(tmp, path)
          SCHEM.remember(name, s, path)
          return true, path, s
        end
        pcall(fs.delete, tmp)
      end
    end
  end
  return false, "no room for it (" .. math.ceil(#data / 1024) .. " KB): no storage helper answered with room, the data floppies and " ..
               "the computer are full - start a storage helper (store.lua) or put an empty floppy in and type  disks data"
end
-- the parsed one if it is in memory (no disk, nothing waits)
function SCHEM.get(name)
  local c = SCHEM.cache[name]
  if c then c.used = os.clock() return c.s end
end
-- read one now (cached). Unpacking a big file takes seconds in the game: in the map worker it pauses (TT.workYield);
-- any other worker (console, chat, actions) asks the MAP WORKER and waits for it - parsing it there without a pause
-- stopped the computer ("too long without yielding")
-- is there a map worker to read it (not this coroutine)?
function SCHEM.otherReader()
  return TT and TT.yieldCo and coroutine.status(TT.yieldCo) ~= "dead" and coroutine.running() ~= TT.yieldCo
end
function SCHEM.load(name)
  local s0 = SCHEM.get(name)
  if s0 then return s0 end
  if SCHEM.otherReader() then
    SCHEM.request(name)
    local untilT = os.clock() + 120
    while not SCHEM.get(name) and not SCHEM.failed[name] and os.clock() < untilT do
      local tm = os.startTimer(1)
      repeat local ev, a = os.pullEvent() until (ev == "timer" and a == tm) or (ev == "schem_loaded" and a == name)
    end
    local s1 = SCHEM.get(name)
    if s1 then return s1 end
    local why = SCHEM.failed[name] or "reading it took too long"
    SCHEM.failed[name] = nil
    return nil, why
  end
  return SCHEM.read(name)
end
function SCHEM.read(name)
  local path = SCHEM.list()[name]
  if not path then return nil, "no schematic '" .. tostring(name) .. "'" end
  local data
  if isRemote(path) then
    local text = STORE and STORE.read and STORE.read(path)
    if not text then return nil, "the storage helper with " .. name .. " did not answer (" .. path .. ") - try again" end
    data = SCHEM.dec(text, TT and TT.workYield)
  else
    local h = fs.open(path, "rb")
    if not h then return nil, "cannot open " .. path end
    data = h.readAll()
    h.close()
  end
  local ok, s = pcall(SCHEM.parse, data or "", TT and TT.workYield)
  if not ok then return nil, tostring(s) end
  SCHEM.remember(name, s, path)
  return s
end
-- the screen / the comms worker must not wait: they ask (SCHEM.wanted) and look again later
SCHEM.wanted, SCHEM.failed = {}, {}
function SCHEM.request(name)
  if SCHEM.get(name) then return true end
  if not SCHEM.otherReader() then return SCHEM.read(name) ~= nil end       -- (no map worker: read it here)
  if not SCHEM.wanted[name] then
    SCHEM.wanted[name] = true
    os.queueEvent("schem_in")
  end
  return false
end
function SCHEM.delete(name)
  local paths = allPaths(name)
  if #paths == 0 then return false end
  for _, p in ipairs(paths) do delAny(p) end
  if SCHEM.remote()[name] then SCHEM.remote()[name] = nil saveWhere() end
  SCHEM.cache[name] = nil
  return true
end

-- a file dropped onto the computer's screen (event "file_transfer"): only
-- taken here (quick); the map worker reads + stores it (SCHEM.processPending),
-- with pauses - a big schematic does not freeze the screen
SCHEM.pending = {}
function SCHEM.onTransfer(transfer)
  local files = {}
  if type(transfer) == "table" and type(transfer.getFiles) == "function" then files = transfer.getFiles() or {} end
  for _, f in ipairs(files) do
    local name = (type(f.getName) == "function" and f.getName()) or "schematic"
    local data = f.readAll() or ""
    pcall(f.close)
    name = fs.getName(name)
    if name:lower():match("%.nbt$") then
      SCHEM.pending[#SCHEM.pending + 1] = { name = name, data = data }
      setToast("Reading schematic " .. name .. " ...", C.label, 4)
    else
      local ok, msg = SCHEM.saveDropped(name, data)
      pushNote(ok and "DONE" or "WARNING", msg, ok and C.good or C.warn)
    end
  end
  if #SCHEM.pending > 0 then os.queueEvent("schem_in") end
end
-- ANY OTHER FILE dropped while the base runs is saved next to inventory.lua, like the shell does when the base is stopped
-- (the owner had to stop the base to copy a file). Through a temp file (a full disk never leaves half a program); the
-- note says what happens with it next.
function SCHEM.saveDropped(name, data)
  name = fs.getName(tostring(name or ""))
  data = tostring(data or "")
  if name == "" or name:find("^%.") then return false, "A dropped file without a name was not saved." end
  for _, v in ipairs(VOICE_FILES or {}) do
    if v == name then return false, name .. " is part of the voice add-on (it lives on a floppy / storage helper) - type  voice update  to get the newest." end
  end
  local path = fs.combine(BASE_DIR or "", name)
  if fs.isDir(path) then return false, name .. ": a folder of that name is in the way." end
  local okF, free = pcall(fs.getFreeSpace, fs.getDir(path) == "" and "/" or fs.getDir(path))
  local old = fs.exists(path) and fs.getSize(path) or 0
  if not okF or (free or 0) + old < #data + 16 * 1024 then
    return false, name .. " (" .. math.ceil(#data / 1024) .. " KB) not saved: the computer has only " .. math.floor(((free or 0) + old) / 1024) ..
           " KB free for it. Type  disks  to see what takes the room."
  end
  local tmp = path .. ".drop"
  local h = fs.open(tmp, "wb")
  if not h then return false, name .. " not saved: cannot write " .. tmp end
  local okW = pcall(h.write, data)
  pcall(h.close)
  if not okW or not fs.exists(tmp) or fs.getSize(tmp) < #data then pcall(fs.delete, tmp) return false, name .. " not saved (disk full?)" end
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
  local what
  if name:match("^base_.*%.lua$") or name == "inventory.lua" or name == "startup.lua" or name == "upgrade.lua" then
    what = "Restart the base to use it (SYSTEM > RESTART BASE)." ..
           (name:match("^base_") and " It is used instead of its packed copy (.luz) until the next upgrade." or "")
  elseif name == "node.lua" then what = "The turtles get it by themselves (it is moved to storage within a minute)."
  elseif name == "miner.lua" then what = "Type  mine update  to send it to the mining turtles."
  elseif name == "store.lua" then what = "The storage helpers get it by themselves within a few minutes."
  else what = "It is next to inventory.lua." end
  if sysLog then pcall(sysLog, "File dropped on the screen and saved: " .. path .. " (" .. #data .. " bytes)") end
  return true, (old > 0 and "Replaced " or "Saved ") .. name .. " (" .. math.ceil(#data / 1024) .. " KB). " .. what
end
function SCHEM.processPending()
  local names = {}
  for name in pairs(SCHEM.wanted) do names[#names + 1] = name end      -- (another worker may ask while this reads)
  for _, name in ipairs(names) do
    SCHEM.wanted[name] = nil
    local s, why = SCHEM.read(name)
    if not s then SCHEM.failed[name] = tostring(why) end
    if DW and DW.sel and DW.sel.name == name and DW.sel.reading then pcall(DW.select, name) end
    os.queueEvent("schem_loaded", name)
  end
  while #SCHEM.pending > 0 do
    local f = table.remove(SCHEM.pending, 1)
    local name, data = f.name, f.data
    do
      local ok, where, s = SCHEM.store(name, data, TT and TT.workYield)
      if ok then
        local _, place = SCHEM.materials(s)
        pushNote("DONE", "Schematic '" .. SCHEM.cleanName(name) .. "' stored: " .. s.size.x .. " x " .. s.size.y .. " x " ..
                 s.size.z .. ", " .. place .. " blocks - type  schem  on the computer", C.good)
        if sysLog then sysLog("Schematic stored: " .. where, "INFO") end
      else
        pushNote("WARNING", "Schematic " .. name .. " not stored: " .. tostring(where), C.warn)
      end
    end
  end
  os.queueEvent("inv_update")
end
