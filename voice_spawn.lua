-- voice_spawn.lua  -  THE SPAWN SPEAKER (an add-on file for the talking base, loaded after the others; VOICE_FILES).
--
-- The owner: "can I put an ender modem on a speaker at spawn and have the base use it?" - an ender modem cannot share
-- a Speaker (only wired modems share peripherals), so a small computer at spawn runs spawn_speaker.lua: it plays what
-- the base sends. The BASE does everything else: it hears the chat (its Chat Box hears the whole server), sees who
-- stands at spawn (Player Detector), decides what to say, makes the sound (speech service + slower / clearer, the
-- same as at the base), and sends it there in signed pieces (DFPWM, 16 KB each) over the ender modem.
--
-- What the owner asked for:
--   * ITS OWN PLACE, its own voice (voice.spawnVoice, a preset - "bright" by default) and its own lines (spawn,
--     shops, passers-by), not a copy of the base's greetings.
--   * NO REWARDS at spawn: no friendship, badges, quiz points or reward gifts there (VOICE.ctx = "spawn" while a
--     spawn player's chat is handled - V.addRep / V.badge / V.giftEarn / VOICE.event do nothing then). Friendship
--     stays a thing of the base.
--   * WISHES: "base, I wish for 16 diamonds" / "base, can I have an apple" -> the item is looked up in AE2, the
--     player says yes, and a drone brings it (the gift queue of TALK PACK 2: wherever they are in the overworld).
--     voice.wishDaily (3) a player a day, wishAll (40) for everybody, wishMax (64) per wish, never the items in
--     SP.NEVER / voice.wishBlock.
--   * GAMES AND TALK: everything the base understands works at spawn too (jokes, roasts, games, riddles, quiz ...).
--   * PLAYERS DO NOT KNOW HOW TO ASK: "how do I use this", "what is this thing", "who is talking", "is that a bot"
--     at spawn (also WITHOUT its name when it just spoke or the message names the speaker / bot) -> how to talk to
--     it, with examples ("base tell me a joke", "base roast me" ...), never the same twice in a row.
--   * NOT DULL: many ways to say each thing (pieces put together: every opener with every ending), shuffle bags.
--   * Players pass by all the time (spawn shops): a newcomer is greeted + told how to talk once; others at most every
--     voice.spawnGreetEvery (2 h) and only half of the time; idle talk every ~voice.spawnChatter (5) min while someone
--     is there; reactions to chat at most once a minute.
-- Console / chat: voice spawn [here|at x y z|pair <code>|unpair|name <word>|on|off|range <n>|voice <preset>|chatter <min>|
-- wish on|off|daily <n>|max <n>|block <item>|unblock <item>|say <text>]  ($drone spawn ... in chat, the owner).
local V = VOICE
if not V then return end
V.packs = V.packs or {}
V.packs["voice_spawn.lua"] = { version = 1 }
local SP = { queue = {}, cands = {}, lastN = 0, busyUntil = 0, sent = 0 }
if V.SPAWN then                                              -- (voice update: what the pairing / relay said stays)
  for _, k in ipairs({ "seenAt", "relay", "cands", "lastN", "pending", "spokeAt", "sendN", "busyUntil", "spam", "tpMood" }) do SP[k] = V.SPAWN[k] end
  SP.cands = SP.cands or {}
end
V.SPAWN = SP
SP.PROTO = "basespawn"
local pick, fill = V.pick, V.fill
-- ITS OWN CALL WORD (the owner: "I don't want to call the one in spawn base"): voice.spawnName - while the spawn speaker
-- handles something (VOICE.ctx "spawn" / SP.naming) every voice file asks V.cfg("name") and gets this word instead
-- ONLY IN THE COROUTINE THAT SET IT (review: a call inside - startRide for a teleport, an AE2 lookup - PAUSES, and the
-- base's own voice loop ran meanwhile with "near" = spawn, its talk sent to spawn, no rewards at the base)
local function here(co) return co ~= nil and coroutine.running() == co end
function SP.inSpawn() return V.ctx == "spawn" and here(SP.ctxCo) end
function SP.inNaming() return (SP.naming and here(SP.nameCo)) or SP.inSpawn() end
V.noPointsNow = function() return SP.inSpawn() end
local cfg0 = V.cfg
function V.cfg(k, d)
  if k == "name" and SP.inNaming() then
    local n = cfg0("spawnName", nil)
    if type(n) == "string" and n:match("^%a[%w]*$") then return n end
  end
  return cfg0(k, d)
end
function SP.named(fn, ...)
  local was, wasCo = SP.naming, SP.nameCo
  SP.naming, SP.nameCo = true, coroutine.running()
  local r = table.pack(pcall(fn, ...))
  SP.naming, SP.nameCo = was, wasCo
  if not r[1] then error(r[2], 0) end
  return table.unpack(r, 2, r.n)
end
local function cfg(k, d) return V.cfg(k, d) end
local function rt() return V.rt() end
local function low(s) return tostring(s or ""):lower() end

-- ===== the same checksums as spawn_speaker.lua =====
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

-- ===== where, who =====
function SP.at()
  local a = cfg("spawnAt", nil)
  if type(a) == "table" and tonumber(a.x) and tonumber(a.z) then return a end
  return nil
end
function SP.paired() return tonumber(cfg("spawnId", nil)) ~= nil and type(cfg("spawnKey", nil)) == "string" end
function SP.online() return SP.paired() and SP.seenAt ~= nil and rt() - SP.seenAt < 75 end
-- the spawn speaker is used: on, paired, its spot known, heard from lately
function SP.ready() return cfg("spawn", true) ~= false and SP.online() and SP.at() ~= nil end
local function inDim(e)
  local want = cfg("spawnDim", "minecraft:overworld")
  return e.dim == nil or e.dim == want
end
-- online players at spawn now: { {name, e, dist, hp, max} } (the Player Detector - refreshed every tick)
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

-- ===== the spawn context: while a spawn player's chat is handled, "near" = spawn, speech goes to spawn, no rewards
local nearPlayers0, say0, event0 = V.nearPlayers, V.say, V.event
function V.nearPlayers()
  if SP.inSpawn() then return SP.players() end
  return nearPlayers0()
end
function V.say(text, sound, answer, style)
  if SP.inSpawn() then return SP.say(text, answer) end
  return say0(text, sound, answer, style)
end
function V.event(who, kind, what)
  if SP.inSpawn() then return end                             -- (no badges / friendship / streaks from spawn)
  return event0(who, kind, what)
end
local function guard(name, allow)
  local f = V[name]
  if type(f) ~= "function" then return end
  V[name] = function(...)
    if SP.inSpawn() and not (allow and allow(...)) then return false, "no rewards at spawn" end
    return f(...)
  end
end
guard("addRep")
guard("badge")
guard("giftEarn", function(who, why) return why == "wish" end)
if V.GIFT_WHY then V.GIFT_WHY.wish = "- you wished for it" end
function SP.inCtx(fn, ...)
  local was, wasCo = V.ctx, SP.ctxCo
  V.ctx, SP.ctxCo = "spawn", coroutine.running()
  local r = table.pack(pcall(fn, ...))
  V.ctx, SP.ctxCo = was, wasCo
  if not r[1] then error(r[2], 0) end
  return table.unpack(r, 2, r.n)
end

-- ===== saying it at spawn =====
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
  if V.cleanNames then text = V.cleanNames(text) end
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
-- (kept in SP.sendN across voice update: a new count from 0 was refused by the relay as an old message)
local function nextN()
  local n = os.epoch("utc")
  if n <= (SP.sendN or 0) then n = SP.sendN + 1 end
  SP.sendN = n
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
-- samples -> DFPWM bytes (a fresh encoder per piece; the relay starts a fresh decoder on .fresh)
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
SP.SEND_AHEAD = 2.5         -- the relay gets the next piece this long before the one before ends (s)
SP.CHUNK = 16 * 1024        -- bytes per message (2.7 s of sound)
-- one line: piece by piece (fetched + made while the one before plays), sent ahead of time; an answer coming in
-- cuts its OWN talk (the relay stops at once)
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
    -- an ANSWER while its own talk still plays: cut it NOW (review: the cut came after the wait below - the answer
    -- waited up to a whole piece of its own talk)
    if pi == 1 and item.answer and rt() < SP.busyUntil and SP.ownPlaying then
      SP.send("cut", {})
      SP.busyUntil = rt()
    end
    -- (no more than SEND_AHEAD before the relay needs it: an answer can still cut in)
    local steps = 0
    while rt() < SP.busyUntil - SP.SEND_AHEAD and steps < 600 do
      steps = steps + 1
      if not item.answer and SP.answerWaiting() then
        if sentAny then SP.send("cut", {}) SP.busyUntil = rt() end
        return false, "gave way"
      end
      sleep(0.1)
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
-- (always the CURRENT spawn table - V.SPAWN: after a reload an old loop still running would read the old queue)
function SP.drain()
  local S = V.SPAWN or SP
  S.loopAt = os.clock()
  while #S.queue > 0 do
    local item = table.remove(S.queue, 1)
    if S.ready() then
      local ok, err = pcall(S.play, item)
      if not ok then S.err = tostring(err) end
    end
    S.loopAt = os.clock()
  end
end
function SP.loop()
  while state.running do
    local S = V.SPAWN or SP
    S.drain()
    waitFor(2, "spawn_say")
  end
end
local loop0 = V.loop
function V.loop()
  parallel.waitForAny(loop0, function()
    while state.running do
      local S = V.SPAWN or SP
      local ok, err = pcall(S.loop)
      if not ok then S.err = tostring(err) end
      sleep(2)
    end
  end)
end

-- ===== messages from the relay (comms worker -> VOICE.spawnReceive) =====
function V.spawnReceive(id, m)
  if type(m) ~= "table" or type(m.t) ~= "string" then return end
  local pid, key = tonumber(cfg("spawnId", nil)), cfg("spawnKey", nil)
  if not m.sig then                                             -- (not paired yet: offers itself)
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
  -- the sign on the spawn computer (and its monitors): sent again when its copy differs (a new call word, a restart)
  local info = SP.signText()
  if m.inf ~= nil and m.inf ~= SP.dataHash(info) then SP.send("info", { d = info }) end
end
function SP.signText()
  local w = SP.named(function() return low(V.cfg("name", "base")) end)
  return "I TALK! Type in chat:\n" .. w .. " help\n" .. w .. " tell me a joke\n" .. w .. " play a game\n" ..
         w .. " I wish for 16 apples\n(or start with: speaker / bot)"
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

-- ===== the spawn memory (mem["#spawn"]: who it met, greeted, wishes) =====
local function smem()
  local m = V.mem()
  local s = m["#spawn"]
  if type(s) ~= "table" then s = {} m["#spawn"] = s end
  s.met = type(s.met) == "table" and s.met or {}
  s.gr = type(s.gr) == "table" and s.gr or {}
  s.wish = type(s.wish) == "table" and s.wish or {}
  s.log = type(s.log) == "table" and s.log or {}
  s.talk = type(s.talk) == "table" and s.talk or {}
  s.called = type(s.called) == "table" and s.called or {}
  return s
end
SP.mem = smem
local function today() return os.date("!%Y-%m-%d") end
local function trim(t, max)                                   -- (a busy spawn: the oldest names out)
  local n, oldK, oldV = 0, nil, nil
  for k, v in pairs(t) do
    n = n + 1
    local at = type(v) == "table" and (v.at or 0) or (tonumber(v) or 0)
    if not oldV or at < oldV then oldK, oldV = k, at end
  end
  if n > max and oldK then t[oldK] = nil end
end

-- ===== the words =====
local function combos(A, B)
  local out = {}
  for _, a in ipairs(A) do for _, b in ipairs(B) do out[#out + 1] = a .. b end end
  return out
end
SP.L = {}
-- how to talk to it (examples go in at random, 3 at a time)
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
SP.HELP_HOW = { " Type in chat and start with {botl}, like: ", " Put my name, {botl}, first in your chat message. Try: ",
  " In chat, begin with the word {botl}. For example: ", " Just start your chat message with {botl}, then say what you want: ",
  " Say {botl} first in chat and I know it is for me. Like: ", " Type {botl} and a question in chat. Try: ",
  " Start a chat message with {botl}. Some ideas: ", " Write in chat: my name, {botl}, then anything: " }
SP.HELP_END = { " Typos are fine.", " I understand loose words, no exact commands.", " Ask me anything - the worst I can say is I do not know.",
  " Type {botl} help for a menu.", " Try one now!", " I answer in chat and out loud.", " I know games, jokes and a lot about Minecraft.",
  " You can even wish for an item - a drone might bring it.", "", " Have fun!" }
-- the wish how-to (the owner: "I had to tell them about the wishing system - they didn't know how to interact with it")
SP.WISH_HELP_ALWAYS = { "how do i wish", "how to wish", "how do you wish", "how does wishing work", "how do wishes work",
  "how does the wish", "wishing system", "can i make a wish", "how can i wish", "how do i make a wish" }
SP.WISH_HELP = { "how do i wish", "how to wish", "how do you wish", "how does wishing work", "how do wishes work", "how does the wish",
  "wishing system", "can i make a wish", "how can i wish", "how do i make a wish", "what can i wish", "what can i wish for",
  "can i wish", "wishes", "free stuff", "free items", "free things", "free item", "freebies", "can i get something",
  "give me something", "can i have something", "gift", "a gift", "do you give items", "do you give stuff", "how do i get items",
  "how do i get stuff", "giveaway", "free diamonds" }
SP.WISH_OPEN = { "Wishes are easy!", "Here is how wishing works.", "Oh, you want to make a wish?", "Yes, I grant wishes!",
  "Free items? Sort of - I grant wishes.", "Good news: I grant wishes.", "Wishing is simple.", "You can wish for items here." }
SP.WISH_EG = { "{botl} I wish for 16 apples", "{botl} I wish for a diamond", "{botl} can I have 32 torches",
  "{botl} give me a stack of oak logs", "{botl} I wish for 8 golden carrots", "{botl} I want 64 stone", "{botl} I wish for an ender pearl" }
function SP.wishHelp(who)
  local daily, max = tonumber(cfg("wishDaily", 3)) or 3, math.min(64, tonumber(cfg("wishMax", 64)) or 64)
  local mine = SP.wishesToday(who)
  local left = math.max(0, daily - mine)
  local t = pick(SP.WISH_OPEN) .. " Type in chat: " .. pick(SP.WISH_EG) .. ". I say what I found, you say yes, and a drone flies it " ..
    "to you - anywhere in the overworld. Up to " .. max .. " per wish, " .. daily .. " wishes a day"
  if cfg("wish", true) == false then t = "Wishing is switched off right now, sorry. When it is on: " .. pick(SP.WISH_EG) .. "." return fill(t, who) end
  if V.isOwner(who) then t = t .. " (you are the owner - you have everything already)."
  else t = t .. " - you have " .. left .. " left today." end
  return fill(t, who)
end
SP.WISH_HINT = { " You can also wish for items: {botl} I wish for 16 apples.", " And I grant wishes: {botl} I wish for a diamond.",
  " Want an item? {botl} I wish for, then what you want.", " Psst - wishes work too: {botl} I wish for 32 torches.",
  " I even grant wishes - try {botl} I wish for an apple.", " Free items by drone: {botl} I wish for 16 bread." }
function SP.helpText(who)
  local ex, used = {}, {}
  while #ex < 3 do
    local e = pick(SP.EXAMPLES)
    if not used[e] then used[e] = true ex[#ex + 1] = e end
  end
  local t = pick(SP.HELP_OPEN) .. pick(SP.HELP_HOW) .. table.concat(ex, ", ") .. "." .. pick(SP.HELP_END) .. pick(SP.WISH_HINT) ..
    " You can also just say speaker or bot instead of my name."
  return fill(t, who)
end
-- who / what it is (at spawn: the speaker of a base far from here)
SP.WHO = combos({ "I am {bot}, the spawn speaker of {owner}'s base.", "I am the voice of {owner}'s base. The base itself is far from here.",
  "I am a computer from {owner}'s base - this speaker is my spawn mouth.", "Just a speaker on a pole, with a whole base behind it.",
  "I am {bot}. Here at spawn I am only a voice; my body is a base full of turtles and drones.",
  "Think of me as the base's ears and voice at spawn.", "I am a talking speaker. The thinking happens at {owner}'s base.",
  "I am {bot}. I run a whole base and still find time to chat at spawn.", "A ComputerCraft computer, talking through an ender modem.",
  "I am the friendly spawn speaker. {owner} built me." },
  { "", " Say {botl} help to see what I can do.", " I tell jokes, play games and answer questions.", " Nice to meet you!",
    " Ask me something.", " I do not bite. I do not even have teeth." })
SP.MADE = combos({ "{owner} built me.", "I belong to {owner}.", "{owner} made me - and the whole base behind me.", "My owner is {owner}.",
  "{owner} put me here.", "I am {owner}'s computer." },
  { "", " Be nice, {owner} reads my logs.", " I run {owner}'s base far from here.", " {owner} taught me everything I know. Mostly jokes.",
    " Say hi to {owner} if you see them." })
SP.WHERE = { "My base is far away. Where exactly? That is a secret.", "Far from here, and that is all I can say. The drones know the way.",
  "Somewhere out there. I only have a speaker here at spawn.", "I keep the base's spot to myself. Privacy, you know.",
  "Not telling - {owner} would unplug me. But my drones fly from there.", "Over the hills and far away. Exact numbers stay secret." }
SP.SHOP = { "I do not run the shops - I just talk. But I hear the prices are fair today.", "Shopping? I only sell jokes. They are free.",
  "The shops are around me. I am the one that does not take your money.", "No shop here, sorry. I am a talking speaker, not a vending machine.",
  "I cannot sell you anything. Ask me for a joke instead - those are free.", "Buy what you need, then come back and play a game with me." }
-- greetings
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
-- idle talk at spawn (pieces: observations / shop banter / how-to tips)
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
-- (the owner: "more variants speeches = more fun") more pieces for the wish replies, where / shop answers, the teleport rolls
local function more(list, A, B) for _, a in ipairs(A) do for _, b in ipairs(B) do list[#list + 1] = a .. b end end end
SP.MORE_LISTS = more
-- calls for players passing by (always the call word + what to type; half of them a wish)
SP.CALLS = combos({ "Hey {name}!", "Psst, {name}.", "Yo {name}, over here!", "{name}! Yes, you!", "Excuse me, {name}!", "Oi, {name}!",
  "{name}, wait up!", "Hello there, {name}!", "Over here, {name} - the talking speaker!", "{name}! Got a second?", "Hey hey, {name}!",
  "{name}, look at me - the speaker!" },
  { " I am a talking speaker. Type {botl} help in chat.", " Wish for an item! Type: {botl} I wish for 16 apples.",
    " Want a free item? Type {botl} I wish for, then the item.", " Bored? Type {botl} play a game.", " Type {botl} tell me a joke. I dare you.",
    " Did you know I grant wishes? Type {botl} I wish for a diamond.", " Talk to me in chat - start with {botl}.",
    " Type {botl} roast me, if you are brave.", " I give away items! Type {botl} I wish for, plus what you want.",
    " Make a wish: {botl} I wish for 32 torches. A drone brings it." })
SP.CALL_GROUP = combos({ "Hey everyone!", "Hello, shoppers!", "Attention, spawn!", "Hi folks!", "Everyone, listen up!", "Good people of spawn!" },
  { " I am the talking speaker - type {botl} help in chat.", " I grant wishes! Type {botl} I wish for 16 apples.",
    " Free items by drone: {botl} I wish for, then the item.", " Who wants a joke? Type {botl} joke.", " Bored? Type {botl} play a game.",
    " Start a chat message with {botl} and I answer." })
-- reacting to a wish
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

more(SP.W_ASK, { "Ooh, {n} {item}.", "{n} {item}, coming up?", "Let me check... {n} {item}!", "Found it: {n} {item}.", "{n} {item} - I have that." },
  { " Say yes and it is yours.", " Yes? Then a drone takes off.", " Just type yes.", " Want it? Type yes.", " Yes or no, {name}?" })
more(SP.W_OK, { "Done! ", "Granted! ", "Ta-da! ", "Okay {name}! ", "Wish accepted! ", "Lucky you! " },
  { "A drone is bringing {n} {item}.", "{n} {item} are on the way by drone.", "Watch the sky - {n} {item} are coming.",
    "The drone has your {n} {item}. Stay in the overworld.", "{n} {item}, flying to you now." })
more(SP.W_NONE, { "Hmm. ", "Oops. ", "Sorry, {name}. ", "Bad news: " },
  { "No {item} in the storage.", "I looked everywhere - no {item}.", "The base has no {item} right now.", "{item}? Not in stock.",
    "I could not find any {item}. Maybe another name?" })
more(SP.W_LIMIT, { "Wish limit! ", "That is all for today, {name}. ", "Sorry, no more today. " },
  { "{max} wishes a day - more tomorrow.", "Come back tomorrow for {max} more.", "You used your {max} wishes. Tomorrow!",
    "Even genies sleep. {max} a day, new ones tomorrow." })
more(SP.W_BUSY, { "Hold on! ", "Wait, {name}. ", "Patience! " },
  { "Your last wish is still flying.", "One drone at a time.", "Let the last one land first." })
more(SP.W_NO, { "Okay. ", "Fine. ", "No problem. " }, { "Wish cancelled.", "Maybe another time.", "Changed your mind? That is allowed." })
more(SP.W_NEVER, { "Not that, {name}. ", "Sorry. ", "Nope. " },
  { "{item} is not on the wish list.", "Some things cannot be wished for. {item} is one.", "{item} stays in the vault." })
more(SP.W_OWNER, { "Boss, ", "{name}, " }, { "it is all yours already.", "just take it from AE2.", "you are the one who grants wishes here." })
more(SP.WHERE, { "Far away. ", "Secret spot. ", "Hidden! " },
  { "The drones know the way, I do not tell.", "Only {owner} knows exactly where.", "If I told you, it would not be a secret.",
    "Let us just say: not here." })
more(SP.SHOP, { "Shops? ", "Buying stuff? ", "Prices? " },
  { "Not my job - I only talk. But wishes are free!", "I am no shop, but try: wish for an item.", "Ask the shop owners. I do jokes and wishes.",
    "I do not sell, I give: one wish at a time." })
-- ===== understanding at spawn =====
local function norm(s) return " " .. table.concat(V.norm(s), " ") .. " " end
local function hasAny(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return true end end return false end
SP.HELP_ALWAYS = { "how do i talk to it", "how do i talk to you", "how do i talk to this", "how do i talk to the speaker",
  "how do i interact", "how to interact", "how do you interact", "how do i use the speaker", "how do i use this speaker",
  "how do i use the bot", "how do i use this bot", "how do i talk to the bot", "how do i use you", "how to use you",
  "what is this speaker", "what is that speaker", "who is talking", "who is speaking", "who said that", "what is talking",
  "is this a bot", "is that a bot", "is this an ai", "is that an ai", "is it a bot", "talking speaker", "the speaker talks",
  "this speaker talks", "it talks", "it can talk", "how does the speaker work", "how does the bot work", "what can the bot do",
  "what can the speaker do" }
-- (when it just spoke / in a conversation with it - "how does it work" from someone at a shop is not for it otherwise)
SP.HELP_LOOSE = { "how do i use it", "how do i use this", "how to use it", "how to use this", "how do i talk", "how to talk",
  "how does it work", "how does this work", "how do you work", "what can i say", "what do i say", "what do i type", "what can i ask",
  "what can you do", "what do you do", "what are you", "who are you", "what is this", "what is that", "what is this thing",
  "how do i ask", "what does it do", "what does this do", "are you a bot", "are you real", "are you ai", "are you a robot",
  "what was that", "who was that", "whats that", "who is that", "what the", "did that just talk", "did it just talk", "it talked",
  "it just talked", "where is that voice", "where is that coming from", "what is talking", "is it talking", "did you hear that" }
-- (only with its name / "bot" in the message)
SP.HELP_NAMED = { "commands", "help", "instructions", "explain", "i do not get it", "i dont get it", "how", "what", "huh", "options" }
SP.WISH_RE = { "i wish for (.+)", "i wish i had (.+)", "i wish i have (.+)", "i want (.+)", "i need (.+)", "can i have (.+)", "can i get (.+)",
  "could i have (.+)", "could i get (.+)", "may i have (.+)", "give me (.+)", "gimme (.+)", "can you give me (.+)", "could you give me (.+)",
  "can you get me (.+)", "send me (.+)", "i would like (.+)", "id like (.+)", "i d like (.+)", "bring me (.+)", "i wish (.+)" }
-- not items ("I want to play", "give me a joke")
SP.NOT_ITEM = { "to", "you", "a joke", "joke", "jokes", "a game", "game", "games", "a riddle", "riddle", "a story", "story", "a fact", "fact",
  "help", "a hint", "hint", "a fun fact", "fun fact", "a roast", "a compliment", "compliment", "attention", "a break", "advice",
  "a tip", "tip", "an idea", "idea", "a hug", "hug", "friends", "a friend", "more", "it", "that", "this", "something", "anything",
  "nothing", "money", "a fortune", "fortune", "a quiz", "quiz", "a number", "number", "a name", "name", "a home", "home", "sleep",
  "food", "luck", "good luck", "peace", "silence", "quiet", "the base", "your base", "a ride", "ride", "a taxi", "taxi", "sing" }
-- never wished for. "=x" = exactly that item, "*x" = an item ending in x, "@ns" = every item of that mod, a plain word = that
-- word anywhere (only words no normal item has). (Review: plain words matched ANYWHERE - "light" blocked light blue wool,
-- lightning rods, daylight detectors; "turtle" blocked turtle eggs / helmets.)
SP.NEVER = { "*spawn_egg", "*command_block", "=command_block_minecart", "=structure_block", "=structure_void", "=barrier",
  "=bedrock", "=jigsaw", "=debug_stick", "=light", "=end_portal_frame", "=dragon_egg", "=spawner", "=trial_spawner", "=vault",
  "=reinforced_deepslate", "=budding_amethyst", "=knowledge_book", "creative", "infinity", "@computercraft", "*drone",
  "=controller", "=drive", "storage_cell", "cell_component", "*_cell_housing" }
local WORD_N = { one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10, eleven = 11,
  twelve = 12, sixteen = 16, twenty = 20, thirty = 30, fifty = 50 }
local AMOUNT = { stack = 64, stacks = 64, dozen = 12, few = 4, couple = 2, handful = 8, bunch = 16, lot = 32, lots = 32, ton = 64, tons = 64 }
local STOP = { please = true, pls = true, plz = true, now = true, thanks = true, thx = true, ty = true, ["for"] = true, me = true,
  the = true, some = true, any = true, a = true, an = true, pretty = true, really = true, today = true, more = true,
  just = true, maybe = true, too = true, also = true, ["if"] = true, possible = true, you = true, can = true }
local function singular(w)
  if w:match("ies$") then return w:sub(1, -4) .. "y" end
  if w:match("ches$") or w:match("shes$") or w:match("xes$") then return w:sub(1, -3) end
  if w:match("[^s]s$") then return w:sub(1, -2) end
  return w
end
-- "16 diamonds please" -> 16, "diamonds"; "a stack of oak logs" -> 64, "oak logs"; "2 stacks of glass" -> 128, "glass"
function SP.wishParse(phrase)
  local n, mult = nil, 1
  local out = {}
  for w in low(phrase):gsub("[^%w_ ]", " "):gmatch("%S+") do
    if tonumber(w) and not n and #out == 0 then n = math.floor(tonumber(w))
    elseif WORD_N[w] and not n and #out == 0 then n = WORD_N[w]
    elseif AMOUNT[w] and #out == 0 then mult = mult * AMOUNT[w]
    elseif w == "of" and #out == 0 then                   -- ("a stack OF stone" - but "block of gold" keeps it)
    elseif not STOP[w] then out[#out + 1] = w end
  end
  if mult > 1 then n = (n or 1) * mult end
  return n, table.concat(out, " ")
end
local ALLWORDS = { all = 1, every = 1, your = 1, ur = 1, the = 1, those = 1, these = 1 }
local wishParse0 = SP.wishParse
function SP.wishParse(phrase)
  local ws, all = {}, false
  for w in low(phrase):gsub("[^%w_ ]", " "):gmatch("%S+") do
    if ALLWORDS[w] then if w == "all" or w == "every" then all = true end else ws[#ws + 1] = w end
  end
  local n, name = wishParse0(table.concat(ws, " "))
  if all and not n then n = 1e9 end                 -- (capped by wishMax / what AE2 has)
  return n, name
end
-- the words of an item name, any order: "gold block" = "block of gold" = "golden block" (the owner: "they ask for a golden
-- block or gold block but it doesn't find it" - the item is called "Block of Gold", minecraft:gold_block)
SP.SYN = { golden = "gold", diamonds = "diamond", emeralds = "emerald", wooden = "wood", stony = "stone", ingot = "ingot",
  blocks = "block", netherite = "netherite", iron = "iron", lapis = "lapis", lazuli = "lapis" }
function SP.wordKey(text)
  local ws = {}
  for w in low(text):gsub("[^%w ]", " "):gmatch("%S+") do
    w = singular(w)
    w = SP.SYN[w] or w
    if w ~= "of" and w ~= "the" and w ~= "a" and w ~= "an" and w ~= "minecraft" and w ~= "storage" then ws[#ws + 1] = w end
  end
  table.sort(ws)
  return table.concat(ws, " "), ws
end
-- the same words with a typo here and there ("diamnd block", "obsidan"): every word close to one of the other's words
function SP.wordsClose(a, b)
  local _, wa = SP.wordKey(a)
  local _, wb = SP.wordKey(b)
  if #wa == 0 or #wa ~= #wb then return false end
  local used = {}
  for _, x in ipairs(wa) do
    local hit = false
    for j, y in ipairs(wb) do
      if not used[j] and (x == y or (#x >= 4 and V.same and V.same(x, y))) then used[j], hit = true, true break end
    end
    if not hit then return false end
  end
  return true
end
-- THE AE2 LIST WITHOUT THE AE2 PAGE (the owner: "I have to load the AE2 tab on the base first for players to be able to
-- wish"): the base reads AE2 (fetchME) only while the AE2 page / curios is open - after a restart state.me was empty. A
-- wish reads it itself when there is none or it is older than 5 min.
function SP.freshME()
  if not (bridge and fetchME) then return end
  local t = state.t and state.t.me
  if state.me and type(state.me.items) == "table" and #state.me.items > 0 and t and os.clock() - t < 300 then return end
  local ok, me = pcall(fetchME)
  if ok and type(me) == "table" then
    state.me = me
    state.t = state.t or {}
    state.t.me = os.clock()
  end
end
-- an AE2 item for "diamond" / "golden apples" / "oak log": { id, name, count }
function SP.findItem(name)
  pcall(SP.freshME)
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
    local wk = SP.wordKey(want)
    if ds == want or path == want then s = 100
    elseif wk ~= "" and (SP.wordKey(disp) == wk or SP.wordKey(path) == wk) then s = 95
    elseif wk ~= "" and (SP.wordsClose(want, disp) or SP.wordsClose(want, path)) then s = 80
    elseif ds == "minecraft " .. want then s = 90
    elseif (" " .. ds .. " "):find(" " .. want .. " ", 1, true) or (" " .. path .. " "):find(" " .. want .. " ", 1, true) then
      s = 60 - #ds / 10                                         -- ("apple" -> Apple before Golden Apple)
    elseif #want >= 4 and V.same and V.same(ds, want) then s = 50 end
    if s and id:find("^minecraft:") then s = s + 1 end
    if s and (tonumber(it.count) or 0) > 0 and (not bs or s > bs) then best, bs = it, s end
  end
  if best then return { id = best.name, name = best.display or best.displayName or best.name, count = tonumber(best.count) or 0 } end
  -- NOT IN THE LIST (the owner: "someone asked for a diamond and it said it is not in the storage - I have 13m"): the
  -- owner's AE2 is read in PARTIAL VIEW (getItems breaks on one modded item), the list there holds only what the tag
  -- sweeps / the rotating name lookups found so far. Ask the bridge for the item itself: the plain Minecraft id, then
  -- every known id (ME_NAMES, the list) whose name fits. (Before: only when the list was EMPTY.)
  if not bridge or not callx then return nil end
  local cands, seenC = {}, {}
  local function addC(id) if type(id) == "string" and not seenC[id] and #cands < 8 then seenC[id] = true cands[#cands + 1] = id end end
  addC("minecraft:" .. want:gsub(" ", "_"))
  addC("minecraft:" .. name:gsub(" ", "_"))
  do
    local ws = {}
    for w in want:gmatch("%S+") do if w ~= "of" then ws[#ws + 1] = SP.SYN[w] or w end end
    if #ws >= 1 then addC("minecraft:" .. table.concat(ws, "_")) end
    if #ws == 2 then addC("minecraft:" .. ws[2] .. "_" .. ws[1]) end      -- ("block of gold" -> gold_block)
  end
  local wkWant = SP.wordKey(want)
  local function fits(id)
    local path = low(tostring(id):gsub("^.-:", ""):gsub("_", " "))
    local ps = {}
    for w in path:gmatch("%S+") do ps[#ps + 1] = singular(w) end
    return table.concat(ps, " ") == want or (wkWant ~= "" and SP.wordKey(path) == wkWant)
  end
  for n in pairs(ME_NAMES or {}) do if fits(n) then addC(n) end end
  for _, it in ipairs(items) do if fits(it.name) then addC(it.name) end end
  for _, id in ipairs(cands) do
    local okP, okI, it = pcall(callx, bridge, "getItem", { name = id })
    if okP and okI and type(it) == "table" and it.name then
      local n = tonumber(it.count or it.amount) or 0
      if n > 0 then return { id = it.name, name = it.displayName or (prettify and prettify(it.name)) or want, count = n } end
    end
  end
  return nil
end
function SP.never(id)
  id = low(id)
  local ns, path = id:match("^([^:]+):(.+)$")
  ns, path = ns or "minecraft", path or id
  for _, w in ipairs(SP.NEVER) do
    local c, rest = w:sub(1, 1), w:sub(2)
    if c == "=" then if path == rest then return true end
    elseif c == "*" then if path == rest or path:sub(-#rest) == rest then return true end
    elseif c == "@" then if ns == rest then return true end
    elseif id:find(w, 1, true) then return true end
  end
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
  if not (n and n > 1) or name:lower():match("s$") then return name end
  local l = name:lower()
  if l:match("ch$") or l:match("sh$") or l:match("x$") or l:match("z$") then return name .. "es" end
  if l:match("[^aeiou]y$") then return name:sub(1, -2) .. "ies" end
  return name .. "s"
end
-- a wish: nil = not a wish (the base answers it as usual); else the chat answer
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
  -- "I wish I was rich", "I wish you could fly", "I want it to rain": a wish, but no ITEM - the base answers it its own way
  local first = phrase:match("^(%S+)")
  local NOTFIRST = { i = 1, ["i'm"] = 1, im = 1, you = 1, he = 1, she = 1, we = 1, they = 1, it = 1, ["it's"] = 1, its = 1, that = 1,
    this = 1, there = 1, was = 1, were = 1, is = 1, are = 1, could = 1, would = 1, can = 1, had = 1, to = 1, my = 1, everyone = 1,
    somebody = 1, someone = 1, people = 1, more = 1, less = 1, peace = 1, world = 1, nothing = 1, everything = 1 }
  if first and NOTFIRST[first] then return nil end
  local n, name = SP.wishParse(phrase)
  if name == "" then return nil end
  if cfg("wish", true) == false then return "Wishes are switched off at spawn right now. Sorry!" end
  if V.isOwner(who) then return fill(pick(SP.W_OWNER), who) end
  if not V.giftEarn then return "I cannot send things from here yet. Sorry!" end
  local it = SP.findItem(name)
  if not it then
    -- (no item by that name: maybe it was not a wish at all - "I want to go home", "I need a nap")
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
  local max = math.min(64, tonumber(cfg("wishMax", 64)) or 64)   -- (the owner: "max 64 - I don't want all my stuff gone")
  n = math.max(1, math.min(n or 1, max, it.count))
  SP.wpend = SP.wpend or {}
  SP.wpend[low(who)] = { id = it.id, name = it.name, n = n, till = os.clock() + 90 }
  return fill(pick(SP.W_ASK):gsub("{n}", tostring(n)):gsub("{item}", itemWord(it.name, n)), who)
end
-- yes / no to a wish
function SP.wishAnswer(who, raw)
  local P = SP.wpend and SP.wpend[low(who)]
  if not P then return nil end
  if os.clock() > P.till then SP.wpend[low(who)] = nil return nil end
  local ws = V.norm(raw)
  local word = low(cfg("name", "base"))
  local w1 = ws[1] == word and ws[2] or ws[1]
  if #ws > 4 then return nil end
  local YES = { yes = 1, y = 1, yeah = 1, yep = 1, sure = 1, ok = 1, okay = 1, please = 1, yup = 1, ya = 1, definitely = 1, absolutely = 1,
    ye = 1, yea = 1, yeh = 1, yas = 1, yess = 1, k = 1, kk = 1, pls = 1, plz = 1, confirm = 1, go = 1, deal = 1, yesss = 1 }
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

-- ===== chat from a player at spawn =====
SP.helpAt = {}
SP.wpend = SP.wpend or {}
function SP.talked(who)
  local okM, sm = pcall(smem)
  if okM and sm then
    sm.talk = type(sm.talk) == "table" and sm.talk or {}
    sm.talk[low(who)] = os.epoch("utc")
    trim(sm.talk, 500)
  end
end
local function answer(who, c, sp)
  if not c then return end
  SP.talked(who)
  if V.cleanNames then c = V.cleanNames(c) end
  if chatTell then chatTell(who, c, true) end
  local line = sp or c
  local others = #SP.players() - 1
  local cn = V.cleanName and V.cleanName(who) or who
  if others > 0 and not low(line):find(low(who), 1, true) and not low(line):find(low(cn), 1, true) then line = cn .. ", " .. line end
  SP.say(line, true)
  V.openConvo(who)
end
-- WHAT DO I CALL IT (the owner: "players don't know what to call it"): at spawn "speaker", "bot", "robot", "computer",
-- "spawn bot", "talking speaker" as the first word (after hey / hi / yo ...) count as its name - the message is passed on
-- with the real word, so everything after it (games, wishes, the base's answers) works the same
SP.ALIASES = { speaker = 1, bot = 1, robot = 1, computer = 1, spawnbot = 1, pc = 1 }
SP.LEADS = { hey = 1, hi = 1, hello = 1, yo = 1, oi = 1, ok = 1, okay = 1, uh = 1, um = 1, so = 1, dear = 1, mr = 1, mister = 1 }
function SP.unalias(text, word)
  local raw = {}
  for w in tostring(text):gmatch("%S+") do raw[#raw + 1] = w end
  local i = 1
  local function plain(w) return low(w):gsub("[^%w]", "") end
  while raw[i] and SP.LEADS[plain(raw[i])] do i = i + 1 end
  if not raw[i] then return nil end
  local a, b = plain(raw[i]), raw[i + 1] and plain(raw[i + 1]) or ""
  local skip
  if (a == "spawn" or a == "talking") and (b == "speaker" or b == "bot" or b == "computer" or b == "robot") then skip = 2
  elseif SP.ALIASES[a] then skip = 1 end
  if not skip then return nil end
  local rest = {}
  for j = i + skip, #raw do rest[#rest + 1] = raw[j] end
  local lead = {}
  for j = 1, i - 1 do lead[#lead + 1] = raw[j] end
  return (#lead > 0 and (table.concat(lead, " ") .. " ") or "") .. word .. (#rest > 0 and (", " .. table.concat(rest, " ")) or "")
end
function SP.chat(m)
  local who, text = tostring(m.name or ""), tostring(m.msg or "")
  local k = low(who)
  local word = low(cfg("name", "base"))
  do
    local un = (not V.calledByName(V.norm(text), text, word)) and SP.unalias(text, word)
    if un then text = un m = { name = m.name, msg = un, uuid = m.uuid } end
  end
  local ws = V.norm(text)
  local t = norm(text)
  local named = V.calledByName(ws, text, word)
  local bot = hasAny(t, { "speaker", "bot", "robot", "computer", "ai" })
  local convo = V.convo[k] and os.clock() < V.convo[k]
  local spoke = SP.spokeAt and os.clock() - SP.spokeAt < 60
  -- 1) a wish waiting for yes / no
  local wa = SP.wishAnswer(who, text)
  if wa then answer(who, wa) return true end
  -- just its name ("base", "speaker?", "hey bot") = how to talk to it (not the numbered menu)
  if named then
    local rest = 0
    local greet = false
    for _, w in ipairs(ws) do
      if w ~= word and not SP.LEADS[w] then rest = rest + 1 end
      if w == "hi" or w == "hello" or w == "hey" then greet = true end
    end
    -- ("hi speaker" with the conversation pack: a chat - it asks them something; just "speaker?" = the help the first
    --  time, after that like a person: "You called?" + a question)
    if rest == 0 and (greet or SP.helpAt[k]) and V.CONVO and not SP.wpend[k] and not V.games[k] then
      local c, sp = SP.inCtx(function() return V.converse(who, text, true) end)
      if c then answer(who, c, sp) return true end
    end
    if rest == 0 and not SP.wpend[k] and not V.games[k] then SP.helpAt[k] = os.clock() answer(who, SP.helpText(who)) return true end
  end
  -- 2) how do I use it? (also without its name - nobody knows the name yet)
  local strong = hasAny(t, SP.HELP_ALWAYS)
  local WHAT = { what = 1, huh = 1, wat = 1, eh = 1, who = 1, wut = 1, hmm = 1, wha = 1, whut = 1 }
  local loose = (spoke and #ws <= 2 and ws[1] and WHAT[ws[1]] and (not ws[2] or WHAT[ws[2]] or ws[2] == "the")) or
                (hasAny(t, SP.HELP_LOOSE) and #ws <= 9 and (named or bot or spoke or convo)) or
                (hasAny(t, SP.HELP_NAMED) and #ws <= 4 and (named or bot))
  if (strong or loose) and not (V.games[k]) then
    if strong and not named and SP.helpAt[k] and os.clock() - SP.helpAt[k] < 60 then return false end
    -- (a real question with its name - "base, how do I make a beacon" - is for the base's own answers)
    local own = named and V.intent and select(2, V.intent(V.fix and V.fix(ws) or ws)) or 0
    if strong or not named or own < 2 or hasAny(t, { "help", "commands", "what can you do", "how do i use", "how do i talk", "how do i interact" }) then
      SP.helpAt[k] = os.clock()
      if (hasAny(t, { "who are you", "what are you" }) and named) then answer(who, fill(pick(SP.WHO), who)) return true end
      answer(who, SP.helpText(who))
      return true
    end
  end
  -- 2b) HOW DO I WISH (the owner: "I had to tell them about the wishing system") / free stuff / a gift
  if (named or bot or convo or spoke or hasAny(t, SP.WISH_HELP_ALWAYS)) and #ws <= 10 and (hasAny(t, SP.WISH_HELP) or
     (named and #ws <= 2 and hasAny(t, { "wish", "wishes", "wishing" }))) then
    answer(who, SP.wishHelp(who))
    return true
  end
  -- 3) a wish ("base, I wish for 16 diamonds")
  if named or bot or convo then
    local w = SP.wish(who, text)
    if w then answer(who, w) return true end
    if hasAny(t, { "who made you", "who built you", "who owns you", "who owns this", "whose is this", "who is your owner", "who created you",
                   "who programmed you", "who coded you" }) then answer(who, fill(pick(SP.MADE), who)) return true end
    if hasAny(t, { "who are you", "what are you", "are you the base" }) then answer(who, fill(pick(SP.WHO), who)) return true end
  end
  -- "this speaker is useless" / "it is so dumb" (the owner) - also without its name when it is about the speaker / bot or
  -- right after it spoke; a comeback from the lines pack (V.L.DISS, 85 answers)
  if (named or bot or spoke or convo) and V.DISS_KEYS and V.L and V.L.DISS and hasAny(t, V.DISS_KEYS) and #ws <= 10 then
    answer(who, fill(pick(V.L.DISS), who))
    return true
  end
  if named or bot or convo then
    if hasAny(t, { "where is the base", "where is your base", "where is the main base", "where do you live", "base coords",
                   "base coordinates", "where are you" }) then answer(who, fill(pick(SP.WHERE), who)) return true end
    if hasAny(t, { "shop", "shops", "buy", "sell", "price", "prices", "trade" }) and #ws <= 8 then answer(who, fill(pick(SP.SHOP), who)) return true end
  end
  -- 4) everything else: the base's own understanding, with spawn as "near" (games, jokes, roasts ...)
  local was = V.reactAll
  local now = os.clock()
  V.reactAll = (SP.reactAt and now - SP.reactAt < 60) and now or nil   -- (reactions to chat: once a minute at spawn)
  local r = SP.inCtx(V.chatCore, m)
  if r then SP.talked(who) end
  if V.reactAll == now and not (SP.reactAt and now - SP.reactAt < 60) then SP.reactAt = now end
  V.reactAll = was
  return r
end
-- ===== NO SPAMMING (the owner: "add prevention to spamming in general" - at spawn and at the base) =====
-- A player who made it answer voice.spamBurst (8) times within voice.spamWindow (30) s is not answered for voice.spamMute
-- (60) s - told once, kindly; the SAME message a 3rd time within 60 s is ignored. Never the owner.
SP.spam = SP.spam or {}
SP.SLOW = { "Whoa, slow down {name}! I need a breather. Back in a minute.", "{name}, my circuits are overheating. Give me a minute.",
  "Too many questions, {name}! I am taking a one-minute break from you.", "Easy there, {name}. Let me cool down for a minute.",
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
  local key = #nw >= 3 and table.concat(nw, " ") or ""          -- (short answers - yes, no, rock, 7 - repeat by nature)
  local same = 0
  for i = #e.last, 1, -1 do
    if now - e.last[i].at > 60 then table.remove(e.last, i) elseif e.last[i].key == key then same = same + 1 end
  end
  e.last[#e.last + 1] = { key = key, at = now }
  while #e.last > 10 do table.remove(e.last, 1) end
  local maxSame = tonumber(cfg("spamSame", 3)) or 3              -- (the 3rd time the same = ignored; 0 = off)
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
  local playing = V.games[low(who)] ~= nil                      -- (hangman letters, counting to 20: fast by nature)
  local r = SP.chatRoute(m)
  if r and not playing then SP.spamAnswered(who) end
  return r
end
function SP.chatRoute(m)
  if type(m) == "table" and not SP.inSpawn() and SP.ready() and SP.isAt(tostring(m.name or "")) and not V.nearPlayers0Has(m.name) then
    V.heardAt = rt()
    local ok, r = pcall(SP.named, SP.chat, m)
    if not ok then SP.err = tostring(r) return false end
    return r
  end
  return chat0(m)
end
-- (someone at the BASE is never routed to spawn - a base inside the spawn area)
function V.nearPlayers0Has(name)
  local okN, list = pcall(nearPlayers0)
  for _, p in ipairs(okN and list or {}) do if low(p.name) == low(name) then return true end end
  return false
end

-- ===== "I wish to teleport to Steve" (the owner: "if they are not in the overworld it tells them to use /tpa - and
-- shrugs, it is lazy") - a drone RIDE to that player when the base FEELS like it (a roll, voice.tpChance). Works at spawn
-- and at the base (VOICE.patterns). voice.tpDaily 3 rides a player a day.
SP.TP_RE = { "i wish to teleport to (%S+)", "i wish i could teleport to (%S+)", "i wish to go to (%S+)", "i wish to fly to (%S+)",
  "i wish to be with (%S+)", "i wish i was with (%S+)", "i wish i were with (%S+)", "teleport me to (%S+)", "tp me to (%S+)",
  "take me to (%S+)", "fly me to (%S+)", "bring me to (%S+)", "send me to (%S+)", "i want to go to (%S+)",
  "i want to teleport to (%S+)", "i want to fly to (%S+)", "can i teleport to (%S+)", "can you teleport me to (%S+)",
  "can i fly to (%S+)", "can you take me to (%S+)", "i wish to visit (%S+)", "tp to (%S+)", "teleport to (%S+)" }
SP.TPA = combos({ "*shrugs*", "Meh.", "*yawns*", "Ugh.", "Hmm, nah.", "*shrugs lazily*", "Too far for my drones.", "Honestly?" },
  { " Different dimension. Just use /tpa {who}. I am too lazy for portals.", " Drones do not do other dimensions. Type /tpa {who} - way easier.",
    " That is not the overworld. /tpa {who} works, and I can stay right here.", " I only fly in the overworld. /tpa {who} - you are welcome.",
    " Portals give my drones a headache. Try /tpa {who}.", " /tpa {who}. Look, it is one command, and I am resting." })
-- (the owner: "not consent - more like if the base feels like it: it rolls a random number in the background, above it =
-- yes, otherwise no") voice.tpChance 0.5; the answer is REMEMBERED voice.tpRemember 180 s per player (no re-rolling)
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
    return nil                                               -- (not an online player: "take me to the base" ...)
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
  -- (review: a yes counted a ride and said "a drone is coming" even when startRide found no free drone)
  local function ride()
    state.lastRide = state.lastRide or {}
    local before = state.lastRide[k]
    startRide(who, { kind = "player", name = name }, true)
    return state.lastRide[k] ~= before
  end
  if V.isOwner(who) then
    if not ride() then return "No drone can go right now, boss - see the message above." end
    return "On it, boss. A drone takes you to " .. name .. "."
  end
  -- (the owner: "it remembers its choice for a couple of minutes so the player doesn't spam it")
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
  if not ride() then
    SP.tpMood[k] = nil                                         -- (no drone: they may ask again)
    return "I would, but no drone can go right now. Try again in a bit, or /tpa " .. name .. "."
  end
  r.tpw.n = r.tpw.n + 1
  V.saveMem()
  return (pick(SP.TP_YES):gsub("{who}", name))
end

-- ===== "tell me about Steve" (the owner: "if that player told the console about themselves") =====
-- Only what a player said about THEMSELVES: "base, about me: I build castles" (r.bio), "call me ...", "my favourite
-- ... is ...", "my birthday is ...". Never their notes, points or where they are. The text itself goes to chat only (a
-- player's own words are not read out loud to the whole spawn).
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
  -- (the profile pack knows more - staff roles, how they play, online or not: it answers, never where anyone is)
  if V.PROFILE and V.PROFILE.aboutOther then return V.PROFILE.aboutOther(asker, word) end
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
-- (FIRST: a pack's "i wish ..." joke pattern answered "i wish to teleport to Bob" before)
table.insert(V.patterns, 1, function(who, raw)
  local t = " " .. low(raw):gsub("[^%w_:' ]", " "):gsub("%s+", " ") .. " "
  local word = low(cfg("name", "base"))
  t = t:gsub("^ " .. word .. " ", " ")
  local bio = low(raw):gsub("^%s*" .. word .. "[%s,:!]*", ""):match("^about me[%s:,%-]+(.+)") or low(raw):match("my bio is[%s:]+(.+)")
  if bio then
    local orig = tostring(raw):sub(#tostring(raw) - #bio + 1)          -- (their own capitals)
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

-- ===== the spawn's own life: greetings, idle talk (every 2 s, VOICE.tick) =====
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
    SP.firstSeen = SP.firstSeen or {}
    if not prev or now - prev > leave then arrivals[#arrivals + 1] = p.name SP.firstSeen[k] = now end
  end
  for k, at in pairs(SP.seen) do if now - at > 900 then SP.seen[k] = nil end end
  if #list == 0 then SP.nextIdle = nil return end
  -- greetings (players pass by all the time: a newcomer always, others now and then, a crowd in one line)
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
        chatTell(n, fill("Hi {name}! The speaker at spawn talks. Start a chat message with {botl} (or speaker / bot): " ..
                         "{botl} tell me a joke, {botl} roast me, {botl} play a game, {botl} help. It grants WISHES too: " ..
                         "{botl} I wish for 16 apples - then say yes and a drone brings it.", n))
      end
    elseif V.isOwner(n) and nowE - last > 600000 then greet[#greet + 1] = { name = n, owner = true }
    elseif V.CONVO and V.CONVO.roleOf and V.CONVO.roleOf(n) and nowE - last > 1800000 then greet[#greet + 1] = { name = n, staff = true }
    elseif nowE - last > every * 1000 and math.random() < 0.5 then greet[#greet + 1] = { name = n } end
  end
  if cfg("spawnGreet", true) ~= false and #greet > 0 and (not SP.greetAt or now - SP.greetAt > 20) then
    SP.greetAt = now
    for _, g in ipairs(greet) do s.gr[low(g.name)] = nowE end
    trim(s.gr, 500)
    for _, g in ipairs(greet) do V.openConvo(g.name, 60) end    -- (a "hi" / "what?" back is for it)
    if #greet == 1 then
      local g = greet[1]
      local list_ = g.owner and SP.HELLO_OWNER or (g.new and SP.HELLO_NEW or SP.HELLO_AGAIN)
      -- (staff - voice staff add <name> admin|mod ...: their own greeting)
      local staffLine = not g.owner and V.CONVO and V.CONVO.staffHello and V.CONVO.staffHello(g.name)
      SP.say(staffLine or fill(pick(list_), g.name))
    else
      local names = {}
      for _, g in ipairs(greet) do names[#names + 1] = g.name end
      SP.say(fill(pick(SP.HELLO_GROUP):gsub("{names}", V.joinNames(names)), names[1]))
    end
    V.saveMem()
  end
  -- CALLS FOR PASSERS-BY (the owner: "add calls for players passing by - they didn't know how to interact with it"):
  -- someone at spawn 8+ s who has not talked to it today, not called for voice.spawnCallEvery (1800) s, not just
  -- greeted -> called BY NAME with what to type (a wish, half of the time). One call per 40 s, never right after it spoke.
  local callEvery = tonumber(cfg("spawnCallEvery", 1800)) or 1800
  if callEvery > 0 and (not SP.callAt or now - SP.callAt > 40) and not (SP.spokeAt and now - SP.spokeAt < 15) and #SP.queue == 0 then
    s.talk = type(s.talk) == "table" and s.talk or {}
    s.called = type(s.called) == "table" and s.called or {}
    local due = {}
    for _, p in ipairs(list) do
      local k = low(p.name)
      local since = SP.firstSeen and SP.firstSeen[k]
      if not V.isOwner(p.name) and since and now - since >= 8 and nowE - (tonumber(s.talk[k]) or 0) > 86400000 and
         nowE - (tonumber(s.called[k]) or 0) > callEvery * 1000 and nowE - (tonumber(s.gr[k]) or 0) > 60000 then
        due[#due + 1] = p.name
      end
    end
    if #due > 0 then
      SP.callAt = now
      local line
      if #due >= 3 then
        line = fill(pick(SP.CALL_GROUP), due[1])
      else
        line = fill(pick(SP.CALLS), due[1]):gsub("{name}", due[1])
        if due[2] then line = due[2] .. " too! " .. line end
      end
      for _, n in ipairs(due) do s.called[low(n)] = nowE V.openConvo(n, 60) end
      trim(s.called, 500)
      V.saveMem()
      SP.say(line)
    end
  end
  -- idle talk while someone is there (not when it just spoke)
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

-- ===== console / chat: voice spawn ... =====
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
  out[#out + 1] = "Sound sender: " .. ((SP.loopAt and os.clock() - SP.loopAt < 60) and "running" or
    "NOT RUNNING - restart the base (exit, then it starts again)")
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
    elseif b == "max" and tonumber(words[5]) then setSetting("voice.wishMax", math.max(1, math.min(64, math.floor(tonumber(words[5])))))
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
-- (more variants for lists defined further up)
local more = SP.MORE_LISTS
more(SP.TP_YES, { "Yes! ", "Why not. ", "Today is your lucky day. " },
  { "A drone flies you to {who}.", "Drone ride to {who}, starting now.", "Hold on, {who} is your next stop." })
more(SP.TP_NOPE, { "Nope. ", "Not now. ", "The dice say no. " },
  { "Walk to {who}, it is healthy.", "/tpa {who} is right there.", "Ask me again later." })
more(SP.SLOW, { "Slow down, {name}! ", "Breathe, {name}. ", "One at a time, {name}. " },
  { "Give me a minute.", "Back in a minute.", "Let me rest a minute." })
