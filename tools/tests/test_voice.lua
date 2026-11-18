-- THE BASE TALKS (voice_addon.lua, an optional add-on on a data floppy): loaded from the floppy,
-- greets players coming near the base, says warnings only when someone can hear them, answers
-- "base, status?" in chat, the alarm, speech cached on the floppy, nothing when it is off.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
-- a data floppy with the add-on on it
addDrive("drive_7", "disk7")
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
put("disk7/base_data", "data")
put("disk7/voice_addon.lua", io.open(SRC_DIR .. "/voice_addon.lua"):read("a"))
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
CHECK(said():find("Welcome back, " .. owner, 1, true) and VOICE.queue[1].sound, "the owner is welcomed back: " .. said())
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

-- 4. a warning now that someone is near: said, with a bell; the same one again soon: not
VOICE.note("TURTLE STUCK", "Turtle 9 is stuck - the rescuer goes", C.warn)
CHECK(said():find("Warning. turtle stuck. Turtle 9 is stuck", 1, true), "a warning is said when someone is near: " .. said())
VOICE.queue = {}
CLOCK = CLOCK + 25
VOICE.note("TURTLE STUCK", "Turtle 9 is stuck - the rescuer goes", C.warn)
CHECK(#VOICE.queue == 0, "the same warning is not repeated within 5 minutes")
VOICE.note("INFO", "just information", C.label)
CHECK(#VOICE.queue == 0, "info messages are not said")

-- 5. a stranger comes near: "Visitor"; the alarm only when switched on
place("Steve", 20)
VOICE.tick()
CHECK(said():find("Visitor near the base: Steve", 1, true) and not said():find("Intruder", 1, true), "a stranger: visitor, no alarm (off by default): " .. said())
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
http = nil
