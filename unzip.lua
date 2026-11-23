-- unzip.lua  -  unpacks the base program's PACKED files (base_*.luz).
--
-- The base program is ~900 KB of a 1 MB computer: with it unpacked there was no room
-- left for anything else ("DISK ALMOST FULL" at 13 KB free). `upgrade` keeps every
-- base_*.lua PACKED as base_*.luz (raw deflate, RFC 1951 - about a third of the size);
-- inventory.lua unpacks each one into memory when the base starts (a few seconds),
-- nothing unpacked is written to the disk. A plain base_*.lua next to it (dragged in by
-- hand) is used instead of its .luz.
--
--   local inflate = dofile("unzip.lua")
--   local text = inflate(bytes [, yield])    -- yield(): called now and then (long files)
--
-- No bit operators (the game's Lua has none): plain arithmetic. The same decoder as the
-- schematic reader (base_schem.lua SCHEM.inflate).

local byte, char = string.byte, string.char
local POW = {}
for i = 0, 31 do POW[i] = 2 ^ i end

local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

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

local function bad() error("unzip: the packed file is broken (type  upgrade  again)", 0) end

return function(data, yield)
  local bitbuf, bitcnt, pos = 0, 0, 1
  local out, n = {}, 0
  local function bits(k)
    while bitcnt < k do
      local b = byte(data, pos)
      if not b then bad() end
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
    bad()
  end
  local fixedL, fixedD
  local syms = 0
  repeat
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      bitbuf, bitcnt = 0, 0
      local lo, hi, nlo, nhi = byte(data, pos, pos + 3)
      if not nhi then bad() end
      local len = lo + hi * 256
      if len + nlo + nhi * 256 ~= 65535 then bad() end
      pos = pos + 4
      if pos + len - 1 > #data then bad() end
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
              if i == 0 then bad() end
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
        if yield and syms % 32768 == 0 then yield() end
        if not sym or sym > 285 then bad() end
        if sym < 256 then
          n = n + 1
          out[n] = sym
        elseif sym == 256 then
          break
        else
          sym = sym - 257
          local len = LBASE[sym + 1] + bits(LEXT[sym + 1])
          local ds = decode(dh)
          if not ds or ds > 29 then bad() end
          local dist = DBASE[ds + 1] + bits(DEXT[ds + 1])
          local from = n - dist
          if from < 0 then bad() end
          for k = 1, len do out[n + k] = out[from + k] end
          n = n + len
        end
      end
    else
      bad()
    end
  until last == 1
  local parts = {}
  local unpack = table.unpack or unpack
  for i = 1, n, 4096 do parts[#parts + 1] = char(unpack(out, i, math.min(n, i + 4095))) end
  return table.concat(parts)
end
