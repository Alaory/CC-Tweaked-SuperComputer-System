-- node.lua's real DRIVE steps (driveStep / driveDig / driveMove / driveLook) in a
-- small fake world.   lua5.3 tools/tests/node_drive.lua node.lua   (exit 1 on a failed check)
local NODE = arg[1] or "node.lua"
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(NODE):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a + 1, true)
  assert(a and b, "not found: " .. from)
  return src:sub(a, b - 1)
end
local code = piece("function natural(name)", "tryDig = function") ..
             piece("-- ===== DRIVE: the owner steers", "-- ===== fuel chest at home")
DX, DZ = { [0] = 0, 1, 0, -1 }, { [0] = -1, 0, 1, 0 }
local Wd = {}
local function k(x, y, z) return x .. "," .. y .. "," .. z end
local function setW(x, y, z, n) Wd[k(x, y, z)] = n end
local P = { x = 0, y = 0, z = 0, f = 1 }        -- facing east
local function cell(d)
  if d == "u" then return P.x, P.y + 1, P.z end
  if d == "d" then return P.x, P.y - 1, P.z end
  if d == "b" then return P.x - DX[P.f], P.y, P.z - DZ[P.f] end
  return P.x + DX[P.f], P.y, P.z + DZ[P.f]
end
local function mover(d) return function()
  local x, y, z = cell(d)
  if Wd[k(x, y, z)] then return false end
  P.x, P.y, P.z = x, y, z
  return true
end end
local function insp(d) return function()
  local n = Wd[k(cell(d))]
  if n then return true, { name = n } end
  return false, "No block to inspect"
end end
local dug = {}
FALLS = {}
local function digger(d) return function()
  local x, y, z = cell(d)
  local n = Wd[k(x, y, z)]
  if not n then return false end
  dug[#dug + 1] = n
  Wd[k(x, y, z)] = nil
  if FALLS[k(x, y, z)] and FALLS[k(x, y, z)] > 0 then           -- gravel above falls in
    FALLS[k(x, y, z)] = FALLS[k(x, y, z)] - 1
    Wd[k(x, y, z)] = "minecraft:gravel"
  end
  return true
end end
turtle = { forward = mover("f"), back = mover("b"), up = mover("u"), down = mover("d"),
           inspect = insp("f"), inspectUp = insp("u"), inspectDown = insp("d"),
           dig = digger("f"), digUp = digger("u"), digDown = digger("d"),
           attack = function() return false end, attackUp = function() return false end, attackDown = function() return false end,
           getFuelLevel = function() return 5000 end }
CONFIG = { digNearHome = 24, geoItem = "advancedperipherals:geo_scanner",
           digOk = { "stone", "dirt", "gravel", "deepslate", "*_ore" } }
S = { pos = { x = 0, y = 0, z = 0, f = 1 }, home = { x = 500, y = 70, z = 500 } }
local SENT = {}
function send(t, m) SENT[#SENT + 1] = { t = t, m = m } end
function ensureFuel() end
function frameMove() end
function moved(dx, dy, dz) S.pos.x, S.pos.y, S.pos.z = S.pos.x + dx, S.pos.y + dy, S.pos.z + dz end
function left() P.f = (P.f + 3) % 4 S.pos.f = P.f end
function right() P.f = (P.f + 1) % 4 S.pos.f = P.f end
local HAS = { pick = true, geo = true }
function findItemLike(part) return (part == "_pickaxe" and HAS.pick) and 4 or nil end
function findItem(name) return (name == CONFIG.geoItem and HAS.geo) and 5 or nil end
function withEquipped(_, f) return f() end
function withScanner(f) return f({ scan = function() return { { x = 1, y = 0, z = 0, name = "minecraft:stone" },
                                                                { x = 0, y = 2, z = 0, name = "minecraft:air" } } end }) end
function sleep() end
assert(load(code))()
-- move forward into air
local ok, msg = driveStep("f")
CHECK(ok and P.x == 1 and S.pos.x == 1, "FORWARD moves one block (" .. tostring(msg) .. ")")
-- blocked: says so at once, no waiting
setW(2, 0, 0, "minecraft:stone")
ok, msg = driveStep("f")
CHECK(not ok and msg == "blocked" and P.x == 1, "blocked: refused at once")
-- MINE FORWARD through stone
ok, msg = driveStep("minef")
CHECK(ok and P.x == 2 and dug[#dug] == "minecraft:stone", "MINE FORWARD digs + moves (" .. tostring(msg) .. ")")
-- planks: not without DIG ANYWAY
setW(3, 0, 0, "minecraft:oak_planks")
ok, msg = driveStep("digf")
CHECK(not ok and msg:find("DIG ANYWAY", 1, true) and Wd[k(3, 0, 0)], "planks: refused, offers DIG ANYWAY")
ok, msg = driveStep("digf", true)
CHECK(ok and not Wd[k(3, 0, 0)], "DIG ANYWAY digs the planks")
-- a chest: never, not even with force
setW(3, 0, 0, "minecraft:chest")
ok, msg = driveStep("digf", true)
CHECK(not ok and Wd[k(3, 0, 0)] and msg:find("items would be lost", 1, true), "a chest is never dug (" .. tostring(msg) .. ")")
-- falling gravel above the way: MINE UP keeps digging until it can move
setW(2, 1, 0, "minecraft:gravel")
FALLS[k(2, 1, 0)] = 2
ok, msg = driveStep("mineu")
CHECK(ok and P.y == 1, "MINE UP with falling gravel (" .. tostring(msg) .. ")")
-- near home: only with DIG ANYWAY
S.home = { x = 2, y = 1, z = 5 }
setW(2, 2, 0, "minecraft:dirt")
ok, msg = driveStep("digu")
CHECK(not ok and msg:find("close to home", 1, true), "near home: refused without DIG ANYWAY")
-- no pickaxe
S.home = { x = 500, y = 70, z = 500 }
HAS.pick = false
ok, msg = driveStep("digu")
CHECK(not ok and msg:find("no pickaxe", 1, true), "no pickaxe: says so")
HAS.pick = true
-- turning
driveStep("l")
CHECK(P.f == 0 and S.pos.f == 0, "TURN LEFT")
-- LOOK: front / up / down + the scan (air left out)
SENT = {}
driveLook(true)
local m = SENT[1] and SENT[1].m
CHECK(SENT[1] and SENT[1].t == "look" and m.up == "minecraft:dirt" and m.scan == "1,0,0,stone", "LOOK sends what it sees: " ..
      tostring(m and m.scan))
HAS.geo = false
SENT = {}
driveLook(true)
CHECK(SENT[1].m.scanErr and not SENT[1].m.scan, "no Geo Scanner: front / up / down only, says why")
print(FAILS == 0 and "OK" or (FAILS .. " failed"))
os.exit(FAILS == 0 and 0 or 1)
