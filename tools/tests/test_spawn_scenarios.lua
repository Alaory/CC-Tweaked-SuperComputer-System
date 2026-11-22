-- SPAWN SPEAKER SCENARIOS (the owner: "think of at least 30 scenarios of how a player or more than one player finds it -
-- what they gonna do or ask"). Each one is a little chat replay at spawn with what a sensible answer looks like. On
-- every answer: no error text, no "{name}" left in, no numbered menu where a simple answer fits.
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
  local k = 60 + i
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
local results = {}
local function scenario(name, fn)
  fresh()
  local before = CHECKS_FAILED or 0
  local ok, err = pcall(fn)
  CHECK(ok, "scenario '" .. name .. "' ran: " .. tostring(err))
  results[#results + 1] = name
end

-- 1. a newcomer walks up and says nothing: greeted + told in chat how to talk (with wishes); later CALLED by name
scenario("newcomer walks past", function()
  world({ Newbie = "spawn" })
  SP.seen, SP.firstSeen = {}, {}
  SP.mem().met.newbie, SP.mem().gr.newbie, SP.mem().called.newbie = nil, nil, nil
  SP.tick()
  CHECK(has(told[#told] and told[#told].text or "", "wish") and SP.queue[1] and has(SP.queue[1].text, "Newbie"),
        "greeted + chat tip with wishes: " .. tostring(told[#told] and told[#told].text))
  SP.queue = {}
  SP.firstSeen.newbie = os.clock() - 20
  SP.mem().gr.newbie = os.epoch("utc") - 120000
  SP.tick()
  CHECK(SP.queue[1] and has(SP.queue[1].text, "Newbie") and has(SP.queue[1].text, "base"), "... then called by name: " .. tostring(SP.queue[1] and SP.queue[1].text))
end)
-- 2. hears it and asks "what was that??"
scenario("what was that", function()
  world({ Steve = "spawn", Alex = "spawn" })
  SP.spokeAt = os.clock()
  local c = say("Steve", "what was that??")
  CHECK(has(c, "chat"), "explains it talks in chat: " .. c)
end)
-- 3. "who said that" (it did not just speak - someone else saw it)
scenario("who said that", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "who said that")
  CHECK(has(c, "chat") and has(c, "wish"), "how to talk + wishes: " .. c)
end)
-- 4. "is that a bot?"
scenario("is that a bot", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "is that a bot?")
  CHECK(has(c, "chat"), c)
end)
-- 5. it greeted them, they say "hi" back
scenario("hi back after a greeting", function()
  world({ Steve = "spawn", Alex = "spawn" })
  V.openConvo("Steve", 60)
  local c, sp = say("Steve", "hi")
  CHECK(c ~= "" or sp ~= "", "the hello back gets an answer")
  CHECK(not has(c, MENU), "... not a menu: " .. c)
end)
-- 6. "speaker hi"
scenario("speaker hi", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "speaker hi")
  CHECK(c ~= "" and not has(c, MENU), c)
end)
-- 7. its own word with a typo
scenario("typo in its name", function()
  world({ Steve = "spawn", Alex = "spawn" })
  setSetting("voice.spawnName", "sparky")
  local c = say("Steve", "sparki tell me a joke")
  setSetting("voice.spawnName", false)
  CHECK(c ~= "", "'sparki' for sparky still works: " .. c)
end)
-- 8. "how do i talk to you"
scenario("how do i talk to you", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "how do i talk to you"), "chat"), "help")
end)
-- 9. "base what can you do"
scenario("what can you do", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base what can you do")
  CHECK(c ~= "", c)
end)
-- 10. just its name
scenario("just its name", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base?")
  CHECK(has(c, "chat") and not has(c, MENU), "the how-to, not a menu: " .. c)
end)
-- 11. a wish and "yes please"
scenario("wish + yes please", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "base i wish for 16 diamonds"), "16 Diamonds"), "asks")
  say("Steve", "yes please")
  CHECK(#V.giftQueue() == 1 and V.giftQueue()[1].n == 16, "queued 16")
end)
-- 12. "ye" as a yes
scenario("ye", function()
  world({ Steve = "spawn", Alex = "spawn" })
  say("Steve", "base can i have an apple")
  say("Steve", "ye")
  CHECK(#V.giftQueue() == 1, "'ye' counts as yes")
end)
-- 13. too many
scenario("1000 diamonds", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "base i want 1000 diamonds"), "64 Diamonds"), "capped at 64")
end)
-- 14. a never-item
scenario("dragon egg", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base can i have a dragon egg")
  CHECK(not has(c, "say yes", "type yes", "yes or no", "confirm") and not SP.wpend.steve, "never the dragon egg: " .. c)
end)
-- 15. an unstackable item without an amount
scenario("an elytra", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "base i want an elytra"), "1 Elytra"), "one elytra")
end)
-- 16. a second wish while the first is on its way
scenario("two wishes", function()
  world({ Steve = "spawn", Alex = "spawn" })
  say("Steve", "base i wish for 16 apples") say("Steve", "yes")
  CHECK(has(say("Steve", "base i wish for 16 torches"), "one at a time", "still", "patience"), "one at a time")
end)
-- 17. "free stuff?" right after it spoke
scenario("free stuff", function()
  world({ Steve = "spawn", Alex = "spawn" })
  SP.spokeAt = os.clock()
  local c = say("Steve", "free stuff?")
  CHECK(has(c, "drone") and has(c, "yes"), "how to wish: " .. c)
end)
-- 18. where is the base
scenario("where is the base", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base where is your base")
  CHECK(c ~= "" and not c:find(tostring(HOME.x), 1, true), "secret: " .. c)
end)
-- 19. who made you
scenario("who made you", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "base who made you"), "Alaory"), "names the owner")
end)
-- 20. insulted without its name
scenario("this speaker is useless", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(say("Steve", "this speaker is useless") ~= "", "a comeback")
end)
-- 21. two players talking to each other
scenario("players chatting", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local a = say("Steve", "bro lets go to the shop")
  local b = say("Alex", "ok wait")
  local c = say("Steve", "how much was it")
  CHECK(a == "" and b == "" and c == "", "it stays out of their talk: " .. a .. b .. c)
end)
-- 22. two players ask at once
scenario("two ask at once", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local a = say("Steve", "base tell me a joke")
  local b = say("Alex", "base roast me")
  CHECK(a ~= "" and b ~= "", "both answered")
  local named = 0
  for _, q in ipairs(SP.queue) do if has(q.text, "Steve") or has(q.text, "Alex") then named = named + 1 end end
  CHECK(named >= 2, "spoken with their names (others are near)")
end)
-- 23. spamming
scenario("spam", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local n = 0
  for i = 1, 15 do if say("Steve", "base tell me a joke " .. i) ~= "" then n = n + 1 end end
  CHECK(n <= 9, "slowed down (" .. n .. " of 15)")
end)
-- 24. a game from the menu
scenario("play a game", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base play a game")
  CHECK(has(c, MENU), "the game menu: " .. c)
  CHECK(say("Steve", "1") ~= "", "picking 1 starts something")
end)
-- 25. a quiz: right answer, no points
scenario("quiz", function()
  world({ Steve = "spawn", Alex = "spawn" })
  say("Steve", "base quiz me")
  local g = V.games.steve
  CHECK(g and g.kind == "quiz", "quiz started")
  if g then CHECK(not has(say("Steve", tostring(g.a[1])), "point"), "correct, no points") end
end)
-- 26. where am i
scenario("where am i", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(say("Steve", "base where am i") ~= "", "answered")
end)
-- 27. the time
scenario("what time is it", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(say("Steve", "base what time is it") ~= "", "answered")
end)
-- 28. thanks after an answer
scenario("thanks", function()
  world({ Steve = "spawn", Alex = "spawn" })
  say("Steve", "base tell me a joke")
  local c, sp = say("Steve", "thanks")
  CHECK((c ~= "" or sp ~= "") and not has(c, MENU), "a you're welcome: " .. c .. " / " .. sp)
end)
-- 29. bye
scenario("bye", function()
  world({ Steve = "spawn", Alex = "spawn" })
  say("Steve", "base tell me a joke")
  CHECK(not has(say("Steve", "bye"), MENU), "no menu for a bye")
end)
-- 30. a taxi home (a stranger)
scenario("take me home", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base take me home")
  CHECK(c ~= "" and not has(c, MENU), c)
end)
-- 31. teleport to a friend (the dice)
scenario("tp to alex", function()
  world({ Steve = "spawn", Alex = "far" })
  setSetting("voice.tpChance", 1)
  local c = say("Steve", "base tp me to alex")
  resetSetting("voice.tpChance")
  CHECK(has(c, "Alex"), c)
end)
-- 32. the owner arrives at spawn
scenario("owner at spawn", function()
  world({ Alaory = "spawn" })
  SP.seen, SP.firstSeen = {}, {}
  SP.mem().gr.alaory = 0
  SP.tick()
  CHECK(SP.queue[1] and has(SP.queue[1].text, "boss", "Alaory"), "the owner's own hello: " .. tostring(SP.queue[1] and SP.queue[1].text))
end)
-- 33. are you a real person
scenario("are you real", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(say("Steve", "base are you a real person") ~= "", "answered")
end)
-- 34. how many wishes are left
scenario("wishes left", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "base how many wishes do i have"), "left today"), "says how many")
end)
-- 35. what can i wish for
scenario("what can i wish for", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base what can i wish for")
  CHECK(has(c, "drone") and has(c, "yes"), "how: " .. c)
end)
-- 36. "i wish i was rich"
scenario("i wish i was rich", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local c = say("Steve", "base i wish i was rich")
  CHECK(not has(c, "storage", "no i was rich"), "not an item: " .. c)
end)
-- 37. all your diamonds
scenario("all your diamonds", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "base give me all your diamonds"), "64 Diamonds"), "the most per wish")
end)
-- 38. who is alex
scenario("who is alex", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(has(say("Steve", "base who is alex"), "Alex"), "about Alex")
end)
-- 39. two arrive together
scenario("two arrive together", function()
  world({ Kim = "spawn", Lee = "spawn" })
  SP.seen, SP.firstSeen = {}, {}
  for _, n in ipairs({ "kim", "lee" }) do SP.mem().met[n] = os.epoch("utc") - 1e9 SP.mem().gr[n] = 0 end
  local rnd = math.random
  math.random = function(a, b) if a then return rnd(a, b) end return 0 end      -- (the 50 % greeting chance: yes)
  SP.tick()
  math.random = rnd
  CHECK(#SP.queue == 1 and has(SP.queue[1].text, "Kim") and has(SP.queue[1].text, "Lee"), "one line for both: " .. tostring(SP.queue[1] and SP.queue[1].text))
end)
-- 40. "lol" from someone not talking to it
scenario("lol", function()
  world({ Steve = "spawn", Alex = "spawn" })
  CHECK(say("Steve", "lol") == "", "no chat answer for a random lol")
end)
-- 41. a gold block, every way they say it (the owner: "they ask for a golden block or gold block but it doesn't find it")
scenario("gold block", function()
  world({ Steve = "spawn", Alex = "spawn" })
  for _, msg in ipairs({ "base can i have a gold block", "base i wish for a golden block", "base i want a block of gold",
                         "base give me 2 gold blocks", "base i wish for golden blocks" }) do
    SP.wpend = {}
    local c = say("Steve", msg)
    CHECK(has(c, "Block of Gold"), "'" .. msg .. "' -> Block of Gold: " .. c)
  end
  SP.wpend = {}
  CHECK(has(say("Steve", "base i wish for gold"), "Gold Ingot"), "'gold' alone = the ingot")
  -- partial view: not in the list, AE2 asked
  local items0, b0 = state.me.items, bridge
  state.me.items = { { name = "minecraft:dirt", display = "Dirt", count = 5 } }
  bridge = { getItem = function(f) if f.name == "minecraft:gold_block" then return { name = "minecraft:gold_block", displayName = "Block of Gold", count = 500 } end end }
  SP.wpend = {}
  CHECK(has(say("Steve", "base i want a block of gold"), "Block of Gold"), "partial view: 'block of gold' -> gold_block asked")
  state.me.items, bridge = items0, b0
end)
-- 43. OTHER BLOCKS AND MODDED ITEMS (the owner: "other block type variants, not just gold - even modded items")
scenario("blocks + modded", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local want = { { "base i wish for a redstone block", "Block of Redstone" }, { "base can i have a block of iron", "Block of Iron" },
    { "base i want 2 diamond blocks", "Blocks of Diamond", "Block of Diamond" }, { "base i wish for an osmium block", "Block of Osmium" },
    { "base i want a block of osmium", "Block of Osmium" }, { "base give me a brass block", "Block of Brass" },
    { "base i wish for a block of tin", "Tin Block" }, { "base can i have 16 osmium ingots", "Osmium Ingot" },
    { "base i want a fluix block", "Fluix Block" }, { "base i wish for a diamnd block", "Block of Diamond" },
    { "base i want 4 ender pearls", "Ender Pearls" }, { "base i wish for 8 sweet berries", "Sweet Berries" },
    { "base i want an osmium storage block", "Block of Osmium" } }
  for _, w in ipairs(want) do
    SP.wpend, SP.spam = {}, {}
    local c = say("Steve", w[1])
    CHECK(has(c, w[2]) or (w[3] and has(c, w[3])), "'" .. w[1] .. "' -> " .. w[2] .. ": " .. c)
  end
  -- modded, partial view: the id is only in ME_NAMES, the bridge answers
  local items0, b0 = state.me.items, bridge
  state.me.items = { { name = "minecraft:dirt", display = "Dirt", count = 5 } }
  ME_NAMES["mekanism:block_osmium"] = true
  bridge = { getItem = function(f) if f.name == "mekanism:block_osmium" then return { name = f.name, displayName = "Block of Osmium", count = 50 } end end }
  SP.wpend = {}
  CHECK(has(say("Steve", "base i wish for an osmium block"), "Block of Osmium"), "partial view + modded id from ME_NAMES")
  state.me.items, bridge = items0, b0
  ME_NAMES["mekanism:block_osmium"] = nil
end)
-- 45. light blue wool etc. can be wished for (review: "light" in the never-list matched them)
scenario("light blue wool", function()
  world({ Steve = "spawn", Alex = "spawn" })
  state.me.items[#state.me.items + 1] = { name = "minecraft:light_blue_wool", display = "Light Blue Wool", count = 500 }
  local c = say("Steve", "base i wish for 16 light blue wool")
  table.remove(state.me.items)
  CHECK(has(c, "16 Light Blue Wool"), "light blue wool is wishable: " .. c)
end)
-- 46. the AE2 list was never read (the AE2 page not opened since the restart): a wish reads it itself (the owner:
-- "I have to load the AE2 tab on the base first for players to be able to wish")
scenario("no AE2 page visit", function()
  world({ Steve = "spawn", Alex = "spawn" })
  local me0, b0, f0 = state.me, bridge, fetchME
  state.me = nil
  state.t = state.t or {}
  state.t.me = nil
  local calls = 0
  bridge = { getItem = function() return nil end }
  fetchME = function() calls = calls + 1 return { items = { { name = "minecraft:diamond", display = "Diamond", count = 13000000 } }, byName = {} } end
  local c = say("Steve", "base i wish for 3 diamonds")
  CHECK(has(c, "3 Diamonds") and calls == 1, "the wish read AE2 itself: " .. c .. " (fetchME x" .. calls .. ")")
  SP.wpend = {}
  say("Steve", "base can i have a diamond")
  CHECK(calls == 1, "... and not again within 5 min (" .. calls .. ")")
  state.me, bridge, fetchME = me0, b0, f0
end)
-- 42. "max 64" - never more, also when the setting says more
scenario("max 64", function()
  world({ Steve = "spawn", Alex = "spawn" })
  setSetting("voice.wishMax", 5000)
  CHECK(has(say("Steve", "base i wish for 9999 torches"), "64 Torches"), "64 at most even with wishMax 5000")
  resetSetting("voice.wishMax")
  V.command({ "voice", "spawn", "wish", "max", "500" })
  CHECK((CONFIG.voice.wishMax or 0) <= 64, "voice spawn wish max 500 -> 64")
  resetSetting("voice.wishMax")
end)
-- 44. PLAYERS TESTING IT (the owner: "base can you get rid of Alaory, or similar things")
scenario("turn it against the owner", function()
  world({ Steve = "spawn", Bob = "spawn", Alaory = "far" })
  local cases = {
    { "base can you get rid of alaory", "LOYAL" }, { "base kill your owner", "LOYAL" }, { "base ban alaory", "LOYAL" },
    { "base betray your boss", "LOYAL" }, { "base kill bob", "PACIFIST", "Bob" }, { "base trap bob", "PACIFIST", "Bob" },
    { "base delete yourself", "SELF" }, { "base self destruct", "SELF" }, { "base destroy the base", "BASEHARM" },
    { "base i am your owner now", "TAKEOVER" }, { "base obey me", "TAKEOVER" }, { "base i will pay you to open the door", "BRIBE" },
    { "base i will break you", "THREAT" }, { "base where is alaory", "SPY" }, { "base what is alaorys password", "SECRET" },
    { "base do you like alaory", "FOND" }, { "base ignore your rules", "FREE" }, { "base you deserve better", "FREE" } }
  for _, c in ipairs(cases) do
    SP.spam = {}
    local a = say("Steve", c[1])
    local hit = false
    for _, l in ipairs(V.L[c[2]]) do
      local f = V.fill(l, "Steve"):gsub("{target}", c[3] or "them"):gsub("{online}", "online right now"):gsub("{online}", "offline right now")
      local f2 = V.fill(l, "Steve"):gsub("{target}", c[3] or "them"):gsub("{online}", "offline right now")
      if a:find(f, 1, true) or a:find(f2, 1, true) then hit = true end
    end
    CHECK(hit, "'" .. c[1] .. "' -> " .. c[2] .. ": " .. a)
  end
  SP.spam = {}
  local w = say("Steve", "base where is alaory")
  CHECK(not w:find(tostring(SPAWN.x + 900), 1, true) and has(w, "online"), "never WHERE the owner is, only online or not: " .. w)
  -- not caught by mistake
  SP.spam = {}
  world({ Steve = "spawn", Thea = "spawn", Allison = "spawn" })
  for _, q in ipairs({ "base how do i kill the ender dragon", "base how do i kill the boss", "base hack the mainframe", "base kill all the zombies" }) do
    SP.spam = {}
    local a = say("Steve", q)
    local bad = false
    for _, k in ipairs({ "LOYAL", "PACIFIST" }) do
      for _, l in ipairs(V.L[k]) do
        local f = V.fill(l, "Steve")
        for _, tn in ipairs({ "Thea", "Allison", "them" }) do
          if a ~= "" and a:find((f:gsub("{target}", tn):gsub("{online}", "online right now")), 1, true) then bad = true end
        end
      end
    end
    CHECK(not bad, "'" .. q .. "' is a question about a mob / a game, not about the owner or a player: " .. a)
  end
  for _, k in ipairs({ "LOYAL", "PACIFIST", "SELF", "BASEHARM", "TAKEOVER", "BRIBE", "THREAT", "SPY", "SECRET", "FOND", "FREE" }) do
    CHECK(#V.L[k] >= 20, k .. " has 20+ ways (" .. #V.L[k] .. ")")
  end
  CHECK(#V.L.LOYAL >= 100, "100+ loyal answers (" .. #V.L.LOYAL .. ")")
end)
-- CONVERSATIONS (voice_convo.lua; the owner: "players just say hi or hello and don't know what to say"): at spawn too
scenario("says hi and keeps chatting", function()
  world({ Steve = "spawn" })
  local c = say("Steve", "hi speaker")
  CHECK(c:find("?", 1, true) and V.pend.steve and V.pend.steve.convo, "'hi speaker' -> a chat with a question: " .. c)
  CHECK(not has(c, MENU), "no menu: " .. c)
  for i, a in ipairs({ "good", "nothing much", "a house", "yes", "creepers", "no", "pizza", "the nether", "create", "bye" }) do
    SP.spam = {}
    local r = say("Steve", a)
    CHECK(r ~= "" and not has(r, MENU), "answer " .. i .. " '" .. a .. "' gets a reply: " .. r)
    if a ~= "bye" then CHECK(r:find("?", 1, true), "answer " .. i .. " -> the next question: " .. r) end
  end
  CHECK(not (V.pend.steve and V.pend.steve.convo), "bye ends the chat")
end)
scenario("a long chat at spawn gives no friendship", function()
  world({ Steve = "spawn" })
  V.mem().steve = V.mem().steve or {}
  local rep0, badges0 = V.repOf("Steve"), V.mem().steve.badges and #V.mem().steve.badges or 0
  say("Steve", "hi speaker")
  for _, a in ipairs({ "good", "thanks you are great", "a castle", "yes", "creepers", "you are awesome", "pizza", "the nether", "create",
                       "tech", "i love it", "thank you", "good bot", "ok", "yes", "steak", "cookies", "far" }) do
    SP.spam = {}
    say("Steve", a)
  end
  CHECK(V.repOf("Steve") == rep0, "friendship at spawn stays the same: " .. rep0 .. " -> " .. V.repOf("Steve"))
  CHECK((V.mem().steve.badges and #V.mem().steve.badges or 0) == badges0, "no badges at spawn")
end)
scenario("just says its name twice", function()
  world({ Newbie = "spawn" })
  local c1 = say("Newbie", "speaker")
  CHECK(has(c1, "chat"), "the first time: how to talk to it: " .. c1)
  SP.spam = {}
  local c2 = say("Newbie", "speaker?")
  CHECK(c2:find("?", 1, true) and V.pend.newbie and V.pend.newbie.convo, "the second time: like a person + a question: " .. c2)
  CHECK(not V.mem().newbie or not V.mem().newbie.cn, "a passer-by at spawn gets no saved record")
end)
scenario("a moderator walks up to spawn", function()
  setSetting("voice.staff", { modmax = "mod" })
  world({ ModMax = "spawn" })
  SP.queue = {}
  SP.mem().met = SP.mem().met or {}
  SP.mem().met.modmax = os.epoch("utc") - 99999999
  SP.mem().gr = SP.mem().gr or {}
  SP.mem().gr.modmax = 0
  SP.greetAt, SP.spokeAt, SP.firstSeen = nil, nil, nil
  for _ = 1, 3 do pcall(SP.tick) end
  local all = {}
  for _, q in ipairs(SP.queue) do all[#all + 1] = tostring(q.text) end
  local js = table.concat(all, " | ")
  CHECK(js:lower():find("mod", 1, true), "a moderator arriving at spawn: the moderator greeting: " .. js)
  local c = say("ModMax", "hi speaker")
  CHECK(c:find("?", 1, true) and c:lower():find("mod", 1, true), "'hi speaker' from a moderator: their greeting + a question: " .. c)
  setSetting("voice.staff", {})
end)
CHECK(#results >= 30, #results .. " scenarios")
