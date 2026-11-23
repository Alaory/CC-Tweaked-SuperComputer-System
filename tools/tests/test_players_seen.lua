-- EVERY PLAYER EVER SEEN IS REMEMBERED (the owner: "keep the list of players remembered, even players who went offline, even
-- after a year"): players_seen.dat - first seen, last seen, visits, time on the server, last place; over a restart and a year.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
local online = { "Alaory", "Mia", "Kim" }
local pos = { Alaory = { x = HOME.x + 2, z = HOME.z }, Mia = { x = HOME.x + 300, z = HOME.z }, Kim = { x = HOME.x - 40, z = HOME.z + 900 } }
det = { getOnlinePlayers = function() return online end,
        getPlayer = function(n)
          for _, o in ipairs(online) do if o == n then
            local p = pos[n]
            return { x = p.x, y = 70, z = p.z, dimension = "minecraft:overworld", health = 20, maxHealth = 20 } end end
          error("not online") end,
        getPlayersInRange = function() return online end }
state.owner = "Alaory"
local function file() return dataPath(SEEN_FILE) end
local function restart() PLAYER_INFO = {} resetSeenPlayers() if dataPathReset then dataPathReset() end end
for _, p in ipairs({ SEEN_FILE, SEEN_FILE .. ".tmp" }) do if fs.exists(p) then fs.delete(p) end end
restart()
refreshPlayers(true)
CLOCK = CLOCK + 30
refreshPlayers(true)
CHECK(PLAYER_INFO.kim and PLAYER_INFO.kim.visits == 1 and math.floor(PLAYER_INFO.kim.played or 0) == 30, "a visit counted, time played: " ..
      tostring(PLAYER_INFO.kim and PLAYER_INFO.kim.played))
-- Kim leaves; saved within ~10 s
online = { "Alaory", "Mia" }
CLOCK = CLOCK + 1
refreshPlayers(true)
CLOCK = CLOCK + 11
refreshPlayers(true)
CHECK(fs.exists(file()), "players_seen.dat saved after a leave: " .. tostring(file()))
-- THE BASE RESTARTS: Kim is still known
restart()
refreshPlayers(true)
local k = PLAYER_INFO.kim
CHECK(k and k.online == false and k.left and k.visits == 1 and (k.played or 0) >= 30 and k.x == HOME.x - 40,
      "after a restart: Kim remembered (offline, when she left, visits, time played, last spot)")
-- A YEAR LATER: still in the list, on the page
CLOCK = CLOCK + 366 * 86400
refreshPlayers(true)
restart()
refreshPlayers(true)
CHECK(PLAYER_INFO.kim and PLAYER_INFO.kim.online == false, "a year later (and another restart): Kim is still remembered")
state.page = "players"
state.playerSel = "Kim"
hits = {}
draw()
local out = {}
for y = 1, H do out[#out + 1] = MONITOR.getLine(y) end
local s = table.concat(out, "\n")
CHECK(s:find("Kim", 1, true) and s:find("1 year", 1, true), "the page: Kim, left 1 year ago")
CHECK(s:find("Visits", 1, true) and s:find("First seen", 1, true), "the page: visits + first seen for an offline player")
-- she comes back: a 2nd visit, online again
online = { "Alaory", "Mia", "Kim" }
refreshPlayers(true)
CHECK(PLAYER_INFO.kim.online and PLAYER_INFO.kim.visits == 2, "back after a year: visit 2 (" .. tostring(PLAYER_INFO.kim.visits) .. ")")
-- a join / leave event counts the visit once, not twice with the online list
playerLeft("Mia")
playerJoined("Mia", "minecraft:overworld")
refreshPlayers(true)
CHECK(PLAYER_INFO.mia.visits == 2, "join event + online list = one visit (" .. tostring(PLAYER_INFO.mia.visits) .. ")")
-- many players: the newest SEEN_MAX kept
for n = 1, SEEN_MAX + 200 do
  PLAYER_INFO["p" .. n] = { name = "P" .. n, online = false, left = os.epoch("utc") - (SEEN_MAX + 200 - n) * 1000, visits = 1 }
end
saveSeenPlayers(true)
restart()
refreshPlayers(true)
local n = 0
for _ in pairs(PLAYER_INFO) do n = n + 1 end
CHECK(n <= SEEN_MAX + 3 and PLAYER_INFO["p" .. (SEEN_MAX + 200)] and not PLAYER_INFO.p1, "at most " .. SEEN_MAX .. " kept, the newest (" .. n .. ")")
CHECK(fs.getSize(file()) < 120000, "the file stays small enough for a floppy: " .. fs.getSize(file()))
-- an odd file never stops the base
for _, odd in ipairs({ "7", "{ 1, 2, 3 }", "{ { 5, 'x' }, { 'Ok', 'no', {}, 9, 'many' } }", "nonsense {{{" }) do
  local h = fs.open(file(), "w") h.write(odd) h.close()
  restart()
  local ok, err = pcall(refreshPlayers, true)
  CHECK(ok, "an odd players_seen.dat (" .. odd .. "): no error " .. tostring(err))
end
-- a base restart while a player is online is not a new visit
for _, p in ipairs({ SEEN_FILE, SEEN_FILE .. ".tmp" }) do if fs.exists(p) then fs.delete(p) end end
restart()
online = { "Alaory", "Zed" }
pos.Zed = { x = 5, z = 5 }
refreshPlayers(true)
CLOCK = CLOCK + 5
saveSeenPlayers(true)
restart()
CLOCK = CLOCK + 60
refreshPlayers(true)
CHECK(PLAYER_INFO.zed.visits == 1, "a base restart while Zed plays: still visit 1 (" .. tostring(PLAYER_INFO.zed.visits) .. ")")
