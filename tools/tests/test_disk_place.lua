-- The computer's 1 MB is for the program: logs and the big data files go to a
-- data floppy when there is one (copies on the computer move along), and map
-- files saved on the computer earlier move to floppies / storage helpers.
local function onPc(name) return fs.exists(name) end
-- 1) no data floppy yet: on the computer
MAP.loaded = true
noteLogAdd({ title = "test", msg = "first", col = C.label })
sysLog("first system line", "INFO")
CHECK(onPc("events.log") and onPc("system.log"), "no floppy: the logs are on the computer")
-- the map saved on the computer (no floppy / helper)
local function scanAt(x, z)
  local cols = {}
  for i = 1, 17 * 17 do cols[i] = { 64, 1 } end
  MAP.addScan({ x = x, y = 70, z = z, r = 8, cols = cols, names = { "minecraft:grass_block" } })
end
for a = 0, 5 do for b = 0, 5 do scanAt(a * 17, b * 17) end end
MAP.save()
local pcMap = 0
for _, p in pairs(MAP.where) do if not p:find("^disk") and not p:find("^store:") then pcMap = pcMap + 1 end end
CHECK(pcMap > 0, "no floppy: the map is on the computer (" .. pcMap .. " files)")
-- 2) a data floppy is put in
addDrive("drive_9", "disk9")
fs.open("disk9/base_data", "w").close()
CLOCK = CLOCK + 61                                       -- (the place is looked up again after a minute)
noteLogAdd({ title = "test", msg = "second", col = C.label })
sysLog("second system line", "INFO")
CHECK(fs.exists("disk9/events.log") and not onPc("events.log"), "events.log moved to the data floppy")
CHECK(fs.exists("disk9/system.log") and not onPc("system.log"), "system.log moved to the data floppy")
local lines = noteLogLines()
CHECK(#lines >= 2 and lines[#lines]:find("second", 1, true), "the EVENTS lines are read back from the floppy")
MINE.units[5] = { id = 5, role = "miner", dim = "overworld", log = {}, queue = {} }
MINE.save()
CHECK(fs.exists("disk9/mining.dat") and not onPc("mining.dat"), "mining.dat on the data floppy")
state.turtles[77] = { id = 77, label = "T77", log = {} }
TT.saveList()
CHECK(fs.exists("disk9/turtles.dat") and not onPc("turtles.dat"), "turtles.dat on the data floppy")
state.turtles = {}
TT.loadList()
CHECK(state.turtles[77] and state.turtles[77].label == "T77", "turtles.dat is read back from the floppy")
-- 3) the map files still on the computer move off it
local moved = MAP.offload()
local left = 0
for _, p in pairs(MAP.where) do if not p:find("^disk") and not p:find("^store:") then left = left + 1 end end
CHECK(moved == pcMap and left == 0, "the old map files moved off the computer (" .. moved .. " of " .. pcMap .. ", " .. left .. " left)")
local stillThere = false
for _, f in ipairs(fs.list and fs.list("map") or {}) do stillThere = true end
CHECK(not stillThere or left == 0, "nothing left in the computer's map folder")
CHECK(MAP.offload() == 0, "nothing more to move")
