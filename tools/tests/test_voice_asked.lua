-- WHAT YOU ASK IS WHAT YOU GET (the owner: "go over all the features - I am sure you did something silly like this", after a
-- 24-hour reminder became 4 hours). Every example in COMMANDS.md was replayed; these answered something else:
-- "roll a d20" -> 1-6, "roll 2 dice" -> one die, "pick a number from 1 to 10" -> 17, "random number 1-6" -> 89, "flip 3 coins"
-- -> one, "be quiet for 2 hours" -> 30 min, "forget my notes" -> SHOWED the notes, "take me to the base" (at the base) -> a
-- story, "tell Steve the farm is ready" -> nonsense, the lonely base's wall / memory / days when the owner is around -> a story
-- or the menu, "base count to 5" while a guessing game runs -> "Higher.". Console: env / world / me jobs / cpus / raw / cancel
-- printed with print() (nothing came back to the console's own output), `lost` said "task 'nil'".
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
CONFIG.voice = CONFIG.voice or {}
local realExists = fs.exists
local HIDDEN = {}
for _, f in ipairs(VOICE_FILES) do HIDDEN[f] = true end
fs.exists = function(p) if HIDDEN[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
for i, f in ipairs(VOICE_FILES) do
  local k = 80 + i
  addDrive("drive_" .. k, "disk" .. k)
  put("disk" .. k .. "/base_data", "data")
  put("disk" .. k .. "/" .. f, io.open(SRC_DIR .. "/dist/" .. f):read("a"))
end
if dataPathReset then dataPathReset() end
local okL, errL = pcall(loadVoiceChain)
CHECK(okL and VOICE, "voice loads: " .. tostring(errL))
local V = VOICE
state.owner = "Alaory"
local told = {}
chatTell = function(who, text) told[#told + 1] = tostring(text) end
local said = {}

V.useEnv = function() return false end
pcall(ENV.read, true)
state.online = { alaory = true }
state.players = { { name = "Alaory", p = { x = HOME.x, y = HOME.y, z = HOME.z }, dim = DRONE_DIM } }
local function ask(msg)
  told, said = {}, {}
  V.chatAt = {}
  V.chat({ name = "Alaory", msg = msg, uuid = "u-Alaory" })
  return table.concat(told, " | ")
end
local function fresh() V.pend, V.games, V.convo = {}, {}, {} if V.CONVO and V.CONVO.state then V.CONVO.state = {} end end
-- dice
local big, two = false, true
for _ = 1, 40 do
  fresh()
  local n = tonumber(ask("base roll a d20"):match("rolled a (%d+)"))
  if n and n > 6 then big = true end
  if not n or n < 1 or n > 20 then two = false end
end
CHECK(big and two, "roll a d20: 1-20 (and not only 1-6)")
fresh()
local r = ask("base roll 2 dice")
CHECK(r:match("rolled %d+, %d+") and r:find("in all", 1, true), "roll 2 dice: two dice + the sum: " .. r)
fresh()
r = ask("base roll 3d6")
CHECK(r:match("rolled %d+, %d+, %d+"), "3d6: " .. r)
-- numbers in a range
local ok = true
for _ = 1, 40 do
  fresh()
  local n = tonumber(ask("base pick a number from 1 to 10"):match("pick (%-?%d+)"))
  if not n or n < 1 or n > 10 then ok = false end
  fresh()
  n = tonumber(ask("base random number 1-6"):match("pick (%-?%d+)"))
  if not n or n < 1 or n > 6 then ok = false end
end
CHECK(ok, "from 1 to 10 / 1-6 stay in the range")
fresh()
r = ask("base flip 3 coins")
CHECK(select(2, r:gsub("heads", "")) + select(2, r:gsub("tails", "")) >= 4, "flip 3 coins: three results + the count: " .. r)
fresh()
r = ask("base be quiet for 2 hours")
CHECK(r:find("2 h", 1, true) and V.isQuiet(), "quiet for 2 hours: " .. r)
fresh()
r = ask("base talk to me")
CHECK(not V.isQuiet(), "talk to me ends it")
-- notes
fresh() ask("base remember the farm is at 100 200")
fresh() r = ask("base forget my notes")
CHECK(r:find("gone", 1, true) and not r:find("100 200", 1, true), "forget my notes forgets them: " .. r)
-- the taxi at the base
fresh() r = ask("base take me to the base")
CHECK(r:find("at the base already", 1, true), "take me to the base, said at the base: " .. r)
-- mail to someone it does not know (no "that")
fresh() r = ask("base tell Steve the farm is ready")
CHECK(r:find("do not know anyone called", 1, true), "tell Steve ... (unknown): " .. r)
-- the lonely base's things while the owner is around
fresh() r = ask("base read the wall")
CHECK(r:find("away", 1, true) and r:find("wall", 1, true), "read the wall (not lonely) says when: " .. r)
fresh() r = ask("base how long has it been?")
CHECK(r:find("not gone", 1, true), "how long has it been (not lonely): " .. r)
-- a number with the name during a guessing game is not a guess
fresh() ask("base guess my number")
local g = V.games.alaory
r = ask("base count to 5")
CHECK(V.games.alaory == g and g.tries == 0 and not r:find("Higher", 1, true) and not r:find("Lower", 1, true),
      "base count to 5 during a game is no guess: " .. r)
r = ask("50")
CHECK(g.tries == 1, "a plain number is a guess")
-- console: the answers come back (not print)
local out = table.concat(handleCommand("env") or {}, "\n")
CHECK(#out > 0, "env answers through the console output: " .. out:sub(1, 80))
out = table.concat(handleCommand("me jobs") or {}, "\n")
CHECK(#out > 0, "me jobs answers through the console output")
-- $drone: a second ride request while a drone is already coming said "All drones are busy" (the other drone was charging)
do
  local c = "$" .. CONFIG.chat.command
  state.players[1].p = { x = HOME.x + 5, y = HOME.y, z = HOME.z, yaw = 0 }
  told = {}
  handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = c .. " home" })
  local first = table.concat(told, " ")
  told = {}
  handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = c .. " to Base" })
  local second = table.concat(told, " ")
  CHECK(not first:find("coming to you", 1, true) or second:find("already on its way", 1, true),
        "a second request while a drone is coming says so: " .. first .. " / " .. second)
end
