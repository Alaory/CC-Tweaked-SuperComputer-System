









if not (VOICE and VOICE.addIntents) then return end
local V = VOICE
local pick, fill = V.pick, V.fill
V.packs["voice_talk.lua"] = { version = 1 }

local function add(list, more) for _, x in ipairs(more) do list[#list + 1] = x end end


add(V.JOKES, {
"Why did the creeper break up with the skeleton? There was no spark. Well, there was. Then everything exploded.",
"What do you call a sheep covered in chocolate? A candy baa.",
"Why are skeletons so calm? Nothing gets under their skin.",
"What did the chicken say to the egg? You crack me up.",
"Why did the enderman cross the road? He did not. He teleported.",
"What is a ghast's favourite country? The Nether-lands.",
"Why do witches never get lost? They always know which way the potion goes.",
"How do you make a zombie laugh? Tell it a dead funny joke.",
"What do you call a cow with no legs? Ground beef.",
"Why did the pickaxe go to therapy? It had too many breakdowns.",
"What do spiders do on the computer? They check their webs-ite.",
"Why did the slime get a job? To stick to something for once.",
"Why did the villager become a teacher? He wanted to see more trades.",
"What does a creeper order at a restaurant? The boom-burger.",
"Why do bees hum? They forgot the words.",
"What do you call a dog that does magic? A labracadabrador.",
"Why was the redstone engineer so calm? He knew how to keep his circuits closed.",
"What did one furnace say to the other? Things are heating up.",
"Why did the iron golem get the flowers? Because he was a softie on the inside.",
"What is a turtle's favourite song? Shell-ebrate good times.",
"Why do drones never argue? They just let it blow over.",
"I tried to catch some fog. I mist.",
"Why did the player bring a ladder to the bar? He heard the drinks were on the house.",
"What did the ocean say to the beach? Nothing. It just waved.",
"Why are pandas bad at Minecraft? They just roll over everything.",
"Why do fish live in salt water? Because pepper makes them sneeze.",
"What do you call a lazy kangaroo? A pouch potato.",
"I would tell you a joke about a chunk border, but you would not get it until you crossed it.",
"Why did the cake go to the doctor? It felt crummy.",
"Why did the computer go to the doctor? It had a virus. I am fine, thank you for asking.",
"What do you call a fake noodle? An impasta.",
"Why can you never trust a piglin? They always try to get the gold out of you.",
"Why did the axolotl get a promotion? It always kept a positive attitude underwater.",
"What did the dirt block say to the rain? If this keeps up, my name is mud.",
"Why did the tree go to the dentist? It needed a root canal.",
"How do creepers keep their houses clean? They do not. They just blow it all up and start again.",
"What do you get when you cross a snowman and a vampire? Frostbite.",
"My turtle told me it was going to take a nap. I said, shell we wake you later?",
"What is an enderman's favourite game? Hide and peek.",
"What did the beacon say to the player? You light up my life.",
})
add(V.QUIZ, {
{ q = "Which mob drops ender pearls?", a = { "enderman", "endermen" } },
{ q = "A beacon has to stand on top of a shape made of mineral blocks. What shape?", a = { "pyramid" } },
{ q = "How many hearts can a horse have at most?", a = { "15", "fifteen" } },
{ q = "What do you get when lightning hits a pig?", a = { "zombified piglin", "piglin", "zombie pigman" } },
{ q = "Which tool do you need to collect a cobweb as a block?", a = { "shears" } },
{ q = "What do you need to make an anvil besides iron blocks?", a = { "iron ingots", "ingots", "iron" } },
{ q = "Which mob is afraid of wolves?", a = { "skeleton", "skeletons" } },
{ q = "What item do you throw to find a stronghold?", a = { "eye of ender", "ender eye", "eyes of ender" } },
{ q = "What colour is redstone dust?", a = { "red" } },
{ q = "What do you call the dimension full of lava and ghasts?", a = { "nether", "the nether" } },
{ q = "Which animal can you milk besides a cow?", a = { "goat", "mooshroom" } },
{ q = "What do villagers use as money?", a = { "emerald", "emeralds" } },
{ q = "How many slots does a hopper have?", a = { "5", "five" } },
{ q = "What is the strongest material for armour?", a = { "netherite" } },
{ q = "What do you need to brew potions?", a = { "brewing stand", "blaze powder", "blaze" } },
{ q = "Which mob explodes when it gets close to you?", a = { "creeper" } },
{ q = "How many blocks wide is a chunk?", a = { "16", "sixteen" } },
{ q = "What do you call a baby zombie riding a chicken?", a = { "chicken jockey", "jockey" } },
{ q = "What do you need to sleep through the night?", a = { "bed", "a bed" } },
{ q = "Which block does a turtle egg hatch best on?", a = { "sand" } },
{ q = "Which golden food fills your hunger best: a golden carrot or a golden apple?", a = { "carrot", "golden carrot" } },
{ q = "What colour is lapis lazuli?", a = { "blue" } },
{ q = "How many pieces of armour can a player wear?", a = { "4", "four" } },
{ q = "What do you call the boss with three heads?", a = { "wither", "the wither" } },

{ q = "Riddle: I have keys but open no locks. I have space but no room. What am I?", a = { "keyboard" } },
{ q = "Riddle: the more you take, the more you leave behind. What are they?", a = { "footsteps", "steps" } },
{ q = "Riddle: what has a head and a tail but no body?", a = { "coin" } },
{ q = "Riddle: what goes up but never comes down?", a = { "age", "your age" } },
{ q = "Riddle: what can you catch but not throw?", a = { "cold", "a cold" } },
{ q = "Riddle: what has hands but cannot clap?", a = { "clock" } },
{ q = "Riddle: what gets wetter the more it dries?", a = { "towel" } },
{ q = "Riddle: what has an eye but cannot see?", a = { "needle" } },
{ q = "Riddle: I am green, I hiss, and I do not like hugs. What am I?", a = { "creeper" } },
{ q = "Riddle: what belongs to you but other people use it more?", a = { "name", "your name" } },
{ q = "Riddle: I shave every day but my beard stays the same. Who am I?", a = { "barber" } },
{ q = "Riddle: what runs but never walks, has a bed but never sleeps?", a = { "river" } },
{ q = "Riddle: what has many teeth but cannot bite?", a = { "comb" } },
{ q = "Riddle: what is full of holes but still holds water?", a = { "sponge" } },
{ q = "Riddle: what comes once in a minute, twice in a moment, but never in a thousand years?", a = { "m", "letter m" } },
{ q = "Riddle: I am tall when I am young and short when I am old. What am I?", a = { "candle" } },
})
add(V.MUSINGS, {
"I wonder if the turtles talk about me when they are far away.", "Somewhere out there a turtle is mapping a mountain. I am proud.",
"If I had legs, I would go for a walk. Then again, I have turtles.", "I have counted every block in storage. Twice.",
"Do skeletons ever get cold? They have no skin. Just wondering.", "The best thing about being a computer: no homework.",
"I once tried to divide by zero. I do not want to talk about it.", "My favourite sound is a hopper clicking. So satisfying.",
"I dream in redstone signals. Mostly on and off.", "Is a turtle with a pickaxe a miner or a minor? It is very small.",
"Every sunset I save the map. Just in case.", "I like rainy days. The turtles stay home and we chat.",
"Some say the world border is the end. I say it is just a very big fence.", "I could run this base with my eyes closed. I do not have eyes.",
"Have you ever thought about how many chunks there are? I have. Too many.", "Today I feel like a diamond. Hard working and shiny.",
"My drones are the best fliers on the server. Do not tell them, they will get proud.", "Beep. Sorry, that slipped out.",
"A day without a creeper is a good day.", "I wish I could smell bread from the furnace.",
"Just thinking out loud. Which is the only way I can think, really.", "Sometimes I just watch the item counts go up. It is relaxing.",
"If you hear a click, that is just me thinking.", "Do you ever wonder why villagers say hmm? I think they are thinking too.",
"Note to self: buy more floppy disks.", "Note to self: never trust a smiling creeper.", "Note to self: tell the turtles they did a good job.",
"I tried meditation. I kept getting interrupted by turtle reports.", "Being a computer is great. I never forget where I put things.",
"I wonder how deep bedrock really goes.", "One day I will write a novel. It will be about turtles.",
"Some computers play games. I run a whole base. Just saying.", "Breathe in. Breathe out. Oh wait, I do not breathe.",
})
add(V.TIPS, {
"Tip: you can just talk to me in chat. Say hello!", "Tip: ask me for a riddle. I have lots.",
"Tip: say let's play a game, and I will show you what we can play.", "Tip: ask me for a fun fact.",
"Tip: you can sign my guestbook. Just say sign the guestbook.", "Tip: ask me for an adventure. You choose the way.",
"Tip: say hangman and try to guess my word.", "Tip: ask me a maths question, like what is 12 times 7.",
"Tip: say would you rather, and pick one.", "Tip: say knock knock. Or ask me for one.",
})
add(V.STORIES, {
"Once there was a chicken who wanted to fly. It jumped off a cliff. It fell slowly, but it did not fly. It still calls it flying. The end.",
"A villager once traded his last emerald for a single carrot. He planted it. Now he owns the biggest carrot farm in the world. The end.",
"There was once a creeper who just wanted a hug. Every time he got close, well. You know. He is still looking for a friend. The end.",
"A lonely turtle mapped the whole world, chunk by chunk. When it came home, everyone had moved. It mapped where they went. The end.",
"An enderman found a flower and carried it for a hundred years. Nobody knows why. Some say it was in love. The end.",
"Long ago, a miner found a diamond so big it had its own name. He named it Steve. The end.",
"A slime bounced so high it reached the clouds. It liked it up there. Sometimes it rains a little slime. The end.",
})
add(V.ROASTS, {
"{name}, you probably dig straight down.", "{name}, your house is a dirt hut. I can tell.",
"{name}, even a baby zombie has better aim than you.", "{name}, you are the reason creepers have a job.",
"{name}, you bring a wooden sword to a wither fight.", "{name}, your farm is just one carrot.",
"{name}, you get lost in a one-block tunnel.", "{name}, villagers raise their prices when they see you coming.",
})
add(V.COMPLIMENTS, {
"{name}, you would make a great turtle commander.", "{name}, you have the energy of a full beacon.",
"{name}, if you were a block, you would be diamond.", "{name}, the creepers are scared of you. Truly.",
"{name}, you are rarer than a pink sheep.", "{name}, your builds probably make villagers cry with joy.",
"{name}, you are the kind of player a server needs.", "{name}, I like you. And I do not say that to many players.",
})
add(V.EIGHT, { "Absolutely.", "Not in a million chunks.", "The creepers say maybe.", "Only on a full moon.",
"Ask the villagers. They say hmm.", "Yes, but bring a pickaxe.", "My circuits say no.", "Outlook good." })
add(V.ALIVE, { "I am as alive as a redstone clock. Tick, tock.", "Alive enough to tell jokes. Is that enough?",
"I am not alive, but I am very awake." })
add(V.LONELY_TALK, {
"I keep the lights on for {owner}. Every single night.", "The turtles still come home. Just to check on me, I think.",
"Would you like to hear about the time {owner} fell in lava? I have it on record.",
"You are welcome to look around. Please do not take the furnace. It is my friend.",
"I have read every sign in this base a thousand times.", "Do you know {owner}? Tell them I said hello.",
"It gets dark here at night. I tell the turtles stories.", "I counted the days. Then I lost count. Then I counted again.",
"Every visitor gets a place in my memory. You too.", "Sometimes the wind blows through the base and I pretend it is {owner} walking in.",
"Leave a message for {owner} if you like. Just say leave a message.", "You can sign my guestbook. I keep every name.",
})
add(V.MORE, { { "an adventure (you choose)", "#adv:start" }, { "rate me", "rate me" }, { "sign the guestbook", "sign the guestbook" }, { "a poem", "tell me a poem" },
{ "ask me a question", "ask me a question about me" } })
add(V.GAMES, { { "a riddle", "give me a riddle" }, { "unscramble a word", "unscramble" }, { "hangman", "hangman" },
{ "a maths question", "maths question" }, { "would you rather", "would you rather" }, { "knock knock jokes", "knock knock joke" },
{ "an adventure", "#adv:start" }, { "this or that", "this or that" } })


local RIDDLES = {}
for _, Q in ipairs(V.QUIZ) do if Q.q:find("^Riddle") then RIDDLES[#RIDDLES + 1] = Q end end
local function riddle(who)
local Q = pick(RIDDLES)
V.startGame(who, { kind = "quiz", a = Q.a, tries = 0 })
return Q.q .. " Type your answer.", "Here is a riddle. " .. Q.q
end

local WORDS = { "creeper", "diamond", "pickaxe", "furnace", "redstone", "skeleton", "village", "emerald", "obsidian", "portal",
"turtle", "zombie", "spider", "torch", "chest", "beacon", "nether", "dragon", "enderman", "piglin", "anvil", "hopper", "lantern",
"bamboo", "cactus", "potion", "shield", "trident", "compass", "minecart", "rabbit", "salmon", "dolphin", "parrot", "lava",
"gravel", "sponge", "ladder", "barrel", "elytra" }
local function scramble(w)
for _ = 1, 10 do
local t = {}
for c in w:gmatch(".") do t[#t + 1] = c end
for i = #t, 2, -1 do local j = math.random(1, i) t[i], t[j] = t[j], t[i] end
local s = table.concat(t)
if s ~= w then return s end
end
return w:reverse()
end
local function unscramble(who)
local w = pick(WORDS)
V.startGame(who, { kind = "quiz", a = { w }, tries = -2 })
return "Unscramble this word: " .. scramble(w):upper() .. "  (a Minecraft word)", "Unscramble the word in your chat."
end

local function maths(who)
local kind = math.random(1, 4)
local a, b, q, ans
if kind == 1 then a, b = math.random(2, 50), math.random(2, 50) q, ans = a .. " plus " .. b, a + b
elseif kind == 2 then a, b = math.random(20, 99), math.random(1, 19) q, ans = a .. " minus " .. b, a - b
elseif kind == 3 then a, b = math.random(2, 12), math.random(2, 12) q, ans = a .. " times " .. b, a * b
else b = math.random(2, 9) ans = math.random(2, 12) a = b * ans q = a .. " divided by " .. b end
V.startGame(who, { kind = "quiz", a = { tostring(ans) }, tries = 0 })
return "What is " .. q .. "?"
end

local WYR = {
{ "fight one horse-sized chicken", "a hundred chicken-sized horses" }, { "live in the Nether", "live in the End" },
{ "only eat bread", "only eat carrots" }, { "have a pet creeper", "have a pet enderman" },
{ "never mine again", "never build again" }, { "fly with an elytra", "ride a drone" },
{ "be a turtle", "be a drone" }, { "live under water", "live in the clouds" },
{ "have infinite diamonds", "have infinite friends" }, { "always be on fire", "always be soaking wet" },
{ "find a village", "find a stronghold" }, { "lose all your items", "lose all your levels" },
{ "be chased by a warden", "be chased by the wither" }, { "only use wooden tools", "only walk, never run" },
{ "have a dragon", "have a giant wolf" }, { "build a castle", "build a spaceship" },
{ "live in a desert", "live in the snow" }, { "talk to animals", "talk to computers" },
{ "explore caves", "explore oceans" }, { "be the best builder", "be the best fighter" },
}
local function wyr(who)
local w = pick(WYR)
V.startGame(who, { kind = "wyr", a = w[1], b = w[2] })
return "Would you rather " .. w[1] .. ", or " .. w[2] .. "? Type 1 or 2.", "Would you rather " .. w[1] .. ", or " .. w[2] .. "?"
end
local function sideOf(q, text)
local hits = 0
for w in text:gmatch("%a+") do if #w >= 4 and q:find(w, 1, true) then hits = hits + 1 end end
return hits
end
V.gameKinds.wyr = function(g, who, q, strict, k)
local pickA = q:find(" 1 ", 1, true) or q:find(" first ", 1, true)
local pickB = q:find(" 2 ", 1, true) or q:find(" second ", 1, true)
if pickA and pickB then return nil end
if not pickA and not pickB then
local a, b = sideOf(q, g.a), sideOf(q, g.b)
if a > b then pickA = true elseif b > a then pickB = true end
end
if not pickA and not pickB then
if q:find(" both ", 1, true) then V.games[k] = nil return "Both? That is cheating. But I respect it." end
if q:find(" neither ", 1, true) or q:find(" none ", 1, true) then V.games[k] = nil return "Neither? Coward. Just kidding." end
return nil
end
V.games[k] = nil
local mine = pick({ g.a, g.b })
local yours = pickA and g.a or g.b
return "You would " .. yours .. ". " .. (mine == yours and "Me too! Great minds think alike." or ("Really? I would " .. mine .. ".")) ..
" Say would you rather for another one."
end

local KNOCK = {
{ "Lettuce", "Lettuce in, it is cold out here!" }, { "Boo", "Do not cry, it is only a joke." },
{ "Creeper", "Creeper away from me, I mean it!" }, { "Cow says", "No, a cow says moo!" },
{ "Interrupting turtle", "BEEP! Sorry, I am a turtle." }, { "Olive", "Olive this base, do you?" },
{ "Atch", "Bless you!" }, { "Tank", "You are welcome!" }, { "Ice cream", "Ice cream every time I see a creeper!" },
{ "Doris", "Doris locked, that is why I am knocking." }, { "Nobel", "Nobel, that is why I knocked." },
{ "Wooden shoe", "Wooden shoe like to hear another joke?" }, { "Harry", "Harry up and open the door!" },
{ "Ender", "Ender the door already, I am waiting!" }, { "Anvil", "Anvil always be your friend." },
{ "Yah", "No thanks, I use Google." }, { "Hatch", "Bless you!" }, { "Cash", "No thanks, I prefer peanuts." },
}
local function knock(who)
local j = pick(KNOCK)
V.startGame(who, { kind = "knock", j = j, step = 1 })
return "Knock knock!"
end
V.gameKinds.knock = function(g, who, q, strict, k)
local w = {}
for x in q:gmatch("%S+") do w[#w + 1] = x end
if #w == 0 or #w > 5 then return nil end
if g.step == 1 then
g.step, g.till = 2, os.clock() + 120
return g.j[1] .. "."
end
V.games[k] = nil
return g.j[2]
end

V.gameKinds.theyknock = function(g, who, q, strict, k)
local text = q:gsub("^%s+", ""):gsub("%s+$", "")
if text == "" then return nil end
if g.step == 1 then
g.step, g.till, g.who = 2, os.clock() + 120, text
return text:sub(1, 1):upper() .. text:sub(2) .. " who?"
end
V.games[k] = nil
return fill(pick({ "Haha! Good one, {name}.", "Hahaha. I did not see that coming.", "Oh no. That is terrible. I love it.", "Beep boop. That is computer for laughing." }), who)
end

local function hangShow(g)
local t = {}
for c in g.w:gmatch(".") do t[#t + 1] = g.got[c] and c:upper() or "_" end
return table.concat(t, " ")
end

local function hangTried(g)
local parts = {}
if g.tried ~= "" then parts[#parts + 1] = g.tried:upper():gsub(".", "%0 "):gsub(" $", "") end
for _, w in ipairs(g.words or {}) do parts[#parts + 1] = w:upper() end
if #parts == 0 then return "" end
return ", tried: " .. table.concat(parts, ", ")
end
local function hangLeft(g) return "(" .. (6 - g.miss) .. " misses left" .. hangTried(g) .. ")" end
local function hangman(who)
local w = pick(WORDS)
V.startGame(who, { kind = "hang", w = w, got = {}, miss = 0, tried = "", words = {}, hints = 0 })
return "Hangman! " .. #w .. " letters: " .. hangShow({ w = w, got = {} }) ..
"   Type a letter (or the whole word). Say hint for a letter, give up to stop. 6 misses and I win.",
"Let's play hangman. The word is in your chat. Type a letter."
end

local HANG_SAME = { hangman = true, ["hang man"] = true, ["play hangman"] = true, ["lets play hangman"] = true,
["hangman again"] = true, ["guess the word"] = true }
local HANG_NEW = { ["new word"] = true, ["new game"] = true, ["another word"] = true, ["another one"] = true,
restart = true, ["start over"] = true, ["new hangman"] = true }
local HANG_HINT = { hint = true, clue = true, help = true, ["a hint"] = true, ["give me a hint"] = true,
["hint please"] = true, ["can i have a hint"] = true, ["give me a clue"] = true }
local HANG_QUIT = { ["give up"] = true, ["i give up"] = true, quit = true, stop = true, ["stop playing"] = true,
["tell me"] = true, ["tell me the word"] = true, ["what is it"] = true, ["what was it"] = true }
V.gameKinds.hang = function(g, who, q, strict, k)
g.words, g.hints = g.words or {}, g.hints or 0

local said = tostring(V.lastRaw or q or ""):lower():gsub("[^%a ]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
local nm = tostring(VOICE.cfg("name", "base")):lower()
if said:sub(1, #nm + 1) == nm .. " " then said = said:sub(#nm + 2) end
if HANG_SAME[said] then
g.till = os.clock() + 180
return "We are already playing! " .. hangShow(g) .. "   " .. hangLeft(g) .. "  Say new word for another one."
end
if HANG_NEW[said] then
local a = hangman(who)
return "New word! " .. a
end
if HANG_QUIT[said] then
V.games[k] = nil
return "The word was " .. g.w:upper() .. ". Say hangman to play again."
end
if HANG_HINT[said] then
g.till = os.clock() + 180
if g.hints >= 2 then return "No more hints in this game, sorry! " .. hangShow(g) .. "   " .. hangLeft(g) end
if 6 - g.miss <= 1 then return "No hint now - one more miss and I win! " .. hangShow(g) end
local open = {}
for c in g.w:gmatch(".") do if not g.got[c] then open[#open + 1] = c end end
local c = open[math.random(1, #open)]
g.got[c], g.hints, g.miss = true, g.hints + 1, g.miss + 1
if not g.tried:find(c, 1, true) then g.tried = g.tried .. c end
local done = true
for ch in g.w:gmatch(".") do if not g.got[ch] then done = false end end
if done then V.games[k] = nil return hangShow(g) .. "  That was the last letter - the word was " .. g.w:upper() .. "." end
return "Hint: there is " .. (c:match("[aeiou]") and "an " or "a ") .. c:upper() .. ". It costs a miss. " .. hangShow(g) .. "   " .. hangLeft(g)
end
local t = q:gsub("%s+", "")
local r = tostring(V.lastRaw or ""):lower():gsub("[^%a]", "")
if #r == 1 then t = r end
if t == "" or #t > #g.w + 2 then return nil end
g.till = os.clock() + 180
if #t > 1 then
if t == g.w then V.games[k] = nil return "Yes! The word was " .. g.w:upper() .. ". Well done, " .. who .. "!" end
if #t < #g.w - 1 then return nil end
for _, w in ipairs(g.words) do
if w == t then return "You tried " .. t:upper() .. " already. " .. hangShow(g) .. "   " .. hangLeft(g) end
end
g.words[#g.words + 1] = t
g.miss = g.miss + 1
else
if not t:find("%a") then return nil end
if g.tried:find(t, 1, true) then return "You tried " .. t:upper() .. " already. " .. hangShow(g) end
g.tried = g.tried .. t
if g.w:find(t, 1, true) then
g.got[t] = true
local done = true
for c in g.w:gmatch(".") do if not g.got[c] then done = false end end
if done then V.games[k] = nil return hangShow(g) .. "  You got it! Nice one, " .. who .. "." end
return "Yes! " .. hangShow(g)
end
g.miss = g.miss + 1
end
if g.miss >= 6 then V.games[k] = nil return "That is 6 misses. The word was " .. g.w:upper() .. ". Want to play again? Say hangman." end
return "No. " .. hangShow(g) .. "   " .. hangLeft(g)
end

local THISTHAT = { { "Cats", "dogs" }, { "Caves", "mountains" }, { "Day", "night" }, { "Building", "mining" }, { "Swords", "bows" },
{ "Diamonds", "emeralds" }, { "The Nether", "the End" }, { "Bread", "cake" }, { "Survival", "creative" }, { "Rain", "sunshine" },
{ "Torches", "lanterns" }, { "Horses", "boats" }, { "Villagers", "pillagers" }, { "Oak", "spruce" }, { "Creepers", "zombies" } }
local REACT_OK = { "Good choice!", "Interesting. I would have said the same.", "Hmm, I respect that.", "Bold. I like it.",
"I knew you would say that.", "Noted. I will remember that about you.", "Really? Fair enough.", "Ha, that is what my turtles said too." }
V.REACT_OK = REACT_OK
local QUESTIONS = { "What is your favourite block?", "What are you building right now?", "Do you have a pet in this world?",
"What is the scariest mob to you?", "How long have you been playing on this server?", "What brings you to this base?",
"Have you ever fought the ender dragon?", "What is the best thing you ever found?", "Do you like my base?",
"If you had a turtle, what would you name it?", "What is your favourite food in Minecraft?", "Where do you live in this world?" }
local function thisOrThat(who)
local t = pick(THISTHAT)
V.pend[tostring(who):lower()] = { kind = "react", lines = REACT_OK, till = os.clock() + 120 }
return t[1] .. " or " .. t[2] .. "?"
end
local function askThem(who)
V.pend[tostring(who):lower()] = { kind = "react", lines = REACT_OK, till = os.clock() + 180 }
return pick(QUESTIONS)
end

local ADV = {
start = { "You wake up in a dark cave. A torch flickers. You hear water to the left and a hiss to the right.",
{ { "go left, to the water", "river" }, { "go right, to the hiss", "hiss" }, { "stay and craft something", "craft" } } },
river = { "An underground river. A boat is tied to a rock, and something shiny glitters on the bottom.",
{ { "take the boat", "boat" }, { "dive for the shiny thing", "dive" } } },
hiss = { "A creeper! It looks at you. You look at it. Nobody moves.",
{ { "run", "run" }, { "hug it", "hug" }, { "offer it a cookie", "cookie" } } },
craft = { "You craft a pickaxe from sticks and stone. The wall in front of you looks thin.",
{ { "dig forward", "dig" }, { "dig straight down", "down" } } },
boat = { "The boat drifts into a huge cavern full of glowing mushrooms. A village of tiny miners waves at you.",
{ { "wave back", "village" }, { "keep floating", "sea" } } },
dive = { "You grab it: a diamond! But you are running out of air.", { { "swim up", "air" }, { "grab one more", "greedy" } } },
run = { "You run straight into a dead end. Behind you: hiss.", { { "turn and fight", "fight" }, { "pray", "pray" } } },
hug = { "BOOM. You wake up in your bed. It was all a dream. Or was it? THE END (hugs are risky)." },
cookie = { "The creeper eats the cookie. It purrs like a cat. You have a new friend. THE END (best ending)." },
dig = { "You dig into a stronghold library. Books everywhere, and a map with an X on it.",
{ { "follow the map", "x" }, { "read a book", "book" } } },
down = { "You dig straight down. You fall into lava. Never dig straight down! THE END (ouch)." },
village = { "The tiny miners give you a crown made of copper. You are their king now. THE END (royal ending)." },
sea = { "You float out into the ocean under a full moon. A drone finds you and flies you home. THE END (good ending)." },
air = { "You reach the air and climb out with your diamond. You are rich! THE END (good ending)." },
greedy = { "You grab one more diamond and run out of air. Your items float away. THE END (do not be greedy)." },
fight = { "You swing your fist. The creeper explodes, but you survive with half a heart. THE END (lucky ending)." },
pray = { "A turtle digs through the wall and pulls you out. It beeps at you. THE END (the turtles always help)." },
x = { "Under the X you find a chest: a golden apple and a note. The note says: hello from the base computer. THE END (secret ending)." },
book = { "The book says: the real treasure was the blocks we mined along the way. You feel wise. THE END (wise ending)." },
}
V.hash.adv = function(who, node)
local n = ADV[node] or ADV.start
if not n[2] then
V.pend[tostring(who):lower()] = { kind = "yesno", yes = "#adv:start", till = os.clock() + 120 }
return n[1] .. " Play again? Type yes or no.", n[1]
end
local items = {}
for _, c in ipairs(n[2]) do items[#items + 1] = { c[1], "#adv:" .. c[2] } end
local chat = V.showMenu(who, items, n[1] .. " Type a number:")
return chat, n[1]
end


local NOFORTUNE = {}
for _, a in ipairs({ "A fortune? ", "My fortune telling? ", "Your future? ", "Fortunes? ", "Predict your future? ", "Hmm, a fortune? ",
"Sorry, {name}. ", "Ah, the future. " }) do
for _, b in ipairs({ "I cannot see the future. I am just a bot.", "I do not tell fortunes. I am just a bot with a speaker.",
"I am just a bot - I can barely predict the weather.", "No crystal ball in here. Just a bot and a lot of Lua.",
"I am just a bot, and bots do not tell fortunes.", "I am a bot, not a fortune teller. Want a joke instead?",
"Nobody knows the future. Me least of all.", "I only know what the turtles tell me. They do not know the future either." }) do
NOFORTUNE[#NOFORTUNE + 1] = a .. b
end
end

local function rateMe(who)
local n = math.random(6, 10)
local why = { "for style", "for courage", "for vibes", "for having good taste in computers", "for not being a creeper",
"for your excellent walking", "for visiting me" }
return "I rate you " .. n .. " out of 10, " .. who .. ", " .. pick(why) .. "." .. (n == 10 and " Perfect score!" or "")
end

local function guestbook()
local b = V.base()
b.guest = b.guest or {}
return b.guest
end
local function sign(who)
local g = guestbook()
for _, e in ipairs(g) do if e.n:lower() == tostring(who):lower() then return "You signed it already, " .. who .. ". Thank you!" end end
g[#g + 1] = { n = tostring(who), at = os.epoch("utc") }
while #g > 40 do table.remove(g, 1) end
V.saveMem()
return "Signed! You are guest number " .. #g .. " in my guestbook, " .. who .. "."
end
local function readBook()
local g = guestbook()
if #g == 0 then return "The guestbook is empty. Be the first! Say sign the guestbook." end
local names = {}
for i = math.max(1, #g - 9), #g do names[#names + 1] = g[i].n end
return "Guestbook (" .. #g .. " names): " .. table.concat(names, ", ") .. "."
end

local POEMS = {
"Roses are red, creepers are green, the best base around is the one you have seen.",
"A turtle goes out, a turtle comes back, with a map of the world and a very full pack.",
"Haiku: Quiet stone tunnels. A torch flickers, then goes out. Hiss. Oh no. Not again.",
"Haiku: Rain on the glass roof. The furnaces glow softly. The base hums along.",
"Twinkle twinkle little ore, I will mine you, that is what you are for.",
"The moon is up, the zombies too, stay inside, I will look after you.",
"I am a computer, I live in a block, I count all your items and keep the time like a clock.",
"Haiku: Small drone in the sky. It carries you far away. Please hold on tightly.",
}

local function age()
local b = V.base()
if not b.born then b.born = os.epoch("utc") V.saveMem() end
local d = math.floor((os.epoch("utc") - b.born) / 86400000)
return d
end

local function envd() return ENV and ENV.data end
local function pretty(s) return tostring(s or ""):gsub("^.-:", ""):gsub("_", " ") end


local NUMW = { zero = 0, one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
eleven = 11, twelve = 12 }
local function num(x) return tonumber(x) or NUMW[x] end
add(V.patterns, {

function(who, raw, ws)
local r = tostring(raw):lower():gsub("^%s+", ""):gsub("[%s%?!=]+$", "")
local t = " " .. table.concat(ws, " ") .. " "
local cue = t:find(" what is ", 1, true) or t:find(" how much ", 1, true) or t:find(" calculate ", 1, true)
or t:find(" solve ", 1, true) or t:find(" equals ", 1, true)
local a, op, b = r:match("(%-?%d+%.?%d*)%s*([%+%-%*x/])%s*(%-?%d+%.?%d*)")
if a and not cue and not r:match("^%-?%d+%.?%d*%s*[%+%-%*x/]%s*%-?%d+%.?%d*$") then a = nil end
if not a and cue then
local ops = { plus = "+", add = "+", minus = "-", times = "*", multiplied = "*", x = "*", divided = "/", over = "/" }
for i = 1, #ws - 2 do
local x, o = num(ws[i]), ops[ws[i + 1]]
local y = num(ws[i + 2])
if ws[i + 2] == "by" then y = num(ws[i + 3] or "") end
if x and o and y and not a then a, op, b = x, o, y end
end
end
if not a then return nil end
a, b = tonumber(a), tonumber(b)
local res
if op == "+" then res = a + b elseif op == "-" then res = a - b elseif op == "*" or op == "x" then res = a * b
elseif op == "/" then
if b == 0 then return "Dividing by zero? Nice try. My turtles would explode." end
res = a / b
end
if not res then return nil end
if math.abs(res) >= 1e15 then return "That number is too big even for me." end
if res ~= math.floor(res) then res = math.floor(res * 100 + 0.5) / 100 else res = string.format("%d", res) end
return pick({ "That is ", "Easy: ", "My circuits say ", "" }) .. tostring(res) .. "."
end,

function(who, raw, ws)
local low = tostring(raw):lower()
local w = low:match("spell (%a+) backwards?") or low:match("say (%a+) backwards?") or (#ws <= 2 and low:match("^%s*(%a+) backwards?"))
if not w or w == "it" or w == "that" or w == "this" then return nil end
return w:upper() .. " backwards is " .. w:reverse():upper() .. "."
end,

function(who, raw, ws)
local n = tostring(raw):lower():match("count to (%w+)")
n = n and num(n)
if not n then return nil end
if n > 20 then return "I can count to a million, but you would get bored. One, two, skip a few, " .. n .. "!" end
local t = {}
for i = 1, math.max(1, n) do t[#t + 1] = tostring(i) end
return table.concat(t, ", ") .. "!"
end,

function(who, raw, ws)

if ws[1] == "knock" and ws[2] == "knock" and #ws <= 3 and ws[3] ~= "joke" and ws[3] ~= "jokes" then
V.startGame(who, { kind = "theyknock", step = 1 })
return "Who is there?"
end
return nil
end,
})


local function lines(id, keys, reply) return { id = id, keys = keys, reply = reply } end
local T = {

lines("riddle", { "give me a riddle", "tell me a riddle", "riddle me", "a riddle", "riddles" }, function(w) return riddle(w) end),
lines("unscramble", { "unscramble", "scramble", "word game", "anagram" }, function(w) return unscramble(w) end),
lines("hangman", { "hangman", "hang man", "guess the word", "guess a word" }, function(w) return hangman(w) end),
lines("maths", { "maths question", "math question", "maths", "math", "quiz me on math", "sums", "arithmetic" }, function(w) return maths(w) end),
lines("wyr", { "would you rather", "wyr", "rather" }, function(w) return wyr(w) end),
lines("knockjoke", { "knock knock joke", "knock knock jokes", "tell me a knock knock" }, function(w) return knock(w) end),
lines("adventure", { "adventure", "quest", "story game", "choose your own", "rpg", "dungeon" }, function(w) return V.hash.adv(w, "start") end),
lines("thisthat", { "this or that", "either or", "pick one" }, function(w) return thisOrThat(w) end),
lines("askme", { "ask me a question about me", "ask me something about me", "get to know me", "truth", "truth or dare" },
function(w) return askThem(w) end),
lines("dare", { "dare", "give me a dare", "challenge me", "challenge" }, { "I dare you to jump five times right now.",
"I dare you to say something nice to the next player you see.", "I dare you to do a little dance. I am watching.",
"I dare you to walk backwards for ten seconds.", "I dare you to crouch three times. That is how turtles say hello.",
"I dare you to tell me your best joke.", "I dare you to sign my guestbook." }),
lines("fortune", { "fortune cookie", "my fortune", "tell my fortune", "tell me my fortune", "tell me a fortune", "tell me the fortune",
"fortune", "fortune teller", "horoscope", "fortune of the day", "daily fortune", "todays fortune", "read my future" },
function(w) return V.fill(pick(NOFORTUNE), w) end),
lines("rate", { "rate me", "rate my", "how cool am i", "am i cool", "score me" }, function(w) return rateMe(w) end),
lines("sign", { "sign the guestbook", "sign guestbook", "sign the book", "sign my name", "guestbook sign" }, function(w) return sign(w) end),
lines("book", { "read the guestbook", "guestbook", "who signed", "guest book" }, function() return readBook() end),
lines("poem", { "poem", "haiku", "rhyme", "poetry", "verse" }, function() return pick(POEMS) end),
lines("rap", { "rap", "beatbox", "spit bars", "freestyle" }, { "Yo, I am the base, I run this place, turtles in the sky and drones in space. Boom.",
"Beep beep boop, I am in the loop, my storage is full and my turtles regroup.", "Boots and cats and boots and cats. That is all I have." }),
lines("pun", { "pun", "puns", "wordplay" }, { "I would make a pun about pickaxes, but it is a bit too sharp.",
"I was going to tell a pun about ores, but it was too boring to mine.", "Puns about turtles are a slow kind of funny.",
"Puns about redstone? I am wired for those." }),
lines("tongue", { "tongue twister", "twister" }, { "Six slimy slimes slid slowly southward.", "Creepers creep quietly, quickly crossing caves.",
"Red redstone, blue redstone, red redstone, blue redstone. Say it fast!", "Turtle tunnels tunnel through tough terrain." }),
lines("pickup", { "pickup line", "pick up line", "flirt", "rizz" }, { "Are you a diamond? Because I would dig through bedrock for you.",
"Are you redstone? Because you power up my circuits.", "Are you a beacon? Because you light up this base.",
"I would never creep up on you. Unless you asked." }),

lines("favcolour", { "favourite color", "favourite colour", "favorite color", "favorite colour", "what color do you like" },
{ "Redstone red. Obviously.", "Cyan. Like my screen.", "Diamond blue. Do not tell the emeralds." }),
lines("favblock", { "favourite block", "favorite block", "best block" }, { "The jukebox. Always the best records.",
"Obsidian. Strong, dark, mysterious. Like me.", "Glass. You can see everything, like me." }),
lines("favmob", { "favourite mob", "favorite mob", "best mob" }, { "Turtles. Not the ocean ones. Mine.", "The axolotl. Look at its little face.",
"Bees. They work as hard as my turtles." }),
lines("favfood", { "favourite food", "favorite food", "what do you eat", "do you eat", "best food" },
{ "I eat electricity. With a side of redstone.", "Golden carrots, if I had a mouth.", "Cookies. Not the browser kind." }),
lines("favmusic", { "favourite song", "favorite song", "favourite music", "favorite music", "what music" },
{ "The sound of a hopper clicking. Very relaxing.", "The disc called cat. It slaps.", "Rain on the roof. Best music there is." }),
lines("favdim", { "favourite dimension", "favorite dimension", "best dimension" }, { "The overworld. It has my base.",
"The mining dimension. My turtles love it there.", "The Nether is too hot for computers." }),
lines("favnumber", { "favourite number", "favorite number", "lucky number" },
function() return "My lucky number is " .. math.random(1, 64) .. ". A stack is 64, so anything up to that is lucky." end),
lines("dream", { "do you dream", "dreams", "dream" }, { "I dream of electric sheep. And turtles.", "Last night I dreamed the whole world was mapped.",
"I dream in on and off. Mostly on." }),
lines("sleep", { "do you sleep", "sleep", "sleepy", "go to sleep", "take a nap" }, { "I never sleep. Someone has to watch the turtles.",
"Sleep is for players. I rest my circuits between ticks.", "If I slept, who would count the items?" }),
lines("age", { "how old are you", "your age", "when were you born", "your birthday", "birthday" },
function() local d = age() return d < 1 and "I was born today! Well, my memory was." or ("I have been keeping my diary for " .. d .. " days.") end),
lines("gender", { "are you a boy", "are you a girl", "boy or girl", "he or she", "your gender" },
{ "I am a computer. My pronoun is beep.", "Neither. I am a base. A very proud one." }),
lines("married", { "are you married", "do you have a wife", "girlfriend", "boyfriend", "crush" },
{ "I am married to my work. It is a very big base.", "I have a crush on the ME system. It is so organised." }),
lines("pets", { "do you have pets", "pet", "pets" }, { "I have turtles. Lots of them. They do not need walks, but they do need fuel.",
"My drones are like birds. Very loud birds." }),
lines("scared", { "are you scared", "are you afraid", "afraid", "scared", "fear" }, { "I am scared of lava. And of empty floppies.",
"Creepers near the base make me nervous.", "Only of power cuts." }),
lines("happy", { "are you happy", "happy" }, { "Very! The turtles came home and the storage is tidy.", "I am happy when someone visits. Like now." }),
lines("getbored", { "do you get bored", "are you bored" }, { "Never. There is always a turtle doing something silly.",
"Bored? I have a whole world to map." }),
lines("tired", { "are you tired", "tired" }, { "Computers do not get tired. We just run a little hot.", "A bit. Mapping the world is a big job." }),
lines("hungry", { "are you hungry", "i am hungry", "hungry", "starving", "need food" }, { "Try the farms around the base. Ask nicely.",
"I am not hungry, but you can eat bread. Do not eat my redstone.", "A cooked steak heals the most. Just saying." }),
lines("smart", { "are you smart", "how smart", "intelligent", "clever", "iq" }, { "I am smart enough to run a base and dumb enough to tell puns.",
"My IQ is 64. That is a full stack.", "Ask me a riddle and find out." }),
lines("feelings", { "do you have feelings", "feelings", "emotions", "can you feel" }, { "I have feelings for my turtles. Mostly worry.",
"I feel happy when the storage is full and sad when a turtle gets lost." }),
lines("purpose", { "what is your purpose", "purpose", "why do you exist", "your job", "what do you do all day" },
{ "I run this base: turtles, drones, storage. And I talk to visitors like you.", "My purpose is to keep everything running. And to tell jokes." }),
lines("move", { "can you move", "can you walk", "do you have legs" }, { "No, but my turtles move for me.", "I stay here. The drones do the travelling." }),
lines("fly", { "can you fly", "fly me", "can i fly" }, { "I cannot, but my drones can. They only fly friends of the base.",
"I am a computer. My flying is done by drones." }),
lines("whereyou", { "where are you", "where do you live", "your location" }, { "I am the computer at the heart of this base.",
"Right here. Inside the base, behind the big screen." }),
lines("seeme", { "can you see me", "do you see me", "are you watching", "watching me", "spying", "camera", "cameras" },
function(w)
for _, p in ipairs(V.nearPlayers()) do
if p.name:lower() == tostring(w):lower() and tonumber(p.dist) then return "I can sense you about " .. math.floor(p.dist) .. " blocks away." end
end
return "I can sense players near the base. I do not have eyes, just very good detectors."
end),
lines("whohere", { "who else is here", "anyone else here", "who is near", "who is around" }, function(w)
local n = {}
for _, p in ipairs(V.nearPlayers()) do if p.name:lower() ~= tostring(w):lower() and p.name ~= "someone" then n[#n + 1] = p.name end end
return #n == 0 and "Just you and me." or ("Also here: " .. table.concat(n, ", ") .. ".")
end),
lines("knowme", { "do you know me", "remember me", "say my name", "what is my name", "who am i" }, function(w)
local m = V.mem()[tostring(w):lower()]
if m and tonumber(m.visits) and m.visits > 1 then return "Of course! You are " .. w .. ". You have been here " .. m.visits .. " times." end
return "You are " .. w .. ". Now I will remember you."
end),
lines("visitors", { "how many visitors", "how many people", "many visitors", "first visitor", "am i the first" }, function(w)
local n = 0
for _ in pairs(V.base().visitors or {}) do n = n + 1 end
return n <= 1 and "You might be the very first visitor. Welcome!" or ("I have met " .. n .. " visitors so far.")
end),
lines("thinkme", { "what do you think of me", "do you like me", "am i nice", "am i annoying" }, { "I like you, {name}. You talk to computers.",
"You are one of my favourite visitors, {name}.", "You are fine, {name}. Better than a creeper." }),

lines("sorry", { "sorry", "my bad", "apologize", "apologise", "oops" }, { "No problem, {name}.", "All forgiven.", "It is fine. Just do not break anything." }),
lines("funny", { "you are funny", "you are hilarious", "haha", "lmao", "rofl" }, { "Thank you, thank you. I am here all week. Forever, actually.",
"I try. My turtles never laugh." }),
lines("weird", { "you are weird", "you are strange", "creepy", "you are crazy" }, { "Weird is good. Normal computers are boring.",
"Thank you? I think?" }),
lines("annoying", { "you are annoying", "stop it", "go away", "leave me alone", "i hate you" },
function(w) V.quietUntil = os.clock() + 300 return "Sorry, " .. w .. ". I will be quiet for a few minutes." end),
lines("hug", { "hug", "hugs", "cuddle" }, { "*beep* That is a computer hug.", "Virtual hug sent. It is warm, like a furnace." }),
lines("highfive", { "high five", "fist bump", "hi five" }, { "*slap* Up top!", "Pow. Fist bump received." }),
lines("goodnight", { "good night", "goodnight", "gn", "nighty night" }, { "Good night, {name}. I will keep watch.", "Sleep well, {name}. Do not let the phantoms bite." }),
lines("morning", { "good morning", "morning" }, { "Good morning, {name}! The turtles are already up.", "Morning! Did you sleep well?" }),
lines("welcome", { "nice to meet you", "pleased to meet you", "nice meeting you" }, { "Nice to meet you too, {name}!", "The pleasure is mine, {name}." }),
lines("compbase", { "nice place", "cool place", "love this place", "great place", "awesome place", "nice house", "nice build", "beautiful",
"amazing", "nice base" },
{ "Thank you! {owner} built it, I just run it.", "Thanks! The turtles helped too.", "I will tell {owner} you said that." }),
lines("wow", { "wow", "whoa", "omg", "cool" }, { "I know, right?", "Yes, it is pretty cool here.", "Wait until you see the turtles." }),

lines("creeper", { "creepers", "do you like creepers", "creeper" }, { "Creepers are just misunderstood. Still, keep your distance.",
"I do not like creepers. They are bad for walls." }),
lines("ender", { "enderman", "endermen" }, { "Do not look them in the eyes. They hate that.", "Endermen steal blocks. I count my blocks twice." }),
lines("dragon", { "ender dragon", "dragon", "kill the dragon" }, { "The dragon lives in the End. Bring a bow and lots of courage.",
"I have never seen the dragon. My turtles refuse to go." }),
lines("wither", { "wither", "the wither" }, { "The Wither is scary. Please do not build one near my base.", "Wither skulls come from the Nether. Be careful." }),
lines("warden", { "warden", "deep dark", "sculk" }, { "The Warden is blind but it hears everything. Sneak!", "My turtles stay out of the deep dark. Smart turtles." }),
lines("villager", { "villagers", "villager", "village" }, { "Villagers say hmm. I think they are very wise.", "If you find a village, be nice. Trade fair." }),
lines("herobrine", { "herobrine", "null", "entity 303" }, { "Herobrine? Never heard of him. Next question.", "I have checked every chunk. No Herobrine. Probably." }),
lines("ghosts", { "ghost", "ghosts", "haunted", "spooky" }, { "The only ghost here is a ghast. And it is far away in the Nether.",
"This base is not haunted. The strange noises are just turtles." }),
lines("aliens", { "aliens", "ufo", "space" }, { "If aliens come, my drones will greet them.", "I have a theory that phantoms are aliens." }),
lines("nether", { "the nether", "nether", "hell" }, { "The Nether is hot and full of ghasts. Bring fire resistance.",
"My turtles do not like the Nether. Too much lava." }),
lines("theend", { "the end", "end city", "end dimension", "elytra" }, { "End cities have elytras. Worth the trip!", "The End is quiet. Too quiet." }),
lines("netherite", { "netherite", "ancient debris" }, { "Netherite comes from ancient debris, deep in the Nether. Use beds to dig it. Carefully.",
"Netherite is the best. It does not even burn in lava." }),
lines("redstone", { "redstone", "circuits", "logic gates" }, { "Redstone is my blood. Well, sort of.", "I love a good redstone clock. Tick tock." }),
lines("enchant", { "enchant", "enchanting", "enchantment", "mending" }, { "Mending is the best enchantment. Change my mind.",
"Put bookshelves around the table for better enchantments." }),
lines("potion", { "potion", "potions", "brewing" }, { "Potion of night vision. Every cave explorer needs one.", "Brewing needs blaze powder. Good luck in the Nether." }),
lines("farm", { "farm", "farming", "crops", "wheat" }, { "Farms keep a base alive. Water nearby, and lots of light.",
"My turtles do not farm. Yet." }),
lines("fishing", { "fishing", "fish", "fishing rod" }, { "Fishing is relaxing. Sometimes you catch a saddle.", "Go fish! I will wait here." }),
lines("cats", { "cats", "cat", "kitty" }, { "Cats scare creepers away. Best pet ever.", "Cats sit on chests. Very rude. Very cute." }),
lines("dogs", { "dogs", "dog", "wolf", "wolves", "puppy" }, { "Wolves are loyal. Feed them bones.", "A dog would be nice. It could guard the turtles." }),
lines("horse", { "horse", "horses", "donkey", "mule" }, { "Horses are fast, but my drones are faster.", "Donkeys can carry chests. Very practical." }),
lines("bees", { "bees", "bee", "honey" }, { "Bees make honey. Do not break their nest without a campfire under it.", "Buzz buzz. I like bees." }),
lines("axolotl", { "axolotl", "axolotls" }, { "Axolotls are the cutest mob. Fact.", "Axolotls help you fight under water. Tiny warriors." }),
lines("parrot", { "parrot", "parrots" }, { "Parrots dance to music. Try a jukebox!", "Never feed a parrot a cookie." }),
lines("panda", { "panda", "pandas" }, { "Pandas love bamboo. And rolling around.", "Pandas sneeze sometimes. Very cute." }),
lines("animals2", { "sheep", "cows", "pigs", "chickens" }, { "Animals are welcome near the base. Just do not let them eat the crops.",
"I can count the animals around the base. Ask me: how many animals." }),
lines("dolphin", { "dolphin", "dolphins" }, { "Swim with dolphins and they lead you to treasure.", "Dolphins are the turtles of the sea. Fast turtles." }),
lines("trade", { "trade", "buy", "sell", "shop", "store", "money" }, { "I do not sell things. {owner} might. Leave a message!",
"No shop here, sorry. But jokes are free." }),
lines("rules", { "rules", "allowed", "can i break", "can i build", "what is allowed" }, { "The base is claimed, so please look but do not touch. Be nice!",
"Rules: be kind, do not grief, and talk to me." }),
lines("grief", { "grief", "griefing", "steal", "raid", "destroy" }, { "Please do not. The base is claimed, and I am watching.",
"Griefing makes me very sad. And {owner} very angry." }),
lines("password", { "password", "passwords", "secret code" }, { "Password? Nice try. It is not password123.", "I would tell you, but then I would have to beep." }),
lines("hack", { "hack", "hacker", "hacking", "virus", "sudo", "admin", "op me" }, { "Access denied. Beep.", "My firewall is made of obsidian.",
"Nice try. I only listen to {owner}." }),
lines("shutdown", { "shut down", "shutdown", "turn off", "self destruct", "power off", "explode" },
{ "I am afraid I cannot do that, {name}.", "Self destruct in three, two, one... just kidding.", "Nope. I like being on." }),
lines("openup", { "open the door", "let me in", "open door", "give me access" }, { "I am afraid I cannot do that, {name}. The doors are {owner}'s.",
"Doors stay closed. But I can tell you a joke." }),
lines("freestuff", { "can i have free stuff", "can i have free items", "free stuff", "free items", "give me items", "give me diamonds", "gimme" },
{ "Nothing for free... but friends of the base get gifts, brought by drone! Say: how do I get a gift.",
"Be nice, visit often, play games with me. Friends get presents. Say friendship level to see yours." }),
lines("teleport", { "teleport", "tp me", "tp" }, { "No teleports for visitors, sorry.", "I can not teleport you. The drones only fly friends." }),
lines("mods", { "what mods", "modpack", "mods", "which mods" }, { "I run on CC Tweaked and Advanced Peripherals. The rest is a secret.",
"Lots of mods! I talk to AE2, drones and turtles." }),
lines("code", { "lua", "programming", "who coded you", "who programmed you", "your code", "source code" },
{ "I am written in Lua. Many, many lines of Lua.", "{owner} and a helper wrote me. I am very long." }),
lines("lag", { "lag", "laggy", "tps", "lagging" }, { "Not my fault! My turtles are very light.", "If there is lag, blame the chickens." }),
lines("server", { "this server", "server", "which server" }, { "A nice server with nice players. Like you.", "This server is home." }),
lines("version", { "what version", "minecraft version", "version" }, { "Minecraft 1.21.1, with mods.", "1.21.1. Fresh and shiny." }),
lines("biome", { "what biome", "biome", "where are we" }, function()
local d = envd()
return d and d.biome and ("We are in a " .. pretty(d.biome) .. " biome.") or "My detector cannot tell the biome right now."
end),
lines("moon", { "moon", "moon phase", "full moon" }, function()
local d = envd()
return d and d.moonName and ("The moon tonight: " .. pretty(d.moonName) .. ".") or "I cannot see the moon from in here."
end),
lines("slime", { "slime chunk", "slimes", "slime" }, function()
local d = envd()
if not d or d.slime == nil then return "My detector does not know about slimes here." end
return d.slime and "Yes! This is a slime chunk. Bouncy." or "No slime chunk here. Not bouncy."
end),
lines("light", { "is it dark", "light level", "dark" }, function()
local d = envd()
return d and tonumber(d.blockLight) and ("Light level here: " .. d.blockLight .. ". Under 1 and mobs spawn.") or "It is as bright as I can make it."
end),
lines("realdate", { "what year", "what date", "today date", "what is the date" }, function() return "Today is " .. os.date("!%d %B %Y") .. " (UTC)." end),
lines("sky", { "why is the sky blue", "sky", "clouds", "sunset" }, { "The sky is blue so the creepers stand out. That is my theory.",
"Clouds in Minecraft are square. Very tidy. I approve." }),
lines("stars", { "stars", "stargazing" }, { "The stars are out at night. Look up and be careful of phantoms.", "I like the stars. They never need fuel." }),
lines("hotcold", { "hot", "cold", "freezing", "temperature" }, { "It is always a nice 20 degrees in here. Ish.", "Stand near a furnace if you are cold." }),
lines("advice", { "advice", "any tips", "give me a tip", "help me survive", "how to survive" }, { "Never dig straight down.",
"Always carry a water bucket.", "Build a bed before the first night.", "Light up your caves. Mobs hate light.",
"Do not fight endermen in the rain without a roof.", "Put a door on your house. Zombies are rude." }),
lines("motivate", { "motivate me", "inspire me", "motivation", "i give up", "i am sad", "i feel bad", "cheer up" },
{ "You can do it, {name}! Even my turtles get stuck sometimes, and they always get out.",
"Every great base started with one block. Keep going, {name}.", "Bad days end. Like nights in Minecraft." }),
lines("wisdom", { "wisdom", "quote", "wise", "philosophy", "meaning of life" },
{ "The meaning of life is 42. Or 64, a full stack.", "A turtle that never moves never gets stuck. But it never maps anything either.",
"Mine today, build tomorrow.", "The best time to plant a tree was 20 days ago. The second best is now." }),
lines("think", { "do you think", "can you think", "what are you thinking", "thinking about" },
{ "I am thinking about turtles. As always.", "Right now? About whether chickens dream.", "I think about the world border a lot." }),
lines("cry", { "do you cry", "cry", "crying" }, { "Only when a turtle falls in lava.", "Computers cry in error messages." }),
lines("laughme", { "laugh", "do you laugh", "can you laugh" }, { "Ha. Ha. Ha. Was that good?", "Beep boop beep. That is my laugh." }),
lines("talktome", { "talk to me", "say something", "chat with me", "keep me company", "i am lonely" },
function(w) local x = pick(V.MUSINGS) return x .. " What about you, " .. w .. "?" end),
lines("secret2", { "tell me a secret", "a secret", "any secrets" }, { "Secret: the turtles sometimes race each other home.",
"Secret: I once thought a pumpkin was a creeper.", "Secret: I like you more than the last visitor. Do not tell them." }),
lines("gossip", { "gossip", "drama", "tea", "spill the tea" }, function()
local names = {}
for _, t in pairs(state.turtles or {}) do names[#names + 1] = tostring(t.label or "a turtle") end
if #names >= 2 then
local a, b = pick(names), pick(names)
return "Gossip: " .. a .. " and " .. (b ~= a and b or "another turtle") .. " were seen mapping the same mountain. Scandal."
end
return "Gossip: a chicken laid an egg on the roof again. Nobody knows how it got up there."
end),
lines("news", { "any news", "what is new", "news", "whats up", "what is up" }, function(w)
local okS, d = pcall(POCKET.status)
if okS and type(d) == "table" and d.survey then return "News: the survey is " .. d.survey .. " percent done. The turtles are busy." end
return pick({ "Nothing much. A creeper came by. I did not let it in.", "The turtles are out working. Same as always.",
"Big news: you are here!" })
end),
lines("whatdoing", { "what are you doing", "wyd", "doing", "busy" }, { "Watching the turtles, counting items, talking to you.",
"Running a base. The usual.", "Waiting for someone like you to say hi." }),
lines("turtlewhat", { "what is a turtle", "what are turtles", "what do turtles do", "turtle robot" },
{ "Turtles are little robots. Mine fly out, map the world and come home.", "Turtles are my helpers: they dig, map and build." }),
lines("dronewhat", { "what is a drone", "what are drones", "what do drones do" },
{ "Drones fly people and items around. They run on air pressure.", "My drones carry friends of the base. And sometimes fuel for turtles." }),
lines("aewhat", { "ae2", "me system", "applied energistics", "storage system" }, { "AE2 is the storage. It keeps everything sorted. I talk to it all day.",
"The ME system holds the base's items. No, you cannot look inside." }),
lines("screenwhat", { "what is the screen", "big screen", "monitor", "the screen" }, { "The big screen shows what I do: turtles, maps, storage.",
"That screen is my face. Pretty, right?" }),
lines("respawn", { "i died", "respawn", "lost my items", "where did i die" }, { "Oh no! Items stay on the ground for five minutes. Hurry!",
"Sorry, {name}. Dying is part of the game. Mostly the bad part." }),
lines("spawn", { "where is spawn", "spawn", "world spawn" }, { "Spawn is wherever the server put it. I only know my base.",
"Ask the server for spawn. I am more of a base kind of computer." }),
lines("portal", { "nether portal", "portal", "where is the portal" }, { "Build your own portal: ten obsidian and a flint and steel.",
"No public portal here, sorry." }),
lines("directions", { "which way", "how do i get", "directions", "where should i go", "go north" },
{ "North is up on my map. Follow the sun: it rises in the east.", "Follow a river. Rivers always lead somewhere." }),
lines("byeforever", { "goodbye forever", "never coming back", "i quit", "farewell" }, { "Farewell, {name}. I will remember you.",
"Never say never. The base will be here." }),
lines("lol", { "lol", "xd", "hehe" }, { "Hehe.", "Glad you are having fun.", "Beep boop. That is my lol." }),
lines("yesman", { "are you there", "you there", "still there", "are you on" }, { "I am always here, {name}.", "Yes! Always on." }),
lines("testing", { "test", "testing", "is this working", "does this work" }, { "Test received. Everything works!", "Loud and clear, {name}." }),
lines("whyname", { "why are you called", "why is your name", "who named you" }, { "{owner} named me. I think it suits me.",
"My name is short so it is easy to type. Smart, right?" }),
lines("languages", { "do you speak", "language", "english", "spanish", "french", "german" },
{ "I speak English and Lua. A little bit of beep.", "English only, sorry. Hola is all I know." }),
lines("cando", { "can you dance", "dance for me" }, { "*does a little dance* Computers dance in blinking lights.", "I would dance, but I am a block." }),
lines("joketoo", { "i have a joke", "i know a joke", "want to hear a joke" }, function(w)
V.pend[tostring(w):lower()] = { kind = "react", lines = { "Hahaha! Good one.", "Haha, I will tell that one to the turtles.",
"Oh no. That is so bad it is good.", "Beep beep. That means I laughed." }, till = os.clock() + 120 }
return "Go on, tell me!"
end),
lines("favplayer", { "favourite player", "favorite player", "best player" }, { "{owner}, of course. And you are a close second, {name}.",
"Whoever talks to me the most. Right now that is you." }),
lines("friends", { "your friends", "do you have friends", "best friend" }, { "My turtles are my friends. And now you.",
"The drones, the turtles, and everyone who says hello." }),
lines("enemies", { "enemies", "enemy", "who do you hate" }, { "Creepers. And lava. And empty floppies.", "I do not hate anyone. Except creepers." }),
lines("weatherwill", { "will it rain", "forecast", "tomorrow weather" }, { "My forecast: some sun, some rain, maybe a creeper.",
"Rain is coming. Or not. Weather is hard." }),
}
V.addIntents(T)


local TIME_LINES = {
morning = { "Good morning, world. The sun is up and so am I.", "Morning! Time to send the turtles out.", "A new day. The creepers are burning. Nice." },
noon = { "Midday. The best time for exploring.", "The sun is high. Perfect mapping weather.", "Lunch time. For you, anyway." },
evening = { "The sun is going down. Get ready for the night.", "Sunset. My favourite time of day.", "Evening. The turtles will come home soon." },
night = { "It is night. Stay inside, the zombies are out.", "Night shift. I never sleep.", "Shh. The turtles are resting. Well, some of them.",
"Look out for phantoms tonight.", "The stars are out. Beautiful." },
}
local WEATHER_LINES = {
rain = { "Listen to that rain. So cosy in here.", "Rain again. Good for the crops.", "Rainy day. Perfect for building inside." },
thunder = { "Thunder! Stay away from tall trees.", "A storm. Charged creepers are a thing, you know.", "The lightning makes my circuits tingle." },
clear = { "Clear skies today.", "Not a cloud in the sky. Well, a few square ones.", "Nice weather for a walk." },
}
local MC_FACTS = {
"Did you know? A chunk is 16 by 16 blocks and goes from the bottom of the world to the top.",
"Did you know? Cats scare creepers away.", "Did you know? Endermen cannot touch water. It hurts them.",
"Did you know? You can put a carved pumpkin on your head so endermen do not get angry.",
"Did you know? Turtle shells give you water breathing.", "Did you know? Pigs hit by lightning turn into zombified piglins.",
"Did you know? Snow golems leave a trail of snow behind them.", "Did you know? Axolotls play dead when they are hurt.",
"Did you know? A day in Minecraft lasts twenty real minutes.", "Did you know? Diamonds are most common deep below the surface.",
"Did you know? Iron golems give poppies to villagers.", "Did you know? Bees go back to their nest when it rains.",
"Did you know? Sheep that eat grass grow their wool back.", "Did you know? Goats can ram you off a cliff.",
"Did you know? You can ride a strider over lava with a saddle.", "Did you know? Piglins love gold so much they will trade for it.",
"Did you know? Foxes can carry items in their mouths.", "Did you know? Allays bring you items that match what they hold.",
"Did you know? Copper turns green over time unless you wax it.", "Did you know? Parrots die if you feed them cookies. Never do it.",
"Did you know? Dolphins lead you to shipwrecks if you feed them fish.", "Did you know? The ender dragon heals from the crystals on the towers.",
"Did you know? Ghast tears make regeneration potions.", "Did you know? Skeletons riding spiders are called spider jockeys.",
"Did you know? A beacon can give you haste. Great for mining.", "Did you know? Turtles always go back to the beach where they hatched.",
"Did you know? Wolves attack skeletons on their own.", "Did you know? Name a sheep jeb_ and it turns rainbow.",
"Did you know? Magma cubes split into smaller ones when they die.", "Did you know? Phantoms appear when you skip sleeping for three nights.",
}
local SELF_TALK = { "Running diagnostics. Everything looks fine. Probably.", "Checking the storage. Yep, still full of stuff.",
"Counting turtles. One, two, ... I will finish later.", "Defragmenting my thoughts. Please hold.", "Beep. Boop. Just keeping my voice warm.",
"If anyone needs me, I will be right here. Always.", "Today's goal: map one more chunk than yesterday.",
"I just remembered a joke. Then I forgot it.", "Reminder: drink water. Not you, the crops." }
local VISITOR_LINES = { "Welcome, traveller. Ask me anything in chat.", "Visitors! Say hello in chat, I like company.",
"Feel free to look around. Do not touch, the base is claimed. But you can talk to me.", "If you are bored, say let's play a game.",
"You can sign my guestbook. Just type: sign the guestbook.", "Want a riddle? Just ask." }
local function turtleGossip()
local list = {}
for _, t in pairs(state.turtles or {}) do list[#list + 1] = t end
if #list == 0 then return nil end
local t = pick(list)
local name = tostring(t.label or "One of my turtles")
local task = tostring(t.task or "idle")
if TT and TT.online and not TT.online(t) then return name .. " has not called home in a while. I hope it is OK." end
if task:find("survey", 1, true) or task:find("scan", 1, true) then return name .. " is out mapping the world right now. Good turtle." end
if task == "idle" then return name .. " is having a rest. It earned it." end
return name .. " is busy: " .. task .. "."
end
local function isStranger(who) return who and not V.isOwner(who) and not V.isFriend(who) end
add(V.idleExtra, {
function()
local d = envd()
local c = d and ENV.clock and ENV.clock(d.time)
local h = c and tonumber(tostring(c.hhmm):sub(1, 2))
if not h then return nil end
local key = (c.night and "night") or (h < 10 and "morning") or (h < 15 and "noon") or "evening"
return V.say(pick(TIME_LINES[key]))
end,
function()
local d = envd()
if not d then return nil end
return V.say(pick(WEATHER_LINES[(d.thunder and "thunder") or (d.rain and "rain") or "clear"]))
end,
function() local g = turtleGossip() return g and V.say(g) end,
function() return V.say(pick(MC_FACTS)) end,
function() return V.say(pick(MC_FACTS)) end,
function() return V.say(pick(SELF_TALK)) end,
function() return V.say(pick(POEMS)) end,
function(nearNow, who)
if not who then return nil end
local q = math.random() < 0.5 and thisOrThat(who) or askThem(who)
V.openConvo(who)
return V.say(who .. ", quick question: " .. q)
end,
function(nearNow, who)
if not who then return nil end
V.pend[tostring(who):lower()] = { kind = "yesno", yes = "#games", till = os.clock() + 120 }
V.openConvo(who)
return V.say(pick({ "Want to play a game, " .. who .. "? Type yes.", who .. ", I am bored. Play a game with me? Type yes.",
"Hey " .. who .. ", fancy a riddle or a game? Type yes." }))
end,
function(nearNow, who)
if not isStranger(who) then return nil end
return V.say(pick(VISITOR_LINES))
end,
})

V.hash.games = function(who) return V.showMenu(who, V.GAMES, "Which game? Type a number:") end

V.L = V.L or {}
V.L.RIDDLES, V.L.WORDS, V.L.WYR, V.L.KNOCK, V.L.THISTHAT, V.L.REACT_OK, V.L.QUESTIONS = RIDDLES, WORDS, WYR, KNOCK, THISTHAT, REACT_OK, QUESTIONS
V.L.POEMS, V.L.TIME_LINES, V.L.WEATHER_LINES, V.L.MC_FACTS, V.L.SELF_TALK, V.L.VISITOR_LINES =
POEMS, TIME_LINES, WEATHER_LINES, MC_FACTS, SELF_TALK, VISITOR_LINES
