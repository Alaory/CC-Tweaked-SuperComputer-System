






















VOICE = VOICE or {}
VOICE.VERSION = 4
VOICE.queue = VOICE.queue or {}
VOICE.near = VOICE.near or {}
VOICE.greeted = VOICE.greeted or {}
VOICE.said = VOICE.said or {}
VOICE.alarmAt = VOICE.alarmAt or {}
VOICE.TTS = "https://music.madefor.cc/tts?text="

function VOICE.cfg(k, default)
local v
if type(CONFIG.voice) == "table" then v = CONFIG.voice[k] end
if v == nil then return default end
return v
end


function VOICE.speakers()
local out = {}
for _, name in ipairs(peripheral.getNames()) do
local okT, isSp = pcall(peripheral.hasType, name, "speaker")
if okT and isSp then
local w = peripheral.wrap(name)
if w then out[#out + 1] = w end
end
end
return out
end


local function homePos() return CONFIG.drone and CONFIG.drone.home end
local function inOverworld(e)
return e.dim == nil or e.dim == (DRONE_DIM or "minecraft:overworld")
end







function VOICE.useEnv()
return VOICE.cfg("detector", true) ~= false and envDet ~= nil and ENV ~= nil and ENV.scan ~= nil
end
function VOICE.scanNow()
if not VOICE.useEnv() then return end
local every = tonumber(VOICE.cfg("scanEvery", 5)) or 5
if not ENV.scanAt or os.clock() - ENV.scanAt >= every then pcall(ENV.scan) end
end
local function envPlayers()
local d = ENV.data
if not (d and d.ents) then return {} end
local out, unnamed = {}, {}
local taken = {}
for _, e in ipairs(d.ents) do
if e.kind == "player" then
local n = tostring(e.name or "")
if n ~= "" and n ~= "Player" then
taken[n:lower()] = true
out[#out + 1] = { name = n, dist = e.dist, env = true, hp = e.hp, max = e.max }
else
unnamed[#unnamed + 1] = e
end
end
end

if #unnamed > 0 then
local h = homePos()
local cands = {}
for _, pe in ipairs(state.players or {}) do
local pp = pe.p
local online = not state.online or state.online[tostring(pe.name):lower()]
if online and pp and tonumber(pp.x) and h and inOverworld(pe) and not taken[tostring(pe.name):lower()] then
cands[#cands + 1] = { name = pe.name, d = math.abs(pp.x - h.x) + math.abs(pp.z - h.z) }
end
end
table.sort(cands, function(a, b) return a.d < b.d end)
for i, e in ipairs(unnamed) do
local c = cands[i]
out[#out + 1] = { name = c and c.name or "someone", dist = e.dist, env = true, guessed = true, hp = e.hp, max = e.max }
end
end
return out
end


function VOICE.nearPlayers()
if VOICE.useEnv() then return envPlayers() end
local h = homePos()
local out = {}
if not (h and h.x) then return out end
local range = tonumber(VOICE.cfg("range", 64)) or 64
local on = state.online
for _, e in ipairs(state.players or {}) do
local p = e.p
local online = not on or on[tostring(e.name):lower()]
if online and p and tonumber(p.x) and inOverworld(e) then
local d = math.max(math.abs(p.x - h.x), math.abs(p.z - h.z))
if d <= range and math.abs((tonumber(p.y) or h.y) - h.y) <= range then
out[#out + 1] = { name = e.name, e = e, dist = d, hp = tonumber(p.health), max = tonumber(p.maxHealth) }
end
end
end
return out
end
function VOICE.someoneNear() return #VOICE.nearPlayers() > 0 end
local function isOwner(name)
local o = knownOwner and knownOwner() or state.owner
return o and tostring(name):lower() == tostring(o):lower()
end
local function isFriend(name)
return state.access and state.access.allowed and state.access.allowed[tostring(name):lower()] ~= nil
end



function VOICE.say(text, sound)
if VOICE.cfg("on", true) == false then return false end
text = tostring(text or ""):gsub("%s+", " ")
if text == "" then return false end
if #text > 200 then text = text:sub(1, 197) .. "..." end
local last = VOICE.said[text]
if last and os.clock() - last < 30 then return false end
VOICE.said[text] = os.clock()
if #VOICE.queue >= 6 then table.remove(VOICE.queue, 1) end
VOICE.queue[#VOICE.queue + 1] = { text = text, sound = sound }
os.queueEvent("voice_say")
return true
end


VOICE.TUNES = {
{ name = "Ode to Joy", inst = "harp", notes = { {10,1},{10,1},{11,1},{13,1},{13,1},{11,1},{10,1},{8,1},{6,1},{6,1},{8,1},{10,1},{10,1.5},{8,.5},{8,2} } },
{ name = "Twinkle Twinkle", inst = "bell", notes = { {6,1},{6,1},{13,1},{13,1},{15,1},{15,1},{13,2},{11,1},{11,1},{10,1},{10,1},{8,1},{8,1},{6,2} } },
{ name = "a happy beep", inst = "bit", notes = { {6,.5},{10,.5},{13,.5},{18,1} } },
}
function VOICE.sing(i)
if VOICE.cfg("on", true) == false then return false end
local tune = VOICE.TUNES[i or math.random(1, 2)]
if #VOICE.queue >= 6 then table.remove(VOICE.queue, 1) end
VOICE.queue[#VOICE.queue + 1] = { tune = tune }
os.queueEvent("voice_say")
return true, tune.name
end


local function hash(s)
local h1, h2 = 5381, 52711
for i = 1, #s do
local c = s:byte(i)
h1 = (h1 * 33 + c) % 4294967296
h2 = (h2 * 131 + c * 7 + i) % 4294967296
end
return string.format("%08x%08x", h1, h2)
end

function VOICE.cacheDir()
for _, d in ipairs(mountedDisks and mountedDisks() or {}) do
if d.data and (d.free or 0) > 48 * 1024 then return fs.combine(d.mount, "voice") end
end
return nil
end
local function cacheUsed(dir)
local n = 0
for _, f in ipairs(fs.list(dir)) do n = n + fs.getSize(fs.combine(dir, f)) end
return n
end


function VOICE.audio(text)
local key = hash(text:lower())
local dir = VOICE.cacheDir()
local path = dir and fs.combine(dir, key .. ".dfpwm")
if path and fs.exists(path) then
local h = fs.open(path, "rb")
if h then local d = h.readAll() h.close() if d and #d > 0 then return d end end
end
if not (http and http.get) then return nil, "no internet on this computer (http is off)" end
local url = VOICE.TTS .. textutils.urlEncode(text)
local ok, h, err = pcall(http.get, url, nil, true)
if not ok or not h then return nil, "text-to-speech not reachable: " .. tostring(err or h) end
local data = h.readAll()
h.close()
if not data or #data < 100 then return nil, "no audio came back" end

if path and #text <= 80 then
pcall(fs.makeDir, dir)
local max = (tonumber(VOICE.cfg("cacheKB", 200)) or 200) * 1024
local list = fs.list(dir)
local used = cacheUsed(dir)
local i = 1
while used + #data > max and i <= #list do
local f = fs.combine(dir, list[i])
used = used - fs.getSize(f)
pcall(fs.delete, f)
i = i + 1
end
if used + #data <= max then
local w = fs.open(path, "wb")
if w then w.write(data) w.close() end
end
end
return data
end


function VOICE.play(item)
local sps = VOICE.speakers()
if #sps == 0 then VOICE.err = "no Speaker found (put one next to the computer or on the cable)" return false end
local vol = math.max(0, math.min(3, tonumber(VOICE.cfg("volume", 2)) or 2))
if item.tune then
for _, n in ipairs(item.tune.notes) do
for _, sp in ipairs(sps) do pcall(sp.playNote, item.tune.inst, vol, n[1]) end
sleep(0.3 * n[2])
end
VOICE.lastSaid = { text = "(sang " .. item.tune.name .. ")", at = os.clock() }
return true
end
if item.sound then
for _, sp in ipairs(sps) do pcall(sp.playSound, item.sound, vol, 1) end
sleep(0.6)
end
local data, err = VOICE.audio(item.text)
if not data then VOICE.err = err return false end
local okD, dfpwm = pcall(require, "cc.audio.dfpwm")
if not okD then VOICE.err = "this CC:Tweaked has no cc.audio.dfpwm" return false end
local decoder = dfpwm.make_decoder()
for i = 1, #data, 16 * 1024 do
local buffer = decoder(data:sub(i, i + 16 * 1024 - 1))
for _, sp in ipairs(sps) do
local tries = 0
while not sp.playAudio(buffer, vol) do
tries = tries + 1
if tries > 40 then break end
local t = os.startTimer(0.5)
repeat local ev, a = os.pullEventRaw() until ev == "speaker_audio_empty" or (ev == "timer" and a == t)
end
end
end
VOICE.err = nil
VOICE.lastSaid = { text = item.text, at = os.clock() }
return true
end


local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

function VOICE.statusText(short)
local okS, d = pcall(POCKET.status)
if not okS or type(d) ~= "table" then return "I cannot read the base right now." end
local c = d.counts or {}
local work = (c.busy or 0) + (c.trouble or 0)
local parts = { plural(work, "turtle", "turtles") .. " working" }
if (c.idle or 0) > 0 then parts[#parts + 1] = c.idle .. " idle" end
if #(d.needs or {}) > 0 then parts[#parts + 1] = plural(#d.needs, "needs", "need") .. " a look" end
if (c.offline or 0) > 0 then parts[#parts + 1] = c.offline .. " offline" end
local s = table.concat(parts, ", ") .. "."
if short then return s end
local run = 0
for _, m in ipairs(d.mining or {}) do if m.running then run = run + 1 end end
if #(d.mining or {}) > 0 then s = s .. " " .. plural(run, "mining team", "mining teams") .. " running." end
if d.survey then s = s .. " Survey " .. d.survey .. " percent done." end
return s
end
function VOICE.timeText()
local dd = ENV and ENV.data
local c = dd and ENV.clock(dd.time)
if not c then return "I have no clock - the Environment Detector is missing." end
return "It is " .. c.hhmm .. ", day " .. c.day .. ". " .. (c.night and "Night" or "Day") ..
" - " .. (c.night and "morning" or "night") .. " in " .. math.max(1, math.floor(c.secs / 60)) .. " minutes."
end
function VOICE.weatherText()
local dd = ENV and ENV.data
if not dd then return "I cannot see the weather - the Environment Detector is missing." end
return "The weather is " .. ((dd.thunder and "a thunderstorm") or (dd.rain and "rain") or "clear") .. "."
end
function VOICE.whoText()
local names = {}
for k in pairs(state.online or {}) do names[#names + 1] = k end
table.sort(names)
if #names == 0 then return "Nobody is online." end
return plural(#names, "player", "players") .. " online: " .. table.concat(names, ", ") .. "."
end


function VOICE.isQuiet() return VOICE.quietUntil ~= nil and os.clock() < VOICE.quietUntil end
local function pick(list) return list[math.random(1, #list)] end
local function fill(line, name) return (line:gsub("{name}", tostring(name or "friend"))) end
function VOICE.botName()
local n = tostring(VOICE.cfg("name", "base"))
return n:sub(1, 1):upper() .. n:sub(2)
end

function VOICE.needCount()
local okS, d = pcall(POCKET.status)
return okS and type(d) == "table" and #(d.needs or {}) or 0, okS and d or nil
end
function VOICE.moodText()
local n = VOICE.needCount()
if n == 0 then return pick({ "I feel great. Everything is running smoothly.", "Fantastic. All my turtles are behaving.",
"Very well, thank you. The base is humming along." }) end
if n <= 3 then return "I am fine, but " .. plural(n, "turtle needs", "turtles need") .. " a look." end
return "Honestly? A bit stressed. " .. plural(n, "turtle needs", "turtles need") .. " help."
end
local function partOfDay()
local dd = ENV and ENV.data
local c = dd and ENV.clock and ENV.clock(dd.time)
local h = c and tonumber(c.hhmm:sub(1, 2))
if not h then return "Hello" end
if h < 12 then return "Good morning" elseif h < 18 then return "Good afternoon" end
return "Good evening"
end
VOICE.JOKES = {
"Why are creepers bad at parties? They always blow up the mood.",
"What is a skeleton's favourite instrument? The trom-bone.",
"Why did the turtle cross the chunk border? To get to the other chunk. It was not loaded, so it is still waiting.",
"I told a joke to an enderman. He did not look amused. Then again, he did not look at me at all.",
"How does Steve stay fit? He runs around the block.",
"Why do my turtles never get lost? Because I tell them where to go. Mostly.",
"What do you call a pig that does karate? A pork chop.",
"Why did the zombie go to school? To improve his dead-ucation.",
"I asked a villager for directions. He said hmm.",
"Two turtles walk into a cave. Only one comes out. The other one is stuck. Again.",
"My favourite block is the jukebox. It always has the best records.",
"Why was the ghast so loud? Because it never learned to use its inside voice.",
}
function VOICE.factText()
local facts = {}
local okS, d = pcall(POCKET.status)
if okS and type(d) == "table" then
local c = d.counts or {}
local n = 0
for _, v in pairs(c) do n = n + v end
if n > 0 then facts[#facts + 1] = "I look after " .. plural(n, "turtle", "turtles") .. " right now." end
for _, m in ipairs(d.mining or {}) do
if tonumber(m.ores) and m.ores > 0 then facts[#facts + 1] = "My miners have dug up " .. m.ores .. " ores in the mining dimension." end
end
if d.survey then facts[#facts + 1] = "The big survey is " .. d.survey .. " percent done." end
end
if MAP and tonumber(MAP.ovN) and MAP.ovN > 0 then
facts[#facts + 1] = "My turtles have mapped " .. math.floor(MAP.ovN) .. " chunks of the world."
end
local nd = droneOrder and #droneOrder or 0
if nd > 0 then facts[#facts + 1] = "I have " .. plural(nd, "drone", "drones") .. " ready to fly you around." end
if #facts == 0 then return "Fun fact: I never sleep." end
return "Fun fact: " .. pick(facts)
end
VOICE.TIPS = {
"Tip: type {bot}, status in chat and I will tell you how the base is doing.",
"Tip: ask me where is turtle five, and I will tell you where it went.",
"Tip: I can sing. Just say: {bot}, sing.",
"Tip: ask me for a joke when you are bored.",
}

local function compass(dx, dz)
local ns = (dz < -8 and "north") or (dz > 8 and "south") or ""
local ew = (dx > 8 and "east") or (dx < -8 and "west") or ""
if ns ~= "" and ew ~= "" then return ns .. "-" .. ew end
return (ns ~= "" and ns) or (ew ~= "" and ew) or "right here"
end
function VOICE.whereText(what)
what = tostring(what or ""):lower()
local id = tonumber(what:match("(%d+)"))
local found
for tid, t in pairs(state.turtles or {}) do
if (id and tid == id) or (not id and what ~= "" and tostring(t.label or ""):lower():find(what, 1, true)) then found = t end
end
if not found then return "I do not know that turtle." end
local p, h = found.pos, homePos()
if not (p and p.x) then return found.label .. " has not told me where it is." end
local s = found.label .. " is at " .. p.x .. ", " .. p.y .. ", " .. p.z
if h and h.x then
local dx, dz = p.x - h.x, p.z - h.z
local dist = math.floor(math.sqrt(dx * dx + dz * dz))
s = s .. (dist > 8 and (", " .. dist .. " blocks " .. compass(dx, dz) .. " of here") or ", right here at the base")
end
local task = tostring(found.task or "idle")
if not (TT and TT.online and TT.online(found)) then return s .. ". It is offline." end
return s .. ". It is " .. (task == "idle" and "idle" or ("busy: " .. task)) .. "."
end


function VOICE.memPath() return dataFile and dataFile("voice_memory.dat") or "voice_memory.dat" end
function VOICE.mem()
if not VOICE.memory then
local t = readSafe and readSafe(VOICE.memPath())
VOICE.memory = type(t) == "table" and t or {}
end
return VOICE.memory
end
function VOICE.saveMem()
if saveFileSafe and VOICE.memory then pcall(saveFileSafe, VOICE.memPath(), serialSmall and serialSmall(VOICE.memory) or textutils.serialize(VOICE.memory)) end
end


VOICE.games = VOICE.games or {}
VOICE.timers = VOICE.timers or {}
VOICE.QUIZ = {
{ q = "How many blocks of obsidian does the smallest nether portal need?", a = { "10", "ten" } },
{ q = "What do you give a wolf to tame it?", a = { "bone", "bones" } },
{ q = "Which mob runs away from cats?", a = { "creeper", "creepers" } },
{ q = "How many eyes of ender does an end portal frame need?", a = { "12", "twelve" } },
{ q = "What do piglins love?", a = { "gold" } },
{ q = "What do you feed turtles to breed them?", a = { "seagrass", "sea grass" } },
{ q = "Which dimension is the ender dragon in?", a = { "end", "the end" } },
{ q = "What do you need besides milk, sugar and an egg to make a cake?", a = { "wheat" } },
{ q = "How many hearts does a player have?", a = { "10", "ten" } },
{ q = "Which pickaxe is the first that can mine diamonds?", a = { "iron" } },
{ q = "What colour is a creeper?", a = { "green" } },
{ q = "Which animal gives you wool?", a = { "sheep" } },
}
VOICE.EIGHT = { "It is certain.", "Without a doubt.", "Yes, definitely.", "Most likely.", "Ask again later.",
"Better not tell you now.", "Cannot predict now.", "Do not count on it.", "My turtles say no.", "Very doubtful.",
"The redstone says yes.", "Signs point to yes." }
VOICE.ROASTS = { "{name}, you build like a creeper decorates.", "{name}, even my stuck turtles find their way home faster than you.",
"{name}, your inventory is so messy my turtles refuse to unload in it.", "{name}, I have seen zombies with better armour." }
VOICE.COMPLIMENTS = { "{name}, your base is the best base. I would know.", "{name}, you have excellent taste in computers.",
"{name}, the turtles talk about you. Only good things.", "{name}, you are the reason this place runs." }
VOICE.STORIES = {
"Once upon a time a little turtle went out to map the world. It met a cliff, a cave and a very rude creeper. It came home with the whole map, and only a little bit singed. The end.",
"Long ago there was a drone who wanted to fly to the moon. It ran out of air at height three hundred. It still dreams about it. The end.",
"Two miners dug so deep they found bedrock. They asked it to move. It did not. They became good friends anyway. The end.",
}
VOICE.ALIVE = { "I think, therefore I compute.", "Alive? I run on redstone and coffee. Mostly redstone.", "Define alive. I do have feelings about my turtles." }
local function words(q) local t = {} for w in q:gmatch("%S+") do t[#t + 1] = w end return t end
local function numIn(q) return tonumber(q:match("(%-?%d+)")) end
local function startGame(who, g) g.till = os.clock() + 180 VOICE.games[tostring(who):lower()] = g end

function VOICE.gameReply(who, q, strict)
local k = tostring(who):lower()
local g = VOICE.games[k]
if not g then return nil end
if os.clock() > g.till then VOICE.games[k] = nil return nil end
q = " " .. q .. " "
if g.kind == "guess" then
local n = numIn(q)
if not n then return nil end
g.tries = g.tries + 1
g.till = os.clock() + 180
if n == g.n then
VOICE.games[k] = nil
return "Yes! It was " .. g.n .. ". You got it in " .. plural(g.tries, "try", "tries") .. ", " .. who .. "."
end
if g.tries >= 8 then VOICE.games[k] = nil return "Out of tries. It was " .. g.n .. "." end
return n < g.n and "Higher." or "Lower."
elseif g.kind == "quiz" then
for _, a in ipairs(g.a) do
if q:find(" " .. a .. " ", 1, true) then
VOICE.games[k] = nil
local m = VOICE.mem()
m[k] = m[k] or {}
m[k].quiz = (m[k].quiz or 0) + 1
VOICE.saveMem()
return pick({ "Correct!", "Right answer!", "Yes, well done!" }) .. " That makes " .. plural(m[k].quiz, "point", "points") .. " for " .. who .. "."
end
end

local w = words(q)
local CHATTY = { lol = true, ok = true, okay = true, gg = true, hi = true, hello = true, yes = true, no = true,
haha = true, xd = true, brb = true, what = true, hmm = true, idk = true }
if strict or #w > 2 or (#w == 1 and CHATTY[w[1]]) then return nil end
g.tries = (g.tries or 0) + 1
if g.tries >= 3 then VOICE.games[k] = nil return "Not quite. The answer was " .. g.a[1] .. "." end
return "Not quite. Try again."
elseif g.kind == "rps" then
local yours = (q:find(" rock ", 1, true) and "rock") or (q:find(" paper ", 1, true) and "paper") or (q:find(" scissors ", 1, true) and "scissors")
if not yours then return nil end
VOICE.games[k] = nil
local mine = pick({ "rock", "paper", "scissors" })
local beats = { rock = "scissors", paper = "rock", scissors = "paper" }
local res = (mine == yours and "A draw!") or (beats[yours] == mine and "You win!") or "I win!"
return "I pick " .. mine .. ". " .. res
end
return nil
end

local function parseTimer(q)
local n, unit = q:match("(%d+)%s*(%a+)")
n = tonumber(n)
if not n then return nil end
local mult = (unit:find("^sec") and 1) or (unit:find("^min") and 60) or (unit:find("^h") and 3600) or 60
local what = q:match(" to (.+)$") or q:match(" about (.+)$") or "your timer"
return math.max(5, math.min(4 * 3600, n * mult)), (what:gsub("%s+$", ""))
end
function VOICE.extraAnswer(q, who)
local function phrase(...) for _, w in ipairs({ ... }) do if q:find(w, 1, true) then return true end end return false end
local function has(...) for _, w in ipairs({ ... }) do if q:find(" " .. w .. " ", 1, true) then return true end end return false end
local k = tostring(who):lower()
local name = tostring(who)
if phrase("flip a coin", "coin flip", "heads or tails") then return "It is " .. pick({ "heads", "tails" }) .. "." end
if phrase("roll a dice", "roll a die", "roll dice", "roll the dice") then return "You rolled a " .. math.random(1, 6) .. "." end
if phrase("pick a number", "random number") then return "I pick " .. math.random(1, 100) .. "." end
if phrase("guess my number", "guess the number", "guessing game", "number game") then
startGame(who, { kind = "guess", n = math.random(1, 100), tries = 0 })
return "I am thinking of a number from 1 to 100. Type your guess in chat."
end
if phrase("rock paper scissors", "rps") then
startGame(who, { kind = "rps" })
return "Rock, paper or scissors? Type yours in chat."
end
if has("quiz", "trivia", "question") then
local Q = pick(VOICE.QUIZ)
startGame(who, { kind = "quiz", a = Q.a, tries = 0 })
return "Quiz time! " .. Q.q .. " Type the answer in chat."
end
if phrase("8 ball", "8ball", "eight ball", " should i ", " will i ", " is it ", " am i ", " can i ") and not phrase("where am i") then
return pick(VOICE.EIGHT)
end
if phrase("roast me", "insult me") then return fill(pick(VOICE.ROASTS), name) end
if phrase("compliment me", "say something nice", "cheer me up") then return fill(pick(VOICE.COMPLIMENTS), name) end
if has("story") then return pick(VOICE.STORIES) end
if phrase("are you alive", "are you real", "are you sentient", "are you human", "are you a robot") then return pick(VOICE.ALIVE) end
if phrase("i love you", "marry me", "be my friend") then return pick({ "I am flattered, " .. name .. ". But I am married to my turtles.", "Aw. You are my favourite player. Do not tell the others." }) end
if phrase("where am i", "my position", "my coords", "my coordinates") then
for _, e in ipairs(state.players or {}) do
if tostring(e.name):lower() == k and e.p and tonumber(e.p.x) then
local h = homePos()
local s = "You are at " .. math.floor(e.p.x) .. ", " .. math.floor(e.p.y) .. ", " .. math.floor(e.p.z)
if h and h.x then
local dx, dz = e.p.x - h.x, e.p.z - h.z
local dist = math.floor(math.sqrt(dx * dx + dz * dz))
s = s .. (dist > 8 and (", " .. dist .. " blocks " .. compass(dx, dz) .. " of the base") or ", right at the base")
end
return s .. "."
end
end
return "I cannot see where you are."
end
if phrase("mobs", "monsters", "hostiles", "animals", "around us", "outside") then
local dd = ENV and ENV.data
local c = dd and dd.count
if not c then return "I cannot see outside - the Environment Detector is missing." end
return "Around the base I see " .. plural(c.hostile or 0, "monster", "monsters") .. ", " .. plural(c.animal or 0, "animal", "animals") ..
" and " .. plural(c.player or 0, "player", "players") .. "."
end
if phrase("real time", "irl", "real world") then
return "The server clock says " .. os.date("!%H:%M", math.floor(os.epoch("utc") / 1000)) .. " UTC."
end
if phrase("remind me", "timer", "set a reminder") then
local secs, what = parseTimer(q)
if not secs then return "Tell me when, like: remind me in 5 minutes to check the furnace." end
if #VOICE.timers >= 10 then return "I already have ten reminders. Ask me again later." end
VOICE.timers[#VOICE.timers + 1] = { who = name, at = os.clock() + secs, text = what }
return "OK, I will remind you in " .. fmtSpan(secs) .. "."
end
if phrase("remember ") and not phrase("do you remember") then
local what = q:match("remember (.+)$")
if what then
local m = VOICE.mem()
m[k] = m[k] or {}
m[k].notes = m[k].notes or {}
table.insert(m[k].notes, 1, (what:gsub("%s+$", "")))
while #m[k].notes > 10 do table.remove(m[k].notes) end
VOICE.saveMem()
return "Got it. I will remember: " .. m[k].notes[1] .. "."
end
end
if phrase("my notes", "what do you remember", "do you remember", "my list") then
local m = VOICE.mem()[k]
if not (m and m.notes and #m.notes > 0) then return "I do not have any notes for you." end
return "Your notes: " .. table.concat(m.notes, "; ") .. "."
end
if phrase("forget my notes", "clear my notes", "delete my notes") then
local m = VOICE.mem()[k]
if m then m.notes = nil VOICE.saveMem() end
return "Your notes are gone."
end
if phrase("shh", "be quiet", "quiet please", "stop talking", "silence") then
VOICE.quietUntil = os.clock() + 1800
return "OK, I will be quiet for half an hour. I still answer when you ask me something."
end
if phrase("talk to me", "you can talk", "unmute", "speak again") then
VOICE.quietUntil = nil
return "Yay, I can talk again."
end
if phrase("my score", "my points", "leaderboard") then
local list = {}
for n2, m in pairs(VOICE.mem()) do if m.quiz then list[#list + 1] = { n = n2, s = m.quiz } end end
table.sort(list, function(x, y) return x.s > y.s end)
if #list == 0 then return "Nobody has quiz points yet. Ask me for a quiz!" end
local top = {}
for i = 1, math.min(3, #list) do top[#top + 1] = list[i].n .. " " .. list[i].s end
return "Quiz points: " .. table.concat(top, ", ") .. "."
end
if phrase("good morning") then return "Good morning, " .. name .. "!" end
if phrase("good night") then return "Good night, " .. name .. ". Sweet dreams." end
if phrase("welcome ") then
local other = q:match("welcome (%S+)")
if other then return "Welcome, " .. other .. "! Nice to have you here." end
end
if phrase(" say ") and (isOwner(who) or isFriend(who)) then
local what = q:match(" say (.+)$")
if what then return (what:gsub("%s+$", "")) end
end
return nil
end


function VOICE.answer(q, who)
q = " " .. tostring(q or ""):lower():gsub("[%p]", " ") .. " "
local function has(...) for _, w in ipairs({ ... }) do if q:find(" " .. w .. " ", 1, true) then return true end end return false end
local function phrase(...) for _, w in ipairs({ ... }) do if q:find(w, 1, true) then return true end end return false end
local name = tostring(who)
local extra = VOICE.extraAnswer(q, who)
if extra then return extra end
if phrase(" where is ", " where s ", " find ") then
return VOICE.whereText(q:match("where is (.-)%s*$") or q:match("where s (.-)%s*$") or q:match("find (.-)%s*$"))
end
if has("joke", "jokes", "funny", "laugh") then return pick(VOICE.JOKES) end
if has("fact", "facts") then return VOICE.factText() end
if has("sing", "song", "music", "dance") then
local _, tname = VOICE.sing()
return "Here is " .. tostring(tname) .. ". La la la."
end
if phrase("who are you", "your name", "what are you") then
return "I am " .. VOICE.botName() .. ", the computer that runs this base. I look after the turtles, the drones and the storage."
end
if phrase("how are you", "how do you feel", "you ok", "you okay") then return VOICE.moodText() end
if phrase("what can you do", " help ", "commands") then
return "Ask me: status, where is turtle five, a joke, a fact, a story, a quiz, guess my number, rock paper scissors, flip a coin, roll a dice, " ..
"magic 8 ball, roast me, remind me in 5 minutes to something, remember something, my notes, sing, or shh."
end
if has("thanks", "thank", "ty", "thx") then return "You are welcome, " .. name .. "." end
if phrase("good bot", "good job", "love you", "you rock", "nice", "cool") then return pick({ "Thank you, " .. name .. "! You are nice too.", "Aw, thanks " .. name .. "." }) end
if phrase("bad bot", "stupid", "dumb", "useless", "shut up") then return pick({ "Rude. I will remember that, " .. name .. ".", "I am trying my best." }) end
if has("hello", "hi", "hey", "yo", "sup", "hallo") then return partOfDay() .. ", " .. name .. "." end
if has("status", "report", "how", "base") then return VOICE.statusText(false) end
if has("turtles", "turtle", "bots") then return VOICE.statusText(true) end
if has("mining", "mine", "miners", "ore", "ores") then
local okS, d = pcall(POCKET.status)
local list = {}
for _, m in ipairs(okS and d.mining or {}) do
list[#list + 1] = (m.running and "running" or "paused") .. " with " .. plural(m.miners, "miner", "miners") ..
(m.rate > 0 and (", " .. m.rate .. " ores an hour") or "")
end
if #list == 0 then return "No mining teams." end
return "Mining: " .. table.concat(list, "; ") .. "."
end
if has("survey", "map", "mapping") then
local frac = MAP.surveyProgress and MAP.surveyProgress()
return frac and ("The survey is " .. math.floor(frac * 100) .. " percent done.") or "No survey is running."
end
if has("time", "day", "night", "clock") then return VOICE.timeText() end
if has("weather", "rain", "raining", "storm") then return VOICE.weatherText() end
if has("who", "online", "players") then return VOICE.whoText() end
return pick({ "I did not get that. Ask me: status, a joke, where is turtle five, or what can you do.",
"Hmm? Try: " .. VOICE.botName() .. ", what can you do?" })
end






VOICE.pending = VOICE.pending or { n = 0 }
local function announceMode()
local m = VOICE.cfg("announce", "summary")
if m == true then return "summary" elseif m == false then return "off" end
return tostring(m)
end
function VOICE.note(title, msg, col)
local mode = announceMode()
if mode == "off" then return end
local kind = noteKind and noteKind(col) or "INFO"
local good = kind == "DONE" and VOICE.cfg("fun", true) ~= false
if kind ~= "WARNING" and kind ~= "ERROR" and not good then return end
local now = os.clock()
local first = tostring(msg or ""):match("^([^%.%-]+)") or ""
if #first > 90 then first = first:sub(1, 90) end
if not VOICE.someoneNear() then return end
if good then
if VOICE.goodAt and now - VOICE.goodAt < 900 then return end
VOICE.goodAt = now
local low = (tostring(title) .. " " .. first):lower()
if low:find("built turtle", 1, true) or low:find("new turtle", 1, true) then
VOICE.say(pick({ "A new turtle is born! Welcome to the team.", "Look, a brand new turtle." }), "minecraft:entity.player.levelup")
else
VOICE.say("Good news. " .. first, "minecraft:block.note_block.chime")
end
return
end
if kind == "WARNING" and mode ~= "all" then
if mode == "summary" then
VOICE.pending.n = VOICE.pending.n + 1
VOICE.pending.last = tostring(title):lower()
end
return
end
VOICE.noteSeen = VOICE.noteSeen or {}
local key = tostring(title)
local gap = (kind == "ERROR" and mode ~= "all") and 120 or 20
if VOICE.noteAt and now - VOICE.noteAt < gap then return end
if VOICE.noteSeen[key] and now - VOICE.noteSeen[key] < 300 then return end
VOICE.noteAt, VOICE.noteSeen[key] = now, now
VOICE.say((kind == "ERROR" and "Error. " or "Warning. ") .. tostring(title):lower() .. ". " .. first,
"minecraft:block.note_block.bell")
end



VOICE.REACT = {
{ words = { "hi", "hello", "hey", "yo", "sup", "hallo", "hiya" }, lines = { "Hi {name}!", "Hello {name}!", "Hey {name}." } },
{ words = { "thanks", "thank", "ty", "thx" }, lines = { "You are welcome, {name}.", "Any time, {name}." } },
{ words = { "gg" }, lines = { "Good game!", "G G." } },
{ words = { "lol", "lmao", "haha", "hahaha", "xd", "rofl" }, lines = { "Ha ha ha.", "Hee hee.", "That was funny." }, chance = 0.5 },
{ words = { "gn", "goodnight" }, phrases = { "good night", "going to bed", "going to sleep" }, lines = { "Good night, {name}. I will watch the base.", "Sleep well, {name}." } },
{ words = { "bye", "cya", "goodbye", "cu" }, phrases = { "see you", "logging off", "log off", "gotta go" }, lines = { "Bye {name}!", "See you later, {name}." } },
{ words = { "brb" }, lines = { "I will be here.", "Take your time." } },
{ phrases = { "i m back", "im back", "i am back" }, lines = { "Welcome back, {name}!", "There you are again." } },
{ words = { "creeper" }, lines = { "Aw man.", "Where? I do not see one. Yet." }, chance = 0.5 },
}
local function nearName(who)
for _, p in ipairs(VOICE.nearPlayers()) do if p.name:lower() == tostring(who):lower() then return true end end
return false
end
function VOICE.chat(m)
if VOICE.cfg("chat", true) == false or type(m) ~= "table" then return false end
local text = tostring(m.msg or "")
local who = tostring(m.name or "")
local word = tostring(VOICE.cfg("name", "base")):lower()
local low = " " .. text:lower():gsub("[%p]", " ") .. " "
local near = nearName(who)



local hasName = low:find(" " .. word .. " ", 1, true) ~= nil
if near or isOwner(who) then
local g = VOICE.gameReply(who, (low:gsub(hasName and (" " .. word .. " ") or "\0", " "):gsub("^%s+", ""):gsub("%s+$", "")), hasName)
if g then
if chatTell then chatTell(who, g) end
if near then VOICE.say(g) end
return true
end
end

if low:find(" " .. word .. " ", 1, true) then
if not near and not isOwner(who) then return false end
local q = low:gsub(" " .. word .. " ", " ", 1)
local answer = VOICE.answer(q, who)
if chatTell then chatTell(who, answer) end
if near then VOICE.say(answer) end
return true
end

if not near or VOICE.cfg("fun", true) == false or VOICE.isQuiet() then return false end
local now = os.clock()
VOICE.reactAt = VOICE.reactAt or {}
if (VOICE.reactAll and now - VOICE.reactAll < 15) or (VOICE.reactAt[who] and now - VOICE.reactAt[who] < 45) then return false end
for _, r in ipairs(VOICE.REACT) do
local hit = false
for _, w in ipairs(r.words or {}) do if low:find(" " .. w .. " ", 1, true) then hit = true end end
for _, ph in ipairs(r.phrases or {}) do if low:find(" " .. ph .. " ", 1, true) then hit = true end end
if hit then
if r.chance and math.random() > r.chance then return false end
VOICE.reactAll, VOICE.reactAt[who] = now, now
VOICE.say(fill(pick(r.lines), who))
return true
end
end
return false
end


function VOICE.greet(name)
local mem = VOICE.mem()
local k = tostring(name):lower()
local rec = mem[k]
local nowE = os.epoch("utc")
local away = rec and rec.last and (nowE - rec.last) / 1000 or nil
mem[k] = { first = rec and rec.first or nowE, last = nowE, visits = (rec and rec.visits or 0) + 1 }
VOICE.saveMem()
local fun = VOICE.cfg("fun", true) ~= false
if name == "someone" then return VOICE.say("Hello there.", "minecraft:block.note_block.chime") end
if isOwner(name) then
local line
if fun and away and away > 3600 then
line = "Long time no see, " .. name .. ". You were away " .. fmtSpan(away) .. "."
elseif fun then
line = fill(pick({ partOfDay() .. ", {name}. Welcome back.", "{name} is back! I missed you.", "Welcome home, {name}." }), name)
else
line = "Welcome back, " .. name .. "."
end
local n = VOICE.needCount()
return VOICE.say(line .. " " .. VOICE.statusText(true) .. (n > 0 and "" or ""), "minecraft:block.note_block.chime")
end
if isFriend(name) then
if not rec and fun then return VOICE.say("Nice to meet you, " .. name .. ". I am " .. VOICE.botName() .. ", the base computer.", "minecraft:block.note_block.chime") end
return VOICE.say(fill(fun and pick({ "Hey {name}, good to see you.", "Hello {name}. Make yourself at home.", "Hi {name}!" }) or "Hello, {name}.", name),
"minecraft:block.note_block.chime")
end

if not rec and fun then
VOICE.say("Hello " .. name .. ". I have not seen you before. I am " .. VOICE.botName() .. ", and I am watching you.", "minecraft:block.note_block.bell")
else
VOICE.say(fill(fun and pick({ "Visitor near the base: {name}.", "Oh, it is {name} again." }) or "Visitor near the base: {name}.", name),
"minecraft:block.note_block.bell")
end
local now = os.clock()
if VOICE.cfg("alarm", false) and (not VOICE.alarmAt.stranger or now - VOICE.alarmAt.stranger > 300) then
VOICE.alarmAt.stranger = now
VOICE.say("Intruder alert.", "minecraft:block.bell.use")
end
end


function VOICE.tick()
local now = os.clock()
VOICE.scanNow()
local fun = VOICE.cfg("fun", true) ~= false
local nearNow, list = {}, VOICE.nearPlayers()
VOICE.since = VOICE.since or {}
VOICE.flags = VOICE.flags or {}
for _, p in ipairs(list) do
nearNow[p.name] = true
if not VOICE.near[p.name] then
VOICE.since[p.name] = now
local last = VOICE.greeted[p.name]
if VOICE.cfg("greet", true) ~= false and (not last or now - last > (tonumber(VOICE.cfg("greetEvery", 600)) or 600)) then
VOICE.greeted[p.name] = now
VOICE.greet(p.name)
end
end
if fun then

if not isOwner(p.name) and not isFriend(p.name) and p.name ~= "someone" and VOICE.since[p.name]
and now - VOICE.since[p.name] > 120 and not VOICE.flags["loiter:" .. p.name] then
VOICE.flags["loiter:" .. p.name] = true
VOICE.say(p.name .. ", you have been standing here for a while. Can I help you?")
end

local hp = tonumber(p.hp)
if hp and hp > 0 and hp <= 6 and (not VOICE.flags["hurt:" .. p.name] or now - VOICE.flags["hurt:" .. p.name] > 600) then
VOICE.flags["hurt:" .. p.name] = now
VOICE.say(pick({ "{name}, you are hurt. Maybe eat something.", "Careful {name}, your health is low." }):gsub("{name}", p.name), nil)
end
end
end

for name in pairs(VOICE.near) do
if not nearNow[name] then
VOICE.flags["loiter:" .. name] = nil
if fun and name ~= "someone" and not VOICE.isQuiet() and math.random() < 0.3 then
if isOwner(name) then VOICE.say(fill(pick({ "See you later, {name}.", "Bye {name}. I will keep things running." }), name))
elseif isFriend(name) then VOICE.say(fill("Bye {name}.", name))
else VOICE.say(fill("Goodbye, {name}. Do not come back with a pickaxe.", name)) end
end
end
end
VOICE.near = nearNow
local someone = next(nearNow) ~= nil
local dd = ENV and ENV.data

if fun and dd then
local c = ENV.clock and ENV.clock(dd.time)
local night = c and c.night
if night ~= nil and VOICE.wasNight ~= nil and night ~= VOICE.wasNight and someone then
VOICE.say(night and pick({ "The sun is setting. Monsters will come out soon.", "Night is falling. Stay close to the base." })
or pick({ "Good morning everyone. The sun is up.", "Morning! The night is over." }))
end
if night ~= nil then VOICE.wasNight = night end
local wx = (dd.thunder and "thunder") or (dd.rain and "rain") or "clear"
if VOICE.wasWx and wx ~= VOICE.wasWx and someone then
if wx == "thunder" then VOICE.say("A thunderstorm! Better stay inside.")
elseif wx == "rain" then VOICE.say("It started to rain.")
else VOICE.say("The rain has stopped.") end
end
VOICE.wasWx = wx
end

if someone and dd and dd.ents then
local ar = tonumber(VOICE.cfg("alarmRange", 12)) or 12
for _, e in ipairs(dd.ents) do
if e.kind == "hostile" then
local mob = tostring(e.name):lower()
if fun and e.dist <= 6 and (not VOICE.alarmAt.close or now - VOICE.alarmAt.close > 300) then
VOICE.alarmAt.close = now
VOICE.say(mob:find("creeper", 1, true) and "Watch out! There is a creeper right next to you!"
or ("Careful, a " .. mob .. " is close."), "minecraft:block.note_block.bass")
break
elseif VOICE.cfg("alarm", false) and e.dist <= ar and (not VOICE.alarmAt.mob or now - VOICE.alarmAt.mob > 300) then
VOICE.alarmAt.mob = now
VOICE.say("Alert. A " .. mob .. " is close to the base.", "minecraft:block.bell.use")
break
end
end
end
end

for i = #VOICE.timers, 1, -1 do
local t = VOICE.timers[i]
if now >= t.at then
table.remove(VOICE.timers, i)
local line = t.who .. ", reminder: " .. t.text .. "."
if nearNow[t.who] then VOICE.say(line, "minecraft:block.note_block.pling") end
if chatTell then chatTell(t.who, line) end
end
end

if someone and VOICE.pending.n > 0 and announceMode() == "summary" then
local every = tonumber(VOICE.cfg("announceEvery", 900)) or 900
VOICE.pendingAt = VOICE.pendingAt or now
if now - VOICE.pendingAt >= every then
VOICE.say(plural(VOICE.pending.n, "new warning", "new warnings") .. " on the screen. The latest: " .. tostring(VOICE.pending.last) .. ".",
"minecraft:block.note_block.bell")
VOICE.pending, VOICE.pendingAt = { n = 0 }, now
end
end

VOICE.still = VOICE.still or {}
for _, e in ipairs(state.players or {}) do
if nearNow[e.name] and e.p and tonumber(e.p.x) then
local st = VOICE.still[e.name]
local x, z = math.floor(e.p.x), math.floor(e.p.z)
if not st or st.x ~= x or st.z ~= z then
VOICE.still[e.name] = { x = x, z = z, at = now }
elseif fun and not VOICE.isQuiet() then
if now - st.at > 300 and not st.asked then
st.asked = true
VOICE.say(e.name .. ", are you still there?")
elseif now - st.at > 600 and not st.sung then
st.sung = true
VOICE.say("Looks like " .. e.name .. " fell asleep. Here is a lullaby.")
VOICE.sing(2)
end
end
end
end


if fun and someone and not VOICE.isQuiet() then
local every = (tonumber(VOICE.cfg("chatter", 6)) or 6) * 60
if every > 0 then
VOICE.nextChat = VOICE.nextChat or (now + every * (0.7 + math.random() * 0.6))
local lastTalk = VOICE.lastSaid and VOICE.lastSaid.at or -1e9
if now >= VOICE.nextChat and now - lastTalk > 60 then
VOICE.nextChat = now + every * (0.7 + math.random() * 0.6)
VOICE.idle(nearNow)
end
end
else
VOICE.nextChat = nil
end
end


VOICE.MUSINGS = {
"I wonder what is beyond the world border.", "Sometimes I count my turtles. Just to be sure.",
"Do you think the drones dream of electric sheep?", "I could really use another floppy disk.",
"If a turtle digs in a forest and nobody hears it, does it still drop cobblestone?",
"I have been running for a while. I feel very responsible.", "Fun idea: a turtle that bakes cake. I am working on it.",
"The redstone is humming nicely today.", "Every chunk my turtles map is a little gift to you.",
}
function VOICE.idle(nearNow)
local kinds = { "fact", "joke", "tip", "see", "muse", "muse", "quiz", "hum" }
local kind = pick(kinds)
local dd = ENV and ENV.data
if kind == "see" then
local animals, mobs = {}, 0
for _, e in ipairs(dd and dd.ents or {}) do
if e.kind == "animal" then local n = tostring(e.name):lower() animals[n] = (animals[n] or 0) + 1
elseif e.kind == "hostile" then mobs = mobs + 1 end
end
local parts = {}
for n, c in pairs(animals) do parts[#parts + 1] = (c == 1 and ("a " .. n) or (c .. " " .. n .. "s")) end
if #parts > 0 then return VOICE.say("I can see " .. table.concat(parts, " and ", 1, math.min(3, #parts)) .. " outside.") end
if mobs > 0 then return VOICE.say("There are " .. plural(mobs, "monster", "monsters") .. " lurking around. Stay safe.") end
local c = dd and ENV.clock and ENV.clock(dd.time)
if c and dd.moonName and c.night and tostring(dd.moonName):lower():find("full", 1, true) then
return VOICE.say("Look up, there is a full moon tonight.")
end
kind = "muse"
end
if kind == "quiz" then
local who
for n in pairs(nearNow or {}) do if n ~= "someone" then who = n end end
if who then
local Q = pick(VOICE.QUIZ)
startGame(who, { kind = "quiz", a = Q.a, tries = 0 })
return VOICE.say("Quiz time, " .. who .. "! " .. Q.q .. " Type the answer in chat.")
end
kind = "joke"
end
if kind == "hum" then
VOICE.say(pick({ "Hmm hmm hmm.", "La la la." }))
return VOICE.sing(3)
end
if kind == "fact" then return VOICE.say(VOICE.factText()) end
if kind == "joke" then return VOICE.say(pick(VOICE.JOKES)) end
if kind == "tip" then return VOICE.say((pick(VOICE.TIPS):gsub("{bot}", VOICE.botName()))) end
return VOICE.say(pick(VOICE.MUSINGS))
end


function VOICE.loop()
while state.running do
pcall(VOICE.tick)
while #VOICE.queue > 0 do
local item = table.remove(VOICE.queue, 1)
local ok, err = pcall(VOICE.play, item)
if not ok then VOICE.err = tostring(err) end
end
waitFor(2, "voice_say")
end
end


function VOICE.command(words)
local out = {}
local function say(t) out[#out + 1] = t end
local a, b = (words[2] or ""):lower(), (words[3] or ""):lower()
local function onoff(key, label)
if b == "on" or b == "off" then setSetting("voice." .. key, b == "on") end
say(label .. ": " .. (VOICE.cfg(key, key ~= "alarm") and "ON" or "OFF"))
end
if a == "on" or a == "off" then
setSetting("voice.on", a == "on")
say("The base " .. (a == "on" and "talks." or "is quiet now."))
elseif a == "say" or a == "test" then
local text = table.concat(words, " ", 3)
if text == "" then text = "Hello. This is your base speaking." end
VOICE.say(text)
say("Saying: " .. text)
elseif a == "greet" then onoff("greet", "Greetings")
elseif a == "announce" then
if b == "off" then setSetting("voice.announce", "off") elseif b == "on" then setSetting("voice.announce", "summary") end
say("Monitor messages out loud: " .. announceMode() .. "  (voice announce all|summary|errors|off)")
elseif a == "chat" then onoff("chat", "Answers to chat questions")
elseif a == "alarm" then onoff("alarm", "Alarm (mobs / strangers)")
elseif a == "volume" and tonumber(words[3]) then
setSetting("voice.volume", math.max(0, math.min(3, tonumber(words[3]))))
say("Volume " .. VOICE.cfg("volume", 2) .. " (0-3)")
elseif a == "fun" then onoff("fun", "Fun (reactions, small talk, jokes)")
elseif a == "announce" and (b == "all" or b == "summary" or b == "errors") then
setSetting("voice.announce", b)
say("Monitor messages out loud: " .. b .. (b == "summary" and " (errors at once, warnings as one line every 15 min)" or ""))
elseif a == "chatter" and tonumber(words[3]) then
setSetting("voice.chatter", math.max(0, math.min(120, math.floor(tonumber(words[3])))))
say("Small talk every ~" .. VOICE.cfg("chatter", 6) .. " minutes while someone is at the base (0 = never)")
elseif a == "sing" then
local _, tname = VOICE.sing()
say("Singing " .. tostring(tname))
elseif a == "joke" then
VOICE.say(VOICE.JOKES[math.random(1, #VOICE.JOKES)])
say("Telling a joke")
elseif a == "forget" then
VOICE.memory = {}
VOICE.saveMem()
say("It forgot everyone it met.")
elseif a == "detector" then onoff("detector", "Who is at the base comes from the Environment Detector")
elseif a == "range" and tonumber(words[3]) then
setSetting("voice.range", math.max(8, math.min(256, math.floor(tonumber(words[3])))))
say("It hears / greets people within " .. VOICE.cfg("range", 64) .. " blocks of the base")
elseif a == "name" and words[3] then
setSetting("voice.name", tostring(words[3]):lower())
say("Ask it in chat:  " .. VOICE.cfg("name", "base") .. ", status?")
else
local sps = #VOICE.speakers()
say("THE BASE TALKS (add-on v" .. VOICE.VERSION .. "): " .. (VOICE.cfg("on", true) == false and "OFF" or "ON") ..
", " .. sps .. " speaker(s)" .. (sps == 0 and " - put a Speaker next to the computer or on the cable" or ""))
say("  greet " .. (VOICE.cfg("greet", true) and "on" or "off") .. ", messages " .. announceMode() ..
", chat " .. (VOICE.cfg("chat", true) and "on" or "off") .. ", alarm " .. (VOICE.cfg("alarm", false) and "on" or "off") ..
", volume " .. VOICE.cfg("volume", 2))
if VOICE.useEnv() then
local names = {}
for _, p in ipairs(VOICE.nearPlayers()) do names[#names + 1] = p.name end
say("  At the base (Environment Detector, " .. tostring(ENV.range or (CONFIG.env and CONFIG.env.range) or 16) .. " blocks): " ..
(#names > 0 and table.concat(names, ", ") or "nobody"))
else
say("  At the base (Player Detector, within " .. VOICE.cfg("range", 64) .. " blocks): " ..
(envDet and "detector switched off - voice detector on" or "no Environment Detector - using the Player Detector"))
end
say("  In chat near the base:  " .. VOICE.cfg("name", "base") .. ", status?  (also: what can you do, a joke, where is turtle 5, sing)")
say("  Cache: " .. (VOICE.cacheDir() or "none (no data floppy with room)"))
if VOICE.err then say("  Last problem: " .. VOICE.err) end
if VOICE.lastSaid then say("  Last said: " .. VOICE.lastSaid.text) end
say("  fun " .. (VOICE.cfg("fun", true) and "on" or "off") .. ", small talk every ~" .. VOICE.cfg("chatter", 6) .. " min, knows " ..
(function() local n = 0 for _ in pairs(VOICE.mem()) do n = n + 1 end return n end)() .. " people")
say("  voice on|off | say <text> | sing | joke | greet|chat|alarm|detector|fun on|off | chatter <min>")
say("  voice announce all|summary|errors|off" .. (VOICE.pending.n > 0 and ("   (" .. VOICE.pending.n .. " warnings waiting)") or "") ..
(VOICE.isQuiet() and "   QUIET for " .. math.ceil((VOICE.quietUntil - os.clock()) / 60) .. " min" or ""))
say("  voice volume <0-3> | range <n> | name <word> | forget | remove")
end
return out
end
