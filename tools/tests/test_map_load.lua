-- The map is read in the background: scans during loading wait and are added
-- afterwards, nothing is saved before it is read, CLEAR MAP waits, the load
-- pauses between files (map worker only), node.lua loads the same with pauses.
-- (this test is about loading, not disk room: the program files - ~900 KB of the
-- 1 MB - do not count here, or the 30x30 scans no longer fit on the computer)
CODE_SIZE = 0
local function scanAt(x, z, top)
  local cols = {}
  for i = 1, 17 * 17 do cols[i] = { top or 0, 1 } end
  MAP.addScan({ x = x, y = 70, z = z, r = 8, cols = cols, names = { "minecraft:grass_block" } })
end
for a = 0, 29 do for b = 0, 29 do scanAt(a * 17, b * 17) end end
CHECK(MAP.save(true), "the map saves")
local files = 0
for _ in pairs(MAP.where) do files = files + 1 end
local ovBefore = MAP.ovN
CHECK(files > 5, "several map files (" .. files .. ")")

-- the base starts again: nothing in memory
MAP.ch, MAP.order, MAP.ov, MAP.where, MAP.dirty = {}, {}, {}, {}, {}
MAP.names, MAP.nameIdx = {}, {}
MAP.scans, MAP.tick, MAP.ovN = 0, 0, 0
MAP.loaded = false
scanAt(1000, 1000, 5)                                -- a scan while loading
CHECK(#MAP.pendingScans == 1, "a scan during loading waits")
CHECK(MAP.save(true) == false, "no save before the map is read")
CHECK(MAP.clear() == false, "CLEAR MAP waits until the map is read")
CHECK(next(MAP.where) == nil, "(clear did nothing)")

local yields = 0
local qe, pe = os.queueEvent, os.pullEvent
os.queueEvent = function() end
os.pullEvent = function(f) yields = yields + 1 return coroutine.yield(f) end
MAP.canYield = true
local co = coroutine.create(MAP.loadNow)
TT.yieldCo = co
while coroutine.status(co) ~= "dead" do
  local ok, e = coroutine.resume(co, "map_loading")
  if not ok then CHECK(false, "load error: " .. tostring(e)) break end
end
CHECK(MAP.loaded, "loaded")
CHECK(yields >= files, "a pause after every file (" .. yields .. " for " .. files .. " files)")
CHECK(MAP.ovN >= ovBefore, "the whole map is back (" .. MAP.ovN .. " / " .. ovBefore .. ")")
CHECK(MAP.get(1000, 1000) == 75, "the scan from loading time is in (" .. tostring(MAP.get(1000, 1000)) .. ")")
CHECK(MAP.save(true), "saves after loading")

-- node.lua: loaded in the map worker with pauses - the same program
CODE, TT.yieldCo = nil, nil
TT.codeLoad(true)
local plain = CODE and CODE.ver
CHECK(plain ~= nil, "node.lua loads")
CODE, yields = nil, 0
local co2 = coroutine.create(function() TT.codeLoad(true) end)
TT.yieldCo = co2
while coroutine.status(co2) ~= "dead" do
  local ok, e = coroutine.resume(co2, "base_working")
  if not ok then CHECK(false, "codeLoad error: " .. tostring(e)) break end
end
CHECK(CODE and CODE.ver == plain, "same node.lua version with pauses")
CHECK(yields > 3, "codeLoad pauses (" .. yields .. ")")
CHECK(#CODE.text < 120000, "shrunk node.lua fits on the install floppy (" .. #CODE.text .. " bytes)")
-- outside the map worker: never a pause (other workers must not lose events)
TT.yieldCo, yields = nil, 0
TT.codeLoad(true)
CHECK(yields == 0, "no pauses outside the map worker")
os.queueEvent, os.pullEvent = qe, pe
