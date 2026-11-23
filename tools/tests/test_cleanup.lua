-- the remote-access feature was taken out again (the owner: "taking space and seems useless"):
-- its files are removed at start; the owner's own pocket.lua (no local mode) stays
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
put("prog/remote.lua", "-- remote")
put("prog/base_remote.lua", "-- base remote")
put("cloud.lua", string.rep("x", 2000))
put("prog/pocket.lua", "local LOCAL = _G.POCKET_LOCAL")
local gone = removeOldFiles("prog")
CHECK(not fs.exists("prog/remote.lua") and not fs.exists("prog/base_remote.lua") and not fs.exists("cloud.lua"),
      "remote access files removed (" .. table.concat(gone, ", ") .. ")")
CHECK(not fs.exists("prog/pocket.lua"), "the pocket.lua copy that feature put on the base is removed")
put("prog/pocket.lua", "-- the owner's own pocket program")
removeOldFiles("prog")
CHECK(fs.exists("prog/pocket.lua"), "an older pocket.lua (not that copy) is left alone")
local src = io.open(SRC_DIR .. "/inventory.lua"):read("a")
CHECK(src:find("removeOldFiles", 1, true), "inventory.lua runs the cleanup at start")
CHECK(not io.open(SRC_DIR .. "/base_remote.lua") and not io.open(SRC_DIR .. "/remote.lua"), "the feature's files are gone from the program")
