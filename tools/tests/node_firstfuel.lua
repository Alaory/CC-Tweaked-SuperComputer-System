-- A NEW turtle with endless (reusable) fuel: it fills up only to FIRST_FUEL
-- (1000) before it moves - off the factory's build spot at once - and fills up
-- the rest later, wherever it waits. Also when the first job comes before the
-- first refuel (ensureFuel on the first move finds the reusable item).
--   lua5.3 tools/tests/node_firstfuel.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a, true)
  return src:sub(a, b - 1)
end
local code = piece("function ensureFuel()", "-- STEPPING = ") ..
             piece("local TOPUP = {}", "-- one block to an ADJACENT") ..
             piece("-- REFUEL: every slot", "function listener()")
local fn, err = load(code, "=node pieces")
CHECK(fn, "pieces load: " .. tostring(err))
local FUEL, SEL = 0, 1
local SLOTS = { [16] = { name = "mdc:core_piece", count = 1 } }      -- 10 fuel per use, never used up
turtle = {
  getFuelLevel = function() return FUEL end, getFuelLimit = function() return 100000 end,
  getSelectedSlot = function() return SEL end, select = function(i) SEL = i return true end,
  getItemDetail = function(i) local d = SLOTS[i] return d and { name = d.name, count = d.count } end,
  getItemCount = function(i) return SLOTS[i] and SLOTS[i].count or 0 end,
  refuel = function(n) local d = SLOTS[SEL] if not d then return false end
                       if n == 0 then return true end FUEL = FUEL + 10 return true end,
}
S, CONFIG, SLOT_LOCK, job, stopFlag = {}, {}, false, nil, false
function send() end function save() end function sleep() end
function isFuel(n) return n == "minecraft:coal" end
peripheral = { wrap = function() return nil end }
if fn then fn() end
-- the base sends it off the build spot BEFORE its first refuel: the first move
ensureFuel()
CHECK(FUEL >= 1000, "first move: filled up from the reusable item (" .. FUEL .. ")")
CHECK(FUEL <= 1010, "first move: only up to ~1000, then it goes (" .. FUEL .. " - was a full tank / 2000)")
CHECK(S.refuelDone and S.reuse and S.reuse["mdc:core_piece"], "learned as reusable, first refuel done")
-- the worker's own first refuel (no job yet): also only ~1000
FUEL, S = 0, {}
local ok, msg = doRefuel(true)
CHECK(FUEL >= 1000 and FUEL <= 1010, "first start: up to ~1000 (" .. FUEL .. ")")
CHECK(tostring(msg):find("keeps filling", 1, true), "it says it fills up the rest by itself (" .. tostring(msg) .. ")")
-- the REFUEL button: still as much as it can in one go
FUEL = 0
doRefuel()
CHECK(FUEL > 1010, "REFUEL button: more than the first-start amount (" .. FUEL .. ")")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
