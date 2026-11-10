-- ENERGY CELLS: an automata core's chargeTurtle turns a charged FE item into fuel,
-- tried FIRST when topping up (node.lua) / before coal (miner.lua).
--   lua5.3 tools/tests/node_cell.lua node.lua miner.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local a = src:find("function chargeFromCell(target)", 1, true)
local b = src:find("function topUp(", a, true)
load(src:sub(a, b - 1))()
local FUEL, CELL, SENT = 100, 5000, {}
turtle = { getFuelLevel = function() return FUEL end }
S = {}
function send(t, e) SENT[#SENT + 1] = e end
local core = { chargeTurtle = function(n) local g = math.min(n, CELL) CELL = CELL - g FUEL = FUEL + g
                                          if g == 0 then return nil, "no energy cell" end return g end }
local sides = { left = { transmit = function() end }, right = core }
peripheral = { wrap = function(s) return sides[s] end }
CHECK(chargeFromCell(2000) == 1900 and FUEL == 2000, "a cell fills up to the target (" .. FUEL .. ")")
CHECK(SENT[1] and tostring(SENT[1].msg):find("energy cell", 1, true), "the base is told once")
CHECK(chargeFromCell(1500) == 0, "already above the target: nothing")
CELL = 0 FUEL = 10
CHECK(chargeFromCell(2000) == 0 and FUEL == 10, "an empty cell: nothing, no error")
sides.right = nil
CHECK(chargeFromCell(2000) == 0, "no core: nothing, no error")
CHECK(src:find("pcall(chargeFromCell, target)", 1, true), "topUp tries the cell first")
local m = io.open(arg[2] or "miner.lua"):read("a")
local bc = m:sub(m:find("function burnCoal()", 1, true), m:find("-- endless fuel first", 1, true))
CHECK(bc:find("cc.chargeTurtle", 1, true), "miner: burnCoal tries a cell before coal / endless fuel")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
