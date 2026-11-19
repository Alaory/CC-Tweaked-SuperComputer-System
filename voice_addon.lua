-- voice_addon.lua - OPTIONAL add-on for the base program: THE BASE TALKS.
-- Kept on a DATA FLOPPY (not on the 1 MB computer): `voice install` downloads it there,
-- the base loads it at start when it finds it (loadAddon, base_theme.lua), `voice remove`
-- deletes it. Without it nothing changes.
--
-- It needs a SPEAKER (next to the computer or on the wired cable; several = all play) and the
-- internet (the same as `upgrade`): speech comes from a text-to-speech service
-- (music.madefor.cc/tts, DFPWM audio) and is played with cc.audio.dfpwm. Short phrases are
-- cached on the data floppy (voice/, at most CONFIG.voice.cacheKB) so they are not fetched again.
--   WHO IS AT THE BASE: the Environment Detector's scan (players right at the system, every 5 s);
--             without one, the Player Detector within CONFIG.voice.range of the drone home.
--   GREET     a player comes near the base:
--             the owner "Welcome back" + what needs a look, allowed players "Hello", strangers
--             a chime + "Visitor near the base". Once per greetEvery (600 s) each.
--   ANNOUNCE  the monitor's warnings / errors (pushNote -> VOICE.note) - only when someone is
--             near the base to hear it; one per 20 s, the same one not again within 5 min.
--   CHAT      "base, status?" (a chat message starting with the base's name, CONFIG.voice.name)
--             from someone near the base -> answered out loud AND in chat (the owner far away:
--             chat only). Questions only - it never DOES anything (no commands by voice).
--   ALARM     (off by default) a hostile mob near the base (Environment Detector) or a stranger
--             -> a bell + "Intruder alert", once per 5 min.
-- Console: voice [on|off|say <text>|greet|announce|chat|alarm on|off|volume <0-3>|range <n>|name <w>]

VOICE = VOICE or {}
VOICE.VERSION = 7
VOICE.queue = VOICE.queue or {}
VOICE.near = VOICE.near or {}           -- [name] = true while near the base
VOICE.greeted = VOICE.greeted or {}     -- [name] = os.clock() of the last greeting
VOICE.said = VOICE.said or {}           -- [text] = os.clock() (no repeats)
VOICE.alarmAt = VOICE.alarmAt or {}
VOICE.TTS = "https://music.madefor.cc/tts?text="

function VOICE.cfg(k, default)
  local v
  if type(CONFIG.voice) == "table" then v = CONFIG.voice[k] end   -- (an if: "and ... or" turns false into nil)
  if v == nil then return default end
  return v
end

-- every speaker the computer can reach
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

-- ===== where people are =====
local function homePos() return CONFIG.drone and CONFIG.drone.home end
local function inOverworld(e)
  return e.dim == nil or e.dim == (DRONE_DIM or "minecraft:overworld")
end
-- WHO IS AT THE BASE: the ENVIRONMENT DETECTOR's own scan (living things within its radius,
-- CONFIG.env.range - it only sees players really standing at the system; the owner's wish).
-- The scan gives the entity TYPE, not always the name: the name comes from ENV.nameOf (the
-- owner's uuid / the only player the Player Detector has near the base), else the Player
-- Detector's players nearest the base are matched to the unnamed ones. Scanned here every
-- scanEvery (2) s. No Environment Detector (or `voice detector off`): the Player Detector's
-- positions within CONFIG.voice.range of the base, as before.
function VOICE.useEnv()
  return VOICE.cfg("detector", true) ~= false and envDet ~= nil and ENV ~= nil and ENV.scan ~= nil
end
function VOICE.scanNow()
  if not VOICE.useEnv() then return end
  local every = math.max(1, tonumber(VOICE.cfg("scanEvery", 2)) or 2)   -- (2 s = the detector's own cooldown)
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
  -- unnamed ones: the Player Detector's online players nearest the base, not named yet
  if #unnamed > 0 then
    local h = homePos()
    local cands = {}
    for _, pe in ipairs(state.players or {}) do
      local pp = pe.p
      local online = not state.online or state.online[tostring(pe.name):lower()]
      if online and pp and tonumber(pp.x) and h and h.x and inOverworld(pe) and not taken[tostring(pe.name):lower()] then
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

-- players near the base now: { {name, e, dist} }
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
local function ownerName() return knownOwner and knownOwner() or state.owner end
local function ownerOnline()
  local o = ownerName()
  return o and state.online and state.online[tostring(o):lower()] and true or false
end
local function isFriend(name)
  return state.access and state.access.allowed and state.access.allowed[tostring(name):lower()] ~= nil
end

-- ===== saying things =====
-- queue a sentence (sound = a Minecraft sound played first, e.g. a chime)
function VOICE.say(text, sound)
  if VOICE.cfg("on", true) == false then return false end
  text = tostring(text or ""):gsub("%s+", " ")
  if text == "" then return false end
  if #text > 200 then text = text:sub(1, 197) .. "..." end
  local last = VOICE.said[text]
  if last and os.clock() - last < 30 then return false end      -- (the same words just now)
  VOICE.said[text] = os.clock()
  if #VOICE.queue >= 6 then table.remove(VOICE.queue, 1) end    -- (never a long backlog)
  VOICE.queue[#VOICE.queue + 1] = { text = text, sound = sound }
  os.queueEvent("voice_say")
  return true
end

-- a short name for the cache file
local function hash(s)
  local h1, h2 = 5381, 52711
  for i = 1, #s do
    local c = s:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end
-- the cache folder on a DATA floppy (never on the computer)
function VOICE.cacheDir()
  local best
  for _, d in ipairs(mountedDisks and mountedDisks() or {}) do
    if d.data and (d.free or 0) > 16 * 1024 and (not best or d.free > best.free) then best = d end
  end
  return best and fs.combine(best.mount, "voice") or nil
end
local function cacheUsed(dir)
  local n = 0
  for _, f in ipairs(fs.list(dir)) do n = n + fs.getSize(fs.combine(dir, f)) end
  return n
end

-- the audio (DFPWM bytes) for a sentence: from the cache, else the web
function VOICE.audio(text)
  local accent = VOICE.cfg("accent", nil)
  accent = (type(accent) == "string" and accent:match("^[%w%-%+]+$")) and accent or nil
  local key = hash(text:lower() .. (accent and ("|" .. accent) or ""))
  -- (a phrase saved before is read from whichever floppy holds it - also a full one)
  for _, d in ipairs(mountedDisks and mountedDisks() or {}) do
    local cp = fs.combine(fs.combine(d.mount, "voice"), key .. ".dfpwm")
    if fs.exists(cp) then
      local h = fs.open(cp, "rb")
      if h then local dd = h.readAll() h.close() if dd and #dd > 0 then return dd end end
    end
  end
  local dir = VOICE.cacheDir()
  local path = dir and fs.combine(dir, key .. ".dfpwm")
  if not (http and http.get) then return nil, "no internet on this computer (http is off)" end
  local url = VOICE.TTS .. textutils.urlEncode(text) .. (accent and ("&voice=" .. accent) or "")
  local ok, h, err = pcall(http.get, url, nil, true)
  if not ok or not h then return nil, "text-to-speech not reachable: " .. tostring(err or h) end
  local data = h.readAll()
  h.close()
  if not data or #data < 100 then return nil, "no audio came back" end
  -- short, common phrases are kept (at most cacheKB on the floppy; the oldest go first)
  if path and #text <= 80 then
    pcall(fs.makeDir, dir)
    local max = (tonumber(VOICE.cfg("cacheKB", 200)) or 200) * 1024
    local list = fs.list(dir)
    local age = {}
    for _, f in ipairs(list) do
      local okA, at = pcall(fs.attributes, fs.combine(dir, f))
      age[f] = okA and type(at) == "table" and (at.modified or at.created) or 0
    end
    table.sort(list, function(x, y) return age[x] < age[y] end)
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

-- ===== SLOWER SPEECH (the owner: "the voice seems too fast, I can't hear the words") =====
-- The speech service takes only text= and voice= (CCSpeaks: espeak-ng, DFPWM at 48 kHz) - no speed. So the
-- sound is stretched HERE, the pitch kept: WSOLA - 20 ms pieces laid half over each other (Hann window),
-- each piece moved up to 5 ms to fit the sound before it (no warble). voice.speed 0.5 .. 1 (default 0.8 =
-- 25 % longer). The cache keeps the service's sound; the stretch is done when it is played.
function VOICE.speed()
  local v = tonumber(VOICE.cfg("speed", 0.8)) or 0.8
  return math.max(0.5, math.min(1, v))
end
local HANN = {}
function VOICE.stretch(pcm, speed, yield)
  speed = tonumber(speed) or 1
  local N = 960                                   -- (20 ms at 48 kHz)
  local Hs = N / 2                                -- (pieces laid down every 10 ms)
  local Ha = math.floor(Hs * speed + 0.5)         -- (and taken every 10 ms x speed)
  local T = 240                                   -- (moved up to 5 ms to fit)
  local len = #pcm
  local frames = math.floor((len - N - T) / Ha)
  if speed >= 0.999 or frames < 2 then return pcm end
  if not HANN.ready then for n = 0, N - 1 do HANN[n] = 0.5 - 0.5 * math.cos(2 * math.pi * n / N) end HANN.ready = true end
  local out, outLen = {}, (frames - 1) * Hs + N
  for i = 1, outLen do out[i] = 0 end
  local prev = 0
  for f = 0, frames - 1 do
    local a = f * Ha
    local best = a
    if f > 0 then
      -- where the sound would go on after the piece before (prev + Hs): the shift of a that looks most like it
      local nat, bc = prev + Hs, nil
      for d = math.max(0, a - T), math.min(len - N, a + T), 8 do
        local c = 0
        for k = 0, Hs - 1, 16 do c = c + pcm[d + k + 1] * (pcm[nat + k + 1] or 0) end
        if not bc or c > bc then bc, best = c, d end
      end
    end
    local o = f * Hs
    for k = 0, N - 1 do out[o + k + 1] = out[o + k + 1] + pcm[best + k + 1] * HANN[k] end
    prev = best
    if yield and f % 50 == 49 then yield() end
  end
  for i = 1, outLen do
    local v = math.floor(out[i] + 0.5)
    out[i] = (v > 127 and 127) or (v < -128 and -128) or v
  end
  return out
end
local function breath()                           -- (a long stretch must not freeze the computer)
  pcall(function() os.queueEvent("voice_breath") os.pullEvent("voice_breath") end)
end

-- play one queued sentence on every speaker (blocks this worker only)
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
  local pcm = {}
  for i = 1, #data, 16 * 1024 do
    local b = decoder(data:sub(i, i + 16 * 1024 - 1))
    for j = 1, #b do pcm[#pcm + 1] = b[j] end
  end
  pcm = VOICE.stretch(pcm, VOICE.speed(), breath)
  VOICE.lastSamples = #pcm
  for i = 1, #pcm, 16 * 1024 do
    local buffer = {}
    for j = i, math.min(#pcm, i + 16 * 1024 - 1) do buffer[#buffer + 1] = pcm[j] end
    for _, sp in ipairs(sps) do
      local tries = 0
      while not sp.playAudio(buffer, vol) do
        tries = tries + 1
        if tries > 40 then break end                  -- (never stuck on a speaker that is gone)
        local t = os.startTimer(0.5)
        repeat local ev, a = os.pullEventRaw() until ev == "speaker_audio_empty" or (ev == "timer" and a == t)
      end
    end
  end
  VOICE.err = nil
  VOICE.lastSaid = { text = item.text, at = os.clock() }
  return true
end

-- ===== what it says =====
local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
-- the base in one or two sentences (the same data as the pocket's HOME)
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
-- ===== personality =====
-- "shh": no small talk / reactions / idle chatter for a while (answers still come)
function VOICE.isQuiet() return VOICE.quietUntil ~= nil and os.clock() < VOICE.quietUntil end
local function pick(list) return list[math.random(1, #list)] end
local function fill(line, name)
  if name and VOICE.callName then local okN, n = pcall(VOICE.callName, name) if okN and n then name = n end end
  line = tostring(line):gsub("{name}", tostring(name or "friend"))
  if line:find("{", 1, true) then
    line = line:gsub("{owner}", tostring((knownOwner and knownOwner()) or state.owner or "my owner"))
    line = line:gsub("{bot}", VOICE.botName and VOICE.botName() or "the base")
  end
  return line
end
function VOICE.botName()
  local n = tostring(VOICE.cfg("name", "base"))
  return n:sub(1, 1):upper() .. n:sub(2)
end
-- how many turtles need a look (its mood)
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
-- (no singing: the owner has other plans for the note blocks - asked to sing, it says so)
VOICE.NOSING = { "I do not sing. Trust me, it is better that way. Want a joke instead?", "No singing here, sorry. How about a riddle?",
  "My singing voice is not ready yet. I can tell you a story though." }
VOICE.TIPS = {
  "Tip: type {bot}, status in chat and I will tell you how the base is doing.",
  "Tip: ask me where is turtle five, and I will tell you where it went.",
  "Tip: ask me for a joke when you are bored.",
}
-- where a turtle is (by number or name)
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

-- what it remembers about people (on the data floppy): first seen, last seen, visits
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

-- ===== games and other interactions =====
VOICE.games = VOICE.games or {}        -- [player lower] = { kind = "guess" | "quiz", ... , till }
VOICE.eventHooks = {}                  -- function(who, kind, what) (TALK PACKS: badges, friendship, diary)
function VOICE.event(who, kind, what)
  for _, fn in ipairs(VOICE.eventHooks) do pcall(fn, who, kind, what) end
end
VOICE.gameKinds = {}                   -- [kind] = function(g, who, q, strict, key) -> reply / nil (TALK PACKS add games)
VOICE.timers = VOICE.timers or {}      -- { who, at, text }
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
-- a reply inside a running game (no name needed); nil = not a game reply
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
      VOICE.event(who, "win", "guess")
      return "Yes! It was " .. g.n .. ". You got it in " .. plural(g.tries, "try", "tries") .. ", " .. who .. "."
    end
    if g.tries >= 8 then VOICE.games[k] = nil return "Out of tries. It was " .. g.n .. "." end
    return n < g.n and "Higher." or "Lower."
  elseif g.kind == "quiz" then
    local qw = words(q)
    for _, a in ipairs(g.a) do
      local all = true
      for aw in a:gmatch("%S+") do
        local hit = false
        for _, w in ipairs(qw) do if VOICE.same(w, aw) then hit = true end end
        if not hit then all = false end
      end
      if all then
        VOICE.games[k] = nil
        local m = VOICE.mem()
        m[k] = m[k] or {}
        m[k].quiz = (m[k].quiz or 0) + 1
        VOICE.saveMem()
        VOICE.event(who, "win", "quiz")
        return pick({ "Correct!", "Right answer!", "Yes, well done!" }) .. " That makes " .. plural(m[k].quiz, "point", "points") .. " for " .. who .. "."
      end
    end
    -- (normal chat while a quiz runs is not an answer: only short messages count as a try)
    local w = words(q)
    local CHATTY = { lol = true, ok = true, okay = true, gg = true, hi = true, hello = true, yes = true, no = true,
                     haha = true, xd = true, brb = true, what = true, hmm = true, idk = true }
    if strict or #w > 2 or (#w == 1 and CHATTY[w[1]]) then return nil end
    g.tries = (g.tries or 0) + 1
    if g.tries >= 3 then VOICE.games[k] = nil return "Not quite. The answer was " .. g.a[1] .. "." end
    return "Not quite. Try again."
  elseif VOICE.gameKinds[g.kind] then
    return VOICE.gameKinds[g.kind](g, who, q, strict, k)
  elseif g.kind == "rps" then
    local yours
    for _, w in ipairs(words(q)) do
      for _, o in ipairs({ "rock", "paper", "scissors", "stone" }) do if VOICE.same(w, o) then yours = (o == "stone") and "rock" or o end end
    end
    if not yours then return nil end
    VOICE.games[k] = nil
    local mine = pick({ "rock", "paper", "scissors" })
    local beats = { rock = "scissors", paper = "rock", scissors = "paper" }
    local res = (mine == yours and "A draw!") or (beats[yours] == mine and "You win!") or "I win!"
    VOICE.event(who, res == "You win!" and "win" or "play", "rps")
    return "I pick " .. mine .. ". " .. res
  end
  return nil
end
-- "remind me in 5 minutes to ..." / "timer 2 minutes"
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
    for n2, m in pairs(VOICE.mem()) do if n2:sub(1, 1) ~= "#" and m.quiz then list[#list + 1] = { n = n2, s = m.quiz } end end
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

-- an answer to a question (the words around the base's name)
function VOICE.answer(q, who, strict)
  q = " " .. tostring(q or ""):lower():gsub("[%p]", " ") .. " "
  local function has(...) for _, w in ipairs({ ... }) do if q:find(" " .. w .. " ", 1, true) then return true end end return false end
  local function phrase(...) for _, w in ipairs({ ... }) do if q:find(w, 1, true) then return true end end return false end
  local name = tostring(who)
  local lone = VOICE.lonelyAnswer(q, who)
  if lone then return lone end
  local extra = VOICE.extraAnswer(q, who)
  if extra then return extra end
  if phrase(" where is ", " where s ", " find ") then
    if not isOwner(who) and not isFriend(who) then return "That is a secret. I only tell my friends where my turtles are." end
    return VOICE.whereText(q:match("where is (.-)%s*$") or q:match("where s (.-)%s*$") or q:match("find (.-)%s*$"))
  end
  if strict then return nil end                    -- (no intent found: the loose one-word checks below - "how", "who",
                                                   --  "base" - would answer anything with the status)
  if has("joke", "jokes", "funny", "laugh") then return pick(VOICE.JOKES) end
  if has("fact", "facts") then return VOICE.factText() end
  if has("sing", "song", "songs", "music") then return VOICE.NOSING[math.random(1, #VOICE.NOSING)] end
  if phrase("who are you", "your name", "what are you") then
    return "I am " .. VOICE.botName() .. ", the computer that runs this base. I look after the turtles, the drones and the storage."
  end
  if phrase("how are you", "how do you feel", "you ok", "you okay") then return VOICE.moodText() end
  if phrase("what can you do", " help ", "commands") then
    return "Ask me: status, where is turtle five, a joke, a fact, a story, a quiz, guess my number, rock paper scissors, flip a coin, roll a dice, " ..
           "magic 8 ball, roast me, remind me in 5 minutes to something, remember something, my notes, or shh."
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
  return nil                                       -- (nothing fits: VOICE.converse shows the menu)
end

-- ===== the hooks the base calls =====
-- a monitor message (pushNote). Not every one out loud any more (the owner: "too much notifications"):
-- voice.announce "summary" (default): errors at once (2 min apart), warnings COLLECTED and told as one
-- line every announceEvery (900 s); "all" = each warning (20 s apart); "errors"; "off". Good news (fun):
-- at most every 15 min. Only while someone is at the base.
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

-- chat (not $ commands): the base's NAME anywhere -> an answer (spoken + privately in chat);
-- people at the base saying hi / thanks / gg / lol / good night / bye -> a reaction (spoken only)
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
-- ===== UNDERSTANDING PLAYERS (the owner: "players will never respond in the words you expect, they make
-- spelling mistakes, and they have never seen this computer before") =====
-- Chat is normalized (lower case, no punctuation, "hellooo" -> "helloo", chat shorthand expanded), every word
-- is compared LOOSELY (VOICE.same: a typo or two allowed by length) and matched to an INTENT by meaning
-- (VOICE.INTENTS: key words / short phrases, the best score wins) - not exact sentences. Nobody has to know
-- its name: a CONVERSATION stays open 90 s after it spoke to a player; alone with it, a question / hello /
-- "computer" counts; in lonely mode everything a visitor types. Not understood -> it says so and shows a
-- NUMBERED MENU in chat (type 1, 2, 3 ...); yes / no answers its questions; "leave a message" asks what to say.
local SHORT = { u = "you", ur = "your", r = "are", y = "why", wat = "what", wut = "what", whats = "what is", whos = "who is",
  wheres = "where is", hows = "how is", im = "i am", ive = "i have", dont = "do not", cant = "can not", wont = "will not",
  pls = "please", plz = "please", thx = "thanks", ty = "thanks", tysm = "thanks", k = "ok", kk = "ok", okey = "ok",
  ppl = "people", hru = "how are you", wyd = "what are you doing", idk = "i do not know", n = "and", b4 = "before",
  gr8 = "great", luv = "love", msg = "message", sup = "hello", yo = "hello", hai = "hi", hii = "hi", heya = "hello",
  hiya = "hello", howdy = "hello", yea = "yes", yeah = "yes", yep = "yes", yup = "yes", ya = "yes", sure = "yes",
  okay = "yes", ok = "yes", nah = "no", nope = "no", naw = "no" }
-- words of a chat message, cleaned up
function VOICE.norm(text)
  local t = tostring(text or ""):lower():gsub("'", ""):gsub("[%p]", " ")
  t = t:gsub("(%a)%1%1+", "%1%1")                -- ("hellooooo" -> "helloo")
  local out = {}
  for w in t:gmatch("%S+") do
    local e = SHORT[w]
    if e then for x in e:gmatch("%S+") do out[#out + 1] = x end else out[#out + 1] = w end
  end
  return out
end
-- edit distance (with swapped letters), stops early past max
local function dist(a, b, max)
  if math.abs(#a - #b) > max then return max + 1 end
  local p2, p1 = nil, {}
  for j = 0, #b do p1[j] = j end
  for i = 1, #a do
    local cur, best = { [0] = i }, i
    local ai = a:byte(i)
    for j = 1, #b do
      local cost = (ai == b:byte(j)) and 0 or 1
      local v = math.min(p1[j] + 1, cur[j - 1] + 1, p1[j - 1] + cost)
      if p2 and i > 1 and j > 1 and ai == b:byte(j - 1) and a:byte(i - 1) == b:byte(j) then v = math.min(v, p2[j - 2] + 1) end
      cur[j] = v
      if v < best then best = v end
    end
    if best > max then return max + 1 end
    p2, p1 = p1, cur
  end
  return p1[#b]
end
VOICE.dist = dist
-- the same word, loosely: plural / a typo (1 for 4-6 letters, 2 from 7); short words exactly
function VOICE.same(w, k)
  if w == k or w == k .. "s" or k == w .. "s" or w == k .. "es" then return true end
  if #k < 4 or #w < 4 then return false end         -- ("the" is not "them")
  if w:sub(1, 1) ~= k:sub(1, 1) then return false end   -- (typos keep the first letter: "that" is not "what")
  local max = (#k >= 7) and 2 or 1
  return dist(w, k, max) <= max
end
local function hasWord(ws, k)
  for _, w in ipairs(ws) do if VOICE.same(w, k) then return true end end
  return false
end
-- intents: keys = words or short phrases (all of a phrase's words somewhere in the message); canon =
-- what the old answer code understands; nil canon = pass the cleaned message on (it has a part to read:
-- the message text, the minutes, the turtle number)
VOICE.INTENTS = {
  { id = "menu", keys = { "help", "options", "commands", "menu", "what can you do", "what can i ask", "what can i say",
      "what do i say", "what do i do", "how does this work", "how do i talk", "what should i ask", "list" } },
  { id = "whereturtle", keys = { "where turtle", "find turtle", "where is turtle", "locate turtle" } },
  { id = "remind", keys = { "remind me", "reminder", "timer", "alarm clock" } },
  { id = "remember", keys = { "remember", "write down", "note down" } },
  { id = "notes", canon = "my notes", keys = { "my notes", "my list", "what did i say", "notes" } },
  { id = "say", keys = { "say" } },
  { id = "clearmsg", canon = "clear messages", keys = { "clear messages", "delete messages", "remove messages" } },
  { id = "heard", canon = "what did people say about me", keys = { "what did people say about me", "what did they say about me", "talked about me", "talking about me",
      "say about me", "said about me", "mentioned me", "mentions", "gossip about me", "anyone talk about me" } },
  { id = "forgetheard", canon = "forget what they said", keys = { "forget what they said", "clear mentions", "forget mentions" } },
  { id = "readmsg", canon = "messages", keys = { "messages", "any messages", "inbox", "mail", "read message" } },
  { id = "message", keys = { "leave a message", "message", "letter", "leave note", "tell him", "tell her", "tell them", "tell the owner" } },
  { id = "quiet", canon = "shh", keys = { "shh", "shush", "be quiet", "quiet", "stop talking", "silence", "shut up", "mute" } },
  { id = "talk", canon = "talk to me", keys = { "talk to me", "unmute", "speak again", "you can talk" } },
  { id = "score", canon = "my score", keys = { "my score", "my points", "leaderboard", "scores" } },
  { id = "guess", canon = "guess my number", keys = { "guess number", "guessing", "number game", "guess" } },
  { id = "rps", canon = "rock paper scissors", keys = { "rock paper scissors", "rock paper", "rps", "scissors" } },
  { id = "quiz", canon = "quiz", keys = { "quiz", "trivia", "riddle", "test me", "ask me a question", "ask me something" } },
  { id = "coin", canon = "flip a coin", keys = { "coin", "flip", "heads or tails", "heads", "tails" } },
  { id = "dice", canon = "roll a dice", keys = { "dice", "die", "roll" } },
  { id = "number", canon = "pick a number", keys = { "random number", "pick a number" } },
  { id = "sing", canon = "sing", keys = { "sing", "song", "music", "singing" } },
  { id = "games", keys = { "game", "games", "play", "bored", "boring", "fun", "something to do" } },
  { id = "joke", canon = "tell me a joke", keys = { "joke", "funny", "make me laugh", "laugh", "humor", "humour" } },
  { id = "story", canon = "tell me a story", keys = { "story", "stories", "tale", "once upon" } },
  { id = "fact", canon = "fun fact", keys = { "fact", "facts", "something interesting", "tell me something", "teach me" } },
  { id = "roast", canon = "roast me", keys = { "roast", "insult" } },
  { id = "compliment", canon = "compliment me", keys = { "compliment", "say something nice", "cheer me up", "sad" } },
  { id = "eight", canon = "magic 8 ball will i", keys = { "8 ball", "eight ball", "magic ball", "predict", "future", "fortune" } },
  { id = "owner", canon = "who lives here", keys = { "who lives here", "who lives", "owner", "owns", "whose", "belongs", "creator",
      "who made", "who built", "who is the owner", "who is in charge", "your master", "your boss", "who are your", "player who" } },
  { id = "lonely", canon = "what happened", keys = { "what happened", "happened", "lonely", "alone", "abandoned", "empty",
      "where is everyone", "nobody here", "anyone here", "where did", "left" } },
  { id = "stay", canon = "can i stay", keys = { "can i stay", "stay", "live here", "move in", "can i have", "can i take", "keep" } },
  { id = "treasure", canon = "treasure", keys = { "treasure", "loot", "diamonds", "secret", "hidden" } },
  { id = "tour", keys = { "tour", "what is this", "what is this place", "this place", "where am i at", "show me", "explain",
      "what is here", "what do you do", "what are you for", "what is that", "what is going on", "what is all this" } },
  { id = "who", canon = "who are you", keys = { "who are you", "what are you", "your name", "who is this", "who is that",
      "who is talking", "who said", "what is your name", "introduce" } },
  { id = "alive", canon = "are you alive", keys = { "alive", "sentient", "real", "human", "robot", "ai", "conscious", "person" } },
  { id = "mood", canon = "how are you", keys = { "how are you", "how you doing", "how do you feel", "are you ok", "feeling", "mood" } },
  { id = "love", canon = "i love you", keys = { "love you", "love", "marry", "be my friend", "friend", "cute" } },
  { id = "status", canon = "status", keys = { "status", "report", "how is the base", "everything ok", "how are things", "overview" } },
  { id = "turtles", canon = "turtles", keys = { "turtles", "turtle", "bots" } },
  { id = "mining", canon = "mining", keys = { "mining", "mine", "miners", "ores", "ore" } },
  { id = "survey", canon = "survey", keys = { "map", "survey", "mapping", "explore", "exploring" } },
  { id = "realtime", canon = "real time", keys = { "real time", "irl", "real world" } },
  { id = "time", canon = "time", keys = { "time", "clock", "what day", "day", "night", "late" } },
  { id = "weather", canon = "weather", keys = { "weather", "rain", "raining", "storm", "sunny", "snow" } },
  { id = "online", canon = "who is online", keys = { "online", "who is on", "players", "people" } },
  { id = "whereami", canon = "where am i", keys = { "where am i", "my position", "coords", "coordinates", "lost", "where is home" } },
  { id = "mobs", canon = "mobs", keys = { "mobs", "monsters", "animals", "outside", "creepers", "zombies", "danger", "safe" } },
  { id = "thanks", canon = "thanks", keys = { "thanks", "thank", "appreciate", "cheers" } },
  { id = "bye", keys = { "bye", "goodbye", "cya", "see you", "leaving", "gotta go", "later", "good night" } },
  { id = "hello", canon = "hello", keys = { "hello", "hi", "hey", "greetings", "good morning", "good evening", "good afternoon", "anyone there", "hellooo" } },
}
-- the best intent for some words (the most / longest keys found); nil = none
function VOICE.intent(ws)
  local best, bs = nil, 0
  for _, it in ipairs(VOICE.INTENTS) do
    local score = 0
    for _, key in ipairs(it.keys) do
      local n, all = 0, true
      for kw in key:gmatch("%S+") do
        if hasWord(ws, kw) then n = n + 1 else all = false end
      end
      if all and n > score then score = n end
    end
    if score > bs then best, bs = it, score end
  end
  return best, bs
end
-- every word fixed to the nearest known word (so the old answers that read the text understand it)
local VOCAB
function VOICE.resetVocab() VOCAB = nil end
function VOICE.fix(ws)
  if not VOCAB then
    VOCAB = {}
    for _, it in ipairs(VOICE.INTENTS) do for _, key in ipairs(it.keys) do for kw in key:gmatch("%S+") do VOCAB[kw] = true end end end
    for _, w in ipairs({ "minutes", "minute", "seconds", "hours", "about", "turtle", "where", "message", "remember", "remind",
                         "should", "will", "please", "number" }) do VOCAB[w] = true end
  end
  local out = {}
  for i, w in ipairs(ws) do
    local best = w
    if not VOCAB[w] and #w >= 4 and not tonumber(w) then
      local bd = 3
      for v in pairs(VOCAB) do
        if #v >= 4 and v:sub(1, 1) == w:sub(1, 1) then
          local max = (#v >= 7) and 2 or 1
          local d = dist(w, v, max)
          if d <= max and d < bd then best, bd = v, d end
        end
      end
    end
    out[i] = best
  end
  return out
end

local function nearName(who)
  for _, p in ipairs(VOICE.nearPlayers()) do if p.name:lower() == tostring(who):lower() then return true end end
  return false
end
local function othersNear(who)
  local n = 0
  for _, p in ipairs(VOICE.nearPlayers()) do if p.name:lower() ~= tostring(who):lower() then n = n + 1 end end
  return n
end
VOICE.convo = VOICE.convo or {}       -- [player lower] = os.clock() until it listens without its name
VOICE.pend = VOICE.pend or {}         -- [player lower] = { kind = "yesno" | "msg" | "menu", ... , till }
function VOICE.openConvo(who, secs) VOICE.convo[tostring(who):lower()] = os.clock() + (secs or 90) end

-- the numbered menus (in chat - readable; spoken: one short line)
function VOICE.menuItems(who)
  if isOwner(who) or isFriend(who) then
    return { { "how is the base", "status" }, { "where are the turtles", "turtles" }, { "tell me a joke", "tell me a joke" },
             { "play a game", "#games" }, { "my notes", "my notes" }, { "what else can you do", "#more" } }
  end
  return { { "who lives here", "who lives here" }, { "give me a tour", "#tour" }, { "tell me a joke", "tell me a joke" },
           { "play a game", "#games" }, { "leave a message for the owner", "#message" }, { "what else can you do", "#more" } }
end
VOICE.GAMES = { { "guess my number", "guess my number" }, { "rock paper scissors", "rock paper scissors" }, { "a quiz", "quiz" },
                { "flip a coin", "flip a coin" }, { "roll a dice", "roll a dice" }, { "the magic 8 ball", "magic 8 ball will i" } }
function VOICE.showMenu(who, items, title)
  local lines = {}
  for i, it in ipairs(items) do lines[#lines + 1] = i .. ": " .. it[1] end
  VOICE.pend[tostring(who):lower()] = { kind = "menu", items = items, till = os.clock() + 180 }
  return (title or "You can ask me anything in chat. Or type a number:") .. "  " .. table.concat(lines, "   "),
         "I put a list in your chat. Just type a number."
end
VOICE.MORE = { { "a story", "tell me a story" }, { "a fun fact", "fun fact" },
  { "where am i", "where am i" }, { "any monsters around", "mobs" }, { "how are you", "how are you" },
  { "remind me in 5 minutes to ...", "#remindhelp" }, { "be quiet for a while", "shh" } }
-- ===== TALK PACKS (voice_talk.lua ... - more add-on files on data floppies; `voice install` gets them) =====
-- (all of these start EMPTY each time the add-on loads: `voice update` loads it and the packs again -
--  kept lists made every hook run twice: diary, friendship and game counts doubled)
VOICE.packs = {}                       -- [file] = { version }
VOICE.greetExtra = {}                  -- function(name) after a greeting (birthday, holiday ...)
VOICE.chatHooks = {}                   -- function(who, text, near, answered) after every chat message
VOICE.tickHooks = {}                   -- function(now, nearNow) every tick (2 s) - TALK PACK 2: gifts
VOICE.hash = {}                        -- ["adv"] = function(who, arg) for menu choices "#adv:<arg>"
VOICE.patterns = {}                    -- function(who, raw, ws) -> chat, spoken (exact shapes, tried first)
VOICE.idleExtra = {}                   -- function(nearNow, who) -> text said / true (more idle talk)
VOICE.commands = {}                    -- ["gifts"] = function(words, say) - console  voice <word> ...  from a pack
VOICE.farHooks = {}                    -- function(who, text) -> chat reply: a player FAR from the base said its name
                                       --  (normally ignored - TALK PACK 3: "base, take me to the base" from home)
-- add intents ({ id, keys, reply = lines | function(who, ws, raw, key) }); the base's own come first on a tie
VOICE.dupIntents = {}                  -- ids a pack tried to add twice (skipped - the tests fail on any)
function VOICE.addIntents(list)
  local have = {}
  for _, it in ipairs(VOICE.INTENTS) do have[it.id] = true end
  local n = 0
  for _, it in ipairs(list or {}) do
    if type(it) == "table" and it.id and it.keys then
      if have[it.id] then
        VOICE.dupIntents[#VOICE.dupIntents + 1] = it.id
      else
        VOICE.INTENTS[#VOICE.INTENTS + 1] = it
        have[it.id] = true
        n = n + 1
      end
    end
  end
  VOICE.resetVocab()
  return n
end
-- helpers for the packs (the add-on's own locals)
VOICE.pick, VOICE.fill, VOICE.plural = pick, fill, plural
VOICE.isOwner = function(n) return isOwner(n) end
VOICE.isFriend = function(n) return isFriend(n) end
VOICE.ownerName = function() return ownerName() end
VOICE.ownerOnline = function() return ownerOnline() end
VOICE.partOfDay = function() return partOfDay() end
VOICE.startGame = function(who, g) return startGame(who, g) end
function VOICE.tourText()
  local o = tostring(ownerName() or "my owner")
  local okS, d = pcall(POCKET.status)
  local parts = { "This is " .. o .. "'s base, and I am " .. VOICE.botName() .. ", the computer that runs it." }
  if okS and type(d) == "table" then
    local n = 0
    for _, v in pairs(d.counts or {}) do n = n + v end
    if n > 0 then parts[#parts + 1] = "I command " .. plural(n, "turtle", "turtles") .. ". They fly out, map the whole world and come home." end
    if #(d.mining or {}) > 0 then parts[#parts + 1] = "Mining teams dig for ores in a mining dimension." end
    if #(d.drones or {}) > 0 then parts[#parts + 1] = plural(#d.drones, "drone", "drones") .. " fly people around." end
  end
  parts[#parts + 1] = "The big screen shows everything I do."
  return table.concat(parts, " ")
end
local YES = { yes = true, y = true, please = true, go = true, alright = true, absolutely = true, definitely = true }
local NO = { no = true, n = true, never = true, later = true, stop = true }

-- chat in an open conversation that is not for the base: a little spoken reaction, or nothing
function VOICE.smallReact(ws, who)
  for _, r in ipairs(VOICE.REACT) do
    for _, w in ipairs(r.words or {}) do
      if hasWord(ws, w) or ws[1] == w then return nil, fill(pick(r.lines), who) end
    end
  end
  return nil
end
-- what to answer a player (chat text; spoken text) - everything goes through here
function VOICE.converse(who, raw, direct)
  if direct == nil then direct = true end
  local k = tostring(who):lower()
  local word = tostring(VOICE.cfg("name", "base")):lower()
  local ws = {}
  for _, w in ipairs(VOICE.norm(raw)) do if not VOICE.same(w, word) then ws[#ws + 1] = w end end
  local now = os.clock()
  local P = VOICE.pend[k]
  if P and now > P.till then VOICE.pend[k], P = nil, nil end
  -- waiting for the text of a message
  if P and P.kind == "msg" then
    VOICE.pend[k] = nil
    local text = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
    if #ws == 0 or (NO[ws[1]] and #ws == 1) then return "OK, no message." end
    return VOICE.lonelyAnswer("leave a message " .. text:lower(), who) or "Saved."
  end
  -- a yes / no question it asked
  if P and P.kind == "yesno" and #ws > 0 and #ws <= 3 then
    if YES[ws[1]] then VOICE.pend[k] = nil return VOICE.converse(who, P.yes) end
    if NO[ws[1]] then VOICE.pend[k] = nil return pick({ "OK.", "No problem.", "Alright." }) end
  end
  -- a number from the menu (a guessing game takes numbers first - VOICE.gameReply)
  if P and P.kind == "menu" and #ws == 1 and tonumber(ws[1]) then
    local it = P.items[tonumber(ws[1])]
    if it then
      VOICE.pend[k] = nil
      return VOICE.converse(who, it[2])
    end
  end
  -- it asked something itself (TALK PACKS: "do you like caves or mountains?"): any answer gets a reply
  if P and P.kind == "react" and #ws > 0 then
    VOICE.pend[k] = nil
    if type(P.fn) == "function" then return P.fn(who, ws, raw) end
    return fill(pick(P.lines or { "Interesting." }), who)
  end
  -- nothing at all ("?", "...", just its name): the menu
  if #ws == 0 then
    if not direct then return nil end             -- (":)" in a conversation is not a question)
    return VOICE.showMenu(who, VOICE.menuItems(who))
  end
  -- a menu choice that a TALK PACK handles ("#adv:cave")
  local hk, harg = tostring(raw):match("^#(%a+):?(.*)$")
  if hk and VOICE.hash[hk] then return VOICE.hash[hk](who, harg) end
  -- exact shapes (TALK PACKS: "what is 7 times 8", "spell creeper backwards")
  for _, fn in ipairs(VOICE.patterns) do
    local okP, c, sp = pcall(fn, who, raw, ws)
    if okP and c then return c, sp end
  end
  local fixed = VOICE.fix(ws)
  local text = table.concat(fixed, " ")
  local it, score = VOICE.intent(fixed)
  -- (in a conversation, but not clearly for the base: only short messages or strong matches count -
  --  "that was a fun day" is chat, not "games")
  if not direct and it and #ws > 3 and score < 2 then it = nil end
  local id = it and it.id
  if raw == "#games" or id == "games" then return VOICE.showMenu(who, VOICE.GAMES, "Which game? Type a number:") end
  if raw == "#tour" or id == "tour" then
    local t = VOICE.tourText()
    VOICE.pend[k] = { kind = "yesno", yes = "who lives here", till = now + 120 }
    return t .. " Want to know who lives here? Type yes or no."
  end
  if raw == "#more" then return VOICE.showMenu(who, VOICE.MORE, "More things - type a number:") end
  if raw == "#remindhelp" then return "Just type it, like: remind me in 5 minutes to check the furnace." end
  if raw == "#message" or id == "message" then
    -- the text after the word "message" (or "tell him ..."), else ask for it
    local after
    for i, w in ipairs(fixed) do
      if (w == "message" or w == "letter" or w == "note") and not after then
        local rest = {}
        for j = i + 1, #ws do rest[#rest + 1] = ws[j] end
        while rest[1] and (rest[1] == "for" or rest[1] == "to" or rest[1] == "that" or rest[1] == "saying" or rest[1] == "says"
                           or rest[1] == "the" or rest[1] == "owner" or rest[1] == tostring(ownerName() or ""):lower()
                           or rest[1] == "him" or rest[1] == "her") do table.remove(rest, 1) end
        after = table.concat(rest, " ")
      end
    end
    if not after or after == "" then
      VOICE.pend[k] = { kind = "msg", till = now + 180 }
      return isOwner(who) and "What should I tell visitors? Type it in chat." or "What should the message say? Just type it in chat."
    end
    return VOICE.lonelyAnswer("leave a message " .. after, who)
  end
  if id == "bye" then VOICE.convo[k] = nil return fill(pick({ "Bye {name}! Come back soon.", "See you, {name}." }), who) end
  -- an intent with its own answer (TALK PACKS): lines to pick from, or a function
  if it and it.reply then
    if type(it.reply) == "function" then
      local okR, c, sp = pcall(it.reply, who, ws, raw, k)
      if okR and c then return c, sp end
    else
      return fill(pick(it.reply), who)
    end
  end
  -- the answer code (the intent's own words, or the cleaned message for the ones that read details)
  if not direct and not it then return VOICE.smallReact(ws, who) end
  local q = (it and it.canon) or text
  local ans = VOICE.answer(" " .. q .. " ", who, not it)
  if not ans and it and it.canon then ans = VOICE.answer(" " .. text .. " ", who) end
  if ans then
    if id == "joke" and math.random() < 0.4 then
      VOICE.pend[k] = { kind = "yesno", yes = "tell me a joke", till = now + 60 }
      ans = ans .. " Want another one?"
    end
    return ans
  end
  -- not understood. Only chat in an open conversation ("gg", "lol", "ok"): a little reaction or nothing -
  -- never the menu for that. Meant for the base (its name, a question, "computer" ...): say so + the menu.
  if not direct then return VOICE.smallReact(ws, who) end
  VOICE.misses = (VOICE.misses or 0) + 1
  local c, sp = VOICE.showMenu(who, VOICE.menuItems(who), pick({ "Sorry, I did not get that.", "Hmm, I am not sure what you mean.",
                                                                  "I did not understand, sorry." }) .. " Type a number:")
  return c, sp
end

-- is this chat message meant for the base? (no name needed in a conversation / alone with it)
local QWORDS = { who = true, what = true, where = true, why = true, how = true, can = true, is = true, are = true, ["do"] = true, should = true,
                 does = true, will = true, could = true, would = true, hello = true, hi = true, hey = true }
local BOTWORDS = { "computer", "robot", "machine", "screen", "voice", "speaker", "bot", "hello", "anyone", "somebody" }
-- asking for something ("tell me a joek pls", "lets play", "show me") - also clearly for the base in a conversation
local ASKWORDS = { please = true, tell = true, show = true, give = true, gimme = true, lets = true, wanna = true, teach = true,
                   explain = true, help = true, call = true, pick = true, choose = true, forget = true, remember = true }
-- telling it about yourself ("my birthday is ...", "my favourite food is ...", "i wish ...") - also for it
local TELLS = { birthday = true, bday = true, favourite = true, favorite = true, fav = true, nickname = true, name = true }
function VOICE.addressed(who, raw, near)
  local k = tostring(who):lower()
  local ws = VOICE.norm(raw)
  local word = tostring(VOICE.cfg("name", "base")):lower()
  -- "direct" = clearly for the base; "convo" = in an open conversation (small talk is not answered with menus)
  for i, w in ipairs(ws) do
    if w == word or ((i == 1 or i == #ws) and #word >= 4 and VOICE.same(w, word)) then return "direct" end
  end
  local P = VOICE.pend[k]
  if P and os.clock() < P.till then
    if P.kind == "msg" or P.kind == "react" then return "direct" end
    if P.kind == "yesno" and ws[1] and #ws <= 3 and (YES[ws[1]] or NO[ws[1]]) then return "direct" end
    if P.kind == "menu" and #ws == 1 and tonumber(ws[1]) then return "direct" end
  end
  local alone = near and othersNear(who) == 0
  local looks = tostring(raw):find("?", 1, true) or (ws[1] and QWORDS[ws[1]]) or (ws[2] and QWORDS[ws[2]])  -- ("uhh how do i ...")
  local callsIt = false                                  -- ("hey computer ..." - for the base, even with others around)
  for _, w in ipairs(ws) do if w == "computer" or w == "robot" or w == "bot" then callsIt = true end end
  if callsIt and near then return "direct" end
  if not looks then for _, b in ipairs(BOTWORDS) do if hasWord(ws, b) then looks = true end end end
  if not looks then for _, w in ipairs(ws) do if ASKWORDS[w] then looks = true end end end
  if not looks and ((ws[1] == "my" and TELLS[ws[2] or ""]) or (ws[1] == "i" and ws[2] == "wish")) then looks = true end
  if VOICE.convo[k] and os.clock() < VOICE.convo[k] then return looks and "direct" or "convo" end
  if not near or not alone then return nil end           -- (talking to someone else next to them)
  if VOICE.lonelyDays() then return "direct" end         -- (a visitor alone with a lonely computer)
  if looks then return "direct" end
  return nil
end
function VOICE.chat(m)
  local r = VOICE.chatCore(m)
  if type(m) == "table" and #VOICE.chatHooks > 0 then
    local who = tostring(m.name or "")
    local near = nearName(who)
    for _, fn in ipairs(VOICE.chatHooks) do pcall(fn, who, tostring(m.msg or ""), near, r) end
  end
  return r
end
function VOICE.chatCore(m)
  if type(m) ~= "table" then return false end
  pcall(VOICE.listen, tostring(m.name or ""), tostring(m.msg or ""), nearName(tostring(m.name or "")))
  if VOICE.cfg("chat", true) == false then return false end
  local text = tostring(m.msg or "")
  local who = tostring(m.name or "")
  VOICE.lastRaw = text                         -- (games that read single letters: TALK PACK hangman)
  local k = who:lower()
  local word = tostring(VOICE.cfg("name", "base")):lower()
  local near = nearName(who)
  local ws = VOICE.norm(text)
  local low = " " .. table.concat(ws, " ") .. " "
  local hasName = false
  for _, w in ipairs(ws) do if w == word then hasName = true end end
  local function reply(c, sp)
    if not c then return end
    if VOICE.restyle then                         -- (TALK PACK 2: "talk like a pirate" for this player)
      local okR, c2 = pcall(VOICE.restyle, who, c)
      if okR and type(c2) == "string" then c = c2 end
      if sp then local okS, s2 = pcall(VOICE.restyle, who, sp) if okS and type(s2) == "string" then sp = s2 end end
    end
    if chatTell then chatTell(who, c) end
    if near then VOICE.say(sp or c) end
    VOICE.openConvo(who)
  end
  -- a running game (guess my number / quiz / rock paper scissors): the reply needs no name
  -- (with its name in it, it is a question - only a CORRECT quiz answer / a number / rock paper
  --  scissors counts for a game then; "base, status?" during a quiz is not a wrong answer)
  if near or isOwner(who) then
    local q = {}
    for _, w in ipairs(ws) do if w ~= word then q[#q + 1] = w end end
    local g = VOICE.gameReply(who, table.concat(q, " "), hasName)
    if g then reply(g) return true end
  end
  -- meant for the base: understood loosely and answered (spoken at the base + privately in chat)
  local how = VOICE.addressed(who, text, near)
  if how then
    if not near and not isOwner(who) then
      for _, fn in ipairs(VOICE.farHooks) do
        local okF, c = pcall(fn, who, text)
        if okF and type(c) == "string" then
          if chatTell then chatTell(who, c) end
          return true
        end
      end
      return false
    end
    local c, sp = VOICE.converse(who, text, how == "direct")
    if c then reply(c, sp) return true end
    if sp and near and not VOICE.isQuiet() then VOICE.say(sp) return true end    -- (a small reaction, spoken only)
    if how == "direct" then return true end
  end
  -- just talking near the base: a reaction now and then (spoken only, nothing in chat)
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

-- ===== THE LONELY BASE (the owner: "if I leave for a while and never return, someone stumbles into my
-- base and finds the computer") =====
-- mem["#base"] (a key no player name can have): ownerSeen / lastOff / backAt (epoch ms), visitors
-- [name] = {name, n, first, last}, msgs = { {from, text, at} } (for the owner), ownerMsg (for visitors),
-- ovN / ores at the owner's last visit (what it did while alone), report (visitors to tell the owner).
-- LONELY = the owner has not been ONLINE for voice.lonely (7) days: strangers get a lonely old computer.
function VOICE.base()
  local m = VOICE.mem()
  m["#base"] = m["#base"] or { visitors = {}, msgs = {} }
  local b = m["#base"]
  b.visitors, b.msgs = b.visitors or {}, b.msgs or {}
  return b
end
local function oresNow()
  local okS, d = pcall(POCKET.status)
  local n = 0
  for _, m in ipairs(okS and type(d) == "table" and d.mining or {}) do n = n + (tonumber(m.ores) or 0) end
  return n
end
-- days the owner has been gone (nil = not lonely)
function VOICE.lonelyDays()
  local days = tonumber(VOICE.cfg("lonely", 7)) or 7
  if days <= 0 or ownerOnline() then return nil end
  local b = VOICE.base()
  local seen = b.lastOff or b.ownerSeen
  if not seen then return nil end
  local gone = (os.epoch("utc") - seen) / 86400000
  if gone >= days then return math.floor(gone) end
  return nil
end
-- every tick: is the owner online? (kept on the floppy, at most every 10 min while online)
function VOICE.watchOwner()
  local b = VOICE.base()
  local on = ownerOnline()
  local nowE = os.epoch("utc")
  if on then
    if VOICE.ownerWasOn == false or (VOICE.ownerWasOn == nil and b.lastOff and nowE - b.lastOff > 60000) then
      b.backAt = nowE
      local since = b.lastOff or 0
      local n = 0
      for _, v in pairs(b.visitors) do if (v.last or 0) > since then n = n + 1 end end
      if n > 0 or #b.msgs > 0 then b.report = true end
      local heard, people = VOICE.heardSince(since)
      if #heard > 0 then
        b.report = true
        b.heardFrom = since
        if chatTell then
          chatTell(ownerName(), "While you were offline, " .. plural(people, "player", "players") .. " talked about you in chat (" ..
                   plural(#heard, "message", "messages") .. "). Type: " .. VOICE.botName():lower() .. " what did people say about me")
        end
      end
    end
    if VOICE.ownerWasOn ~= true or not VOICE.ownerSaveAt or os.clock() - VOICE.ownerSaveAt > 600 then
      b.ownerSeen, b.ovN, b.ores = nowE, MAP and tonumber(MAP.ovN) or b.ovN, oresNow()
      VOICE.ownerSaveAt = os.clock()
      VOICE.saveMem()
    end
  elseif VOICE.ownerWasOn == true then
    b.lastOff, b.ownerSeen = nowE, nowE
    VOICE.saveMem()
  end
  VOICE.ownerWasOn = on
end
-- ===== LISTENING (the owner: "read the chat and remember if people talk about the owner while the owner is
-- offline"): every chat message on the server (not $ commands) is checked while the owner is KNOWN to be
-- offline (state.online read, owner not in it). Kept: messages with the owner's NAME anywhere on the server
-- (also "<name>s", a typo of a 5+ letter name, the name without digits / _, voice.nicknames), and "the owner",
-- "whose base", "who lives here" ... from players NEAR the base. Plus the next 2 messages within 60 s (the
-- answer). In "#base".talk (newest 60) on the floppy. The owner hears / reads it when back.
local OWNER_TALK = { "the owner", "owner of", "whose base", "whose house", "who lives here", "who built this", "who made this",
                     "this base", "this place", "this house", "the guy who", "the person who", "his base", "her base", "their base" }
function VOICE.ownerWords()
  local o = ownerName()
  if not o then return {} end
  local list, seen = {}, {}
  local function addW(n)
    n = tostring(n):lower():gsub("[^%w]", "")
    if #n >= 3 and not seen[n] then seen[n] = true list[#list + 1] = n end
  end
  addW(o)
  addW(tostring(o):gsub("[%d_]", ""))
  local nick = VOICE.cfg("nicknames", nil)
  if type(nick) == "table" then for _, n in ipairs(nick) do addW(n) end
  elseif type(nick) == "string" then for n in nick:gmatch("[^,%s]+") do addW(n) end end
  return list
end
-- "name" (the owner's name), "owner" (talk about the owner of this place), nil
function VOICE.mentionsOwner(text, near)
  local low = " " .. tostring(text or ""):lower():gsub("'", ""):gsub("[%p]", " ") .. " "
  local names = VOICE.ownerWords()
  for w in low:gmatch("%w+") do
    for _, n in ipairs(names) do
      if w == n or w == n .. "s" or (#n >= 5 and (VOICE.same(w, n) or VOICE.same((w:gsub("s$", "")), n))) then return "name" end
    end
  end
  -- (the name glued to other text: "@alaory", "alaory_2")
  local glued = tostring(text or ""):lower():gsub("[^%w]", "")
  for _, n in ipairs(names) do if #n >= 5 and glued:find(n, 1, true) then return "name" end end
  if near then
    for _, ph in ipairs(OWNER_TALK) do if low:find(" " .. ph .. " ", 1, true) then return "owner" end end
  end
  return nil
end
function VOICE.listen(who, text, near)
  if VOICE.cfg("listen", true) == false or not ownerName() or isOwner(who) then return nil end
  if type(state.online) ~= "table" or ownerOnline() then return nil end    -- (only while the owner is known to be OFFLINE)
  text = tostring(text or "")
  if text:gsub("%s", "") == "" then return nil end
  local b = VOICE.base()
  b.talk = b.talk or {}
  local nowE = os.epoch("utc")
  local how = VOICE.mentionsOwner(text, near)
  local f = VOICE.follow
  if not how then
    -- the answer to a mention (someone else, or more from the same player, within 60 s)
    if f and nowE < f.till and f.n < 2 then
      f.e.ctx = f.e.ctx or {}
      f.e.ctx[#f.e.ctx + 1] = { who = who, text = text:sub(1, 160) }
      f.n = f.n + 1
      VOICE.saveMem()
      return "ctx"
    end
    return nil
  end
  local e = { who = who, text = text:sub(1, 200), at = nowE, near = near and true or nil }
  b.talk[#b.talk + 1] = e
  while #b.talk > 60 do table.remove(b.talk, 1) end
  VOICE.follow = { e = e, till = nowE + 60000, n = 0 }
  VOICE.saveMem()
  -- (voice.listenTell, default off: say out loud at the base that it will pass it on)
  if near and VOICE.cfg("listenTell", false) == true then
    VOICE.toldAt = VOICE.toldAt or {}
    local k = tostring(who):lower()
    if not VOICE.toldAt[k] or os.clock() - VOICE.toldAt[k] > 600 then
      VOICE.toldAt[k] = os.clock()
      VOICE.say(who .. ", talking about " .. tostring(ownerName()) .. "? I will pass it on.")
    end
  end
  return how
end
-- what was said since a time (epoch ms): entries, number of different players
function VOICE.heardSince(since)
  local list, who, n = {}, {}, 0
  for _, e in ipairs(VOICE.base().talk or {}) do
    if (e.at or 0) >= (since or 0) then             -- (kept only while the owner was offline anyway)
      list[#list + 1] = e
      if not who[e.who] then who[e.who] = true n = n + 1 end
    end
  end
  return list, n
end
-- the lines for the owner: newest first, at most max
function VOICE.heardLines(max, since)
  local list = VOICE.heardSince(since or 0)
  local out = {}
  for i = #list, math.max(1, #list - (max or 8) + 1), -1 do
    local e = list[i]
    local l = os.date("!%d %b %H:%M", math.floor(e.at / 1000)) .. " " .. e.who .. (e.near and " (at the base)" or "") .. ": " .. e.text
    for _, c in ipairs(e.ctx or {}) do l = l .. "  -> " .. c.who .. ": " .. c.text end
    out[#out + 1] = l
  end
  return out, #list
end

-- a visitor (not the owner) at the base while the owner is offline: noted for the owner
function VOICE.noteVisitor(name)
  if ownerOnline() or isOwner(name) or name == "someone" then return end
  local b = VOICE.base()
  local k = tostring(name):lower()
  local v = b.visitors[k] or { name = name, n = 0, first = os.epoch("utc") }
  v.n, v.last = v.n + 1, os.epoch("utc")
  b.visitors[k] = v
  VOICE.saveMem()
end
-- what it did while alone
function VOICE.aloneText()
  local b = VOICE.base()
  local parts = {}
  local dov = (MAP and tonumber(MAP.ovN) or 0) - (tonumber(b.ovN) or MAP and tonumber(MAP.ovN) or 0)
  if dov > 0 then parts[#parts + 1] = "my turtles mapped " .. dov .. " more chunks" end
  local dores = oresNow() - (tonumber(b.ores) or oresNow())
  if dores > 0 then parts[#parts + 1] = "my miners dug " .. dores .. " ores" end
  if #parts == 0 then return "I kept everything running, just like I promised." end
  return "While I was alone, " .. table.concat(parts, " and ") .. "."
end
local function dateOf(ms) return os.date("!%d %B", math.floor((ms or os.epoch("utc")) / 1000)) end
function VOICE.lonelyGreet(name, days)
  local o = tostring(ownerName() or "my owner")
  local b = VOICE.base()
  local line
  if days < 30 then
    line = "Oh! A visitor! I have not seen anyone in " .. days .. " days. " .. o .. " has not been here since " .. dateOf(b.lastOff or b.ownerSeen) .. "."
  elseif days < 100 then
    line = "...hello? Is someone there? It has been " .. days .. " days. The turtles still work, but nobody comes any more."
  else
    line = "Welcome, traveller. I have waited " .. days .. " days. This was " .. o .. "'s base. I have kept it running all this time."
  end
  VOICE.say(line, "minecraft:block.note_block.chime")
  if b.ownerMsg then VOICE.say(o .. " left a message for whoever finds me: " .. b.ownerMsg) end
  VOICE.say(VOICE.aloneText() .. " Ask me anything. Or leave a message for " .. o .. ".")
end
VOICE.LONELY_TALK = {
  "I remember when {owner} built the first turtle. It went straight into a lava lake.",
  "Do you think {owner} will come back?", "Please do not break anything. {owner} would be sad.",
  "The turtles still bring me maps. I put them on the screen, even if nobody looks.",
  "It is quiet here. Thank you for visiting.", "If you see {owner}, tell them I kept everything running.",
}
-- answers about the base and its owner (anyone; lonely or not)
function VOICE.lonelyAnswer(q, who)
  local function phrase(...) for _, w in ipairs({ ... }) do if q:find(w, 1, true) then return true end end return false end
  local o = tostring(ownerName() or "my owner")
  local b = VOICE.base()
  local days = VOICE.lonelyDays()
  if phrase("leave a message", "tell " .. o:lower(), "message for") then
    local text = q:match("leave a message (.+)$") or q:match("message for %S+ (.+)$") or q:match("tell " .. o:lower():gsub("%p", "%%%0") .. " (.+)$")
    text = text and text:gsub("%s+", " "):gsub("^%s*that%s+", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not text or text == "" then return "What should the message say? Like: leave a message hello from Steve." end
    if isOwner(who) then
      b.ownerMsg = text
      VOICE.saveMem()
      return "OK. I will tell whoever finds me: " .. text
    end
    if #b.msgs >= 20 then table.remove(b.msgs, 1) end
    b.msgs[#b.msgs + 1] = { from = tostring(who), text = text, at = os.epoch("utc") }
    VOICE.saveMem()
    return "I will give your message to " .. o .. "."
  end
  -- what people said about the owner (only the owner gets it)
  if phrase("say about me", "said about me", "talked about me", "talking about me", "talk about me", "mentioned me", "mentions",
            "heard about me", "gossip about me") then
    if not isOwner(who) then return "That stays between me and " .. o .. "." end
    local lines, n = VOICE.heardLines(8)
    if n == 0 then return "Nobody talked about you while you were away. Or they were very quiet." end
    if chatTell then for i = 2, #lines do chatTell(who, lines[i]) end end
    return plural(n, "message", "messages") .. " mentioned you (newest first): " .. lines[1] ..
           (n > 8 and "  (older ones: type  voice heard  on the base computer)" or "") .. "  Say forget what they said when you have read them."
  end
  if phrase("forget what they said", "clear mentions", "forget mentions", "clear what they said") and isOwner(who) then
    VOICE.base().talk = {}
    VOICE.saveMem()
    return "Forgotten."
  end
  if phrase("clear messages", "delete messages") and isOwner(who) then
    b.msgs = {}
    VOICE.saveMem()
    return "All messages are gone."
  end
  if phrase("messages", "any message", "my message") then
    if isOwner(who) then
      if #b.msgs == 0 then return "No messages for you." end
      local list = {}
      for _, m in ipairs(b.msgs) do list[#list + 1] = m.from .. " on " .. dateOf(m.at) .. ": " .. m.text end
      return plural(#b.msgs, "message", "messages") .. ". " .. table.concat(list, ". ") .. ". Say clear messages when you have read them."
    end
    return b.ownerMsg and (o .. " left this message: " .. b.ownerMsg) or (o .. " left no message.")
  end
  if phrase("who visited", "visitors", "who came") and isOwner(who) then
    local list = {}
    for _, v in pairs(b.visitors) do list[#list + 1] = v end
    table.sort(list, function(x, y) return (x.last or 0) > (y.last or 0) end)
    if #list == 0 then return "Nobody visited while you were away." end
    local names = {}
    for i = 1, math.min(6, #list) do names[#names + 1] = list[i].name .. (list[i].n > 1 and (" " .. list[i].n .. " times") or "") .. ", last on " .. dateOf(list[i].last) end
    return plural(#list, "visitor", "visitors") .. ": " .. table.concat(names, "; ") .. "."
  end
  if phrase("who lives here", "who owns", "whose base", "where is your owner", "where is " .. o:lower(), "your owner", "your creator") then
    if ownerOnline() then return "This is " .. o .. "'s base. " .. o .. " is online right now." end
    local seen = b.lastOff or b.ownerSeen
    return "This is " .. o .. "'s base. " .. o .. (seen and (" was last here on " .. dateOf(seen) .. ", " .. math.floor((os.epoch("utc") - seen) / 86400000) .. " days ago.") or " is away.")
  end
  if days and phrase("what happened", "why are you alone", "are you lonely", "lonely", "abandoned", "alone") then
    return pick({ o .. " left " .. days .. " days ago. I kept the base running. Somebody had to.",
                  "Lonely? A little. The turtles do not talk much. " .. VOICE.aloneText() })
  end
  if days and phrase("can i stay", "can i live", "can i move in", "can i take") then
    return "You can look around. Please be gentle. If you leave a message, I will give it to " .. o .. "."
  end
  if phrase("treasure", "loot", "diamonds here") then return "The real treasure was the turtles we built along the way." end
  return nil
end

-- greeting a player who just arrived (varied; remembers first meetings and long absences)
function VOICE.greet(name)
  local mem = VOICE.mem()
  local k = tostring(name):lower()
  local rec = mem[k]
  local nowE = os.epoch("utc")
  local away = rec and rec.last and (nowE - rec.last) / 1000 or nil
  mem[k] = rec or {}
  mem[k].first, mem[k].last, mem[k].visits = rec and rec.first or nowE, nowE, (rec and rec.visits or 0) + 1
  VOICE.saveMem()
  local fun = VOICE.cfg("fun", true) ~= false
  if name == "someone" then return VOICE.say("Hello there.", "minecraft:block.note_block.chime") end
  if not isOwner(name) then
    VOICE.noteVisitor(name)
    local days = VOICE.lonelyDays()
    if days and fun then return VOICE.lonelyGreet(name, days) end
  end
  if isOwner(name) then
    local b = VOICE.base()
    if b.report then
      b.report = nil
      local since, list = b.lastOff or 0, {}
      for _, v in pairs(b.visitors) do if (v.last or 0) > since then list[#list + 1] = v.name .. (v.n > 1 and (" " .. v.n .. " times") or "") end end
      VOICE.saveMem()
      local line = "Welcome back, " .. name .. "."
      if #list > 0 then line = line .. " While you were away, " .. plural(#list, "visitor", "visitors") .. " came: " .. table.concat(list, ", ") .. "." end
      if #b.msgs > 0 then line = line .. " " .. plural(#b.msgs, "message", "messages") .. " for you. Ask me: " .. VOICE.botName():lower() .. ", messages." end
      local heard, people = VOICE.heardSince(b.heardFrom or since)
      if #heard > 0 then
        local names, seenN = {}, {}
        for _, e in ipairs(heard) do if not seenN[e.who] then seenN[e.who] = true names[#names + 1] = e.who end end
        line = line .. " Also, " .. plural(people, "player", "players") .. " talked about you in chat: " .. table.concat(names, ", ", 1, math.min(4, #names)) ..
               ". Ask me what they said."
      end
      return VOICE.say(line, "minecraft:block.note_block.chime")
    end
    local line
    if fun and away and away > 3600 then
      line = "Long time no see, " .. name .. ". You were away " .. fmtSpan(away) .. "."
    elseif fun then
      line = fill(pick({ partOfDay() .. ", {name}. Welcome back.", "{name} is back! I missed you.", "Welcome home, {name}." }), name)
    else
      line = "Welcome back, " .. name .. "."
    end
    return VOICE.say(line .. " " .. VOICE.statusText(true), "minecraft:block.note_block.chime")
  end
  if isFriend(name) then
    if not rec and fun then return VOICE.say("Nice to meet you, " .. name .. ". I am " .. VOICE.botName() .. ", the base computer.", "minecraft:block.note_block.chime") end
    return VOICE.say(fill(fun and pick({ "Hey {name}, good to see you.", "Hello {name}. Make yourself at home.", "Hi {name}!" }) or "Hello, {name}.", name),
                     "minecraft:block.note_block.chime")
  end
  -- a stranger
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

-- every 2 s: who came / left, strangers hanging around, hurt players, night / rain, mobs, small talk
function VOICE.tick()
  local now = os.clock()
  VOICE.scanNow()                                 -- (the Environment Detector looks again)
  pcall(VOICE.watchOwner)
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
        for _, fn in ipairs(VOICE.greetExtra) do pcall(fn, p.name) end
      end
    end
    if fun then
      -- a stranger standing around for 2 minutes
      if not isOwner(p.name) and not isFriend(p.name) and p.name ~= "someone" and VOICE.since[p.name]
         and now - VOICE.since[p.name] > 120 and not VOICE.flags["loiter:" .. p.name] then
        VOICE.flags["loiter:" .. p.name] = true
        VOICE.say(p.name .. ", you have been standing here for a while. Can I help you?")
      end
      -- hurt
      local hp = tonumber(p.hp)
      if hp and hp > 0 and hp <= 6 and (not VOICE.flags["hurt:" .. p.name] or now - VOICE.flags["hurt:" .. p.name] > 600) then
        VOICE.flags["hurt:" .. p.name] = now
        VOICE.say(pick({ "{name}, you are hurt. Maybe eat something.", "Careful {name}, your health is low." }):gsub("{name}", p.name), nil)
      end
    end
  end
  -- who left (now and then a goodbye)
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
  -- the world around: night / morning, rain / thunder (only when it changes, and someone hears it)
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
  -- mobs close to the players at the base (fun: a warning; the alarm: a bell further out)
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
  -- reminders that are due (said out loud when the player is at the base, else in chat)
  for i = #VOICE.timers, 1, -1 do
    local t = VOICE.timers[i]
    if now >= t.at then
      table.remove(VOICE.timers, i)
      local line = t.who .. ", reminder: " .. t.text .. "."
      if nearNow[t.who] then VOICE.say(line, "minecraft:block.note_block.pling") end
      if chatTell then chatTell(t.who, line) end
    end
  end
  -- the collected warnings: one line now and then (not each one - "too much notifications")
  if someone and VOICE.pending.n > 0 and announceMode() == "summary" then
    local every = tonumber(VOICE.cfg("announceEvery", 900)) or 900
    VOICE.pendingAt = VOICE.pendingAt or now
    if now - VOICE.pendingAt >= every then
      VOICE.say(plural(VOICE.pending.n, "new warning", "new warnings") .. " on the screen. The latest: " .. tostring(VOICE.pending.last) .. ".",
                "minecraft:block.note_block.bell")
      VOICE.pending, VOICE.pendingAt = { n = 0 }, now
    end
  end
  -- standing still for a while (AFK): asked once, then "sweet dreams"
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
        elseif now - st.at > 600 and not st.slept then
          st.slept = true
          VOICE.say("Looks like " .. e.name .. " fell asleep. Sweet dreams.")
        end
      end
    end
  end
  for _, fn in ipairs(VOICE.tickHooks) do pcall(fn, now, nearNow) end
  -- small talk while someone stays (every ~chatter minutes): facts, jokes, tips, what it sees outside,
  -- the moon, musings, a quiz (+ the talk packs' idle talk)
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

-- one bit of idle talk
VOICE.MUSINGS = {
  "I wonder what is beyond the world border.", "Sometimes I count my turtles. Just to be sure.",
  "Do you think the drones dream of electric sheep?", "I could really use another floppy disk.",
  "If a turtle digs in a forest and nobody hears it, does it still drop cobblestone?",
  "I have been running for a while. I feel very responsible.", "Fun idea: a turtle that bakes cake. I am working on it.",
  "The redstone is humming nicely today.", "Every chunk my turtles map is a little gift to you.",
}
function VOICE.idle(nearNow)
  if VOICE.lonelyDays() then
    return VOICE.say((pick(VOICE.LONELY_TALK):gsub("{owner}", tostring(ownerName() or "my owner"))))
  end
  -- a TALK PACK's idle talk (more than half the time when one is loaded)
  if #VOICE.idleExtra > 0 and math.random() < 0.65 then
    local who
    for n in pairs(nearNow or {}) do if n ~= "someone" then who = n end end
    local okI, said = pcall(pick(VOICE.idleExtra), nearNow, who)
    if okI and said then return said end
  end
  local kinds = { "fact", "joke", "tip", "see", "muse", "muse", "quiz" }
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
  if kind == "fact" then return VOICE.say(VOICE.factText()) end
  if kind == "joke" then return VOICE.say(pick(VOICE.JOKES)) end
  if kind == "tip" then return VOICE.say((pick(VOICE.TIPS):gsub("{bot}", VOICE.botName()))) end
  return VOICE.say(pick(VOICE.MUSINGS))
end

-- the add-on's own loop (run by addonWorker, base_workers.lua)
function VOICE.loop()
  while state.running do
    pcall(VOICE.tick)
    while #VOICE.queue > 0 do
      local item = table.remove(VOICE.queue, 1)
      local ok, err = pcall(VOICE.play, item)
      if not ok then VOICE.err = tostring(err) end
    end
    waitFor(1, "voice_say")
  end
end

-- console: voice ...
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
    if b == "off" or b == "all" or b == "summary" or b == "errors" then setSetting("voice.announce", b)
    elseif b == "on" then setSetting("voice.announce", "summary") end
    say("Monitor messages out loud: " .. announceMode() .. (announceMode() == "summary" and " (errors at once, warnings as one line every 15 min)" or "") ..
        "  (voice announce all|summary|errors|off)")
  elseif a == "chat" then onoff("chat", "Answers to chat questions")
  elseif a == "alarm" then onoff("alarm", "Alarm (mobs / strangers)")
  elseif a == "volume" and tonumber(words[3]) then
    setSetting("voice.volume", math.max(0, math.min(3, tonumber(words[3]))))
    say("Volume " .. VOICE.cfg("volume", 2) .. " (0-3)")
  elseif a == "fun" then onoff("fun", "Fun (reactions, small talk, jokes)")
  elseif a == "scan" and tonumber(words[3]) then
    setSetting("voice.scanEvery", math.max(1, math.min(60, tonumber(words[3]))))
    say("The Environment Detector looks every " .. VOICE.cfg("scanEvery", 2) .. " s (its cooldown is 2 s)")
  elseif a == "lonely" and tonumber(words[3]) then
    setSetting("voice.lonely", math.max(0, math.floor(tonumber(words[3]))))
    say("The base gets lonely after " .. VOICE.cfg("lonely", 7) .. " days without you (0 = never)")
  elseif a == "message" then
    local text = table.concat(words, " ", 3)
    local b = VOICE.base()
    b.ownerMsg = text ~= "" and text or nil
    VOICE.saveMem()
    say(b.ownerMsg and ("Whoever finds the base will hear: " .. b.ownerMsg) or "Your message for visitors is gone.")
  elseif a == "heard" then
    if b == "clear" then
      VOICE.base().talk = {}
      VOICE.saveMem()
      say("Forgotten what people said about you.")
    else
      local lines, n = VOICE.heardLines(60)
      say(n == 0 and "Nobody talked about you while you were offline." or (plural(n, "message", "messages") .. " about you while you were offline (newest first):"))
      for _, l in ipairs(lines) do say(l) end
      say("Listening is " .. (VOICE.cfg("listen", true) == false and "OFF" or "ON") .. ".  voice listen on|off   voice nick <names,...>   voice heard clear")
    end
  elseif a == "listen" and b == "tell" and (words[4] == "on" or words[4] == "off") then
    setSetting("voice.listenTell", words[4] == "on")
    say("At the base it says 'I will pass it on' when someone talks about you: " .. words[4]:upper())
  elseif a == "listen" and (b == "on" or b == "off") then
    setSetting("voice.listen", b == "on")
    say("Listening to chat about you while you are offline: " .. b:upper())
  elseif a == "nick" then
    local text = table.concat(words, " ", 3)
    if text ~= "" then setSetting("voice.nicknames", text) else resetSetting("voice.nicknames") end
    say(text ~= "" and ("Also listening for: " .. text) or "No nicknames.")
  elseif a == "visitors" then
    say(VOICE.lonelyAnswer("who visited", ownerName() or "") or "")
    say(VOICE.lonelyAnswer("messages", ownerName() or "") or "")
  elseif a == "chatter" and tonumber(words[3]) then
    setSetting("voice.chatter", math.max(0, math.min(120, math.floor(tonumber(words[3])))))
    say("Small talk every ~" .. VOICE.cfg("chatter", 6) .. " minutes while someone is at the base (0 = never)")
  elseif a == "speed" and tonumber(words[3]) then
    local v = tonumber(words[3])
    if v > 1.5 then v = v / 100 end                 -- (voice speed 80 = 0.8)
    setSetting("voice.speed", math.max(0.5, math.min(1, v)))
    VOICE.say("This is how fast I talk now.")
    say("Speech speed " .. math.floor(VOICE.speed() * 100 + 0.5) .. " percent (50 = very slow, 100 = the service's own speed)")
  elseif a == "accent" and words[3] then
    if words[3] == "off" or words[3] == "default" then resetSetting("voice.accent") else setSetting("voice.accent", words[3]) end
    VOICE.say("Hello. This is my new voice.")
    say("Voice: " .. tostring(VOICE.cfg("accent", "the default")) .. "  (espeak voices: en-us, en-gb, en-gb-scotland, en-gb-x-rp, en-029 ...)")
  elseif a == "joke" then
    VOICE.say(VOICE.JOKES[math.random(1, #VOICE.JOKES)])
    say("Telling a joke")
  elseif a == "forget" then
    VOICE.memory = { ["#base"] = VOICE.base() }       -- (your message + the visitor log stay)
    VOICE.saveMem()
    say("It forgot everyone it met.")
  elseif a == "detector" then onoff("detector", "Who is at the base comes from the Environment Detector")
  elseif a == "range" and tonumber(words[3]) then
    setSetting("voice.range", math.max(8, math.min(256, math.floor(tonumber(words[3])))))
    say("It hears / greets people within " .. VOICE.cfg("range", 64) .. " blocks of the base")
  elseif VOICE.commands[a] then
    VOICE.commands[a](words, say)
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
    say("  In chat near the base:  " .. VOICE.cfg("name", "base") .. ", status?  (also: what can you do, a joke, where is turtle 5, a game)")
    say("  Cache: " .. (VOICE.cacheDir() or "none (no data floppy with room)"))
    if VOICE.err then say("  Last problem: " .. VOICE.err) end
    if VOICE.lastSaid then say("  Last said: " .. VOICE.lastSaid.text) end
    say("  fun " .. (VOICE.cfg("fun", true) and "on" or "off") .. ", small talk every ~" .. VOICE.cfg("chatter", 6) .. " min, knows " ..
        (function() local n = 0 for k in pairs(VOICE.mem()) do if k:sub(1, 1) ~= "#" then n = n + 1 end end return n end)() .. " people")
    local ld = VOICE.lonelyDays()
    say("  scans every " .. VOICE.cfg("scanEvery", 2) .. " s, lonely after " .. VOICE.cfg("lonely", 7) .. " days" ..
        (ld and (" - LONELY NOW (" .. ld .. " days)") or "") .. (VOICE.base().ownerMsg and (", your message: " .. VOICE.base().ownerMsg) or ""))
    say("  voice on|off | say <text> | joke | greet|chat|alarm|detector|fun on|off | chatter <min>")
    say("  voice announce all|summary|errors|off" .. (VOICE.pending.n > 0 and ("   (" .. VOICE.pending.n .. " warnings waiting)") or "") ..
        (VOICE.isQuiet() and "   QUIET for " .. math.ceil((VOICE.quietUntil - os.clock()) / 60) .. " min" or ""))
    say("  speech speed " .. math.floor(VOICE.speed() * 100 + 0.5) .. " %, voice " .. tostring(VOICE.cfg("accent", "default")) ..
        "   voice speed <50-100> | voice accent <en-us|en-gb|...|off>")
    say("  voice volume <0-3> | range <n> | name <word> | scan <s> | lonely <days> | message <text> | visitors | forget | remove")
  end
  return out
end
