-- Base files on a FULL disk: settings.dat, saved places, the chat access list, chargers,
-- me_setup.dat ... were written in place (opening empties them) - a full disk wiped them.
-- Now writeSafe: the old file stays whole; a .tmp left behind is read back.
local open0 = fs.open
local full = false
fs.open = function(p, mode)
  local h = open0(p, mode)
  if mode == "w" and full and h then
    local w0 = h.write
    h.write = function(s) return w0(tostring(s):sub(1, 3)) end      -- (the disk ran out after 3 bytes)
  end
  return h
end
setSetting("turtles.idleHome", 300)
local okS = readSafe(SETTINGS_FILE)
CHECK(type(okS) == "table" and okS["turtles.idleHome"] == 300, "settings saved")
full = true
setSetting("turtles.idleHome", 450)
full = false
local t = readSafe(SETTINGS_FILE)
CHECK(type(t) == "table" and t["turtles.idleHome"] == 300, "full disk: settings.dat still holds the old settings (" .. tostring(t and t["turtles.idleHome"]) .. ")")
CHECK(not fs.exists(SETTINGS_FILE .. ".tmp"), "no half-written .tmp left")
-- saved places through saveWaypoints
state.waypoints = { mine = { x = 1, y = 2, z = 3 } }
saveWaypoints()
full = true
state.waypoints = { mine = { x = 1, y = 2, z = 3 }, other = { x = 9, y = 9, z = 9 } }
saveWaypoints()
full = false
local w = readSafe(CONFIG.drone.waypointFile)
CHECK(type(w) == "table" and w.mine and w.mine.x == 1, "full disk: the saved places are not wiped")
-- saveFileSafe reports it
full = true
local ok2, why = saveFileSafe("test_file.dat", string.rep("x", 100))
full = false
CHECK(ok2 == false and tostring(why):find("not saved", 1, true), "saveFileSafe: a cut-off write is reported, not kept (" .. tostring(why) .. ")")
-- a .tmp left by a stop between delete and move is read back
fs.delete(SETTINGS_FILE)
local h = open0(SETTINGS_FILE .. ".tmp", "w") h.write(textutils.serialize({ ["a.b"] = 7 })) h.close()
local t2 = readSafe(SETTINGS_FILE)
CHECK(type(t2) == "table" and t2["a.b"] == 7, "a settings.dat.tmp left behind is read back")
fs.open = open0
