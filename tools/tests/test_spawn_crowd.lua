-- A CROWD AT SPAWN (voice_crowd.lua; the owner: "sometimes there might be a lot of players at spawn fighting / joking - add
-- some stuff for this"). The real voice files + the relay setup of test_spawn_scenarios; health readings changed by hand.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
CONFIG.voice = CONFIG.voice or {}
local SPAWN = { x = HOME.x + 3000, y = 70, z = HOME.z - 2000 }
local realExists = fs.exists
local HIDDEN = {}
for _, f in ipairs(VOICE_FILES) do HIDDEN[f] = true end
fs.exists = function(p) if HIDDEN[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
for i, f in ipairs(VOICE_FILES) do
  local k = 30 + i
  addDrive("drive_" .. k, "disk" .. k)
  put("disk" .. k .. "/base_data", "data")
  put("disk" .. k .. "/" .. f, io.open(SRC_DIR .. "/dist/" .. f):read("a"))
end
if dataPathReset then dataPathReset() end
package.preload["cc.audio.dfpwm"] = function()
  return { make_decoder = function() return function(s) local o = {} for i = 1, #s * 8 do o[i] = 0 end return o end end,
           make_encoder = function() return function(p) return string.rep("\0", math.floor(#p / 8)) end end }
end
package.loaded["cc.audio.dfpwm"] = nil
textutils.urlEncode = textutils.urlEncode or function(x) return tostring(x) end
http = { get = function() return { readAll = function() return string.rep("\0", 4800) end, close = function() end } end }
rednet = rednet or {}
rednet.send = function() return true end
local okL, errL = pcall(loadVoiceChain)
CHECK(okL and VOICE and VOICE.SPAWN, "the voice chain + spawn pack load: " .. tostring(errL))
local V, SP = VOICE, VOICE.SPAWN
setSetting("voice.spawnId", 77)
setSetting("voice.spawnKey", "k")
setSetting("voice.spawnAt", { x = SPAWN.x, y = SPAWN.y, z = SPAWN.z })
SP.seenAt = V.rt()
CHECK(SP.ready(), "the spawn speaker is ready")

state.owner = "Alaory"
local function online(...) state.online = {} for _, n in ipairs({ ... }) do state.online[n:lower()] = true end end
local function at(name, dx, dz) return { name = name, p = { x = SPAWN.x + (dx or 0), y = 70, z = SPAWN.z + (dz or 0) }, dim = DRONE_DIM } end
local function world(list)                    -- (who is where: "spawn" / "base" / "nether" / "far")
  state.players = {}
  local names = {}
  for name, where in pairs(list) do
    names[#names + 1] = name
    if where == "spawn" then state.players[#state.players + 1] = at(name, #names, 1)
    elseif where == "base" then state.players[#state.players + 1] = { name = name, p = { x = HOME.x, y = HOME.y, z = HOME.z }, dim = DRONE_DIM }
    elseif where == "nether" then state.players[#state.players + 1] = { name = name, p = { x = 10, y = 70, z = 10 }, dim = "minecraft:the_nether" }
    else state.players[#state.players + 1] = { name = name, p = { x = SPAWN.x + 900, y = 70, z = SPAWN.z }, dim = DRONE_DIM } end
  end
  online(table.unpack(names))
end
state.me = { items = {
  { name = "minecraft:diamond", display = "Diamond", count = 5000 },
  { name = "minecraft:apple", display = "Apple", count = 900 },
  { name = "minecraft:elytra", display = "Elytra", count = 3 },
  { name = "minecraft:dragon_egg", display = "Dragon Egg", count = 1 },
  { name = "minecraft:torch", display = "Torch", count = 9000 },
  { name = "minecraft:stone", display = "Stone", count = 90000 },
  { name = "minecraft:gold_block", display = "Block of Gold", count = 800 },
  { name = "minecraft:gold_ingot", display = "Gold Ingot", count = 8000 },
  { name = "minecraft:redstone_block", display = "Block of Redstone", count = 300 },
  { name = "minecraft:iron_block", display = "Block of Iron", count = 300 },
  { name = "minecraft:diamond_block", display = "Block of Diamond", count = 300 },
  { name = "minecraft:ender_pearl", display = "Ender Pearl", count = 300 },
  { name = "minecraft:sweet_berries", display = "Sweet Berries", count = 300 },
  { name = "mekanism:block_osmium", display = "Block of Osmium", count = 60 },
  { name = "create:brass_block", display = "Block of Brass", count = 60 },
  { name = "thermal:tin_block", display = "Tin Block", count = 60 },
  { name = "mekanism:ingot_osmium", display = "Osmium Ingot", count = 600 },
  { name = "ae2:fluix_block", display = "Fluix Block", count = 60 } }, byName = {} }
local told = {}
chatTell = function(who, text) told[#told + 1] = { who = who, text = tostring(text) } end
local rideN = 0
startRide = function(name, dest)
  told[#told + 1] = { who = name, text = "[RIDE to " .. tostring(dest.name) .. "]" }
  rideN = rideN + 1
  state.lastRide = state.lastRide or {}
  state.lastRide[name:lower()] = rideN
end
droneOrder = { "d1" }

-- one scenario: fresh state, then steps
local function fresh()
  told = {}
  SP.queue, SP.spam, SP.helpAt, SP.wpend, SP.tpMood = {}, {}, {}, {}, {}
  V.convo, V.pend, V.games, V.chatAt, V.talkingTo = {}, {}, {}, {}, {}
  SP.spokeAt, SP.callAt, SP.greetAt, SP.reactAt = nil, nil, nil, nil
  for i = #V.giftQueue(), 1, -1 do table.remove(V.giftQueue(), i) end
  local s = SP.mem()
  s.wish, s.wall = {}, nil
end
local function say(who, msg)
  local n0 = #told
  local q0 = #SP.queue
  local ok, err = pcall(V.chat, { name = who, msg = msg })
  CHECK(ok, "'" .. msg .. "' from " .. who .. " - no error: " .. tostring(err))
  local out = {}
  for i = n0 + 1, #told do if told[i].who == who then out[#out + 1] = told[i].text end end
  local spoken = {}
  for i = 1, #SP.queue do if i > q0 or SP.queue[i].answer then spoken[#spoken + 1] = SP.queue[i].text end end
  local c = table.concat(out, " | ")
  if SP.err then CHECK(false, "'" .. msg .. "': spawn error: " .. tostring(SP.err)) SP.err = nil end
  CHECK(not c:find("{name}", 1, true) and not c:find("{botl}", 1, true) and not c:find("attempt to", 1, true),
        "'" .. msg .. "': no unfilled / error text: " .. c)
  return c, table.concat(spoken, " | ")
end
local function has(t, ...) t = t:lower() for _, w in ipairs({ ... }) do if t:find(w:lower(), 1, true) then return true end end return false end
local MENU = "type a number"
-- (the relay plays what is queued: the test empties the queue after every step into LOG, like the speaker would)
local LOG = {}
local function drain() for _, q in ipairs(SP.queue) do LOG[#LOG + 1] = q end SP.queue = {} end
local say1 = say
say = function(...) local c, sp = say1(...) drain() return c, sp end
local CR = V.CROWD
CHECK(CR and V.packs["voice_crowd.lua"], "the crowd pack loads")
CONFIG.voice.spamBurst, CONFIG.voice.spamSame = 100000, 0
SP.online = function() return true end              -- (the relay says hello every 20 s in game; the test moves the clock)
local function tick(n) for _ = 1, (n or 1) do for _, f in ipairs(V.tickHooks) do pcall(f) end end drain() end
local function spokenSince(q0) local out = {} for i = q0 + 1, #LOG do out[#out + 1] = LOG[i].text end return table.concat(out, " | ") end
local function lineIn(text, list, subs)
  for _, l in ipairs(list) do
    local x = l
    for k, v in pairs(subs or {}) do x = x:gsub("{" .. k .. "}", v) end
    if text:find(x, 1, true) then return true end
  end
  return false
end
local function setHp(name, h)
  for _, e in ipairs(state.players) do if e.name == name then e.p.health, e.p.maxHealth = h, 20 end end
end
local function reset()
  fresh()
  CR.score, CR.hp, CR.hurtAt, CR.lowSaid, CR.fight, CR.duel, CR.quiz, CR.vote = {}, {}, {}, {}, nil, nil, nil, nil
  CR.spoke, CR.ownAt, CR.saidAt, CR.heard, CR.levelAt, CR.lastN, CR.fightSaid, CR.hitSaid = {}, nil, {}, {}, {}, 0, nil, nil
  SP.queue, SP.said = {}, {}
  SP.spokeAt = nil
end

-- 1) the crowd grows: one line for 5+
reset()
world({ Steve = "spawn", Alex = "spawn" })
tick()
local q0 = #LOG
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn", Kim = "spawn", Zed = "spawn" })
CLOCK = CLOCK + 30
tick()
local s1 = spokenSince(q0)
CHECK(s1 ~= "" and (lineIn(s1, CR.GROW[5]) or lineIn(s1, CR.GROW[3])), "5 players at spawn: a crowd line: " .. s1)
-- 2) NOT TALKING OVER EVERYONE: 10 questions in a row - every one answered in chat, at most 4 spoken in 20 s
reset()
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn", Kim = "spawn", Zed = "spawn" })
CLOCK = CLOCK + 60
local names = { "Steve", "Alex", "Mia", "Kim", "Zed" }
q0 = #LOG
local chats = 0
for i = 1, 10 do
  local c = say(names[(i % 5) + 1], "speaker tell me a joke")
  if c ~= "" then chats = chats + 1 end
end
local nAns = 0
for i = q0 + 1, #LOG do if LOG[i].answer then nAns = nAns + 1 end end
CHECK(chats == 10 and nAns <= 4, "a crowd: 10 answers in chat (" .. chats .. "), at most 4 spoken (" .. nAns .. ")")
-- 3) A FIGHT from the health readings: a fight line, a hit, low hearts, a knockout with the winner, the scoreboard
reset()
world({ Steve = "spawn", Alex = "spawn" })
for _, e in ipairs(state.players) do e.p.x, e.p.z = SPAWN.x + 1, SPAWN.z + 1 end
setHp("Steve", 20) setHp("Alex", 20)
tick()
q0 = #LOG
CLOCK = CLOCK + 2 setHp("Steve", 16) tick()
CLOCK = CLOCK + 2 setHp("Alex", 15) tick()
local s3 = spokenSince(q0)
CHECK(lineIn(s3, CR.FIGHT, { a = "Alex", b = "Steve" }) or lineIn(s3, CR.FIGHT, { a = "Steve", b = "Alex" }), "two players hurt next to each other = a fight: " .. s3)
q0 = #LOG
CLOCK = CLOCK + 2 setHp("Steve", 5) tick()
local s3b = spokenSince(q0)
CHECK(s3b:find("Steve", 1, true) and (s3b:find("heart", 1, true)), "low health: the commentator says the hearts: " .. s3b)
q0 = #LOG
CLOCK = CLOCK + 2 setHp("Steve", 2) tick()
CLOCK = CLOCK + 2 setHp("Steve", 20) tick()                   -- (a respawn: low, then full at once)
local s3c = spokenSince(q0)
CHECK(lineIn(s3c, CR.DOWN, { a = "Steve", b = "Alex" }), "a knockout: Steve is down, Alex wins: " .. s3c)
CHECK(CR.score.alex and CR.score.alex.w == 1 and CR.score.steve.d == 1, "the scoreboard counts it")
local sb = say("Steve", "speaker scoreboard")
CHECK(sb:find("Alex", 1, true) and sb:find("1 win", 1, true), "speaker, scoreboard: " .. sb)
-- one player falling alone (fall damage, no fight) is no fight
reset()
world({ Steve = "spawn", Alex = "spawn" })
setHp("Steve", 20) setHp("Alex", 20)
tick()
q0 = #LOG
CLOCK = CLOCK + 2 setHp("Steve", 12) tick()
CHECK(not CR.fight and not lineIn(spokenSince(q0), CR.FIGHT, { a = "Steve", b = "Alex" }), "one player hurt alone: no fight")
-- 4) A DUEL: called by name, a countdown, the first one down loses
reset()
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn" })
setHp("Steve", 20) setHp("Alex", 20)
tick()
local d0 = say("Steve", "duel alex")
CHECK(not CR.duel, "'duel alex' WITHOUT its name: no duel (players talk among themselves)")
q0 = #LOG
say("Steve", "speaker duel alex")
CHECK(CR.duel and CR.duel.b == "Alex", "speaker, duel alex: a duel")
CHECK(spokenSince(q0):find("FIGHT", 1, true) or spokenSince(q0):find("GO", 1, true), "a countdown: " .. spokenSince(q0))
q0 = #LOG
CLOCK = CLOCK + 2 setHp("Alex", 0) tick()
local s4 = spokenSince(q0)
CHECK(lineIn(s4, CR.DUEL_WIN, { w = "Steve", l = "Alex" }) and not CR.duel, "Alex down: Steve wins the duel: " .. s4)
-- a duel nobody finishes = a draw after 3 min
say("Steve", "speaker 1v1 mia")
q0 = #LOG
CLOCK = CLOCK + 200 tick()
CHECK(not CR.duel and lineIn(spokenSince(q0), CR.DUEL_DRAW, { a = "Steve", b = "Mia" }), "3 min and nobody down: a draw: " .. spokenSince(q0))
-- 5) A GROUP QUIZ: everyone gets the question, the first right answer wins the round
reset()
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn" })
local n0 = #told
say("Steve", "speaker group quiz")
CHECK(CR.quiz and CR.quiz.q, "speaker, group quiz: a quiz starts")
local gotQ = {}
for i = n0 + 1, #told do if told[i].text:find("question 1", 1, true) then gotQ[told[i].who] = true end end
CHECK(gotQ.Steve and gotQ.Alex and gotQ.Mia, "everyone at spawn gets the question in chat")
local ans = tostring(CR.quiz.q.a[1])
n0 = #told
say("Mia", ans)
local gotIt = false
for i = n0 + 1, #told do if told[i].text:find("Mia got it", 1, true) then gotIt = true end end
CHECK(gotIt and CR.quiz and CR.quiz.round == 2 and CR.score.mia.q == 1, "Mia answers first: her point, question 2")
CLOCK = CLOCK + 45 tick()
CHECK(CR.quiz and CR.quiz.round == 3, "nobody answers in 40 s: the answer is said, the next question")
for _ = 1, 3 do say("Alex", tostring(CR.quiz.q.a[1])) end
CHECK(not CR.quiz, "after 5 questions the quiz is over")
CHECK(not (V.mem().mia and V.mem().mia.quiz), "no quiz points saved at spawn")
-- 6) A ROAST BATTLE: a roast for each, the crowd votes
reset()
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn", Kim = "spawn" })
say("Steve", "bot roast battle alex")
CHECK(CR.vote and CR.vote.b == "Alex", "bot, roast battle alex: a vote opens")
say("Mia", "1") say("Kim", "1") say("Alex", "2")
CHECK(CR.vote.votes.alex == nil, "a battler's own vote does not count (the crowd decides)")
n0 = #told
CLOCK = CLOCK + 50 tick()
local won = false
for i = n0 + 1, #told do if told[i].text:find("Steve wins the roast battle", 1, true) then won = true end end
CHECK(won and not CR.vote, "the crowd's 2 votes: Steve wins the roast battle")
-- 6b) REVIEW FIXES
-- "can we duel with alex": the name after "with" (it took the first words of the message: "duel")
reset()
world({ Steve = "spawn", Alex = "spawn", Youri = "spawn" })
setHp("Steve", 20) setHp("Alex", 20) setHp("Youri", 20)
tick()
say("Steve", "speaker can we duel with alex")
CHECK(CR.duel and CR.duel.b == "Alex", "speaker, can we duel with alex: a duel with Alex (" .. tostring(CR.duel and CR.duel.b) .. ")")
CR.duel = nil
say("Steve", "speaker i challenge you")
CHECK(not CR.duel, "'i challenge you' is no duel with Youri (you is not a name)")
-- a knockout from 8 hearts' worth of health straight to a respawn (a 2-s reading misses the last hits)
reset()
world({ Steve = "spawn", Alex = "spawn" })
for _, e in ipairs(state.players) do e.p.x, e.p.z = SPAWN.x + 1, SPAWN.z + 1 end
setHp("Steve", 20) setHp("Alex", 20)
tick()
CLOCK = CLOCK + 2 setHp("Steve", 14) tick()
CLOCK = CLOCK + 2 setHp("Alex", 12) tick()
q0 = #LOG
CLOCK = CLOCK + 2 setHp("Steve", 8) tick()
CLOCK = CLOCK + 2 setHp("Steve", 20) tick()
CHECK(lineIn(spokenSince(q0), CR.DOWN, { a = "Steve", b = "Alex" }), "8 health, then full at once (a respawn): a knockout: " .. spokenSince(q0))
-- died and respawned at a bed far away: gone from spawn right after a low reading = down (a duel)
reset()
world({ Steve = "spawn", Alex = "spawn" })
setHp("Steve", 20) setHp("Alex", 20)
tick()
say("Steve", "speaker duel alex")
CLOCK = CLOCK + 2 setHp("Alex", 4) tick()
q0 = #LOG
for _, e in ipairs(state.players) do if e.name == "Alex" then e.p.x = SPAWN.x + 900 e.p.health = 20 end end
CLOCK = CLOCK + 2 tick()
CHECK(not CR.duel and lineIn(spokenSince(q0), CR.DUEL_WIN, { w = "Steve", l = "Alex" }), "duelist gone from spawn just after 4 health: Steve wins: " .. spokenSince(q0))
-- a player dying alone (no fight, no duel) is not on the scoreboard
reset()
world({ Steve = "spawn", Alex = "spawn" })
setHp("Steve", 20) setHp("Alex", 20)
tick()
CLOCK = CLOCK + 2 setHp("Steve", 0) tick()
CHECK(not CR.score.steve, "a death alone (lava, a fall) is no score")
-- a group quiz: no question twice in one game; one chat line per step; the timer counts the chat backlog
reset()
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn" })
state.chatOut = {}
for i = 1, 20 do state.chatOut[i] = { name = "x", text = "waiting" } end
say("Steve", "speaker group quiz")
CHECK(CR.quiz and CR.quiz.till >= V.rt() + 40 + 20, "20 chat lines waiting: 22 s more to answer (" .. tostring(CR.quiz and (CR.quiz.till - V.rt())) .. ")")
state.chatOut = {}
local asked = { [CR.quiz.q.q] = 1 }
local twice = false
n0 = #told
for _ = 1, 4 do
  say("Mia", tostring(CR.quiz.q.a[1]))
  if CR.quiz then if asked[CR.quiz.q.q] then twice = true end asked[CR.quiz.q.q] = 1 end
end
CHECK(not twice, "five different questions in one group quiz")
local both = false
for i = n0 + 1, #told do if told[i].who == "Steve" and told[i].text:find("got it", 1, true) and told[i].text:find("question 2", 1, true) then both = true end end
CHECK(both, "'Mia got it' and the next question go in ONE chat line")
-- 7) JOKING: laughter from several players, trash talk, gg after a fight - spoken only, minutes apart, nothing in chat
reset()
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn" })
q0 = #LOG
n0 = #told
say("Steve", "lol that was so funny") say("Alex", "hahaha") say("Mia", "lmao")
local s7 = spokenSince(q0)
CHECK(lineIn(s7, CR.LAUGH), "three laughs from several players: a comment: " .. s7)
local chatted = false
for i = n0 + 1, #told do if lineIn(told[i].text, CR.LAUGH) then chatted = true end end
CHECK(not chatted, "... spoken only, nothing in chat")
q0 = #LOG
say("Steve", "lol") say("Alex", "haha") say("Mia", "lol")
CHECK(not lineIn(spokenSince(q0), CR.LAUGH), "... not again within 10 min")
q0 = #LOG
say("Alex", "ez noob")
CHECK(lineIn(spokenSince(q0), CR.TRASH), "trash talk: a comment: " .. spokenSince(q0))
-- 8) many random messages from a crowd: no error, no unfilled text
reset()
world({ Steve = "spawn", Alex = "spawn", Mia = "spawn", Kim = "spawn", Zed = "spawn" })
local WORDS = { "lol", "ez", "gg", "speaker", "duel", "alex", "group quiz", "roast battle", "1", "2", "fight me", "haha", "scoreboard", "%", "{", "noob", "bot" }
for i = 1, 300 do
  local m = {}
  for _ = 1, math.random(1, 5) do m[#m + 1] = WORDS[math.random(1, #WORDS)] end
  say(names[math.random(1, 5)], table.concat(m, " "))
  if i % 7 == 0 then CLOCK = CLOCK + math.random(1, 30) setHp(names[math.random(1, 5)], math.random(0, 20)) tick() end
end
CHECK(true, "300 messy crowd messages with health changes: no error")
-- voice name: one plain word only ("(" or "%" in it broke every chat answer: the name goes into patterns)
local name0 = CONFIG.voice.name
VOICE.command({ "voice", "name", "(bot" })
CHECK(CONFIG.voice.name == name0, "voice name (bot: refused (" .. tostring(CONFIG.voice.name) .. ")")
VOICE.command({ "voice", "name", "r2-d2" })
CHECK(CONFIG.voice.name == name0, "voice name r2-d2: refused")
VOICE.command({ "voice", "name", "Sparky" })
CHECK(CONFIG.voice.name == "sparky", "voice name Sparky: saved as sparky")
local okN, errN = pcall(VOICE.chat, { name = "Steve", msg = "sparky what time is it" })
CHECK(okN, "chat still works after a rename: " .. tostring(errN))
if name0 ~= nil then setSetting("voice.name", name0) else resetSetting("voice.name") end
