-- SCHEMATIC REVIEW (the owner: "go over the schematic code"): what the first version got wrong -
--  * a LONG tag (8 bytes) in the file = a Lua error: POW only goes to 2^31 (Create's machines keep their network id as a
--    long - every schematic with a Create machine in it could not be read)
--  * a cut-off file gave Lua errors ("attempt to perform arithmetic on a nil value") instead of saying so
--  * a block with an odd palette number stopped the materials list
--  * blocks whose name is not an item (carrots, potatoes, cave vines, a filled cauldron ...): the build waited for
--    "carrots" in AE2 for ever; fluids (water, modded ones) were listed as "short: water bucket"
--  * a newer file of the same name stored on another disk: after a restart the OLD one came back; delete left copies
--  * a tap on a schematic after a restart unpacked it ON THE SCREEN (seconds in the game, "too long without yielding")
CODE_SIZE = 800000
local function readFile(path)
  local h = fs.open(path, "rb")
  local d = h.readAll()
  h.close()
  return d
end
local F = "tools/tests/fixtures/"

-- a small NBT writer (big-endian) for test files
local function be(v, nb)
  local neg = v < 0
  if neg then v = -v - 1 end                    -- (two's complement byte by byte: exact)
  local t = {}
  for i = nb, 1, -1 do
    local b = math.floor(v % 256)
    t[i] = string.char(neg and (255 - b) or b)
    v = math.floor(v / 256)
  end
  return table.concat(t)
end
local function nstr(s) return be(#s, 2) .. s end
local W = {}
function W.compound(fields)            -- fields = { {tag, name, payload}, ... }
  local o = {}
  for _, f in ipairs(fields) do o[#o + 1] = string.char(f[1]) .. nstr(f[2]) .. f[3] end
  return table.concat(o) .. "\0"
end
function W.list(et, items) return string.char(et) .. be(#items, 4) .. table.concat(items) end
function W.int(v) return be(v, 4) end
function W.long(v) return be(v, 8) end
local function block(x, y, z, st, nbt)
  local f = { { 9, "pos", W.list(3, { W.int(x), W.int(y), W.int(z) }) }, { 3, "state", W.int(st) } }
  if nbt then f[#f + 1] = { 10, "nbt", nbt } end
  return W.compound(f)
end
local function pal(name, props)
  local f = { { 8, "Name", nstr(name) } }
  if props then
    local p = {}
    for k, v in pairs(props) do p[#p + 1] = { 8, k, nstr(v) } end
    f[#f + 1] = { 10, "Properties", W.compound(p) }
  end
  return W.compound(f)
end
local function structure(size, palette, blocks)
  return string.char(10) .. nstr("") .. W.compound({
    { 9, "size", W.list(3, { W.int(size[1]), W.int(size[2]), W.int(size[3]) }) },
    { 9, "palette", W.list(10, palette) },
    { 9, "blocks", W.list(10, blocks) },
    { 3, "DataVersion", W.int(3955) } })
end

-- 1) LONG tags, long arrays, a big byte array (a Create machine's block entity)
local bytes = string.rep("\7", 10000)
local machine = W.compound({ { 4, "Network", W.long(-123456789) }, { 4, "Big", W.long(2 ^ 40 + 5) },
                             { 12, "Seeds", be(2, 4) .. W.long(7) .. W.long(-1) },
                             { 7, "Data", be(#bytes, 4) .. bytes }, { 5, "Speed", be(0x40800000, 4) } })
local data = structure({ 2, 1, 1 }, { pal("create:shaft", { axis = "x" }), pal("minecraft:stone") },
                       { block(0, 0, 0, 0, machine), block(1, 0, 0, 1) })
local ok, s = pcall(SCHEM.parse, data)
CHECK(ok and s and #s.blocks == 2, "a schematic with LONG tags (a Create machine) reads (" .. tostring(ok and #s.blocks or s) .. ")")
local root = SCHEM.nbt(data)
local nb = root.blocks[1].nbt
CHECK(nb.Network == -123456789 and nb.Big == 2 ^ 40 + 5 and nb.Seeds[1] == 7 and nb.Seeds[2] == -1, "long values are right (" ..
      tostring(nb.Network) .. ", " .. tostring(nb.Seeds and nb.Seeds[2]) .. ")")
CHECK(#nb.Data == 10000 and nb.Data[10000] == 7 and nb.Speed == 4, "a 10000-byte array + a float")

-- 2) cut-off / broken files say so (no Lua errors)
local function says(d, what)
  local okC, err = pcall(SCHEM.parse, d)
  CHECK(not okC and tostring(err):find("schematic", 1, true) and not tostring(err):find("attempt to", 1, true),
        what .. ": " .. tostring(err))
end
says(data:sub(1, 60), "plain NBT cut off")
says(data:sub(1, 300), "plain NBT cut off later")
local stored = readFile(F .. "house_stored.nbt")
says(stored:sub(1, math.floor(#stored / 2)), "a stored (not packed) gzip cut off")
says(readFile(F .. "house.nbt"):sub(1, 200), "a packed gzip cut off")
says(structure({ 0, 1, 1 }, { pal("minecraft:stone") }, {}), "size 0")

-- 3) odd palette numbers / spots outside the size are left out
local odd = SCHEM.parse(structure({ 2, 2, 2 }, { pal("minecraft:stone") },
                        { block(0, 0, 0, 0), block(1, 0, 0, 5), block(5, 0, 0, 0), block(1, 1, 1, 0) }))
CHECK(#odd.blocks == 2, "a block with no palette entry / outside the size is left out (" .. #odd.blocks .. " of 4)")
local okM, need = pcall(SCHEM.materials, odd)
CHECK(okM and need["minecraft:stone"] == 2, "materials of it work")

-- 4) blocks that are not items + fluids
local farm = SCHEM.parse(structure({ 9, 2, 1 }, {
  pal("minecraft:carrots", { age = "7" }), pal("minecraft:tall_seagrass", { half = "lower" }),
  pal("minecraft:tall_seagrass", { half = "upper" }), pal("minecraft:water", { level = "0" }),
  pal("create:honey", { level = "0" }), pal("minecraft:water_cauldron", { level = "3" }),
  pal("minecraft:composter", { level = "2" }), pal("minecraft:cave_vines", { age = "3", berries = "true" }),
  pal("minecraft:small_dripleaf", { half = "upper", facing = "north", waterlogged = "false" }),
  pal("minecraft:oak_stairs", { half = "top", facing = "north", shape = "straight", waterlogged = "false" }) },
  { block(0, 0, 0, 0), block(1, 0, 0, 1), block(1, 1, 0, 2), block(2, 0, 0, 3), block(3, 0, 0, 4), block(4, 0, 0, 5),
    block(5, 0, 0, 6), block(6, 0, 0, 7), block(7, 1, 0, 8), block(8, 0, 0, 9) }))
local fneed, fplace, fair, fluids = SCHEM.materials(farm)
CHECK(fneed["minecraft:carrot"] == 1 and not fneed["minecraft:carrots"], "carrots (the crop) = a carrot (the item)")
CHECK(fneed["minecraft:seagrass"] == 1, "tall seagrass = one seagrass (the upper half needs none)")
CHECK(fneed["minecraft:cauldron"] == 1 and fneed["minecraft:composter"] == 1 and fneed["minecraft:glow_berries"] == 1,
      "a filled cauldron = a cauldron, a composter stays, cave vines = glow berries")
CHECK(fneed["minecraft:oak_stairs"] == 1, "upside-down stairs (half = top) are still placed")
CHECK(not fneed["minecraft:water_bucket"] and not fneed["create:honey_bucket"] and fluids == 2,
      "fluids are not on the list (" .. tostring(fluids) .. " left out)")
CHECK(fplace == 6, "6 blocks to place (" .. fplace .. ")")
local fplan = DW.plan(farm, 0, 0, 0, 0)
local items = {}
for _, p in ipairs(fplan.place) do items[p.item] = (items[p.item] or 0) + 1 end
CHECK(#fplan.place == 6 and items["minecraft:carrot"] == 1 and not items["create:honey"] and fplan.skipped["create:honey_bucket"] == 1,
      "the build places the same 6 (modded honey left out)")
DW.select = DW.select    -- (keep)
SCHEM.cache["farm"] = { s = farm, path = "schematics/farm.nbt" }
DW.select("farm")
CHECK(DW.sel and DW.sel.fluids == 2 and DW.sel.place == 6, "the BUILD card knows the fluids left out")

-- 5) the same name stored again elsewhere: the NEW one stays (the old one went first in the list)
fs.makeDir("disk9")
fs.makeDir("disk9/schematics")
local h = fs.open("disk9/schematics/dup.nbt", "wb") h.write(readFile(F .. "house.nbt")) h.close()
local md0 = mountedDisks
local floppyFree = 1000                                   -- (the floppy has no room for the new one)
mountedDisks = function() return { { mount = "disk9", data = true, free = floppyFree } } end
local newer = structure({ 1, 1, 1 }, { pal("minecraft:gold_block") }, { block(0, 0, 0, 0) })
local okS, where = SCHEM.store("dup", newer)
CHECK(okS and not tostring(where):find("disk9", 1, true), "stored on the computer (the floppy is full): " .. tostring(where))
SCHEM.cache = {}
local back = SCHEM.load("dup")
CHECK(back and #back.blocks == 1 and back.palette[1].name == "minecraft:gold_block", "after a restart the NEW one is read (" ..
      tostring(back and back.palette[1].name) .. ")")
CHECK(not fs.exists("disk9/schematics/dup.nbt"), "the old copy on the floppy is gone")
h = fs.open("disk9/schematics/dup.nbt", "wb") h.write(readFile(F .. "house.nbt")) h.close()
CHECK(SCHEM.delete("dup") and SCHEM.list()["dup"] == nil, "delete removes every copy")
mountedDisks = md0

-- 6) a tap after a restart: the MAP WORKER reads it, the screen does not wait
local h2 = fs.open("schematics/castle.nbt", "wb") h2.write(readFile(F .. "big.nbt")) h2.close()
local _, CASTLE = SCHEM.materials(SCHEM.parse(readFile(F .. "big.nbt")))
SCHEM.cache = {}
local co0 = TT.yieldCo
TT.yieldCo = coroutine.create(function() end)             -- (a map worker that is not this coroutine)
local parse0, parsed = SCHEM.parse, 0
SCHEM.parse = function(...) parsed = parsed + 1 return parse0(...) end
DW.select("castle")
CHECK(parsed == 0 and DW.sel.reading and DW.sel.err:find("Reading", 1, true), "the tap does not unpack it (" .. tostring(DW.sel.err) .. ")")
state.page = "work"
DW.view = DW.view or {}
DW.view.schems = { "castle" }
local okD = pcall(draw)
CHECK(okD, "the page draws while it is read")
SCHEM.processPending()                                    -- (the map worker)
CHECK(parsed == 1 and DW.sel.size and DW.sel.place == CASTLE and not DW.sel.reading, "read by the map worker, the card filled in (" ..
      tostring(DW.sel.place) .. ")")
-- a build of it after a restart: the comms tick does not unpack it either - it says so, no pause
DW.notReady = DW.notReady or function() end
DW.job = { name = "castle", x = 0, y = 64, z = 0, rot = 0, clear = false, done = string.rep("0", CASTLE), dug = "", placed = 0,
           skippedN = 0, fails = 0 }
SCHEM.cache = {}
parsed = 0
local p1, why1, reading = DW.planOf(DW.job)
CHECK(p1 == nil and reading and parsed == 0, "the build's plan is asked for, not read in the comms worker (" .. tostring(why1) .. ")")
SCHEM.processPending()
local p2 = DW.planOf(DW.job)
CHECK(p2 and #p2.place == CASTLE and not DW.job.paused, "then the build goes on")
DW.job = nil
SCHEM.parse = parse0
TT.yieldCo = co0
state.page = "home"

-- 7) only a few parsed schematics are kept in memory (+ the one being built)
SCHEM.cache = {}
DW.job = { name = "keepme" }
for i, n in ipairs({ "keepme", "a", "b", "c", "d", "e", "f" }) do SCHEM.remember(n, { blocks = {} }, n) CLOCK = CLOCK + 1 end
local cnt = 0
for _ in pairs(SCHEM.cache) do cnt = cnt + 1 end
CHECK(cnt <= SCHEM.KEEP and SCHEM.cache.keepme and SCHEM.cache.f, "at most " .. SCHEM.KEEP .. " in memory, the build's kept (" .. cnt .. ")")
DW.job = nil
SCHEM.cache = {}
pcall(fs.delete, "schematics/castle.nbt")
