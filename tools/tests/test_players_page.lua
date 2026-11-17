-- PLAYERS page: the list + everything about the picked player (where, from the base
-- with direction, how long in the dimension, moving speed from two readings, body,
-- bed, what the drones / turtles do about them, the raw detector data); players who
-- left are kept in the list; tapping picks one.
local HOME = CONFIG.drone.home or { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
local online = { "Alaory", "Mia" }
local pos = { Alaory = { x = HOME.x + 2, z = HOME.z }, Mia = { x = HOME.x + 300, z = HOME.z - 300 } }
det = { getOnlinePlayers = function() return online end,
        getPlayer = function(n)
          local p = pos[n]
          for _, o in ipairs(online) do if o == n then
            return { x = p.x, y = 70, z = p.z, dimension = "minecraft:overworld", health = 14, maxHealth = 20,
                     airSupply = 300, yaw = 180, pitch = -40, eyeHeight = 1.27,
                     respawnPosition = { x = 10, y = 64, z = -20 }, respawnDimension = "minecraft:overworld" } end end
          error("not online") end,
        getPlayersInRange = function() return online end }
state.owner = "Alaory"
PLAYER_INFO = {}
refreshPlayers(true)
CLOCK = CLOCK + 10
pos.Mia = { x = pos.Mia.x + 50, z = pos.Mia.z }                -- 50 blocks in 10 s = 5 blocks/s
refreshPlayers(true)
local function screen()
  hits = {}
  draw()
  local out = {}
  for y = 1, H do out[#out + 1] = (MONITOR.getLine(y)) end
  return table.concat(out, "\n")
end
state.page = "players"
state.playerSel = "Mia"
local s = screen()
CHECK(s:find("Mia  -  VISITOR", 1, true), "the picked player's panel (Mia, a visitor)")
CHECK(s:find("blocks north-east", 1, true), "distance AND direction from the base (" .. tostring(s:match("From the base[^\n]*")) .. ")")
CHECK(s:find("running", 1, true) and s:find("5.0 blocks/s", 1, true), "moving speed from two readings")
CHECK(s:find("sneaking", 1, true), "body: sneaking (eye height)")
CHECK(s:find("facing north, looking up", 1, true), "facing + looking up (yaw / pitch)")
CHECK(s:find("10, 64, -20", 1, true), "the bed (respawn position)")
CHECK(s:find("In it for", 1, true), "how long in the dimension")
CHECK(s:find("DETECTOR DATA", 1, true) and s:find("eyeHeight", 1, true), "every raw detector value")
CHECK(s:find("Alaory  YOU", 1, true), "the owner in the list, marked YOU")
-- Mia leaves: still in the list (offline, when she left)
online = { "Alaory" }
CLOCK = CLOCK + 60
refreshPlayers(true)
s = screen()
CHECK(s:find("left 0 s ago", 1, true) or s:find("left 1 min ago", 1, true) or s:find("left %d+ s ago"), "a player who left stays in the list")
-- a tap on a list row picks that player
local picked
for _, h in ipairs(hits) do if h[5] == "psel" and h[6] == "Alaory" then picked = h end end
CHECK(picked and picked[4] >= 2, "list rows are tap areas (2 rows)")
if picked then handleTouch(picked[1], picked[2]) end
CHECK(state.playerSel == "Alaory", "tapping a row picks the player (" .. tostring(state.playerSel) .. ")")
s = screen()
CHECK(s:find("Alaory  -  OWNER", 1, true) and s:find("at the base", 1, true), "the owner's panel: at the base")
