-- node.lua fuel code, the cases that went wrong:
--  * a lava bucket was LEARNED as endless fuel (refuel leaves 1 item: an empty bucket)
--  * "only reusable" top-up burned whatever sat in a remembered slot after unloading
--  * an endless item that keeps refusing made ensureFuel wait FOR EVER (no budget)
--  * REFUEL / out of fuel burned planks, chests, wooden tools (the owner's things)
--  * mid-job with an endless item it did not know yet: could not move at all
--   lua5.3 tools/tests/node_fuel.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a, true)
  assert(a and b, "piece " .. from)
  return src:sub(a, b - 1)
end
local code = piece("function ensureFuel()", "-- STEPPING = ") ..
             piece("local TOPUP = {}", "-- one block to an ADJACENT") ..
             piece("function isFuel(n)", "-- what rescue gear") ..
             piece("-- REFUEL: every slot", "function listener()")
local fn, err = load(code, "=node pieces")
CHECK(fn, "pieces load: " .. tostring(err))
local FUEL, SEL, CLOCKV = 0, 1, 0
SLOTS = {}
local FUELVAL = { ["minecraft:coal"] = 80, ["minecraft:lava_bucket"] = 1000, ["minecraft:oak_planks"] = 15,
                  ["minecraft:chest"] = 15, ["minecraft:wooden_pickaxe"] = 10, ["glow:orb"] = 10, ["stuck:orb"] = 10 }
local ENDLESS = { ["glow:orb"] = true, ["stuck:orb"] = true }
local REFUSE = { ["stuck:orb"] = true }
local calls = 0
turtle = {
  getFuelLevel = function() return FUEL end, getFuelLimit = function() return 100000 end,
  getSelectedSlot = function() return SEL end, select = function(i) SEL = i return true end,
  getItemDetail = function(i) local d = SLOTS[i] return d and { name = d.name, count = d.count } end,
  getItemCount = function(i) return SLOTS[i] and SLOTS[i].count or 0 end,
  refuel = function(n)
    calls = calls + 1
    local d = SLOTS[SEL]
    if not d or not FUELVAL[d.name] or REFUSE[d.name] then return false end
    if n == 0 then return true end
    FUEL = FUEL + FUELVAL[d.name]
    if d.name == "minecraft:lava_bucket" then SLOTS[SEL] = { name = "minecraft:bucket", count = 1 }
    elseif not ENDLESS[d.name] then d.count = d.count - 1 if d.count == 0 then SLOTS[SEL] = nil end end
    return true
  end,
}
os.clock = function() return CLOCKV end
S, CONFIG, SLOT_LOCK, job, stopFlag = {}, {}, false, nil, false
function send() end function save() end function sleep(t) CLOCKV = CLOCKV + (t or 0) end
peripheral = { wrap = function() return nil end }
if fn then fn() end

-- 1) a lava bucket is NOT endless fuel
FUEL, S = 0, { refuelDone = true }
SLOTS = { [1] = { name = "minecraft:lava_bucket", count = 1 } }
topUp(5000, false, 50)
CHECK(not (S.reuse or {})["minecraft:lava_bucket"], "a lava bucket is not learned as endless fuel")
CHECK(FUEL == 1000 and SLOTS[1].name == "minecraft:bucket", "the lava was burned once, the bucket kept (" .. FUEL .. ")")

-- 2) remembered endless slot now holds COAL (after unloading): only-reusable burns nothing
FUEL, S = 0, { refuelDone = true, reuse = { ["glow:orb"] = true } }
SLOTS = { [3] = { name = "glow:orb", count = 1 } }
topUp(50, true, 40)
CHECK(REUSE_SLOTS and REUSE_SLOTS[1].i == 3, "the endless slot is remembered")
SLOTS = { [3] = { name = "minecraft:coal", count = 32 }, [7] = { name = "glow:orb", count = 1 } }
FUEL = 0
topUp(500, true, 40)
CHECK(SLOTS[3] and SLOTS[3].count == 32, "only-reusable top-up does not burn the coal now in the old slot")
CHECK(FUEL > 0, "...and finds the endless item where it is now (" .. FUEL .. ")")

-- 3) an endless item that keeps refusing: ensureFuel ends (no budget there)
FUEL, S, REUSE_SLOTS = 0, { refuelDone = true, reuse = { ["stuck:orb"] = true } }, nil
SLOTS = { [1] = { name = "stuck:orb", count = 1 } }
calls, CLOCKV = 0, 0
ensureFuel()
CHECK(calls < 1000, "a refusing endless item: ensureFuel gives up (" .. calls .. " refuel calls, " .. CLOCKV .. " s)")

-- 4) never the owner's wooden things / tools / containers
FUEL, S, REUSE_SLOTS = 0, {}, nil
SLOTS = { [1] = { name = "minecraft:oak_planks", count = 64 }, [2] = { name = "minecraft:chest", count = 4 },
          [3] = { name = "minecraft:wooden_pickaxe", count = 1 }, [4] = { name = "minecraft:coal", count = 2 } }
doRefuel()
CHECK(SLOTS[1] and SLOTS[1].count == 64 and SLOTS[2] and SLOTS[2].count == 4 and SLOTS[3], "REFUEL leaves planks, chests and wooden tools alone")
CHECK(not SLOTS[4], "...and burns the coal (" .. FUEL .. ")")
CHECK(neverBurn("minecraft:oak_log") and neverBurn("minecraft:barrel") and not neverBurn("minecraft:coal_block")
      and not neverBurn("glow:orb") and not neverBurn("minecraft:charcoal"), "neverBurn: wood/containers yes, fuel no")
CHECK(not isFuel("minecraft:coal_ore") and isFuel("minecraft:coal"), "coal ORE is not fuel")

-- 5) mid-job, out of fuel, an endless item it does not know yet: it can move again
FUEL, S, REUSE_SLOTS = 0, { refuelDone = true, reuse = { ["other:thing"] = true } }, nil
SLOTS = { [5] = { name = "glow:orb", count = 1 } }
job = { cmd = "goto" }
ensureFuel()
job = nil
CHECK(FUEL >= 20 and S.reuse["glow:orb"], "mid-job: the unknown endless item is found and used (" .. FUEL .. ")")

-- the fuel chest at home: wooden things in it are not burned (never taken as fuel)
local fs0 = src:match("local burnable = it and %((.-)%)\n")
CHECK(fs0 and fs0:find("neverBurn", 1, true), "the chest at home: neverBurn is checked before refuel(0)")
-- the report says when it carries endless fuel (base: no fuel trips for it)
CHECK(src:find("m.endless = REUSE_SLOTS ~= nil", 1, true) and src:find("\nREUSE_SLOTS = nil", 1, true), "reports m.endless (REUSE_SLOTS is global)")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
