-- NO DIGGING AT THE BASE: inside CONFIG.noDigBase blocks (x and z) of the base
-- (CONFIG.baseAt, sent by the base) NOTHING is dug - not with the dig setting on,
-- not on a rescue (DIG_JOB). Around its own home: a SQUARE now (the x+z diamond
-- left the corners of the base open).   lua5.3 tools/tests/node_nodig.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local a = src:find("-- the base's no-dig zone", 1, true)
local b = src:find("function isOre(b)", a or 1, true)
if not (a and b) then print("FAIL: no base no-dig zone in node.lua") print("FAILED") os.exit(1) end
local DUG = 0
turtle = { inspect = function() return true, { name = "minecraft:stone" } end, dig = function() DUG = DUG + 1 return true end }
function natural() return true end
function withEquipped(_, f) return f() end
CONFIG = { dig = true, digNearHome = 24, baseAt = "-5271,64,10845", noDigBase = 96 }
S = { pos = { x = -5271 + 80, y = 64, z = 10845 - 50 }, home = { x = -5271, y = 64, z = 10845 } }
DIG_JOB, HOMEPROBE = true, nil
load(src:sub(a, b - 1))()
CHECK(tryDig("f") == false and DUG == 0, "80 blocks from the base, rescue trip: NOT dug")
S.pos = { x = -5271 + 100, y = 64, z = 10845 }
CHECK(tryDig("f") == true and DUG == 1, "outside the zone: dug as before")
-- the corner of the home square (the old x+z rule allowed this one)
CONFIG.baseAt = ""
S.pos = { x = -5271 + 20, y = 64, z = 10845 + 20 }
CHECK(tryDig("f") == false, "20/20 from home (x+z = 40): NOT dug any more")
S.pos = nil
CHECK(tryDig("f") == false, "position unknown: never dug")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
