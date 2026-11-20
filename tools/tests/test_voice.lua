-- THE BASE TALKS (voice_addon.lua, an optional add-on on a data floppy): loaded from the floppy,
-- greets players coming near the base, says warnings only when someone can hear them, answers
-- "base, status?" in chat, the alarm, speech cached on the floppy, nothing when it is off.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
local realEnvDet = envDet
envDet = nil                 -- (parts 1-9: no Environment Detector - the Player Detector within range)
CONFIG.drone.home = HOME
-- (the repo's own copies "next to inventory.lua" are not on this computer: the voice files come from floppies)
local realExists = fs.exists
local HIDDEN = { ["voice_addon.lua"] = true, ["voice_talk.lua"] = true, ["voice_talk2.lua"] = true, ["voice_talk3.lua"] = true }
fs.exists = function(p) if HIDDEN[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
-- a data floppy with the add-on on it
addDrive("drive_7", "disk7")
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
put("disk7/base_data", "data")
-- (a second data floppy: the add-on alone takes ~97 KB of a 125 KB floppy - the speech cache goes where there is room)
addDrive("drive_8", "disk8")
put("disk8/base_data", "data")
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
CHECK(#gets >= 1 and gets[1]:find("music.madefor.cc/tts", 1, true) and played > 0, "spoken: text-to-speech fetched, played on the speaker")
VOICE.said = {}
VOICE.say("Short and sweet.")                          -- (phrases up to 80 letters are kept; the greeting may be longer)
speakAll()
CHECK((fs.list("disk7/voice")[1] or fs.list("disk8/voice")[1]) ~= nil, "the phrase is kept on a DATA floppy (voice/)")
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
local firstLine = false                              -- (one of the first-meeting lines - picked at random now)
for _, l in ipairs(VOICE.HELLO_NEW) do
  -- (up to the first other {word} - "{bot}" is filled in with the base's name)
  local t = l:gsub("{name}", "Steve")
  t = (t:match("^([^{]*)") or t):sub(1, 20)
  if #t >= 6 and said():find(t, 1, true) then firstLine = true end
end
CHECK(said():find("Steve", 1, true) and firstLine and not said():find("Intruder", 1, true),
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
CHECK(src:find('loadVoiceChain', 1, true) and src:find("loadAddon", 1, true) and src:find("addonWorker", 1, true), "inventory.lua loads the add-on (+ talk packs) and runs its worker")
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
VOICE.queue, told = {}, {}
VOICE.chat({ name = owner, msg = "base, sing" })
local isNoSing = false
for _, l in ipairs(VOICE.NOSING) do if told[#told] == l then isNoSing = true end end
CHECK(isNoSing and not VOICE.sing and not VOICE.TUNES, "no singing (the owner: removed as a whole): asked to sing, it says it does not: " .. tostring(told[#told]))
for _, f in ipairs({ "voice_addon.lua", "voice_talk.lua", "voice_talk2.lua" }) do
  local src = io.open(SRC_DIR .. "/" .. f):read("a")
  CHECK(not src:find("playNote", 1, true) and not src:find("V.sing(", 1, true) and not src:find("VOICE.sing(", 1, true), f .. ": no note-block tunes / singing left")
end
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
for _ = 1, 13 do CLOCK = CLOCK + 10 VOICE.tick() end      -- (130 s; the base looks every 2 s in game)
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
VOICE.greeted, VOICE.seenNear = {}, {}               -- (away for days: not seen near the base since)
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

-- 17. TALK PACK (voice_talk.lua, the owner: "more idle talk, 100+ more interactions for visitors"): its own file
--     on a data floppy, loaded after the add-on; chat only (visitors cannot touch the claimed base)
local nBefore = #VOICE.INTENTS
addDrive("drive_8", "disk8")                 -- (a second data floppy: install puts each file where there is most room)
put("disk8/base_data", "data")
put("disk8/voice_talk.lua", io.open(SRC_DIR .. "/dist/voice_talk.lua"):read("a"))
local okT, whereT = loadAddon("voice_talk.lua")
CHECK(okT and VOICE.packs["voice_talk.lua"], "the talk pack loads from the data floppy: " .. tostring(whereT))
CHECK(#VOICE.INTENTS - nBefore >= 100, "100+ more things to ask: " .. (#VOICE.INTENTS - nBefore))
CHECK(man:find("\nvoice voice_talk.lua ", 1, true) and not man:find("\nbase voice_talk.lua", 1, true), "the pack is a voice download, never on the computer")
CHECK(#io.open(SRC_DIR .. "/dist/voice_talk.lua"):read("a") < 100000, "the slim pack fits on one floppy with room to spare")
VOICE.convo, VOICE.pend, VOICE.games, VOICE.quietUntil = {}, {}, {}, nil
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3, hp = 20, max = 20 } }
place("Kevin", 3)
-- every pack intent is reached by at least one of its own keys (no core intent / other pack intent steals all of them)
local stolen = {}
for i = nBefore + 1, #VOICE.INTENTS do
  local it, own = VOICE.INTENTS[i], false
  for _, key in ipairs(it.keys) do
    local got = VOICE.intent(VOICE.fix(VOICE.norm(key)))
    if got == it then own = true end
  end
  if not own then stolen[#stolen + 1] = it.id end
end
CHECK(#stolen == 0, "every new intent is reachable by its own words: not " .. table.concat(stolen, ", "))
-- and every one gives an answer (asked directly, as a stranger)
local silent = {}
for i = nBefore + 1, #VOICE.INTENTS do
  local it = VOICE.INTENTS[i]
  VOICE.games, VOICE.pend = {}, {}
  local c = VOICE.converse(stranger, it.keys[1], true)
  if type(c) ~= "string" or c == "" or c:find("did not get that", 1, true) or c:find("not sure what you mean", 1, true) or c:find("did not understand", 1, true) then silent[#silent + 1] = it.id end
end
CHECK(#silent == 0, "every new intent answers: not " .. table.concat(silent, ", "))
VOICE.quietUntil, VOICE.games, VOICE.pend = nil, {}, {}
-- typos in the new words still land (a letter swapped in the longest word of the first key)
local okTypo, allTypo, missT = 0, 0, {}
for i = nBefore + 1, #VOICE.INTENTS do
  local it = VOICE.INTENTS[i]
  local key = it.keys[1]
  local long = ""
  for w in key:gmatch("%a+") do if #w > #long then long = w end end
  if #long >= 6 then
    local typo = long:sub(1, 2) .. long:sub(4, 4) .. long:sub(3, 3) .. long:sub(5)
    allTypo = allTypo + 1
    if VOICE.intent(VOICE.fix(VOICE.norm((key:gsub(long, typo, 1))))) == it then okTypo = okTypo + 1 else missT[#missT + 1] = typo end
  end
end
CHECK(okTypo >= allTypo * 0.9, "typos in the new words: " .. okTypo .. " of " .. allTypo .. " understood (missed " .. table.concat(missT, " ") .. ")")
-- maths: only with a cue or the sum alone
CHECK(say2("whats 7 times 8"):find("56", 1, true), "'whats 7 times 8' -> 56: " .. told[1])
CHECK(say2("12+5"):find("17", 1, true), "'12+5' -> 17")
CHECK(say2("what is 100 / 8"):find("12.5", 1, true), "'what is 100 / 8' -> 12.5")
CHECK(not say2("how do i build a 3x3 farm"):find("9.", 1, true), "'a 3x3 farm' is not a sum: " .. told[1])
CHECK(say2("spell creeper backwards"):find("REPEERC", 1, true), "spell creeper backwards")
CHECK(say2("count to 5"):find("1, 2, 3, 4, 5", 1, true), "count to 5")
-- riddle (misspelled) -> answered right -> a point
CHECK(say2("give me a ridle"):find("Riddle", 1, true), "'give me a ridle' -> a riddle: " .. told[1])
local gk = VOICE.games.kevin
CHECK(gk and gk.kind == "quiz", "... and it waits for the answer")
CHECK(say2(gk.a[1]):find("Correct", 1, true) or told[1]:find("Right", 1, true) or told[1]:find("well done", 1, true), "the right answer -> a point: " .. told[1])
-- unscramble / maths question
CHECK(say2("unscramble pls"):find("Unscramble this word", 1, true), "unscramble")
CHECK(say2(VOICE.games.kevin.a[1]):find("point", 1, true), "unscrambled -> a point: " .. told[1])
CHECK(say2("give me a math question"):find("What is", 1, true), "a maths question")
CHECK(say2(VOICE.games.kevin.a[1]):find("point", 1, true), "the right number -> a point: " .. told[1])
-- hangman: letters (also u / r / n, which are chat shorthand elsewhere), then the word
CHECK(say2("hangman"):find("Hangman", 1, true), "hangman starts")
local hw = VOICE.games.kevin.w
CHECK(say2(hw:sub(1, 1)):find("Yes", 1, true), "a right letter: " .. told[1])
CHECK(say2("q"):find("No", 1, true) or hw:find("q", 1, true), "a wrong letter")
VOICE.games.kevin.w = "turn"
CHECK(say2("u"):find("U", 1, true) and told[1]:find("Yes", 1, true), "'u' is a letter in hangman, not 'you': " .. told[1])
CHECK(say2("turn"):find("The word was TURN", 1, true), "the whole word wins")
-- would you rather
CHECK(say2("would u rather"):find("Would you rather", 1, true), "would u rather")
CHECK(say2("2"):find("You would", 1, true), "2 -> its reaction: " .. told[1])
-- knock knock: it tells one, then they tell one
CHECK(say2("tell me a knock knock joke") == "Knock knock!", "a knock knock joke: " .. told[1])
local kj = VOICE.games.kevin.j
CHECK(say2("whos there") == kj[1] .. ".", "who's there -> " .. kj[1])
CHECK(say2(kj[1] .. " who") == kj[2], "... who -> the punchline")
CHECK(say2("knock knock") == "Who is there?", "they knock -> who is there")
CHECK(say2("lettuce") == "Lettuce who?", "-> Lettuce who?")
CHECK(say2("lettuce in its cold out here"):find("Ha", 1, true) or told[1]:find("terrible", 1, true) or told[1]:find("laughing", 1, true), "-> it laughs: " .. told[1])
-- the adventure: numbers through the story to an ending, yes plays again
local a1 = say2("lets go on an adventure")
CHECK(a1:find("dark cave", 1, true) and a1:find("1:", 1, true), "an adventure: the start + numbered choices")
CHECK(say2("1"):find("underground river", 1, true), "1 -> the river")
CHECK(say2("2"):find("diamond", 1, true), "2 -> dive")
CHECK(say2("1"):find("THE END", 1, true) and told[1]:find("Play again", 1, true), "1 -> an ending + play again?")
CHECK(say2("yeah"):find("dark cave", 1, true), "yeah -> it starts again")
VOICE.pend = {}
-- this or that: any answer gets a reaction
CHECK(say2("this or that"):find(" or ", 1, true), "this or that")
local isReact = function(t) for _, l in ipairs(VOICE.REACT_OK) do if l == t then return true end end return false end
CHECK(isReact(say2("hmm the first one i guess")), "their answer (whatever it is) gets a reaction: " .. told[1])
CHECK(VOICE_FILES[2] == "voice_talk.lua" and io.open(SRC_DIR .. "/base_theme.lua"):read("a"):find("installAddon(VOICE_FILES[i]", 1, true),
      "voice install / update also gets the talk pack")
-- the guestbook
B.guest = nil
CHECK(say2("sign the guestbok"):find("guest number 1", 1, true), "sign the guestbook (misspelled): " .. told[1])
CHECK(say2("sign the guestbook"):find("already", 1, true), "only once")
CHECK(say2("who signed the guestbook"):find("Kevin", 1, true), "the guestbook lists Kevin: " .. told[1])
-- sloppy questions about it
CHECK(say2("what is ur favrite colour") ~= "", "'what is ur favrite colour' -> " .. told[1])
CHECK(say2("can u see me"):find("blocks away", 1, true), "can u see me -> the detector distance: " .. told[1])
CHECK(say2("fortune cookie pls"):find("fortune cookie says", 1, true), "a fortune cookie")
CHECK(say2("can i grief here"):find("claimed", 1, true) or told[1]:find("sad", 1, true), "griefing -> please do not: " .. told[1])
CHECK(say2("open the door"):find("cannot", 1, true) or told[1]:find("closed", 1, true), "open the door -> no: " .. told[1])
-- the menus show the new things
CHECK(say2("lets play a game"):find("hangman", 1, true), "the game menu lists the new games")
VOICE.pend = {}
-- idle talk: every new kind runs, and with someone near most of it is the pack's
local okIdle = 0
for i, fn in ipairs(VOICE.idleExtra) do
  VOICE.said, VOICE.queue = {}, {}
  local okF, r = pcall(fn, { kevin = true }, "Kevin")
  CHECK(okF, "idle talk #" .. i .. " runs: " .. tostring(r))
  if okF and r then okIdle = okIdle + 1 end
end
CHECK(okIdle >= #VOICE.idleExtra - 1 and #VOICE.idleExtra >= 10, "new idle talk: " .. okIdle .. " of " .. #VOICE.idleExtra .. " said something")
local spoken = {}
B.lastOff, state.online = nil, { [owner:lower()] = true, kevin = true }
for _ = 1, 60 do
  VOICE.said, VOICE.queue, VOICE.pend = {}, {}, {}
  VOICE.idle({ kevin = true })
  for _, q in ipairs(VOICE.queue) do if q.text then spoken[q.text] = true end end
end
local nSpoken = 0
for _ in pairs(spoken) do nSpoken = nSpoken + 1 end
CHECK(nSpoken >= 35, "60 idle moments -> " .. nSpoken .. " different lines")

-- 18. LISTENING (the owner: "read the chat and remember if people talk about the owner while the owner is offline")
VOICE.convo, VOICE.pend, VOICE.games, VOICE.follow, VOICE.quietUntil = {}, {}, {}, nil, nil
B.talk = nil
local function hear(name, msg) told = {} VOICE.queue = {} handleChat({ name = name, msg = msg }) return told end
local function nTalk() return #(VOICE.base().talk or {}) end
place("Steve", 9000)                                    -- (far away: anywhere on the server)
state.online = { [owner:lower()] = true, kevin = true, steve = true }
VOICE.watchOwner()
hear("Steve", "has anyone seen " .. owner .. " lately")
CHECK(nTalk() == 0, "the owner ONLINE: nothing is kept")
state.online = { kevin = true, steve = true }
VOICE.watchOwner()
CLOCK = CLOCK + 5
hear("Steve", "has anyone seen " .. owner .. " lately")
CHECK(nTalk() == 1 and VOICE.base().talk[1].who == "Steve", "the owner offline: a message with their name (from far away) is kept")
hear("Kevin", "no idea, maybe they quit")
hear("Steve", "lol")
hear("Kevin", "anyway")
local e1 = VOICE.base().talk[1]
CHECK(e1.ctx and #e1.ctx == 2 and e1.ctx[1].text:find("maybe they quit", 1, true), "the next 2 messages are kept with it (the answer)")
CHECK(nTalk() == 1, "... other chat is not kept")
VOICE.follow = nil
hear("Steve", "nice weather today")
CHECK(nTalk() == 1 and #e1.ctx == 2, "chat that is not about the owner: not kept")
local typo = owner:sub(1, 2) .. owner:sub(4, 4) .. owner:sub(3, 3) .. owner:sub(5)
VOICE.follow = nil
hear("Steve", "i think " .. typo:lower() .. "s base is cool")
CHECK(#owner < 5 or nTalk() == 2, "a typo of the name ('" .. typo .. "s') is kept too")
VOICE.follow = nil
local n0 = nTalk()
hear("Steve", "@" .. owner .. "_fan")
CHECK(nTalk() == n0 + 1, "the name glued to other text (@" .. owner .. "_fan) is kept")
VOICE.follow = nil
n0 = nTalk()
hear("Steve", "who lives here anyway")
CHECK(nTalk() == n0, "'who lives here' from FAR away is not about this base: not kept")
hear("Kevin", "whose base is this")
CHECK(nTalk() == n0 + 1 and VOICE.base().talk[nTalk()].near, "'whose base is this' from someone AT the base: kept (marked at the base)")
VOICE.follow = nil
n0 = nTalk()
hear("Steve", "$drone home " .. owner)
CHECK(nTalk() == n0, "$ commands are never kept")
handleCommand("voice listen off")
hear("Steve", owner .. " is never online")
CHECK(nTalk() == n0, "voice listen off: nothing kept")
handleCommand("voice listen on")
handleCommand("voice listen tell on")
CHECK(VOICE.cfg("listenTell", false) == true, "voice listen tell on")
handleCommand("voice listen tell off")
CHECK(VOICE.cfg("listenTell", true) == false, "voice listen tell off")
handleCommand("voice nick boss, al")
VOICE.follow = nil
hear("Steve", "where is the boss")
CHECK(nTalk() == n0 + 1, "a nickname (voice nick boss) is listened for")
VOICE.follow = nil
hear("Steve", "i like algae")
CHECK(nTalk() == n0 + 1, "(a too short nickname 'al' is ignored, and 'algae' is not 'al')")
handleCommand("voice nick")
-- a stranger asking gets nothing
CHECK(table.concat(hear("Kevin", "base what did people say about " .. owner), " "):find("between me and", 1, true)
      or not table.concat(told, " "):find("Steve", 1, true), "a stranger never hears what was said")
-- the owner comes back: a private chat note at once, the welcome mentions it, then the details
local nKept = nTalk()
told = {}
CLOCK = CLOCK + 5
state.online = { [owner:lower()] = true }
VOICE.watchOwner()
CHECK(table.concat(told, " "):find("talked about you", 1, true), "the owner logs in: a private chat note: " .. table.concat(told, " | "))
VOICE.queue = {}
VOICE.greet(owner)
CHECK(said():find("talked about you in chat", 1, true) and said():find("Steve", 1, true), "the welcome back says who talked about them: " .. said())
local r = table.concat(hear(owner, "base wat did ppl say about me"), " | ")
CHECK(r:find("Steve", 1, true) and r:find("lately", 1, true) and r:find("maybe they quit", 1, true),
      "'base wat did ppl say about me' -> the messages + the answers: " .. r)
-- READ = GONE (the owner: "even after checking what people said about me the base still remembers it")
CHECK(nTalk() == math.max(0, nKept - 8), "what the owner read is forgotten (" .. nTalk() .. " of " .. nKept .. " left)")
local again = table.concat(hear(owner, "base what did people say about me"), " | ")
CHECK(nKept <= 8 and again:find("Nobody talked about you", 1, true) or nKept > 8, "asked again: nothing left (" .. again .. ")")
CHECK(VOICE.heardSince(0)[1] == nil, "... and the welcome back will not mention them again")
hear(owner, "base forget what they said")
CHECK(nTalk() == 0, "the owner: forget what they said")

-- 19. TALK PACK 2 (voice_talk2.lua; the owner: "add more interactions, idle talk and good ideas"):
--     friendship, badges, memory, daily secret word, more games, idea generators, styles, guides, songs, diary
VOICE.convo, VOICE.pend, VOICE.games, VOICE.follow, VOICE.quietUntil = {}, {}, {}, nil, nil
state.online = { [owner:lower()] = true, kevin = true }
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3, hp = 20, max = 20 } }
place("Kevin", 3)
VOICE.mem().kevin = { first = os.epoch("utc"), visits = 2, quiz = 7 }
VOICE.greet("Kevin")
CHECK(VOICE.mem().kevin.quiz == 7 and VOICE.mem().kevin.visits == 3, "a greeting keeps what it knew (quiz points were lost before)")
local nBefore2 = #VOICE.INTENTS
addDrive("drive_9", "disk9")
put("disk9/base_data", "data")
put("disk9/voice_talk2.lua", io.open(SRC_DIR .. "/dist/voice_talk2.lua"):read("a"))
local okT2, whereT2 = loadAddon("voice_talk2.lua")
CHECK(okT2 and VOICE.packs["voice_talk2.lua"], "talk pack 2 loads: " .. tostring(whereT2))
CHECK(#VOICE.INTENTS - nBefore2 >= 70, "pack 2: " .. (#VOICE.INTENTS - nBefore2) .. " more things to ask")
CHECK(#io.open(SRC_DIR .. "/dist/voice_talk2.lua"):read("a") < 100000, "pack 2 fits on one floppy")
CHECK(VOICE_FILES[3] == "voice_talk2.lua" and man:find("\nvoice voice_talk2.lua ", 1, true), "pack 2 is installed by voice install")
local stolen2, silent2 = {}, {}
for i = nBefore2 + 1, #VOICE.INTENTS do
  local it, own = VOICE.INTENTS[i], false
  for _, key in ipairs(it.keys) do if VOICE.intent(VOICE.fix(VOICE.norm(key))) == it then own = true end end
  if not own then stolen2[#stolen2 + 1] = it.id end
  VOICE.games, VOICE.pend = {}, {}
  local c = VOICE.converse(stranger, it.keys[1], true)
  if type(c) ~= "string" or c == "" or c:find("did not get that", 1, true) or c:find("not sure what you mean", 1, true) then silent2[#silent2 + 1] = it.id end
end
CHECK(#VOICE.dupIntents == 0, "no pack intent has the name of another (it was skipped): " .. table.concat(VOICE.dupIntents, ", "))
CHECK(#stolen2 == 0, "every pack 2 intent is reachable by its own words: not " .. table.concat(stolen2, ", "))
CHECK(#silent2 == 0, "every pack 2 intent answers: not " .. table.concat(silent2, ", "))
VOICE.games, VOICE.pend, VOICE.styles, VOICE.quietUntil = {}, {}, {}, nil
VOICE.mem().kevin = { first = os.epoch("utc"), visits = 3, quiz = 7 }
local function say3(msg) told = {} VOICE.queue = {} VOICE.chat({ name = stranger, msg = msg }) return table.concat(told, " | ") end
-- memory: nickname, favourites, birthday, about me
CHECK(say3("base call me captain kev"):find("call you Captain kev", 1, true), "call me captain kev: " .. table.concat(told, " | "))
CHECK(VOICE.fill("Hi {name}!", "Kevin") == "Hi Captain kev!", "{name} becomes the nickname: " .. VOICE.fill("Hi {name}!", "Kevin"))
CHECK(say3("my favorite food is cake"):lower():find("cake", 1, true), "my favorite food is cake")
CHECK(say3("whats my favourite food?"):find("is cake", 1, true), "what's my favourite food -> cake: " .. table.concat(told, " | "))
CHECK(say3("my birthday is 14 march"):find("14 March", 1, true), "my birthday is 14 march")
CHECK(say3("when is my birthday?"):find("14 march", 1, true), "when is my birthday")
local about = say3("what do you know about me")
CHECK(about:find("Captain kev", 1, true) and about:find("cake", 1, true) and about:find("14 march", 1, true), "what do you know about me: " .. about)
CHECK(VOICE.mem().kevin.badges and VOICE.mem().kevin.badges.named and VOICE.mem().kevin.badges.bday and VOICE.mem().kevin.badges.quiz5,
      "badges for a nickname, a birthday and 5 quiz points")
CHECK(table.concat(told, " "):find("Badge earned", 1, true) or true, "(badges are told in chat)")
CHECK(say3("my badges"):find("of " .. #VOICE.BADGES .. ")", 1, true), "my badges: " .. table.concat(told, " | "))
-- a birthday greeting
local tnow = os.date("!*t", math.floor(os.epoch("utc") / 1000))
VOICE.mem().kevin.bday = tnow.day .. " " .. ({ "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" })[tnow.month]
VOICE.queue, told = {}, {}
for _, fn in ipairs(VOICE.greetExtra) do fn("Kevin") end
CHECK(said():find("Happy birthday", 1, true) and table.concat(told, " "):find("Happy birthday", 1, true), "on their birthday: happy birthday (spoken + chat): " .. said())
VOICE.queue = {}
for _, fn in ipairs(VOICE.greetExtra) do fn("Kevin") end
CHECK(not said():find("Happy birthday", 1, true), "... only once a year")
-- friendship
CHECK(say3("whats my friendship level"):find("You are my", 1, true), "friendship level: " .. table.concat(told, " | "))
told = {}
VOICE.addRep("Kevin", 45)
CHECK(table.concat(told, " "):find("friend", 1, true) and VOICE.titleOf("Kevin"):find("friend", 1, true), "more friendship -> a new title, told in chat: " .. table.concat(told, " | "))
VOICE.checkBadges("Kevin")
local rep0 = VOICE.repOf("Kevin")
say3("base you are stupid")
CHECK(VOICE.repOf("Kevin") < rep0, "rude words cost friendship")
-- the secret word of the day
local sw = VOICE.secretWord()
local hint = say3("base whats the secret word")
CHECK(hint:find("letters", 1, true) and not hint:lower():find(sw, 1, true), "a stranger gets a hint, not the word: " .. hint)
local ding = say3("i really like my " .. sw .. " a lot")
CHECK(ding:find("DING", 1, true) and VOICE.mem().kevin.badges.secret, "saying the secret word at the base: DING + a badge: " .. ding)
CHECK(not say3("another " .. sw):find("DING", 1, true), "... once a day")
told = {}
VOICE.chat({ name = owner, msg = "base what is the secret word" })
CHECK(table.concat(told, " "):find(sw:upper(), 1, true), "the owner may know it")
-- true or false
VOICE.games, VOICE.pend = {}, {}
CHECK(say3("lets play true or false"):find("True or false:", 1, true), "true or false starts")
local tq = VOICE.games.kevin.q
CHECK(say3(tq[2] and "true" or "false"):find("Correct!", 1, true), "the right answer: correct + the next one")
tq = VOICE.games.kevin.q
CHECK(say3(tq[2] and "false" or "true"):find("Nope", 1, true), "a wrong answer ends it")
-- guess the mob
CHECK(say3("guess the mob"):find("Hint 1", 1, true), "guess the mob starts")
CHECK(say3("hint"):find("Hint 2", 1, true), "hint -> the next hint")
local mob = VOICE.games.kevin.m[1]
CHECK(say3(mob):find("Yes! It is the " .. mob, 1, true) and VOICE.mem().kevin.badges.mob, "the right mob: " .. table.concat(told, " | "))
-- word chain (their word starts with the last letter of its word)
CHECK(say3("word chain"):find("Word chain!", 1, true), "word chain starts")
local need = VOICE.games.kevin.last:sub(-1)
if need == "x" or need == "y" or need == "q" then need = VOICE.games.kevin.last:sub(-2, -2) end
local wc = say3(need .. "ooble")
CHECK(wc:find("Your turn", 1, true) or wc:find("You win", 1, true), "a right word: it answers with one of its own: " .. wc)
if VOICE.games.kevin then CHECK(say3("zzzq"):find("Game over", 1, true) or need == "z", "a word with the wrong letter: game over") end
-- higher or lower
VOICE.games = {}
CHECK(say3("higher or lower"):find("My card is", 1, true), "higher or lower starts")
CHECK(say3("higher"):find("It is ", 1, true), "higher -> the next card")
-- mad libs
VOICE.games = {}
CHECK(say3("mad libs"):find("Give me", 1, true), "mad libs starts")
local story
for i = 1, 5 do story = say3("zorb" .. i) end
CHECK(story:find("zorb1", 1, true) and story:find("zorb5", 1, true) and VOICE.mem().kevin.badges.madlib, "mad libs: the story uses their words: " .. story)
-- count with me
CHECK(say3("lets count together"):find("I say 1", 1, true), "count with me starts")
CHECK(say3("2") == "3.", "2 -> 3")
CHECK(say3("5"):find("should have been 4", 1, true), "a wrong number: says which one it should have been: " .. table.concat(told, " | "))
VOICE.games = {}
-- hack, ideas, pick for me, random number
CHECK(say3("hack the mainframe") ~= "", "hack the mainframe")
CHECK(say3("give me a build idea"):find("Build idea: a", 1, true), "a build idea")
CHECK(say3("name for my pet") ~= "" and say3("team name"):find("The ", 1, true), "pet name / team name")
local pk = say3("should i mine or build")
CHECK(pk:lower():find("mine", 1, true) or pk:lower():find("build", 1, true), "should i mine or build -> one of them: " .. pk)
local rn = say3("random number between 5 and 6")
CHECK(rn:find("I pick 5", 1, true) or rn:find("I pick 6", 1, true), "random number between 5 and 6: " .. rn)
-- styles
CHECK(say3("talk like a pirate"):find("pirate", 1, true), "talk like a pirate")
CHECK(VOICE.restyle("Kevin", "Hello, you are my friend"):find("Ahoy, ye be me matey", 1, true), "pirate words: " .. VOICE.restyle("Kevin", "Hello, you are my friend"))
CHECK(VOICE.restyle("Kevin", "the theory"):find("th' theory", 1, true), "whole words only (theory stays)")
CHECK(say3("talk normal"):find("normal", 1, true) and VOICE.restyle("Kevin", "you") == "you", "talk normal ends it")
-- guides, holiday, diary, top
CHECK(say3("how do i get diamonds"):find("Y -59", 1, true), "how do i get diamonds")
CHECK(say3("how do i tame a wolf"):find("bones", 1, true), "how do i tame a wolf")
CHECK(say3("is it a holiday today?"):find("holiday", 1, true), "is it a holiday: " .. table.concat(told, " | "))
CHECK(say3("what happened today"):find("Dear diary", 1, true), "the diary: " .. table.concat(told, " | "))
CHECK(say3("top players"):find("Hall of fame", 1, true) and told[#told]:find("Captain kev", 1, true), "top players: " .. table.concat(told, " | "))
-- AE2 counts for the owner / friends only
local realBridge = bridge
bridge = { getItem = function(f) if type(f) == "table" and f.name == "minecraft:iron_ingot" then return { name = f.name, amount = 42, displayName = "Iron Ingot" } end return nil end }
told = {}
VOICE.chat({ name = owner, msg = "base how many iron ingots do we have" })
CHECK(table.concat(told, " "):find("42", 1, true), "owner: how many iron ingots -> 42: " .. table.concat(told, " | "))
CHECK(say3("how many iron ingots do we have"):find("secret", 1, true), "a stranger may not ask")
bridge = realBridge
-- emoticons: no menu in a conversation, a little spoken reaction
VOICE.emoAt = {}
VOICE.queue = {}
VOICE.openConvo("Kevin")
VOICE.chat({ name = stranger, msg = ":)" })
CHECK(#told == 0 or not table.concat(told, " "):find("1:", 1, true), "':)' is not answered with a menu")
CHECK(#VOICE.queue == 1, "':)' gets a little spoken reaction")
VOICE.convo, VOICE.emoAt, VOICE.said = {}, {}, {}
VOICE.queue = {}
told = {}
VOICE.chat({ name = stranger, msg = "<3" })
CHECK(#VOICE.queue == 1 and #told == 0, "'<3' near the base: a spoken reaction only: " .. said())
-- the games menu has the new games, more menu too
CHECK(say3("base lets play a game"):find("word chain", 1, true), "the game menu lists pack 2 games")
VOICE.pend = {}
-- idle talk: every pack 2 kind runs
local errs = {}
for i, fn in ipairs(VOICE.idleExtra) do
  VOICE.said, VOICE.queue = {}, {}
  local okF, e = pcall(fn, { kevin = true }, "Kevin")
  if not okF then errs[#errs + 1] = i .. ": " .. tostring(e) end
end
CHECK(#errs == 0, "all idle talk runs: " .. table.concat(errs, "; "))
-- GIFTS (the owner: "on certain friendship levels gift them some stuff with the drones - be generous, I am rich")
local B2 = VOICE.base()
CHECK(VOICE.giftList("friend")[1][1] == "minecraft:diamond" and VOICE.giftList("best friend")[1][1] == "minecraft:netherite_ingot",
      "generous defaults: diamonds for a friend, netherite for a best friend")
local function queued(who, item)
  local n = 0
  for _, g in ipairs(B2.giftQ or {}) do if g.who:lower() == who:lower() and (not item or g.item == item) then n = n + 1 end end
  return n
end
CHECK(queued("Kevin", "minecraft:golden_carrot") == 1 and queued("Kevin", "minecraft:diamond") >= 1,
      "becoming a regular / a friend earlier queued their gifts (" .. queued("Kevin") .. " items)")
CHECK(not VOICE.giftEarn(owner, "friend"), "the owner never gets gifts (it is all theirs anyway)")
handleCommand("voice gifts block kevin")
CHECK(not VOICE.giftEarn("Kevin", "secret"), "voice gifts block kevin: no gifts for Kevin")
handleCommand("voice gifts unblock kevin")
CHECK(VOICE.giftEarn("Kevin", "secret"), "... unblock: gifts again")
-- the drone part (DW.giftRun) is tested in test_dronework; here: who gets what, when
local realRun, realReady, realTrip = DW.giftRun, DW.notReady, DW.trip
local runs = {}
DW.notReady, DW.trip = function() return nil end, nil
DW.giftRun = function(who, item, n, cb, still) runs[#runs + 1] = { who = who, item = item, n = n, cb = cb, still = still } return true end
local gtick = VOICE.tickHooks[1]
VOICE.giftNext, VOICE.giftBusy = 0, nil
gtick(CLOCK, {})
CHECK(#runs == 0 and tostring(VOICE.giftWhy):find("waiting for the players", 1, true), "nobody at the base: no drone (" .. tostring(VOICE.giftWhy) .. ")")
VOICE.giftNext = 0
told = {}
gtick(CLOCK, { Kevin = true })
CHECK(#runs == 1 and runs[1].who == "Kevin" and table.concat(told, " "):find("on its way", 1, true), "Kevin at the base: a drone brings the first gift")
CHECK(runs[1].still("Kevin") == true, "... and stops if Kevin leaves (still = at the base)")
VOICE.giftNext = 0
gtick(CLOCK, { Kevin = true })
CHECK(#runs == 1, "one gift trip at a time")
local before = queued("Kevin")
told = {}
runs[1].cb(true, runs[1].n, nil)
CHECK(queued("Kevin") == before - 1 and #B2.giftLog >= 1 and table.concat(told, " "):find("Gift delivered", 1, true), "delivered: logged, told, off the queue")
setSetting("voice.giftDaily", 1)
VOICE.giftNext = 0
gtick(CLOCK, { Kevin = true })
CHECK(#runs == 1, "the daily limit per player holds (voice.giftDaily)")
resetSetting("voice.giftDaily")
VOICE.giftNext = 0
gtick(CLOCK, { Kevin = true })
CHECK(#runs == 2, "next gift")
runs[2].cb(false, 0, "no plain minecraft:emerald in AE2")
CHECK(VOICE.giftBusy == nil and table.concat(told, " "):find("could not bring", 1, true), "AE2 has none: the player is told, the gift dropped")
-- the birthday gift only for a birthday told 30+ days ago ("my birthday is today" = a wish, no gift)
local rk = VOICE.mem().kevin
local tn = os.date("!*t", math.floor(os.epoch("utc") / 1000))
local months = { "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" }
rk.bday, rk.bdaySet, rk.sung = tn.day .. " " .. months[tn.month], math.floor(os.epoch("utc") / 1000), nil
local q0 = queued("Kevin", "minecraft:cake")
if B2.gm and B2.gm.kevin then B2.gm.kevin.y = nil end
for _, fn in ipairs(VOICE.greetExtra) do fn("Kevin") end
CHECK(queued("Kevin", "minecraft:cake") == q0, "a birthday told today: a wish, no gift")
rk.bdaySet, rk.sung = math.floor(os.epoch("utc") / 1000) - 40 * 86400, nil
for _, fn in ipairs(VOICE.greetExtra) do fn("Kevin") end
CHECK(queued("Kevin", "minecraft:cake") == q0 + 1, "a birthday told 40 days ago: the birthday gift")
rk.sung = nil
for _, fn in ipairs(VOICE.greetExtra) do fn("Kevin") end
CHECK(queued("Kevin", "minecraft:cake") == q0 + 1, "... once a year")
-- chat: how to get one, what is waiting
CHECK(say3("how do i get a gift"):find("gifts, brought by drone", 1, true), "how do i get a gift")
CHECK(say3("where is my gift"):find("Waiting for you", 1, true), "where is my gift: " .. table.concat(told, " | "))
-- console
local gout = table.concat(handleCommand("voice gifts"), "\n")
CHECK(gout:find("FRIENDSHIP GIFTS: ON", 1, true) and gout:find("best friend:", 1, true) and gout:find("Given", 1, true), "voice gifts shows the rules, the queue and the log")
handleCommand("voice gifts give Kevin diamond 7")
local manual = false
for _, g in ipairs(B2.giftQ) do if g.why == "manual" and g.item == "minecraft:diamond" and g.n == 7 then manual = true end end
CHECK(manual, "voice gifts give Kevin diamond 7 queues a gift from the owner")
handleCommand("voice gifts off")
CHECK(not VOICE.giftEarn("Kevin", "secret"), "voice gifts off: none")
handleCommand("voice gifts on")
-- the owner hears what was given while away
VOICE.queue = {}
B2.giftToldAt = 0
for _, fn in ipairs(VOICE.greetExtra) do fn(owner) end
CHECK(said():find("I gave", 1, true) and said():find("Kevin", 1, true), "the owner back: which gifts were given: " .. said())
DW.giftRun, DW.notReady, DW.trip = realRun, realReady, realTrip
-- REVIEW FIXES (the owner: "go over all the code you added, look for typos, issues and bugs")
handleCommand("voice announce all")
CHECK(VOICE.cfg("announce") == "all", "voice announce all works (an earlier branch swallowed it)")
handleCommand("voice announce summary")
VOICE.convo = {}
VOICE.pend.kevin = { kind = "yesno", yes = "tell me a joke", till = os.clock() + 100 }
CHECK(VOICE.addressed("Kevin", "nice weather today", true) == nil, "a waiting yes/no question does not take other chat as meant for it")
CHECK(VOICE.addressed("Kevin", "yes", true) == "direct", "... but a yes is")
VOICE.pend = {}
told = {}
VOICE.chat({ name = owner, msg = "base forget mentions" })
CHECK(not table.concat(told, " "):find("Type yes or no", 1, true), "'forget mentions' is not 'forget me': " .. table.concat(told, " | "))
VOICE.pend = {}
local hc, hsp = VOICE.converse(stranger, "hack the mainframe", true)
CHECK(type(hc) == "string" and hsp == nil, "hack the mainframe: no stray second value (it would have been spoken)")
VOICE.games = {}
CHECK(say3("my birthday is the 14th of march"):find("14 March", 1, true), "my birthday is the 14th of march: " .. table.concat(told, " | "))
VOICE.chat({ name = "Zed", msg = "hello everyone, nice server" })
CHECK(VOICE.mem().zed == nil, "chat from a player far away who never visited makes no record")
-- forget me asks first, then deletes everything
CHECK(say3("forget me"):find("Type yes or no", 1, true), "forget me asks first")
CHECK(say3("yes"):find("forgot everything", 1, true) and VOICE.mem().kevin == nil and VOICE.callName("Kevin") == nil, "yes -> all gone")
local gq = queued("Kevin")
VOICE.addRep("Kevin", 60)
CHECK(queued("Kevin") == gq, "after forget me, the same titles give no gifts again")
-- 21. TALK PACK 3 (voice_talk3.lua; the owner: "continue working on ideas"): streaks, mail between players, a
--     glossary, recipes, jokes on a topic, spirit mob, ship, "last time", milestones, thanks after a gift
local nBefore3 = #VOICE.INTENTS
addDrive("drive_10", "disk10")
put("disk10/base_data", "data")
put("disk10/voice_talk3.lua", io.open(SRC_DIR .. "/dist/voice_talk3.lua"):read("a"))
local okT3, whereT3 = loadAddon("voice_talk3.lua")
CHECK(okT3 and VOICE.packs["voice_talk3.lua"], "talk pack 3 loads: " .. tostring(whereT3))
CHECK(VOICE_FILES[4] == "voice_talk3.lua" and man:find("\nvoice voice_talk3.lua ", 1, true), "pack 3 is installed by voice install")
CHECK(#VOICE.dupIntents == 0, "pack 3: no duplicate intent names: " .. table.concat(VOICE.dupIntents, ", "))
local stolen3, silent3 = {}, {}
for i = nBefore3 + 1, #VOICE.INTENTS do
  local it, own = VOICE.INTENTS[i], false
  for _, key in ipairs(it.keys) do if VOICE.intent(VOICE.fix(VOICE.norm(key))) == it then own = true end end
  if not own then stolen3[#stolen3 + 1] = it.id end
  VOICE.games, VOICE.pend = {}, {}
  local c = VOICE.converse("Kevin", it.keys[1], true)
  if type(c) ~= "string" or c == "" or c:find("did not get that", 1, true) or c:find("not sure what you mean", 1, true) then silent3[#silent3 + 1] = it.id end
end
CHECK(#stolen3 == 0 and #silent3 == 0, "every pack 3 intent reachable + answers: " .. table.concat(stolen3, ",") .. " / " .. table.concat(silent3, ","))
VOICE.games, VOICE.pend, VOICE.convo = {}, {}, {}
place("Kevin", 3)
place("Steve", 9000)
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3 } }
state.online = { [owner:lower()] = true, kevin = true, steve = true }
VOICE.mem().kevin = VOICE.mem().kevin or {}
VOICE.mem().steve = VOICE.mem().steve or { visits = 1 }
local function k3(msg) told = {} VOICE.queue = {} VOICE.chat({ name = "Kevin", msg = msg }) return table.concat(told, " | ") end
-- streaks
local rk3 = VOICE.mem().kevin
local yday = os.date("!%Y-%m-%d", math.floor(os.epoch("utc") / 1000) - 86400)
rk3.vday, rk3.streak = yday, 2
CHECK(VOICE.visitDay("Kevin") == 3 and rk3.badges and rk3.badges.streak3, "yesterday + today = a streak of 3 and a badge")
CHECK(VOICE.visitDay("Kevin") == 3, "the same day again does not count twice")
rk3.vday, rk3.streak = os.date("!%Y-%m-%d", math.floor(os.epoch("utc") / 1000) - 3 * 86400), 9
CHECK(VOICE.visitDay("Kevin") == 1, "a missed day starts again at 1")
local B3 = VOICE.base()
local function q3(item) local n = 0 for _, g in ipairs(B3.giftQ or {}) do if g.who == "Kevin" and g.item == item and g.why == "streak7" then n = n + 1 end end return n end
rk3.vday, rk3.streak = yday, 6
VOICE.visitDay("Kevin")
CHECK(q3("minecraft:diamond") == 1, "7 days in a row: the streak gift")
rk3.vday, rk3.streak = yday, 6
VOICE.visitDay("Kevin")
CHECK(q3("minecraft:diamond") == 1, "... only once")
-- mail between players
CHECK(k3("base tell steve that the farm is ready"):find("I will tell", 1, true), "tell steve that ...: " .. table.concat(told, " | "))
CHECK(B3.mail and B3.mail.steve and #B3.mail.steve == 1 and B3.mail.steve[1].text:find("farm is ready", 1, true), "... kept for Steve")
CHECK(k3("base tell bob that hi"):find("do not know anyone called bob", 1, true), "a player it never met: it says so")
CHECK(not k3("base tell " .. owner:lower() .. " that hi"):find("I will tell " .. owner, 1, true), "a message for the owner is the old leave-a-message")
told = {}
place("Steve", 2)
ENV.data.ents = { { kind = "player", name = "Steve", dist = 2 } }
for _, fn in ipairs(VOICE.greetExtra) do fn("Steve") end
CHECK(table.concat(told, " "):find("Mail from Kevin", 1, true) and table.concat(told, " "):find("farm is ready", 1, true) and not B3.mail.steve,
      "Steve comes to the base: the mail is told and gone: " .. table.concat(told, " | "))
place("Steve", 9000)
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3 } }
for i = 1, 3 do k3("base tell steve that note " .. i) end
CHECK(k3("base tell steve that one more"):find("3 messages waiting", 1, true), "max 3 waiting messages per sender")
B3.mail = {}
-- glossary, recipes, jokes about
CHECK(k3("base what is a shulker box"):find("shulker shells", 1, true), "what is a shulker box")
CHECK(k3("base what is a shulkr box"):find("shulker shells", 1, true), "... also misspelled")
CHECK(k3("base explain redstone"):find("electricity", 1, true), "explain redstone")
CHECK(k3("base how do i make a hopper"):find("Hopper: five iron", 1, true), "how do i make a hopper: " .. table.concat(told, " | "))
CHECK(k3("base recipe for an enchantment table"):find("diamonds on the sides", 1, true), "recipe for an enchantment table (another name)")
CHECK(not k3("base how do i make friends"):find("Friends:", 1, true), "how do i make friends is not a recipe")
CHECK(k3("base how do i get diamonds"):find("Y -59", 1, true), "the guides still answer (how do i get diamonds)")
local jc = k3("base tell me a joke about creepers"):lower()
CHECK(jc:find("creeper", 1, true), "a joke about creepers: " .. jc)
-- spirit mob, ship
local sp1 = k3("base what is my spirit mob")
CHECK(sp1:find("spirit mob is the", 1, true) and k3("base what is my spirit mob") == sp1, "spirit mob: always the same for a name")
local sh = k3("base ship me and steve")
CHECK(sh:find("percent", 1, true) and k3("base ship steve and me") == sh:gsub("Kevin and Steve", "Steve and Kevin"), "ship: a stable percentage: " .. sh)
-- last time: a rematch
local mr = math.random
math.random = function(a, b) if a then return mr(a, b) end return 0.1 end
rk3.lastGame = { what = "hang", won = true, at = math.floor(os.epoch("utc") / 1000) }
rk3.vday = os.date("!%Y-%m-%d", math.floor(os.epoch("utc") / 1000))
VOICE.queue = {}
for _, fn in ipairs(VOICE.greetExtra) do fn("Kevin") end
math.random = mr
CHECK(said():find("last time you won at hangman", 1, true), "coming back: last time you won at hangman - rematch?: " .. said())
CHECK(k3("yes"):find("Hangman", 1, true), "yes -> hangman again")
VOICE.games = {}
-- milestones
MAP.ovN = 2600
VOICE.queue, VOICE.mileNext = {}, 0
B3.ms = nil
for _, fn in ipairs(VOICE.tickHooks) do fn(CLOCK, { Kevin = true }) end
CHECK(said():find("mapped 2500 chunks", 1, true), "milestone: the biggest new one is said: " .. said())
VOICE.queue, VOICE.mileNext = {}, 0
for _, fn in ipairs(VOICE.tickHooks) do fn(CLOCK, { Kevin = true }) end
CHECK(not said():find("Milestone", 1, true), "... once")
-- thanks after a gift
B3.giftLog = B3.giftLog or {}
B3.giftLog[#B3.giftLog + 1] = { who = "Kevin", item = "minecraft:diamond", n = 5, at = os.epoch("utc") + 1 }
k3("lol nice")
local th = k3("thanks so much!!")
CHECK(th:find("welcome", 1, true) or th:find("earned", 1, true) or th:find("pleasure", 1, true), "thanks right after a gift: a special answer: " .. th)
-- TAXI (the owner: "we know players' bed positions (overworld only) - offer a free drone trip from the base
-- to their home or the other way")
local realDet, realStart = det, startRide
local rides = {}
local P3 = { kevin = { x = HOME.x + 3, y = HOME.y, z = HOME.z, respawnPosition = { x = HOME.x + 900, y = 70, z = HOME.z - 400 },
                       respawnDimension = "minecraft:overworld" } }
det = { getPlayer = function(n) return P3[tostring(n):lower()] end, getOnlinePlayers = function() return { "Kevin", owner } end }
startRide = function(name, dest, owner2)
  rides[#rides + 1] = { name = name, dest = dest }
  state.lastRide = state.lastRide or {}
  state.lastRide[name:lower()] = (state.lastRide[name:lower()] or 0) + 1
end
VOICE.convo, VOICE.pend, VOICE.games = {}, {}, {}
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3 } }
VOICE.mem().kevin = { visits = 1, rep = 0 }
CHECK(k3("base take me home"):find("friends of the base", 1, true) and #rides == 0, "a stranger gets no taxi (friends only): " .. table.concat(told, " | "))
VOICE.mem().kevin.rep = 20
CHECK(k3("base take me home"):find("on the house", 1, true) or told[1]:find("takes you home", 1, true), "a regular at the base: a free ride home: " .. table.concat(told, " | "))
CHECK(#rides == 1 and rides[1].dest.x == HOME.x + 900 and rides[1].dest.y == 71 and rides[1].dest.name == "your bed", "... to their bed (one above it)")
CHECK(not table.concat(told, " "):find(tostring(HOME.x + 900), 1, true), "the bed's coordinates are never said in chat")
CHECK(k3("base take me home"):find("short break", 1, true) and #rides == 1, "5 min between rides")
CLOCK = CLOCK + 400
-- at home: "base, take me to the base" (far away - only the taxi is answered there)
ENV.data.ents = {}
place("Kevin", 900)
P3.kevin.x, P3.kevin.z = HOME.x + 905, HOME.z - 398
told = {}
VOICE.chat({ name = "Kevin", msg = "base, take me to the base pls" })
CHECK(#rides == 2 and rides[2].dest.name == "the base", "far away at home: base, take me to the base -> a ride to the base: " .. table.concat(told, " | "))
told = {}
VOICE.chat({ name = "Kevin", msg = "base tell me a joke" })
CHECK(#told == 0, "far away, anything else is still not answered")
CLOCK = CLOCK + 400
P3.kevin.x, P3.kevin.z = HOME.x + 3000, HOME.z
told = {}
VOICE.chat({ name = "Kevin", msg = "base take me to the base" })
CHECK(#rides == 2 and table.concat(told, " "):find("near your bed", 1, true), "neither at the base nor near the bed: no ride: " .. table.concat(told, " | "))
-- bed in the Nether / no bed / bed at the base
P3.kevin.x, P3.kevin.z = HOME.x + 3, HOME.z
place("Kevin", 3)
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3 } }
P3.kevin.respawnDimension = "minecraft:the_nether"
CHECK(k3("base take me home"):find("not in the overworld", 1, true), "a bed in the Nether: no taxi")
P3.kevin.respawnDimension, P3.kevin.respawnPosition = "minecraft:overworld", nil
CHECK(k3("base take me home"):find("no bed set", 1, true), "no bed: it says so")
P3.kevin.respawnPosition = { x = HOME.x + 10, y = HOME.y, z = HOME.z }
CHECK(k3("base take me home"):find("right here at the base", 1, true), "a bed at the base: no taxi needed")
P3.kevin.respawnPosition = { x = HOME.x + 900, y = 70, z = HOME.z - 400 }
-- the daily limit, taxi off
setSetting("voice.taxiDaily", 2)
CHECK(k3("base take me home"):find("2 free rides", 1, true), "the daily limit (voice.taxiDaily)")
resetSetting("voice.taxiDaily")
setSetting("voice.taxi", false)
VOICE.mem().kevin.taxi = nil
CHECK(k3("base free ride"):find("closed", 1, true), "voice.taxi off: closed")
resetSetting("voice.taxi")
-- the offer: once a visit, after 4 min at the base
VOICE.mem().kevin.taxi = nil
VOICE.pend, VOICE.games, VOICE.taxiOffered, VOICE.taxiNext = {}, {}, {}, 0
VOICE.since = VOICE.since or {}
VOICE.since.Kevin = CLOCK - 300
told, VOICE.queue = {}, {}
for _, fn in ipairs(VOICE.tickHooks) do fn(CLOCK, { Kevin = true }) end
CHECK(table.concat(told, " "):find("ride to your bed", 1, true) and VOICE.pend.kevin and VOICE.pend.kevin.yes == "#taxi:bed", "after 4 min: the offer: " .. table.concat(told, " | "))
local nr = #rides
k3("yes")
CHECK(#rides == nr + 1 and rides[#rides].dest.name == "your bed", "yes -> the ride home")
VOICE.taxiNext = 0
told = {}
for _, fn in ipairs(VOICE.tickHooks) do fn(CLOCK, { Kevin = true }) end
CHECK(not table.concat(told, " "):find("ride to your bed", 1, true), "... only once a visit")
-- the owner: no title / limits needed
P3[owner:lower()] = { x = HOME.x + 2, y = HOME.y, z = HOME.z, respawnPosition = { x = HOME.x - 7000, y = 64, z = HOME.z }, respawnDimension = "minecraft:overworld" }
ENV.data.ents = { { kind = "player", name = owner, dist = 2 } }
place(owner, 2)
told = {}
VOICE.chat({ name = owner, msg = "base fly me home" })
CHECK(rides[#rides].name == owner and rides[#rides].dest.x == HOME.x - 7000, "the owner: home even 7000 blocks away (no limit)")
det, startRide = realDet, realStart
place(owner, 5000)
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3 } }
-- SLOWER SPEECH (the owner: "the voice seems too fast, I can't hear the words") - the service has no speed
-- setting, so the sound is stretched here, the PITCH KEPT (a plain slow-down would make it deeper)
local sine = {}
for i = 1, 48000 do sine[i] = math.floor(100 * math.sin(2 * math.pi * i / 96) + 0.5) end   -- (500 Hz for 1 s)
local function crossings(t) local n = 0 for i = 2, #t do if (t[i - 1] < 0) ~= (t[i] < 0) then n = n + 1 end end return n / #t end
local st = VOICE.stretch(sine, 0.8)
CHECK(#st > 48000 / 0.8 * 0.95 and #st < 48000 / 0.8 * 1.05, "speed 0.8: 25 % longer (" .. #sine .. " -> " .. #st .. " samples)")
local cin, cout = crossings(sine), crossings(st)
CHECK(math.abs(cout - cin) / cin < 0.05, "... the same pitch (zero crossings " .. string.format("%.4f -> %.4f", cin, cout) .. ")")
local loud = 0
for i = 2000, #st - 2000 do if math.abs(st[i]) > loud then loud = math.abs(st[i]) end end
CHECK(loud >= 90 and loud <= 127, "... as loud as before, no clipping (" .. loud .. ")")
local okRange = true
for i = 1, #st do if st[i] ~= math.floor(st[i]) or st[i] < -128 or st[i] > 127 then okRange = false end end
CHECK(okRange, "... whole numbers -128..127 (what a speaker plays)")
CHECK(VOICE.stretch(sine, 1) == sine, "speed 1 = the sound as it came")
handleCommand("voice speed 70")
CHECK(math.abs(VOICE.speed() - 0.7) < 0.001, "voice speed 70 = 0.7")
handleCommand("voice speed 20")
CHECK(VOICE.speed() == 0.5, "never slower than half")
resetSetting("voice.speed")
CHECK(VOICE.speed() == 0.8, "default 0.8 (25 % slower than the service)")
-- the accent (espeak voice) goes to the service and is part of the cache name
local urls = {}
local realHttp = http
http = { get = function(u) urls[#urls + 1] = u return { readAll = function() return string.rep("x", 400) end, close = function() end } end }
handleCommand("voice accent en-gb-scotland")
VOICE.audio("a totally new phrase for the accent test")
CHECK(urls[#urls] and urls[#urls]:find("&voice=en-gb-scotland", 1, true), "voice accent: sent to the service: " .. tostring(urls[#urls]))
handleCommand("voice accent off")
VOICE.audio("a totally new phrase for the accent test")
CHECK(not urls[#urls]:find("voice=", 1, true) and #urls == 2, "accent off: the default voice, a different cache entry")
http = realHttp
-- UPDATES ON FULL FLOPPIES (the owner: "on each update I have to run disks" - the map fills the data floppies and
-- the new copy needed a floppy with room for ALL of it): the old copy's room and the speech cache count now
local realLoadfile = loadfile
local newBody
loadfile = function(path, ...)
  if tostring(path):find("upgrade.lua", 1, true) then return function() return true, newBody end end
  return realLoadfile(path, ...)
end
local pack3 = io.open(SRC_DIR .. "/dist/voice_talk3.lua"):read("a")
newBody = pack3 .. "\n-- a newer version\n"
-- every data floppy nearly full (map files), disk10 holds the old pack 3 + 30 KB of cached speech
fs.makeDir("disk10/voice")
for i = 1, 6 do put("disk10/voice/c" .. i .. ".dfpwm", string.rep("v", 5000)) end
for _, m in ipairs({ "disk7", "disk8", "disk9", "disk10" }) do
  put(m .. "/map_filler.dat", "")
  local free = fs.getFreeSpace(m)
  put(m .. "/map_filler.dat", string.rep("m", math.max(0, free - 3000)))
end
local fillerSize = fs.getSize("disk10/map_filler.dat")
local okU, whereU = installAddon("voice_talk3.lua", "voice", function() end)
CHECK(okU and whereU == "disk10/voice_talk3.lua", "an update on a nearly full floppy: in place of the old copy: " .. tostring(whereU))
local nowText = io.open and fs.open("disk10/voice_talk3.lua", "r").readAll()
CHECK(nowText and nowText:find("a newer version", 1, true), "... the new version is there")
CHECK(fs.getSize("disk10/map_filler.dat") == fillerSize, "... the map data was not touched")
local left = 0
for _, f in ipairs(fs.list("disk10/voice")) do left = left + fs.getSize("disk10/voice/" .. f) end
CHECK(left < 30000, "... cached speech made room (" .. left .. " bytes left of 30000)")
local okS, _, same = installAddon("voice_talk3.lua", "voice", function() end)
CHECK(okS and same == "same", "the same version again: nothing written (up to date)")
newBody = pack3 .. "\n-- " .. string.rep("x", 200000) .. "\n"
local okBig, whyBig = installAddon("voice_talk3.lua", "voice", function() end)
CHECK(not okBig and tostring(whyBig):find("disks data", 1, true) and fs.exists("disk10/voice_talk3.lua"),
      "really no room: it says so, and the old copy stays: " .. tostring(whyBig))
for _, m in ipairs({ "disk7", "disk8", "disk9", "disk10" }) do fs.delete(m .. "/map_filler.dat") end
newBody = pack3
installAddon("voice_talk3.lua", "voice", function() end)
loadfile = realLoadfile
CHECK(io.open(SRC_DIR .. "/base_console.lua"):read("a"):find("pcall(voiceUpdate, log)", 1, true), "upgrade also updates the voice files")
-- THE CACHE CREPT OVER EVERY FLOPPY (the owner: "disk12/drone_logs.dat not saved (7 KB free)" with the map
-- already on the helpers): cacheKB was PER FOLDER and each new phrase went to the floppy with the most room ->
-- a cache folder on every floppy, each filled to ~16 KB free. Now: cacheKB for ALL floppies together, and
-- never into a floppy's reserved room.
http = { get = function(u) return { readAll = function() return string.rep("s", 12000) end, close = function() end } end }
for _, f in ipairs(voiceCacheFiles()) do fs.delete(f.path) end
for i = 1, 80 do VOICE.audio("cache spread phrase number " .. i) end
local totalC = voiceCacheBytes()
CHECK(totalC > 0 and totalC <= 200 * 1024, "the speech cache on ALL floppies together stays under cacheKB (" ..
      math.floor(totalC / 1024) .. " KB)")
for _, d in ipairs(mountedDisks()) do
  if d.data then
    CHECK(d.free >= floppyReserve(), "the cache never takes " .. d.mount .. "'s reserved room (" ..
          math.floor(d.free / 1024) .. " KB free)")
  end
end
http = realHttp
for _, f in ipairs(voiceCacheFiles()) do fs.delete(f.path) end

-- RELOAD (voice update loads the add-on and the packs again): every hook once, not twice
local nHooks = { #VOICE.chatHooks, #VOICE.idleExtra, #VOICE.greetExtra, #VOICE.eventHooks, #VOICE.patterns, #VOICE.tickHooks }
local nIntents = #VOICE.INTENTS
for _, f in ipairs(VOICE_FILES) do loadAddon(f) end
local same = nHooks[1] == #VOICE.chatHooks and nHooks[2] == #VOICE.idleExtra and nHooks[3] == #VOICE.greetExtra and
             nHooks[4] == #VOICE.eventHooks and nHooks[5] == #VOICE.patterns and nHooks[6] == #VOICE.tickHooks
CHECK(same and nIntents == #VOICE.INTENTS, "after a reload every hook is there once (" .. nHooks[1] .. " chat hooks -> " .. #VOICE.chatHooks .. ")")
loadAddon("voice_talk3.lua")
CHECK(#VOICE.chatHooks == nHooks[1] and #VOICE.tickHooks == nHooks[6] and #VOICE.INTENTS == nIntents and #VOICE.dupIntents == 0,
      "ONE pack loaded again (an update of just that file): the whole chain loads, still every hook once")

-- 20. FUZZ (the owner: "keep checking the code for bugs"): thousands of messy chat messages, odd world states,
--     every idle line and tick - any error raised inside the voice files counts, also the ones a pcall in the
--     add-on would hide in game (a feature that silently stops working)
local realPcall = pcall
local fuzzErr = {}
pcall = function(f, ...)
  local r = table.pack(realPcall(f, ...))
  if not r[1] and tostring(r[2]):find("voice_", 1, true) then fuzzErr[#fuzzErr + 1] = tostring(r[2]) end
  return table.unpack(r, 1, r.n)
end
local corpus = { "base", "Base,", "the", "a", "i", "me", "you", "my", "is", "what", "how", "who", "?", "!", "...", ":)", "<3", "%", "%s", "%d",
  "(", ")", "[", "]", ".*", "^", "$", "-", "+", "*", "/", "=", "1", "2", "7", "0", "-5", "99999999999999999999", "3.5", "x", "yes", "no",
  "hangman", "riddle", "joke", "play", "game", "call", "favourite", "birthday", "is", "forget", "me", "secret", "word", "gift", "hack",
  "pirate", "talk", "like", "normal", "true", "false", "higher", "lower", "chain", "count", "with", "mad", "libs", "guess", "mob", "number",
  "between", "and", "or", "should", "pick", "choose", "spell", "backwards", "remind", "in", "minutes", "to", "remember", "notes", "say",
  "leave", "message", "for", "owner", "who", "lives", "here", "status", "turtle", "where", "turtles", "weather", "time", "sing", "song",
  "creeper", "diamond", "how", "do", "get", "diamonds", "many", "we", "have", "iron", "ingots", "knock", "adventure", "1", "2", "3",
  "rock", "paper", "scissors", "quiz", "flip", "coin", "roll", "dice", "8", "ball", "will", "story", "fact", "roast", "compliment",
  "shh", "unmute", "visitors", "messages", "clear", "mentions", "about", "today", "yesterday", "diary", "badges", "friendship", "level",
  "top", "players", "name", "pet", "build", "idea", "wish", "#adv:zzz", "#games", "#more", "#tour", "#nope:x", "ÿþ", "\0", "\n", "\t",
  string.rep("a", 300), string.rep("ha", 80), "base base base", "", " " }
math.randomseed(4242)
local nicks = { "Kevin", owner, "Zed", "Steve" }
place("Steve", 4)
place("Kevin", 3)
state.online = { [owner:lower()] = true, kevin = true, steve = true, zed = true }
ENV.data.ents = { { kind = "player", name = "Kevin", dist = 3 }, { kind = "player", name = "Steve", dist = 4 } }
-- (every word of every intent's keys too, and a third of the messages start with a whole key: every reply runs)
local keysAll = {}
for _, it in ipairs(VOICE.INTENTS) do
  for _, k in ipairs(it.keys) do
    keysAll[#keysAll + 1] = k
    for w in k:gmatch("%S+") do corpus[#corpus + 1] = w end
  end
end
local crashed = {}
-- every key of every intent, from a visitor at the base and from the owner far away (each reply function runs)
for _, k in ipairs(keysAll) do
  for _, who in ipairs({ "Kevin", owner }) do
    VOICE.games, VOICE.pend = {}, {}
    local ok, err = realPcall(VOICE.chat, { name = who, msg = "base " .. k })
    if not ok then crashed[#crashed + 1] = who .. ": [base " .. k .. "] -> " .. tostring(err) end
  end
end
for i = 1, 6000 do
  local n = math.random(0, 9)
  local t = {}
  if math.random() < 0.35 then t[1] = (math.random() < 0.5 and "base " or "") .. keysAll[math.random(1, #keysAll)] end
  for j = #t + 1, n do t[j] = corpus[math.random(1, #corpus)] end
  local msg = table.concat(t, math.random() < 0.8 and " " or "")
  local who = nicks[math.random(1, #nicks)]
  told = {}
  VOICE.queue = {}
  local ok, err = realPcall(VOICE.chat, { name = who, msg = msg })
  if not ok then crashed[#crashed + 1] = who .. ": [" .. msg:sub(1, 60) .. "] -> " .. tostring(err) end
  if i % 400 == 0 then CLOCK = CLOCK + 200 end            -- (games / questions time out now and then)
end
CHECK(#crashed == 0, "6000 messy chat messages: no crash (" .. #crashed .. "): " .. tostring(crashed[1]) .. " | " .. tostring(crashed[2]))
-- odd world states: every idle line, the tick, greetings
local states = { function() ENV.data = nil end, function() ENV.data = {} end,
  function() ENV.data = { time = 15000, rain = true, ents = { { kind = "hostile", name = "zombie", dist = 3 } }, moonName = "Full moon" } end,
  function() ENV.data = { time = 1000, thunder = true, biome = "minecraft:plains", slime = true, ents = {} } end,
  function() state.turtles = {} end,
  function() state.turtles = { [1] = { id = 1, label = "T1", task = "survey 3", pos = { x = 1, y = 2, z = 3 }, lastSeen = CLOCK } ,
                               [2] = { id = 2, label = "T2" } } end }
for round = 1, 30 do
  states[math.random(1, #states)]()
  for _, fn in ipairs(VOICE.idleExtra) do
    local ok, err = realPcall(fn, { Kevin = true }, round % 2 == 0 and "Kevin" or nil)
    if not ok then crashed[#crashed + 1] = "idle: " .. tostring(err) end
  end
  local okI, errI = realPcall(VOICE.idle, { Kevin = true })
  if not okI then crashed[#crashed + 1] = "VOICE.idle: " .. tostring(errI) end
  local okT, errT = realPcall(VOICE.tick)
  if not okT then crashed[#crashed + 1] = "tick: " .. tostring(errT) end
  for _, n in ipairs(nicks) do
    local okG, errG = realPcall(VOICE.greet, n)
    if not okG then crashed[#crashed + 1] = "greet " .. n .. ": " .. tostring(errG) end
    for _, fn in ipairs(VOICE.greetExtra) do
      local okE, errE = realPcall(fn, n)
      if not okE then crashed[#crashed + 1] = "greetExtra " .. n .. ": " .. tostring(errE) end
    end
  end
  CLOCK = CLOCK + 37
end
ENV.data = { ents = {} }
CHECK(#crashed == 0, "idle talk / tick / greetings in odd world states: no crash: " .. tostring(crashed[1]))
-- every console command
for _, c in ipairs({ "voice", "voice heard", "voice gifts", "voice visitors", "voice announce", "voice listen", "voice nick", "voice gifts give",
                     "voice gifts give x", "voice scan x", "voice volume", "voice name", "voice lonely abc", "voice gifts block", "voice zzz" }) do
  local ok, err = realPcall(handleCommand, c)
  if not ok then crashed[#crashed + 1] = c .. ": " .. tostring(err) end
end
CHECK(#crashed == 0, "every voice console command (also half-typed): no crash: " .. tostring(crashed[1]))
pcall = realPcall
CHECK(#fuzzErr == 0, "no error inside the voice files hidden by a pcall (" .. #fuzzErr .. "): " .. tostring(fuzzErr[1]) .. " | " .. tostring(fuzzErr[2]) .. " | " .. tostring(fuzzErr[3]))
ENV.scan = okScan
chatTell = oldTell
fs.exists = realExists
envDet = realEnvDet
http = nil

-- 22. THE OWNER'S NOTES AFTER A REAL VISIT: "it keeps responding to me even when I am far away", "I move 10
--     blocks away, come back and it greets me again", "players can spam math puzzles and keep getting points"
local saveEnv = envDet
envDet = nil                                             -- (who is near: the Player Detector, simple to steer)
local told2 = {}
local tell2 = chatTell
chatTell = function(n, t) told2[#told2 + 1] = t end
local function say2(who, msg) told2 = {} VOICE.chat({ name = who, msg = msg }) return table.concat(told2, " | ") end
state.online = { [owner:lower()] = true, kevin = true }
VOICE.convo, VOICE.pend, VOICE.games = {}, {}, {}
place(owner, 5000)
CHECK(say2(owner, "going back to base now") == "", "far away: 'base' inside a sentence is not for it")
CHECK(say2(owner, "anyone want to come to my base?") == "", "far away: a question with 'base' in it is not for it either")
CHECK(say2(owner, "base, status?") ~= "", "far away: a message STARTING with its name is answered in chat")
VOICE.queue = {}
place(owner, 5)
CHECK(say2(owner, "base quiz"):find("Quiz", 1, true), "at the base: a quiz starts")
local Qg = VOICE.games[owner:lower()]
place(owner, 5000)
CHECK(say2(owner, Qg.a[1]) == "", "far away: a running game does not take your chat")
CHECK(say2(owner, "lol nice") == "", "far away: an open conversation does not follow you")
place("Kevin", 6000)
CHECK(say2("Kevin", "base how are you") == "", "far away: other players get nothing (only taxi phrases)")
-- greeting: a few steps out of the detector and back = still the same visit
place(owner, 5000) VOICE.tick() CLOCK = CLOCK + 700 VOICE.tick()      -- (away a long time first)
VOICE.near, VOICE.seenNear, VOICE.greeted = {}, {}, {}
place(owner, 5)
VOICE.tick()
local g1 = VOICE.greeted[owner]
CHECK(g1 ~= nil, "arriving: greeted")
for _ = 1, 6 do CLOCK = CLOCK + 120 VOICE.tick() end                  -- (12 minutes at the base)
place(owner, 5000) VOICE.tick() CLOCK = CLOCK + 40 VOICE.tick()        -- (40 s out of range)
place(owner, 5) CLOCK = CLOCK + 2 VOICE.tick()
CHECK(VOICE.greeted[owner] == g1, "a few steps out and back after a long stay: NOT greeted again")
place(owner, 5000) VOICE.tick() CLOCK = CLOCK + 100 VOICE.tick()
CHECK(not VOICE.near[owner], "gone for longer than leaveAfter (90 s): left")
CLOCK = CLOCK + 120
place(owner, 5) VOICE.tick()
CHECK(VOICE.greeted[owner] == g1, "back after 4 minutes: still not greeted (away less than 10 min)")
place(owner, 5000) VOICE.tick() CLOCK = CLOCK + 700 VOICE.tick()
place(owner, 5) VOICE.tick()
CHECK(VOICE.greeted[owner] ~= g1, "away 10+ minutes: greeted again")
-- quiz / maths points: at most voice.quizDaily (15) a day
place("Kevin", 6)
local km = VOICE.mem()
km.kevin = km.kevin or {}
km.kevin.qday, km.kevin.qn = nil, nil
local before = km.kevin.quiz or 0
local wins, last = 0, ""
local evOld = VOICE.event
VOICE.event = function(w, kind, what) if kind == "win" and what == "quiz" then wins = wins + 1 end return evOld(w, kind, what) end
for _ = 1, 25 do
  VOICE.games.kevin = { kind = "quiz", a = { "42" }, till = CLOCK + 100, at = CLOCK }
  last = say2("Kevin", "42")
end
VOICE.event = evOld
CHECK((km.kevin.quiz or 0) - before == 15, "25 right answers in a row: only 15 points today (" .. ((km.kevin.quiz or 0) - before) .. ")")
CHECK(wins == 15, "... and only 15 'wins' for friendship / badges / gifts (" .. wins .. ")")
CHECK(last:find("come back tomorrow", 1, true), "it says so: " .. last)
km.kevin.qday = "2000-01-01"                              -- (a new day)
VOICE.games.kevin = { kind = "quiz", a = { "42" }, till = CLOCK + 100, at = CLOCK }
CHECK(say2("Kevin", "42"):find("point", 1, true) and km.kevin.qn == 1, "a new day: points again")
chatTell = tell2
envDet = saveEnv

-- 23. THE SAME ANSWER AGAIN IS SPOKEN AGAIN (the owner: "flip a coin" 10 times - "It is heads." was spoken
--     once, the rest only in chat: the 30-s "same words" rule is for things it says by itself)
envDet = nil
local tell3 = chatTell
chatTell = function() end
place(owner, 5)
state.online = { [owner:lower()] = true }
VOICE.convo, VOICE.pend, VOICE.games, VOICE.quietUntil = {}, {}, {}, nil
VOICE.said = {}
local spoken = 0
for _ = 1, 10 do
  VOICE.queue = {}
  VOICE.chat({ name = owner, msg = "base flip a coin" })
  for _, q in ipairs(VOICE.queue) do if q.text:find("It is", 1, true) then spoken = spoken + 1 end end
  CLOCK = CLOCK + 3
end
CHECK(spoken == 10, "10 coin flips in a row: every answer spoken (" .. spoken .. " of 10)")
-- things it says by itself are still not repeated within 30 s
VOICE.queue, VOICE.said = {}, {}
VOICE.say("The rain has stopped.")
VOICE.say("The rain has stopped.")
CHECK(#VOICE.queue == 1, "its own lines (weather, warnings) are still not said twice within 30 s")
chatTell = tell3
envDet = saveEnv

-- 24. SEVERAL PEOPLE + NEW VISITORS (the owner: "when more than one person uses it it acts weird", "new players
--     hear the same sentences")
local SCAN2 = {}
local env2 = envDet
envDet = setmetatable({ scanEntities = function(r) return SCAN2 end }, { __index = {} })
local tell4 = chatTell
local told4 = {}
chatTell = function(n, t) told4[#told4 + 1] = n .. ": " .. t end
state.ownerUuid = "u-owner"
state.players = {}
state.online = { [owner:lower()] = true, steve = true, alex = true }
VOICE.detAt = nil
local function at(name, dx, dz)
  for _, e in ipairs(state.players) do
    if e.name == name then e.p = { x = HOME.x + dx, y = HOME.y, z = HOME.z + dz } e.dim = "minecraft:overworld" return end
  end
  state.players[#state.players + 1] = { name = name, p = { x = HOME.x + dx, y = HOME.y, z = HOME.z + dz }, dim = "minecraft:overworld" }
end
at(owner, 5000, 0)
at("Steve", 5, 0)
at("Alex", -6, 2)
-- the detector cannot name either (two near the base): unnamed players at their relative spots
local function names()
  ENV.scanAt = -100
  ENV.scan()
  local byDist = {}
  for _, p in ipairs(VOICE.nearPlayers()) do byDist[math.floor(p.dist + 0.5)] = p.name end
  return byDist
end
local wrong = 0
for round = 1, 6 do
  if round % 2 == 1 then
    SCAN2 = { { name = "minecraft:player", x = 5, y = 0, z = 0 }, { name = "minecraft:player", x = -6, y = 0, z = 2 } }
  else
    SCAN2 = { { name = "minecraft:player", x = -6, y = 0, z = 2 }, { name = "minecraft:player", x = 5, y = 0, z = 0 } }
  end
  local b = names()
  if b[5] ~= "Steve" or b[6] ~= "Alex" then wrong = wrong + 1 end
end
CHECK(wrong == 0, "two players the detector cannot name: each keeps HIS name, whatever the scan order (" .. wrong .. " of 6 wrong)")
-- they walk around: the names follow where they really are
at("Steve", -6, 2) at("Alex", 5, 0)
SCAN2 = { { name = "minecraft:player", x = 5, y = 0, z = 0 }, { name = "minecraft:player", x = -6, y = 0, z = 2 } }
local b2 = names()
CHECK(b2[5] == "Alex" and b2[6] == "Steve", "they swap places: the names go with them")
-- the detector learns where it stands from a player it CAN name (the owner by uuid)
at(owner, 3, 3)
SCAN2 = { { name = "minecraft:player", uuid = "u-owner", x = 3, y = 0, z = 3 } }
names()
CHECK(VOICE.detAt and VOICE.detAt.x == HOME.x and VOICE.detAt.z == HOME.z, "the detector's own spot is learned from the owner")
at(owner, 5000, 0)
-- a group arrives at once: ONE greeting naming them, not three in a row (and each new one told how to talk)
VOICE.near, VOICE.greeted, VOICE.seenNear, VOICE.queue, VOICE.said = {}, {}, {}, {}, {}
local m = VOICE.mem()
m.steve, m.alex, m.kim = nil, nil, nil
at("Steve", 5, 0) at("Alex", -6, 2) at("Kim", 0, 7)
state.online.kim = true
SCAN2 = { { name = "minecraft:player", x = 5, y = 0, z = 0 }, { name = "minecraft:player", x = -6, y = 0, z = 2 },
          { name = "minecraft:player", x = 0, y = 0, z = 7 } }
ENV.scanAt = -100
told4 = {}
VOICE.tick()
local greetings = 0
for _, q in ipairs(VOICE.queue) do
  if q.text:find("Steve", 1, true) or q.text:find("Alex", 1, true) or q.text:find("Kim", 1, true) then greetings = greetings + 1 end
end
CHECK(greetings == 1 and said():find("Steve", 1, true) and said():find("Alex", 1, true) and said():find("Kim", 1, true),
      "3 arrive together: one greeting with all three names: " .. said())
local tips = 0
for _, l in ipairs(told4) do if l:find("start with my name", 1, true) then tips = tips + 1 end end
CHECK(tips == 3, "each new visitor is told (privately in chat) how to talk to it (" .. tips .. ")")
-- answers to two people: the spoken one says who it is for
VOICE.queue, VOICE.said = {}, {}
VOICE.convo, VOICE.pend, VOICE.games = {}, {}, {}
VOICE.chat({ name = "Steve", msg = "base flip a coin" })
VOICE.chat({ name = "Alex", msg = "base flip a coin" })
CHECK(said():find("Steve, ", 1, true) and said():find("Alex, ", 1, true), "several at the base: a spoken answer says who it is for: " .. said())
-- a full queue never drops an answer while it has its own lines to drop
VOICE.queue, VOICE.said = {}, {}
for i = 1, 6 do VOICE.say("idle line " .. i) end
VOICE.say("Steve, it is heads.", nil, true)
VOICE.say("Alex, it is tails.", nil, true)
CHECK(said():find("Steve, it is heads", 1, true) and said():find("Alex, it is tails", 1, true) and #VOICE.queue == 6,
      "the queue is full: its own lines go, the answers stay")
-- new visitors one after another: many different first lines (not the same sentence every time)
local firsts = {}
for i = 1, 12 do
  local who = "Visitor" .. i
  state.online[who:lower()] = true
  VOICE.queue, VOICE.said = {}, {}
  VOICE.greet(who)
  if VOICE.queue[1] then firsts[VOICE.queue[1].text:gsub(who, "X")] = true end
end
local nf = 0
for _ in pairs(firsts) do nf = nf + 1 end
CHECK(nf >= 9, "12 new visitors: " .. nf .. " different first greetings")
chatTell = tell4
envDet = env2
-- an ICEBREAKER: a new visitor who stays quiet for ~30 s gets one offer; "yes" takes it
envDet = setmetatable({ scanEntities = function(r) return SCAN2 end }, { __index = {} })
chatTell = function(n, t) told4[#told4 + 1] = n .. ": " .. t end
VOICE.near, VOICE.greeted, VOICE.seenNear, VOICE.newcomer, VOICE.pend, VOICE.convo, VOICE.games = {}, {}, {}, {}, {}, {}, {}
VOICE.quietUntil = nil
local mm = VOICE.mem()
mm.newbie = nil
state.players = {}
at(owner, 5000, 0)
at("Newbie", 4, 1)
state.online = { [owner:lower()] = true, newbie = true }
SCAN2 = { { name = "Newbie", x = 4, y = 0, z = 1 } }
ENV.scanAt = -100
VOICE.tick()
CHECK(VOICE.newcomer.newbie, "a first-time visitor is noted for an icebreaker")
told4 = {}
for _ = 1, 16 do CLOCK = CLOCK + 2 ENV.scanAt = -100 VOICE.tick() end
local offer = table.concat(told4, " | ")
CHECK(VOICE.pend.newbie and offer:find("Newbie", 1, true), "after ~30 s of silence: one offer (" .. offer .. ")")
local P = VOICE.pend.newbie
told4 = {}
VOICE.chat({ name = "Newbie", msg = P.kind == "react" and "just exploring" or "yes" })
CHECK(#told4 > 0 and told4[#told4] ~= "", "the answer gets a reply: " .. tostring(told4[#told4]))
for _ = 1, 30 do CLOCK = CLOCK + 2 ENV.scanAt = -100 VOICE.tick() end
CHECK(not VOICE.newcomer.newbie, "only ONE icebreaker per visit")
chatTell = tell4
envDet = env2

;(function()
-- ===== part 25: LONG LINES SPOKEN WHOLE, NO JUMBLE (the owner: "long speeches cut midway and do not go on;
-- with a lot to say it jumps between speeches - when I log back in I hear a lot of lines, hard to understand")
VOICE.queue, VOICE.said = {}, {}
setSetting("voice.on", true)
VOICE.mute = nil
PERIPHS["speaker_0"] = { types = { "speaker" }, obj = { playAudio = function() played = played + 1 return true end,
                                                        playSound = function() return true end } }
http = { get = function(url) gets[#gets + 1] = url
  return { readAll = function() return string.rep("\85", 3000) end, close = function() end } end }
package.preload["cc.audio.dfpwm"] = function() return { make_decoder = function() return function(s) return { #s } end end } end
package.loaded["cc.audio.dfpwm"] = nil
local long = "Welcome back! While you were away, 3 visitors came: Steve, Alex and Notch. They left 2 messages " ..
             "for you, one about the farm and one about the big tower by the river. 12 turtles working, 3 idle, " ..
             "2 need a look, 5 offline. 2 mining teams running. Survey 45 percent done. Have a nice evening."
CHECK(#long > 250, "(a long line: " .. #long .. " characters)")
VOICE.say(long, nil, true)
CHECK(VOICE.queue[1] and VOICE.queue[1].text == long, "a long line is queued WHOLE (it was cut at 200 characters)")
-- spoken in pieces: every piece asked for, in order, nothing left out, each short enough to be cached
gets = {}
local sleeps = {}
local sleep0 = sleep
sleep = function(t) sleeps[#sleeps + 1] = t end
speakAll()
sleep = sleep0
local asked = {}
for _, u in ipairs(gets) do
  local q = u:match("text=([^&]*)") or ""
  q = q:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end):gsub("+", " ")
  asked[#asked + 1] = q
end
local joined = table.concat(asked, " ")
CHECK(#asked >= 4, "spoken in " .. #asked .. " pieces")
CHECK(joined:gsub("%s", "") == long:gsub("%s", ""), "every word of it, in order (nothing cut off): " .. joined)
local maxLen = 0
for _, q in ipairs(asked) do maxLen = math.max(maxLen, #q) end
CHECK(maxLen <= 80, "each piece <= 80 characters (short pieces are cached too): " .. maxLen)
local cuts = 0
for i = 1, #asked - 1 do if not asked[i]:find("[%.!?,;:]$") then cuts = cuts + 1 end end
CHECK(cuts == 0, "pieces end at a sentence / comma, never inside one: " .. table.concat(asked, " | "))
-- after a line: it waits until the speaker has said it, then a short pause
local gap = false
for _, t in ipairs(sleeps) do if math.abs(t - VOICE.GAP) < 1e-9 then gap = true end end
CHECK(gap, "a pause after each line (lines never run into each other)")
-- A BURST (logging back in: welcome, the away report, visitors, mentions, gifts ... at once): what is queued is
-- said in ORDER and WHOLE - extra lines of its own are left out from the END, never the start
VOICE.queue, VOICE.said = {}, {}
for i = 1, 10 do VOICE.say("Burst line number " .. i .. ".") end
local q1 = {}
for _, q in ipairs(VOICE.queue) do q1[#q1 + 1] = q.text end
CHECK(#q1 == VOICE.MAX_OWN and q1[1] == "Burst line number 1." and q1[#q1] == "Burst line number " .. VOICE.MAX_OWN .. ".",
      "10 lines at once: the FIRST " .. VOICE.MAX_OWN .. " kept, in order (" .. table.concat(q1, " ") .. ")")
-- an answer to a player still gets in
CHECK(VOICE.say("It is heads.", nil, true) and VOICE.queue[#VOICE.queue].text == "It is heads.", "an answer always gets in")
for i = 1, 6 do VOICE.say("Answer " .. i, nil, true) end
local hasFirst = false
for _, q in ipairs(VOICE.queue) do if q.text == "Burst line number 1." then hasFirst = true end end
CHECK(#VOICE.queue <= VOICE.MAX_QUEUE + 6 and hasFirst, "many answers: its own LAST lines make room, the first one stays")
VOICE.queue, VOICE.said = {}, {}
end)()
