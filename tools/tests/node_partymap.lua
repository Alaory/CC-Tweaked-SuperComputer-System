-- SEARCH PARTY scans also go onto the MAP - only with open sky above the turtle
-- (underground every column would "end" at the scan's top: a false surface).
--   lua5.3 tools/tests/node_partymap.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local a = src:find("-- nothing above me in this scan", 1, true)
local b = src:find("function rescue(", a or 1, true)
CHECK(a and b, "findTurtles + openSkyIn found")
if not (a and b) then print("FAILED") os.exit(1) end
local SENT, SUMMARY = {}, 0
function send(t, m) SENT[#SENT + 1] = { t = t, m = m } end
function sendSummary() SUMMARY = SUMMARY + 1 return 0 end
function findItem() return 1 end
CONFIG = { geoItem = "geo" }
S = { pos = { x = 100, y = 70, z = 100 } }
local DATA
function scanRaw(r) return DATA, r end
load(src:sub(a, b - 1))()
-- in the open: ground below and around, nothing above
DATA = { { x = 0, y = -1, z = 0, name = "minecraft:grass_block" }, { x = 3, y = -2, z = 1, name = "minecraft:dirt" },
         { x = 5, y = 0, z = 5, name = "computercraft:turtle_normal" } }
local ok, msg = findTurtles()
CHECK(ok and SUMMARY == 1, "open sky: the scan goes onto the map (" .. tostring(msg) .. ")")
CHECK(tostring(msg):find("map updated", 1, true), "it says so")
CHECK(SENT[1] and SENT[1].t == "turtlesseen" and #SENT[1].m.seen == 1, "the turtle it saw is still reported")
-- underground: a block above it
DATA[#DATA + 1] = { x = 0, y = 5, z = 0, name = "minecraft:stone" }
findTurtles()
CHECK(SUMMARY == 1, "underground: NOT put on the map")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
