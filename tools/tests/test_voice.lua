-- THE BASE TALKS (voice_addon.lua, an optional add-on on a data floppy): loaded from the floppy,
-- greets players coming near the base, says warnings only when someone can hear them, answers
-- "base, status?" in chat, the alarm, speech cached on the floppy, nothing when it is off.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
local realEnvDet = envDet
envDet = nil                 -- (parts 1-9: no Environment Detector - the Player Detector within range)
CONFIG.drone.home = HOME
-- a data floppy with the add-on on it
addDrive("drive_7", "disk7")
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
put("disk7/base_data", "data")
put("disk7/voice_addon.lua", io.open(SRC_DIR .. "/dist/voice_addon.lua"):read("a"))     -- (the slim copy - what voice install puts there)
if dataPathReset then dataPathReset() end
CHECK(addonPath("voice_addon.lua") == "disk7/voice_addon.lua", "the add-on is found on the data floppy")
VOICE = nil
local okL, where = loadAddon("voice_addon.lua")
CHECK(okL and VOICE and VOICE.loop, "it loads from the floppy: " .. tostring(where))

-- a speaker, the internet (text-to-speech), cc.audio.dfpwm
local played, sounds, gets = 0, {}, {}
PERIPHS["speaker_0"] = { types = { "speaker" }, obj = {
  playAudio = function(buf, vol) played = played + 1 return true end,
  playSound = function(name) sounds[#sounds + 1] = name return true end } }
http = { get = function(url, headers, binary)
  gets[#gets + 1] = url
  return { readAll = function() return string.rep("\85", 3000) end, close = function() end }
end }
package.preload["cc.audio.dfpwm"] = function() return { make_decoder = function() return function(s) return { #s } end end } end
textutils.urlEncode = textutils.urlEncode or function(s) return (s:gsub("[^%w]", function(c) return string.format("%%%02X", c:byte()) end)) end
local function said()                                   -- what is waiting to be spoken
  local t = {}
  for _, q in ipairs(VOICE.queue) do t[#t + 1] = q.text end
  return table.concat(t, " | ")
end
local function speakAll() while #VOICE.queue > 0 do VOICE.play(table.remove(VOICE.queue, 1)) end end

-- players: the owner and a stranger, far away first
local owner = knownOwner and knownOwner() or state.owner or "Alaory"
state.owner = owner
state.online = { [owner:lower()] = true, ["steve"] = true }
local function place(name, dx)
  for _, e in ipairs(state.players) do if e.name == name then e.p = { x = HOME.x + dx, y = HOME.y, z = HOME.z } e.dim = "minecraft:overworld" return end end
  state.players[#state.players + 1] = { name = name, p = { x = HOME.x + dx, y = HOME.y, z = HOME.z }, dim = "minecraft:overworld" }
end
state.players = {}
place(owner, 5000)
place("Steve", 6000)
VOICE.queue, VOICE.near, VOICE.greeted = {}, {}, {}

-- 1. a warning with nobody near: not said (nobody hears it)
VOICE.note("TURTLE STUCK", "Turtle 9 is stuck - the rescuer goes", C.warn)
CHECK(#VOICE.queue == 0, "a warning with nobody near the base is not said")

-- 2. the owner comes home: welcome back + a status, with a chime
place(owner, 10)
VOICE.tick()
CHECK(said():find(owner, 1, true) and said():find("working", 1, true) and VOICE.queue[1].sound, "the owner is welcomed back (+ how the turtles are): " .. said())
speakAll()
CHECK(#gets == 1 and gets[1]:find("music.madefor.cc/tts", 1, true) and played > 0, "spoken: text-to-speech fetched, played on the speaker")
CHECK(fs.list("disk7/voice")[1] ~= nil, "the phrase is kept on the DATA floppy (voice/)")
VOICE.tick()
CHECK(#VOICE.queue == 0, "not greeted again while staying")

-- 3. the same phrase later: from the cache, not the internet
VOICE.said = {}
VOICE.say("Hello there.")
speakAll()
local n = #gets
VOICE.said = {}
VOICE.say("Hello there.")
speakAll()
CHECK(#gets == n, "a phrase said before comes from the floppy, not the internet")

-- 4. a warning now that someone is near: by default (summary) COLLECTED, not said at once (the owner:
--    "too much notifications"); "all" says it, with a bell; the same one again soon: not
VOICE.note("TURTLE STUCK", "Turtle 9 is stuck - the rescuer goes", C.warn)
CHECK(#VOICE.queue == 0 and VOICE.pending.n == 1, "summary mode: a warning is collected, not said at once")
VOICE.pending = { n = 0 }
setSetting("voice.announce", "all")
VOICE.note("TURTLE STUCK", "Turtle 9 is stuck - the rescuer goes", C.warn)
CHECK(said():find("Warning. turtle stuck. Turtle 9 is stuck", 1, true), "announce all: a warning is said when someone is near: " .. said())
VOICE.queue = {}
CLOCK = CLOCK + 25
VOICE.note("TURTLE STUCK", "Turtle 9 is stuck - the rescuer goes", C.warn)
CHECK(#VOICE.queue == 0, "the same warning is not repeated within 5 minutes")
VOICE.note("INFO", "just information", C.label)
CHECK(#VOICE.queue == 0, "info messages are not said")

-- 5. a stranger comes near: "Visitor"; the alarm only when switched on
place("Steve", 20)
VOICE.tick()
CHECK(said():find("Steve", 1, true) and said():find("not seen you before", 1, true) and not said():find("Intruder", 1, true),
      "a stranger met for the first time: introduced, no alarm (off by default): " .. said())
VOICE.queue = {}
setSetting("voice.alarm", true)
place("Steve", 9000) VOICE.tick()
CLOCK = CLOCK + 700
place("Steve", 20) VOICE.tick()
CHECK(said():find("Intruder alert", 1, true), "alarm on: intruder alert: " .. said())
VOICE.queue = {}
ENV = ENV or {}
ENV.data = { ents = { { kind = "hostile", name = "Zombie", dist = 6 } } }
VOICE.alarmAt.mob = nil
VOICE.tick()
CHECK(said():find("zombie is close", 1, true), "alarm on: a zombie close to the base: " .. said())
setSetting("voice.alarm", false)
VOICE.queue = {}

-- 6. chat: "base, status?" from someone near -> out loud AND in chat; others are ignored
local told = {}
local oldTell = chatTell
chatTell = function(name, text) told[#told + 1] = name .. ": " .. text end
CHECK(VOICE.chat({ name = owner, msg = "base, status?" }) and told[1] and told[1]:find("working", 1, true)
      and said():find("working", 1, true), "base, status? -> answered in chat and out loud: " .. tostring(told[1]))
VOICE.queue, told = {}, {}
VOICE.convo, VOICE.pend = {}, {}
CHECK(not VOICE.chat({ name = owner, msg = "baseball is fun" }), "baseball is not for the base")
CHECK(VOICE.chat({ name = owner, msg = "Base what time is it" }) and told[1], "a question about the time is answered: " .. tostring(told[1]))
place("Steve", 9000)
told = {}
CHECK(not VOICE.chat({ name = "Steve", msg = "base, status" }) and #told == 0, "a stranger far away is not answered")
place(owner, 8000)
VOICE.queue, told = {}, {}
CHECK(VOICE.chat({ name = owner, msg = "base, who is online" }) and told[1] and #VOICE.queue == 0, "the owner far away: answered in chat only (nobody to hear it)")
chatTell = oldTell
-- a $ command never reaches the voice
local hit = false
local oldChat = VOICE.chat
VOICE.chat = function() hit = true return false end
pcall(handleChat, { name = owner, msg = "$" .. CONFIG.chat.command .. " status" })
VOICE.chat = oldChat
CHECK(not hit, "a $ command is not taken as a question")

-- 7. switched off: says nothing; no speaker: says why
place(owner, 10)
setSetting("voice.on", false)
CHECK(not VOICE.say("anything"), "voice off: nothing is said")
setSetting("voice.on", true)
PERIPHS["speaker_0"] = nil
VOICE.say("no speaker here")
speakAll()
CHECK(tostring(VOICE.err):find("Speaker", 1, true), "no speaker: it says why: " .. tostring(VOICE.err))

-- 8. console + the hooks in the base
local out = handleCommand("voice")
CHECK(table.concat(out, "\n"):find("THE BASE TALKS", 1, true), "console `voice` shows its state")
out = handleCommand("voice greet off")
CHECK(VOICE.cfg("greet", true) == false, "voice greet off is kept (a false setting is not read as unset)")
local src = io.open(SRC_DIR .. "/base_me.lua"):read("a")
CHECK(src:find("VOICE.note", 1, true), "pushNote passes warnings to the voice")
src = io.open(SRC_DIR .. "/inventory.lua"):read("a")
CHECK(src:find('loadAddon, "voice_addon.lua"', 1, true) and src:find("addonWorker", 1, true), "inventory.lua loads the add-on and runs its worker")
local man = io.open(SRC_DIR .. "/manifest.txt"):read("a")
CHECK(man:find("\nvoice voice_addon.lua ", 1, true) and not man:find("\nbase voice_addon.lua", 1, true),
      "voice_addon.lua is its own download (not installed on the computer)")
-- 9. remove: the file is gone, the base quiet
out = handleCommand("voice remove")
CHECK(not fs.exists("disk7/voice_addon.lua") and VOICE == nil, "voice remove deletes it from the floppy")
out = handleCommand("voice")
CHECK(table.concat(out, "\n"):find("voice install", 1, true), "not installed: `voice` says how to install it")

-- 10. WITH the Environment Detector: who is at the base = its scan (players right at the system).
--     The Player Detector alone (within 64 blocks) is not enough any more.
put("disk7/voice_addon.lua", io.open(SRC_DIR .. "/dist/voice_addon.lua"):read("a"))     -- (the slim copy - what voice install puts there)
VOICE = nil
loadAddon("voice_addon.lua")
PERIPHS["speaker_0"] = { types = { "speaker" }, obj = { playAudio = function() return true end, playSound = function() return true end } }
local SCAN = {}
envDet = setmetatable({ scanEntities = function(r) return SCAN end }, { __index = realEnvDet or {} })
ENV.scanAt, ENV.range = -100, nil
state.ownerUuid = "u-owner"
setSetting("voice.greet", true)                          -- (part 8 switched it off)
state.players = {}
place(owner, 40)                                         -- 40 blocks off: the Player Detector sees it
place("Steve", 6000)
VOICE.queue, VOICE.near, VOICE.greeted = {}, {}, {}
VOICE.tick()
CHECK(VOICE.useEnv() and #VOICE.queue == 0, "in Player Detector range but NOT seen by the Environment Detector: no greeting")
SCAN = { { name = "minecraft:player", uuid = "u-owner", x = 3, y = 0, z = 2, health = 20, maxHealth = 20 } }
CLOCK = CLOCK + 6
VOICE.tick()
CHECK(said():find(owner, 1, true), "the detector sees the owner at the system: welcomed: " .. said())
VOICE.queue = {}
-- an unnamed player in the scan: the nearest online player the Player Detector knows (Steve is far)
place("Steve", 12)
SCAN = { { name = "minecraft:player", uuid = "u-owner", x = 3, y = 0, z = 2 }, { name = "minecraft:player", x = -4, y = 0, z = 1 } }
CLOCK = CLOCK + 6
VOICE.tick()
CHECK(said():find("Steve", 1, true), "an unnamed player at the system gets the nearest known name: " .. said())
VOICE.queue = {}
-- the owner walks off (out of the detector's scan): warnings are no longer said
SCAN = {}
CLOCK = CLOCK + 6
VOICE.tick()
VOICE.queue = {}                                         -- (a goodbye may have been said)
VOICE.noteSeen, VOICE.noteAt = {}, nil
VOICE.note("SOMETHING", "went wrong", C.warn)
CHECK(#VOICE.queue == 0, "nobody at the system (scan empty): warnings are not said")
local o2 = handleCommand("voice")
CHECK(table.concat(o2, "\n"):find("Environment Detector", 1, true), "`voice` says who is at the base comes from the Environment Detector")
handleCommand("voice detector off")
CHECK(not VOICE.useEnv(), "voice detector off: back to the Player Detector")
setSetting("voice.detector", true)

-- 11. FUN (the owner: "make it interactive"): reactions to chat, its name anywhere, jokes, songs,
--     where is a turtle, remembered people, strangers hanging around, hurt players, night, mobs,
--     small talk - all only while someone is at the base, with cooldowns
SCAN = { { name = "minecraft:player", uuid = "u-owner", x = 2, y = 0, z = 1, health = 20, maxHealth = 20 } }
CLOCK = CLOCK + 6
VOICE.tick()
VOICE.queue = {}
told = {}
chatTell = function(name, text) told[#told + 1] = text end
-- (talking to someone ELSE next to them: chat is not for the base, it only reacts now and then)
place("Steve", 10)
SCAN = { { name = "minecraft:player", uuid = "u-owner", x = 2, y = 0, z = 1, health = 20, maxHealth = 20 }, { name = "minecraft:player", x = -3, y = 0, z = 0 } }
CLOCK = CLOCK + 6
VOICE.tick()
VOICE.queue, VOICE.convo, VOICE.pend = {}, {}, {}
told = {}
CHECK(VOICE.chat({ name = owner, msg = "hi everyone" }) and said():find(owner, 1, true) and #told == 0, "hi to others near the base: it says hi too (spoken only): " .. said())
VOICE.queue = {}
CHECK(not VOICE.chat({ name = owner, msg = "thanks" }), "not twice within 15 s (cooldown)")
CLOCK = CLOCK + 50
CHECK(VOICE.chat({ name = owner, msg = "gg" }) and said():find("ood game", 1, true) or said():find("G G", 1, true), "gg -> good game: " .. said())
VOICE.queue = {}
place("Steve", 9000)
SCAN = { { name = "minecraft:player", uuid = "u-owner", x = 2, y = 0, z = 1, health = 20, maxHealth = 20 } }
CLOCK = CLOCK + 6
VOICE.tick()
VOICE.queue = {}
local isJoke = function(t) for _, j in ipairs(VOICE.JOKES) do if t and t:sub(1, #j) == j then return true end end return false end
CHECK(VOICE.chat({ name = owner, msg = "can the base tell me a joke" }) and #VOICE.queue == 1 and isJoke(told[#told]),
      "its name ANYWHERE in a sentence: answered (a joke): " .. tostring(told[#told]))
VOICE.queue = {}
VOICE.chat({ name = owner, msg = "base, sing" })
local tuneQueued = false
for _, q in ipairs(VOICE.queue) do if q.tune then tuneQueued = true end end
CHECK(tuneQueued, "base, sing -> a tune on the note blocks")
local notes = 0
PERIPHS["speaker_0"].obj.playNote = function() notes = notes + 1 return true end
speakAll()
CHECK(notes >= 4, "the tune is played note by note (" .. notes .. ")")
state.turtles = state.turtles or {}
state.turtles[63] = { id = 63, label = "Turtle 63", pos = { x = HOME.x + 300, y = 70, z = HOME.z - 400 }, task = "survey", lastSeen = CLOCK, log = {} }
told = {}
VOICE.chat({ name = owner, msg = "base where is turtle 63" })
CHECK(told[1] and told[1]:find("500 blocks north-east", 1, true), "where is turtle 63 -> how far and which way: " .. tostring(told[1]))
told = {}
VOICE.chat({ name = owner, msg = "base how are you" })
CHECK(told[1] and (told[1]:find("great", 1, true) or told[1]:find("need", 1, true) or told[1]:find("behaving", 1, true) or told[1]:find("humming", 1, true)),
      "how are you -> its mood: " .. tostring(told[1]))
told = {}
VOICE.chat({ name = owner, msg = "base what can you do" })
CHECK(told[1] and told[1]:find("joke", 1, true), "what can you do -> the list: " .. tostring(told[1]))
-- a hurt player at the base
VOICE.queue = {}
SCAN = { { name = "minecraft:player", uuid = "u-owner", x = 2, y = 0, z = 1, health = 4, maxHealth = 20 } }
CLOCK = CLOCK + 6
VOICE.tick()
CHECK(said():find("hurt", 1, true) or said():find("health is low", 1, true), "a hurt player is told: " .. said())
VOICE.queue = {}
-- a stranger hanging around for 2 minutes
place("Mallory", 12)
state.online["mallory"] = true
SCAN = { { name = "minecraft:player", uuid = "u-owner", x = 2, y = 0, z = 1, health = 20, maxHealth = 20 }, { name = "Mallory", x = -3, y = 0, z = 2 } }
CLOCK = CLOCK + 6
VOICE.tick()
CHECK(said():find("Mallory", 1, true), "a new stranger is noticed: " .. said())
VOICE.queue = {}
CLOCK = CLOCK + 130
VOICE.tick()
CHECK(said():find("standing here for a while", 1, true), "a stranger standing around for 2 minutes is asked: " .. said())
VOICE.queue = {}
-- remembered: the owner's record on the data floppy
CHECK(VOICE.mem()[owner:lower()] and VOICE.mem()[owner:lower()].visits >= 1, "it remembers who it met (on the data floppy)")
-- night falls while someone is there
ENV.data = ENV.data or {}
ENV.data.ents = {}
ENV.data.time = 6000
CLOCK = CLOCK + 6
VOICE.tick()
VOICE.queue = {}
ENV.data.time = 13500
CLOCK = CLOCK + 6
VOICE.tick()
CHECK(said():find("sun is setting", 1, true) or said():find("Night is falling", 1, true), "night falls: it says so: " .. said())
VOICE.queue = {}
-- a creeper right next to a player
local ME = { kind = "player", name = owner, dist = 2, hp = 20, max = 20 }
ENV.data.ents = { ME, { kind = "hostile", name = "Creeper", dist = 3 } }
VOICE.alarmAt.close = nil
CLOCK = CLOCK + 6
local okScan = ENV.scan
ENV.scan = function() end                               -- (keep the fake mob list)
VOICE.tick()
CHECK(said():find("creeper right next to you", 1, true), "a creeper right next to you: warned (alarm off): " .. said())
VOICE.queue = {}
-- small talk after a while
ENV.data.ents = { ME }
VOICE.nextChat = CLOCK - 1
VOICE.lastSaid = nil
CLOCK = CLOCK + 6
VOICE.tick()
CHECK(#VOICE.queue >= 1, "small talk while someone stays: " .. said())
VOICE.queue = {}
-- fun off: no reactions, no small talk; questions still answered
VOICE.games, VOICE.pending = {}, { n = 0 }
setSetting("voice.fun", false)
CLOCK = CLOCK + 100
CHECK(not VOICE.chat({ name = owner, msg = "lol" }), "fun off: no reactions")
VOICE.nextChat = CLOCK - 1
VOICE.tick()
CHECK(#VOICE.queue == 0, "fun off: no small talk")
told = {}
CHECK(VOICE.chat({ name = owner, msg = "base, status" }) and told[1], "fun off: questions are still answered")
setSetting("voice.fun", true)

-- 12. FEWER NOTIFICATIONS: summary mode collects warnings into ONE line every 15 min; errors 2 min apart
setSetting("voice.announce", "summary")
VOICE.queue, VOICE.pending, VOICE.pendingAt = {}, { n = 0 }, nil
for i = 1, 5 do VOICE.note("PROBLEM " .. i, "something " .. i, C.warn) end
CHECK(#VOICE.queue == 0 and VOICE.pending.n == 5, "5 warnings: none said at once (" .. VOICE.pending.n .. " collected)")
VOICE.tick()
CHECK(not said():find("new warning", 1, true), "not summed up before 15 minutes: " .. said())
VOICE.queue = {}
CLOCK = CLOCK + 901
VOICE.tick()
CHECK(said():find("5 new warnings on the screen", 1, true) and VOICE.pending.n == 0, "after 15 min: one line for all of them: " .. said())
VOICE.queue, VOICE.noteAt, VOICE.noteSeen = {}, nil, {}
VOICE.note("BROKEN", "something broke", C.bad)
VOICE.note("BROKEN TOO", "something else broke", C.bad)
CHECK(#VOICE.queue == 1, "errors are said, but 2 minutes apart (" .. #VOICE.queue .. ")")
VOICE.queue = {}

-- 13. MORE INTERACTIONS: games, notes, reminders, quiet, 8 ball, roast, story, where am I
told = {}
chatTell = function(name, text) told[#told + 1] = text end
local function ask(msg) told = {} VOICE.chat({ name = owner, msg = msg }) return told[#told] or "" end
local fc = ask("base flip a coin")
CHECK(fc:find("heads", 1, true) or fc:find("tails", 1, true), "flip a coin: " .. fc)
CHECK(ask("base roll a dice"):find("rolled", 1, true), "roll a dice")
CHECK(ask("base guess my number"):find("1 to 100", 1, true), "guess my number starts a game")
local g = VOICE.games[owner:lower()]
local guess = ask(tostring(g.n > 50 and 10 or 90))
CHECK(guess == "Higher." or guess == "Lower.", "a guess without the name gets higher / lower: " .. guess)
CHECK(ask(tostring(g.n)):find("You got it", 1, true), "the right number wins")
CHECK(ask("base rock paper scissors"):find("Rock, paper or scissors", 1, true), "rock paper scissors starts")
CHECK(ask("rock"):find("I pick", 1, true), "rock -> it picks one and says who won")
local qz = ask("base quiz")
CHECK(qz:find("Quiz time", 1, true), "quiz asks a question: " .. qz)
local Q = VOICE.games[owner:lower()]
CHECK(ask("lol") == "", "normal chat during a quiz is not an answer")
CHECK(ask("base, status?"):find("working", 1, true), "a question to the base during a quiz is answered, not marked wrong")
CHECK(ask("that was a fun day") == "", "a longer sentence during a quiz is not a wrong answer")
CHECK(ask(Q.a[1]):find("point", 1, true), "the right answer scores a point")
CHECK(ask("base my score"):find(owner:lower(), 1, true), "the quiz points list")
CHECK(ask("base magic 8 ball will i find diamonds") ~= "", "the magic 8 ball answers")
CHECK(ask("base roast me"):find(owner, 1, true), "roast me")
CHECK(ask("base compliment me"):find(owner, 1, true), "compliment me")
CHECK(ask("base tell me a story"):find("The end", 1, true), "a story")
CHECK(ask("base remember buy diamonds"):find("buy diamonds", 1, true), "remember something")
CHECK(ask("base my notes"):find("buy diamonds", 1, true) and VOICE.mem()[owner:lower()].notes, "my notes (kept on the floppy)")
CHECK(ask("base remind me in 2 minutes to check the furnace"):find("2 m", 1, true) or #VOICE.timers == 1, "a reminder is set")
CLOCK = CLOCK + 121
told = {}
VOICE.tick()
CHECK(told[1] and told[1]:find("check the furnace", 1, true), "the reminder comes after 2 minutes: " .. tostring(told[1]))
CHECK(ask("base shh"):find("quiet", 1, true) and VOICE.isQuiet(), "shh -> quiet for a while")
VOICE.queue, VOICE.convo, VOICE.pend = {}, {}, {}
CLOCK = CLOCK + 60
place("Steve", 10)
ENV.data.ents = { { kind = "player", name = owner, dist = 2 }, { kind = "player", name = "Steve", dist = 3 } }
CHECK(not VOICE.chat({ name = owner, msg = "hello all" }), "quiet: no reactions")
place("Steve", 9000)
ENV.data.ents = { { kind = "player", name = owner, dist = 2 } }
CHECK(ask("base talk to me") ~= "" and not VOICE.isQuiet(), "talk to me -> talking again")
CHECK(ask("base where am i"):find("You are at", 1, true), "where am I")
CHECK(ask("base say hello world") == "hello world", "say <text> (owner)")

-- 14. FASTER SCANS: the Environment Detector looks every 2 s (its cooldown), the add-on checks every 1 s
local scans = 0
ENV.scan = function() scans = scans + 1 ENV.scanAt = os.clock() end
ENV.scanAt = -100
for _ = 1, 10 do CLOCK = CLOCK + 1 VOICE.tick() end
CHECK(scans >= 5 and scans <= 6, "10 s: the detector looked about every 2 s (" .. scans .. " scans)")
local vsrc = io.open(SRC_DIR .. "/voice_addon.lua"):read("a")
CHECK(vsrc:find('waitFor(1, "voice_say")', 1, true), "the add-on checks every second")
ENV.scan = function() end

-- 15. THE LONELY BASE: the owner gone 7+ days -> a stranger finds a lonely old computer; the owner's
--     message for visitors; visitors leave messages; the owner hears who came when back
VOICE.queue, VOICE.near, VOICE.greeted, told = {}, {}, {}, {}
chatTell = function(name, text) told[#told + 1] = text end
local B = VOICE.base()
state.online = { [owner:lower()] = true }
VOICE.ownerWasOn = nil
VOICE.tick()
CHECK(B.ownerSeen and not VOICE.lonelyDays(), "the owner online: seen, not lonely")
told = {}
VOICE.chat({ name = owner, msg = "base, leave a message gone fishing, back soon" })
CHECK(B.ownerMsg == "gone fishing back soon", "the owner leaves a message for visitors: " .. tostring(B.ownerMsg))
-- the owner logs off ... 23 days pass
state.online = {}
ENV.data.ents = {}
VOICE.tick()
CHECK(B.lastOff ~= nil, "the owner went offline: noted")
B.lastOff = os.epoch("utc") - 23 * 86400000
B.ownerSeen = B.lastOff
B.ovN = (MAP.ovN or 0) - 500
CHECK(VOICE.lonelyDays() == 23, "23 days later: LONELY (" .. tostring(VOICE.lonelyDays()) .. ")")
-- a stranger stumbles in
state.online = { ["alex"] = true }
place("Alex", 5)
ENV.data.ents = { { kind = "player", name = "Alex", dist = 4, hp = 20, max = 20 } }
VOICE.queue = {}
CLOCK = CLOCK + 2
VOICE.tick()
CHECK(said():find("A visitor! I have not seen anyone in 23 days", 1, true), "the stranger meets a lonely computer: " .. said())
CHECK(said():find("gone fishing back soon", 1, true), "... and hears the owner's message")
CHECK(said():find("500 more chunks", 1, true), "... and what it did while alone")
CHECK(B.visitors.alex and B.visitors.alex.n == 1, "the visitor is noted for the owner")
local function askAs(who, msg) told = {} VOICE.chat({ name = who, msg = msg }) return told[#told] or "" end
CHECK(askAs("Alex", "base who lives here"):find(owner .. "'s base", 1, true), "who lives here -> the owner, last seen: " .. told[1])
CHECK(askAs("Alex", "base are you lonely"):find("23 days", 1, true) or told[1]:find("Lonely", 1, true), "are you lonely: " .. tostring(told[1]))
CHECK(askAs("Alex", "base leave a message nice base, I left you some bread"):find("give your message", 1, true) and #B.msgs == 1, "a visitor leaves a message")
CHECK(askAs("Alex", "base where is turtle 63"):find("secret", 1, true), "strangers never learn where the turtles are")
-- the owner comes back: who came + messages
VOICE.queue = {}
state.online = { [owner:lower()] = true }
ENV.data.ents = { { kind = "player", name = owner, dist = 2, hp = 20, max = 20 } }
VOICE.greeted = {}
CLOCK = CLOCK + 2
VOICE.tick()
CHECK(said():find("While you were away, 1 visitor came: Alex", 1, true) and said():find("1 message for you", 1, true),
      "the owner is told who came and that there are messages: " .. said())
CHECK(askAs(owner, "base messages"):find("Alex", 1, true) and told[1]:find("bread", 1, true), "base, messages -> the visitor's message")
CHECK(askAs(owner, "base clear messages"):find("gone", 1, true) and #B.msgs == 0, "clear messages")
CHECK(not VOICE.lonelyDays(), "the owner is back: not lonely any more")

-- 16. REAL PLAYERS (the owner: "they never use the words you expect, they misspell, and they have never
--     seen this computer"): typos, chat shorthand, no name, numbers from a menu, yes / no, two-step message
VOICE.convo, VOICE.pend, VOICE.games = {}, {}, {}
local stranger = "Kevin"
state.online = { ["kevin"] = true }                     -- (the owner offline 23+ days: lonely mode)
B.lastOff = os.epoch("utc") - 23 * 86400000
place("Kevin", 3)
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3, hp = 20, max = 20 } }
local function say2(msg) told = {} VOICE.queue = {} VOICE.chat({ name = stranger, msg = msg }) return told[#told] or "" end
-- never heard of "base": a plain question, alone with the computer, is answered
CHECK(say2("hello?? who r u"):find("I am", 1, true), "'hello?? who r u' (no name) -> who it is: " .. told[1])
-- in the conversation now: misspelled, no name, no question mark
CHECK(isJoke(say2("tell me a joek pls")), "'tell me a joek pls' -> a joke: " .. tostring(told[1]))
CHECK(say2("wat is this place"):find("base", 1, true), "'wat is this place' -> the tour: " .. told[1])
CHECK(say2("yeah"):find(owner .. "'s base", 1, true), "the tour asks 'want to know who lives here?' - 'yeah' -> the answer: " .. told[1])
-- not understood: it says so and gives a numbered list
local m1 = say2("uhh how do i blorp the zorp")
CHECK(m1:find("1:", 1, true) and m1:find("2:", 1, true), "'uhh how do i blorp the zorp' (not known) -> sorry + a numbered menu: " .. m1)
CHECK(said():find("number", 1, true), "... spoken: type a number")
-- a number from the menu
CHECK(say2("1"):find(owner .. "'s base", 1, true), "typing 1 -> the first choice (who lives here): " .. told[1])
-- a two-step message
CHECK(say2("can i leave a mesage for the owner"):find("What should the message say", 1, true), "a message without text -> it asks what to say: " .. told[1])
CHECK(say2("Nice place! I left some bread in the chest :)"):find("give your message", 1, true), "the next line is the message")
CHECK(B.msgs[#B.msgs] and B.msgs[#B.msgs].text:find("bread", 1, true), "... saved for the owner: " .. tostring(B.msgs[#B.msgs] and B.msgs[#B.msgs].text))
-- more sloppy ways to say things
CHECK(say2("lets play a gaem"):find("Which game", 1, true), "'lets play a gaem' -> the game menu")
CHECK(say2("2"):find("Rock, paper or scissors", 1, true), "2 -> rock paper scissors")
CHECK(say2("sisors"):find("I pick", 1, true), "'sisors' (misspelled) still plays: " .. told[1])
CHECK(say2("whos the owner of this place"):find(owner, 1, true), "'whos the owner of this place' -> the owner: " .. told[1])
CHECK(say2("hows the wether"):find("weather", 1, true), "'hows the wether' -> the weather: " .. told[1])
CHECK(say2("is there any tresure here") ~= "", "'is there any tresure here' -> answered: " .. told[1])
CHECK(say2("bye!"):find("Bye", 1, true) or told[1]:find("See you", 1, true), "bye -> goodbye")
-- chat that is NOT for the base (two players talking) gets no menu
place("Steve", 4)
state.online["steve"] = true
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3 }, { kind = "player", name = "Steve", dist = 4 } }
VOICE.convo, VOICE.pend = {}, {}
CHECK(say2("dude look at this cool build") == "", "two players chatting: nothing in chat, no menu")
CHECK(say2("hey computer, what time is it") ~= "", "... but 'computer' / a question is answered")
place("Steve", 9000)
ENV.scan = okScan
chatTell = oldTell
envDet = realEnvDet
http = nil
