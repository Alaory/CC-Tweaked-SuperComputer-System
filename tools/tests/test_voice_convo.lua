-- CONVERSATIONS (voice_convo.lua; the owner: "players just say hi or hello and don't know what to say - I want it to have
-- long conversations" + "an information system where it remembers what a player likes - players do talk about mods").
-- Real voice files from floppies, players at the base, chat replayed through VOICE.chat (as in game).
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
CONFIG.voice = CONFIG.voice or {}
CONFIG.voice.detector = false
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
local okL, errL = pcall(loadVoiceChain)
CHECK(okL and VOICE and VOICE.CONVO, "the voice chain + the conversation pack load: " .. tostring(errL))
local V, C = VOICE, VOICE.CONVO
CONFIG.voice.spamBurst, CONFIG.voice.spamSame = 100000, 0      -- (the spam limit is tested in test_spawn; this test chats fast)
state.owner = "Alaory"
local function world(...)
  state.players, state.online = {}, {}
  for i, n in ipairs({ ... }) do
    state.players[#state.players + 1] = { name = n, p = { x = HOME.x + i, y = HOME.y, z = HOME.z }, dim = DRONE_DIM }
    state.online[n:lower()] = true
  end
end
local told, spoken = {}, {}
chatTell = function(who, text) told[#told + 1] = { who = who, text = tostring(text) } end
local say0 = V.say
V.say = function(text) spoken[#spoken + 1] = tostring(text) return true end
local function say(who, msg)
  local n0 = #told
  local ok, err = pcall(V.chat, { name = who, msg = msg })
  CHECK(ok, "'" .. msg .. "' - no error: " .. tostring(err))
  local out = {}
  for i = n0 + 1, #told do if told[i].who == who then out[#out + 1] = told[i].text end end
  local c = table.concat(out, " | ")
  CHECK(not c:find("{", 1, true) and not c:find("attempt to", 1, true), "'" .. msg .. "': no unfilled / error text: " .. c)
  return c
end
local function asks(c) return c:find("?", 1, true) ~= nil end
local function lowc(s) return tostring(s):lower() end
local function fresh(...)
  V.convo, V.pend, V.games, V.chatAt, V.talkingTo = {}, {}, {}, {}, {}
  C.state = {}
  world(...)
end
local MENU = "type a number"

-- 1) "hi" starts a chat: a greeting AND a question (the old base: "Good afternoon, Steve." and nothing to answer)
fresh("Steve")
local c = say("Steve", "hi")
CHECK(asks(c) and V.pend.steve and V.pend.steve.kind == "react", "'hi' -> a greeting and a question it waits for: " .. c)
CHECK(not lowc(c):find(MENU, 1, true), "no numbered menu for a hello: " .. c)
for _, g in ipairs({ "hello", "hey base", "hiii", "yo", "sup", "hello there", "good morning", "hey everyone", "howdy", "heyyy" }) do
  fresh("Steve")
  local cg = say("Steve", g)
  CHECK(asks(cg) and V.pend.steve, "'" .. g .. "' starts a chat with a question: " .. cg)
end
-- 2) LONG: 30 answers of all kinds - every one gets a reaction and a NEW question; no menu; several topics
fresh("Steve")
say("Steve", "hello")
local ANSWERS = { "good thanks", "building a castle", "yeah", "deepslate mostly", "a huge tower", "no not really", "caves",
  "creepers lol", "phantoms", "yes i have a cat", "steak", "pizza", "cookies", "pretty far", "not yet", "the nether", "create",
  "maybe 2 weeks", "the people", "my brother", "yes", "minecraft only", "tech", "i dunno", "yes a dog", "Rex", "flying",
  "buy a mansion", "cherry grove", "i love it here" }
local topics, qs = {}, {}
for i, a in ipairs(ANSWERS) do
  local ca = say("Steve", a)
  CHECK(ca ~= "", "answer " .. i .. " '" .. a .. "' got a reply")
  CHECK(asks(ca) and V.pend.steve, "answer " .. i .. " '" .. a .. "' -> the chat goes on with a question: " .. ca)
  CHECK(not lowc(ca):find(MENU, 1, true), "answer " .. i .. ": no menu: " .. ca)
  local st = C.state.steve
  if st and st.topic then topics[st.topic] = true end
  qs[ca] = true
end
local nt = 0
for _ in pairs(topics) do nt = nt + 1 end
CHECK(nt >= 5, "30 answers walk through 5+ topics: " .. nt)
-- 3) it says back what they said ("a castle")
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "building")
local cb = say("Steve", "i am building a big castle")
CHECK(lowc(cb):find("big castle", 1, true), "it repeats the answer back: " .. cb)
-- 4) "what about you" = its own answer, then the question back; "bye" ends it
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "mobs")
local cm = say("Steve", "what about you?")
CHECK(asks(cm) and (lowc(cm):find("axolotl", 1, true) or lowc(cm):find("turtles", 1, true) or lowc(cm):find("me?", 1, true) or
      lowc(cm):find("my answer", 1, true)), "what about you -> its own answer + the question back: " .. cm)
local cbye = say("Steve", "bye")
CHECK(not V.pend.steve and (lowc(cbye):find("bye", 1, true) or lowc(cbye):find("see you", 1, true) or lowc(cbye):find("talk soon", 1, true) or
      lowc(cbye):find("next time", 1, true) or lowc(cbye):find("chat", 1, true)), "bye ends the chat: " .. cbye)
-- 5) answers with stop words in them are answers ("busy with my farm", "I'll do it later")
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "day")
local cl = say("Steve", "busy with my farm")
CHECK(V.pend.steve and asks(cl), "'busy with my farm' is an answer, not a stop: " .. cl)
local cl2 = say("Steve", "i will do it later today")
CHECK(V.pend.steve and asks(cl2), "'i will do it later today' is an answer: " .. cl2)
-- 6) a real question in the middle is answered, then the chat goes on
fresh("Steve")
say("Steve", "hi")
local cq = say("Steve", "what time is it?")
CHECK(V.pend.steve and asks(cq), "a question mid-chat is answered and the chat goes on: " .. cq)
-- 7) rude words are never said back
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "building")
local cr = say("Steve", "a fucking castle")
CHECK(not lowc(cr):find("fuck", 1, true) and V.pend.steve, "a rude answer: not repeated, asked again: " .. cr)
-- 8) lazy answers -> it asks whether to go on
fresh("Steve")
say("Steve", "hi")
local last
for _ = 1, 3 do last = say("Steve", "idk") end
CHECK(lowc(last):find("type yes", 1, true), "three 'idk' in a row -> asks whether to go on: " .. last)
local cy = say("Steve", "yes")
CHECK(asks(cy) and V.pend.steve and V.pend.steve.kind == "react", "yes -> the chat goes on: " .. cy)
-- 9) how are you / I'm bored / let's talk / ask me something
for _, m in ipairs({ "how are you", "hru", "hey base how are you doing", "im bored", "lets talk", "ask me something", "can we chat",
                     "entertain me", "lets talk about mobs" }) do
  fresh("Steve")
  local ch = say("Steve", m)
  CHECK(asks(ch) and V.pend.steve, "'" .. m .. "' starts a chat: " .. ch)
end
fresh("Steve")
say("Steve", "lets talk about food")
CHECK(C.state.steve.topic == "food", "'lets talk about food' -> the food topic: " .. tostring(C.state.steve.topic))
-- 10) variety: 50 hellos -> 40+ different openers
local seen, n = {}, 0
for _ = 1, 50 do
  fresh("Steve")
  local ch = say("Steve", "hi")
  local first = ch:match("^(.-[%.!%?])") or ch
  if not seen[first] then seen[first] = true n = n + 1 end
end
CHECK(n >= 12, "50 hellos: " .. n .. " different first sentences")
local all = {}
local na = 0
for _ = 1, 50 do fresh("Steve") local ch = say("Steve", "hi") if not all[ch] then all[ch] = true na = na + 1 end end
CHECK(na >= 45, "50 hellos: " .. na .. " different whole greetings")

-- ===== WHAT THEY LIKE =====
-- 11) favourite answers are remembered, and come back later
fresh("Steve")
V.mem().steve = nil
say("Steve", "hi")
C.begin("Steve", C.state.steve, "mobs")
say("Steve", "the axolotl")
local r = V.mem().steve
CHECK(r and r.fav and r.fav.mob == "axolotl", "the favourite mob is remembered: " .. tostring(r and r.fav and r.fav.mob))
local recalled = false
for _ = 1, 40 do
  fresh("Steve")
  local ch = say("Steve", "hello")
  if lowc(ch):find("axolotl", 1, true) then recalled = true break end
end
CHECK(recalled, "a later hello brings the axolotl up again")
-- 12) "I like X" / "I hate X" anywhere at the base: remembered; "what do I like" lists it
fresh("Steve")
say("Steve", "base i like trains")
say("Steve", "base i hate phantoms")
r = V.mem().steve
local hasLike = false
for _, v in ipairs(r.likes or {}) do if v == "trains" then hasLike = true end end
local hasHate = false
for _, v in ipairs(r.hates or {}) do if v == "phantoms" then hasHate = true end end
CHECK(hasLike and hasHate, "likes + dislikes remembered: likes " .. table.concat(r.likes or {}, ",") .. " hates " .. table.concat(r.hates or {}, ","))
fresh("Steve")
local cw = say("Steve", "base what do i like")
CHECK(lowc(cw):find("trains", 1, true) and lowc(cw):find("phantoms", 1, true) and lowc(cw):find("axolotl", 1, true),
      "'what do I like' lists likes, dislikes and favourites: " .. cw)
-- "i like it" / "i like you" / a player's name are not things it remembers
local nl = #(V.mem().steve.likes or {})
world("Steve", "Alex")
say("Steve", "base i like it")
say("Steve", "base i like you")
say("Steve", "base i like alex")
CHECK(#(V.mem().steve.likes or {}) == nl, "'it' / 'you' / another player are not likes: " .. table.concat(V.mem().steve.likes or {}, ","))
-- liking it again after hating: moves over
fresh("Steve")
say("Steve", "base i like phantoms")
hasHate = false
for _, v in ipairs(V.mem().steve.hates or {}) do if v == "phantoms" then hasHate = true end end
CHECK(not hasHate, "liked after all: off the dislike list")
-- in pack 2's "what do you know about me" too
local ck = say("Steve", "base what do you know about me")
CHECK(lowc(ck):find("trains", 1, true), "'what do you know about me' includes the likes: " .. ck)
-- passive: chat near the base that is not for the base still teaches it (no answer)
fresh("Steve", "Alex")
V.mem().alex = V.mem().alex or {}
local n0 = #told
pcall(V.chat, { name = "Alex", msg = "honestly i love cherry trees" })
local likesA = table.concat(V.mem().alex.likes or {}, ",")
CHECK(likesA:find("cherry trees", 1, true), "overheard 'I love cherry trees' is remembered: " .. likesA)

-- ===== MODS =====
fresh("Steve")
local cm1 = say("Steve", "base do you like create?")
CHECK(lowc(cm1):find("create", 1, true) and asks(cm1) and V.pend.steve, "'do you like create' -> its opinion + a Create question: " .. cm1)
fresh("Steve")
local cm2 = say("Steve", "base i love mekanism")
CHECK(lowc(cm2):find("mekanism", 1, true) and asks(cm2), "'I love mekanism' -> a reaction + a question: " .. cm2)
local mods = V.mem().steve.mods or {}
CHECK(mods.Mekanism and mods.Mekanism.l == true, "Mekanism remembered as liked")
fresh("Steve")
local cm3 = say("Steve", "base what is your favourite mod")
CHECK(lowc(cm3):find("cc:tweaked", 1, true) and asks(cm3), "favourite mod -> its own + asks theirs: " .. cm3)
local cm4 = say("Steve", "probably botania")
CHECK(lowc(cm4):find("botania", 1, true) and V.mem().steve.fav.mod == "Botania", "their answer names the mod; saved as favourite: " .. cm4)
local cm5 = say("Steve", "base thoughts on ae2?")
CHECK(lowc(cm5):find("ae2", 1, true), "thoughts on ae2 (mid-chat): " .. cm5)
-- lore questions are still the lore pack's ("what is create" / "create tips")
fresh("Steve")
local cl3 = say("Steve", "base create tips")
CHECK(not (V.pend.steve and V.pend.steve.convo), "'create tips' stays a lore answer: " .. cl3)
-- "create" as a word is not the mod; the mod talk between players gets a spoken comment now and then
fresh("Steve", "Alex")
C.chimeChance, C.chimeAll, C.chimeAt = 1, nil, {}
spoken = {}
pcall(V.chat, { name = "Alex", msg = "lets create a new farm" })
CHECK(#spoken == 0, "'create a new farm' is no mod talk: " .. table.concat(spoken, " | "))
pcall(V.chat, { name = "Alex", msg = "steve have you tried the create mod yet" })
CHECK(#spoken == 1 and lowc(spoken[1]):find("create", 1, true), "players talking about the Create mod: one spoken comment: " .. table.concat(spoken, " | "))
pcall(V.chat, { name = "Steve", msg = "yeah create mod is great" })
CHECK(#spoken == 1, "... and not again right away")
local am = V.mem().alex.mods or {}
CHECK(am.Create and am.Create.c >= 1, "the mod Alex talked about is remembered")
setSetting("voice.modChat", false)
C.chimeAll, C.chimeAt = nil, {}
pcall(V.chat, { name = "Alex", msg = "i really like mekanism" })
CHECK(#spoken == 1, "voice modchat off: no comment")
setSetting("voice.modChat", true)
C.chimeChance = nil

-- 13) talking to another player mid-chat ends it quietly
fresh("Steve", "Alex")
V.chatAt = {}
say("Steve", "base hi")
local cx = say("Steve", "alex come here")
CHECK(cx == "" and not (V.pend.steve and V.pend.steve.convo), "naming another player ends the chat quietly: " .. cx)
-- ... but naming a friend as the ANSWER to "who do you play with" is an answer
fresh("Steve", "Alex")
say("Steve", "base hi")
C.begin("Steve", C.state.steve, "server")
C.state.steve.i = 3
local cf = say("Steve", "alex")
CHECK(asks(cf) and lowc(cf):find("alex", 1, true), "'who do you play with' -> 'alex' is the answer: " .. cf)

-- 14) FUZZ: 300 random answers in a row - always a reply, never an error, never a menu
fresh("Steve")
say("Steve", "hi")
local WORDS = { "yes", "no", "idk", "lol", "creeper", "castle", "what", "you", "?", "good", "bad", "maybe", "i like", "the", "base",
  "create", "mekanism", "stop", "later", "busy", "skip", "next", "what about you", "how are you", "my", "favourite", "is", "pizza",
  "!!!", "%", "(", "[[", "alex", "do you", "i think", "a", "very", "big", "farm", "ok", "k", "hmm", "1", "64", "nether" }
local broke = 0
for i = 1, 300 do
  local m = {}
  for _ = 1, math.random(1, 6) do m[#m + 1] = WORDS[math.random(1, #WORDS)] end
  local msg = table.concat(m, " ")
  if not (V.pend.steve) then say("Steve", "hi") end
  local cz = say("Steve", msg)
  if lowc(cz):find(MENU, 1, true) and V.pend.steve and V.pend.steve.convo then broke = broke + 1 end
end
CHECK(broke == 0, "300 random answers: no menu inside a chat (" .. broke .. ")")
V.say = say0

-- 15) JUST ITS NAME ("sparky" - the owner: "players sometimes just mention the name"): like a person + a question, no menu
setSetting("voice.name", "sparky")
for _, m in ipairs({ "sparky", "sparky?", "SPARKY!", "sparky...", "sparkyy" }) do
  fresh("Steve")
  local cn = say("Steve", m)
  CHECK(asks(cn) and V.pend.steve and V.pend.steve.convo and not lowc(cn):find(MENU, 1, true), "'" .. m .. "' alone -> 'you called?' + a question: " .. cn)
end
fresh("Steve")
say("Steve", "sparky")
local q1 = C.state.steve.asked
local cn2 = say("Steve", "sparky")
CHECK(cn2:find(q1, 1, true), "the name again mid-chat: the same question again: " .. cn2)
local seenC, nC = {}, 0
for _ = 1, 40 do fresh("Steve") local cn = say("Steve", "sparky") local f = cn:match("^(.-[%.!%?])") or cn if not seenC[f] then seenC[f] = true nC = nC + 1 end end
CHECK(nC >= 15, "40 calls by name: " .. nC .. " different answers")
setSetting("voice.name", "base")
-- 16) a command mid-chat is the base's own answer, and the chat stops
fresh("Alaory")
say("Alaory", "base hi")
local cs = say("Alaory", "base say hello world")
CHECK(cs == "hello world" and not (V.pend.alaory and V.pend.alaory.convo), "a command mid-chat: its own answer, the chat stops: " .. cs)
-- 17) another player chats after its question: the next message is for them, not an answer
fresh("Steve", "Alex")
V.chatAt = {}
say("Steve", "base hi")
CLOCK = (CLOCK or 0) + 1
pcall(V.chat, { name = "Alex", msg = "anyone want to trade" })
local co = say("Steve", "sure what do you have")
CHECK(co == "", "Alex spoke after the question: Steve's message is for Alex: " .. co)
-- 18) an answer + asking back ("good u?"): a reaction, its own answer, the next question (not the same one again)
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "mobs")
local qa = C.state.steve.asked
local cu = say("Steve", "creepers wbu")
CHECK(asks(cu) and not cu:find(qa, 1, true) and (lowc(cu):find("axolotl", 1, true) or lowc(cu):find("turtles", 1, true)),
      "'creepers wbu' -> reaction + its own answer + the next question: " .. cu)
-- 19) a mod mid-chat: the chat goes to that mod
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "food")
local cmc = say("Steve", "base i love create")
CHECK(lowc(cmc):find("create", 1, true) and C.state.steve.topic == "mods", "'i love create' mid-chat -> a chat about Create: " .. cmc)
-- 20) NAMES WITHOUT NUMBERS (the owner: "stop it from mentioning numbers in players' names - deadman213, 125steve1, 1alex2steve")
CHECK(V.cleanName("deadman213") == "deadman" and V.cleanName("125steve1") == "steve" and V.cleanName("1alex2steve") == "alex steve" and
      V.cleanName("Dark_Knight_7") == "Dark Knight" and V.cleanName("12345") == "friend", "clean names: " .. V.cleanName("1alex2steve"))
for _, n in ipairs({ "deadman213", "125steve1", "1alex2steve", "Dark_Knight_7" }) do
  fresh(n)
  spoken = {}
  local cd = say(n, "hi")
  CHECK(cd ~= "" and not cd:find("%d") and not cd:find(n, 1, true), n .. ": no digits / raw name in the answer: " .. cd)
  for _, l in ipairs(spoken) do CHECK(not l:find("%d"), n .. ": nothing spoken with digits: " .. l) end
end
-- spoken: an answer for one of two players starts with the CLEAN name, once
V.say = function(text) spoken[#spoken + 1] = V.cleanNames(text) return true end
fresh("deadman213", "Alex")
spoken = {}
say("deadman213", "base what time is it")
local sp1 = table.concat(spoken, " | ")
CHECK(not sp1:find("213", 1, true), "spoken answer with others near: no digits: " .. sp1)
state.players = { { name = "125Steve1" }, { name = "deadman213" } }
CHECK(V.cleanNames("Hi deadman213 and 125steve1!") == "Hi deadman and Steve!", "names in a text cleaned (any case): " .. V.cleanNames("Hi deadman213 and 125steve1!"))
CHECK(V.cleanNames("x 100, y 64") == "x 100, y 64", "other numbers stay")
-- a nickname they chose is said as it is
V.mem()["deadman213"] = { nick = "R2D2" }
CHECK(V.fill("Hi {name}!", "deadman213") == "Hi R2D2!", "a chosen nickname stays: " .. V.fill("Hi {name}!", "deadman213"))
V.say = say0
-- 21) REVIEW: answers that start with a verb are answers ("play with my friends" opened the games menu)
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "day")
C.state.steve.i = 3
local cv = say("Steve", "play with my friends")
CHECK(asks(cv) and V.pend.steve and V.pend.steve.convo and not lowc(cv):find(MENU, 1, true), "'play with my friends' is an answer: " .. cv)
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "day")
local cv2 = say("Steve", "find diamonds and build a house")
CHECK(asks(cv2) and V.pend.steve and V.pend.steve.convo, "'find diamonds and build a house' is an answer: " .. cv2)
local cv3 = say("Steve", "next to my house in the forest")
CHECK(asks(cv3) and not lowc(cv3):find("skipping", 1, true) and not lowc(cv3):find("skip that", 1, true), "'next to my house ...' is an answer, not a skip: " .. cv3)
-- "create" as a word, "my backpack": no mod talk
fresh("Steve")
say("Steve", "hi")
C.begin("Steve", C.state.steve, "building")
say("Steve", "i like to create stuff")
CHECK(C.state.steve.topic ~= "mods", "'i like to create stuff' is not the Create mod")
fresh("Steve")
local cb2 = say("Steve", "base do you like my backpack")
CHECK(not lowc(cb2):find("sophisticated", 1, true) and not (C.state.steve and C.state.steve.topic == "mods"), "'do you like my backpack' is not the mod: " .. cb2)
-- rude: "hoe" is a tool; "fuuuck" is rude
CHECK(not C.isBad({ "a", "diamond", "hoe" }, " a diamond hoe "), "a diamond hoe is not rude")
CHECK(not C.isBad({ "rapeseed" }, " rapeseed ") and not C.isBad({ "cocktail" }, " cocktail "), "rapeseed / cocktail are not rude")
CHECK(C.isBad(V.norm("fuuuuck"), " " .. table.concat(V.norm("fuuuuck"), " ") .. " "), "fuuuuck is rude")
-- "hi" mid-chat: hello back + the same question
fresh("Steve")
say("Steve", "hi")
local qh = C.state.steve.asked
local ch2 = say("Steve", "hello")
CHECK(ch2:find(qh, 1, true) and not ch2:find("Hello?", 1, true), "'hello' mid-chat: hello back + the same question: " .. ch2)
-- a far player: no chat started (it could never answer), the old answers instead
fresh("Alaory")
state.players = { { name = "Alaory", p = { x = HOME.x + 5000, y = HOME.y, z = HOME.z }, dim = DRONE_DIM } }
local cfar = say("Alaory", "base hi")
CHECK(not (V.pend.alaory and V.pend.alaory.convo), "far away: 'base hi' starts no chat: " .. cfar)
local cfar2 = say("Alaory", "base")
CHECK(not (V.pend.alaory and V.pend.alaory.convo), "far away: just the name starts no chat: " .. cfar2)
-- other players chatting FAR away do not end the chat
fresh("Steve", "Alex")
state.players[2].p = { x = HOME.x + 5000, y = HOME.y, z = HOME.z }
say("Steve", "base hi")
CLOCK = (CLOCK or 0) + 1
pcall(V.chat, { name = "Alex", msg = "anyone want to trade" })
local cfa = say("Steve", "pretty good")
CHECK(asks(cfa) and V.pend.steve and V.pend.steve.convo, "someone far away chatting does not end the chat: " .. cfa)
-- likes said mid-chat are remembered
fresh("Steve")
say("Steve", "hi")
say("Steve", "i love sunflowers")
local hasSun = false
for _, v in ipairs(V.mem().steve.likes or {}) do if v == "sunflowers" then hasSun = true end end
CHECK(hasSun, "a like said mid-chat is remembered")
-- 22) every question is a question; the text cleaner squashes stretched words (it never did: "(%a)%1%1+" is not a Lua repeat)
local notQ = {}
for key, steps in pairs(C.TOPICS) do
  for _, st in ipairs(steps) do for _, q in ipairs(st.q or {}) do if not q:find("%?%s*$") then notQ[#notQ + 1] = key .. ": " .. q end end end
end
for _, p in ipairs(C.PAIRS) do if not p[1]:find("%?%s*$") then notQ[#notQ + 1] = "pair: " .. p[1] end end
CHECK(#notQ == 0, "every question ends in '?': " .. table.concat(notQ, " | "))
CHECK(table.concat(V.norm("hellooooo yesssss hiiiii"), " ") == "helloo yess hi", "stretched words squashed: " .. table.concat(V.norm("hellooooo yesssss hiiiii"), " "))
-- 23) STAFF (the owner: "variant speeches for admins / moderators"): a list the owner keeps
local slog = {}
V.commands.staff({ "voice", "staff", "add", "ModMax", "mod" }, function(x) slog[#slog + 1] = x end)
V.commands.staff({ "voice", "staff", "add", "AdminAnna", "admin" }, function(x) slog[#slog + 1] = x end)
CHECK(C.roleOf("modmax") == "mod" and C.roleOf("AdminAnna") == "admin" and not C.roleOf("Steve"), "voice staff add: roles kept")
-- a staff member saying hi: their own greeting + the staff topic
fresh("ModMax")
local cs1 = say("ModMax", "hi")
CHECK(asks(cs1) and (lowc(cs1):find("mod", 1, true)) and C.state.modmax.topic == "staff", "a moderator saying hi: a moderator greeting + the staff topic: " .. cs1)
fresh("AdminAnna")
local cs2 = say("AdminAnna", "base")
CHECK(asks(cs2) and lowc(cs2):find("admin", 1, true), "an admin calling its name: an admin greeting: " .. cs2)
-- 50 greetings for a moderator: many different ones
local sv, nsv = {}, 0
for _ = 1, 50 do fresh("ModMax") local g = say("ModMax", "hello") if not sv[g] then sv[g] = true nsv = nsv + 1 end end
CHECK(nsv >= 40, "50 moderator greetings: " .. nsv .. " different")
CHECK(#C.STAFF_HELLO.admin >= 100 and #C.STAFF_HELLO.mod >= 100, "100+ admin / moderator greetings")
-- arriving at the base: the staff greeting, never the stranger alarm
fresh("ModMax")
spoken = {}
V.say = function(text) spoken[#spoken + 1] = tostring(text) return true end
V.greet("ModMax")
CHECK(#spoken == 1 and lowc(spoken[1]):find("mod", 1, true) and not lowc(spoken[1]):find("intruder", 1, true), "arriving: the moderator greeting: " .. table.concat(spoken, " | "))
-- who are the staff / am I staff / I am an admin
fresh("Steve")
local cw1 = say("Steve", "base who are the admins?")
CHECK(cw1:find("AdminAnna", 1, true) or cw1:find("adminanna", 1, true), "who are the admins: " .. cw1)
fresh("Steve")
local cw2 = say("Steve", "base i am an admin")
CHECK(not lowc(cw2):find("i know", 1, true) and (lowc(cw2):find("list", 1, true) or lowc(cw2):find("try", 1, true) or lowc(cw2):find("no", 1, true)), "a stranger claiming admin: nice try: " .. cw2)
fresh("ModMax")
local cw3 = say("ModMax", "base am i a mod")
CHECK(lowc(cw3):find("moderator", 1, true), "am I a mod: " .. cw3)
-- the owner in chat: "Steve is a moderator" (a known player), "make Bob an admin", "Steve is not staff"; others cannot
fresh("Alaory", "Steve")
local co1 = say("Alaory", "base steve is a moderator")
CHECK(C.roleOf("Steve") == "mod" and co1:find("Steve", 1, true), "the owner: 'steve is a moderator': " .. co1)
local co2 = say("Alaory", "base this is a mod")
CHECK(not C.roleOf("this"), "'this is a mod' adds nobody: " .. co2)
local co3 = say("Alaory", "base steve is not staff")
CHECK(not C.roleOf("Steve"), "the owner: 'steve is not staff': " .. co3)
fresh("Steve", "Alex")
local co4 = say("Steve", "base alex is an admin")
CHECK(not C.roleOf("Alex") and lowc(co4):find("only", 1, true), "a player cannot add staff: " .. co4)
V.commands.staff({ "voice", "staff", "remove", "ModMax" }, function() end)
CHECK(not C.roleOf("ModMax"), "voice staff remove")
V.say = say0
