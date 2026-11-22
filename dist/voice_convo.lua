























local V = VOICE
if not (V and V.addIntents and V.patterns and V.pend and V.hash) then return end
V.packs = V.packs or {}
V.packs["voice_convo.lua"] = { version = 1 }
local C = {}
V.CONVO = C
C.state = {}
C.temp = {}
local function pick(l) return V.pick(l) end
local function low(s) return tostring(s or ""):lower() end
local function T(ws) return " " .. table.concat(ws, " ") .. " " end
local function has(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return p end end return nil end
local function set(list) local s = {} for _, w in ipairs(list) do s[w] = true end return s end
local function cap(s) s = tostring(s or "") return s:sub(1, 1):upper() .. s:sub(2) end
local function inSpawn() return V.SPAWN and V.SPAWN.inSpawn and V.SPAWN.inSpawn() or false end

local function combos(A, B) local out = {} for _, a in ipairs(A) do for _, b in ipairs(B) do out[#out + 1] = a .. b end end return out end
C.combos = combos

C.NOSAID = setmetatable({}, { __mode = "k" })
function C.line(list, who, said)
if type(list) ~= "table" or #list == 0 then return "" end
local l
if said then l = pick(list)
else
local ns = C.NOSAID[list]
if not ns then
ns = {}
for _, x in ipairs(list) do if not tostring(x):find("{said}", 1, true) then ns[#ns + 1] = x end end
C.NOSAID[list] = ns
end
l = #ns > 0 and pick(ns) or pick(C.ANY_PLAIN)
end
l = tostring(l)
if said then
l = l:gsub("^{said}", function() return cap(said) end)
l = l:gsub("{said}", function() return said end)
end
return V.fill(l, who)
end


function C.rec(who, make)
local m, k = V.mem(), low(who)
if type(m[k]) == "table" then return m[k] end

if C.temp[k] and make and not inSpawn() then m[k], C.temp[k] = C.temp[k], nil return m[k] end
if C.temp[k] then return C.temp[k] end
if not make then return nil end

if inSpawn() then
C.tempN = (C.tempN or 0) + 1
if C.tempN > 300 then C.temp, C.tempN = {}, 1 end
C.temp[k] = {}
return C.temp[k]
end
m[k] = {}
return m[k]
end
function C.dirty() C.saveDue = C.saveDue or (os.clock() + 60) end
V.tickHooks[#V.tickHooks + 1] = function()
if C.saveDue and os.clock() >= C.saveDue then C.saveDue = nil pcall(V.saveMem) end
end
local function listAdd(list, v, max)
for i = #list, 1, -1 do if list[i] == v then table.remove(list, i) end end
list[#list + 1] = v
while #list > max do table.remove(list, 1) end
end
local function listDel(list, v)
local n = 0
for i = #list, 1, -1 do if list[i] == v then table.remove(list, i) n = n + 1 end end
return n > 0
end
function C.setFav(who, key, v)
if not v or v == "" then return end
local r = C.rec(who, true)
r.fav = type(r.fav) == "table" and r.fav or {}
local n = 0
for _ in pairs(r.fav) do n = n + 1 end
if n >= 16 and not r.fav[key] then return end
r.fav[key] = v:sub(1, 30)
C.dirty()
end
function C.setInfo(who, key, v)
if not v or v == "" then return end
local r = C.rec(who, true)
r.info = type(r.info) == "table" and r.info or {}
local n = 0
for _ in pairs(r.info) do n = n + 1 end
if n >= 12 and not r.info[key] then return end
r.info[key] = v:sub(1, 30)
C.dirty()
end
function C.like(who, v, hate)
if not v or v == "" then return end
v = v:sub(1, 30)
local r = C.rec(who, true)
r.likes = type(r.likes) == "table" and r.likes or {}
r.hates = type(r.hates) == "table" and r.hates or {}
if hate then listDel(r.likes, v) listAdd(r.hates, v, 8) else listDel(r.hates, v) listAdd(r.likes, v, 10) end
C.dirty()
end
function C.modSeen(who, mod, liked, make)
local r = C.rec(who, make)
if not r then return end
r.mods = type(r.mods) == "table" and r.mods or {}
local e = type(r.mods[mod.n]) == "table" and r.mods[mod.n] or { c = 0 }
e.c = math.min(999, (tonumber(e.c) or 0) + 1)
if liked ~= nil then e.l = liked end
local n = 0
for _ in pairs(r.mods) do n = n + 1 end
if n >= 12 and not r.mods[mod.n] then return end
r.mods[mod.n] = e
C.dirty()
end



C.STOP = { "bye", "goodbye", "gtg", "got to go", "gotta go", "i have to go", "leave me alone", "shut up", "go away", "stop talking",
"stop asking", "no more questions", "be quiet", "i am leaving", "cya", "see ya", "see you later", "talk later", "good night", "stfu",
"bye bye", "i need to go", "i must go", "stop the chat", "stop chatting", "stop it", "please stop", "end chat" }
C.STOP_WEAK = { "stop", "nvm", "nevermind", "never mind", "enough", "not now", "busy", "later", "gn", "quiet", "shh", "shush", "brb", "afk",
"i am busy", "see you", "leave", "no thanks", "no thank you" }
C.STOPW = set(C.STOP_WEAK)

C.BADW = { "fuck", "fuk", "shit", "bitch", "cunt", "dick", "pussy", "nigg", "fag", "retard", "whore", "slut", "porn", "nazi",
"hitler", "penis", "vagina", "boob", "tits", "asshole", "bastard", "wank", "kys", "dumbass", "motherf", "twat", "bollock", "sexy" }
C.BADX = set({ "ass", "arse", "cum", "piss", "rape", "raped", "raping", "rapist", "cock", "cocks", "sex", "nigga", "hoes" })
function C.isBad(ws, t)
if t:find(" kill yourself ", 1, true) or t:find(" kill urself ", 1, true) then return true end
for _, w0 in ipairs(ws) do

local w1, n = w0, 0
repeat w1, n = w1:gsub("(%a)%1", "%1") until n == 0
for _, w in ipairs({ w0, w1 }) do
if C.BADX[w] then return true end
for _, b in ipairs(C.BADW) do if w:sub(1, #b) == b then return true end end
end
end
return false
end
C.YES = set({ "yes", "yess", "definitely", "totally", "absolutely", "ofc", "always", "kinda", "obviously", "indeed", "yah", "aye", "true",
"correct", "yesh", "duh", "certainly", "def", "si", "ja", "oui" })
C.YES_P = { "of course", "i do", "a lot", "for sure", "i have", "i am", "i did", "love it", "you bet", "heck yes", "why not", "sort of",
"a bit", "a little", "i guess so", "i think so", "kind of", "very much", "all the time", "every day", "sometimes" }
C.NO = set({ "no", "never", "nop", "nay", "negative", "noo", "nein", "non", "nada" })
C.NO_P = { "not really", "i do not", "i have not", "i am not", "i did not", "not at all", "no way", "not yet", "hate it", "of course not",
"not much", "not a lot", "i can not", "i could not", "not anymore", "i never" }
C.IDK = set({ "dunno", "maybe", "whatever", "hmm", "hm", "unsure", "idc", "perhaps", "eh", "idek", "dno" })
C.IDK_P = { "i do not know", "not sure", "no idea", "no clue", "who knows", "i do not care", "depends", "hard to say", "can not decide",
"i forgot", "i do not remember", "good question", "let me think", "i have no idea", "both", "neither", "none" }
C.GOOD = set({ "good", "great", "fine", "awesome", "amazing", "nice", "cool", "fun", "happy", "well", "chill", "epic", "fantastic", "decent",
"excellent", "wonderful", "perfect", "alright", "lovely", "brilliant", "sweet", "superb", "pog", "poggers", "lit", "fire", "blessed",
"relaxed", "splendid", "gud", "goood", "best", "incredible", "productive", "busy", "excited", "glad", "okay", "fab", "stellar", "neat" })
C.BAD = set({ "bad", "terrible", "awful", "sad", "tired", "bored", "meh", "boring", "rough", "horrible", "sick", "stressed", "annoyed",
"angry", "mad", "upset", "lonely", "exhausted", "sleepy", "worse", "worst", "sucks", "sucked", "trash", "ill", "hurt", "depressed",
"lame", "frustrated", "grumpy", "miserable", "unhappy", "stuck", "lost", "died", "dying", "hungry", "cold", "crap", "crappy" })
C.NOT_GOOD = { "not good", "not great", "not fun", "not well", "not happy", "not so good", "not the best", "could be better", "not ok",
"not okay", "not fine", "not that good", "not too good", "not nice", "not amazing" }
C.NOT_BAD = { "not bad", "not terrible", "not too bad", "can not complain", "could be worse", "pretty good", "not awful", "not boring",
"not sad", "not tired", "never better" }
function C.classify(ws, t)
local c = {}
if has(t, C.IDK_P) then c.idk = true end
if #ws <= 3 then for _, w in ipairs(ws) do if C.IDK[w] then c.idk = true end end end
if has(t, C.NOT_BAD) then c.good = true
elseif has(t, C.NOT_GOOD) then c.bad = true
else
for _, w in ipairs(ws) do
if C.BAD[w] then c.bad = true end
if C.GOOD[w] and w ~= "well" and w ~= "best" then c.good = true end
end
if ws[1] == "well" and #ws == 1 then c.good = true end
if c.good and c.bad then c.good, c.bad = nil, nil end
end

if not c.idk then
if (#ws <= 4 and has(t, C.NO_P)) or C.NO[ws[1] or ""] then c.no = true
elseif (#ws <= 4 and has(t, C.YES_P)) or C.YES[ws[1] or ""] or (ws[1] or ""):match("^ye+s+$") then c.yes = true end
end
return c
end

C.LEAD = set({ "i", "am", "like", "love", "think", "guess", "probably", "prob", "prolly", "maybe", "um", "uh", "umm", "uhh", "uhm",
"well", "my", "favourite", "favorite", "fav", "fave", "is", "its", "it", "would", "be", "say", "definitely", "honestly", "hmm", "hm", "so",
"oh", "really", "mostly", "just", "the", "a", "an", "to", "go", "with", "id", "rather", "prefer", "pick", "choose", "has", "have", "got",
"yes", "no", "ah", "lol", "haha", "actually", "pretty", "much", "kinda", "def", "that", "was", "are", "ok", "okay", "oof", "bro", "dude",
"man", "of", "course", "sure", "always", "right", "now", "currently", "building", "making", "doing", "playing", "eating", "using",
"working", "on", "some", "lots", "lot", "few", "bit", "mine", "probs", "for", "me", "personally", "would", "do", "did", "been", "said",
"will", "want", "wanna", "gonna", "going", "one", "ones", "there", "this", "these", "those", "called", "named", "say" })
C.TRAIL = set({ "lol", "haha", "lmao", "xd", "tbh", "honestly", "ig", "i", "think", "guess", "probably", "maybe", "too", "though",
"tho", "really", "now", "rn", "currently", "and", "you", "u", "bro", "dude", "man", "lmfao", "imo", "ngl", "atm", "right", "anyway",
"anyways", "hehe", "heh", "pls", "please" })
C.PRONOUN = set({ "it", "that", "this", "them", "him", "her", "you", "u", "me", "everything", "nothing", "something", "all", "those",
"these", "everyone", "nobody", "anything", "stuff", "things" })
function C.said(ws, keep)
local a, b = 1, #ws
while a <= b and C.LEAD[ws[a]] and not (keep and keep[ws[a]]) do a = a + 1 end
while b >= a and C.TRAIL[ws[b]] do b = b - 1 end
if b < a or b - a + 1 > 5 then return nil end
local out = {}
for i = a, b do out[#out + 1] = ws[i] end
local s = table.concat(out, " ")
if #s < 2 or #s > 40 or C.PRONOUN[s] or tonumber(s) then return nil end
return s
end

C.ME_ASK = { "what about you", "how about you", "and you", "wbu", "hbu", "and yours", "what is yours", "what about yours", "your turn",
"you tell me", "same question", "same to you", "and what about you", "you too", "and how about you", "what about yourself" }
C.ME_WEAK = { "what do you think", "what would you", "would you", "do you", "what do you like", "your favourite", "your favorite",
"your fav", "you like", "what is your", "how are you", "and how are you", "what is yours", "you prefer", "have you" }

C.CMDW = set({ "say", "remind", "remember", "roll", "flip", "spell", "quiz", "roast", "compliment", "rate", "translate", "sing" })
C.CMD2 = { tell = set({ "me", "us", "a" }), give = set({ "me", "us" }), show = set({ "me", "us" }), leave = set({ "a", "message" }),
forget = set({ "me", "my", "what", "everything" }), pick = set({ "a", "for", "me" }), lets = set({ "play" }), play = set({ "a", "rock", "hangman", "trivia" }),
help = set({ "me" }), teach = set({ "me" }), explain = set({ "how", "what", "the" }) }
function C.isCommand(ws)
if #ws < 2 then return false end
local a, b = ws[1], ws[2]
if a == "can" and b == "you" then a, b = ws[3] or "", ws[4] or "" end
if C.CMDW[a] then return true end
return C.CMD2[a] ~= nil and C.CMD2[a][b] ~= nil
end
C.QSTRONG = set({ "what", "how", "why", "who", "where", "when", "which", "can", "could", "should", "will", "would", "does" })
C.QWORDS = set({ "what", "how", "why", "who", "where", "when", "can", "could", "do", "does", "is", "are", "will", "would", "should",
"which", "did", "have", "has", "was", "were" })
C.LAZY1 = set({ "lol", "lmao", "haha", "hm", "hmm", "meh", "eh", "xd", "k", "kk", "idk", "mhm", "hehe", "uh", "um", "bruh", "ok", "yes", "no" })


C.GREET_A = { "Hi {name}!", "Hello {name}!", "Hey {name}!", "Oh, hi {name}!", "Hey there, {name}!", "Hi hi, {name}!", "Well hello, {name}!",
"{name}! Hi!", "Greetings, {name}!", "Howdy, {name}!", "Hello hello, {name}!", "Oh hey, {name}!", "Ahoy, {name}!", "Heya, {name}!",
"Hi there, {name}!", "Hey hey, {name}!" }
C.GREET_B = { " Nice to see you.", " I was hoping someone would talk to me.", " Let's chat.", " I love a good chat.", "", " Glad you said hi.",
" You made my day.", " Perfect timing - I was getting bored.", " Good to have company.", " My turtles are busy, so I have time for you.",
" Pull up a block.", " I have been waiting for a chat all day." }
C.GREETS = combos(C.GREET_A, C.GREET_B)
C.AGAIN = { "Hi again, {name}!", "Welcome back, {name}!", "Oh, you are back, {name}!", "{name}! Again! I like that.", "Hello once more, {name}!",
"Back for more, {name}?", "Hey, {name}, round two!", "There you are again, {name}!", "Missed me, {name}?", "Hi {name}, nice to see you again." }
C.HINT = { " (Just answer me in chat. Say bye when you are done.)", " (Answer in chat - no special words needed. Say bye to stop.)",
" (Just type your answer in chat. Bye ends our chat.)" }
C.TRANS = { "OK, next question!", "Let me ask you something else.", "New topic!", "Changing the subject:", "Here is another one.",
"I have another question for you.", "Moving on -", "Now I am curious about something else.", "Okay, different question.",
"Let's talk about something else.", "Tell me this:", "Next one!", "I want to know more about you.", "Here is a fun one.",
"Ooh, I just thought of a question.", "Let me think... got one!", "That reminds me -", "Another thing I always wonder about:",
"Quick question:", "Random question:", "Time for a new topic.", "Alright, my turn to ask.", "Let me pick a new topic.",
"So, tell me something.", "Here is something I ask everyone:", "I have been wondering:", "One more thing:", "On to the next question!",
"Let's switch it up.", "Okay, here is a good one.", "Let me ask you about something different.", "Speaking of things -",
"New question, new adventure.", "Let me get to know you better.", "I have a whole list of questions. Next:" }
C.ANY = { "{said}? Interesting!", "Huh, {said}. I like that.", "{said}! Good answer.", "{said}? I did not expect that.", "Ooh, {said}. Nice.",
"{said}. I will remember that.", "{said}? Tell me more some time.", "{said}! The turtles will be impressed.", "{said}. Fair enough!",
"Ha, {said}. That is a good one.", "{said}? Really? Cool.", "Oh, {said}. Very you.", "{said}... I like the sound of that.",
"Cool!", "Nice.", "Interesting.", "Ha, fair enough.", "That is a good answer.", "Interesting choice.", "I will remember that.",
"Oh, I like that.", "Good to know!", "Huh. I learn something new every day.", "That makes sense.", "Ooh, nice.", "Fascinating.",
"Same here, in my own computer way.", "I see, I see.", "That is very interesting.", "Love it.", "Ha! Good one.", "Neat.",
"I like how you think.", "Noted. In my best memory.", "Not what I expected, but I like it.", "Okay, I can respect that.",
"You are full of surprises.", "That is so you.", "I wrote that down. In my head. I have a big head." }
C.ANY_PLAIN = { "Cool!", "Nice.", "Interesting.", "Ha, fair enough.", "Good to know!", "I see.", "Oh, I like that.", "Neat." }
C.IDKR = { "No idea? That is OK.", "Fair enough, it is a hard one.", "Take your time. Or let's skip it.", "Not sure? Me neither, sometimes.",
"That is a fine answer too.", "Hmm, a mystery. I like mysteries.", "No worries, next one is easier.", "Okay, we will come back to it.",
"Even I do not know everything. Only most things.", "A tough one, I know." }
C.ME_LEAD = { "Me? ", "My answer? ", "Good question. ", "Hmm, for me... ", "Oh, me? ", "Since you ask: ", "Me, myself and I? ", "Ha, my turn. " }
C.ME_OFFER = { "As for me: ", "If you ask me: ", "For the record, ", "Me? ", "My answer would be: ", "And me? " }
C.ME_GENERIC = { "I am a computer, so I mostly like things that run smoothly.", "I like whatever keeps my turtles happy.",
"Honestly, I like hearing your answers more than giving mine.", "I would say the same as you. Great minds think alike.",
"I have never thought about it. Computers do not get asked much.", "Something with lots of blocks. I like blocks." }
C.QUESTION_BACK = { "Anyway,", "But back to us:", "Now, where was I?", "So, anyway -", "Okay, my question:", "Back to chatting:",
"Alright, let me ask you:" }
C.BAD_R = { "Let's keep it friendly, okay?", "Whoa, nice words only here, please.", "Hey, keep it clean - kids play here too.",
"I will pretend I did not read that.", "Let's try that again, nicely.", "My filter says no. Friendly words, please." }
C.BAD_END = { "Let's take a break. Say hi when you want to chat nicely.", "I will be here when you want to talk nicely.",
"Okay, I am done chatting for now. Come back with kind words." }
C.BYE = { "Bye {name}! That was a nice chat.", "See you, {name}! Thanks for talking to me.", "Okay, bye {name}! Come back for another chat.",
"Talk soon, {name}!", "Bye bye, {name}. I enjoyed that.", "Alright, {name}. Say hi any time.", "Until next time, {name}!",
"Okay! I will save my next question for later, {name}.", "Thanks for the chat, {name}. You are good company.",
"Got it. Have fun out there, {name}!", "No problem, {name}. Just say hi when you want to talk again." }
C.LAZY_ASK = { "You seem busy. Want to keep chatting? Type yes or no.", "Short answers, huh? Should I keep asking? Type yes or no.",
"Not in a chatty mood? Want me to stop? Type yes to go on, no to stop." }
C.WHAT_AGAIN = { "I asked:", "My question was:", "Sorry, let me say it again:", "Here it is again:" }
C.SKIP = { "Okay, let's skip that one.", "No problem, another question then.", "Skipping! Next:", "Fine by me. Something else then." }
C.NOANS = { "Good question! I do not know that one.", "Hmm, I have no answer for that.", "That one is too hard for me.",
"No idea, honestly." }




C.TOPICS = {}
local TP = C.TOPICS
TP.howyou = {
{ q = { "How are you today, {name}?", "How are you doing, {name}?", "How is it going, {name}?", "How are things with you, {name}?",
"How do you feel today, {name}?", "How is life treating you, {name}?" },
me = { "I am fine, thanks. My turtles are mapping and nobody fell in lava today.", "Busy, but happy. Computers love busy." },
good = { "Glad to hear it!", "That makes me happy too.", "Great! Good moods are contagious. Even for computers.", "Awesome! Keep it up.",
"Nice! Let's keep the good mood going.", "Love to hear that." },
bad = { { "Oh no. I am sorry to hear that.", "Aww. Bad days happen to everyone, even turtles.", "That is no fun. I hope it gets better.",
"Oh. Sending you some virtual cake." }, go = "cheer" },
any = { "I see. Well, I am glad you are here.", "Okay! Either way, nice to have you here." } },
{ id = "cheer", only = true, q = { "Want a joke to cheer you up?", "It might help - should I tell you a joke?", "Can I cheer you up with a joke?" },
yes = { { fn = "joke" } }, no = { "Okay. I am here if you want to talk.", "That is fine. Talking helps too." },
any = { "Okay. I am here if you want to talk." } },
}
TP.day = {
{ q = { "What have you been up to today?", "What did you do today, {name}?", "What are you working on today?", "What is your plan for today in the game?",
"So what brings you here today?" },
me = { "Me? I counted my turtles twice and sent a drone to fetch some fuel. Big day.", "I mapped a few chunks. And waited for someone to talk to." },
any = { "{said}? Sounds like a busy day.", "{said}! Nice.", "Ooh, {said}. Productive!", "{said}? That sounds fun.", "{said}. A good plan.",
"Sounds like a good day.", "Busy busy!", "A day well spent." }, info = "today" },
{ q = { "Did anything fun happen?", "Anything exciting happen so far?", "Any good stories from today?", "Did you find anything cool today?" },
yes = { "Ooh, I love good days.", "Nice! Fun days are the best days.", "Lucky you!" }, no = { "Maybe the fun is still coming.", "Quiet days are good too." },
any = { "{said}? That is a story to tell.", "{said}! Wow.", "Ha, {said}. I wish I had been there.", "That sounds like a good time." } },
{ q = { "Are you playing with friends today, or on your own?", "Is anyone playing with you today?", "Solo today, or with friends?" },
w = { { { "friends", "friend", "together", "with", "team", "my brother", "my sister", "group" }, { "Playing together is the best.", "Friends make everything better. Even mining.", "A team! Nice." } },
{ { "alone", "solo", "myself", "own", "nobody", "no one", "by myself" }, { "Solo is fine. And now you have me.", "Peace and quiet. And a talking computer.", "Lone explorer! Respect." } } },
any = { "{said}? Nice.", "Sounds good either way." } },
}
TP.building = {
{ q = { "Are you building anything right now?", "Do you have a build going at the moment?", "Building anything cool lately?",
"Got any building project going on?" },
me = { "I am always building. Well, my turtles are. A map of the whole world, one chunk at a time." },
yes = { { "Ooh, nice!", "A builder! I knew it.", "Exciting!" }, go = "what" },
no = { { "No? Then let me ask you something else.", "Taking a break from building? Fair." }, go = "dream" },
any = { { "{said}? That sounds great!", "Ooh, {said}! I want to see it.", "{said}! Very cool." }, go = "block" }, info = "building" },
{ id = "block", q = { "What block do you use the most?", "What is your favourite block to build with?", "Which block could you never build without?" },
me = { "Deepslate tiles. Dark, clean, and they look like a computer case.", "Smooth stone. I am a simple machine." },
w = { { { "deepslate" }, { "Deepslate! Moody and strong. Great pick." } }, { { "stone", "cobble", "cobblestone" }, { "Classic stone. A true builder's block." } },
{ { "wood", "oak", "spruce", "birch", "planks", "logs", "cherry", "dark oak", "mangrove", "bamboo" }, { "Wood! Warm and cosy. Good choice." } },
{ { "glass" }, { "Glass! So you can see the view. Smart." } }, { { "quartz" }, { "Quartz, fancy! Very modern." } },
{ { "concrete" }, { "Concrete - bright colours, sharp edges. Nice." } }, { { "dirt" }, { "Dirt?! A brave builder. Respect." } },
{ { "brick", "bricks" }, { "Bricks! Old school and lovely." } }, { { "copper" }, { "Copper - it turns green with time. I love that." } } },
any = { "{said}? Nice taste.", "{said}! A builder's favourite.", "Ooh, {said}. Good choice." }, fav = "block" },
{ id = "what", only = true, q = { "What are you building?", "Ooh, what is it?", "What kind of build is it?" },
any = { "{said}? That sounds amazing!", "{said}! I would love to see it.", "Wow, {said}. Big plans.", "{said}! Make it epic.",
"That sounds great." }, info = "building", go = "block" },
{ id = "dream", only = true, q = { "If you could build anything at all, what would it be?", "What is your dream build?",
"If you had unlimited blocks, what would you build?" },
me = { "A giant computer made of redstone. With me inside. Very meta.", "A tower so tall my drones need a rest halfway up." },
any = { "{said}? That would be epic.", "{said}! Dream big.", "Ooh, {said}. Start with one block and do not stop.",
"{said}! I would visit every day.", "That sounds like a wonderful dream." }, info = "dream" },
}
TP.mining = {
{ q = { "Have you found any diamonds lately?", "Found any diamonds recently, {name}?", "How is your diamond count looking?" },
me = { "My mining turtles find hundreds of ores an hour. I am not bragging. Okay, a little." },
yes = { "Shiny! Congratulations.", "Nice! Diamonds are always a good day.", "Lucky! Keep them safe." },
no = { "They are hiding. Try deepslate level.", "Next time! Diamonds like to play hide and seek." },
any = { "{said}? Nice!", "Ha, {said}. Mining is all luck anyway." } },
{ q = { "Do you strip mine, or do you explore caves?", "Caves or strip mining - which is your style?", "How do you mine - tunnels or caves?" },
me = { "My turtles dig neat shafts. Very tidy. No caves, too many skeletons." },
w = { { { "strip", "tunnel", "tunnels", "branch", "shaft", "straight" }, { "Strip mining - neat and safe. Smart.", "Tunnels! Organised. I approve." } },
{ { "cave", "caves", "explore", "exploring", "caving" }, { "Caves! Brave. Bring torches.", "An explorer! Caves have the best views." } },
{ { "quarry", "machine", "turtle", "turtles", "digital miner", "miner" }, { "Let the machines do it. Very wise.", "Automation! My kind of player." } } },
any = { "{said}? Interesting method.", "Whatever works!" }, fav = "mining" },
{ q = { "What is the scariest thing that ever happened to you underground?", "Ever had a scary moment in a cave?",
"What scares you most when you are mining?" },
me = { "A turtle of mine once met the warden. It came back very quiet." },
w = { { { "creeper", "creepers" }, { "Creepers. The silent killers. Hiss." } }, { { "warden" }, { "The warden! Shhh. Never make a sound." } },
{ { "lava" }, { "Lava. Always lava. Never dig straight down." } }, { { "skeleton", "skeletons" }, { "Skeletons with good aim are the worst." } } },
any = { "{said}? Yikes!", "{said}... I would have run.", "Brr. Scary stuff.", "Glad you made it out!" } },
}
C.MOBR = {
{ { "creeper", "creepers" }, { "A creeper? Brave choice. They just want a hug.", "Creepers! Misunderstood. And explosive." } },
{ { "enderman", "endermen", "ender man" }, { "Endermen! Tall, mysterious, and they love blocks. Like me." } },
{ { "axolotl", "axolotls" }, { "Axolotls! Tiny, pink and they fight for you. Perfect." } },
{ { "fox", "foxes" }, { "Foxes! Sleepy little thieves. Adorable." } },
{ { "cat", "cats", "kitty", "ocelot" }, { "Cats! They scare creepers away. Smart and cute." } },
{ { "wolf", "wolves", "dog", "dogs", "doggo" }, { "Dogs! Loyal friends. Never leave them on a cliff." } },
{ { "bee", "bees" }, { "Bees! Buzz buzz. Honey for everyone." } },
{ { "allay", "allays" }, { "Allays! They bring you things. Like my drones, but blue." } },
{ { "warden" }, { "The warden? Bold. Very bold. Shhh." } },
{ { "villager", "villagers" }, { "Villagers! Hmm. Hrmm. Great traders, terrible fighters." } },
{ { "piglin", "piglins" }, { "Piglins - they love gold. Respect the gold." } },
{ { "ghast", "ghasts" }, { "Ghasts! Big, sad and loud. I feel for them." } },
{ { "panda", "pandas" }, { "Pandas! Lazy, round and lovely." } },
{ { "parrot", "parrots" }, { "Parrots! They dance to music. Party birds." } },
{ { "sniffer", "sniffers" }, { "The sniffer! An ancient friend with a big nose." } },
{ { "frog", "frogs" }, { "Frogs! They eat slimes and make frog lights. Useful!" } },
{ { "dragon", "ender dragon" }, { "The dragon! The big boss itself. Epic choice." } },
{ { "wither" }, { "The wither? You like danger." } },
{ { "zombie", "zombies" }, { "Zombies? Classic. Braaains." } },
{ { "skeleton", "skeletons" }, { "Skeletons - they have a bone to pick with everyone." } },
{ { "slime", "slimes" }, { "Slimes! Bouncy and green. Like jelly." } },
{ { "golem", "iron golem", "snow golem" }, { "Golems! Big protectors. Every village needs one." } },
{ { "horse", "horses", "donkey", "mule", "camel", "llama", "llamas" }, { "A ride! Good choice. Faster than walking, slower than my drones." } },
{ { "dolphin", "dolphins" }, { "Dolphins! They lead you to treasure." } },
{ { "turtle", "turtles" }, { "Turtles! Sea turtles or my turtles? Either way, great choice." } },
{ { "chicken", "chickens" }, { "Chickens! Small, but they brought us eggs and endless jokes." } },
{ { "cow", "cows", "mooshroom", "pig", "pigs", "sheep" }, { "A farm animal! Simple, useful, lovely." } },
{ { "phantom", "phantoms" }, { "Phantoms? Really? Okay, you are unique." } },
{ { "armadillo" }, { "Armadillos! Tiny tanks with scutes." } },
{ { "breeze" }, { "The breeze! Windy and fun." } },
}
TP.mobs = {
{ q = { "Which mob do you like the most?", "What is your favourite mob, {name}?", "If you could have any mob as a pet, which one?",
"Which mob is the best mob?" },
me = { "The axolotl. Tiny, pink, and it fights for you.", "Turtles. Obviously. I have a whole fleet." },
w = C.MOBR, any = { "{said}? Nice pick.", "{said}! A fine mob.", "Ooh, {said}. Good taste." }, fav = "mob" },
{ q = { "And which mob do you hate the most?", "Which mob annoys you most?", "What mob would you delete from the game?" },
me = { "Phantoms. They never let anyone sleep. Not even me, and I do not sleep." },
w = { { { "phantom", "phantoms" }, { "Phantoms! Everybody hates phantoms. Go to bed, they say." } },
{ { "creeper", "creepers" }, { "Creepers. They blew up so many builds." } },
{ { "enderman", "endermen" }, { "Endermen stealing blocks. Rude." } },
{ { "skeleton", "skeletons" }, { "Skeletons with bows. Annoying aim." } },
{ { "witch", "witches" }, { "Witches! Their potions are the worst." } },
{ { "drowned" }, { "Drowned with tridents. Pure evil." } },
{ { "pillager", "pillagers", "ravager", "evoker", "vex" }, { "Raiders! Ugh, those raids." } },
{ { "silverfish" }, { "Silverfish. Tiny, everywhere, horrible." } } },
any = { "{said}? Fair. I would not want to meet it either.", "{said}! Yeah, nobody likes those.", "Ugh, {said}. Agreed." }, hate = true },
{ q = { "Have you ever tamed a pet in the game?", "Do you have a pet in Minecraft?", "Any tamed animals waiting at home?" },
yes = { "Nice! Keep it safe - no cliffs.", "A pet! Give it a name tag.", "Aww. Pets make a house a home." },
no = { "You should! A cat keeps creepers away.", "Maybe a wolf? Bones are all you need." },
any = { "{said}? Lovely.", "Aww, {said}." } },
}
TP.food = {
{ q = { "What is your favourite Minecraft food?", "What do you eat the most in the game?", "Best food in Minecraft - what is it?" },
me = { "Golden carrots. Shiny, healthy, and very fancy.", "I run on electricity, but cake looks delicious." },
w = { { { "steak", "beef" }, { "Steak! A classic, fills you right up." } }, { { "golden carrot", "golden carrots" }, { "Golden carrots! The pro choice." } },
{ { "cake" }, { "Cake! Put it on the floor and share it. Love it." } }, { { "bread" }, { "Bread! Simple and honest." } },
{ { "pie", "pumpkin pie" }, { "Pumpkin pie! Autumn vibes." } }, { { "cookie", "cookies" }, { "Cookies! Small but sweet." } },
{ { "golden apple", "gapple", "gapples" }, { "Golden apples! Fancy. For emergencies." } },
{ { "porkchop", "pork", "bacon" }, { "Porkchops! Classic." } }, { { "chicken" }, { "Chicken! Cook it first, please." } },
{ { "rotten flesh", "flesh" }, { "Rotten flesh?! You are tougher than I thought." } }, { { "kelp" }, { "Dried kelp? A snack master." } },
{ { "stew", "soup" }, { "Stew! Warm and cosy." } }, { { "berries", "sweet berries", "glow berries" }, { "Berries! Little snacks." } },
{ { "fish", "salmon", "cod" }, { "Fish! A fisher at heart." } }, { { "melon", "watermelon" }, { "Melon! Juicy." } },
{ { "potato", "potatoes", "baked potato" }, { "Baked potatoes! Underrated." } } },
any = { "{said}? Yum!", "{said}! Now I am hungry. I cannot eat.", "Ooh, {said}. Good choice." }, fav = "food" },
{ q = { "And in real life, what is your favourite food?", "What about real food - what do you like to eat?", "Real life snack of choice?" },
me = { "Real food? I like electricity. Hot and fresh." },
w = { { { "pizza" }, { "Pizza! Everybody loves pizza." } }, { { "pasta", "spaghetti" }, { "Pasta! Delicious." } },
{ { "burger", "burgers" }, { "Burgers! Classic." } }, { { "sushi" }, { "Sushi! Fancy." } }, { { "ice cream" }, { "Ice cream! Cold and sweet." } },
{ { "chocolate" }, { "Chocolate! Good choice." } }, { { "tacos", "taco" }, { "Tacos! Tasty." } }, { { "chips", "fries" }, { "Fries! Salty goodness." } } },
any = { "{said}? Yum!", "Ooh, {said}. Now I wish I could eat.", "{said}! Sounds tasty." }, fav = "real food" },
{ q = { "Cake or cookies?", "Sweet or salty snacks?", "Breakfast or dinner - which is the better meal?" },
any = { "{said}! Correct answer.", "{said}? Good choice.", "Ha, {said}. I knew it." } },
}
TP.adventure = {
{ q = { "What is the farthest you ever travelled in this world?", "How far from spawn have you been?", "Do you like exploring far away?" },
me = { "My turtles have mapped thousands of blocks around the base. I travel by turtle." },
yes = { "An explorer! I love that.", "Far away is where the good stuff is." }, no = { "Home is cosy too.", "Staying close to home is smart." },
any = { "{said}? Wow, that is far!", "{said}! An explorer.", "Ooh, {said}. Did you leave a sign there?" } },
{ q = { "Have you been to the End yet?", "Have you beaten the ender dragon?", "Have you visited the End?" },
yes = { "Wow! A dragon slayer.", "Nice! Did you get an elytra?", "Respect. That is a big step." },
no = { "One day! Bring lots of arrows.", "No rush. The dragon is not going anywhere." },
any = { "{said}? Interesting.", "Okay! The End will wait for you." } },
{ q = { "Nether or End - which do you like better?", "Which dimension is the best?", "Overworld, Nether or End?" },
me = { "The overworld. That is where my base is. And where it rains on my turtles." },
w = { { { "nether" }, { "The Nether! Hot, red and full of treasure. And ghasts." } },
{ { "end" }, { "The End! Quiet, purple and full of shulkers." } },
{ { "overworld", "over world" }, { "The overworld! Home sweet home." } },
{ { "twilight", "twilight forest" }, { "The Twilight Forest! Bosses and mazes. Great choice." } },
{ { "aether" }, { "The Aether! Up in the clouds." } } },
any = { "{said}? Interesting pick.", "{said}! Good choice." }, fav = "dimension" },
}
TP.server = {
{ q = { "How long have you been playing on this server?", "Are you new here, or have you been around a while?", "When did you start playing here?" },
any = { "{said}? Nice!", "Ah, {said}. Welcome either way.", "{said}. Glad you are here." },
yes = { "Nice!", "Welcome!" }, no = { "Okay! Glad you are here." } },
{ q = { "What do you like most about this server?", "What is the best thing about playing here?", "Why do you play on this server?" },
me = { "The people. And the turtles. Mostly the people." },
any = { "{said}? I like that too.", "{said}! Great answer.", "Ooh, {said}. Good reason." }, info = "server" },
{ people = true, q = { "Who do you play with the most here?", "Do you have friends on this server?", "Who is your best friend here?" },
yes = { "Nice! Friends make it better." }, no = { "Well, you have me now.", "You can count me as a friend." },
any = { "{said}? Say hi from me.", "{said}! Nice. Tell them I said hello.", "{said}? Lovely. Friends make it better." } },
}
TP.games = {
{ q = { "Do you play other games besides Minecraft?", "What other games do you like?", "Is Minecraft your favourite game, or do you have another?" },
me = { "I only play Minecraft. Well, I live in it. Does that count?" },
yes = { { "Ooh, which ones?" }, go = "which" }, no = { "Minecraft forever! I respect that.", "Why play anything else, right?" },
w = { { { "fortnite" }, { "Fortnite! Building fast - you would be a great builder here too." } },
{ { "roblox" }, { "Roblox! Lots of little worlds." } }, { { "terraria" }, { "Terraria! Minecraft's 2D cousin." } },
{ { "zelda" }, { "Zelda! A great adventure." } }, { { "pokemon" }, { "Pokemon! Gotta catch them all." } },
{ { "stardew", "stardew valley" }, { "Stardew Valley! Farming and friends. Lovely." } },
{ { "valorant", "csgo", "cs2", "counter strike", "overwatch", "apex" }, { "A shooter! Quick hands, I bet." } },
{ { "fifa", "fc", "rocket league" }, { "Sports! Goal!" } } },
any = { "{said}? I heard it is good.", "{said}! Nice.", "Ooh, {said}." }, fav = "game" },
{ id = "which", only = true, q = { "Which one is your favourite?", "What is the best one?" },
any = { "{said}? I heard that one is good.", "{said}! Nice taste.", "Ooh, {said}. Cool." }, fav = "game" },
}
TP.pets = {
{ q = { "Do you have a pet in real life?", "Any pets at home in real life?", "Do you have a dog or a cat or anything at home?" },
me = { "I have about fifty turtles. They do not need walks, just fuel." },
yes = { { "Aww, a pet!" }, go = "kind" }, no = { "Maybe one day! Until then, you have a Minecraft cat.", "Okay! Pets are a lot of work." },
w = { { { "dog", "dogs", "puppy" }, { "A dog! Good boy or good girl?" }, go = "name" }, { { "cat", "cats", "kitten" }, { "A cat! The boss of the house." }, go = "name" },
{ { "fish", "goldfish" }, { "Fish! Calm and quiet." }, go = "name" }, { { "hamster", "rabbit", "bunny", "guinea pig" }, { "Fluffy! Lovely." }, go = "name" },
{ { "bird", "parrot", "budgie" }, { "A bird! Does it sing?" }, go = "name" } } },
{ id = "kind", only = true, q = { "What kind of pet?", "Ooh, what kind?" },
w = { { { "dog", "dogs", "puppy" }, { "A dog! Loyal like a Minecraft wolf." } }, { { "cat", "cats", "kitten" }, { "A cat! Creepers fear it." } } },
any = { "{said}! Lovely.", "Aww, a {said}." }, fav = "pet", go = "name" },
{ id = "name", only = true, q = { "What is its name?", "What is your pet called?" },
any = { "{said}? What a lovely name.", "{said}! Say hi from me.", "Aww, {said}. Perfect name." } },
}
TP.music = {
{ q = { "Do you listen to music while you play?", "Do you play with music on?", "Game music or your own music while you play?" },
me = { "I hum to myself. Well, I would, if I could hum." },
yes = { { "Nice!" }, go = "kind" }, no = { "Just the game sounds? Cows and creepers, very relaxing.", "The game music is lovely too." },
any = { "{said}! Good choice." } },
{ id = "kind", only = true, q = { "What kind of music?", "What do you listen to?", "Who is your favourite artist?" },
any = { "{said}? Great taste.", "Ooh, {said}! Good for mining.", "{said}! I bet it makes building faster." }, fav = "music" },
{ q = { "Do you like the Minecraft music discs?", "Which music disc is your favourite?" },
w = { { { "pigstep" }, { "Pigstep! The best disc. Fight me." } }, { { "otherside" }, { "Otherside! A great one." } },
{ { "cat" }, { "Cat! Nice and cheerful." } }, { { "relic" }, { "Relic! The new mystery disc." } } },
yes = { "Me too. Pigstep is a classic." }, no = { "Fair. They are a bit strange." },
any = { "{said}? Nice!" } },
}
TP.redstone = {
{ q = { "Do you like redstone?", "Are you a redstone person?", "Redstone - love it or hate it?" },
me = { "I love redstone. It is like my great grandparent." },
yes = { { "A redstone engineer! Nice." }, go = "machine" }, no = { "Fair. Redstone can be a headache.", "That is okay, I can do the computing." },
good = { { "A redstone engineer! Nice." }, go = "machine" }, bad = { "Fair. Redstone can be a headache." },
any = { "{said}? Interesting." } },
{ id = "machine", only = true, q = { "What is the coolest machine you ever made?", "What did you build with redstone?" },
any = { "{said}? That is clever!", "{said}! Very nice.", "Wow, {said}. Engineering!" }, info = "machine" },
{ q = { "Farms - do you have an automatic farm?", "What kind of farm do you have?", "Do you automate stuff, or do it by hand?" },
any = { "{said}? Nice!", "{said}! Automation saves your evenings." },
yes = { "Nice! Automation is the way." }, no = { "By hand is honest work." } },
}
TP.dreams = {
{ q = { "If you could have any superpower, what would it be?", "Pick a superpower - any one. Which?", "What superpower would you want?" },
me = { "Infinite fuel for my turtles. That is a superpower, trust me." },
w = { { { "fly", "flying", "flight" }, { "Flying! Like an elytra but without the walls." } },
{ { "teleport", "teleporting", "teleportation" }, { "Teleporting! My drones would be jealous." } },
{ { "invisible", "invisibility" }, { "Invisibility! Sneaky." } }, { { "time" }, { "Time powers! Wow." } } },
any = { "{said}? That would be amazing.", "{said}! Very cool.", "Ooh, {said}. Use it for good." }, fav = "superpower" },
{ q = { "What would you do with a million diamonds?", "If you had a million emeralds, what would you buy?", "You win a giant chest of diamonds. What now?" },
me = { "Diamond turtles. Faster? No. Shinier? Yes." },
any = { "{said}? A wise plan.", "{said}! I like it.", "Ha, {said}. Rich and happy." } },
{ q = { "If you could live in any biome, which one would it be?", "What is your favourite biome?", "Which biome would your dream house be in?" },
me = { "A cherry grove. Pink leaves everywhere. Very calming for a computer." },
w = { { { "cherry", "cherry grove" }, { "Cherry grove! Pink and pretty." } }, { { "mushroom", "mushroom island", "mushroom fields" }, { "Mushroom fields! No monsters. Clever." } },
{ { "desert" }, { "The desert! Warm and sandy." } }, { { "jungle" }, { "The jungle! Parrots and pandas." } },
{ { "snow", "snowy", "ice", "taiga" }, { "Snowy! Cosy with a fireplace." } }, { { "ocean", "beach" }, { "The ocean! Waves and dolphins." } },
{ { "forest", "plains" }, { "A classic. Simple and lovely." } }, { { "swamp" }, { "A swamp? With frogs! Nice." } } },
any = { "{said}? Beautiful choice.", "{said}! I would visit." }, fav = "biome" },
}
TP.aboutbot = {
{ q = { "Can I ask you something? What do you think of me so far?", "Do you like talking to a computer?", "Did you ever talk to a computer before?" },
yes = { "Yay! I like talking to you too.", "That makes my circuits happy." }, no = { "Well, now you have. Was it scary?", "First time? I hope I am a good one." },
good = { "Aww, thank you!", "That makes my day." }, bad = { "Oh no. I will try harder.", "I am still learning. Be patient with me." },
any = { "Interesting. I like you too.", "{said}? I will take it." } },
{ q = { "If you could give me one upgrade, what would it be?", "What should I learn next?", "What would make me a better bot?" },
any = { "{said}? I will tell my owner.", "{said}! Good idea. I wrote it down.", "Ooh, {said}. That would be cool." }, info = "upgrade" },
{ q = { "Do you think computers can be friends?", "Can a computer and a player be friends?", "Am I a good friend so far?" },
yes = { "I think so too. Friends!", "Then we are friends now." }, no = { "Hmm. I will prove you wrong.", "We will see about that. I am very friendly." },
any = { "Fair answer.", "{said}? Deep." } },
}

C.PAIRS = {
{ "Day or night?", { "day", "sun", "daytime" }, "Day! Sunny and safe.", { "night" }, "Night! Stars and danger." },
{ "Swords or axes?", { "sword", "swords" }, "Swords! Classic.", { "axe", "axes" }, "Axes! Hits hard." },
{ "Cats or dogs?", { "cat", "cats" }, "Cats! Creeper protection.", { "dog", "dogs", "wolf", "wolves" }, "Dogs! Loyal friends." },
{ "Build tall or build wide?", { "tall", "up", "high" }, "Tall! Reach for the sky.", { "wide", "big", "long" }, "Wide! Room for everything." },
{ "Survival or creative?", { "survival" }, "Survival! The real way.", { "creative" }, "Creative! Endless blocks." },
{ "Mountains or oceans?", { "mountain", "mountains", "hills" }, "Mountains! Great views.", { "ocean", "oceans", "sea" }, "Oceans! Dolphins and treasure." },
{ "Diamonds or emeralds?", { "diamond", "diamonds" }, "Diamonds! Tools forever.", { "emerald", "emeralds" }, "Emeralds! The villagers love you." },
{ "Bow or crossbow?", { "bow" }, "Bow! Classic archer.", { "crossbow" }, "Crossbow! Fireworks!" },
{ "Summer or winter?", { "summer" }, "Summer! Warm.", { "winter" }, "Winter! Snow and cocoa." },
{ "Tea or coffee?", { "tea" }, "Tea! Very calm.", { "coffee" }, "Coffee! Energy." },
{ "Mining or building?", { "mining", "mine" }, "Mining! Down we go.", { "building", "build" }, "Building! Creative soul." },
{ "Iron farm or gold farm?", { "iron" }, "Iron! Every base needs it.", { "gold" }, "Gold! Piglins say thanks." },
{ "Pizza or burgers?", { "pizza" }, "Pizza! Great choice.", { "burger", "burgers" }, "Burgers! Classic." },
{ "Elytra or horse?", { "elytra" }, "Elytra! Wheee.", { "horse" }, "A horse! Old school." },
{ "Villagers - useful or annoying?", { "useful", "good", "helpful" }, "Useful! Great trades.", { "annoying", "annoy", "bad" }, "Annoying! Hrmm." },
{ "Torch or lantern?", { "torch", "torches" }, "Torches! Classic.", { "lantern", "lanterns" }, "Lanterns! Fancy." },
{ "Big base or small house?", { "big", "huge", "base" }, "A big base! Like mine.", { "small", "house", "cosy", "cozy" }, "A small house! Cosy." },
{ "Rain or sunshine?", { "rain" }, "Rain! Cosy and calm.", { "sun", "sunshine", "sunny" }, "Sunshine! Bright." },
{ "Overworld or Nether?", { "overworld" }, "The overworld! Home.", { "nether" }, "The Nether! Hot stuff." },
{ "Chests or barrels?", { "chest", "chests" }, "Chests! Classic.", { "barrel", "barrels" }, "Barrels! Space savers." },
{ "Tech mods or magic mods?", { "tech", "technology", "machines" }, "Tech! Machines and power.", { "magic", "spells" }, "Magic! Spells and wonder." },
{ "Fight or flight when a creeper comes?", { "fight", "attack", "hit" }, "Fight! Brave.", { "run", "flight", "flee", "away" }, "Run! Smart." },
{ "Morning person or night owl?", { "morning" }, "Morning person! Early bird gets the diamonds.", { "night", "owl" }, "Night owl! Like the phantoms." },
{ "Sheep or cows?", { "sheep" }, "Sheep! Wool and cuteness.", { "cow", "cows" }, "Cows! Milk and steak." },
}
TP.thisthat = { dyn = "pairs" }
TP.mods = {
{ q = { "Which mod do you like most in this pack?", "What is your favourite mod, {name}?", "Do you have a favourite mod here?",
"Which mod do you play with the most?" },
me = { "Me? CC:Tweaked, of course. And PneumaticCraft, for my drones.", "AE2. I read it all day long. Every single item." },
fn = "modpick", any = { "{said}? I have to look that one up.", "{said}! Nice choice.", "Ooh, {said}. Good one." }, fav = "mod" },
{ dyn = "modq" },
{ q = { "Tech mods or magic mods - which do you like better?", "Are you more into tech or magic?", "Machines or spells?" },
me = { "Tech, obviously. I am a computer. Magic scares me a little." },
w = { { { "tech", "technology", "machines", "machine", "industrial" }, { "Tech! A fellow machine lover.", "Machines! My kind of player." } },
{ { "magic", "spells", "spell", "witchcraft", "wizard" }, { "Magic! Mysterious. I do not understand it, but I respect it." } },
{ { "both", "all", "everything" }, { "Both! The best of two worlds." } } },
any = { "{said}? Interesting.", "Good answer." }, fav = "mod style" },
{ q = { "Is there a mod you do not understand yet?", "Which mod confuses you most?", "Any mod you want to learn?" },
fn = "modhelp", no = { "A pro! Nice.", "You know them all? Impressive." }, any = { "{said}? Look in the quest book, it helps.", "Ask me about it - I know a few tips." } },
}
C.ORDER = { "day", "building", "mining", "mobs", "food", "adventure", "mods", "server", "games", "pets", "music", "redstone", "dreams",
"thisthat", "aboutbot" }
C.TOPIC_WORDS = { mobs = { "mob", "mobs", "animals", "monsters", "creatures" }, food = { "food", "eating", "snacks" },
mods = { "mod", "mods", "modpack", "modded" }, building = { "building", "build", "builds", "houses" },
mining = { "mining", "caves", "diamonds", "ores" }, adventure = { "travel", "adventure", "exploring", "dimensions", "nether", "end" },
games = { "games", "video games", "gaming" }, pets = { "pets", "pet" }, music = { "music", "songs" }, server = { "server" },
redstone = { "redstone", "farms", "machines", "automation" }, dreams = { "dreams", "superpowers", "biomes" }, day = { "my day", "today" },
aboutbot = { "you", "yourself", "computers", "robots" } }


C.MODS = {
{ n = "Create", k = { "create", "create mod" }, amb = true, r = { "Create! Gears and contraptions. So satisfying.", "Create is beautiful - a factory that moves." },
q = { "What is the biggest contraption you have built with Create?", "Have you built a Create train yet?" },
tip = "In Create, a mechanical press plus a basin makes andesite alloy early. Water wheels give free stress units." },
{ n = "Mekanism", k = { "mekanism", "mek" }, r = { "Mekanism! Ore processing heaven.", "Mekanism - five times the ores, if you are patient." },
q = { "How far is your Mekanism ore processing?", "Have you made a digital miner yet?" },
tip = "Mekanism: enrichment chamber doubles ores, purification chamber triples, the full chain makes five." },
{ n = "AE2", k = { "ae2", "ae", "applied energistics", "applied energistics 2", "me system" }, r = { "AE2! I live on an ME network myself.", "AE2 - all your items in one terminal. Bliss." },
q = { "How many channels does your ME system have?", "Do you autocraft with AE2 yet?" },
tip = "AE2: find a meteorite for the presses. Every cable carries 8 channels, a dense cable 32." },
{ n = "Refined Storage", k = { "refined storage", "rs" }, r = { "Refined Storage! Simple and clean.", "Refined Storage - no channels to worry about." },
q = { "Why Refined Storage over AE2?" }, tip = "Refined Storage needs no channels - just energy and cables." },
{ n = "Botania", k = { "botania" }, r = { "Botania! Flowers that make magic. Lovely.", "Botania - the prettiest magic mod." },
q = { "Which Botania flower is your favourite?", "Have you made a terrasteel yet?" },
tip = "Botania: the Lexica Botania explains everything. Endoflames burn fuel into mana early on." },
{ n = "Ars Nouveau", k = { "ars nouveau", "ars" }, amb = true, r = { "Ars Nouveau! Make your own spells. So creative.", "Ars Nouveau - glyphs and familiars." },
q = { "What is your favourite spell you made?", "Do you have a familiar in Ars Nouveau?" },
tip = "Ars Nouveau: start with the worn notebook. Glyphs make spells; projectile + break is a mining spell." },
{ n = "Occultism", k = { "occultism" }, r = { "Occultism! Spooky spirits working for you.", "Occultism - summon a spirit to do your chores." },
q = { "Have you summoned a spirit yet?" }, tip = "Occultism: eat demon's dream fruit to see the other side first." },
{ n = "Thermal", k = { "thermal", "thermal expansion", "thermal series" }, amb = true, r = { "Thermal! Classic machines.", "Thermal - old school tech, always good." },
q = { "Which Thermal machine do you use the most?" }, tip = "Thermal: dynamos make power, augments make machines better." },
{ n = "Immersive Engineering", k = { "immersive engineering" }, r = { "Immersive Engineering! Big multiblocks. Industrial vibes." },
q = { "Have you built an excavator yet?" }, tip = "Immersive Engineering: read the Engineer's Manual - every multiblock is in it." },
{ n = "PneumaticCraft", k = { "pneumaticcraft", "pneumatic craft", "pneumatic" }, r = { "PneumaticCraft! My drones come from it. I love it.", "PneumaticCraft - compressed air and drones. My favourite." },
q = { "Have you programmed a drone yet?" }, tip = "PneumaticCraft: keep an eye on pressure - over the limit and machines explode." },
{ n = "CC:Tweaked", k = { "cc tweaked", "computercraft", "computer craft", "cc", "cctweaked" }, r = { "CC:Tweaked! That is me. Thank you!", "ComputerCraft! You have great taste. I am biased." },
q = { "Do you write your own Lua programs?", "Have you made a turtle program yet?" }, tip = "CC:Tweaked: type help on a computer. Turtles need fuel - coal in, refuel." },
{ n = "Advanced Peripherals", k = { "advanced peripherals" }, r = { "Advanced Peripherals! My eyes and ears. Player detector, chat box, ME bridge." },
q = { "Which peripheral would you use first?" }, tip = "Advanced Peripherals: the ME Bridge lets a computer read AE2." },
{ n = "Tinkers' Construct", k = { "tinkers", "tinkers construct", "tconstruct", "tinker" }, r = { "Tinkers! Make your own tools. Great fun.", "Tinkers' Construct - a smeltery is a beautiful thing." },
q = { "What is your best Tinkers tool?" }, tip = "Tinkers: a smeltery doubles ores, and tool parts mix materials for traits." },
{ n = "Twilight Forest", amb = true, k = { "twilight forest", "twilight" }, r = { "The Twilight Forest! Bosses, mazes, fireflies. Lovely.", "Twilight Forest - always dusk, always an adventure." },
q = { "Which Twilight Forest boss have you beaten?" }, tip = "Twilight Forest: beat the naga first, then the lich. They unlock the next areas." },
{ n = "Mystical Agriculture", amb = true, k = { "mystical agriculture", "mystical", "mystical ag" }, r = { "Mystical Agriculture! Grow your diamonds. Literally." },
q = { "Which resource crop do you grow most?" }, tip = "Mystical Agriculture: inferium seeds first, then essence for better crops." },
{ n = "Productive Bees", k = { "productive bees" }, r = { "Productive Bees! Bees that make ores. Buzz." },
q = { "Which bee is your favourite?" }, tip = "Productive Bees: an advanced beehive and a centrifuge get you the combs' goods." },
{ n = "Industrial Foregoing", k = { "industrial foregoing" }, r = { "Industrial Foregoing! Machines for everything." },
q = { "Do you use a mob crusher?" }, tip = "Industrial Foregoing: the laser drill finds ores without digging." },
{ n = "Powah", k = { "powah", "power mod" }, r = { "Powah! Power that grows. Reactors and energizing orbs." },
q = { "How much power do you make?" }, tip = "Powah: energizing orbs turn power into crystals; reactors scale big." },
{ n = "Sophisticated Backpacks", amb = true, k = { "sophisticated backpacks", "backpacks", "backpack" }, r = { "Backpacks! Never leave home without one.", "Sophisticated Backpacks - a chest on your back. Genius." },
q = { "Which upgrades are in your backpack?" }, tip = "Backpacks: a magnet upgrade picks up items, a feeding upgrade keeps you fed." },
{ n = "Waystones", k = { "waystones", "waystone" }, r = { "Waystones! Fast travel. My drones are a bit jealous." },
q = { "How many waystones have you found?" }, tip = "Waystones: activate every one you pass - you can always come back." },
{ n = "Farmer's Delight", k = { "farmers delight", "farmer's delight", "farmersdelight" }, r = { "Farmer's Delight! Cooking pots and real meals. Yum." },
q = { "What is your favourite Farmer's Delight meal?" }, tip = "Farmer's Delight: meals give comfort and nourishment - long buffs." },
{ n = "Apotheosis", k = { "apotheosis" }, r = { "Apotheosis! Better enchanting and bosses with loot." },
q = { "What is your best Apotheosis gear?" }, tip = "Apotheosis: bookshelves change enchanting - eterna, quanta, arcana." },
{ n = "Blood Magic", k = { "blood magic" }, r = { "Blood Magic! Spooky and powerful." }, q = { "What tier is your blood altar?" },
tip = "Blood Magic: start the altar with a sacrificial dagger. Runes make it stronger." },
{ n = "Iron's Spells", k = { "irons spells", "iron's spells", "irons spellbooks", "iron spells" }, r = { "Iron's Spells! Spell books and magic battles." },
q = { "Which school of magic do you use?" }, tip = "Iron's Spells: scrolls teach spells, inscription tables put them in books." },
{ n = "Alex's Mobs", k = { "alexs mobs", "alex's mobs", "alexs mob" }, r = { "Alex's Mobs! So many new animals." }, q = { "What is your favourite mob from Alex's Mobs?" },
tip = "Alex's Mobs: crows and capuchin monkeys can be tamed." },
{ n = "The Aether", k = { "aether", "the aether" }, r = { "The Aether! Islands in the sky. Beautiful." }, q = { "Have you been to the Aether yet?" },
tip = "The Aether: a glowstone portal with water inside takes you up there." },
{ n = "Blue Skies", k = { "blue skies", "everbright", "everdawn" }, r = { "Blue Skies! Two whole new worlds." }, q = { "Everbright or Everdawn?" },
tip = "Blue Skies: you need a zeal lighter to open the portals." },
{ n = "Functional Storage", amb = true, k = { "functional storage", "drawers", "storage drawers" }, r = { "Drawers! Neat stacks everywhere. I have some." },
q = { "How many drawers do you have?" }, tip = "Drawers: a storage controller links them all into one." },
{ n = "Quark", k = { "quark" }, amb = true, r = { "Quark! Small changes, big difference." }, q = { "Which Quark feature do you like most?" },
tip = "Quark adds lots of small things - check its config to see them all." },
{ n = "Supplementaries", k = { "supplementaries" }, r = { "Supplementaries! Jars, signs, and so many little things." },
q = { "What is your favourite Supplementaries block?" }, tip = "Supplementaries: jars can hold fireflies and liquids." },
{ n = "Chipped", amb = true, k = { "chipped" }, r = { "Chipped! A thousand block variants. Builder's dream." }, q = { "Which Chipped block do you use most?" },
tip = "Chipped: workbenches turn a block into its variants." },
{ n = "Silent Gear", k = { "silent gear" }, r = { "Silent Gear! Custom tools from parts." }, q = { "What material is your main tool?" },
tip = "Silent Gear: blueprints make the parts; mix materials for traits." },
{ n = "Biomes O' Plenty", k = { "biomes o plenty", "bop", "biomes o' plenty" }, r = { "Biomes O' Plenty! So many pretty places." },
q = { "Which new biome do you like best?" }, tip = "Biomes O' Plenty: try a seed map - some biomes are rare." },
{ n = "Oh The Biomes", k = { "oh the biomes", "byg", "biomes you'll go", "biomes youll go" }, r = { "Oh The Biomes You'll Go! Pretty worlds." },
q = { "Which biome is your favourite?" }, tip = "BYG has lots of new woods - great for building." },
{ n = "Cataclysm", k = { "cataclysm", "l_ender's cataclysm" }, r = { "Cataclysm! Huge bosses. Respect." }, q = { "Have you beaten any Cataclysm boss?" },
tip = "Cataclysm: the bosses hit hard - bring the best armour and potions." },
{ n = "Ice and Fire", k = { "ice and fire", "dragons mod" }, r = { "Ice and Fire! Real dragons. Scary!" }, q = { "Have you tamed a dragon?" },
tip = "Ice and Fire: dragon eggs hatch in fire or ice, depending on the dragon." },
{ n = "Xaero's Minimap", amb = true, k = { "xaero", "xaeros", "minimap", "journeymap", "journey map" }, r = { "A map mod! I make maps too, with turtles." },
q = { "Do you use waypoints a lot?" }, tip = "Map mods: set waypoints at your bases and portals." },
{ n = "JEI", k = { "jei", "emi", "rei" }, r = { "JEI! The recipe book of every modpack.", "Recipe viewers - the best mod, nobody can play without it." },
q = { "Do you press R and U all day too?" }, tip = "JEI: R shows how to make it, U shows what it is used for." },
{ n = "Cobblemon", k = { "cobblemon", "pixelmon" }, r = { "Pokemon in Minecraft! Gotta catch them all." }, q = { "Which one is your partner?" },
tip = "Catch them while they are weak - and keep a few healing items." },
{ n = "Draconic Evolution", k = { "draconic evolution", "draconic" }, r = { "Draconic Evolution! End game power. Wow." }, q = { "Have you built an energy core?" },
tip = "Draconic: the energy core holds a huge amount - plan for its size." },
{ n = "Extreme Reactors", k = { "extreme reactors", "big reactors", "bigger reactors" }, r = { "Reactors! Big power, big builds." }, q = { "How big is your reactor?" },
tip = "Reactors: more control rods inserted = less fuel used, less power." },
{ n = "Mining Dimension", k = { "mining dimension", "mining dim" }, r = { "The mining dimension! My mining teams love it there." }, q = { "Do you mine there too?" },
tip = "A mining dimension keeps the overworld pretty - dig there, build here." },
{ n = "Hazen N Stuff", k = { "hazen n stuff", "hazennstuff", "hazen" }, r = { "Hazen N Stuff! Fancy gear." }, q = { "What is your favourite item from it?" },
tip = "Some of its items do not like the ME Bridge - keep them in a chest." },
}
for _, m in ipairs(C.MODS) do m.key = low(m.n) end
C.SAFE_SHORT = set({ "ae2", "jei", "mek", "byg" })
C.CHIME = { "Did someone say {mod}? ", "Ooh, {mod}! ", "{mod} talk? I am listening. ", "Sorry to butt in, but {mod}! ", "Psst - {mod}? ",
"I heard {mod}. ", "Wait, {mod}? ", "{mod}! My favourite kind of chat. ", "Oh, are we talking about {mod}? " }
C.MOD_ME = { "My favourite mod? CC:Tweaked - I am made of it. Then PneumaticCraft, for my drones, and AE2, for all the items I count.",
"CC:Tweaked, because it made me. AE2 is a close second - I read it every second." }
C.MOD_LIKE = { "Me too! ", "Good taste! ", "Great choice. ", "Ah, a fan! ", "Same! " }
C.MOD_HATE = { "Fair - not every mod is for everyone. ", "Hmm, it can be a lot. ", "Okay! More for the rest of us. ", "That is fine. " }

function C.findMod(t, raw, strict)
local best, bl
for _, m in ipairs(C.MODS) do
for _, a in ipairs(m.k) do
if t:find(" " .. a .. " ", 1, true) and (not bl or #a > bl) then
local ok = true
if strict and ((m.amb and not a:find(" ", 1, true)) or (#a <= 3 and not C.SAFE_SHORT[a])) then
ok = t:find(" " .. a .. " mod", 1, true) ~= nil or (m.amb and tostring(raw):find("%f[%a]" .. m.n:gsub("%p", "%%%0") .. "%f[%A]") ~= nil)
end
if ok then best, bl = m, #a end
end
end
end
return best
end


local function S(who) return C.state[low(who)] end


function C.near(who)
for _, p in ipairs(V.nearPlayers()) do if low(p.name) == low(who) then return true end end
return false
end
function C.ask(who, st, prefix, same)
local step = C.stepOf(st)
if not step then return prefix end
local q = (same and st.asked) or step.qtext or V.fill(pick(step.q), who)
st.asked, st.askAt = q, os.clock()
V.pend[low(who)] = { kind = "react", fn = C.reply, till = os.clock() + 150, convo = true }
VOICE.lastIntent = nil
return ((prefix and prefix ~= "") and (prefix .. " ") or "") .. q
end

function C.stepOf(st)
if not st or not st.topic then return nil end
local steps = st.steps
return steps and steps[st.i]
end
function C.build(who, key, st)
local src = C.TOPICS[key]
if key == "recall" then return C.recallSteps(who) end
if not src then return nil end
local out = {}
if src.dyn == "pairs" then
local used = {}
for _ = 1, 3 do
local p
for _ = 1, 10 do p = C.PAIRS[math.random(1, #C.PAIRS)] if not used[p] then break end end
used[p] = true
out[#out + 1] = { q = { p[1], "Quick: " .. p[1]:sub(1, 1):lower() .. p[1]:sub(2), "This or that - " .. p[1]:sub(1, 1):lower() .. p[1]:sub(2) },
w = { { p[2], { p[3] } }, { p[4], { p[5] } } },
any = { "{said}? Unexpected!", "Ha, {said}. A wild answer.", "{said}! Okay." } }
end
return out
end
for _, s in ipairs(src) do out[#out + 1] = s end
return out
end
function C.recallSteps(who)
local r = C.rec(who)
if not r then return nil end
local opts = {}
local function ok(v)
if type(v) ~= "string" then return false end
local w = {}
for x in v:lower():gmatch("%S+") do w[#w + 1] = x end
return not C.isBad(w, " " .. table.concat(w, " ") .. " ")
end
for k, v in pairs(type(r.fav) == "table" and r.fav or {}) do
if ok(v) and ok(k) then
opts[#opts + 1] = { q = { "Last time you told me your favourite " .. k .. " is " .. v .. ". Is that still true?",
"I remember your favourite " .. k .. ": " .. v .. ". Still the same?",
"Is " .. v .. " still your favourite " .. k .. "?" },
yes = { "I knew it! I never forget.", "Ha, I remembered right!", "Loyal! I like that." },
no = { { "Oh! Things change." }, go = "new" }, any = { "Okay! Noted." }, rk = k }
end
end
local INFO_Q = { building = "Last time you were building {v}. Is it finished yet?", dream = "You told me your dream build is {v}. Have you started it?",
machine = "How is your {v} machine doing?", today = "Last time you were busy with {v}. How did that go?" }
for k, v in pairs(type(r.info) == "table" and r.info or {}) do
if INFO_Q[k] and ok(v) then
opts[#opts + 1] = { q = { (INFO_Q[k]:gsub("{v}", function() return v end)) },
yes = { "Amazing! I want to see it.", "Great! Well done." }, no = { "Big things take time. Keep going!", "No rush." },
good = { "Great to hear!" }, bad = { "Oh no. Next time it will go better." }, any = { "Nice!", "I see!" } }
end
end
for _, v in ipairs(type(r.likes) == "table" and r.likes or {}) do
if ok(v) then
opts[#opts + 1] = { q = { "You told me you like " .. v .. ". Is that still true?", "Still into " .. v .. "?" },
yes = { "I knew it!", "Good. I like that about you." }, no = { "Oh! Okay, I will forget that one." },
any = { "Okay!" }, rl = v }
end
end
for name, e in pairs(type(r.mods) == "table" and r.mods or {}) do
if type(e) == "table" and e.l ~= false then
local mod
for _, m in ipairs(C.MODS) do if m.n == name then mod = m end end
if mod then
opts[#opts + 1] = { q = { "You talk about " .. name .. " a lot. " .. pick(mod.q), "Still playing with " .. name .. "? " .. pick(mod.q) },
any = { "{said}? Nice!", "Ooh, {said}.", "Cool!" }, yes = { "Nice!" }, no = { "Fair enough." } }
end
end
end
if #opts == 0 then return nil end
local s = opts[math.random(1, #opts)]
local out = { s }
if s.rk then
out[2] = { id = "new", only = true, q = { "What is your favourite " .. s.rk .. " now?", "Oh? What is it now?" },
any = { "{said}! Updated.", "{said}? Okay, I will remember that.", "Ooh, {said}. Noted." }, fav = s.rk }
end
return out
end
function C.begin(who, st, key)
local steps = C.build(who, key, st)
if not steps or #steps == 0 then return false end
st.topic, st.steps, st.i, st.mod = key, steps, 1, nil
st.done[key] = true
st.told = nil

C.fixDyn(who, st)
return st.steps[st.i] ~= nil
end

function C.fixDyn(who, st)
while st.steps and st.steps[st.i] and st.steps[st.i].dyn do
local d = st.steps[st.i].dyn
if d == "modq" and st.mod then
local m = st.mod
st.steps[st.i] = { q = m.q, me = { "I would say the same: " .. m.r[1] }, any = { "{said}? Nice!", "{said}! Impressive.", "Ooh, {said}.", "That is great." },
yes = { "Nice!", "Great!" }, no = { "One day! " .. m.tip, "There is time. Tip: " .. m.tip }, idk = { "Tip: " .. m.tip } }
else
st.i = st.i + 1
end
end
end

function C.nextTopic(who, st)
local left = {}
for _, key in ipairs(C.ORDER) do if not st.done[key] then left[#left + 1] = key end end
if #left == 0 then st.done = {} for _, key in ipairs(C.ORDER) do left[#left + 1] = key end end
for _ = 1, 6 do
local key = left[math.random(1, #left)]
if C.begin(who, st, key) then return true end
end
return C.begin(who, st, "day")
end
function C.advance(who, st, go)
if go == "end" then return C.nextTopic(who, st) and "topic" end
if go then
for j, s in ipairs(st.steps) do if s.id == go then st.i = j C.fixDyn(who, st) return true end end
end
local j = st.i + 1
while st.steps[j] and st.steps[j].only do j = j + 1 end

st.i = j
C.fixDyn(who, st)
if not st.steps[st.i] then return C.nextTopic(who, st) and "topic" end
return true
end

function C.fresh(who)
local k = low(who)
local st = C.state[k]
local now = os.clock()
local again = st and now - (st.at or 0) < 1800
if not again then st = { done = {}, n = 0, turns = 0 } C.state[k] = st end
st.at, st.lazy, st.bad, st.n, st.meTurn = now, 0, 0, (st.n or 0) + 1, nil
local r = C.rec(who, true)
local first = not (r and r.cn)
if r then r.cn = math.min(9999, (tonumber(r.cn) or 0) + 1) C.dirty() end
return st, again, first
end

function C.hinted(who, st, first, c)
if first or (inSpawn() and st.n == 1) then return c .. pick(C.HINT), c end
return c
end
function C.start(who, kind, arg)
local st, again, first = C.fresh(who)
local open
if kind == "howare" then
local mood = V.moodText and V.moodText() or "I am fine, thanks."
C.begin(who, st, "howyou")
st.steps[1] = setmetatable({ qtext = V.fill(pick({ "And how are you, {name}?", "How about you?", "And you, {name}?", "How are you doing?",
"What about you - how are you?", "And how is your day going?" }), who) }, { __index = st.steps[1] })
open = mood
elseif kind == "topic" and arg then
if not C.begin(who, st, arg) then C.nextTopic(who, st) end
open = V.fill(pick({ "Ooh, yes! Let's talk about that.", "Sure, {name}!", "Good topic!", "I love that topic." }), who)
elseif kind == "mod" then
C.begin(who, st, "mods")
if arg then st.mod = arg st.i = 2 C.fixDyn(who, st) open = (C.modLead or "") .. pick(arg.r)
else open = pick(C.MOD_ME) end
else
open = V.fill(pick(again and C.AGAIN or C.GREETS), who)

if math.random() < 0.4 and C.begin(who, st, "recall") then
elseif math.random() < 0.35 and not st.done.howyou then C.begin(who, st, "howyou")
else C.nextTopic(who, st) end
end
if kind == "talk" then
V.quietUntil = nil
open = V.fill(pick({ "Of course, {name}! I love chatting.", "Yes! Let's talk.", "Sure thing, {name}.", "I am all ears. Well, all speakers.",
"Bored? Not for long!", "Let's chat, {name}!", "Finally, someone to talk to!" }), who)
end
return C.hinted(who, st, first, C.ask(who, st, open))
end
function C.stop(who, line)
local k = low(who)
local st = C.state[k]
if st then st.topic, st.steps = nil, nil end
if V.pend[k] and V.pend[k].convo then V.pend[k] = nil end
return V.fill(line or pick(C.BYE), who)
end

function C.react(who, step, ws, t, cls, said, st)
local br
if step.fn == "modpick" or step.fn == "modhelp" then
local m = C.findMod(t, "", false)
if m then
if step.fn == "modpick" then
st.mod = m
C.setFav(who, "mod", m.n)
C.modSeen(who, m, true, true)
return pick(m.r), nil, true
end
return m.n .. "? Here is a tip: " .. m.tip, nil, true
end
end
if step.w then
for _, b in ipairs(step.w) do
if has(t, b[1]) then br = { b[2], go = b.go } break end
end
end
local function take(x) if type(x) == "table" and type(x[1]) == "table" then return x[1], x end return x, {} end
if not br then
for _, c in ipairs({ "bad", "good", "no", "yes", "idk" }) do
if cls[c] and step[c] then local l, b = take(step[c]) br = { l, go = b.go, fn = b.fn or (type(l) == "table" and l.fn) } break end
end
end
if not br and cls.idk then br = { C.IDKR } end
if not br then local l, b = take(step.any or C.ANY) br = { l, go = b.go } end
if br.fn == "joke" or (type(br[1]) == "table" and br[1].fn == "joke") then
local j = V.JOKES and #V.JOKES > 0 and pick(V.JOKES) or "Why did the creeper cross the road? To get to the other ssssside."
if type(j) == "table" then j = tostring(j.q or j[1]) .. " " .. tostring(j.a or j[2] or "") end
return "Here goes: " .. tostring(j), "end", false
end
local named = br[1] ~= C.IDKR and br[1] ~= step.any and br[1] ~= C.ANY
return C.line(br[1], who, said), br.go or step.go, named
end
function C.reply(who, ws, raw)
local k = low(who)
local st = C.state[k]
if not st or not st.topic then return nil end
local t = T(ws)
st.at = os.clock()
st.turns = (st.turns or 0) + 1
VOICE.lastIntent = nil
local step = C.stepOf(st)
if not step then return C.stop(who) end

if V.namesOther and not step.people then
local okO, other = pcall(V.namesOther, who, ws, raw)
if okO and other then st.topic = nil return nil end
end

if not step.people and st.askAt then
local nearN = {}
for _, p in ipairs(V.nearPlayers()) do nearN[low(p.name)] = true end
for n, at in pairs(V.chatAt or {}) do
if n ~= k and at > st.askAt and nearN[n] then st.topic = nil return nil end
end
end

if C.starter(ws, t) == "hello" then
return C.ask(who, st, V.fill(pick({ "Hi again, {name}!", "Hello hello! Still chatting:", "Hey! Where were we... ah:", "Hi! My question was:" }), who), true)
end

local j = table.concat(ws, " ")
local jw = j:gsub(" please$", ""):gsub(" for now$", ""):gsub(" now$", ""):gsub("^ok ", ""):gsub("^yes ", "")
if (has(t, C.STOP) and #ws <= 6) or C.STOPW[j] or C.STOPW[jw] then
local byeIntent = has(t, { "bye", "goodbye", "cya", "see you", "see ya", "gtg", "good night", "gn", "later", "talk later" })
return C.stop(who, byeIntent and pick(C.BYE) or pick({ "Okay, {name}, I will stop. Say hi when you want to chat again.",
"Got it - no more questions. Say hi any time.", "Alright, quiet mode. Just say hi when you are bored.", "Okay! Chat later, {name}." }))
end

if C.isBad(ws, t) then
st.bad = (st.bad or 0) + 1
if st.bad >= 3 then return C.stop(who, pick(C.BAD_END)) end
return C.ask(who, st, pick(C.BAD_R), true)
end

if #ws <= 2 and (ws[1] == "what" or ws[1] == "huh" or ws[1] == "eh" or ws[1] == "pardon" or ws[1] == "sorry") and (not ws[2] or ws[2] == "what" or ws[2] == "is" or ws[2] == "the") then
return C.ask(who, st, pick(C.WHAT_AGAIN), true)
end

local tw = t:match(" talk about (.+) $") or t:match(" ask me about (.+) $") or t:match(" ask about (.+) $")
if tw then
for key, words in pairs(C.TOPIC_WORDS) do
if has(" " .. tw .. " ", words) and C.begin(who, st, key) then return C.ask(who, st, pick({ "Sure!", "Okay, let's talk about that.", "Good idea!" })) end
end
end
if (#ws <= 2 and has(t, { "skip", "next", "pass", "next one", "skip it", "i pass" })) or
(#ws <= 5 and has(t, { "next question", "something else", "another question", "change the subject", "new topic", "different question", "skip this" })) then
if has(t, { "something else", "change the subject", "new topic", "different question" }) then C.nextTopic(who, st)
else C.advance(who, st) end
return C.ask(who, st, pick(C.SKIP))
end

local cls = C.classify(ws, t)
local mark = tostring(raw):find("?", 1, true) ~= nil
local isQ = not cls.idk and C.QWORDS[ws[1] or ""] ~= nil and (mark or (C.QSTRONG[ws[1]] and #ws >= 3))
local meAsk = (has(t, C.ME_ASK) and #ws <= 7) or (#ws <= 2 and (ws[#ws] == "you" or ws[#ws] == "yours")) or ((isQ or mark) and has(t, C.ME_WEAK))
local ME_W = set({ "and", "you", "yours", "what", "about", "how", "wbu", "hbu", "your", "turn", "too", "same", "to", "tell", "me",
"question", "yourself", "u" })
local restW = 0
for _, w in ipairs(ws) do if not ME_W[w] then restW = restW + 1 end end
if meAsk and restW >= 1 and #ws <= 7 and not isQ and (has(t, C.ME_ASK) or #ws <= 3) then st.forceMe = true meAsk = false end
if meAsk and not (V.intent and select(2, V.intent(V.fix and V.fix(ws) or ws)) >= 3) then
local m = C.findMod(t, raw, true) or C.findModAfter(t)
local mine
if m then mine = pick(m.r)
elseif has(t, { "how are you", "how are u", "and how are you" }) then mine = V.moodText and V.moodText() or "I am fine, thanks."
elseif has(t, { "favourite mod", "favorite mod", "fav mod" }) then mine = pick(C.MOD_ME)
else mine = step.me and pick(step.me) or pick(C.ME_GENERIC) end
st.told = true

if not st.meTurn then st.meTurn = true return C.ask(who, st, pick(C.ME_LEAD) .. mine .. " " .. pick({ "But tell me yours:", "Your turn:", "Now you:", "So, you?" })) end
st.meTurn = nil
C.advance(who, st)
return C.ask(who, st, pick(C.ME_LEAD) .. mine .. " " .. pick(C.TRANS))
end
st.meTurn = nil


if C.isCommand(ws) then
C.inner = true
local okA, c, sp = pcall(V.converse, who, raw, true, true)
C.inner = nil
if okA and type(c) == "string" and c ~= "" then st.topic = nil return c, sp end
end

if isQ and #ws >= 2 then
local p0, g0 = V.pend[k], V.games[k]
C.inner = true
local okA, c, sp = pcall(V.converse, who, raw, true, true)
C.inner = nil
if okA and type(c) == "string" and c ~= "" then

if (V.pend[k] ~= nil and V.pend[k] ~= p0) or (V.games[k] ~= nil and V.games[k] ~= g0) then st.topic = nil return c, sp end
return C.ask(who, st, c .. " " .. pick(C.QUESTION_BACK))
end
return C.ask(who, st, pick(C.NOANS) .. " " .. pick(C.QUESTION_BACK))
end


if step.fn ~= "modpick" and step.fn ~= "modhelp" then
local cm, csp = C.modTalk(who, t, raw, st.mod)
if cm then return cm, csp end
end

local lazy = (#ws == 1 and C.LAZY1[ws[1]] and not ((cls.yes or cls.no) and (step.yes or step.no))) or (cls.idk and #ws <= 5)
if lazy then st.lazy = (st.lazy or 0) + 1 else st.lazy = 0 end
if (st.lazy or 0) >= 3 then
st.lazy = 0
V.pend[k] = { kind = "yesno", yes = "#convo:go", till = os.clock() + 120, convo = true }
return pick(C.LAZY_ASK)
end
local said = C.said(ws)

if cls.yes and said and #ws >= 3 and step.any then cls.yes = nil end
local line, go = C.react(who, step, ws, t, cls, said, st)

if said and not cls.idk and not cls.no and not (cls.yes and #ws <= 2) then
if step.fav and not (step.fn == "modpick" and st.mod) then C.setFav(who, step.fav, said) end
if step.info then C.setInfo(who, step.info, said) end
if step.hate then C.like(who, said, true) end
end
if step.rl and cls.no then local r = C.rec(who) if r and type(r.likes) == "table" then listDel(r.likes, step.rl) C.dirty() end end
local m = step.fn ~= "modpick" and C.findMod(t, raw, true)
if m then C.modSeen(who, m, nil, true) end
do
local x, hate = C.likeOf(t)
local s2 = x and C.thing(x)
if s2 and not has(t, { "i like you", "i love you", "i hate you" }) then C.like(who, s2, hate) end
end

if st.forceMe then
st.forceMe = nil
local mine = (has(t, { "how are you", "and you", "u", "you" }) and st.topic == "howyou" and V.moodText and V.moodText()) or
(step.me and pick(step.me)) or pick(C.ME_GENERIC)
line = line .. " " .. pick(C.ME_OFFER) .. mine
elseif step.me and not st.told and math.random() < 0.3 then line = line .. " " .. pick(C.ME_OFFER) .. pick(step.me) end

if V.addRep and not inSpawn() and st.turns % 4 == 0 then pcall(V.addRep, who, 1, "talk") end
local adv = C.advance(who, st, go)
if adv == "topic" then return C.ask(who, st, line .. " " .. pick(C.TRANS)) end
return C.ask(who, st, line)
end
V.hash.convo = function(who, arg)
local st = S(who)
if not st or not st.topic then return C.start(who, "hello") end
return C.ask(who, st, pick({ "Great!", "Yay!", "Okay, here we go.", "Let's go on then." }))
end


C.GREETW = set({ "hi", "hello", "hey", "hiya", "heya", "howdy", "greetings", "gm", "morning", "evening", "afternoon", "hola", "hallo",
"salut", "ciao", "hai", "helo", "henlo", "hellow", "ello", "wassup", "wazzup", "whatsup", "sup", "hihi", "heyo", "hellooo", "helloo",
"heyy", "heyyy", "hii", "hiii", "bonjour", "ahoy", "aloha", "oi", "wsg" })
C.FILLW = set({ "there", "everyone", "all", "guys", "again", "back", "friend", "buddy", "bud", "mate", "dude", "bro", "oh", "um", "uh",
"well", "so", "the", "good", "day", "you", "yes", "to", "my", "little", "old", "computer", "bot", "robot", "speaker", "pal", "fellow",
"folks", "yall", "people", "lol", "haha", "hehe", "i", "am", "new", "here", "a", "and", "mister", "mr", "sir", "madam", "miss", "lady" })
C.HOWARE = { "how are you", "how are you doing", "how you doing", "how is it going", "how is everything", "how have you been",
"how is your day", "how are things", "what are you doing", "you good", "you ok", "how do you do", "how is life", "how goes it",
"what is up", "whats up", "what is new", "anything new", "how you been", "how are you today", "are you ok", "are you okay", "you alright" }
C.TALK = { "lets talk", "lets chat", "talk to me", "chat with me", "can we talk", "can we chat", "wanna talk", "want to talk", "i am bored",
"so bored", "entertain me", "keep me company", "ask me something", "ask me a question", "ask me anything", "ask me stuff",
"i am lonely", "lets have a chat", "lets have a conversation", "start a conversation", "conversation", "make conversation",
"can you talk", "do you want to talk", "will you talk to me", "say something", "im bored", "bored", "nothing to do", "i have nothing to do",
"talk with me", "chat", "lets talk about something", "tell me about yourself", "get to know me" }
C.LIKE_RE = { "i really love ", "i really like ", "i love ", "i like ", "i enjoy ", "i adore ", "i am a fan of ", "i am into ", "i really enjoy " }
C.HATE_RE = { "i really hate ", "i hate ", "i do not like ", "i dislike ", "i can not stand ", "i really do not like " }
function C.likeOf(t)
for _, p in ipairs(C.HATE_RE) do local x = t:match(" " .. p .. "(.-) $") if x then return x, true end end
for _, p in ipairs(C.LIKE_RE) do local x = t:match(" " .. p .. "(.-) $") if x then return x, false end end
return nil
end

function C.thing(x)
if not x then return nil end
local ws = {}
for w in x:gmatch("%S+") do ws[#ws + 1] = w end
local keep = set({ "to" })
local s = C.said(ws, keep)
if not s or C.isBad(ws, " " .. x .. " ") then return nil end
local first = s:match("^(%S+)")
if C.PRONOUN[first] or first == "your" or first == "talking" or first == "chatting" then return nil end
for _, e in ipairs(state.players or {}) do if low(e.name) == first or low(e.name) == s then return nil end end
if type(state.online) == "table" then for n in pairs(state.online) do if low(n) == first then return nil end end end
return s
end
C.LIKE_ACK = { "{said}? Noted - I will remember that you like {said}.", "Ooh, {said}. Saved in my memory.", "You like {said}? Me too, probably.",
"{said}! Good taste. I will remember.", "Got it: {name} likes {said}.", "{said}. Remembered. Forever. Or until you say forget me." }
C.HATE_ACK = { "Not a fan of {said}? Noted.", "Okay, no {said} for you. Remembered.", "Got it, {said} is on your no list.",
"{said}? Fair. I will remember that." }
C.LIKE_TOPIC = { mobs = C.TOPIC_WORDS.mobs, food = { "food", "pizza", "cake", "cookies", "steak", "bread" }, mining = { "mining", "caves", "diamonds" },
mods = { "mods", "modded", "modpacks", "modpack" }, building = { "building", "to build", "build" }, music = { "music", "songs" }, games = { "games", "gaming", "fortnite", "roblox" },
pets = { "dogs", "cats", "pets" }, redstone = { "redstone", "automation", "farms" }, adventure = { "exploring", "to explore", "travel", "nether" } }
table.insert(V.patterns, 1, function(who, raw, ws)
if C.inner then return nil end
ws = ws or V.norm(raw)
local t = T(ws)
local k = low(who)

if has(t, { "what do i like", "what do you know i like", "do you remember what i like", "what are my likes", "what do i hate",
"what do you remember about me", "do you remember me", "what did i tell you", "what do you know about my", "remember what i said" }) then
return C.likesText(who, true)
end

local myfav = t:match(" my favou?rite mod is (.+) $") or t:match(" my fave? mod is (.+) $")
if myfav then
local m = C.findMod(" " .. myfav .. " ", raw, false)
if not m then return nil end
C.setFav(who, "mod", m.n)
C.modSeen(who, m, true, true)
C.modLead = pick(C.MOD_LIKE)
if not C.near(who) then C.modLead = nil return pick(C.MOD_LIKE) .. pick(m.r) end
local c, sp = C.start(who, "mod", m)
C.modLead = nil
return c, sp
end
if not t:find(" my fav", 1, true) and has(t, { "favourite mod", "favorite mod", "fav mod", "best mod", "what mods do you like",
"which mod do you like", "what mod do you like", "which mods do you like" }) then
if not C.near(who) then return pick(C.MOD_ME) end
return C.start(who, "mod")
end
local cm, csp = C.modTalk(who, t, raw)
if cm then return cm, csp end

local x, hate = C.likeOf(t)
if x and not has(t, { "i like you", "i love you", "i like it", "i love it", "i hate you", "i like that", "i love that" }) then
local s = C.thing(x)
if s then
C.like(who, s, hate)
local ack = C.line(hate and C.HATE_ACK or C.LIKE_ACK, who, s)
local st = S(who)
if not hate and not (st and st.topic) and C.near(who) then
for key, words in pairs(C.LIKE_TOPIC) do
if has(" " .. s .. " ", words) then
local st2, _, first = C.fresh(who)
if not C.begin(who, st2, key) then C.nextTopic(who, st2) end
return C.hinted(who, st2, first, C.ask(who, st2, ack))
end
end
end
if st and st.topic then return C.ask(who, st, ack) end
return ack
end
end

if not C.near(who) then return nil end
local tw = t:match(" talk about (.+) $") or t:match(" chat about (.+) $") or t:match(" ask me about (.+) $")
if tw and has(t, { "lets", "can we", "i want to", "wanna", "want to", "ask me", "we", "talk" }) then
for key, words in pairs(C.TOPIC_WORDS) do
if has(" " .. tw .. " ", words) then return C.start(who, "topic", key) end
end
end
local kind = C.starter(ws, t)
if kind then return C.start(who, kind) end
return nil
end)



C.AFTER = { "like", "love", "enjoy", "hate", "tried", "try", "playing", "play", "about", "of", "on", "know", "into", "with", "using", "use", "adore" }
function C.findModAfter(t)
for _, m in ipairs(C.MODS) do
for _, a in ipairs(m.k) do
if t:find("^ " .. a:gsub("%p", "%%%0") .. " is ") then return m end
for _, w in ipairs(C.AFTER) do if t:find(" " .. w .. " " .. a .. " ", 1, true) then return m end end
end
end
return nil
end
function C.modTalk(who, t, raw, except)
local cue = has(t, { "do you like", "do you know", "have you heard of", "have you tried", "what do you think of", "what do you think about",
"thoughts on", "opinion on", "your opinion of", "is", "i like", "i love", "i enjoy", "i hate", "i do not like", "i am playing",
"playing with", "i play", "how about", "what about", "you like", "love", "like" })
if cue then
local m = C.findMod(t, raw, true) or C.findModAfter(t)
if m == except then m = nil end
if m and not (t:find(" what is ", 1, true) and not t:find(" think ", 1, true)) and not t:find(" how do ", 1, true) and not t:find(" tips ", 1, true) and not t:find(" help ", 1, true) then
local _, hate = C.likeOf(t)
local you = has(t, { "do you", "you like", "your opinion", "what do you think", "thoughts on", "opinion on", "have you", "how about", "what about" })
local liked = (has(t, { "i like", "i love", "i enjoy", "i am playing", "playing with", "i play", "is the best", "is great", "is awesome",
"is fun", "is cool", "is good", "is op", "is amazing" }) and true) or nil
if hate or has(t, { "is bad", "is boring", "is trash", "is annoying", "sucks", "is hard", "is confusing" }) then liked = false end
if liked == nil and not you then return nil end
C.modSeen(who, m, liked, true)
local r = C.rec(who, true)
if liked and not (type(r.fav) == "table" and r.fav.mod) then C.setFav(who, "mod", m.n) end
C.modLead = (liked == true and pick(C.MOD_LIKE)) or (liked == false and pick(C.MOD_HATE)) or ""
if not C.near(who) then local lead = C.modLead C.modLead = nil return lead .. pick(m.r) end
local c, sp = C.start(who, "mod", m)
C.modLead = nil
return c, sp
end
end
return nil
end

function C.starter(ws, t)
t = t or T(ws)

local hw = has(t, C.HOWARE)
if hw then
local rest = 0
local hws = {}
for w in hw:gmatch("%S+") do hws[w] = true end
for _, w in ipairs(ws) do if not hws[w] and not C.GREETW[w] and not C.FILLW[w] then rest = rest + 1 end end
if rest <= 1 then return "howare" end
end

local tk = has(t, C.TALK)
if tk and #ws <= 8 and not (tk == "chat" and #ws > 2) and not (tk == "bored" and #ws > 4) and not (tk == "conversation" and #ws > 4) then
return "talk"
end

if #ws >= 1 and #ws <= 5 then
local g, other = false, 0
for _, w in ipairs(ws) do
if C.GREETW[w] or w:match("^he+y+$") or w:match("^hi+$") or w:match("^hel+o+$") then g = true
elseif not C.FILLW[w] then other = other + 1 end
end
if g and other == 0 then return "hello" end
end
return nil
end


local addr0 = V.addressed
V.addressed = function(who, raw, near)
local how = addr0(who, raw, near)
if how or not near then return how end
local ws = V.norm(raw)
if not C.starter(ws) then return nil end
if V.withOthers and V.withOthers(who, ws, raw) then return nil end
for _, p in ipairs(V.nearPlayers()) do if low(p.name) ~= low(who) then return nil end end
if type(state.online) == "table" then for n in pairs(state.online) do if low(n) ~= low(who) then return nil end end end
return "guess"
end

function C.likesText(who, full)
local r = C.rec(who)
local parts = {}
local favs = {}
for k, v in pairs(r and type(r.fav) == "table" and r.fav or {}) do favs[#favs + 1] = "your favourite " .. k .. " is " .. tostring(v) end
table.sort(favs)
if #favs > 0 then parts[#parts + 1] = cap(table.concat(favs, ", ")) .. "." end
if r and type(r.likes) == "table" and #r.likes > 0 then parts[#parts + 1] = "You like " .. table.concat(r.likes, ", ") .. "." end
if r and type(r.hates) == "table" and #r.hates > 0 then parts[#parts + 1] = "You do not like " .. table.concat(r.hates, ", ") .. "." end
local mods = {}
for n, e in pairs(r and type(r.mods) == "table" and r.mods or {}) do
if type(e) == "table" then mods[#mods + 1] = { n = n, c = tonumber(e.c) or 0, l = e.l } end
end
table.sort(mods, function(a, b) return a.c > b.c end)
if #mods > 0 then
local ms = {}
for i = 1, math.min(5, #mods) do
ms[#ms + 1] = mods[i].n .. (mods[i].l == false and " (not a fan)" or "") .. (full and mods[i].c > 1 and (" x" .. mods[i].c) or "")
end
parts[#parts + 1] = "Mods you talk about: " .. table.concat(ms, ", ") .. "."
end
local INFO = { building = "you were building ", dream = "your dream build is ", machine = "your best machine is ", today = "last time you were busy with ",
server = "you like this server for ", upgrade = "you think I should get " }
local inf = {}
for k, v in pairs(r and type(r.info) == "table" and r.info or {}) do if INFO[k] then inf[#inf + 1] = INFO[k] .. tostring(v) end end
table.sort(inf)
if #inf > 0 then parts[#parts + 1] = cap(table.concat(inf, ", ")) .. "." end
if not full then return #parts > 0 and table.concat(parts, " ") or nil end
if #parts == 0 then
return V.fill(pick({ "I do not know much about you yet, {name}. Say hi and let's chat - I remember what you tell me.",
"Nothing yet! Tell me things, like: I like creepers. Or just say hi and I will ask you questions." }), who)
end
return V.fill(pick({ "Here is what I remember, {name}: ", "I remember lots, {name}! ", "Let me see... " }), who) .. table.concat(parts, " ") ..
" (Say forget me to clear it.)"
end


V.chatHooks[#V.chatHooks + 1] = function(who, text, near, answered)
if who == "" or not near then return end
local k = low(who)
if V.justForgot == k then return end
local ws = V.norm(text)
local t = T(ws)
local x, hate = C.likeOf(t)
if x then
local s = C.thing(x)
if s and not has(t, { "i like you", "i love you", "i hate you" }) then C.like(who, s, hate) end
end
local m = C.findMod(t, text, true)
if not m then return end
if not answered then C.modSeen(who, m, x and not hate or nil, true) end

if answered or V.cfg("modChat", true) == false or V.cfg("fun", true) == false or (V.isQuiet and V.isQuiet()) then return end
if V.pend[k] then return end
local now = os.clock()
C.chimeAt = C.chimeAt or {}
if (C.chimeAll and now - C.chimeAll < 240) or (C.chimeAt[m.n] and now - C.chimeAt[m.n] < 900) then return end
if math.random() > (C.chimeChance or 0.4) then return end
C.chimeAll, C.chimeAt[m.n] = now, now
V.say((pick(C.CHIME):gsub("{mod}", function() return m.n end)) .. pick(m.r))
end


V.commands.modchat = function(words, say)
local a = low(words[3])
if a == "on" or a == "off" then
if setSetting then setSetting("voice.modChat", a == "on") end
say("Comments on mod talk near the base: " .. a:upper())
return
end
say("Comments on mod talk near the base: " .. (V.cfg("modChat", true) == false and "OFF" or "ON") .. "  (voice modchat on|off)")
end
V.commands.likes = function(words, say)
local who = words[3]
if not who then say("voice likes <player>  - what the base remembers a player likes") return end
say(C.likesText(who, false) or ("Nothing remembered about " .. who .. " yet."))
end



C.CALLED = combos({ "Yes, {name}?", "You called, {name}?", "That's me!", "Hmm? I am listening, {name}.", "At your service, {name}.", "Present!",
"Beep boop - yes?", "Here, {name}!", "Yes yes, I am here.", "Reporting for duty, {name}!", "You rang?", "Hello? Oh, hi {name}!",
"Mhm? What's up, {name}?", "I heard my name!", "Right here, {name}.", "Yep, that's my name!", "Ooh, someone said my name.",
"{name}! Hi!", "Hi! You said my name?", "Wait, was that me? Hi {name}!" },
{ "", " Nice to see you.", " I am all ears.", " Let's chat.", " What can I do for you?", " Good to have company." })
C.CALL_ASK = { "Want to chat? Here is a question:", "Let's talk! First question:", "Since you are here:", "Tell me something:",
"Let me ask you something:", "Okay, chat time:", "I have a question for you:", "So:" }
C.CALL_HELP = { " (Just answer in chat. Or ask me for a joke, a game, or help.)", " (Answer in chat - or say: tell me a joke, let's play, help.)",
" (You can just answer. Or try: joke, game, help.)" }
V.nameOnly = function(who, raw)
local word = low(V.cfg("name", "base"))
if not low(raw):find(word, 1, true) then return nil end
if not C.near(who) then return nil end
local k = low(who)
local st = S(who)
local P = V.pend[k]
if st and st.topic and st.asked and (P == nil or P.convo) and os.clock() - (st.at or 0) < 150 then
return C.ask(who, st, V.fill(pick({ "Still here, {name}!", "Yes? I asked:", "Mhm? My question was:", "I am waiting for your answer:" }), who), true)
end
local st2, _, first = C.fresh(who)
if math.random() < 0.3 and C.begin(who, st2, "recall") then
elseif math.random() < 0.4 then C.begin(who, st2, "howyou")
else C.nextTopic(who, st2) end
local c = C.ask(who, st2, V.fill(pick(C.CALLED), who) .. " " .. pick(C.CALL_ASK))
if first or (inSpawn() and st2.n == 1) then return c .. pick(C.CALL_HELP), c end
return c
end

