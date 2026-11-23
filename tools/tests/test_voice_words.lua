-- VOICE ADD-ON REVIEW (the owner: "go over the voice addon"). Ordinary chat went wrong:
--  * chat is matched LOOSELY (one letter off = the same word), and a REAL word next to a key word counted as a typo of it:
--    "I have a story for you" = "I HATE you" (it went quiet for 5 minutes), "could" = cold, "water" = weather, "making" =
--    mapping, "having" = hacking, "saying" = spying, "telling" = talking, "then" = they, "fire" = five, "gold" = good,
--    "I will bake bread" called the base ("bake" = "base")
--  * "can I ask you a question" / "I have a question" started a QUIZ
--  * "are you ok" was never understood ("ok" was turned into "yes" before matching), "thanks for the help" got the help
--    list, "I am back" got the not-understood menu, "remember when we built the farm" was saved as a note, "I love this
--    place" was saved as "likes place", "you are welcome here" -> "Welcome, here!", "night in 1 minutes"
--  * every line it ever said was kept in memory (VOICE.said) for as long as the base ran
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
CHECK(V.isReal and V.isReal("have") and V.isReal("making") and V.isReal("tried") and not V.isReal("joek"), "the real-word list is loaded")

-- 1) real words stay themselves, typos are still fixed
local real = { "have", "could", "water", "making", "having", "saying", "telling", "then", "wait", "fire", "gold", "these", "three",
               "trying", "tried", "used", "more", "plan", "tree", "taking" }
local f = V.fix(real)
local bad = {}
for i, w in ipairs(real) do if f[i] ~= w then bad[#bad + 1] = w .. " -> " .. f[i] end end
CHECK(#bad == 0, "real words are not 'fixed' into others: " .. table.concat(bad, ", "))
local ty = V.fix({ "joek", "weathr", "turtels", "stauts", "remmber" })
CHECK(ty[1] == "joke" and ty[2] == "weather" and ty[3] == "turtles" and (ty[4] == "status" or ty[4] == "stats") and ty[5] == "remember",
      "typos are still understood: " .. table.concat(ty, " "))
CHECK(not V.same("have", "hate") and not V.same("bake", "base") and V.same("joek", "joke") and V.same("hlelo", "hello"),
      "VOICE.same: have is not hate, bake is not base; joek / hlelo still are")
CHECK(not V.calledByName(V.norm("bake bread first"), "bake bread first", "base"), "'bake bread' does not call the base")

-- 2) the chat lines that went wrong
fresh()
local r = ask("base i have a story for you")
CHECK(not V.isQuiet() and not r:find("quiet", 1, true), "'I have a story for you' is not 'I hate you': " .. r)
for _, l in ipairs({ "base can i ask you a question", "base i have a question", "base quick question" }) do
  fresh()
  r = ask(l)
  CHECK(next(V.games) == nil and not r:find("Quiz", 1, true), "'" .. l .. "' starts no quiz: " .. r)
end
fresh()
r = ask("base are you okay")
CHECK(not r:find("Type a number", 1, true), "'are you okay' is understood: " .. r)
fresh()
r = ask("base is everything ok")
CHECK(not r:find("Type a number", 1, true), "'is everything ok' is understood: " .. r)
fresh()
r = ask("base thanks for the help")
CHECK(r:lower():find("welcome", 1, true) and not r:find("Ask me:", 1, true), "'thanks for the help' = you are welcome: " .. r)
fresh()
r = ask("base i am back")
CHECK(r:lower():find("back", 1, true) and not r:find("Type a number", 1, true), "'I am back' = welcome back: " .. r)
fresh()
local m = V.mem()
m.alaory = m.alaory or {}
m.alaory.notes = nil
ask("base remember when we built the farm")
CHECK(not (m.alaory.notes and #m.alaory.notes > 0), "'remember when ...' is not saved as a note")
fresh()
ask("base remember to feed the cows")
CHECK(m.alaory.notes and m.alaory.notes[1] and m.alaory.notes[1]:find("feed the cows", 1, true), "'remember to ...' still is")
fresh()
m.alaory.likes = nil
r = ask("base i love this place")
CHECK(not r:find("likes place", 1, true) and not (m.alaory.likes and m.alaory.likes.place), "'I love this place' is a thank-you, not 'likes place': " .. r)
fresh()
r = ask("base you are welcome here")
CHECK(not r:find("Welcome, here", 1, true), "'you are welcome here' -> not 'Welcome, here!': " .. r)
fresh()
r = ask("base welcome steve")
CHECK(r:find("Welcome, steve", 1, true), "'welcome steve' still welcomes Steve: " .. r)
CHECK(not V.timeText():find(" 1 minutes", 1, true), "no '1 minutes': " .. V.timeText())

-- 3) the yes / no answers: "ok" still means yes
fresh()
V.pend.alaory = { kind = "yesno", yes = "tell me a story", till = os.clock() + 60 }
r = ask("ok")
CHECK(V.pend.alaory == nil and r ~= "" and not r:find("Type a number", 1, true), "'ok' answers a yes / no question: " .. r)

-- 4) what it said is not kept for ever
V.said = {}
local q0 = V.queue
for i = 1, 1000 do
  V.queue = {}
  V.say("Line number " .. i .. " of a long day", nil, true)
  CLOCK = CLOCK + 1
end
V.queue = q0
local n = 0
for _ in pairs(V.said) do n = n + 1 end
CHECK(n < 400, "VOICE.said keeps only the last minute or so (" .. n .. " of 1000 lines)")

-- 5) WRONG FACTS taken out (the owner: "go over all voice lines" - every quiz / riddle / fact / tip / recipe / glossary / mod
--    line was read; these were wrong): a beacon is not "made of nine iron", iron golems do NOT attack creepers, ants do sleep,
--    pigs can look up, one gold piece is enough for piglins, Mekanism has no "fluorinated" reactor, andesite alloy is not pressed
local src = ""
for _, f in ipairs({ "voice_lines.lua", "voice_lore.lua", "voice_convo.lua", "voice_talk.lua", "voice_talk2.lua", "voice_talk3.lua" }) do
  local h = io.open(SRC_DIR .. "/" .. f) src = src .. h:read("a") h:close()
end
local WRONG = { "made of nine iron", "Iron golems attack creepers.\", true", "Ants never sleep", "Pigs cannot look up",
  "a full set of gold armour makes piglins", "fluorinated", "mechanical press plus a basin makes andesite alloy",
  "a block you can walk through that lets mobs fall", "a skeleton's worst fear", "ore gives the most experience",
  "demon's dream tea", "gears that are too fast will break", "cat-free platform", "name your pets with a name tag",
  "honey blocks stop pistons", "a smeltery doubles ores", "portable teleporter for travel" }
local found = {}
for _, w in ipairs(WRONG) do if src:find(w, 1, true) then found[#found + 1] = w end end
CHECK(#found == 0, "no wrong facts left in the voice lines: " .. table.concat(found, " | "))
