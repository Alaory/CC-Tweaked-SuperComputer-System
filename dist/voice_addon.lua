




















VOICE = VOICE or {}
VOICE.VERSION = 1
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

function VOICE.nearPlayers()
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
if d <= range and math.abs((tonumber(p.y) or h.y) - h.y) <= range then out[#out + 1] = { name = e.name, e = e, dist = d } end
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

function VOICE.answer(q, who)
q = " " .. tostring(q or ""):lower():gsub("[%p]", " ") .. " "
local function has(...) for _, w in ipairs({ ... }) do if q:find(" " .. w .. " ", 1, true) then return true end end return false end
if has("hello", "hi", "hey", "yo") then return "Hello " .. tostring(who) .. "." end
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
return "Ask me: status, turtles, mining, survey, time, weather, or who is online."
end



function VOICE.note(title, msg, col)
if VOICE.cfg("announce", true) == false then return end
local kind = noteKind and noteKind(col) or "INFO"
if kind ~= "WARNING" and kind ~= "ERROR" then return end
if not VOICE.someoneNear() then return end
local now = os.clock()
if VOICE.noteAt and now - VOICE.noteAt < 20 then return end
VOICE.noteSeen = VOICE.noteSeen or {}
local key = tostring(title)
if VOICE.noteSeen[key] and now - VOICE.noteSeen[key] < 300 then return end
VOICE.noteAt, VOICE.noteSeen[key] = now, now
local first = tostring(msg or ""):match("^([^%.%-]+)") or ""
if #first > 90 then first = first:sub(1, 90) end
VOICE.say((kind == "ERROR" and "Error. " or "Warning. ") .. tostring(title):lower() .. ". " .. first,
"minecraft:block.note_block.bell")
end


function VOICE.chat(m)
if VOICE.cfg("chat", true) == false or type(m) ~= "table" then return false end
local text = tostring(m.msg or "")
local word = tostring(VOICE.cfg("name", "base")):lower()
local low = text:lower()
if low:sub(1, #word) ~= word then return false end
local rest = text:sub(#word + 1)
if rest ~= "" and not rest:match("^[%s,:!%?]") then return false end
local who = tostring(m.name or "")
local near = false
for _, p in ipairs(VOICE.nearPlayers()) do if p.name:lower() == who:lower() then near = true end end
if not near and not isOwner(who) then return false end
local answer = VOICE.answer(rest, who)
if chatTell then chatTell(who, answer) end
if near then VOICE.say(answer) end
return true
end


function VOICE.tick()
local now = os.clock()
local nearNow = {}
for _, p in ipairs(VOICE.nearPlayers()) do
nearNow[p.name] = true
if not VOICE.near[p.name] and VOICE.cfg("greet", true) ~= false then
local last = VOICE.greeted[p.name]
if not last or now - last > (tonumber(VOICE.cfg("greetEvery", 600)) or 600) then
VOICE.greeted[p.name] = now
if isOwner(p.name) then
VOICE.say("Welcome back, " .. p.name .. ". " .. VOICE.statusText(true), "minecraft:block.note_block.chime")
elseif isFriend(p.name) then
VOICE.say("Hello, " .. p.name .. ".", "minecraft:block.note_block.chime")
else
VOICE.say("Visitor near the base: " .. p.name .. ".", "minecraft:block.note_block.bell")
if VOICE.cfg("alarm", false) and (not VOICE.alarmAt.stranger or now - VOICE.alarmAt.stranger > 300) then
VOICE.alarmAt.stranger = now
VOICE.say("Intruder alert.", "minecraft:block.bell.use")
end
end
end
end
end
VOICE.near = nearNow

if VOICE.cfg("alarm", false) and next(nearNow) and ENV and ENV.data and ENV.data.ents then
local r = tonumber(VOICE.cfg("alarmRange", 12)) or 12
for _, e in ipairs(ENV.data.ents) do
if e.kind == "hostile" and e.dist <= r and (not VOICE.alarmAt.mob or now - VOICE.alarmAt.mob > 300) then
VOICE.alarmAt.mob = now
VOICE.say("Alert. A " .. tostring(e.name):lower() .. " is close to the base.", "minecraft:block.bell.use")
break
end
end
end
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
elseif a == "announce" then onoff("announce", "Warnings out loud")
elseif a == "chat" then onoff("chat", "Answers to chat questions")
elseif a == "alarm" then onoff("alarm", "Alarm (mobs / strangers)")
elseif a == "volume" and tonumber(words[3]) then
setSetting("voice.volume", math.max(0, math.min(3, tonumber(words[3]))))
say("Volume " .. VOICE.cfg("volume", 2) .. " (0-3)")
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
say("  greet " .. (VOICE.cfg("greet", true) and "on" or "off") .. ", warnings " .. (VOICE.cfg("announce", true) and "on" or "off") ..
", chat " .. (VOICE.cfg("chat", true) and "on" or "off") .. ", alarm " .. (VOICE.cfg("alarm", false) and "on" or "off") ..
", volume " .. VOICE.cfg("volume", 2) .. ", range " .. VOICE.cfg("range", 64))
say("  In chat near the base:  " .. VOICE.cfg("name", "base") .. ", status?  (also: turtles, mining, survey, time, weather, who)")
say("  Cache: " .. (VOICE.cacheDir() or "none (no data floppy with room)"))
if VOICE.err then say("  Last problem: " .. VOICE.err) end
if VOICE.lastSaid then say("  Last said: " .. VOICE.lastSaid.text) end
say("  voice on|off | say <text> | greet|announce|chat|alarm on|off | volume <0-3> | range <n> | name <word> | remove")
end
return out
end
