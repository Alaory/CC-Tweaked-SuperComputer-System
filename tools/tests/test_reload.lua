-- LOADING AGAIN (the owner: "when the base loads / unloads everything needs to be reconnected - other stuff is in other
-- chunks and not loaded" + "or a reboot"): set up by pre_reload.lua - the Inventory Manager and data floppy #77 (in
-- drive_5) are missing at the start. The base must START (it crashed: the Inventory Manager was required), wait for
-- them first, never save turtles.dat / mining.dat anywhere else, find the block when it comes, and restart ONCE when
-- the floppy comes (its data was read as nothing).
CHECK(state ~= nil and draw ~= nil, "the base loaded with the Inventory Manager missing (it was required = a crash at every start)")
CHECK(inv == nil, "no Inventory Manager yet")
CHECK(WAITS >= 50 and CLOCK - CLOCK0 >= 50, "it waited for them first (~60 s; " .. tostring(WAITS) .. " waits)")
local miss = {}
for _, e in ipairs(NET_START_MISSING) do miss[e.name] = e end
CHECK(miss.inventory_manager_3 and miss["floppy #77"], "started without: the Inventory Manager + floppy #77")
CHECK(not miss.old_block_1, "a block last seen 5 days ago is not waited for")
CHECK(DATA_AWAY["turtles.dat"] == 77 and DATA_AWAY["mining.dat"] == 77, "turtles.dat / mining.dat: their floppy is away")
-- 1) never saved elsewhere meanwhile
local ok1, why1 = saveFileSafe("turtles.dat", "{}")
CHECK(not ok1 and tostring(why1):find("#77", 1, true), "turtles.dat is NOT saved on the computer meanwhile: " .. tostring(why1))
addDrive("drive_6", "disk6")
FILES["disk6/base_data"] = "data"
local ok2 = saveFileSafe("disk6/mining.dat", "{}")
CHECK(not ok2, "... nor on another data floppy")
CHECK(saveFileSafe("waypoints.dat", "{}") == true, "other files are saved as usual")
-- 2) pinned blocks that are not there: no crash at the start
local okL, p = pcall(locate, "ME/RS Bridge", "me_bridge_99", BR_TYPES)
CHECK(okL and p == nil, "a block pinned in CONFIG.names that is not loaded: nil, no error")
-- 3) every page draws without the Inventory Manager
for _, pg in ipairs({ "home", "inventory", "storage", "curios", "players", "turtles", "system" }) do
  state.page = pg
  local okD, err = pcall(draw)
  CHECK(okD, pg .. " draws without the Inventory Manager: " .. tostring(err))
end
state.page = "system"
-- 4) its chunk loads: found again at the next check (also when the "peripheral" event was lost)
PERIPHS.inventory_manager_3 = SAVED_INV
local restarts = 0
BASE_RESTART = function() restarts = restarts + 1 end
netTick()
CHECK(inv ~= nil, "the Inventory Manager is found at the next check")
CHECK(restarts == 0, "no restart for a block")
-- 5) the floppy's chunk loads: the map is saved and the base restarts once
addDrive("drive_5", "disk5")
DRIVE_IDS.drive_5 = 77
FILES["disk5/base_data"] = "data"
FILES["disk5/turtles.dat"] = "{ [7] = { id = 7 } }"
FILES["disk5/mining.dat"] = "{}"
CHECK(dataAway("turtles.dat") == nil, "the floppy is here: no longer away")
netTick()
CHECK(restarts == 1, "floppy #77 is back: the base restarts once to read it (" .. restarts .. ")")
netTick()
CHECK(restarts == 1, "... only once")
-- 6) what it saw is remembered for the next start
state.netRestarting = nil
DATA_AWAY = {}
noteNetwork(true)
local seen = textutils.unserialize(FILES["net_seen.dat"])
local has = {}
for _, f in ipairs(seen and seen.f[77] and seen.f[77].files or {}) do has[f] = true end
CHECK(seen and seen.p.inventory_manager_3 and has["turtles.dat"] and has["mining.dat"], "net_seen.dat: the blocks + floppy #77 with its data files")
-- 7) the wait ends at once on a tap / a key, and returns what is still missing
NET.p.far_block_0 = { t = "chest", at = os.epoch("utc") }
local n = 0
os.pullEventRaw = function() n = n + 1 return "monitor_touch", "right", 3, 3 end
local left = waitForNetwork()
CHECK(n == 1 and #left == 1 and left[1].name == "far_block_0", "a tap starts the base at once (" .. n .. " events)")
-- 8) nothing remembered (a first start): no wait at all
NET.p, NET.f = {}, {}
n = 0
CHECK(#waitForNetwork() == 0 and n == 0, "nothing remembered: no waiting")
-- 9) the source: the Inventory Manager is not required any more
local src = io.open(SRC_DIR .. "/base_devices.lua"):read("a")
CHECK(not src:find('IM_TYPES, true)', 1, true), "base_devices.lua: the Inventory Manager is not required")
-- 10) a data floppy that UNLOADS while the base runs and comes back with an old copy: only the newest copy stays
NET.f[88] = { at = os.epoch("utc"), drive = "drive_8", files = { "drone_logs.dat" } }
local MOD = {}
fs.attributes = function(p) return { modified = MOD[p] or 0, size = #(FILES[p] or "") } end
addDrive("drive_8", "disk8")
FILES["disk8/base_data"] = "data"
FILES["disk8/drone_logs.dat"] = "old"
MOD["disk8/drone_logs.dat"] = 1000
FILES["disk6/drone_logs.dat"] = "new"            -- (saved on disk6 while drive_8's chunk was not loaded)
MOD["disk6/drone_logs.dat"] = 5000
local removed = dedupeDataFiles()
CHECK(removed == 1 and FILES["disk8/drone_logs.dat"] == nil and FILES["disk6/drone_logs.dat"] == "new",
      "the floppy came back with an OLD copy: the old one is removed, the newest stays (" .. tostring(removed) .. ")")
-- no times known: nothing is deleted
fs.attributes = function() return {} end
FILES["disk8/drone_logs.dat"] = "old"
CHECK(dedupeDataFiles() == 0 and FILES["disk8/drone_logs.dat"] == "old", "when the times cannot be told nothing is deleted")
fs.attributes = nil
