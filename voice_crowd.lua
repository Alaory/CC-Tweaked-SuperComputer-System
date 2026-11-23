-- voice_crowd.lua  -  A CROWD AT SPAWN (an add-on file on a data floppy or a storage helper, loaded after voice_spawn.lua; see
-- VOICE_FILES in base_theme.lua).
--
-- The owner: "sometimes there might be a lot of players at spawn fighting / joking etc - can you add some stuff for this?"
-- 1) A CROWD (voice.crowdMin 3+ players at spawn): it notices the crowd growing ("Look at this crowd!"), talks to the group
--    now and then, and does NOT talk over everyone: at most voice.crowdSpeak (4) spoken answers per 20 s (more go to chat
--    only), its own lines at most one per 25 s.
-- 2) FIGHTS: from the Player Detector's health readings - two or more players near each other losing health within 12 s =
--    a fight: a commentator ("Fight at spawn! Steve versus Alex!", "Steve takes a hit!", "Alex is down to 2 hearts!"), a
--    knockout (low health, then full health at once = a respawn, or 0) = "Steve is down! Alex wins this round." A SCOREBOARD
--    for the session (memory only - no rewards at spawn). "speaker, duel Alex" / "1v1 Alex" = a refereed duel: a countdown,
--    the first one down loses, 3 min = a draw.
-- 3) JOKING: laughter from several players ("lol", "haha" ...), trash talk ("ez", "noob", "skill issue"), "gg", fight talk,
--    a very busy chat - each gets a short SPOKEN comment now and then (never in chat; minutes apart). GROUP GAMES (called
--    by name / "speaker" / "bot"): "group quiz" (5 questions for everyone at spawn, the first right answer wins the round),
--    "roast battle Alex" (a roast for each, then the crowd votes 1 or 2), "scoreboard" / "who is winning".
-- No points, gifts or friendship from any of it (spawn gives no rewards).
local V = VOICE
local SP = V and V.SPAWN
if not (V and SP and SP.chat and SP.players and SP.say) then return end
V.packs = V.packs or {}
V.packs["voice_crowd.lua"] = { version = 1 }
local CR = {}
V.CROWD = CR
local function pick(l) return V.pick(l) end
local function fill(l, who) return V.fill(l, who) end
local function low(s) return tostring(s or ""):lower() end
local function T(ws) return " " .. table.concat(ws, " ") .. " " end
local function has(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return p end end return nil end
local function now() return V.rt and V.rt() or os.epoch("utc") / 1000 end
local function cfg(k, d) local v = V.cfg(k, d) if v == nil then return d end return v end
local function combos(A, B) local out = {} for _, a in ipairs(A) do for _, b in ipairs(B) do out[#out + 1] = a .. b end end return out end
local function cleanN(n) return V.cleanName and V.cleanName(n) or tostring(n) end
local function joinAnd(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- ===== who is at spawn, how many =====
function CR.enabled() return cfg("crowd", true) ~= false end
function CR.count() local okP, l = pcall(SP.players) return okP and #l or 0 end
function CR.on() return CR.enabled() and CR.count() >= (tonumber(cfg("crowdMin", 3)) or 3) end
local function atSpawn(name) local ok, r = pcall(SP.isAt, name) return ok and r end
-- a player at spawn from a word (exact, the name without digits, a unique start of 3+ letters)
CR.NOT_NAME = { me = 1, you = 1, him = 1, her = 1, them = 1, us = 1, the = 1, a = 1, an = 1, with = 1, against = 1, vs = 1, versus = 1,
  everyone = 1, everybody = 1, someone = 1, somebody = 1, anyone = 1, anybody = 1, all = 1, yourself = 1, myself = 1, ["then"] = 1,
  now = 1, please = 1, pls = 1, plz = 1, again = 1, too = 1, my = 1, your = 1, this = 1, that = 1, ["and"] = 1, ["or"] = 1, it = 1 }
function CR.findHere(word, not1)
  local w = low(word):gsub("[^%w_]", "")
  if #w < 2 or CR.NOT_NAME[w] then return nil end
  local okP, list = pcall(SP.players)
  local hit
  for _, p in ipairs(okP and list or {}) do
    local n = low(p.name)
    if n ~= low(not1) then
      if n == w or low(cleanN(p.name)) == w then return p.name end
      if #w >= 3 and n:sub(1, #w) == w then
        if hit and low(hit) ~= n then return nil end
        hit = p.name
      end
    end
  end
  return hit
end

-- ===== 1) not talking over everyone =====
CR.spoke = {}
local say0 = SP.say
SP.say = function(text, answer)
  if CR.on() then
    local t = now()
    if answer and not CR.urgent then
      local keep = {}
      for _, x in ipairs(CR.spoke) do if t - x < 20 then keep[#keep + 1] = x end end
      CR.spoke = keep
      if #keep >= (tonumber(cfg("crowdSpeak", 4)) or 4) then return false end      -- (the chat answer went out already)
      CR.spoke[#CR.spoke + 1] = t
    elseif not CR.urgent then
      if CR.ownAt and t - CR.ownAt < 25 then return false end
      CR.ownAt = t
    end
  end
  return say0(text, answer)
end
-- its own crowd line. urgent = past the crowd's 25-s rule (the comments have their own minutes-long gaps); "big" = a
-- knockout / a duel's result / a countdown: also before its other talk (as an answer)
function CR.say(text, urgent)
  CR.urgent = urgent
  local ok, r = pcall(SP.say, text, urgent == "big" or nil)
  CR.urgent = nil
  return ok and r
end
-- an answer to one player (chat to them + spoken)
function CR.answer(who, c, sp)
  if SP.talked then pcall(SP.talked, who) end
  if chatTell then chatTell(who, c, true) end
  pcall(SP.say, sp or c, true)
  if V.openConvo then V.openConvo(who, 60) end
end
-- something for everyone at spawn (chat to each + spoken once)
function CR.toAll(c, sp)
  local okP, list = pcall(SP.players)
  for _, p in ipairs(okP and list or {}) do if chatTell then chatTell(p.name, c) end end
  -- (a group game's line goes before its own talk, and past the crowd's limits)
  CR.urgent = "big"
  pcall(SP.say, sp or c, true)
  CR.urgent = nil
end

-- ===== lines =====
CR.GROW = {
  [3] = combos({ "Oh, a little crowd!", "Three of you! A party is starting.", "Look, a group!", "Ooh, company - lots of it." },
    { " Welcome, everyone.", " Hi all!", " This is fun.", " Say speaker to talk to me." }),
  [5] = combos({ "Five players at spawn!", "Look at this crowd!", "Wow, spawn is busy!", "A real crowd now!" },
    { " Is there an event I do not know about?", " Welcome, everybody!", " I love it.", " Want a group quiz? Say: speaker, group quiz." }),
  [8] = combos({ "Eight of you! Spawn is packed!", "This is the biggest crowd I have seen in a while!", "So many people!" },
    { " Do not all talk at once. Okay, you can.", " Somebody start a game!", " I am a little nervous. In a good way." }),
  [12] = combos({ "Twelve players! Spawn is a festival!", "What a crowd! Is it a server event?", "A huge crowd at spawn!" },
    { " Hello, everyone!", " I need more speakers.", " The server is alive today!" }),
}
CR.IDLE = combos({ "What a crowd today.", "Spawn is the place to be today.", "So many friends at spawn.", "Hello, crowd!", "Busy, busy spawn.",
  "I love when spawn is full.", "This crowd has energy." },
  { " Want a group quiz? Say: speaker, group quiz.", " Anyone up for a roast battle? Say: speaker, roast battle and a name.",
    " If you want to duel, I can be the referee. Say: speaker, duel and a name.", " Ask me for the scoreboard any time.",
    " Be nice to each other!", " Somebody tell me a joke.", " I am keeping score, by the way.", "" })
CR.FIGHT = combos({ "Fight at spawn!", "Ooh, a fight!", "Uh oh, swords are out!", "And we have a fight!", "Here we go - a brawl!", "Fight! Fight!" },
  { " {a} versus {b}!", " {a} and {b} are at it!", " {a} against {b} - who will win?", " {a} versus {b}. I will keep score." })
CR.HIT = { "{a} takes a hit!", "Ouch, {a}!", "{a} is hurt!", "A hit on {a}!", "{a} felt that one!", "Oof, {a}!", "Watch out, {a}!",
  "{a} is taking damage!", "Nice hit on {a}!", "{a} needs to dodge!" }
CR.LOW = { "{a} is down to {h} hearts!", "{a} only has {h} hearts left!", "Careful, {a} - {h} hearts!", "{a} is in trouble - {h} hearts!",
  "{h} hearts for {a}! This could be it!" }
CR.DOWN = combos({ "{a} is down!", "And {a} goes down!", "Knockout! {a} is out!", "{a} has fallen!", "That is it for {a}!", "Down goes {a}!" },
  { " {b} wins this round!", " Point for {b}!", " {b} takes it!", " Well fought, {b}!", " {b} is on fire!" })
CR.DOWN_ALONE = { "{a} is down!", "And {a} goes down!", "Oh no, {a} has fallen!", "{a} is out! Respawn and try again.", "Down goes {a}!" }
CR.LAUGH = { "This crowd is in a good mood!", "Ha! You lot are funny.", "So much laughing - I love it.", "Whatever the joke is, I want in.",
  "Laughter at spawn! The best sound.", "You are all hilarious today.", "Stop it, you are making my speakers laugh." }
CR.TRASH = { "Ooh, trash talk! Keep it friendly, folks.", "Big words! Can you back them up?", "Easy there, champion.", "Spicy chat today!",
  "I heard that. The scoreboard will decide.", "Words are cheap. Duels are free. Just saying.", "Friendly fire only, please." }
CR.GG = { "Good game, everyone!", "GG! What a fight.", "Good game! Shake hands. Or punch fists. Gently.", "GG all round!",
  "That was a good one. GG!" }
CR.BREW = { "A fight is brewing! Say: speaker, duel and a name - I will be the referee.", "Fight talk! Want a proper duel? Say: speaker, duel and a name.",
  "Ooh. If you want to fight, do it properly: speaker, duel and a name." }
CR.BUSY = { "Wow, the chat is busy!", "So much chatting - I can barely keep up.", "Everybody is talking! Spawn is alive.", "Chat is flying today!" }
CR.DUEL = combos({ "A duel! {a} versus {b}!", "Duel time! {a} against {b}!", "{a} challenges {b}!", "Ladies and gentlemen, {a} versus {b}!" },
  { " Ready? 3... 2... 1... FIGHT!", " On my count: 3, 2, 1 - FIGHT!", " Fight fair. 3... 2... 1... GO!" })
CR.DUEL_WIN = { "{w} wins the duel!", "The winner of the duel: {w}!", "{w} takes the duel! Well fought, {l}.", "It is over - {w} wins!",
  "Victory for {w}! Good fight, {l}." }
CR.DUEL_DRAW = { "Time is up - the duel between {a} and {b} is a draw!", "Three minutes and nobody fell. A draw!", "A draw! Both still standing." }

-- ===== 2) FIGHTS from health readings =====
CR.hp, CR.hurtAt, CR.lowSaid, CR.score = {}, {}, {}, {}
local function scoreOf(n) local s = CR.score[low(n)] if not s then s = { name = n, w = 0, d = 0, q = 0 } CR.score[low(n)] = s end return s end
local function hearts(h) return math.max(0, math.floor((tonumber(h) or 0) / 2 + 0.5)) end
local function posOf(p) return p.e and p.e.p end
function CR.fightTick()
  if not CR.enabled() or cfg("fightTalk", true) == false then return end
  local t = now()
  local okP, list = pcall(SP.players)
  if not okP then return end
  local here = {}
  for _, p in ipairs(list) do
    local k = low(p.name)
    here[k] = p
    local h = tonumber(p.hp)
    local prev = CR.hp[k]
    if h then
      local mx = tonumber(p.max) or 20
      if prev and prev.h then
        -- a KNOCKOUT: 0, or low and then (nearly) full at once (a respawn)
        if h <= 0 or (h >= mx - 1 and h - prev.h >= 12 and t - prev.t <= 10) then
          if not prev.down then CR.knockout(p.name, t) end
          prev.down = h <= 0
        elseif h < prev.h - 1 then
          CR.hurtAt[k] = t
          CR.hit(p, h, t)
        end
      end
      CR.hp[k] = { h = h, t = t, down = (h <= 0) or nil, name = p.name }
    end
  end
  -- gone from spawn: a fighter whose last reading was low and fresh died and respawned somewhere else (a bed)
  for k, prev in pairs(CR.hp) do
    if not here[k] then
      local d = CR.duel
      local inIt = (d and (low(d.a) == k or low(d.b) == k)) or (CR.fight and CR.fight.who[k])
      if inIt and not prev.down and prev.h and prev.h <= 6 and t - prev.t <= 6 then CR.knockout(prev.name or k, t) end
      CR.hp[k] = nil
    end
  end
  -- a duel timed out: a draw
  local d = CR.duel
  if d and t > d.till then
    CR.duel = nil
    CR.say((pick(CR.DUEL_DRAW):gsub("{a}", cleanN(d.a)):gsub("{b}", cleanN(d.b))), "big")
  end
  if CR.fight and t - CR.fight.at > 30 then CR.fight = nil end
end
-- a hit: is it a FIGHT (another player near, hurt in the last 12 s)?
function CR.hit(p, h, t)
  local k = low(p.name)
  local okP, list = pcall(SP.players)
  local other
  local pp = posOf(p)
  for _, q in ipairs(okP and list or {}) do
    local kq = low(q.name)
    local qp = posOf(q)
    if kq ~= k and CR.hurtAt[kq] and t - CR.hurtAt[kq] <= 12 and pp and qp and math.abs(pp.x - qp.x) <= 8 and math.abs(pp.z - qp.z) <= 8 then
      other = q.name
    end
  end
  local f = CR.fight
  if other then
    if not f then
      CR.fight = { at = t, who = { [k] = p.name, [low(other)] = other } }
      CR.lowSaid = {}
      if not CR.fightSaid or t - CR.fightSaid > 60 then
        CR.fightSaid = t
        CR.say((pick(CR.FIGHT):gsub("{a}", cleanN(p.name)):gsub("{b}", cleanN(other))), "big")
      end
      return
    end
    f.at, f.who[k], f.who[low(other)] = t, p.name, other
  end
  if not CR.fight then return end
  -- commentary (not every hit: 10 s apart; low health once per fight)
  if h <= 6 and not CR.lowSaid[k] then
    CR.lowSaid[k] = t
    CR.say((pick(CR.LOW):gsub("{a}", cleanN(p.name)):gsub("{h}", tostring(hearts(h)))), true)
  elseif not CR.hitSaid or t - CR.hitSaid > 10 then
    CR.hitSaid = t
    CR.say((pick(CR.HIT):gsub("{a}", cleanN(p.name))))
  end
end
function CR.knockout(name, t)
  local k = low(name)
  CR.lowSaid[k] = nil
  -- the winner: the duel's other side, else the only other fighter
  local winner
  local d = CR.duel
  if d and (low(d.a) == k or low(d.b) == k) then
    winner = low(d.a) == k and d.b or d.a
    CR.duel = nil
    scoreOf(name).d = scoreOf(name).d + 1
    scoreOf(winner).w = scoreOf(winner).w + 1
    CR.say((pick(CR.DUEL_WIN):gsub("{w}", cleanN(winner)):gsub("{l}", cleanN(name))), "big")
    return
  end
  local f = CR.fight
  if f and f.who[k] then
    local others = {}
    for kk, n in pairs(f.who) do if kk ~= k then others[#others + 1] = n end end
    if #others == 1 then winner = others[1] end
  end
  if f and f.who[k] then scoreOf(name).d = scoreOf(name).d + 1 end     -- (a fall into lava alone is no score)
  if winner then
    scoreOf(winner).w = scoreOf(winner).w + 1
    CR.say((pick(CR.DOWN):gsub("{a}", cleanN(name)):gsub("{b}", cleanN(winner))), "big")
  elseif f and f.who[k] then
    CR.say((pick(CR.DOWN_ALONE):gsub("{a}", cleanN(name))), "big")
  end
end
function CR.scoreText()
  local list = {}
  for _, s in pairs(CR.score) do if s.w + s.d + s.q > 0 then list[#list + 1] = s end end
  if #list == 0 then return "No scores yet today. Start a duel or a group quiz!" end
  table.sort(list, function(a, b) return (a.w * 2 + a.q) > (b.w * 2 + b.q) end)
  local parts = {}
  for i = 1, math.min(6, #list) do
    local s = list[i]
    local bits = {}
    if s.w > 0 then bits[#bits + 1] = s.w .. (s.w == 1 and " win" or " wins") end
    if s.d > 0 then bits[#bits + 1] = s.d .. " down" end
    if s.q > 0 then bits[#bits + 1] = s.q .. " quiz" end
    parts[#parts + 1] = i .. ". " .. cleanN(s.name) .. " (" .. table.concat(bits, ", ") .. ")"
  end
  return "Scoreboard: " .. table.concat(parts, "  ") .. "."
end

-- ===== 3) JOKING, trash talk, busy chat: short spoken comments (never in chat) =====
CR.LAUGHW = { lol = 1, lmao = 1, lmfao = 1, haha = 1, hahaha = 1, hehe = 1, xd = 1, rofl = 1, kek = 1, lul = 1, hah = 1, ha = 1 }
CR.TRASHW = { "ez", "noob", "get good", "git gud", "skill issue", "bozo", "l bozo", "trash", "rekt", "get rekt", "too easy", "so bad", "cry about it",
  "ratio", "nub", "scrub", "sit down" }
CR.FIGHTW = { "fight me", "1v1", "1v1 me", "pvp", "duel me", "lets fight", "come fight", "wanna fight", "i will fight you", "square up" }
CR.heard = {}
function CR.listen(who, ws, t)
  if not CR.enabled() or #ws == 0 then return end
  local tn = now()
  local keep = {}
  for _, e in ipairs(CR.heard) do if tn - e.at < 20 then keep[#keep + 1] = e end end
  CR.heard = keep
  local laugh = false
  for _, w in ipairs(ws) do if CR.LAUGHW[w] or w:match("^h[ae]h[ae]") or w:match("^lo+l$") then laugh = true end end
  CR.heard[#CR.heard + 1] = { who = low(who), at = tn, laugh = laugh }
  local function once(key, gap) CR.saidAt = CR.saidAt or {} if CR.saidAt[key] and tn - CR.saidAt[key] < gap then return false end CR.saidAt[key] = tn return true end
  -- laughter from several players
  local lp, ln = {}, 0
  for _, e in ipairs(CR.heard) do if e.laugh and not lp[e.who] then lp[e.who] = true ln = ln + 1 end end
  local laughs = 0
  for _, e in ipairs(CR.heard) do if e.laugh then laughs = laughs + 1 end end
  if laughs >= 3 and ln >= 2 and once("laugh", 600) then CR.say(pick(CR.LAUGH), true) return end
  -- gg after a fight
  if (ws[1] == "gg" or t:find(" good game ", 1, true)) and CR.lastFightAt and tn - CR.lastFightAt < 120 and once("gg", 120) then CR.say(pick(CR.GG), true) return end
  if has(t, CR.TRASHW) and #ws <= 6 and once("trash", 180) then CR.say(pick(CR.TRASH), true) return end
  if has(t, CR.FIGHTW) and #ws <= 6 and not CR.duel and once("brew", 300) then CR.say(pick(CR.BREW), true) return end
  -- a very busy chat
  local pn, n = {}, 0
  for _, e in ipairs(CR.heard) do if not pn[e.who] then pn[e.who] = true n = n + 1 end end
  if #CR.heard >= 8 and n >= 3 and once("busy", 600) then CR.say(pick(CR.BUSY), true) end
end

-- ===== GROUP GAMES (called by its name / "speaker" / "bot") =====
local function quizItem(used)
  local list, fresh = {}, {}
  for _, q in ipairs(V.QUIZ or {}) do
    if type(q) == "table" and q.q and type(q.a) == "table" and #q.a > 0 then
      list[#list + 1] = q
      if not (used and used[q.q]) then fresh[#fresh + 1] = q end
    end
  end
  if #fresh > 0 then list = fresh end
  if #list == 0 then return nil end
  return list[math.random(1, #list)]
end
-- seconds until a chat line sent now reaches the last player at spawn (the Chat Box sends one line a second)
function CR.chatLag()
  return #((state and state.chatOut) or {}) * 1.1
end
function CR.quizAsk(before)
  local g = CR.quiz
  if not g then return end
  g.used = g.used or {}
  local q = quizItem(g.used)
  if not q then CR.quiz = nil if before then CR.toAll(before) end return end
  g.used[q.q] = true
  local pre = before and (before .. " ") or ""
  CR.toAll(pre .. "Group quiz, question " .. g.round .. " of " .. g.max .. ": " .. q.q .. " (First right answer wins - just type it.)",
           pre .. "Question " .. g.round .. ": " .. q.q)
  g.q, g.till = q, now() + 40 + CR.chatLag()
end
function CR.quizEnd(before)
  local g = CR.quiz
  CR.quiz = nil
  if not g then return end
  local pre = before and (before .. " ") or ""
  local best, bn = {}, 0
  for k, n in pairs(g.scores) do
    if n > bn then best, bn = { g.names[k] }, n elseif n == bn and n > 0 then best[#best + 1] = g.names[k] end
  end
  local names = {}
  for _, n in ipairs(best) do names[#names + 1] = cleanN(n) end
  if bn == 0 then CR.toAll(pre .. "The group quiz is over - nobody scored! Next time.") return end
  CR.toAll(pre .. "The group quiz is over! " .. (#names == 1 and ("The winner is " .. names[1]) or ("A tie between " .. joinAnd(names))) ..
           " with " .. bn .. (bn == 1 and " point" or " points") .. "!")
end
function CR.quizAnswer(who, ws)
  local g = CR.quiz
  if not (g and g.q) then return nil end
  local hit = false
  for _, a in ipairs(g.q.a) do
    local aw = V.norm(tostring(a))
    local all = true
    for _, x in ipairs(aw) do
      local found = false
      for _, w in ipairs(ws) do if w == x then found = true end end
      if not found then all = false end
    end
    if all and #aw > 0 then hit = true end
  end
  if not hit then return nil end
  local k = low(who)
  g.scores[k] = (g.scores[k] or 0) + 1
  g.names[k] = who
  scoreOf(who).q = scoreOf(who).q + 1
  local line = cleanN(who) .. " got it! The answer was " .. tostring(g.q.a[1]) .. "."
  g.round = g.round + 1
  if g.round > g.max then CR.quizEnd(line) return true end
  CR.quizAsk(line)
  return true
end
function CR.voteEnd()
  local v = CR.vote
  CR.vote = nil
  if not v then return end
  local na, nb = 0, 0
  for _, c in pairs(v.votes) do if c == 1 then na = na + 1 elseif c == 2 then nb = nb + 1 end end
  local a, b = cleanN(v.a), cleanN(v.b)
  if na == nb then CR.toAll("The roast battle is a tie! " .. na .. " to " .. nb .. ". You are both terrible. Lovingly.") return end
  local w = na > nb and a or b
  CR.toAll(w .. " wins the roast battle, " .. math.max(na, nb) .. " votes to " .. math.min(na, nb) .. "!")
end
local function roastOf(name)
  local list = {}
  for _, r in ipairs(V.ROASTS or {}) do list[#list + 1] = r end
  if #list == 0 then return cleanN(name) .. ", your builds are... interesting." end
  return fill(pick(list), cleanN(name))
end
function CR.called(ws, raw)
  local word = low(cfg("name", "base"))
  if V.calledByName and V.calledByName(ws, raw, word) then return true end
  local i = 1
  while ws[i] and SP.LEADS and SP.LEADS[ws[i]] do i = i + 1 end
  return ws[i] ~= nil and SP.ALIASES and SP.ALIASES[ws[i]] ~= nil
end
function CR.command(who, ws, t, raw)
  local word = low(cfg("name", "base"))
  -- (the words after its name / "speaker")
  local rest = {}
  local skipped = false
  for _, w in ipairs(ws) do
    if not skipped and (w == word or (SP.ALIASES and SP.ALIASES[w]) or (SP.LEADS and SP.LEADS[w])) then
    else skipped = true rest[#rest + 1] = w end
  end
  local r = T(rest)
  if has(r, { "scoreboard", "score", "scores", "who is winning", "leaderboard", "who won", "standings" }) then return CR.scoreText() end
  if has(r, { "group quiz", "quiz everyone", "quiz battle", "trivia", "quiz for everyone", "quiz us", "group trivia", "quiz all" }) then
    if CR.quiz then return "A group quiz is already running - question " .. CR.quiz.round .. "! Just type your answer." end
    if CR.count() < 2 then return "A group quiz needs at least two players at spawn. Bring a friend!" end
    CR.quiz = { round = 1, max = 5, scores = {}, names = {} }
    CR.toAll(cleanN(who) .. " started a GROUP QUIZ for everyone at spawn! Five questions.")
    CR.quizAsk()
    return true
  end
  local target = r:match(" roast battle with (%S+) ") or r:match(" roast battle (%S+) ") or r:match(" roast battle against (%S+) ") or
                 r:match(" roast battle vs (%S+) ")
  if target or has(r, { "roast battle" }) then
    local other = target and CR.findHere(target, who)
    if not other then return "A roast battle needs a name of someone at spawn. Say: speaker, roast battle and their name." end
    if CR.vote then return "A roast battle is already running - vote 1 or 2!" end
    CR.vote = { a = who, b = other, votes = {}, till = now() + 45 + CR.chatLag() + 1.1 * CR.count() }
    CR.toAll("ROAST BATTLE! " .. cleanN(who) .. " versus " .. cleanN(other) .. "! Round one: " .. roastOf(other) .. " And: " .. roastOf(who) ..
             " Who won? Everybody: type 1 for " .. cleanN(who) .. " or 2 for " .. cleanN(other) .. ".",
             "Roast battle! " .. cleanN(who) .. " versus " .. cleanN(other) .. "! " .. roastOf(other) .. " " .. roastOf(who) .. " Type 1 or 2!")
    return true
  end
  local dt
  for _, re in ipairs({ " duel with (%S+) ", " duel against (%S+) ", " duel vs (%S+) ", " 1v1 with (%S+) ", " 1v1 vs (%S+) ",
                        " fight with (%S+) ", " fight against (%S+) ", " duel (%S+) ", " 1v1 (%S+) ", " fight (%S+) ",
                        " challenge (%S+) " }) do
    local x = r:match(re)
    if x and not CR.NOT_NAME[x] then dt = x break end
  end
  if dt or has(r, { "duel", "1v1", "referee" }) then
    local other = dt and CR.findHere(dt, who)
    if not other then return "Say: speaker, duel and the name of someone at spawn - I will be the referee." end
    if CR.duel then return "A duel is already on: " .. cleanN(CR.duel.a) .. " versus " .. cleanN(CR.duel.b) .. "!" end
    CR.duel = { a = who, b = other, till = now() + 180 }
    CR.lowSaid = {}
    CR.toAll((pick(CR.DUEL):gsub("{a}", cleanN(who)):gsub("{b}", cleanN(other))))
    return true
  end
  if has(r, { "hype", "cheer", "hype us up", "pump us up", "cheer for us", "commentate" }) then
    CR.say(pick({ "Make some noise, spawn!", "This is the best crowd on the server!", "Who is ready to have fun? Everyone!", "Let's go, spawn!" }), "big")
    return true
  end
  return nil
end

-- every message from a player at spawn comes here first (before the spawn pack's own answers)
local chat0 = SP.chat
SP.chat = function(m)
  if not (type(m) == "table" and CR.enabled()) then return chat0(m) end
  local who, text = tostring(m.name or ""), tostring(m.msg or "")
  local ws = V.norm(text)
  local t = T(ws)
  pcall(CR.listen, who, ws, t)
  -- a group game waiting for an answer: no name needed
  if CR.quiz then local okQ, q = pcall(CR.quizAnswer, who, ws) if okQ and q then return true end end
  if CR.vote and #ws == 1 and (ws[1] == "1" or ws[1] == "2" or ws[1] == "one" or ws[1] == "two") then
    local v = CR.vote
    if low(who) == low(v.a) or low(who) == low(v.b) then
      if chatTell then chatTell(who, "You are in the battle - the crowd decides!") end
      return true
    end
    v.votes[low(who)] = (ws[1] == "1" or ws[1] == "one") and 1 or 2
    if chatTell then chatTell(who, "Vote counted!") end
    return true
  end
  if CR.called(ws, text) then
    local okC, c = pcall(CR.command, who, ws, t, text)
    if okC and type(c) == "string" then CR.answer(who, c) return true end
    if okC and c == true then if SP.talked then pcall(SP.talked, who) end return true end
  end
  return chat0(m)
end

-- the crowd's own life (every tick, 2 s)
V.tickHooks[#V.tickHooks + 1] = function()
  if not CR.enabled() then return end
  pcall(CR.fightTick)
  if CR.fight then CR.lastFightAt = now() end
  local t = now()
  if CR.quiz and CR.quiz.till and t > CR.quiz.till then
    local g = CR.quiz
    local line = "Nobody got it - the answer was " .. tostring(g.q and g.q.a[1] or "?") .. "."
    g.round = g.round + 1
    if CR.count() == 0 then CR.quiz = nil                    -- (everybody left spawn: no more questions to nobody)
    elseif g.round > g.max then CR.quizEnd(line) else CR.quizAsk(line) end
  end
  if CR.vote and t > CR.vote.till then CR.voteEnd() end
  -- the crowd grows past 3 / 5 / 8 / 12 (each level at most every 10 min)
  local n = CR.count()
  CR.levelAt = CR.levelAt or {}
  local lvl
  for _, l in ipairs({ 3, 5, 8, 12 }) do if n >= l then lvl = l end end
  if lvl and lvl >= (tonumber(cfg("crowdMin", 3)) or 3) and (CR.lastN or 0) < lvl and (not CR.levelAt[lvl] or t - CR.levelAt[lvl] > 600) then
    CR.levelAt[lvl] = t
    CR.say(pick(CR.GROW[lvl]), true)
  end
  CR.lastN = n
  -- talking to the crowd now and then (~4 min), not right after it spoke
  if CR.on() and not CR.quiz and not CR.vote and (not CR.idleAt or t - CR.idleAt > 240) and not (SP.spokeAt and os.clock() - SP.spokeAt < 60) then
    CR.idleAt = t
    if CR.started then CR.say(pick(CR.IDLE)) end
    CR.started = true
  end
  -- a long quiet spawn: the session's scores start over (an hour with no crowd)
  if n == 0 then CR.emptySince = CR.emptySince or t elseif CR.emptySince then CR.emptySince = nil end
  if CR.emptySince and t - CR.emptySince > 3600 then CR.score, CR.emptySince = {}, nil end
end

-- console:  voice crowd [on|off]
V.commands.crowd = function(words, say)
  local a = low(words[3])
  if a == "on" or a == "off" then
    if setSetting then setSetting("voice.crowd", a == "on") end
    say("The crowd at spawn (fights, laughs, group games): " .. a:upper())
    return
  end
  say("Crowd at spawn: " .. (CR.enabled() and "ON" or "OFF") .. " - " .. CR.count() .. " players at spawn" .. (CR.on() and " (a crowd)" or "") ..
      (CR.duel and (", duel " .. CR.duel.a .. " vs " .. CR.duel.b) or "") .. (CR.quiz and ", group quiz running" or ""))
  say(CR.scoreText())
end
