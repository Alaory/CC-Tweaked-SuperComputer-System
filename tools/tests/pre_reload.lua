-- (set-up BEFORE the base loads, for test_reload.lua - run_tests sets PRE to this file)
-- The base saw these last time: the Inventory Manager, a bridge, and data floppy #77 in drive_5 with turtles.dat +
-- mining.dat. Now (a server restart) the Inventory Manager's and drive_5's chunks are not loaded yet.
local now = os.epoch("utc")
FILES["net_seen.dat"] = textutils.serialize({
  p = { inventory_manager_3 = { t = "inventory_manager", at = now - 3600000 },
        right = { t = "monitor", at = now - 3600000 },
        old_block_1 = { t = "chest", at = now - 5 * 86400000 } },            -- (5 days ago: not waited for)
  f = { [77] = { at = now - 3600000, drive = "drive_5", files = { "turtles.dat", "mining.dat" } } } })
SAVED_INV = PERIPHS.inventory_manager_3
PERIPHS.inventory_manager_3 = nil
DRIVE_IDS = {}
disk.getID = function(n) return DRIVE_IDS[n] end
CLOCK0 = CLOCK
WAITS = 0
os.pullEventRaw = function() WAITS = WAITS + 1 CLOCK = CLOCK + 1 return "timer", 1 end
