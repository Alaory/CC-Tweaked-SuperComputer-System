-- STUCK only when a trip could not MOVE (the owner: "some turtles report that they cannot move when they can"):
-- node.lua set its stuck flag for ANY failed trip - "fuel only for the way home", "position/facing unknown", "the
-- offered home is not free" - and the base sent the rescuer to turtles that were fine. Any step clears it.
--   lua5.3 tools/tests/node_stuck.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local a = src:find("MOVE_FAIL = {", 1, true)
local b = src:find("-- A move failed.", a, true)
CHECK(a and b, "MOVE_FAIL .. moved() found")
local fn, err = load(src:sub(a, b - 1), "=node pieces")
CHECK(fn, "pieces load: " .. tostring(err))
S = { pos = { x = 1, y = 2, z = 3 }, stuck = "blocked at 1 2 3" }
function save() end
if fn then fn() end
-- moving: no longer stuck
moved(1, 0, 0)
CHECK(S.stuck == nil and S.pos.x == 2, "a step clears the stuck flag")
-- what counts as "could not move"
for _, m in ipairs({ "blocked at 5 70 9", "could not reach 100 200 (at 5 70 9)", "no progress (going in circles) at 1 2 3",
                     "out of fuel at 1 2 3", "gave up after 6 plans", "no way up to the sky highway (blocked)",
                     "blocked (forward) at 1 2 3", "retracing blocked at 1 2 3", "no way found with what I know",
                     "blocked at 1 2 3 (scan 4/16)" }) do
  CHECK(isMoveFail(m), "a movement failure: " .. m)
end
for _, m in ipairs({ "fuel 1800 only for the way home (2400) after 3/16 scans", "low fuel (150) after 2 of 16 scans",
                     "position/facing unknown - use GPS LOCATE", "the offered home 1 2 3 is not free - asked the base for another one",
                     "no home set (SET HOME)", "area too big (900 scans) - zoom in on the map", "home spot not free",
                     "path record does not match my moves", "I am the ANCHOR (I keep the base loaded) - turn ANCHOR off first",
                     "could not equip the Geo Scanner", "no GPS signal - use setpos instead", "usage: goto x y z", "stopped at 1 2 3" }) do
  CHECK(not isMoveFail(m), "NOT a movement failure: " .. m)
end
-- the job end sets it only for those
CHECK(src:find('or j.cmd == "surveypts" or j.cmd == "rescue") and isMoveFail(msg) then', 1, true), "job end: S.stuck only when isMoveFail")
-- the base reads the same words
local base = io.open((((arg[1] or "node.lua"):gsub("node%.lua$", "base_turtles.lua")))):read("a")
local nl = src:match("MOVE_FAIL = (%b{})")
local bl = base:match("TT%.MOVE_FAIL = (%b{})")
CHECK(nl and nl == bl, "node.lua MOVE_FAIL == base_turtles.lua TT.MOVE_FAIL")
if FAILS > 0 then os.exit(1) end
print("node stuck: all checks passed")
