-- (set-up BEFORE the base loads, for test_broken.lua) - a player broke parts of the base while it was off: the
-- MONITOR, the ME Bridge me_bridge_4, a chest, and took data floppy #55 (pockets.dat on it).
local now = os.epoch("utc")
FILES["net_seen.dat"] = textutils.serialize({
  p = { right = { t = "monitor", at = now - 7200000 },
        me_bridge_4 = { t = "me_bridge", at = now - 7200000 },
        ["minecraft:chest_9"] = { t = "minecraft:chest", at = now - 7200000 },
        turtle_12 = { t = "turtle", at = now - 7200000 },
        inventory_manager_3 = { t = "inventory_manager", at = now - 7200000 } },
  f = { [55] = { at = now - 7200000, drive = "drive_9", files = { "pockets.dat" } } } })
SAVED_MON = PERIPHS.right
PERIPHS.right = nil
CLOCK0 = CLOCK
os.pullEventRaw = function() CLOCK = CLOCK + 1 return "timer", 1 end
