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
-- idle top-up toward a full tank: an order that comes in stops it at once
FUEL = 3000
local r0 = turtle.refuel
local uses = 0
turtle.refuel = function(n) uses = uses + 1 if uses == 5 then job = { cmd = "home" } end return r0(n) end
topUp(100000, true, 40)
turtle.refuel, job = r0, nil
CHECK(uses <= 6, "an order while filling up: it stops filling and goes (" .. uses .. " uses)")
-- A COPY (server crash) / a turtle that knows OTHER endless items: refuelDone, S.reuse without
-- the item it carries now, fuel 0, idle -> it sat at 0 for good. Now it tries what it carries.
FUEL, S, job = 0, { refuelDone = true, reuse = { ["othermod:old_orb"] = true } }, nil
SLOTS = { [1] = { name = "glowmod:endless_orb", count = 1 } }
os.clock = os.clock or function() return 0 end
CHECK(idleEmptyFuel() == true and FUEL >= 20, "idle at 0 fuel with an unknown endless item: refuelled (" .. FUEL .. ")")
CHECK(S.reuse["glowmod:endless_orb"], "...and the item is learned as endless")
-- not again within a minute, never with a job, never when it has fuel
FUEL = 0
CHECK(idleEmptyFuel() == false and FUEL == 0, "tried at most once a minute")
FUEL, EMPTY_TRY = 0, nil
job = { cmd = "home" }
CHECK(idleEmptyFuel() == false, "not while a job runs (ensureFuel does that on the move)")
job = nil
FUEL, EMPTY_TRY = 500, nil
CHECK(idleEmptyFuel() == false, "not when it has fuel")
-- an EMPTY reuse list must not count as "first refuel done"
local isrc = src:match("if not S.refuelDone and %((.-)%) then")
CHECK(isrc and isrc:find("next(S.reuse)", 1, true), "an empty endless-fuel list is not 'refuelled'")
CHECK(src:find("pcall(idleEmptyFuel)", 1, true), "the idle loop calls it")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
