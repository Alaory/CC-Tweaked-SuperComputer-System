-- THE SPAWN SPEAKER (voice_spawn.lua + spawn_speaker.lua; the owner: "a speaker with an ender modem at spawn - its own
-- place, no rewards, wishes sent by drone, games, players do not know how to ask it, lots of different sentences").
-- The REAL relay program runs on a fake second computer, wired to the base by a fake rednet: pairing (a wrong code
-- does nothing), signed hellos (a forged one does not count), chat from a player at spawn answered AT SPAWN (help
-- without its name, jokes, games), no friendship / quiz points / badges there, wishes -> the drone gift queue (limits,
-- never-items, not-items), the sound sent in signed pieces (a changed / replayed one is refused), an answer cuts its
-- own talk, greetings + idle talk with many different lines, the relay offline = spawn is not special.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
CONFIG.voice = CONFIG.voice or {}
local SPAWN = { x = HOME.x + 3000, y = 70, z = HOME.z - 2000 }

-- the voice files on data floppies (the repo copies hidden)
local realExists = fs.exists
local HIDDEN = {}
for _, f in ipairs(VOICE_FILES) do HIDDEN[f] = true end
fs.exists = function(p) if HIDDEN[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
for i, f in ipairs(VOICE_FILES) do
  local k = 40 + i
  addDrive("drive_" .. k, "disk" .. k)
  put("disk" .. k .. "/base_data", "data")
  put("disk" .. k .. "/" .. f, io.open(SRC_DIR .. "/dist/" .. f):read("a"))
end
if dataPathReset then dataPathReset() end
-- a stand-in DFPWM: 8 samples <-> 1 byte (the real one is in the game)
package.preload["cc.audio.dfpwm"] = function()
  return {
    make_decoder = function() return function(s) local o = {} for i = 1, #s * 8 do o[i] = (s:byte(math.floor((i - 1) / 8) + 1) % 2 == 0) and 20 or -20 end return o end end,
    make_encoder = function() return function(p) local o = {} for i = 1, #p, 8 do o[#o + 1] = string.char(p[i] >= 0 and 2 or 1) end return table.concat(o) end end,
  }
end
package.loaded["cc.audio.dfpwm"] = nil
textutils.urlEncode = textutils.urlEncode or function(x) return tostring(x) end
http = { get = function(url) return { readAll = function() return string.rep("\0", 4800) end, close = function() end } end }
local okL, errL = pcall(loadVoiceChain)
CHECK(okL, "the voice chain loads: " .. tostring(errL))
CHECK(VOICE and VOICE.SPAWN and VOICE.packs["voice_spawn.lua"], "the spawn pack is loaded")
local SP = VOICE.SPAWN
setSetting("voice.spamBurst", 100000)          -- (the spam limit is tested in part 9; the other parts chat fast)
CHECK(#VOICE.dupIntents == 0, "no pack intent added twice")

state.owner = "Alaory"
state.online = { alaory = true, steve = true, alex = true, bob = true }
state.players = {
  { name = "Alaory", p = { x = HOME.x, y = HOME.y, z = HOME.z }, dim = DRONE_DIM },
  { name = "Steve", p = { x = SPAWN.x + 3, y = 70, z = SPAWN.z - 2 }, dim = DRONE_DIM },
}
state.me = { items = {
  { name = "minecraft:diamond", display = "Diamond", count = 500 },
  { name = "minecraft:apple", display = "Apple", count = 90 },
  { name = "minecraft:golden_apple", display = "Golden Apple", count = 30 },
  { name = "minecraft:oak_log", display = "Oak Log", count = 900 },
  { name = "minecraft:spawner", display = "Monster Spawner", count = 2 } }, byName = {} }
local told = {}
chatTell = function(who, text) told[#told + 1] = { who = who, text = tostring(text) } end
local function toldTo(who, n)
  local out = {}
  for i = math.max(1, #told - (n or 1) + 1), #told do if told[i].who == who then out[#out + 1] = told[i].text end end
  return table.concat(out, " | ")
end

-- ===== the relay: spawn_speaker.lua on its own computer =====
local RELAY, BASE = 77, os.getComputerID()
local src = io.open(SRC_DIR .. "/spawn_speaker.lua"):read("a")
src = src:gsub("parallel%.waitForAny%(listener, hello, player%)%s*$",
  "return { receive = receive, S = S, sendBase = sendBase, sign = sign, dataHash = dataHash }")
local relayFiles = {}
local renv = setmetatable({}, { __index = _G })
local toBase = {}                          -- messages the relay sent (delivered by hand)
renv.os = setmetatable({ getComputerID = function() return RELAY end, getComputerLabel = function() return "Spawn" end,
  setComputerLabel = function() end }, { __index = os })
renv.rednet = { send = function(id, m, proto) toBase[#toBase + 1] = { id = id, m = textutils.unserialize(textutils.serialize(m)), proto = proto } end,
  broadcast = function(m, proto) toBase[#toBase + 1] = { id = "all", m = textutils.unserialize(textutils.serialize(m)), proto = proto } end,
  isOpen = function() return true end, open = function() end, receive = function() end }
renv.peripheral = { getNames = function() return { "top", "left" } end,
  hasType = function(n, t) return (n == "top" and t == "modem") or (n == "left" and t == "speaker") end,
  call = function(n, f) if f == "isWireless" then return true end end,
  wrap = function(n) return { stop = function() end, playAudio = function() return true end } end }
renv.fs = { open = function(p, mode)
    if mode == "w" then local buf = {} return { write = function(t) buf[#buf + 1] = t end, close = function() relayFiles[p] = table.concat(buf) end } end
    if relayFiles[p] then local d = relayFiles[p] return { readAll = function() return d end, close = function() end } end
  end,
  exists = function(p) return relayFiles[p] ~= nil end, delete = function(p) relayFiles[p] = nil end,
  move = function(a, b) relayFiles[b], relayFiles[a] = relayFiles[a], nil end, getSize = function(p) return #(relayFiles[p] or "") end }
local termStub = setmetatable({}, { __index = function() return function() end end })
renv.term = termStub
renv.print = function() end
local fn = load(src, "spawn_speaker", "t", renv)
local okR, R = pcall(fn)
CHECK(okR and type(R) == "table", "the relay program loads: " .. tostring(R))
local function deliver()
  local n = 0
  while #toBase > 0 do
    local o = table.remove(toBase, 1)
    CHECK(o.proto == "basespawn", "the relay talks on basespawn")
    VOICE.spawnReceive(RELAY, o.m)
    n = n + 1
  end
  return n
end
-- the base's rednet -> the relay
local sentToRelay = {}
rednet = rednet or {}
rednet.send = function(id, m, proto)
  local copy = textutils.unserialize(textutils.serialize(m))
  sentToRelay[#sentToRelay + 1] = copy
  if id == RELAY and proto == "basespawn" then R.receive(BASE, copy) end
  return true
end

-- 1) not paired: it offers itself; a wrong code does nothing, the right one pairs
R.sendBase("hello")
deliver()
CHECK(SP.cands[RELAY], "the base heard the unpaired spawn speaker")
local out = {}
VOICE.command({ "voice", "spawn", "pair", "123456" == R.S.code and "654321" or "123456" }, function(t) out[#out + 1] = t end)
deliver()
CHECK(not R.S.key and not SP.paired(), "a WRONG code pairs nothing")
VOICE.command({ "voice", "spawn", "pair", R.S.code }, function(t) out[#out + 1] = t end)
CHECK(R.S.key and R.S.base == BASE, "the right code: the relay has a key")
deliver()
CHECK(SP.paired() and CONFIG.voice.spawnId == RELAY and CONFIG.voice.spawnKey == R.S.key, "... and the base saved the pairing")
CHECK(relayFiles["spawn_key.dat"] ~= nil, "the relay keeps its key in a file")
-- the spot: voice spawn at x y z
VOICE.command({ "voice", "spawn", "at", tostring(SPAWN.x), tostring(SPAWN.y), tostring(SPAWN.z) }, function() end)
CHECK(SP.at() and SP.at().x == SPAWN.x, "voice spawn at sets the spot")
-- signed hellos: a forged one is not "online"
SP.seenAt = nil
VOICE.spawnReceive(RELAY, { t = "hello", n = os.epoch("utc") + 5, sp = 1, q = 0, sig = "0000000000000000" })
CHECK(not SP.online(), "a FORGED hello does not count")
R.sendBase("hello")
deliver()
CHECK(SP.online() and SP.ready(), "a signed hello: the spawn speaker is online + ready")
CHECK(SP.isAt("Steve") and not SP.isAt("Alaory"), "Steve is at spawn, the owner at the base")

-- 2) chat at spawn
SP.queue = {}
VOICE.queue = {}
told = {}
VOICE.chat({ name = "Steve", msg = "how do i use this speaker?" })
CHECK(toldTo("Steve"):lower():find("base", 1, true) and (toldTo("Steve"):lower():find("start", 1, true) or toldTo("Steve"):lower():find("first", 1, true)
      or toldTo("Steve"):lower():find("begin", 1, true) or toldTo("Steve"):lower():find("use my name", 1, true) or toldTo("Steve"):lower():find("type", 1, true)),
      "'how do I use this speaker' (no name) -> how to talk to it: " .. toldTo("Steve"))
CHECK(#SP.queue == 1 and SP.queue[1].answer and #VOICE.queue == 0, "... said AT SPAWN, not at the base")
-- help is varied
local seen, n = {}, 0
for i = 1, 60 do local h = SP.helpText("Steve") if not seen[h] then seen[h] = true n = n + 1 end end
CHECK(n >= 55, "60 help answers, " .. n .. " different")
-- a joke
SP.queue = {}
told = {}
VOICE.chat({ name = "Steve", msg = "base tell me a joke" })
CHECK(#told >= 1 and #SP.queue >= 1 and #VOICE.queue == 0, "'base tell me a joke' at spawn: answered in chat + spoken at spawn")
-- a game works (rock paper scissors)
told = {}
VOICE.chat({ name = "Steve", msg = "base rock paper scissors" })
VOICE.chat({ name = "Steve", msg = "rock" })
CHECK(#told >= 2, "games work at spawn (rock paper scissors): " .. toldTo("Steve", 2))
-- who are you / where is the base: its own answers
told = {}
VOICE.chat({ name = "Steve", msg = "base who are you" })
CHECK(toldTo("Steve"):lower():find("spawn", 1, true) or toldTo("Steve"):lower():find("speaker", 1, true) or toldTo("Steve"):lower():find("voice", 1, true)
      or toldTo("Steve"):lower():find("computer", 1, true),
      "'who are you' at spawn: the spawn speaker's own answer: " .. toldTo("Steve"))
told = {}
VOICE.chat({ name = "Steve", msg = "base where is your base" })
CHECK(not toldTo("Steve"):find(tostring(HOME.x), 1, true), "the base's spot stays secret: " .. toldTo("Steve"))
-- players talking about a shop near it, without its name: nothing
told = {}
SP.spokeAt = nil
VOICE.convo = {}
VOICE.chat({ name = "Steve", msg = "how much is that sword at the shop" })
CHECK(#told == 0, "shop talk without its name gets no answer: " .. toldTo("Steve"))

-- 3) NO REWARDS at spawn
local m0 = VOICE.mem()
local before = m0.steve and m0.steve.rep
SP.inCtx(function() if VOICE.addRep then VOICE.addRep("Steve", 5) end end)
CHECK((VOICE.mem().steve and VOICE.mem().steve.rep) == before, "no friendship at spawn")
local evN = 0
VOICE.eventHooks[#VOICE.eventHooks + 1] = function() evN = evN + 1 end
SP.inCtx(VOICE.event, "Steve", "win", "quiz")
CHECK(evN == 0, "no game-win events (badges) at spawn")
VOICE.event("Steve", "win", "quiz")
CHECK(evN == 1, "... the base still gets them")
told = {}
VOICE.chat({ name = "Steve", msg = "base quiz me" })
local g = VOICE.games.steve
CHECK(g and g.kind == "quiz", "a quiz starts at spawn")
if g and g.kind == "quiz" then
  VOICE.chat({ name = "Steve", msg = tostring(g.a[1]) })
  CHECK(not (VOICE.mem().steve and VOICE.mem().steve.quiz), "a right quiz answer at spawn gives NO points: " .. toldTo("Steve"))
  CHECK(not toldTo("Steve"):find("point", 1, true), "... and does not talk about points: " .. toldTo("Steve"))
end
local okG, whyG = SP.inCtx(VOICE.giftEarn, "Steve", "regular")
CHECK(not okG, "no reward gifts at spawn (" .. tostring(whyG) .. ")")

-- 4) WISHES
local function wish(text) told = {} VOICE.chat({ name = "Steve", msg = text }) return toldTo("Steve") end
local a = wish("base i wish for 16 diamonds please")
CHECK(a:find("16 Diamonds", 1, true) and a:lower():find("yes", 1, true), "a wish asks first: " .. a)
a = wish("yes")
local q = VOICE.giftQueue()
CHECK(#q == 1 and q[1].who == "Steve" and q[1].item == "minecraft:diamond" and q[1].n == 16 and q[1].why == "wish",
      "yes -> queued for a drone: " .. a)
a = wish("base can i have an apple")
CHECK(a:lower():find("one at a time", 1, true) or a:lower():find("still", 1, true), "one wish at a time: " .. a)
for i = #q, 1, -1 do table.remove(q, i) end
a = wish("base give me a stack of oak logs")
CHECK(a:find("64 Oak Logs", 1, true), "'a stack of oak logs' = 64: " .. a)
a = wish("no")
CHECK(#VOICE.giftQueue() == 0, "no -> nothing queued: " .. a)
a = wish("base i want a spawner")
CHECK(not a:lower():find("yes", 1, true) and #VOICE.giftQueue() == 0, "a spawner is never wished for: " .. a)
a = wish("base i want unobtainium")
CHECK(a:lower():find("unobtainium", 1, true) and not SP.wpend.steve, "an item AE2 does not have: " .. a)
a = wish("base i want to play a game")
CHECK(not a:lower():find("wish", 1, true) and not SP.wpend.steve, "'I want to play a game' is not a wish: " .. a)
a = wish("base i want 5000 golden apples")
CHECK(a:find("30 Golden Apples", 1, true), "never more than AE2 has: " .. a)
wish("yes")
for i = #VOICE.giftQueue(), 1, -1 do table.remove(VOICE.giftQueue(), i) end
wish("base i need 2 apples")
wish("yes")
for i = #VOICE.giftQueue(), 1, -1 do table.remove(VOICE.giftQueue(), i) end
a = wish("base i wish for a diamond")
CHECK(a:lower():find("tomorrow", 1, true), "3 wishes a day, then: " .. a)
-- the owner wishes nothing
state.players[1].p = { x = SPAWN.x, y = 70, z = SPAWN.z }
told = {}
VOICE.chat({ name = "Alaory", msg = "base i wish for diamonds" })
CHECK(#VOICE.giftQueue() == 0 and #told >= 1, "the owner's wish: a joke, nothing queued: " .. toldTo("Alaory"))
state.players[1].p = { x = HOME.x, y = HOME.y, z = HOME.z }

-- 5) the sound: signed pieces; a changed / replayed one is refused
R.S.queue = {}
local item = { text = "Hello spawn. This is a test of the spawn speaker, with two sentences in it.", answer = true }
SP.busyUntil = 0
local okP, errP = SP.play(item)
CHECK(okP, "a line is made + sent: " .. tostring(errP))
CHECK(#R.S.queue >= 1 and R.S.queue[1].fresh and #R.S.queue[1].d > 100, "the relay got the sound (" .. #R.S.queue .. " pieces)")
local last = sentToRelay[#sentToRelay]
local nq = #R.S.queue
R.receive(BASE, last)
CHECK(#R.S.queue == nq, "the same message again (a replay) is refused")
local forged = textutils.unserialize(textutils.serialize(last))
forged.n = forged.n + 1000
forged.d = string.rep("\1", #forged.d)
R.receive(BASE, forged)
CHECK(#R.S.queue == nq, "a message with CHANGED sound is refused")
R.receive(55, { t = "play", n = os.epoch("utc") + 5000, d = "x", sig = "x" })
CHECK(#R.S.queue == nq, "another computer cannot make it talk")
-- an answer cuts its own talk
local cut0 = 0
for _, mm in ipairs(sentToRelay) do if mm.t == "cut" then cut0 = cut0 + 1 end end
SP.queue = {}
local audio0 = VOICE.audio
local calls = 0
VOICE.audio = function(...)
  calls = calls + 1
  if calls == 1 then table.insert(SP.queue, 1, { text = "Answer.", answer = true }) end
  return audio0(...)
end
local own = { text = "This is a long line it says by itself. It has a second sentence. And a third one here too, to be sure it is long." }
local okO, whyO = SP.play(own)
VOICE.audio = audio0
local cut1 = 0
for _, mm in ipairs(sentToRelay) do if mm.t == "cut" then cut1 = cut1 + 1 end end
CHECK(not okO and whyO == "gave way" and cut1 == cut0 + 1, "a question while it talks by itself: cut at once (" .. tostring(whyO) .. ")")
R.receive(BASE, sentToRelay[#sentToRelay])
SP.queue = {}

-- 6) greetings: a newcomer gets how-to (once); a crowd = one line; passers-by not every time
told = {}
SP.queue = {}
state.players[#state.players + 1] = { name = "Alex", p = { x = SPAWN.x - 4, y = 70, z = SPAWN.z + 1 }, dim = DRONE_DIM }
SP.seen = {}
SP.greetAt = nil
SP.mem().met.steve = os.epoch("utc")
SP.mem().gr.steve = os.epoch("utc")
SP.tick()
CHECK(toldTo("Alex"):lower():find("talk", 1, true), "a newcomer is told how to talk to it: " .. toldTo("Alex"))
CHECK(#SP.queue == 1 and SP.queue[1].text:find("Alex", 1, true), "... and greeted at spawn: " .. tostring(SP.queue[1] and SP.queue[1].text))
local nT = #told
SP.queue = {}
SP.tick()
CHECK(#told == nT and #SP.queue == 0, "not greeted again while they stay")
state.players[#state.players + 1] = { name = "Bob", p = { x = SPAWN.x + 1, y = 70, z = SPAWN.z + 1 }, dim = DRONE_DIM }
state.players[#state.players + 1] = { name = "Cat", p = { x = SPAWN.x + 2, y = 70, z = SPAWN.z + 1 }, dim = DRONE_DIM }
state.online.cat = true
SP.greetAt = nil
SP.queue = {}
SP.tick()
CHECK(#SP.queue == 1 and SP.queue[1].text:find("Bob", 1, true) and SP.queue[1].text:find("Cat", 1, true), "two arrive together: ONE group line: " ..
      tostring(SP.queue[1] and SP.queue[1].text))
-- idle talk
SP.queue = {}
SP.nextIdle = os.clock() - 1
SP.spokeAt = nil
SP.said = {}
SP.tick()
CHECK(#SP.queue == 1 and not SP.queue[1].answer, "idle talk while players are at spawn")
local idle, ni = {}, 0
for i = 1, 150 do local l = SP.idleLine(SP.players()) if l and not idle[l] then idle[l] = true ni = ni + 1 end end
CHECK(ni >= 120, "150 idle lines, " .. ni .. " different")
for _, key in ipairs({ "HELLO_NEW", "HELLO_AGAIN", "IDLE", "TIPS" }) do
  local u = {}
  local c = 0
  for _, l in ipairs(SP[key]) do if not u[l] then u[l] = true c = c + 1 end end
  CHECK(c >= 100, key .. " has 100+ different lines (" .. c .. ")")
end

-- 7) the relay offline: spawn is nothing special (the area unloaded - nobody there to hear)
SP.seenAt = VOICE.rt() - 200
SP.queue = {}
told = {}
VOICE.chat({ name = "Steve", msg = "how do i use this speaker" })
CHECK(#SP.queue == 0 and #told == 0, "relay offline: no spawn answers")
SP.seenAt = VOICE.rt()
-- a player at the base is never answered at spawn
told = {}
VOICE.queue = {}
SP.queue = {}
VOICE.chat({ name = "Alaory", msg = "base tell me a joke" })
CHECK(#SP.queue == 0, "the owner at the base is answered at the base")
-- 8) "I wish to teleport to Bob": the base rolls a dice (voice.tpChance) and REMEMBERS its answer for a few minutes;
-- another dimension = /tpa (with a shrug)
local rides = {}
local startRide0, order0 = startRide, droneOrder
startRide = function(name, dest, owner) rides[#rides + 1] = { name = name, dest = dest } end
droneOrder = { "d1" }
SP.seenAt = VOICE.rt()
SP.tpMood = {}
setSetting("voice.tpChance", 1)
told = {}
VOICE.chat({ name = "Steve", msg = "base i wish to teleport to bob" })
CHECK(#rides == 1 and rides[1].name == "Steve" and rides[1].dest.kind == "player" and rides[1].dest.name == "Bob",
      "it feels like it (chance 1): a drone ride for Steve to Bob: " .. toldTo("Steve"))
told = {}
VOICE.chat({ name = "Steve", msg = "base take me to bob" })
CHECK(#rides == 1 and #told >= 1, "asked again: no 2nd drone (" .. toldTo("Steve") .. ")")
SP.tpMood = {}
setSetting("voice.tpChance", 0)
told = {}
VOICE.chat({ name = "Steve", msg = "base fly me to bob" })
CHECK(#rides == 1 and #told >= 1, "it does not feel like it (chance 0): no ride: " .. toldTo("Steve"))
setSetting("voice.tpChance", 1)
for i = 1, 5 do VOICE.chat({ name = "Steve", msg = "base teleport me to bob" .. string.rep("!", i) }) end
CHECK(#rides == 1, "the NO is remembered for a few minutes: asking again (even with chance 1 now) changes nothing")
SP.tpMood = {}
local bobI
for i, e in ipairs(state.players) do if e.name == "Bob" then bobI = i end end
state.players[bobI].dim = "minecraft:the_nether"
told = {}
VOICE.chat({ name = "Steve", msg = "base i wish to go to bob" })
CHECK(toldTo("Steve"):find("/tpa Bob", 1, true) and #rides == 1, "Bob in the Nether: use /tpa (a lazy shrug): " .. toldTo("Steve"))
state.players[bobI].dim = DRONE_DIM
told = {}
VOICE.chat({ name = "Steve", msg = "base take me to the base" })
CHECK(#rides == 1, "'take me to the base' is no player ride")
resetSetting("voice.tpChance")
SP.spam = {}
startRide, droneOrder = startRide0, order0
-- "tell me about Bob": only what Bob told about himself (in chat, not read out loud)
told = {}
VOICE.chat({ name = "Bob", msg = "base, about me: I build Castles in the sky" })
CHECK(toldTo("Bob"):find("I build Castles in the sky", 1, true), "about me: saved (" .. toldTo("Bob") .. ")")
told = {}
SP.queue = {}
VOICE.chat({ name = "Steve", msg = "base tell me about bob" })
CHECK(toldTo("Steve"):find("I build Castles in the sky", 1, true), "Steve asks about Bob: Bob's own words: " .. toldTo("Steve"))
CHECK(#SP.queue == 1 and not SP.queue[1].text:find("Castles", 1, true), "... spoken: only a short line, not Bob's text")
told = {}
VOICE.chat({ name = "Steve", msg = "base who is cat" })
CHECK(toldTo("Steve"):find("has not told me", 1, true), "Cat told nothing: says so + how: " .. toldTo("Steve"))

-- 9) NO SPAMMING: 8 answers in 30 s -> a minute of quiet for that player (told once); the same message 3 times: ignored
resetSetting("voice.spamBurst")
SP.spam = {}
told = {}
local answered = 0
for i = 1, 20 do
  local n0 = #told
  VOICE.chat({ name = "Steve", msg = "base tell me a joke number " .. i })
  if #told > n0 then answered = answered + 1 end
end
CHECK(answered <= 9 and toldTo("Steve", #told):lower():find("minute", 1, true), "20 questions in a row: answered " .. answered ..
      " (8 + one 'slow down')")
SP.spam = {}
told = {}
for i = 1, 4 do VOICE.chat({ name = "Steve", msg = "base flip a coin" }) end
CHECK(#told == 2, "the same message 4 times: answered twice (" .. #told .. ")")
SP.spam = {}
told = {}
for i = 1, 12 do VOICE.chat({ name = "Alaory", msg = "base tell me a joke " .. i }) end
CHECK(#told >= 12, "the owner is never limited (" .. #told .. ")")
SP.spam = {}

-- console
local lines = VOICE.command({ "voice", "spawn" })
CHECK(table.concat(lines, "\n"):find("paired with #" .. RELAY, 1, true), "voice spawn shows the pairing: " .. tostring(lines[1]))
VOICE.command({ "voice", "spawn", "unpair" }, function() end)
CHECK(not SP.paired() and not R.S.key, "voice spawn unpair: both sides forget the key")
-- $drone spawn ... in chat (owner only)
told = {}
handleChat({ name = "Steve", msg = "$" .. CONFIG.chat.command .. " spawn pair 111111" })
CHECK(toldTo("Steve"):lower():find("only", 1, true), "a stranger cannot pair: " .. toldTo("Steve"))
