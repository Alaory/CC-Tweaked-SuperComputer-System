-- FUEL FOR THE WAY HOME, turtle side (node.lua homeFuel / surveyPoints / idleEmptyFuel): far out a survey
-- stops while the fuel still covers the way home; a turtle that cannot get home burns what it carries
-- (fuel a drone brought) up to the way home.
--   lua5.3 tools/tests/node_fuelhome.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  assert(a, "not found: " .. from)
  local b = src:find(to, a, true)
  assert(b, "not found: " .. to)
  return src:sub(a, b - 1)
end
local code = piece("function homeFuel()", "function noFuel()") ..
             piece("surveyPoints = function(points, r)", "-- search & rescue") ..
             piece("EMPTY_TRY = nil", "function listener()")
local fn, err = load(code, "=node pieces")
CHECK(fn, "pieces load: " .. tostring(err))
local FUEL = 4000
turtle = { getFuelLevel = function() return FUEL end, detectDown = function() return true end }
S = { home = { x = 0, y = 64, z = 0 }, pos = { x = 2400, y = 70, z = 0, f = 3 }, job = nil }
CONFIG = { skyMinDist = 48, skyY = 150, maxSurveyPoints = 400, minFuel = 200 }
stopFlag, job, SLOT_LOCK = false, nil, false
local scans = 0
function known() return true end
function requestKnowledge() end
function send() end function save() end function note() end function settle() end function down() return false end
function withLadder(_, f) return f() end
local function walk(x, z)
  FUEL = FUEL - (math.abs(x - S.pos.x) + math.abs(z - S.pos.z))
  S.pos.x, S.pos.z = x, z
  return true
end
function travelOnce(x, _, z) return walk(x, z) end
function moveToXZ(x, z) return walk(x, z) end
function warpRemember() end
function scanHere() scans = scans + 1 FUEL = FUEL - 2 return true end
local TOPS = {}
function topUp(target) TOPS[#TOPS + 1] = target end
function refuelTarget() return 100000 end
function doRefuel() end
if fn then fn() end

-- the way home from 2,400 blocks out
local need = homeFuel()
CHECK(need > 2400 + 80 + 86 and need < 3600, "homeFuel from 2,400 out: " .. need)
S.pos.x = 30
CHECK(homeFuel() == 30 + 6, "near home: just the blocks (" .. homeFuel() .. ")")
S.pos.x = 2400

-- a batch of 40 spots going AWAY from home: it stops while it can still get home
local pts = {}
for i = 1, 40 do pts[i] = { 2400 + 17 * i, 0 } end
local ok, msg = surveyPoints(pts, 8)
CHECK(not ok and tostring(msg):find("way home", 1, true), "it stops: " .. tostring(msg))
CHECK(scans > 3 and scans < 40, "after some spots (" .. scans .. ")")
CHECK(FUEL >= homeFuel(), "fuel left " .. FUEL .. " still covers the way home (" .. homeFuel() .. ")")

-- with endless fuel (S.reuse) it tops up first instead of stopping
FUEL, scans = 3300, 0
S.pos.x = 2400
S.reuse = { ["mod:endless"] = true }
local topped = false
topUp = function(target) topped = true FUEL = target end
ok = surveyPoints({ { 2417, 0 }, { 2434, 0 } }, 8)
CHECK(topped and ok and scans == 2, "endless fuel: topped up and went on")
S.reuse = nil

-- cannot get home (1500 fuel, 2,400 out), idle: it burns what it carries up to the way home + 500
FUEL = 1500
S.pos.x = 2400
TOPS = {}
topUp = function(target) TOPS[#TOPS + 1] = target FUEL = target end
os.clock = os.clock or function() return 0 end
EMPTY_TRY = nil
local r = idleEmptyFuel()
CHECK(#TOPS == 1 and TOPS[1] >= homeFuel() and r == true, "short of the way home: burns what it carries (" .. tostring(TOPS[1]) .. ")")
-- enough fuel: nothing burned
FUEL, TOPS, EMPTY_TRY = 9000, {}, nil
idleEmptyFuel()
CHECK(#TOPS == 0, "enough fuel: nothing burned")
if FAILS > 0 then os.exit(1) end
print("node fuel home: all checks passed")
