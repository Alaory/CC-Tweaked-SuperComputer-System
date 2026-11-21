



























local V = VOICE
if not V then return end
V.packs = V.packs or {}
V.packs["voice_spawn.lua"] = { version = 1 }
local SP = { queue = {}, cands = {}, lastN = 0, busyUntil = 0, sent = 0 }
if V.SPAWN then
for _, k in ipairs({ "seenAt", "relay", "cands", "lastN", "pending", "spokeAt" }) do SP[k] = V.SPAWN[k] end
SP.cands = SP.cands or {}
end
V.SPAWN = SP
SP.PROTO = "basespawn"
local pick, fill = V.pick, V.fill


local cfg0 = V.cfg
function V.cfg(k, d)
if k == "name" and (V.ctx == "spawn" or SP.naming) then
local n = cfg0("spawnName", nil)
if type(n) == "string" and n:match("^%a[%w]*$") then return n end
end
return cfg0(k, d)
end
function SP.named(fn, ...)
local was = SP.naming
SP.naming = true
local r = table.pack(pcall(fn, ...))
SP.naming = was
if not r[1] then error(r[2], 0) end
return table.unpack(r, 2, r.n)
end
local function cfg(k, d) return V.cfg(k, d) end
local function rt() return V.rt() end
local function low(s) return tostring(s or ""):lower() end


function SP.dataHash(d)
local h1, h2 = 7, 13
for i = 1, #d, 16 do
local b = { d:byte(i, i + 15) }
for j = 1, #b do
h1 = (h1 * 31 + b[j]) % 4294967296
h2 = (h2 + b[j] * (i + j)) % 4294967296
end
end
return string.format("%x%x%d", h1, h2, #d)
end
local function sign(key, t, n, cmd, args) return TT.sign(key, t, n, cmd, args) end


function SP.at()
local a = cfg("spawnAt", nil)
if type(a) == "table" and tonumber(a.x) and tonumber(a.z) then return a end
return nil
end
function SP.paired() return tonumber(cfg("spawnId", nil)) ~= nil and type(cfg("spawnKey", nil)) == "string" end
function SP.online() return SP.paired() and SP.seenAt ~= nil and rt() - SP.seenAt < 75 end

function SP.ready() return cfg("spawn", true) ~= false and SP.online() and SP.at() ~= nil end
local function inDim(e)
local want = cfg("spawnDim", "minecraft:overworld")
return e.dim == nil or e.dim == want
end

function SP.players()
local a = SP.at()
local out = {}
if not a then return out end
local r = tonumber(cfg("spawnRange", 24)) or 24
local on = state.online
for _, e in ipairs(state.players or {}) do
local p = e.p
if p and tonumber(p.x) and tonumber(p.z) and inDim(e) and (not on or on[low(e.name)]) then
local d = math.max(math.abs(p.x - a.x), math.abs(p.z - a.z))
if d <= r and math.abs((tonumber(p.y) or tonumber(a.y) or 64) - (tonumber(a.y) or 64)) <= 24 then
out[#out + 1] = { name = e.name, e = e, dist = d, hp = tonumber(p.health), max = tonumber(p.maxHealth) }
end
end
end
return out
end
function SP.isAt(who)
for _, p in ipairs(SP.players()) do if low(p.name) == low(who) then return true end end
return false
end


local nearPlayers0, say0, event0 = V.nearPlayers, V.say, V.event
function V.nearPlayers()
if V.ctx == "spawn" then return SP.players() end
return nearPlayers0()
end
function V.say(text, sound, answer, style)
if V.ctx == "spawn" then return SP.say(text, answer) end
return say0(text, sound, answer, style)
end
function V.event(who, kind, what)
if V.ctx == "spawn" then return end
return event0(who, kind, what)
end
local function guard(name, allow)
local f = V[name]
if type(f) ~= "function" then return end
V[name] = function(...)
if V.ctx == "spawn" and not (allow and allow(...)) then return false, "no rewards at spawn" end
return f(...)
end
end
guard("addRep")
guard("badge")
guard("giftEarn", function(who, why) return why == "wish" end)
if V.GIFT_WHY then V.GIFT_WHY.wish = "- you wished for it" end
function SP.inCtx(fn, ...)
local was, wasPts = V.ctx, V.noPoints
V.ctx, V.noPoints = "spawn", true
local r = table.pack(pcall(fn, ...))
V.ctx, V.noPoints = was, wasPts
if not r[1] then error(r[2], 0) end
return table.unpack(r, 2, r.n)
end


SP.MAX_OWN = 3
function SP.style()
local p = V.preset and V.preset(cfg("spawnVoice", "bright"))
if not p then return nil end
return { accent = p.accent, pitch = p.pitch, speed = p.speed }
end
SP.said = {}
function SP.say(text, answer)
if not SP.ready() then return false end
text = tostring(text or ""):gsub("%s+", " ")
if text == "" then return false end
if #text > 600 then text = text:sub(1, 597) .. "..." end
if not answer and SP.said[text] and rt() - SP.said[text] < 120 then return false end
local own = 0
for _, q in ipairs(SP.queue) do if not q.answer then own = own + 1 end end
if not answer and own >= SP.MAX_OWN then return false end
if #SP.queue >= 8 then
for i = #SP.queue, 1, -1 do if not SP.queue[i].answer then table.remove(SP.queue, i) break end end
if #SP.queue >= 8 then return false end
end
SP.said[text] = rt()
local at = #SP.queue + 1
if answer then for i, q in ipairs(SP.queue) do if not q.answer then at = i break end end end
table.insert(SP.queue, at, { text = text, answer = answer or nil, at = rt() })
os.queueEvent("spawn_say")
return true
end
local lastN = 0
local function nextN()
local n = os.epoch("utc")
if n <= lastN then n = lastN + 1 end
lastN = n
return n
end
function SP.send(t, fields)
local id, key = tonumber(cfg("spawnId", nil)), cfg("spawnKey", nil)
if not id or type(key) ~= "string" then return false end
local m = fields or {}
m.t, m.n = t, nextN()
m.sig = sign(key, t, m.n, tostring(m.line or ""), { SP.dataHash(type(m.d) == "string" and m.d or ""), tostring(m.v or "") })
local ok = pcall(rednet.send, id, m, SP.PROTO)
return ok
end

function SP.encode(pcm)
local okD, dfpwm = pcall(require, "cc.audio.dfpwm")
if not okD then return nil end
local enc = dfpwm.make_encoder()
local out = {}
local CH = 8 * 1024
for i = 1, #pcm, CH do
local buf = {}
for j = i, math.min(#pcm, i + CH - 1) do buf[#buf + 1] = pcm[j] end
while #buf % 8 ~= 0 do buf[#buf + 1] = 0 end
out[#out + 1] = enc(buf)
if i + CH <= #pcm then pcall(function() os.queueEvent("spawn_breath") os.pullEvent("spawn_breath") end) end
end
return table.concat(out)
end
function SP.answerWaiting() return SP.queue[1] ~= nil and SP.queue[1].answer == true end
SP.SEND_AHEAD = 2.5
SP.CHUNK = 16 * 1024


function SP.play(item)
local style = SP.style()
local vol = math.max(0, math.min(3, tonumber(cfg("spawnVolume", cfg("volume", 2))) or 2))
local pieces = V.split(V.clarifyText(item.text))
SP.lineN = (SP.lineN or 0) + 1
local sentAny = false
for pi, piece in ipairs(pieces) do
if not item.answer and SP.answerWaiting() then
if sentAny then SP.send("cut", {}) SP.busyUntil = rt() end
return false, "gave way"
end
local data, err = V.audio(piece, style and style.accent)
if not data then SP.err = err return false, err end
local pcm, perr = V.pcmOf(data, style)
if not pcm then SP.err = perr return false, perr end
local d = SP.encode(pcm)
if not d then SP.err = "this CC:Tweaked has no cc.audio.dfpwm" return false, SP.err end

local steps = 0
while rt() < SP.busyUntil - SP.SEND_AHEAD and steps < 600 do
steps = steps + 1
if not item.answer and SP.answerWaiting() then
if sentAny then SP.send("cut", {}) SP.busyUntil = rt() end
return false, "gave way"
end
sleep(0.1)
end
if pi == 1 and item.answer and rt() < SP.busyUntil and SP.ownPlaying then
SP.send("cut", {})
SP.busyUntil = rt()
end
for i = 1, #d, SP.CHUNK do
SP.send("play", { d = d:sub(i, i + SP.CHUNK - 1), v = vol, line = SP.lineN .. ":" .. pi, fresh = i == 1 or nil })
end
sentAny = true
SP.ownPlaying = not item.answer
SP.busyUntil = math.max(rt(), SP.busyUntil) + #pcm / 48000
SP.sent = SP.sent + 1
end
SP.busyUntil = SP.busyUntil + 0.6
SP.spokeAt = os.clock()
return true
end
function SP.loop()
while state.running do
while #SP.queue > 0 do
local item = table.remove(SP.queue, 1)
if SP.ready() then
local ok, err = pcall(SP.play, item)
if not ok then SP.err = tostring(err) end
end
end
waitFor(2, "spawn_say")
end
end
local loop0 = V.loop
function V.loop()
parallel.waitForAny(loop0, function()
while state.running do
local ok, err = pcall(SP.loop)
if not ok then SP.err = tostring(err) end
sleep(2)
end
end)
end


function V.spawnReceive(id, m)
if type(m) ~= "table" or type(m.t) ~= "string" then return end
local pid, key = tonumber(cfg("spawnId", nil)), cfg("spawnKey", nil)
if not m.sig then
if m.t == "hello" then SP.cands[id] = { at = os.clock(), sp = tonumber(m.sp) } end
return
end
local P = SP.pending
if m.t == "paired" and P and P.keys[id] then
if type(m.n) == "number" and m.sig == sign(P.keys[id], "paired", m.n, "", { tostring(m.sp), tostring(m.q) }) then
setSetting("voice.spawnId", id)
setSetting("voice.spawnKey", P.keys[id])
SP.pending, SP.lastN, SP.seenAt = nil, m.n, rt()
SP.relay = { sp = tonumber(m.sp), q = tonumber(m.q), ver = m.ver }
if P.tell then pcall(P.tell, "The spawn speaker #" .. id .. " is paired. It talks when players are at spawn.") end
if sysLog then pcall(sysLog, "Spawn speaker #" .. id .. " paired", "DONE") end
end
return
end
if id ~= pid or type(key) ~= "string" then return end
if type(m.n) ~= "number" or m.n <= (SP.lastN or 0) then return end
if m.sig ~= sign(key, m.t, m.n, "", { tostring(m.sp), tostring(m.q) }) then return end
SP.lastN, SP.seenAt = m.n, rt()
SP.relay = { sp = tonumber(m.sp), q = tonumber(m.q), ver = m.ver }
end
function SP.pair(code, tell)
code = tostring(code or ""):match("^%d%d%d%d%d%d$")
if not code then return "Type the 6 numbers shown on the spawn computer's screen." end
local keys, n = {}, 0
for id, c in pairs(SP.cands) do
if os.clock() - c.at < 90 then
local t = {}
for i = 1, 24 do t[i] = string.format("%x", math.random(0, 15)) end
local key = table.concat(t)
keys[id] = key
n = n + 1
pcall(rednet.send, id, { t = "pair", proof = sign(code, "pair", id), k = POCKET.scramble(key, code, id) }, SP.PROTO)
end
end
if n == 0 then
return "No unpaired spawn speaker heard in the last 90 s. Is spawn_speaker.lua running there (startup.lua) with an ENDER modem, and is the base's own modem an ender modem too?"
end
SP.pending = { keys = keys, at = os.clock(), tell = tell }
return "Pairing code sent to " .. n .. " spawn speaker" .. (n > 1 and "s" or "") .. " - it says PAIRED on its screen in a few seconds."
end


local function smem()
local m = V.mem()
local s = m["#spawn"]
if type(s) ~= "table" then s = {} m["#spawn"] = s end
s.met = type(s.met) == "table" and s.met or {}
s.gr = type(s.gr) == "table" and s.gr or {}
s.wish = type(s.wish) == "table" and s.wish or {}
s.log = type(s.log) == "table" and s.log or {}
return s
end
SP.mem = smem
local function today() return os.date("!%Y-%m-%d") end
local function trim(t, max)
local n, oldK, oldV = 0, nil, nil
for k, v in pairs(t) do
n = n + 1
local at = type(v) == "table" and (v.at or 0) or (tonumber(v) or 0)
if not oldV or at < oldV then oldK, oldV = k, at end
end
if n > max and oldK then t[oldK] = nil end
end


local function combos(A, B)
local out = {}
for _, a in ipairs(A) do for _, b in ipairs(B) do out[#out + 1] = a .. b end end
return out
end
SP.L = {}

SP.EXAMPLES = { "{botl} tell me a joke", "{botl} roast me", "{botl} play a game", "{botl} quiz me", "{botl} tell me a riddle",
"{botl} fun fact", "{botl} tell me a story", "{botl} compliment me", "{botl} flip a coin", "{botl} roll a dice",
"{botl} rock paper scissors", "{botl} would you rather", "{botl} magic 8 ball, will I get rich", "{botl} hangman",
"{botl} what time is it", "{botl} what is the weather", "{botl} give me a mod tip", "{botl} how do I make a beacon",
"{botl} what is a creeper", "{botl} give me a build idea", "{botl} knock knock", "{botl} guess my number",
"{botl} I wish for an apple", "{botl} tell me a fortune", "{botl} pick a number", "{botl} true or false",
"{botl} what should I do", "{botl} talk like a pirate", "{botl} who are you", "{botl} help" }
SP.HELP_OPEN = { "I am a talking speaker!", "Good question - I am the voice of a base, out here at spawn.", "Hi! I am the spawn speaker.",
"You talk to me in chat.", "Easy: just type in chat.", "No buttons, no menus - just chat.", "I listen to the chat.",
"I am {bot}, a computer that talks.", "Glad you asked!", "Talking to me is simple.", "Oh, a curious one. Good.",
"I am a chatty computer - here is how it works.", "Type to me like you type to a friend.", "I understand chat messages.",
"Nobody reads the manual. Here it is anyway." }
SP.HELP_HOW = { " Start your message with {botl}, like: ", " Put my name, {botl}, first. Try: ", " Begin with the word {botl}. For example: ",
" Just start with {botl}, then say what you want: ", " Say {botl} first and I know it is for me. Like: ", " Type {botl} and a question. Try: ",
" Start with {botl}. Some ideas: ", " Use my name, {botl}, then anything: " }
SP.HELP_END = { " Typos are fine.", " I understand loose words, no exact commands.", " Ask me anything - the worst I can say is I do not know.",
" Type {botl} help for a menu.", " Try one now!", " I answer in chat and out loud.", " I know games, jokes and a lot about Minecraft.",
" You can even wish for an item - a drone might bring it.", "", " Have fun!" }
function SP.helpText(who)
local ex, used = {}, {}
while #ex < 3 do
local e = pick(SP.EXAMPLES)
if not used[e] then used[e] = true ex[#ex + 1] = e end
end
local t = pick(SP.HELP_OPEN) .. pick(SP.HELP_HOW) .. table.concat(ex, ", ") .. "." .. pick(SP.HELP_END)
return fill(t, who)
end

SP.WHO = combos({ "I am {bot}, the spawn speaker of {owner}'s base.", "I am the voice of {owner}'s base. The base itself is far from here.",
"I am a computer from {owner}'s base - this speaker is my spawn mouth.", "Just a speaker on a pole, with a whole base behind it.",
"I am {bot}. Here at spawn I am only a voice; my body is a base full of turtles and drones.",
"Think of me as the base's ears and voice at spawn.", "I am a talking speaker. The thinking happens at {owner}'s base.",
"I am {bot}. I run a whole base and still find time to chat at spawn.", "A ComputerCraft computer, talking through an ender modem.",
"I am the friendly spawn speaker. {owner} built me." },
{ "", " Say {botl} help to see what I can do.", " I tell jokes, play games and answer questions.", " Nice to meet you!",
" Ask me something.", " I do not bite. I do not even have teeth." })
SP.WHERE = { "My base is far away. Where exactly? That is a secret.", "Far from here, and that is all I can say. The drones know the way.",
"Somewhere out there. I only have a speaker here at spawn.", "I keep the base's spot to myself. Privacy, you know.",
"Not telling - {owner} would unplug me. But my drones fly from there.", "Over the hills and far away. Exact numbers stay secret." }
SP.SHOP = { "I do not run the shops - I just talk. But I hear the prices are fair today.", "Shopping? I only sell jokes. They are free.",
"The shops are around me. I am the one that does not take your money.", "No shop here, sorry. I am a talking speaker, not a vending machine.",
"I cannot sell you anything. Ask me for a joke instead - those are free.", "Buy what you need, then come back and play a game with me." }

SP.HELLO_NEW = combos({ "Hello there, {name}!", "Oh, a new face. Hi {name}!", "Welcome to spawn, {name}.", "Hey {name}, first time here?",
"Psst, {name}. Over here. The speaker.", "Greetings, {name}!", "Hi {name}, I have not seen you before.", "Well hello, {name}.",
"A new visitor! Hi {name}.", "{name}! Nice to meet you.", "Hello hello, {name}!", "Fresh face at spawn: hi {name}.",
"Oh hi, {name}. Do not mind me, I am the talking speaker.", "Ahoy, {name}!" },
{ " I am a talking speaker - start a chat message with {botl} and I answer.", " Try typing: {botl} tell me a joke.",
" Type {botl} help in chat and I show you what I can do.", " Talk to me in chat: start with {botl}.", " Ask me anything - just begin with {botl}.",
" I know games and jokes. Start with {botl}.", " Want a joke? Type {botl} joke.", " Try: {botl} roast me. If you dare.",
" Bored while shopping? Type {botl} play a game.", " Curious? Type {botl} who are you." })
SP.HELLO_AGAIN = combos({ "Welcome back to spawn, {name}.", "Hey {name}, shopping again?", "Oh, {name} is back.", "Hi again, {name}.",
"{name}! Good to see you.", "Look who it is - {name}.", "Back already, {name}?", "Hello again, {name}.", "Hey there, {name}.",
"{name}, my favourite shopper.", "Ah, {name}. Welcome.", "Hi {name}, spawn missed you.", "Oh look, {name} again.",
"{name}, back for more shopping?", "Welcome, welcome, {name}." },
{ "", " Need a joke for the queue?", " Shout {botl} if you want a game.", " I have new jokes.", " The shops are still here.",
" Want a riddle?", " Ask me anything.", " Have a good one." })
SP.HELLO_OWNER = { "Hey boss. Spawn is quiet. Mostly.", "{name}! The boss is at spawn. Everyone look busy.", "Welcome to spawn, {name}. Your speaker is working fine.",
"Hi {name}. Shopping, or checking on me?", "Boss at spawn. I will behave.", "Oh, hi {name}. I have been chatting with your visitors.",
"{name}, welcome. Nobody has unplugged me yet.", "Hey {name}. The base is fine, I checked." }
SP.HELLO_GROUP = combos({ "Hello {names}!", "Hi everyone - {names}.", "Welcome to spawn, {names}.", "Oh, a crowd! Hi {names}.",
"Hey {names}.", "Greetings, {names}." },
{ "", " Start a chat message with {botl} to talk to me.", " Who wants a joke?", " I have games, if anyone is bored.", " Have fun shopping." })

SP.IDLE = {}
local IDLE_A = { "Spawn is busy today.", "So many people walking past.", "Another lovely day at spawn.", "I like it here. Lots of visitors.",
"I counted the people walking by today. I lost count.", "Fun fact about spawn: everybody passes me sooner or later.",
"The shops smell like fresh coins.", "Somebody just bought something shiny. I could hear it.", "I am the only speaker at spawn that talks back.",
"Spawn sounds different from the base. More footsteps.", "I see a lot of hurried shoppers.", "Nobody stops to chat. I understand. Shopping is serious.",
"Spawn: the place where every adventure starts.", "Ah, the sound of busy players.", "I wonder what everyone is buying today.",
"If you are lost: this is spawn. You are welcome.", "Quiet moment at spawn.", "I have been standing here all day. Speakers do that.",
"Spawn chunks, the most loaded chunks in the world. Probably." }
local IDLE_B = { "", " Anyone want a joke?", " Say {botl} if you want to chat.", " Type {botl} play a game if you are bored.",
" I know riddles too.", " Ask me something, I do not bite.", " Start a message with {botl} - I listen.", " I could roast someone. Any volunteers?" }
SP.IDLE = combos(IDLE_A, IDLE_B)
SP.TIPS = combos({ "Tip:", "Did you know?", "Psst.", "Hint:", "Little secret:", "By the way:", "Friendly reminder:", "Quick tip:", "Hey you, shopping:",
"For the new people:" },
{ " start a chat message with {botl} and I will answer.", " type {botl} tell me a joke.", " try {botl} roast me. I am brutal.",
" {botl} play a game - I know a lot of them.", " ask {botl} fun fact for something new.", " type {botl} help to see what I can do.",
" I understand typos. Mostly.", " {botl} quiz me - how smart are you?", " {botl} tell me a riddle. Can you solve it?",
" {botl} would you rather - hard choices only.", " {botl} magic 8 ball, will I find diamonds.", " you can wish for an item: {botl} I wish for an apple." })
SP.INVITES = { "Anyone up for a quiz? Type {botl} quiz.", "Who wants a riddle? Type {botl} riddle.", "I feel like a game. Type {botl} play a game.",
"Rock, paper, scissors, anyone? Type {botl} rock paper scissors.", "Bored in the queue? Type {botl} hangman.",
"Need a laugh? Type {botl} joke.", "I have a story ready. Type {botl} tell me a story.", "Who dares? Type {botl} roast me.",
"Think you are lucky? Type {botl} flip a coin.", "Want to know your future? Type {botl} fortune." }
SP.NAMED = combos({ "{name}, ", "Hey {name}, ", "Psst, {name}. ", "{name}! ", "Oh, {name}, " },
{ "you look like someone who would enjoy a joke. Type {botl} joke.", "have you tried talking to me? Start with {botl}.",
"want a riddle while you shop? Type {botl} riddle.", "nice to see you around spawn.", "do you dare? {botl} roast me.",
"I bet you cannot beat me at rock paper scissors.", "I have a fun fact with your name on it. Type {botl} fun fact.",
"take your time, the shops are not going anywhere." })

SP.W_ASK = combos({ "{n} {item}?", "You wish for {n} {item}?", "{n} {item} - is that your wish?", "So: {n} {item}?", "A wish for {n} {item}." },
{ " Say yes and a drone brings it.", " Type yes and I send a drone.", " Yes or no?", " Say yes to make it real.", " Confirm with yes." })
SP.W_OK = { "Your wish is my command. A drone is coming with {n} {item}.", "Wish granted! {n} {item} - a drone brings it to you.",
"Done. {n} {item} is on the drone list. Stay in the overworld.", "Okay! A drone will bring {n} {item}. Look up when it comes.",
"Granted. The base sends {n} {item} by drone.", "Poof! Well, nearly. {n} {item} - by drone, shortly.",
"Coming right up: {n} {item}, delivered by drone.", "Your {n} {item} is on its way. Drones are fast. Sometimes." }
SP.W_NONE = { "I looked in the base's storage - no {item} there.", "No {item} in storage, sorry. Wish for something else?",
"Hmm, {item}? The base has none. Try another item.", "I could not find {item} in the storage system.",
"The base is out of {item}. Or it never had any.", "{item}? Not in stock. Make another wish." }
SP.W_LIMIT = { "That was your {max} wishes for today. Come back tomorrow!", "No more wishes today - {max} a day. Tomorrow, okay?",
"Wish limit reached: {max} a day. Even genies have rules.", "You used all {max} wishes for today. Try again tomorrow." }
SP.W_BUSY = { "Your last wish is still on its way. One at a time!", "Patience - the drone with your last wish is not done yet.",
"One wish at a time, please. The last one is still coming." }
SP.W_NO = { "Okay, wish cancelled.", "No wish then. Your loss!", "Fine, I keep it.", "Wish cancelled. Make another one any time." }
SP.W_NEVER = { "Not that one. Some things are not for wishing.", "Nope, {item} is not on the wish list.", "Sorry, I cannot give {item} away.",
"That item stays in storage. Wish for something else." }
SP.W_OWNER = { "Boss, you own everything already.", "You do not need to wish, boss - it is all yours.", "Wishing for your own items? Cute." }


local function norm(s) return " " .. table.concat(V.norm(s), " ") .. " " end
local function hasAny(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return true end end return false end
SP.HELP_ALWAYS = { "how do i talk to it", "how do i talk to you", "how do i talk to this", "how do i talk to the speaker",
"how do i interact", "how to interact", "how do you interact", "how do i use the speaker", "how do i use this speaker",
"how do i use the bot", "how do i use this bot", "how do i talk to the bot", "how do i use you", "how to use you",
"what is this speaker", "what is that speaker", "who is talking", "who is speaking", "who said that", "what is talking",
"is this a bot", "is that a bot", "is this an ai", "is that an ai", "is it a bot", "talking speaker", "the speaker talks",
"this speaker talks", "it talks", "it can talk", "how does the speaker work", "how does the bot work", "what can the bot do",
"what can the speaker do" }

SP.HELP_LOOSE = { "how do i use it", "how do i use this", "how to use it", "how to use this", "how do i talk", "how to talk",
"how does it work", "how does this work", "how do you work", "what can i say", "what do i say", "what do i type", "what can i ask",
"what can you do", "what do you do", "what are you", "who are you", "what is this", "what is that", "what is this thing",
"how do i ask", "what does it do", "what does this do", "are you a bot", "are you real", "are you ai", "are you a robot" }

SP.HELP_NAMED = { "commands", "help", "instructions", "explain", "i do not get it", "i dont get it", "how", "what", "huh", "options" }
SP.WISH_RE = { "i wish for (.+)", "i wish i had (.+)", "i wish i have (.+)", "i want (.+)", "i need (.+)", "can i have (.+)", "can i get (.+)",
"could i have (.+)", "could i get (.+)", "may i have (.+)", "give me (.+)", "gimme (.+)", "can you give me (.+)", "could you give me (.+)",
"can you get me (.+)", "send me (.+)", "i would like (.+)", "id like (.+)", "i d like (.+)", "bring me (.+)", "i wish (.+)" }

SP.NOT_ITEM = { "to", "you", "a joke", "joke", "jokes", "a game", "game", "games", "a riddle", "riddle", "a story", "story", "a fact", "fact",
"help", "a hint", "hint", "a fun fact", "fun fact", "a roast", "a compliment", "compliment", "attention", "a break", "advice",
"a tip", "tip", "an idea", "idea", "a hug", "hug", "friends", "a friend", "more", "it", "that", "this", "something", "anything",
"nothing", "money", "a fortune", "fortune", "a quiz", "quiz", "a number", "number", "a name", "name", "a home", "home", "sleep",
"food", "luck", "good luck", "peace", "silence", "quiet", "the base", "your base", "a ride", "ride", "a taxi", "taxi", "sing" }
SP.NEVER = { "spawn_egg", "command_block", "structure_block", "structure_void", "barrier", "bedrock", "jigsaw", "debug_stick", "light",
"creative", "end_portal_frame", "dragon_egg", "spawner", "reinforced_deepslate", "budding_amethyst", "knowledge_book", "infinity",
"turtle", "computer", "pocket_computer", "drone", "me_controller", "me_drive", "storage_cell", "cell_component" }
local WORD_N = { one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10, eleven = 11,
twelve = 12, sixteen = 16, twenty = 20, thirty = 30, fifty = 50 }
local AMOUNT = { stack = 64, stacks = 64, dozen = 12, few = 4, couple = 2, handful = 8, bunch = 16, lot = 32, lots = 32, ton = 64, tons = 64 }
local STOP = { please = true, pls = true, plz = true, now = true, thanks = true, thx = true, ty = true, ["for"] = true, me = true,
of = true, the = true, some = true, any = true, a = true, an = true, pretty = true, really = true, today = true, more = true,
just = true, maybe = true, too = true, also = true, ["if"] = true, possible = true, you = true, can = true }
local function singular(w)
if w:match("ies$") then return w:sub(1, -4) .. "y" end
if w:match("ches$") or w:match("shes$") or w:match("xes$") then return w:sub(1, -3) end
if w:match("[^s]s$") then return w:sub(1, -2) end
return w
end

function SP.wishParse(phrase)
local n, mult = nil, 1
local out = {}
for w in low(phrase):gsub("[^%w_ ]", " "):gmatch("%S+") do
if tonumber(w) and not n and #out == 0 then n = math.floor(tonumber(w))
elseif WORD_N[w] and not n and #out == 0 then n = WORD_N[w]
elseif AMOUNT[w] and #out == 0 then mult = mult * AMOUNT[w]
elseif not STOP[w] then out[#out + 1] = w end
end
if mult > 1 then n = (n or 1) * mult end
return n, table.concat(out, " ")
end

function SP.findItem(name)
name = low(name):gsub("^%s+", ""):gsub("%s+$", "")
if name == "" then return nil end
local ws = {}
for w in name:gmatch("%S+") do ws[#ws + 1] = singular(w) end
local want = table.concat(ws, " ")
local items = (state.me and state.me.items) or {}
local best, bs
for _, it in ipairs(items) do
local id = tostring(it.name or "")
local disp = low(it.display or it.displayName or "")
local path = low(id:gsub("^.-:", ""):gsub("_", " "))
local dsing = {}
for w in disp:gmatch("%S+") do dsing[#dsing + 1] = singular(w) end
local ds = table.concat(dsing, " ")
local s
if ds == want or path == want then s = 100
elseif ds == "minecraft " .. want then s = 90
elseif (" " .. ds .. " "):find(" " .. want .. " ", 1, true) or (" " .. path .. " "):find(" " .. want .. " ", 1, true) then
s = 60 - #ds / 10
elseif #want >= 4 and V.same and V.same(ds, want) then s = 50 end
if s and id:find("^minecraft:") then s = s + 1 end
if s and (tonumber(it.count) or 0) > 0 and (not bs or s > bs) then best, bs = it, s end
end
if best then return { id = best.name, name = best.display or best.displayName or best.name, count = tonumber(best.count) or 0 } end

if #items == 0 and FACTORY and FACTORY.variants then
local id = "minecraft:" .. want:gsub(" ", "_")
local okV, v = pcall(FACTORY.variants, id)
if okV and type(v) == "table" and (tonumber(v.plain) or 0) > 0 then return { id = id, name = want, count = tonumber(v.plain) } end
end
return nil
end
function SP.never(id)
id = low(id)
for _, w in ipairs(SP.NEVER) do if id:find(w, 1, true) then return true end end
for w in low(cfg("wishBlock", "") or ""):gmatch("[^,%s]+") do if id:find(w, 1, true) then return true end end
return false
end
function SP.wishesToday(who)
local s = smem()
local w = s.wish[low(who)]
local all = s.wall
return (type(w) == "table" and w.d == today()) and (w.n or 0) or 0, (type(all) == "table" and all.d == today()) and (all.n or 0) or 0
end
local function itemWord(name, n)
name = tostring(name)
if n and n > 1 and not name:lower():match("s$") then return name .. "s" end
return name
end

function SP.wish(who, raw)
local t = low(raw):gsub("[^%w_' ]", " ")
local word = low(cfg("name", "base"))
t = (" " .. t .. " "):gsub(" " .. word .. " ", " "):gsub("%s+", " ")
local phrase
for _, re in ipairs(SP.WISH_RE) do
phrase = t:match("^ ?" .. re) or t:match(" " .. re)
if phrase then break end
end
if not phrase then return nil end
phrase = phrase:gsub("^%s+", ""):gsub("%s+$", "")
for _, w in ipairs(SP.NOT_ITEM) do
if phrase == w or phrase:find("^" .. w:gsub("%p", "%%%0") .. " ") then return nil end
end
if phrase:find("^to ") or phrase:find("^you ") or phrase:find("^a?n? ?help") then return nil end
local n, name = SP.wishParse(phrase)
if name == "" then return nil end
if cfg("wish", true) == false then return "Wishes are switched off at spawn right now. Sorry!" end
if V.isOwner(who) then return fill(pick(SP.W_OWNER), who) end
if not V.giftEarn then return "I cannot send things from here yet. Sorry!" end
local it = SP.findItem(name)
if not it then

if #name > 30 or select(2, name:gsub("%S+", "")) > 4 then return nil end
return fill(pick(SP.W_NONE):gsub("{item}", name), who)
end
if SP.never(it.id) then return fill(pick(SP.W_NEVER):gsub("{item}", tostring(it.name)), who) end
local daily, all = tonumber(cfg("wishDaily", 3)) or 3, tonumber(cfg("wishAll", 40)) or 40
local mine, everyone = SP.wishesToday(who)
if mine >= daily then return fill(pick(SP.W_LIMIT):gsub("{max}", tostring(daily)), who) end
if everyone >= all then return "The base granted " .. all .. " wishes today already - that is all for today. Come back tomorrow!" end
for _, g in ipairs((V.giftQueue and V.giftQueue()) or {}) do
if low(g.who) == low(who) and g.why == "wish" then return fill(pick(SP.W_BUSY), who) end
end
local max = tonumber(cfg("wishMax", 64)) or 64
n = math.max(1, math.min(n or 1, max, it.count))
SP.wpend = SP.wpend or {}
SP.wpend[low(who)] = { id = it.id, name = it.name, n = n, till = os.clock() + 90 }
return fill(pick(SP.W_ASK):gsub("{n}", tostring(n)):gsub("{item}", itemWord(it.name, n)), who)
end

function SP.wishAnswer(who, raw)
local P = SP.wpend and SP.wpend[low(who)]
if not P then return nil end
if os.clock() > P.till then SP.wpend[low(who)] = nil return nil end
local ws = V.norm(raw)
local word = low(cfg("name", "base"))
local w1 = ws[1] == word and ws[2] or ws[1]
if #ws > 4 then return nil end
local YES = { yes = 1, y = 1, yeah = 1, yep = 1, sure = 1, ok = 1, okay = 1, please = 1, yup = 1, ya = 1, definitely = 1, absolutely = 1 }
local NO = { no = 1, n = 1, nope = 1, nah = 1, cancel = 1, never = 1, stop = 1 }
if NO[w1 or ""] then SP.wpend[low(who)] = nil return fill(pick(SP.W_NO), who) end
if not YES[w1 or ""] then return nil end
SP.wpend[low(who)] = nil
local ok, why = V.giftEarn(who, "wish", { { P.id, P.n } })
if not ok then return "I could not send it: " .. tostring(why or "?") .. "." end
local s = smem()
local k, d = low(who), today()
s.wish[k] = (type(s.wish[k]) == "table" and s.wish[k].d == d) and s.wish[k] or { d = d, n = 0 }
s.wish[k].n = s.wish[k].n + 1
s.wish[k].at = os.epoch("utc")
s.wall = (type(s.wall) == "table" and s.wall.d == d) and s.wall or { d = d, n = 0 }
s.wall.n = s.wall.n + 1
s.log[#s.log + 1] = { who = who, item = P.id, n = P.n, at = os.epoch("utc") }
while #s.log > 30 do table.remove(s.log, 1) end
trim(s.wish, 300)
V.saveMem()
if pushNote then pcall(pushNote, "INFO", who .. " wished for " .. P.n .. " " .. tostring(P.name) .. " at spawn - a drone brings it", C and C.info) end
return fill(pick(SP.W_OK):gsub("{n}", tostring(P.n)):gsub("{item}", itemWord(P.name, P.n)), who)
end


SP.helpAt = {}
local function answer(who, c, sp)
if not c then return end
if chatTell then chatTell(who, c, true) end
local line = sp or c
local others = #SP.players() - 1
if others > 0 and not low(line):find(low(who), 1, true) then line = who .. ", " .. line end
SP.say(line, true)
V.openConvo(who)
end
function SP.chat(m)
local who, text = tostring(m.name or ""), tostring(m.msg or "")
local k = low(who)
local word = low(cfg("name", "base"))
local ws = V.norm(text)
local t = norm(text)
local named = V.calledByName(ws, text, word)
local bot = hasAny(t, { "speaker", "bot", "robot", "computer", "ai" })
local convo = V.convo[k] and os.clock() < V.convo[k]
local spoke = SP.spokeAt and os.clock() - SP.spokeAt < 60

local wa = SP.wishAnswer(who, text)
if wa then answer(who, wa) return true end

local strong = hasAny(t, SP.HELP_ALWAYS)
local loose = (hasAny(t, SP.HELP_LOOSE) and #ws <= 9 and (named or bot or spoke or convo)) or
(hasAny(t, SP.HELP_NAMED) and #ws <= 4 and (named or bot))
if (strong or loose) and not (V.games[k]) then
if strong and not named and SP.helpAt[k] and os.clock() - SP.helpAt[k] < 60 then return false end

local own = named and V.intent and select(2, V.intent(V.fix and V.fix(ws) or ws)) or 0
if strong or not named or own < 2 or hasAny(t, { "help", "commands", "what can you do", "how do i use", "how do i talk", "how do i interact" }) then
SP.helpAt[k] = os.clock()
if (hasAny(t, { "who are you", "what are you" }) and named) then answer(who, fill(pick(SP.WHO), who)) return true end
answer(who, SP.helpText(who))
return true
end
end

if named or bot or convo then
local w = SP.wish(who, text)
if w then answer(who, w) return true end
if hasAny(t, { "who are you", "what are you", "who made you", "who built you", "are you the base" }) then answer(who, fill(pick(SP.WHO), who)) return true end
if hasAny(t, { "where is the base", "where is your base", "where is the main base", "where do you live", "base coords",
"base coordinates", "where are you" }) then answer(who, fill(pick(SP.WHERE), who)) return true end
if hasAny(t, { "shop", "shops", "buy", "sell", "price", "prices", "trade" }) and #ws <= 8 then answer(who, fill(pick(SP.SHOP), who)) return true end
end

local was = V.reactAll
local now = os.clock()
V.reactAll = (SP.reactAt and now - SP.reactAt < 60) and now or nil
local r = SP.inCtx(V.chatCore, m)
if V.reactAll == now and not (SP.reactAt and now - SP.reactAt < 60) then SP.reactAt = now end
V.reactAll = was
return r
end



SP.spam = SP.spam or {}
SP.SLOW = { "Whoa, slow down {name}! I need a breather. Back in a minute.", "{name}, my circuits are overheating. Give me a minute.",
"Too many questions, {name}! I am taking a short break from you.", "Easy there, {name}. Let me cool down for a minute.",
"{name}, I only have one speaker and you used it all. A minute of quiet, please.", "Spam detected, {name}. I will be back in a minute." }
function SP.spamBlocked(who, text)
if V.isOwner(who) then return false end
local k = low(who)
local now = os.clock()
local e = SP.spam[k]
if not e then e = { times = {}, last = {} } SP.spam[k] = e end
if e.mutedTill and now < e.mutedTill then return true end
e.mutedTill = nil
local nw = V.norm(text)
local key = #nw >= 3 and table.concat(nw, " ") or ""
local same = 0
for i = #e.last, 1, -1 do
if now - e.last[i].at > 60 then table.remove(e.last, i) elseif e.last[i].key == key then same = same + 1 end
end
e.last[#e.last + 1] = { key = key, at = now }
while #e.last > 10 do table.remove(e.last, 1) end
local maxSame = tonumber(cfg("spamSame", 3)) or 3
if key ~= "" and maxSame > 0 and same >= maxSame - 1 then return true end
return false
end
function SP.spamAnswered(who)
if V.isOwner(who) then return end
local k = low(who)
local e = SP.spam[k]
if not e then return end
local now = os.clock()
local win = tonumber(cfg("spamWindow", 30)) or 30
for i = #e.times, 1, -1 do if now - e.times[i] > win then table.remove(e.times, i) end end
e.times[#e.times + 1] = now
if #e.times >= (tonumber(cfg("spamBurst", 8)) or 8) then
e.times = {}
e.mutedTill = now + (tonumber(cfg("spamMute", 60)) or 60)
if chatTell then chatTell(who, fill(pick(SP.SLOW), who)) end
end
end
local chat0 = V.chat
function V.chat(m)
if type(m) ~= "table" then return chat0(m) end
local who = tostring(m.name or "")
if SP.spamBlocked(who, tostring(m.msg or "")) then return false end
local playing = V.games[low(who)] ~= nil
local r = SP.chatRoute(m)
if r and not playing then SP.spamAnswered(who) end
return r
end
function SP.chatRoute(m)
if type(m) == "table" and not V.ctx and SP.ready() and SP.isAt(tostring(m.name or "")) and not V.nearPlayers0Has(m.name) then
V.heardAt = rt()
local ok, r = pcall(SP.named, SP.chat, m)
if not ok then SP.err = tostring(r) return false end
return r
end
return chat0(m)
end

function V.nearPlayers0Has(name)
local okN, list = pcall(nearPlayers0)
for _, p in ipairs(okN and list or {}) do if low(p.name) == low(name) then return true end end
return false
end




SP.TP_RE = { "i wish to teleport to (%S+)", "i wish i could teleport to (%S+)", "i wish to go to (%S+)", "i wish to fly to (%S+)",
"i wish to be with (%S+)", "i wish i was with (%S+)", "i wish i were with (%S+)", "teleport me to (%S+)", "tp me to (%S+)",
"take me to (%S+)", "fly me to (%S+)", "bring me to (%S+)", "send me to (%S+)", "i want to go to (%S+)",
"i want to teleport to (%S+)", "i want to fly to (%S+)", "can i teleport to (%S+)", "can you teleport me to (%S+)",
"can i fly to (%S+)", "can you take me to (%S+)", "i wish to visit (%S+)", "tp to (%S+)", "teleport to (%S+)" }
SP.TPA = combos({ "*shrugs*", "Meh.", "*yawns*", "Ugh.", "Hmm, nah.", "*shrugs lazily*", "Too far for my drones.", "Honestly?" },
{ " Different dimension. Just use /tpa {who}. I am too lazy for portals.", " Drones do not do other dimensions. Type /tpa {who} - way easier.",
" That is not the overworld. /tpa {who} works, and I can stay right here.", " I only fly in the overworld. /tpa {who} - you are welcome.",
" Portals give my drones a headache. Try /tpa {who}.", " /tpa {who}. Look, it is one command, and I am resting." })


SP.TP_YES = combos({ "Feeling generous today.", "Okay, fine.", "Sure, why not.", "Lucky you - I am in a good mood.", "Alright, alright.",
"You caught me on a good day.", "The dice say yes.", "Hmm... yes." },
{ " A drone takes you to {who}.", " Hold still, a drone is coming to fly you to {who}.", " Drone on its way - next stop: {who}.",
" One drone ride to {who}, coming up.", " Hop on the drone when it comes. Destination: {who}." })
SP.TP_NOPE = combos({ "Nah.", "*rolls a dice* Nope.", "Not feeling it right now.", "Hmm... no.", "The dice say no.", "Ask me later.",
"My drones are on a coffee break.", "Not today.", "*yawns* Maybe another time." },
{ " Walk, or try /tpa {who}.", " /tpa {who} exists, you know.", " Try again in a minute - my mood changes fast.", "",
" {who} will survive without you for a bit.", " I am a speaker, not a taxi company." })
SP.TP_AGAIN_NO = { "I said no. Still no. Ask me again in a few minutes.", "Still not feeling it. My mood changes slowly.",
"Asking again will not change my mind. Not yet, anyway.", "Nope, same answer. Give me a few minutes.",
"I remember you asked. The answer is still no.", "No means no - for a few minutes at least. Try /tpa {who}." }
SP.TP_AGAIN_YES = { "I already sent a drone for you. Patience!", "Your drone to {who} is on its way already.",
"Once is enough - the drone is coming.", "I said yes already. Wait for the drone." }
local function onlinePlayer(word, notMe)
word = low(word):gsub("[^%w_]", "")
local NOT = { me = 1, you = 1, spawn = 1, base = 1, home = 1, the = 1, my = 1, your = 1, his = 1, her = 1, our = 1, their = 1, bed = 1,
him = 1, them = 1, there = 1, here = 1, someone = 1, somebody = 1, everyone = 1, nether = 1, ["end"] = 1, village = 1 }
if #word < 3 or NOT[word] then return nil end
local hit, n = nil, 0
for _, e in ipairs(state.players or {}) do
local nm = tostring(e.name or "")
local k = low(nm)
if k ~= low(notMe) and (not state.online or state.online[k]) then
if k == word then return nm, e end
if k:sub(1, #word) == word or (#word >= 5 and V.same and V.same(k, word)) then hit, n = e, n + 1 end
end
end
if n == 1 then return hit.name, hit end
return nil
end
function SP.tpWish(who, target)
local name, e = onlinePlayer(target, who)
if not name then
if low(target) == low(who) then return "You are already with yourself. Deep." end
return nil
end
if cfg("wishTp", true) == false then return "Drone rides to players are switched off. Try /tpa " .. name .. "." end
local want = DRONE_DIM or "minecraft:overworld"
local me
for _, x in ipairs(state.players or {}) do if low(x.name) == low(who) then me = x end end
local dimOf = function(x) return x and x.dim end
if (dimOf(e) and dimOf(e) ~= want) or (dimOf(me) and dimOf(me) ~= want) or not startRide or #(droneOrder or {}) == 0 then
return (pick(SP.TPA):gsub("{who}", name))
end
local k = low(who)
local m = V.mem()
m[k] = type(m[k]) == "table" and m[k] or {}
local r = m[k]
r.tpw = (type(r.tpw) == "table" and r.tpw.d == today()) and r.tpw or { d = today(), n = 0 }
local daily = tonumber(cfg("tpDaily", 3)) or 3
if not V.isOwner(who) and r.tpw.n >= daily then return "That was your " .. daily .. " drone rides to players for today. /tpa still works!" end
if V.isOwner(who) then
startRide(who, { kind = "player", name = name }, true)
return "On it, boss. A drone takes you to " .. name .. "."
end

SP.tpMood = SP.tpMood or {}
local mood = SP.tpMood[k]
local keep = tonumber(cfg("tpRemember", 180)) or 180
if mood and os.clock() - mood.at >= 0 and os.clock() - mood.at < keep then
return ((mood.yes and pick(SP.TP_AGAIN_YES) or pick(SP.TP_AGAIN_NO)):gsub("{who}", mood.who))
end
local chance = math.max(0, math.min(1, tonumber(cfg("tpChance", 0.5)) or 0.5))
local yes = math.random() < chance
SP.tpMood[k] = { at = os.clock(), yes = yes, who = name }
if not yes then return (pick(SP.TP_NOPE):gsub("{who}", name)) end
r.tpw.n = r.tpw.n + 1
V.saveMem()
startRide(who, { kind = "player", name = name }, true)
return (pick(SP.TP_YES):gsub("{who}", name))
end





function SP.setBio(who, text)
text = tostring(text or ""):gsub("^[%s:,%-]+", ""):gsub("%s+$", ""):gsub("%s+", " ")
if text == "" then return nil end
local m = V.mem()
local k = low(who)
m[k] = type(m[k]) == "table" and m[k] or {}
if text:lower() == "nothing" or text:lower() == "forget it" then m[k].bio = nil V.saveMem() return "Okay, I forgot what you told me about yourself." end
if #text > 120 then text = text:sub(1, 120) end
m[k].bio = text
V.saveMem()
return "Got it. When someone asks me about " .. who .. ", I tell them: " .. text
end
function SP.aboutOther(asker, word)
local w = low(word):gsub("[^%w_]", "")
if #w < 3 or w == low(asker) or w == "me" or w == "you" or w == "yourself" then return nil end
local m = V.mem()
local k
if type(m[w]) == "table" and not w:find("^#") then k = w end
if not k then
local nm = onlinePlayer(w, asker)
if nm then k = low(nm) end
end
if not k then return nil end
local r = type(m[k]) == "table" and m[k] or {}
local shown = k
for _, e in ipairs(state.players or {}) do if low(e.name) == k then shown = e.name end end
local parts = {}
if r.bio then parts[#parts + 1] = shown .. " says: \"" .. r.bio .. "\"" end
if r.nick then parts[#parts + 1] = "I call " .. shown .. " " .. r.nick .. "." end
local favs = {}
for a, b in pairs(type(r.fav) == "table" and r.fav or {}) do favs[#favs + 1] = "favourite " .. a .. ": " .. b end
table.sort(favs)
if #favs > 0 then parts[#parts + 1] = table.concat(favs, ", ", 1, math.min(5, #favs)) .. "." end
if r.bday then parts[#parts + 1] = "Birthday: " .. r.bday .. "." end
local word_ = low(cfg("name", "base"))
if #parts == 0 then
return shown .. " has not told me anything about themselves yet. Anyone can: " .. word_ .. ", about me: <a few words>.",
shown .. " has not told me about themselves yet."
end
return table.concat(parts, " "), pick({ "Here is what " .. shown .. " told me about themselves - in chat.",
"I sent you what " .. shown .. " told me.", shown .. "? I put it in chat for you.", "Check your chat - that is what " .. shown .. " said about themselves." })
end

table.insert(V.patterns, 1, function(who, raw)
local t = " " .. low(raw):gsub("[^%w_:' ]", " "):gsub("%s+", " ") .. " "
local word = low(cfg("name", "base"))
t = t:gsub("^ " .. word .. " ", " ")
local bio = low(raw):gsub("^%s*" .. word .. "[%s,:!]*", ""):match("^about me[%s:,%-]+(.+)") or low(raw):match("my bio is[%s:]+(.+)")
if bio then
local orig = tostring(raw):sub(#tostring(raw) - #bio + 1)
return SP.setBio(who, orig)
end
for _, re in ipairs(SP.TP_RE) do
local target = t:match(" " .. re .. " ")
if target then
local c = SP.tpWish(who, target)
if c then return c end
end
end
for _, re in ipairs({ "tell me about (%S+)", "who is (%S+)", "what do you know about (%S+)", "do you know (%S+)", "info on (%S+)",
"what is (%S+) like", "tell me something about (%S+)" }) do
local target = t:match(" " .. re .. " ")
if target then
local c, sp = SP.aboutOther(who, target)
if c then return c, sp end
end
end
return nil
end)


SP.seen = {}
SP.nextIdle = nil
function SP.tick()
if not SP.ready() then return end
local now = os.clock()
local list = SP.players()
local s = smem()
local arrivals = {}
local leave = 120
for _, p in ipairs(list) do
local k = low(p.name)
local prev = SP.seen[k]
SP.seen[k] = now
if not prev or now - prev > leave then arrivals[#arrivals + 1] = p.name end
end
for k, at in pairs(SP.seen) do if now - at > 900 then SP.seen[k] = nil end end
if #list == 0 then SP.nextIdle = nil return end

local greet = {}
local every = tonumber(cfg("spawnGreetEvery", 7200)) or 7200
local nowE = os.epoch("utc")
for _, n in ipairs(arrivals) do
local k = low(n)
local met = s.met[k]
local last = tonumber(s.gr[k]) or 0
if not met then
s.met[k] = nowE
trim(s.met, 500)
greet[#greet + 1] = { name = n, new = true }
if chatTell then
chatTell(n, fill("Hi {name}! The speaker at spawn talks. Start a chat message with {botl}: {botl} tell me a joke, " ..
"{botl} roast me, {botl} play a game, {botl} help.", n))
end
elseif V.isOwner(n) and nowE - last > 600000 then greet[#greet + 1] = { name = n, owner = true }
elseif nowE - last > every * 1000 and math.random() < 0.5 then greet[#greet + 1] = { name = n } end
end
if cfg("spawnGreet", true) ~= false and #greet > 0 and (not SP.greetAt or now - SP.greetAt > 20) then
SP.greetAt = now
for _, g in ipairs(greet) do s.gr[low(g.name)] = nowE end
trim(s.gr, 500)
if #greet == 1 then
local g = greet[1]
local list_ = g.owner and SP.HELLO_OWNER or (g.new and SP.HELLO_NEW or SP.HELLO_AGAIN)
SP.say(fill(pick(list_), g.name))
else
local names = {}
for _, g in ipairs(greet) do names[#names + 1] = g.name end
SP.say(fill(pick(SP.HELLO_GROUP):gsub("{names}", V.joinNames(names)), names[1]))
end
V.saveMem()
end

local chatter = tonumber(cfg("spawnChatter", 5)) or 5
if chatter <= 0 or cfg("fun", true) == false then return end
if not SP.nextIdle then SP.nextIdle = now + chatter * 60 * (0.6 + math.random() * 0.8) return end
if now < SP.nextIdle then return end
if SP.spokeAt and now - SP.spokeAt < 90 then SP.nextIdle = now + 60 return end
SP.nextIdle = now + chatter * 60 * (0.7 + math.random() * 0.6)
local line = SP.idleLine(list)
if line then SP.say(line) end
end
function SP.idleLine(list)
local who = list[math.random(1, math.max(1, #list))]
local name = who and who.name or nil
local r = math.random(1, 100)
local line
if r <= 22 then line = pick(SP.IDLE)
elseif r <= 40 then line = pick(SP.TIPS)
elseif r <= 52 then line = pick(SP.INVITES)
elseif r <= 62 and name then line = pick(SP.NAMED)
elseif r <= 74 and V.JOKES then line = "Joke time. " .. pick(V.JOKES)
elseif r <= 86 and V.factText then local okF, f = pcall(V.factText) line = okF and f and ("Fun fact: " .. f) or pick(SP.IDLE)
elseif r <= 94 and V.MODTIPS then line = "Mod tip: " .. pick(V.MODTIPS)
elseif V.L and V.L.WISDOM then line = pick(V.L.WISDOM)
else line = pick(SP.IDLE) end
return fill(line, name)
end
V.tickHooks[#V.tickHooks + 1] = function()
local ok, err = pcall(SP.named, SP.tick)
if not ok then SP.err = tostring(err) end
end


function SP.status()
local out = {}
local a = SP.at()
out[#out + 1] = "SPAWN SPEAKER: " .. (cfg("spawn", true) == false and "OFF" or "on") ..
" | " .. (SP.paired() and ("paired with #" .. tostring(cfg("spawnId", "?"))) or "NOT PAIRED") ..
" | " .. (SP.online() and ("heard " .. math.floor(rt() - SP.seenAt) .. " s ago, " .. tostring(SP.relay and SP.relay.sp or "?") .. " speaker(s)")
or "not heard from (its area is not loaded, or it is not running)")
out[#out + 1] = "Spot: " .. (a and (a.x .. " " .. (a.y or "?") .. " " .. a.z) or "NOT SET - stand there:  $drone spawn here") ..
" | range " .. tostring(cfg("spawnRange", 24)) .. " | voice " .. tostring(cfg("spawnVoice", "bright")) ..
" | call word: " .. tostring(SP.named(function() return V.cfg("name", "base") end)) ..
" | idle talk every ~" .. tostring(cfg("spawnChatter", 5)) .. " min"
local names = {}
for _, p in ipairs(SP.players()) do names[#names + 1] = p.name end
out[#out + 1] = "At spawn now: " .. (#names > 0 and table.concat(names, ", ") or "nobody") .. " | lines sent: " .. SP.sent ..
(#SP.queue > 0 and (" | waiting: " .. #SP.queue) or "")
local mine, all = SP.wishesToday("")
out[#out + 1] = "Wishes: " .. (cfg("wish", true) == false and "OFF" or "on") .. " - " .. all .. " today (max " .. tostring(cfg("wishAll", 40)) ..
", " .. tostring(cfg("wishDaily", 3)) .. " a player, " .. tostring(cfg("wishMax", 64)) .. " per wish)"
local s = smem()
for i = math.max(1, #s.log - 2), #s.log do
local e = s.log[i]
if e then out[#out + 1] = "  wished: " .. tostring(e.who) .. " - " .. tostring(e.n) .. " " .. tostring(e.item) end
end
if SP.err then out[#out + 1] = "Last problem: " .. tostring(SP.err) end
if not SP.paired() then
local c = 0
for _, x in pairs(SP.cands) do if os.clock() - x.at < 90 then c = c + 1 end end
out[#out + 1] = c > 0 and ("An unpaired spawn speaker is waiting: type the code from its screen - voice spawn pair <code>")
or "Set it up: a computer at spawn + Speaker + ENDER modem, spawn_speaker.lua on it as startup.lua"
end
return out
end
V.commands.spawn = function(words, say, who)
local a, b = low(words[3]), low(words[4])
local owner = who or (V.ownerName and V.ownerName())
if a == "" or a == "status" then for _, l in ipairs(SP.status()) do say(l) end
elseif a == "here" then
local p
for _, e in ipairs(state.players or {}) do if owner and low(e.name) == low(owner) then p = e end end
if not (p and p.p and tonumber(p.p.x)) then say("I cannot see where you are (Player Detector).") return end
setSetting("voice.spawnAt", { x = math.floor(p.p.x), y = math.floor(tonumber(p.p.y) or 64), z = math.floor(p.p.z) })
if p.dim then setSetting("voice.spawnDim", p.dim) end
say("Spawn speaker spot: " .. math.floor(p.p.x) .. " " .. math.floor(tonumber(p.p.y) or 64) .. " " .. math.floor(p.p.z) ..
" (players within " .. tostring(cfg("spawnRange", 24)) .. " blocks are 'at spawn')")
elseif a == "at" and tonumber(words[4]) and tonumber(words[5]) and tonumber(words[6]) then
setSetting("voice.spawnAt", { x = tonumber(words[4]), y = tonumber(words[5]), z = tonumber(words[6]) })
say("Spawn speaker spot: " .. words[4] .. " " .. words[5] .. " " .. words[6])
elseif a == "pair" then say(SP.pair(words[4], say))
elseif a == "unpair" then
SP.send("unpair", {})
setSetting("voice.spawnId", false)
setSetting("voice.spawnKey", false)
SP.seenAt = nil
say("Unpaired. The spawn computer shows a new code.")
elseif a == "name" then
local w = tostring(words[4] or ""):lower()
if w == "off" or w == "reset" then
setSetting("voice.spawnName", false)
say("The spawn speaker answers to the base's own word again: " .. tostring(cfg0("name", "base")))
elseif w:match("^%a[%w]*$") and #w >= 3 and #w <= 16 then
setSetting("voice.spawnName", w)
say("At spawn players now call it: " .. w .. " (like: " .. w .. " tell me a joke). The base itself stays " .. tostring(cfg0("name", "base")) .. ".")
else
say("Use: voice spawn name <one word, 3-16 letters> | voice spawn name off   - now: " ..
tostring(SP.named(function() return V.cfg("name", "base") end)))
end
elseif a == "on" or a == "off" then
setSetting("voice.spawn", a == "on")
say("Spawn speaker " .. (a == "on" and "ON" or "OFF"))
elseif a == "range" and tonumber(words[4]) then
setSetting("voice.spawnRange", math.max(4, math.min(128, tonumber(words[4]))))
say("Players within " .. cfg("spawnRange", 24) .. " blocks of the spot are at spawn")
elseif a == "chatter" and tonumber(words[4]) then
setSetting("voice.spawnChatter", math.max(0, math.min(120, tonumber(words[4]))))
say("Idle talk at spawn every ~" .. cfg("spawnChatter", 5) .. " min (0 = never)")
elseif a == "greet" and (b == "on" or b == "off") then
setSetting("voice.spawnGreet", b == "on")
say("Greetings at spawn " .. (b == "on" and "ON" or "OFF"))
elseif a == "voice" then
local p = V.preset and V.preset(words[4])
if not p then
local names = {}
for _, x in ipairs(V.PRESETS or {}) do names[#names + 1] = x.name end
say("Voices: " .. table.concat(names, ", ") .. " - now: " .. tostring(cfg("spawnVoice", "bright")))
return
end
setSetting("voice.spawnVoice", p.name)
SP.say("This is my spawn voice now. " .. p.what .. ".", true)
say("Spawn voice: " .. p.name)
elseif a == "volume" and tonumber(words[4]) then
setSetting("voice.spawnVolume", math.max(0, math.min(3, tonumber(words[4]))))
say("Spawn volume " .. cfg("spawnVolume", 2) .. " (0-3)")
elseif a == "say" then
local t = table.concat(words, " ", 4)
if t == "" then t = "Hello spawn! This is a test." end
if not SP.ready() then say("Not ready: " .. SP.status()[1]) return end
SP.say(t, true)
say("Saying at spawn: " .. t)
elseif a == "wish" then
if b == "on" or b == "off" then setSetting("voice.wish", b == "on")
elseif b == "daily" and tonumber(words[5]) then setSetting("voice.wishDaily", math.max(0, math.floor(tonumber(words[5]))))
elseif b == "max" and tonumber(words[5]) then setSetting("voice.wishMax", math.max(1, math.floor(tonumber(words[5]))))
elseif b == "all" and tonumber(words[5]) then setSetting("voice.wishAll", math.max(0, math.floor(tonumber(words[5]))))
elseif (b == "block" or b == "unblock") and words[5] then
local list = {}
for w in low(cfg("wishBlock", "") or ""):gmatch("[^,%s]+") do if w ~= low(words[5]) then list[#list + 1] = w end end
if b == "block" then list[#list + 1] = low(words[5]) end
setSetting("voice.wishBlock", table.concat(list, ","))
end
say("Wishes " .. (cfg("wish", true) == false and "OFF" or "ON") .. ": " .. tostring(cfg("wishDaily", 3)) .. " a player a day, " ..
tostring(cfg("wishAll", 40)) .. " for everybody, up to " .. tostring(cfg("wishMax", 64)) .. " per wish. Never: " ..
(cfg("wishBlock", "") ~= "" and tostring(cfg("wishBlock", "")) or "(only the built-in list)") ..
"  (voice spawn wish on|off|daily <n>|all <n>|max <n>|block <item>|unblock <item>)")
else
say("voice spawn [status|here|at x y z|pair <code>|unpair|name <word>|on|off|range <n>|voice <preset>|volume <0-3>|chatter <min>|greet on|off|say <text>|wish ...]")
end
end
