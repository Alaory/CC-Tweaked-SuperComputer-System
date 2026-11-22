-- HOW EACH PLAYER PLAYS (voice_profile.lua; the owner: "a detection system: when a player tells the base what they like to do it adapts -
-- like they love tech mods but spend most of their time watching tutorials, or ones who like to build but get burned out").
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
  local k = 20 + i
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
local P = V.PROFILE
CHECK(P and V.packs["voice_profile.lua"], "the profile pack loads")
local function prof(n) return P.prof(n) or { i = {}, s = {} } end
local function hasAny(text, list) for _, l in ipairs(list) do if text:find(l, 1, true) then return true end end return false end
local function tips(key) local out = {} for _, l in ipairs(P.TIP2[key] or {}) do out[#out + 1] = l end return out end

-- 1) the owner's example: loves tech mods, watches tutorials
fresh("Steve")
V.mem().steve = nil
local c1 = say("Steve", "base i love tech mods but i spend most of my time watching tutorials")
CHECK(hasAny(c1, tips("tutorials+tech")), "tech + tutorials: the tip for BOTH: " .. c1)
CHECK(lowc(c1):find("tech mods", 1, true) and lowc(c1):find("tutorials", 1, true), "... and it says what it understood: " .. c1)
CHECK((prof("Steve").i.tech or 0) >= 2 and prof("Steve").s.tutorials, "learned: tech mods + tutorials")
CHECK(asks(c1) and V.pend.steve and V.pend.steve.convo, "... and a chat goes on: " .. c1)
local tt = C.state.steve.topic
CHECK(tt == "prof_tech" or tt == "mods" or tt == "redstone", "... about tech: " .. tostring(tt))
-- 2) the other example: likes building, burns out
fresh("Kim")
V.mem().kim = nil
local c2 = say("Kim", "base i like to build but i always get burned out")
CHECK(hasAny(c2, tips("burnout+build")), "building + burnout: the tip for BOTH: " .. c2)
CHECK((prof("Kim").i.build or 0) >= 2 and prof("Kim").s.burnout, "learned: building + burnout")
CHECK(C.state.kim.topic == "prof_build", "... a chat for a builder: " .. tostring(C.state.kim.topic))
-- 3) CHECK-IN later: "how is your motivation now?" - better = solved; still bad = a tip, kept
prof("Kim").s.burnout.at = os.epoch("utc") - 86400000
local checked = false
for _ = 1, 30 do
  fresh("Kim")
  local ck = say("Kim", "hello")
  if C.state.kim.topic == "checkin_burnout" then checked = true break end
end
CHECK(checked, "a later hello: a check-in on the burnout")
local ck2 = say("Kim", "yes still burned out")
CHECK(prof("Kim").s.burnout and lowc(ck2):find("tip", 1, true), "still burned out: a tip, still remembered: " .. ck2)
prof("Kim").s.burnout.at = os.epoch("utc") - 86400000
checked = false
for _ = 1, 30 do fresh("Kim") say("Kim", "hello") if C.state.kim.topic == "checkin_burnout" then checked = true break end end
local ck3 = say("Kim", "much better now")
CHECK(checked and not prof("Kim").s.burnout, "better now: the burnout is forgotten: " .. ck3)
-- 4) conversations lean to what they love
local techT = 0
for _ = 1, 20 do
  fresh("Steve")
  prof("Steve").s = {}
  say("Steve", "hi")
  local tp = C.state.steve.topic
  if tp == "prof_tech" or tp == "mods" or tp == "redstone" then techT = techT + 1 end
end
CHECK(techT >= 8, "a tech player: tech topics in " .. techT .. " of 20 chats (a random one would be ~3)")
-- 5) what kind of player am I / what should I do / what do you know about me
prof("Steve").s.tutorials = { n = 1, at = os.epoch("utc"), first = os.epoch("utc") }
fresh("Steve")
local c5 = say("Steve", "base what kind of player am i")
CHECK(lowc(c5):find("tech player", 1, true) and lowc(c5):find("tutorials", 1, true), "what kind of player am I: " .. c5)
local c6 = say("Steve", "base what should i do")
local todo = false
for _, l in ipairs(P.TODO.tech) do if c6:find(l, 1, true) then todo = true end end
CHECK(todo and c6:find("No videos", 1, true), "what should I do: a tech idea, the tutorial habit in mind: " .. c6)
local c7 = say("Steve", "base what do you know about me")
CHECK(lowc(c7):find("tech player", 1, true), "what do you know about me includes it: " .. c7)
-- 6) mid-chat: an answer that tells a struggle gets understanding + a tip, then the chat goes on
fresh("Zed")
V.mem().zed = nil
say("Zed", "hi")
local c8 = say("Zed", "i dont know what to build honestly")
CHECK(lowc(c8):find("tip", 1, true) and asks(c8) and prof("Zed").s.noideas, "mid-chat 'I don't know what to build': a tip + the next question: " .. c8)
-- the tech topic's "how do you learn" -> videos = the tutorial habit noted (and no "table: 0x" text)
fresh("Zed")
say("Zed", "hi")
C.begin("Zed", C.state.zed, "prof_tech")
C.state.zed.i = 3
local c9 = say("Zed", "mostly youtube videos")
CHECK(prof("Zed").s.tutorials and not c9:find("table:", 1, true) and lowc(c9):find("video", 1, true), "learning from videos: noted, a tip: " .. c9)
-- 7) overheard near the base (not for it): learned quietly
fresh("Alex", "Steve")
V.mem().alex = V.mem().alex or {}
local n0 = #told
pcall(V.chat, { name = "Alex", msg = "steve honestly i get burned out on building so fast" })
CHECK(prof("Alex").s.burnout, "overheard: the burnout is learned")
local toAlex = 0
for i = n0 + 1, #told do if told[i].who == "Alex" then toAlex = toAlex + 1 end end
CHECK(toAlex == 0, "... without an answer to a chat that was not for it")
-- 8) no misfires
fresh("Rob")
V.mem().rob = {}
for _, m in ipairs({ "base the drone is too slow", "base i just started a new build", "base i had to start over because i died",
                     "base i like it", "base how do i play hangman" }) do
  say("Rob", m)
end
local any = false
for _ in pairs(prof("Rob").s) do any = true end
CHECK(not any, "no struggle from 'the drone is too slow' / 'I just started a new build' / 'start over' ...")
-- 9) "I love mekanism": the mod talk still answers; the tech interest is learned too
fresh("Mia")
V.mem().mia = nil
local c10 = say("Mia", "base i love mekanism")
CHECK(lowc(c10):find("mekanism", 1, true) and (prof("Mia").i.tech or 0) >= 2, "'I love mekanism': the mod talk + tech learned: " .. c10)
-- 10) idle: a tip for a player near it, once an hour
fresh("Steve")
spoken = {}
V.say = function(text) spoken[#spoken + 1] = tostring(text) return true end
P.tipAt = {}
pcall(P.idle, { steve = true }, "Steve")
local tipped = false
for _, l in ipairs(spoken) do
  for _, list in pairs(P.TIP2) do for _, x in ipairs(list) do if l:find(x, 1, true) then tipped = true end end end
  for _, x in ipairs(P.TIP.tutorials) do if l:find(x, 1, true) then tipped = true end end
end
CHECK(tipped and spoken[1] and spoken[1]:find("Steve", 1, true), "idle: a tip for the player near it, about what they told it: " .. table.concat(spoken, " | "))
local n1 = #spoken
for _ = 1, 5 do pcall(P.idle, { steve = true }, "Steve") end
CHECK(#spoken == n1, "... not again within the hour")
V.say = say0
-- 11) variety: the same thing told by 30 players -> many different answers
local seen, n = {}, 0
for i = 1, 30 do
  local name = "P" .. string.char(96 + (i % 26) + 1) .. i
  fresh(name)
  local a = say(name, "base i love building but i get burned out")
  if not seen[a] then seen[a] = true n = n + 1 end
end
CHECK(n >= 20, "30 burned out builders: " .. n .. " different answers")
-- 12) every struggle / interest is reachable by its own words
for id, s in pairs(P.STRUGGLES) do
  fresh("Tess")
  V.mem().tess = {}
  P.lastKey = nil
  say("Tess", "base " .. (s.phrases[1]:find("^i ") and s.phrases[1] or ("honestly i " .. s.phrases[1])))
  CHECK(prof("Tess").s[id], "struggle '" .. id .. "' from '" .. s.phrases[1] .. "'")
end
for id, it in pairs(P.INTERESTS) do
  V.mem().tess = {}
  P.lastKey = nil
  P.learn("Tess", V.norm("i love " .. it.words[1]), nil)
  CHECK((prof("Tess").i[id] or 0) >= 2, "interest '" .. id .. "' from 'i love " .. it.words[1] .. "'")
end

-- 13) WHO IS WHO (the owner: "players might ask who am I, or ask about themselves or other players / moderators")
setSetting("voice.staff", { anna = "admin,builder", modmax = "mod" })
fresh("Steve", "Anna", "Theo")
V.mem().anna = { fav = { mob = "fox" }, likes = { "sunflowers" }, bio = "I build castles", prof = { i = { build = 6, tech = 3 }, s = { burnout = { n = 1, at = os.epoch("utc") } } } }
V.mem().steve = V.mem().steve or {}
V.mem().steve.prof = { i = { tech = 5 }, s = { tutorials = { n = 1, at = os.epoch("utc") } } }
V.mem().steve.fav = { food = "pizza" }
-- who am I: everything about yourself, your struggles too
local w1 = say("Steve", "base who am i")
CHECK(w1:find("Steve", 1, true) and lowc(w1):find("tech player", 1, true) and lowc(w1):find("tutorials", 1, true) and lowc(w1):find("pizza", 1, true),
      "who am I: name, how you play, what gets in your way, favourites: " .. w1)
local w1b = say("Anna", "base tell me about myself")
CHECK(lowc(w1b):find("admin and builder", 1, true) and lowc(w1b):find("i build castles", 1, true), "an admin + builder about themselves: " .. w1b)
-- about another player: public things only
local w2 = say("Steve", "base who is anna")
CHECK(lowc(w2):find("admin and builder", 1, true) and lowc(w2):find("online", 1, true) and lowc(w2):find("building", 1, true) and lowc(w2):find("fox", 1, true)
      and w2:find("I build castles", 1, true), "who is Anna: roles, online, what she loves, favourites, her bio: " .. w2)
CHECK(not lowc(w2):find("burn", 1, true), "... never what gets in her way (burnout): " .. w2)
CHECK(not w2:find(tostring(HOME.x + 2), 1, true) and not lowc(w2):find(" x ", 1, true), "... never where she is")
local w3 = say("Steve", "base tell me about modmax")
CHECK(lowc(w3):find("moderator", 1, true) and lowc(w3):find("not online", 1, true), "tell me about an offline moderator: " .. w3)
local w4 = say("Steve", "base what is anna like")
CHECK(lowc(w4):find("admin", 1, true), "what is Anna like: " .. w4)
-- is X a ...?
local w5 = say("Steve", "base is anna an admin")
CHECK(lowc(w5):find("yes", 1, true), "is Anna an admin - yes: " .. w5)
local w6 = say("Steve", "base is anna a mod")
CHECK(lowc(w6):find("not a moderator", 1, true), "is Anna a mod - no, admin and builder: " .. w6)
local w7 = say("Steve", "base is anna a builder")
CHECK(lowc(w7):find("building", 1, true) or lowc(w7):find("yes", 1, true), "is Anna a builder - yes: " .. w7)
local w8 = say("Anna", "base is steve a builder")
CHECK(lowc(w8):find("not that i know", 1, true) and lowc(w8):find("tech", 1, true), "is Steve a builder - no, he loves tech mods: " .. w8)
-- the owner: never where
fresh("Steve", "Alaory")
local w9 = say("Steve", "base who is alaory")
CHECK(lowc(w9):find("owner", 1, true) and not lowc(w9):find(" x ", 1, true), "who is the owner: built me, never where: " .. w9)
-- little words are never a player: "who is the admin" is not about Theo
fresh("Steve", "Theo")
local w10 = say("Steve", "base who is the admin")
CHECK(not w10:find("Theo", 1, true), "'who is the admin' is not Theo: " .. w10)
-- a name with digits by its clean part
fresh("Steve", "deadman213")
V.mem().deadman213 = { fav = { mob = "warden" } }
local w11 = say("Steve", "base who is deadman")
CHECK(lowc(w11):find("warden", 1, true) and not w11:find("213", 1, true), "'who is deadman' = deadman213, said without digits: " .. w11)
-- unknown
fresh("Steve")
local w12 = say("Steve", "base who is zorblax")
CHECK(not lowc(w12):find("zorblax is", 1, true) or lowc(w12):find("not", 1, true), "an unknown name: " .. w12)
setSetting("voice.staff", {})
