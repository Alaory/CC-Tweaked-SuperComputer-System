-- Schematics: gzip (stored / fixed / dynamic blocks) + NBT + Create's structure
-- format, the materials list, storing a dropped file, the schem console command.
-- (where it is stored is not this test: a fixed program size, not the real one - that
-- grows with every feature and left the stand-in computer under its 96 KB margin)
CODE_SIZE = 800000
local function readFile(path)
  local h = fs.open(path, "rb")
  local d = h.readAll()
  h.close()
  return d
end
local F = "tools/tests/fixtures/"
local raw = readFile(F .. "house.raw")

-- 1. the three kinds of compressed data unpack to exactly the original
for _, f in ipairs({ "house.nbt", "house_stored.nbt", "house_fixed.nbt" }) do
  local ok, out = pcall(SCHEM.unpack, readFile(F .. f))
  CHECK(ok and out == raw, f .. ": unpacks to the original bytes" .. (ok and "" or (" - " .. tostring(out))))
end

-- 2. the house
local s = SCHEM.parse(readFile(F .. "house.nbt"))
CHECK(s.size.x == 5 and s.size.y == 4 and s.size.z == 5, "size 5 x 4 x 5")
CHECK(#s.blocks == 99, "99 blocks in the file (one spot left out = structure void): " .. #s.blocks)
CHECK(#s.palette == 9, "9 palette entries")
local door
for _, e in ipairs(s.palette) do if e.name == "minecraft:oak_door" and e.props.half == "lower" then door = e end end
CHECK(door and door.props.facing == "south" and door.props.hinge == "left", "block properties are read (door facing south)")
local roofVoid = true
for _, b in ipairs(s.blocks) do if b[1] == 4 and b[2] == 3 and b[3] == 4 then roofVoid = false end end
CHECK(roofVoid, "the left-out spot is not in the list (left as it is when building)")
local need, place, air = SCHEM.materials(s)
CHECK(need["minecraft:stone_bricks"] == 29, "29 stone bricks (" .. tostring(need["minecraft:stone_bricks"]) .. ")")
CHECK(need["minecraft:oak_planks"] == 25, "25 planks")
CHECK(need["minecraft:oak_door"] == 1, "1 door (the upper half needs no item)")
CHECK(need["minecraft:torch"] == 1 and not need["minecraft:wall_torch"], "a wall torch needs a torch")
CHECK(need["minecraft:oak_slab"] == 25, "25 slabs (a double slab = 2): " .. tostring(need["minecraft:oak_slab"]))
CHECK(need["minecraft:glass"] == 1, "1 glass")
CHECK(place == 81 and air == 17, "81 blocks to place, 17 air to clear (" .. place .. ", " .. air .. ")")

-- 3. a bigger one: 560 KB of NBT, many kinds
local big = SCHEM.parse(readFile(F .. "big.nbt"))
-- (big.json: {"blocks": n, "counts": {"name": n, ...}, ...} - read with a pattern, no JSON reader needed)
local want = { counts = {} }
local js = readFile(F .. "big.json")
for k, v in js:match('"counts": (%b{})'):gmatch('"([^"]+)": (%d+)') do want.counts[k] = tonumber(v) end
local counts = {}
for _, b in ipairs(big.blocks) do local n = big.palette[b[4]].name counts[n] = (counts[n] or 0) + 1 end
CHECK(#big.blocks == 15562, "big: all 15562 blocks read (" .. #big.blocks .. ")")
local same, kinds = true, 0
for k, v in pairs(want.counts) do kinds = kinds + 1 if counts[k] ~= v then same = false end end
CHECK(kinds == 10 and same, "big: the count of every one of the 10 kinds matches")

-- 4. a file dropped on the screen is stored and listed; a wrong file is refused
local data = readFile(F .. "house.nbt")
local function transfer(name, bytes)
  return { getFiles = function() return { { getName = function() return name end, readAll = function() return bytes end,
                                             close = function() end } } end }
end
local notes = {}
local push0 = pushNote
pushNote = function(kind, msg) if kind then notes[#notes + 1] = kind .. ": " .. tostring(msg) end end   -- (toasts: no kind)
SCHEM.onTransfer(transfer("My House.nbt", data))
SCHEM.onTransfer(transfer("broken.nbt", "\31\139\8\0garbage"))
SCHEM.onTransfer(transfer("notes.txt", "hello"))
CHECK(#SCHEM.pending == 2 and #notes == 1, "the drop only takes the files (read later in the map worker)")
SCHEM.processPending()
pushNote = push0
CHECK(#SCHEM.pending == 0, "all read")
notes = { notes[2], notes[3], notes[1] }        -- (order: stored, broken, not .nbt)
CHECK(notes[1] and notes[1]:find("^DONE") and notes[1]:find("5 x 4 x 5"), "dropped schematic stored: " .. tostring(notes[1]))
CHECK(notes[2] and notes[2]:find("^WARNING"), "a broken file is refused: " .. tostring(notes[2]))
CHECK(notes[3] and notes[3]:find("Saved notes.txt", 1, true), "any other file is SAVED next to inventory.lua (no need to stop the base): " .. tostring(notes[3]))
local np = fs.combine(BASE_DIR or "", "notes.txt")
local hN = fs.open(np, "rb")
CHECK(hN and hN.readAll() == "hello", "with what was dropped")
if hN then hN.close() end
pcall(fs.delete, np)
-- a base file: replaced, "restart" said; a voice file: sent to voice update; no room: refused, the old file kept
local bp = fs.combine(BASE_DIR or "", "base_dropped_test.lua")
local w0 = fs.open(bp, "w") w0.write("old") w0.close()
local okB, msgB = SCHEM.saveDropped("base_dropped_test.lua", "-- new")
local hB = fs.open(bp, "r") local gotB = hB.readAll() hB.close()
CHECK(okB and gotB == "-- new" and msgB:find("Restart the base", 1, true), "a base file is replaced + restart said: " .. tostring(msgB))
local okV, msgV = SCHEM.saveDropped("voice_talk.lua", "x")
CHECK(not okV and msgV:find("voice update", 1, true), "a voice file -> voice update: " .. tostring(msgV))
local gfs0 = fs.getFreeSpace
fs.getFreeSpace = function() return 1000 end
local okR, msgR = SCHEM.saveDropped("base_dropped_test.lua", string.rep("x", 50000))
fs.getFreeSpace = gfs0
local hB2 = fs.open(bp, "r") local gotB2 = hB2.readAll() hB2.close()
CHECK(not okR and msgR:find("not saved", 1, true) and gotB2 == "-- new", "no room: refused, the old file kept: " .. tostring(msgR))
pcall(fs.delete, bp)
-- the drop worker takes a drop even while the screen loop is busy (its own worker, waiting only for file_transfer)
CHECK(type(dropWorker) == "function", "a drop worker exists")
local invSrc = io.open(SRC_DIR .. "/inventory.lua"):read("a")
CHECK(invSrc:find("dropWorker", 1, true), "inventory.lua starts the drop worker")
local wSrc = io.open(SRC_DIR .. "/base_workers.lua"):read("a")
CHECK(not wSrc:find('ev == "file_transfer"', 1, true), "the screen loop no longer handles drops (they would be taken twice)")
CHECK(SCHEM.list()["My_House"], "listed under a clean name (My_House)")
SCHEM.cache = {}
local again = SCHEM.load("My_House")
CHECK(again and #again.blocks == 99, "read back from where it was stored")

-- 5. the console
local out = handleCommand("schem") or {}
CHECK(table.concat(out, "\n"):find("My_House", 1, true), "schem lists it")
out = handleCommand("schem My_House") or {}
local text = table.concat(out, "\n")
CHECK(text:find("81 blocks to place", 1, true) and text:find("stone_bricks", 1, true), "schem <name> shows size + materials")
out = handleCommand("schem delete My_House") or {}
CHECK(SCHEM.list()["My_House"] == nil, "schem delete removes it")
