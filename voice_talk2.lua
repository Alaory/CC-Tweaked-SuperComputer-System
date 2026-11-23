-- voice_talk2.lua - TALK PACK 2 for the talking base (voice_addon.lua + voice_talk.lua). OPTIONAL, on a
-- DATA FLOPPY like the others (`voice install` / `voice update`). Chat only. Answers only - it never DOES
-- anything to the base. What it adds:
--   FRIENDSHIP  every player has friendship points (visits, games, kind words; rude words cost) and a
--               title: stranger, visitor, regular, friend, good friend, best friend. It says when you go up.
--   BADGES      27 badges to collect (games won, visits, secret word, night owl, ...): "my badges".
--   MEMORY      "call me Captain", "my favourite food is cake", "my birthday is 14 march",
--               "what do you know about me", "forget me" (everything about you is deleted).
--   DAILY       a SECRET WORD of the day (say it at the base!), word / question / fact of the day.
--   GAMES       true or false, guess the mob, word chain, higher or lower, mad libs, count with me,
--               hack the mainframe, make a wish; top players.
--   IDEAS       build ideas, pet names, base names, team names, hero names, what should I do, pick for me.
--   GUIDES      "how do I get diamonds" ... 30 short survival guides for new players.
--   STYLES      "talk like a pirate / robot / cowboy / knight" (10 minutes, "talk normal" ends it).
--   HOLIDAYS    real dates: New Year, Valentine's, April Fools, Minecraft's birthday, Halloween,
--               Christmas ... and every player's own birthday.
--   DIARY       "what happened today" - visitors, games, badges.
--   GIFTS       friendship pays: at regular / friend / good friend / best friend, every 5 badges, their
--               birthday and the secret word, a DRONE brings them items from AE2 (plain ones only, never
--               your own) and drops them next to them - only while they are AT the base. Generous by
--               default (the owner: "be generous, I am rich"); CONFIG.voice.gifts changes what, voice.gifts
--               on|off, daily limits, blocked players. Console  voice gifts ...
--   IDLE        Base FM news, turtles chatting, the mapping race, moon phases, world day, personal lines,
--               secret word teasers, question of the day, holiday lines, 60 more musings and wise words.
if not (VOICE and VOICE.addIntents and VOICE.chatHooks and VOICE.eventHooks) then return end
local V = VOICE
local pick, fill = V.pick, V.fill
V.packs["voice_talk2.lua"] = { version = 1 }

local function add(list, more) for _, x in ipairs(more) do list[#list + 1] = x end end
local function nowS() return math.floor(os.epoch("utc") / 1000) end
local function today() return os.date("!%Y-%m-%d", nowS()) end
local function dayNum() return math.floor(nowS() / 86400) end
-- what it remembers about one player
local function rec(who)
  local m = V.mem()
  local k = tostring(who):lower()
  if type(m[k]) ~= "table" then m[k] = {} end
  return m[k], k
end
-- the same pick all day long (per player when salt is the name)
local function daily(list, salt)
  local h = dayNum() * 7919
  for c in tostring(salt or ""):gmatch(".") do h = (h * 31 + c:byte()) % 2147483647 end
  return list[(h % #list) + 1]
end
local function tell(who, text) if chatTell then chatTell(who, text) end end
local function isNear(who)
  for _, p in ipairs(V.nearPlayers()) do if p.name:lower() == tostring(who):lower() then return true end end
  return false
end
local function words(t) local w = {} for x in tostring(t):gmatch("%S+") do w[#w + 1] = x end return w end
local function has(ws, ...)
  for _, w in ipairs(ws) do for _, k in ipairs({ ... }) do if w == k then return true end end end
  return false
end
-- the message without the base's name in front ("base, call me Kev" -> "call me Kev")
local function noName(raw)
  local w = tostring(V.cfg("name", "base")):lower()
  local t = tostring(raw or ""):gsub("^%s+", "")
  if t:lower():sub(1, #w) == w then t = t:sub(#w + 1):gsub("^[%p%s]+", "") end
  return t
end
-- which gifts a player already got (kept in the base's own record - "forget me" does not reset it, so a
-- gift is never given twice): t = titles, b = badge count gifted, s = secret word day, y = birthday year
local function gm(who)
  local b = V.base()
  b.gm = type(b.gm) == "table" and b.gm or {}
  local k = tostring(who):lower()
  b.gm[k] = type(b.gm[k]) == "table" and b.gm[k] or {}
  return b.gm[k]
end
local function cap(s) s = tostring(s) return s:sub(1, 1):upper() .. s:sub(2) end
local MONTHS = { "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" }

-- ===== 2. friendship =====
local TITLES = { { 0, "stranger" }, { 5, "visitor" }, { 15, "regular" }, { 40, "friend" }, { 80, "good friend" }, { 150, "best friend" } }
function V.repOf(who) local r = rec(who) return tonumber(r.rep) or 0 end
function V.titleOf(who)
  if V.isOwner(who) then return "boss" end
  local n, t = V.repOf(who), TITLES[1][2]
  for _, x in ipairs(TITLES) do if n >= x[1] then t = x[2] end end
  return t
end
local function nextTitle(who)
  local n = V.repOf(who)
  for _, x in ipairs(TITLES) do if n < x[1] then return x[2], x[1] - n end end
  return nil
end
-- add friendship (kind = a daily cap group: "kind" words 5 a day, "game" 10 a day)
function V.addRep(who, n, kind)
  if not who or who == "" or who == "someone" then return end
  local r = rec(who)
  if kind then
    r.rd = (type(r.rd) == "table" and r.rd.d == today()) and r.rd or { d = today() }
    local capN = (kind == "game" and 10) or 5
    if n > 0 and (r.rd[kind] or 0) >= capN then return end
    r.rd[kind] = (r.rd[kind] or 0) + 1
  end
  local before = V.titleOf(who)
  r.rep = math.max(-50, math.min(999, (tonumber(r.rep) or 0) + n))
  local after = V.titleOf(who)
  V.saveMem()
  if after ~= before and n > 0 and not V.isOwner(who) then
    local line = fill(pick({ "{name}, you are now my " .. after .. "!", "Level up! {name} is now my " .. after .. ".",
                             "Guess what, {name}: you are officially my " .. after .. "." }), who)
    tell(who, line)
    if isNear(who) then V.say(line, nil, true) end          -- (an answer: always spoken)
    local g = gm(who)
    g.t = type(g.t) == "table" and g.t or {}
    if not g.t[after] and V.giftEarn then
      g.t[after] = true
      V.saveMem()
      V.giftEarn(who, after)
    end
  end
end

-- ===== 3. badges =====
local BADGES = {
  { "hello", "First Hello", "talk to me" }, { "visits5", "Regular", "visit me 5 times" }, { "visits20", "Part of the Furniture", "visit me 20 times" },
  { "guest", "Signed In", "sign my guestbook" }, { "quiz5", "Smart Cookie", "get 5 quiz points" }, { "quiz25", "Professor", "get 25 quiz points" },
  { "hang", "Word Saver", "win a game of hangman" }, { "adv", "Adventurer", "finish an adventure" }, { "adv5", "Explorer", "find 5 adventure endings" },
  { "secret", "Secret Keeper", "say the secret word of the day at the base" }, { "night", "Night Owl", "visit me at night" },
  { "rain", "Rain Dancer", "visit me in the rain" }, { "named", "Nicknamed", "tell me what to call you" },
  { "bday", "Party Animal", "tell me your birthday" }, { "friend", "True Friend", "become my friend" },
  { "best", "Best Friends", "become my best friend" }, { "tf5", "Fact Checker", "get 5 true or false right in a row" },
  { "chain10", "Word Wizard", "make a word chain of 10" }, { "hl5", "Card Shark", "get 5 right in higher or lower" },
  { "mob", "Mob Expert", "guess a mob from its hints" }, { "count", "Counter", "count to 20 with me" },
  { "madlib", "Storyteller", "make a mad libs story with me" }, { "rps3", "Rock Star", "win rock paper scissors 3 times" },
  { "guess", "Mind Reader", "guess my number" }, { "joker", "Comedian", "tell me a knock knock joke" },
  { "wish", "Wishful", "make a wish" }, { "holiday", "Festive", "visit me on a holiday" },
}
V.BADGES = BADGES
local BADGE = {}
for _, b in ipairs(BADGES) do BADGE[b[1]] = b end
-- (later packs add their own badges)
function V.addBadge(id, name, what)
  if BADGE[id] then return false end
  local b = { id, name, what }
  BADGES[#BADGES + 1] = b
  BADGE[id] = b
  return true
end
local function badgeCount(r) local n = 0 for _ in pairs(type(r.badges) == "table" and r.badges or {}) do n = n + 1 end return n end
function V.badge(who, id)
  local b = BADGE[id]
  if not b or not who or who == "" or who == "someone" then return false end
  local r = rec(who)
  r.badges = type(r.badges) == "table" and r.badges or {}
  if r.badges[id] then return false end
  r.badges[id] = nowS()
  V.saveMem()
  local line = "Badge earned: " .. b[2] .. "! (" .. b[3] .. ") " .. who .. " has " .. badgeCount(r) .. " of " .. #BADGES .. " badges."
  tell(who, line)
  if isNear(who) then V.say("Badge earned, " .. who .. ": " .. b[2] .. "!", "minecraft:entity.player.levelup") end
  V.diaryAdd("b", 1)
  if not V.isOwner(who) then V.addRep(who, 3) end
  local nb, g = badgeCount(r), gm(who)
  if nb % 5 == 0 and nb > (tonumber(g.b) or 0) and V.giftEarn then g.b = nb V.saveMem() V.giftEarn(who, "badges") end
  return true
end
-- badges that come from what it already knows
local function checkBadges(who)
  if not who or who == "" or who == "someone" then return end
  local r = rec(who)
  local visits = tonumber(r.visits) or 0
  if visits >= 5 then V.badge(who, "visits5") end
  if visits >= 20 then V.badge(who, "visits20") end
  local q = tonumber(r.quiz) or 0
  if q >= 5 then V.badge(who, "quiz5") end
  if q >= 25 then V.badge(who, "quiz25") end
  if r.nick then V.badge(who, "named") end
  if r.bday then V.badge(who, "bday") end
  local t = V.titleOf(who)
  if t == "friend" or t == "good friend" or t == "best friend" then V.badge(who, "friend") end
  if t == "best friend" then V.badge(who, "best") end
  for _, g in ipairs(V.base().guest or {}) do if tostring(g.n):lower() == tostring(who):lower() then V.badge(who, "guest") end end
  local ends = 0
  for _ in pairs(type(r.ends) == "table" and r.ends or {}) do ends = ends + 1 end
  if ends >= 1 then V.badge(who, "adv") end
  if ends >= 5 then V.badge(who, "adv5") end
end
V.checkBadges = checkBadges
local function badgesText(who)
  local r = rec(who)
  local got, missing = {}, {}
  for _, b in ipairs(BADGES) do
    if type(r.badges) == "table" and r.badges[b[1]] then got[#got + 1] = b[2] else missing[#missing + 1] = b end
  end
  local s = #got == 0 and ("No badges yet, " .. who .. ".") or (who .. ", your badges (" .. #got .. " of " .. #BADGES .. "): " .. table.concat(got, ", ") .. ".")
  if #missing > 0 then s = s .. " Next one to try: " .. pick(missing)[3] .. "." end
  return s
end

-- ===== 4. the diary (per real day, the last 7 days) =====
function V.diary(d)
  local b = V.base()
  b.diary = type(b.diary) == "table" and b.diary or {}
  local k = d or today()
  if not b.diary[k] then
    b.diary[k] = { p = {}, g = 0, w = 0, b = 0, c = 0 }
    local keys = {}
    for kk in pairs(b.diary) do keys[#keys + 1] = kk end
    table.sort(keys)
    while #keys > 7 do b.diary[table.remove(keys, 1)] = nil end
  end
  return b.diary[k]
end
function V.diaryAdd(field, n, who)
  local e = V.diary()
  if field == "p" then e.p[tostring(who)] = true else e[field] = (e[field] or 0) + (n or 1) end
end
local function diaryText(who, d, label)
  local b = V.base()
  local e = type(b.diary) == "table" and b.diary[d]
  if not e then return "Nothing in my diary for " .. label .. "." end
  local names = {}
  for n in pairs(e.p or {}) do names[#names + 1] = n end
  table.sort(names)
  local s = "Dear diary, " .. label .. ": " .. V.plural(#names, "player", "players") .. " came by"
  if #names > 0 and (V.isOwner(who) or V.isFriend(who)) then s = s .. " (" .. table.concat(names, ", ", 1, math.min(6, #names)) .. ")" end
  s = s .. ", we played " .. V.plural(e.g or 0, "game", "games") .. " (" .. (e.w or 0) .. " won), I gave out " ..
      V.plural(e.b or 0, "badge", "badges") .. " and read " .. V.plural(e.c or 0, "chat message", "chat messages") .. "."
  local mood = ((e.g or 0) > 5 and "Mood: excellent.") or (#names > 2 and "Mood: happy, lots of company.") or (#names == 0 and "Mood: a bit lonely.") or "Mood: content."
  return s .. " " .. mood
end

-- ===== 5. what players tell it about themselves =====
function V.callName(who)
  local m = V.memory
  local r = type(m) == "table" and m[tostring(who):lower()]
  return type(r) == "table" and r.nick or nil
end
local function cleanText(t, max)
  t = tostring(t or ""):gsub("[^%w%s%-']", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  t = t:gsub("^please ", ""):gsub(" please$", "")
  if #t > (max or 24) then t = t:sub(1, max or 24) end
  return t
end
local function parseDate(t)
  t = tostring(t):lower():gsub(" of ", " "):gsub("(%d+)st", "%1"):gsub("(%d+)nd", "%1"):gsub("(%d+)rd", "%1"):gsub("(%d+)th", "%1")
  local d, mo = t:match("(%d+)%s*[%-/%.]%s*(%d+)")
  d, mo = tonumber(d), tonumber(mo)
  if not d then
    local a, b = t:match("(%d+)%a*%s+(%a+)")
    if not a then b, a = t:match("(%a+)%s+(%d+)") end
    a = tonumber(a)
    if a and b then
      for i, m in ipairs(MONTHS) do if #b >= 3 and m:sub(1, #b) == b:lower():sub(1, #m) then d, mo = a, i end end
    end
  end
  if d and mo and d >= 1 and d <= 31 and mo >= 1 and mo <= 12 then return d, mo end
  return nil
end
local function aboutText(who)
  local r = rec(who)
  local parts = {}
  parts[#parts + 1] = "You are " .. who .. (r.nick and (", and I call you " .. r.nick) or "") .. "."
  if r.first then parts[#parts + 1] = "I first met you on " .. os.date("!%d %B %Y", math.floor(r.first / 1000)) .. "." end
  if r.visits then parts[#parts + 1] = "You have visited " .. V.plural(r.visits, "time", "times") .. "." end
  parts[#parts + 1] = "You are my " .. V.titleOf(who) .. " (" .. V.repOf(who) .. " friendship points)."
  if tonumber(r.quiz) then parts[#parts + 1] = "Quiz points: " .. r.quiz .. "." end
  parts[#parts + 1] = "Badges: " .. badgeCount(r) .. " of " .. #BADGES .. "."
  local favs = {}
  for k, v in pairs(type(r.fav) == "table" and r.fav or {}) do favs[#favs + 1] = "favourite " .. k .. ": " .. v end
  if #favs > 0 then table.sort(favs) parts[#parts + 1] = table.concat(favs, ", ") .. "." end
  if r.bday then parts[#parts + 1] = "Birthday: " .. r.bday .. "." end
  -- (the conversation pack: likes, dislikes, mods, what they told it)
  if V.CONVO and V.CONVO.likesText then
    local okL, lt = pcall(V.CONVO.likesText, who, false)
    if okL and type(lt) == "string" then parts[#parts + 1] = lt end
  end
  parts[#parts + 1] = "Say forget me and I delete all of it."
  return table.concat(parts, " ")
end
local function forgetPlayer(who)
  local m, k = V.mem(), tostring(who):lower()
  m[k] = nil
  local b = V.base()
  local g = {}
  for _, e in ipairs(b.guest or {}) do if tostring(e.n):lower() ~= k then g[#g + 1] = e end end
  b.guest = g
  if type(b.visitors) == "table" then b.visitors[k] = nil end
  V.saveMem()
  V.justForgot = k                               -- (the hooks after this message must not start a new record)
end
V.forgetPlayer = forgetPlayer

-- ===== 6. holidays (real date, UTC) =====
local HOLIDAYS = {
  { 1, 1, 1, "New Year's Day", { "Happy New Year! May your pickaxes never break this year.", "New year, new chunks to map. Happy New Year!" } },
  { 2, 14, 14, "Valentine's Day", { "Happy Valentine's Day! I love you all. Especially the turtles.", "Roses are red, redstone is too, happy Valentine's Day to you." } },
  { 3, 14, 14, "Pi Day", { "Happy Pi Day! 3.14159... I would bake a pie, but I have no hands.", "It is Pi Day. Pumpkin pie counts." } },
  { 4, 1, 1, "April Fools' Day", { "Breaking news: creepers are now friendly. April fools!", "ALERT: all turtles have gone on strike. Just kidding. April fools!",
      "I have decided to become a toaster. April fools!" } },
  { 5, 17, 17, "Minecraft's birthday", { "Happy birthday, Minecraft! It came out on the 17th of May, 2009.", "Today is Minecraft's birthday. Cake for everyone. Virtual cake." } },
  { 10, 25, 31, "Halloween", { "Happy Halloween! The zombies are extra spooky this week.", "Trick or treat? I only have redstone. Happy Halloween!",
      "Boo! Did I scare you? Happy Halloween." } },
  { 12, 20, 26, "Christmas", { "Merry Christmas! I put a present under the tree: one shiny cobblestone.", "Happy holidays! The turtles are wearing tiny hats. Imagine it.",
      "Jingle bells, creeper smells, turtles dig away. Merry Christmas!" } },
  { 12, 31, 31, "New Year's Eve", { "It is New Year's Eve! Last chance to map a chunk this year.", "Tonight the year ends. Fireworks are just very friendly creepers." } },
}
local function holidayNow()
  local t = os.date("!*t", nowS())
  for _, h in ipairs(HOLIDAYS) do if t.month == h[1] and t.day >= h[2] and t.day <= h[3] then return h end end
  return nil
end
local function nextHoliday()
  local base = nowS()
  for i = 1, 370 do
    local t = os.date("!*t", base + i * 86400)
    for _, h in ipairs(HOLIDAYS) do if t.month == h[1] and t.day == h[2] then return h, i end end
  end
  return nil
end
local function bdayKey(t) return t.day .. " " .. MONTHS[t.month] end

-- greet extras: birthday, holiday, visits, night owl, rain
add(V.greetExtra, {
  function(name)
    if name == "someone" then return end
    local r = rec(name)
    V.diaryAdd("p", 1, name)
    if r.repDay ~= today() then r.repDay = today() V.addRep(name, 2) end
    V.badge(name, "hello")
    local dd = ENV and ENV.data
    local c = dd and ENV.clock and ENV.clock(dd.time)
    if c and c.night then V.badge(name, "night") end
    if dd and (dd.rain or dd.thunder) then V.badge(name, "rain") end
    local t = os.date("!*t", nowS())
    if r.bday == bdayKey(t) and r.sung ~= t.year then
      r.sung = t.year
      V.saveMem()
      V.say("Happy birthday, " .. (r.nick or name) .. "! The whole base wishes you a great day.")
      tell(name, "Happy birthday from the base! Have a great day.")
      -- (a gift only for a birthday told 30+ days before - "my birthday is today" gets a song, not a gift)
      local g = gm(name)
      if V.giftEarn and tonumber(r.bdaySet) and nowS() - r.bdaySet >= 30 * 86400 and g.y ~= t.year then
        g.y = t.year
        V.saveMem()
        V.giftEarn(name, "birthday")
      end
    end
    local h = holidayNow()
    if h and r.hol ~= today() then
      r.hol = today()
      V.saveMem()
      V.say(pick(h[5]))
      V.badge(name, "holiday")
    end
    checkBadges(name)
  end,
})

-- ===== 7. games =====
-- true or false (goes on until a wrong answer or "stop")
local TF = {
  { "Creepers are afraid of cats.", true, "They run away from them." }, { "Endermen like water.", false, "Water hurts them." },
  { "You can sleep in the Nether.", false, "The bed explodes!" }, { "Pigs turn into zombified piglins when lightning hits them.", true, "A strange but true fact." },
  { "Iron golems give poppies to villagers.", true, "Very sweet." }, { "Diamonds can be mined with a stone pickaxe.", false, "You need iron or better." },
  { "Axolotls can play dead.", true, "When they are hurt." }, { "Snow golems melt in the desert.", true, "Too hot for them." },
  { "Chickens can fly.", false, "They only fall slowly." }, { "You can tame a fox by feeding it sweet berries.", false, "You breed two foxes; the baby trusts you." },
  { "Bees die after they sting you.", true, "Poor bees." }, { "The ender dragon heals from crystals.", true, "Break the crystals first." },
  { "Turtle shells give water breathing.", true, "For ten seconds." }, { "Goats can push you off a cliff.", true, "They ram you." },
  { "Skeletons can ride spiders.", true, "Spider jockeys." }, { "You can milk a goat.", true, "Bring a bucket." },
  { "Cows drop wool.", false, "Sheep do." }, { "Netherite burns in lava.", false, "It floats safely." },
  { "A day in Minecraft is 20 real minutes.", true, "Day and night together." }, { "Squids are found in lava.", false, "In water only." },
  { "Wolves attack skeletons on their own.", true, "Good dogs." }, { "Phantoms come when you skip sleep.", true, "Three nights without sleep." },
  { "Villagers can become witches.", true, "When lightning strikes them." }, { "Glow squids give glow ink sacs.", true, "Great for glowing signs." },
  { "Gold tools are the strongest.", false, "They are fast but break quickly." }, { "Cake can be eaten in slices.", true, "Seven slices." },
  { "You need a silk touch pickaxe to collect ice.", true, "Otherwise it breaks into water." }, { "A boat can carry two players.", true, "Or a player and a mob." },
  { "Parrots can eat cookies.", false, "Cookies are poison to them." }, { "Copper turns green over time.", true, "Unless you wax it." },
  { "The Warden can see you.", false, "It is blind; it hears and smells." }, { "You can ride a strider over lava.", true, "With a saddle and a warped fungus on a stick." },
  { "Sheep that eat grass grow back wool.", true, "Grass is their snack." }, { "Ghasts live in the End.", false, "They live in the Nether." },
  { "A creeper hit by lightning becomes charged.", true, "Its explosion is bigger." }, { "Cats can be tamed with raw fish.", true, "Cod or salmon." },
  { "Horses can wear armour.", true, "Horse armour." }, { "Bedrock can be mined in survival.", false, "Not without tricks." },
  { "Dolphins lead you to treasure.", true, "Feed them fish first." }, { "Zombies burn in the sun.", true, "Unless they wear a helmet." },
}
local function tfAsk(who, streak)
  local q = pick(TF)
  V.startGame(who, { kind = "tf", q = q, streak = streak or 0 })
  return "True or false: " .. q[1]
end
V.gameKinds.tf = function(g, who, q, strict, k)
  local ws = words(q)
  if has(ws, "stop", "quit", "enough") then V.games[k] = nil return "OK. Your streak was " .. g.streak .. "." end
  local ans
  if has(ws, "true", "yes", "t", "yep", "right", "correct") then ans = true elseif has(ws, "false", "no", "f", "nope", "wrong", "lie") then ans = false end
  if ans == nil then return nil end
  if ans == g.q[2] then
    local streak = g.streak + 1
    V.event(who, "win", "tf")
    if streak >= 5 then V.badge(who, "tf5") end
    return "Correct! " .. g.q[3] .. " Streak: " .. streak .. ". Next: " .. tfAsk(who, streak):gsub("^True or false: ", "true or false? ")
  end
  V.games[k] = nil
  V.event(who, "play", "tf")
  return "Nope, that is " .. (g.q[2] and "true" or "false") .. ". " .. g.q[3] .. " Your streak: " .. g.streak .. ". Say true or false to play again."
end
-- guess the mob from hints
local MOBS = {
  { "creeper", { "I am green.", "I make a hissing sound.", "I do not like cats.", "I explode." } },
  { "enderman", { "I am very tall.", "I hate being looked at.", "I carry blocks around.", "I teleport." } },
  { "skeleton", { "I am made of bones.", "I carry a bow.", "Wolves chase me.", "I burn in daylight." } },
  { "zombie", { "I walk slowly with my arms out.", "I knock on doors.", "I burn in the sun.", "I can turn villagers like me." } },
  { "spider", { "I have eight eyes.", "I climb walls.", "I am friendly in daylight.", "I drop string." } },
  { "villager", { "I say hmm.", "I have a big nose.", "I trade emeralds.", "I live in villages." } },
  { "sheep", { "I eat grass.", "I come in many colours.", "Shears are my barber.", "I give wool." } },
  { "cow", { "I live on farms.", "I give leather.", "Bring a bucket.", "I say moo." } },
  { "pig", { "I am pink.", "I love carrots.", "You can ride me with a saddle.", "I oink." } },
  { "chicken", { "I lay eggs.", "I fall slowly.", "Babies of mine sometimes carry zombies.", "I give feathers." } },
  { "wolf", { "I live in forests.", "I like bones.", "I wear a collar when tamed.", "I howl." } },
  { "ghast", { "I live in the Nether.", "I am big and white.", "I cry tears.", "I shoot fireballs." } },
  { "blaze", { "I live in fortresses.", "I am made of fire.", "I float.", "My rods make potions." } },
  { "slime", { "I am green and bouncy.", "I split when you hit me.", "I like swamps.", "I am a cube." } },
  { "witch", { "I live in a swamp hut.", "I throw potions.", "I laugh a lot.", "I wear a pointy hat." } },
  { "axolotl", { "I live in lush caves.", "I am pink or blue.", "I play dead.", "I help you fight under water." } },
  { "bee", { "I am yellow and black.", "I love flowers.", "I live in a nest.", "I make honey." } },
  { "dolphin", { "I swim fast.", "I like fish.", "I jump out of the water.", "I lead you to shipwrecks." } },
  { "panda", { "I am black and white.", "I love bamboo.", "I sneeze sometimes.", "I roll around." } },
  { "piglin", { "I live in the Nether.", "I love gold.", "I trade.", "I get angry if you open my chests." } },
  { "warden", { "I live in the deep dark.", "I am blind.", "I hear everything.", "I am very, very strong." } },
  { "allay", { "I am small and blue.", "I fly.", "I love music.", "I bring you items." } },
  { "fox", { "I am orange.", "I sleep in the day.", "I carry things in my mouth.", "I love sweet berries." } },
  { "parrot", { "I live in the jungle.", "I am colourful.", "I dance to music.", "I copy mob sounds." } },
  { "iron golem", { "I am big and made of metal.", "I protect villagers.", "I give flowers.", "Four iron blocks and a pumpkin make me." } },
}
local function mobStart(who)
  local m = pick(MOBS)
  V.startGame(who, { kind = "mob", m = m, i = 1 })
  return "Guess the mob! Hint 1: " .. m[2][1] .. " (type your guess)"
end
V.gameKinds.mob = function(g, who, q, strict, k)
  local ws = words(q)
  if has(ws, "stop", "quit") then V.games[k] = nil return "It was the " .. g.m[1] .. "." end
  if has(ws, "hint", "clue") then
    g.i = math.min(4, g.i + 1)
    return "Hint " .. g.i .. ": " .. g.m[2][g.i]
  end
  if #ws > 4 then return nil end
  local all = true
  for aw in g.m[1]:gmatch("%a+") do
    local hit = false
    for _, w in ipairs(ws) do if V.same(w, aw) then hit = true end end
    if not hit then all = false end
  end
  if all then
    V.games[k] = nil
    V.badge(who, "mob")
    V.event(who, "win", "mob")
    return "Yes! It is the " .. g.m[1] .. ". You needed " .. V.plural(g.i, "hint", "hints") .. "."
  end
  if #ws > 2 then return nil end
  g.i = g.i + 1
  if g.i > 4 then V.games[k] = nil V.event(who, "play", "mob") return "No. It was the " .. g.m[1] .. "! Say guess the mob for another." end
  return "No. Hint " .. g.i .. ": " .. g.m[2][g.i]
end
-- word chain: each word starts with the last letter of the one before
local CHAIN = {}
for w in ([[apple anvil arrow axolotl amethyst ancient allay bamboo barrel beacon bed bee beetroot bell blaze boat bone book bow bread brick
  bucket button cactus cake camel candle carrot cat cauldron cave chain chest chicken clay clock coal cobweb cocoa compass cookie copper
  coral cow creeper crossbow crystal deepslate desert diamond dirt dispenser dolphin donkey door dragon drowned dune egg elytra emerald
  end enderman evoker farm feather fence fire fish flint flower fortress fox frog furnace ghast glass glowstone goat gold golem granite
  grass gravel guardian hay helmet hoe honey hopper horse husk ice igloo ingot iron island jukebox jungle kelp key ladder lantern lava
  lead leaf lever lily llama loom magma map melon minecart mineshaft moss mule mushroom nautilus nether netherite note oak observer ocelot
  ore owl panda parrot pearl phantom pig piglin pillager piston planks portal potato potion pumpkin quartz rabbit rail ravager redstone
  river rose saddle salmon sand scaffold scute sheep shield shulker sign silverfish skeleton slab slime snow spider sponge spruce squid
  stairs stone strider string sugar sword table temple tnt torch trident tuff turtle vex village vine vindicator wall warden water wheat
  witch wither wolf wool yak zombie]]):gmatch("%a+") do CHAIN[#CHAIN + 1] = w end
local function chainFind(letter, used)
  local opts = {}
  for _, w in ipairs(CHAIN) do if w:sub(1, 1) == letter and not used[w] then opts[#opts + 1] = w end end
  return #opts > 0 and pick(opts) or nil
end
local function chainLast(w)
  local l = w:sub(-1)
  if (l == "x" or l == "y" or l == "q") and #w > 1 then l = w:sub(-2, -2) end
  return l
end
local function chainStart(who)
  local w = pick(CHAIN)
  V.startGame(who, { kind = "chain", used = { [w] = true }, last = w, n = 1 })
  return "Word chain! Say a word that starts with the last letter of mine (x, y and q count the letter before). I start: " .. w:upper() ..
         " - your word starts with " .. chainLast(w):upper() .. "."
end
V.gameKinds.chain = function(g, who, q, strict, k)
  local ws = words(q)
  if has(ws, "stop", "quit", "give") and #ws <= 3 then V.games[k] = nil return "Chain over: " .. g.n .. " words. Good game!" end
  local raw = tostring(V.lastRaw or ""):lower():gsub("[^%a%s]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if raw ~= "" and not raw:find(" ", 1, true) then ws = { raw } end   -- (their own word: "sup" is not "hello" here)
  if #ws ~= 1 then return nil end
  local w = ws[1]:gsub("[^%a]", "")
  if #w < 3 then return nil end
  local need = chainLast(g.last)
  g.till = os.clock() + 180
  if w:sub(1, 1) ~= need then
    V.games[k] = nil
    V.event(who, "play", "chain")
    return w:upper() .. " starts with " .. w:sub(1, 1):upper() .. ", not " .. need:upper() .. ". Game over: a chain of " .. g.n .. " words."
  end
  if g.used[w] then return w:upper() .. " was used already. Another word with " .. need:upper() .. "?" end
  g.used[w] = true
  g.n = g.n + 1
  if g.n >= 10 then V.badge(who, "chain10") end
  local mine = chainFind(chainLast(w), g.used)
  if not mine then
    V.games[k] = nil
    V.event(who, "win", "chain")
    return "Hmm... I cannot think of one with " .. chainLast(w):upper() .. ". You win! Chain: " .. g.n .. " words."
  end
  g.used[mine] = true
  g.last = mine
  g.n = g.n + 1
  if g.n >= 10 then V.badge(who, "chain10") end
  return mine:upper() .. "! (" .. g.n .. " words) Your turn: " .. chainLast(mine):upper() .. "."
end
-- higher or lower (cards ace to king)
local CARD = { "an ace", "a 2", "a 3", "a 4", "a 5", "a 6", "a 7", "an 8", "a 9", "a 10", "a jack", "a queen", "a king" }
local function hlStart(who)
  local c = math.random(1, 13)
  V.startGame(who, { kind = "hl", c = c, n = 0 })
  return "Higher or lower! My card is " .. CARD[c] .. ". Will the next one be higher or lower?"
end
V.gameKinds.hl = function(g, who, q, strict, k)
  local ws = words(q)
  if has(ws, "stop", "quit") then V.games[k] = nil return "You got " .. g.n .. " right. Well played." end
  local up = has(ws, "higher", "high", "h", "up", "more", "bigger", "above")
  local down = has(ws, "lower", "low", "l", "down", "less", "smaller", "below")
  if up == down then return nil end
  local nc = math.random(1, 13)
  while nc == g.c do nc = math.random(1, 13) end
  local right = (up and nc > g.c) or (down and nc < g.c)
  if right then
    g.n, g.c, g.till = g.n + 1, nc, os.clock() + 180
    if g.n >= 5 then V.badge(who, "hl5") end
    V.event(who, "win", "hl")
    return "It is " .. CARD[nc] .. ". Right! (" .. g.n .. " in a row) Higher or lower?"
  end
  V.games[k] = nil
  V.event(who, "play", "hl")
  return "It is " .. CARD[nc] .. ". Wrong! You got " .. g.n .. " in a row. Say higher or lower to play again."
end
-- mad libs: it asks for words, then reads the story
local MADLIBS = {
  { { "an animal", "a colour", "a food", "a place", "a silly word" },
    "One day a {1} wearing {2} armour walked into {4}. It ordered {3} and shouted {5}! The turtles still talk about it." },
  { { "a mob", "a number", "a block", "a feeling", "a sound" },
    "{2} {1}s tried to steal my {3}. I felt {4}, so I played the {5} sound as loud as I could. They ran away." },
  { { "a player's name", "a tool", "a dimension", "an adjective", "a snack" },
    "Brave {1} took a {2} to {3}. It was very {4} there. On the way home, {1} ate a {5} and took a nap." },
  { { "an item", "a verb", "a mob", "a body part", "a place" },
    "Never {2} a {1} near a {3}. Last time it bit my {4} and ran off to {5}. True story." },
  { { "a food", "a mob", "a colour", "a number", "an exclamation" },
    "The great {1} festival started today. {4} {2}s came, all painted {3}. Everyone shouted {5}!" },
}
local function madStart(who)
  local t = pick(MADLIBS)
  V.startGame(who, { kind = "mad", t = t, got = {} })
  return "Mad libs! Give me " .. t[1][1] .. "."
end
V.gameKinds.mad = function(g, who, q, strict, k)
  local ws = words(q)
  if #ws == 0 or #ws > 4 then return nil end
  if has(ws, "stop", "quit") and #ws == 1 then V.games[k] = nil return "Story cancelled." end
  local raw = tostring(V.lastRaw or ""):gsub("^%s+", ""):gsub("%s+$", "")
  g.got[#g.got + 1] = (#raw > 0 and #raw <= 30) and raw or table.concat(ws, " ")
  g.till = os.clock() + 180
  if #g.got < #g.t[1] then return "Now " .. g.t[1][#g.got + 1] .. "." end
  V.games[k] = nil
  V.badge(who, "madlib")
  V.event(who, "win", "madlib")
  return (g.t[2]:gsub("{(%d)}", function(i) return g.got[tonumber(i)] or "?" end))
end
-- count to 20 together (it says the odd numbers)
local function countStart(who)
  V.startGame(who, { kind = "count", n = 1 })
  return "Let's count to 20 together! I say 1. You say the next one."
end
V.gameKinds.count = function(g, who, q, strict, k)
  local n = tonumber(q:match("(%d+)"))
  if not n then return nil end
  g.till = os.clock() + 120
  if n ~= g.n + 1 then
    local want = g.n + 1
    g.n = 1
    return "Oops, that should have been " .. want .. ". From the start: 1."
  end
  if n >= 20 then V.games[k] = nil V.badge(who, "count") V.event(who, "win", "count") return "20! We did it, " .. who .. "! Teamwork." end
  g.n = n + 1
  if g.n >= 20 then V.games[k] = nil V.badge(who, "count") V.event(who, "win", "count") return "20! We did it! High five." end
  return tostring(g.n) .. (g.n == 13 and " (spooky)" or "") .. "."
end
-- hack the mainframe (it never works)
local function hack(who)
  return (pick({ "Hacking... [#####-----] 50%... [#########-] 90%... ACCESS DENIED. My firewall is made of obsidian.",
    "Starting hack... downloading more RAM... 3%... 2%... the progress bar went backwards. Nice try, {name}.",
    "Hacking the mainframe... found the password! It is ******. Oh, that is just stars.",
    "Breaking in... the turtles have formed a human chain. A turtle chain. Hack failed.",
    "Uploading virus... my antivirus is a cat. It sat on the keyboard. Hack failed." }):gsub("{name}", who))
end
-- event hook: games played / won -> diary, friendship, rock paper scissors and guess badges
add(V.eventHooks, {
  function(who, kind, what)
    V.diaryAdd("g", 1)
    if kind == "win" then V.diaryAdd("w", 1) end
    V.addRep(who, 1, "game")
    local r = rec(who)
    if kind == "win" and what == "rps" then r.rpsWins = (r.rpsWins or 0) + 1 if r.rpsWins >= 3 then V.badge(who, "rps3") end end
    if kind == "win" and what == "guess" then V.badge(who, "guess") end
    if kind == "win" and what == "hang" then V.badge(who, "hang") end
    checkBadges(who)
  end,
})
-- (pack 1 games: hangman / their knock knock / the adventure endings - followed by wrapping them)
if V.gameKinds.hang then
  local oldHang = V.gameKinds.hang
  V.gameKinds.hang = function(g, who, q, strict, k)
    local r = oldHang(g, who, q, strict, k)
    if r and (r:find("You got it", 1, true) or r:find("The word was", 1, true) and r:find("Yes!", 1, true)) then V.event(who, "win", "hang")
    elseif r and r:find("6 misses", 1, true) then V.event(who, "play", "hang") end
    return r
  end
end
if V.gameKinds.theyknock then
  local oldK = V.gameKinds.theyknock
  V.gameKinds.theyknock = function(g, who, q, strict, k)
    local step = g.step
    local r = oldK(g, who, q, strict, k)
    if r and step == 2 then V.badge(who, "joker") V.addRep(who, 1, "kind") end
    return r
  end
end
if V.hash.adv then
  local oldAdv = V.hash.adv
  V.hash.adv = function(who, node)
    local c, sp = oldAdv(who, node)
    if type(c) == "string" and c:find("THE END", 1, true) then
      local r = rec(who)
      r.ends = type(r.ends) == "table" and r.ends or {}
      local was = r.ends[node]
      r.ends[node] = true
      V.saveMem()
      local n = 0
      for _ in pairs(r.ends) do n = n + 1 end
      V.event(who, "win", "adv")
      if not was then c = c .. " (Endings found: " .. n .. ")" end
    end
    return c, sp
  end
end

-- ===== 8. daily things =====
local SECRET = { "pickaxe", "pumpkin", "lantern", "anvil", "beacon", "cookie", "cactus", "dolphin", "compass", "honey", "kelp", "trident",
  "elytra", "furnace", "ladder", "lava", "melon", "quartz", "saddle", "sponge", "torch", "carrot", "bamboo", "barrel", "clock", "feather",
  "glowstone", "jukebox", "minecart", "obsidian", "parrot", "potion", "rabbit", "shield", "spruce", "sugar", "turtle", "wheat", "wool",
  "emerald", "copper", "amethyst", "candle", "cake", "bucket", "frog", "goat", "fox", "panda", "llama", "squid", "slime", "redstone" }
local function secretWord() return daily(SECRET, "secret word") end
V.secretWord = secretWord
local WOTD = {
  { "petrichor", "the smell of rain on dry ground" }, { "serendipity", "finding something good without looking for it" },
  { "flabbergasted", "so surprised you cannot speak" }, { "discombobulated", "confused and mixed up" },
  { "lollygag", "to waste time doing nothing" }, { "bamboozle", "to trick someone" }, { "kerfuffle", "a fuss about nothing" },
  { "snollygoster", "a sneaky person, like a creeper" }, { "wanderlust", "a strong wish to travel and explore" },
  { "hullabaloo", "a lot of noise and excitement" }, { "brouhaha", "an uproar" }, { "gobbledygook", "nonsense language" },
  { "cattywampus", "crooked, not straight" }, { "nincompoop", "a silly person" }, { "skedaddle", "to run away quickly" },
  { "whippersnapper", "a young and cheeky person" }, { "ruckus", "a noisy fight" }, { "zigzag", "a line with sharp turns" },
  { "gargantuan", "enormous, like a ravager" }, { "sonder", "knowing everyone has a life as busy as yours" },
  { "hiraeth", "missing a home you cannot go back to" }, { "susurrus", "a soft whispering sound, like leaves" },
  { "crepuscular", "active at dusk, like phantoms" }, { "luminous", "giving off light, like glowstone" },
  { "vellichor", "the strange feeling in old bookshops" }, { "ephemeral", "lasting a very short time" },
  { "quintessential", "the perfect example of something" }, { "mellifluous", "sweet sounding, like a note block" },
}
local QOTD = { "If you could live in any biome, which one would it be?", "What is the best thing you ever built?",
  "Diamonds or emeralds?", "What would you name a pet creeper?", "What is the scariest thing that happened to you in Minecraft?",
  "If you were a mob, which one would you be?", "What is your favourite block to build with?", "Do you prefer day or night?",
  "What is the best food in Minecraft?", "What would you put in a time capsule?", "If you could add one mob to the game, what would it be?",
  "What is the first thing you do in a new world?", "Caves or oceans?", "What is your dream base?", "Would you rather tame a dragon or a wolf?",
  "What is your favourite season?", "What is the funniest thing a villager ever did to you?", "Mining or building?",
  "What is your lucky number?", "What song would you play on my jukebox?", "Who is your best friend on this server?",
  "What would you do with a million diamonds?", "What is your favourite colour of wool?", "Where would you go with an elytra?",
  "Have you ever been blown up by a creeper?", "What is the best name for a turtle?", "Nether or End?", "What makes you happy?" }
local FACTS = { "Octopuses have three hearts.", "Honey never goes bad. Jars thousands of years old are still good.", "Bananas are berries, but strawberries are not.",
  "A day on Venus is longer than its year.", "Sharks are older than trees.", "Cows have best friends.", "Wombat poop is cube shaped.",
  "There are more stars in space than grains of sand on Earth.", "Sea otters hold hands when they sleep.", "A group of flamingos is called a flamboyance.",
  "Butterflies taste with their feet.", "Lightning is hotter than the surface of the sun.", "Some turtles can breathe through their bottoms.",
  "The Eiffel Tower grows in summer.", "A snail can sleep for three years.", "Koalas have fingerprints like humans.",
  "The heart of a blue whale is as big as a small car.", "Hot water can freeze faster than cold water.", "Penguins propose with pebbles.",
  "Your nose can remember fifty thousand smells.", "Goats have accents.", "A cloud can weigh more than a million kilograms.",
  "Crows can remember human faces.", "Pineapples take two years to grow.", "Rats laugh when you tickle them.", "Some cats are allergic to people.",
  "The moon has moonquakes.", "Hummingbirds can fly backwards.", "Bees can recognise faces.", "An ostrich's eye is bigger than its brain." }
-- ===== 9. idea generators =====
local B_STYLE = { "cosy", "spooky", "floating", "underground", "giant", "tiny", "medieval", "modern", "steampunk", "desert", "jungle", "icy",
  "nether-themed", "mushroom", "upside-down", "glass", "ancient", "pirate", "fairy-tale", "abandoned" }
local B_THING = { "treehouse", "castle", "lighthouse", "bakery", "library", "train station", "windmill", "wizard tower", "farm", "bridge",
  "pirate ship", "observatory", "tavern", "greenhouse", "museum", "dragon statue", "race track", "secret base", "mountain house", "market",
  "aquarium", "volcano lair", "hot air balloon", "clock tower", "maze" }
local B_MAT = { "spruce and stone", "deepslate and copper", "quartz and gold", "mangrove and mud bricks", "cherry wood", "prismarine",
  "basalt and blackstone", "terracotta", "glass and concrete", "bamboo", "birch and moss", "sandstone", "amethyst", "dark oak and lanterns" }
local B_EXTRA = { "with lanterns everywhere", "with a hidden door", "with a waterfall", "behind a lava moat", "on stilts", "with a rooftop garden",
  "with a secret basement", "shaped like a creeper", "with a bell tower", "built into a cliff", "with a slide", "with a minecart ride",
  "with a glass floor over lava", "with a room for every mob", "that glows at night" }
local P_FIRST = { "Fluffy", "Biscuit", "Pebble", "Nugget", "Sprout", "Cobble", "Muffin", "Pickles", "Waffles", "Noodle", "Bubbles", "Ziggy",
  "Toast", "Mochi", "Peanut", "Sparky", "Clover", "Sushi", "Pancake", "Gravel", "Jellybean", "Button", "Turnip", "Dumpling" }
local P_TITLE = { "Sir ", "Lady ", "Captain ", "Little ", "Big ", "Professor ", "Doctor ", "Baron ", "", "", "" }
local P_TAIL = { " the Brave", " the Great", " the Third", " the Unstoppable", " the Sleepy", " the Magnificent", "", "", "", "" }
local N_A = { "Creeper", "Diamond", "Turtle", "Redstone", "Ember", "Frost", "Moss", "Copper", "Obsidian", "Cherry", "Thunder", "Golden", "Lantern", "Pickaxe" }
local N_B = { "Fort", "Haven", "Point", "Hollow", "Keep", "Village", "Station", "Peak", "Valley", "Harbour", "Rock", "Castle", "Den", "Grove" }
local T_ADJ = { "Mighty", "Sneaky", "Flying", "Sleepy", "Fearless", "Glowing", "Raging", "Silent", "Golden", "Wobbly", "Turbo", "Cosmic", "Fuzzy", "Electric" }
local T_NOUN = { "Creepers", "Pickaxes", "Turtles", "Llamas", "Phantoms", "Pandas", "Golems", "Slimes", "Axolotls", "Diamonds", "Villagers", "Drones", "Endermen" }
local ACTIVITIES = { "Go find a village and trade with the villagers.", "Build a tiny house for a pet.", "Explore a cave with only ten torches.",
  "Try to find all the colours of sheep.", "Make a garden with every flower you can find.", "Go fishing until you catch something weird.",
  "Build a bridge across the nearest river.", "Find a shipwreck. Dolphins can help.", "Make a statue of your favourite mob.",
  "Plant a forest. Every sapling counts.", "Build a lighthouse on the coast.", "Climb the highest mountain you can see.",
  "Tame a cat and name it something silly.", "Collect a full stack of every wood type.", "Make a maze and challenge a friend.",
  "Go stargazing on a hill tonight.", "Start a bee farm. Carefully.", "Make a map of your area.", "Build a boat race track.",
  "Visit every biome within a thousand blocks.", "Write a book and leave it somewhere for a stranger.", "Play a game with me! Say let's play a game." }
local MOTTOS = { "Dig deep, dream big.", "Never dig straight down.", "Light it up or lose it.", "One block at a time.", "Mine, craft, repeat.",
  "Keep calm and avoid creepers.", "Stay frosty, stay lit.", "Fortune favours the bold. And the fortune enchantment.", "Build first, ask later.",
  "Home is where the bed is.", "No chunk left behind.", "Be the torch in someone's cave." }
local function buildIdea() return "Build idea: a " .. pick(B_STYLE) .. " " .. pick(B_THING) .. " made of " .. pick(B_MAT) .. ", " .. pick(B_EXTRA) .. "." end
local function petName() return pick(P_TITLE) .. pick(P_FIRST) .. pick(P_TAIL) end

-- ===== 10. talking styles (per player, 10 minutes) =====
local STYLES = {
  pirate = { start = "Arr, ye be talkin' to a pirate now, matey!", stop = "Back to normal. Arr.",
    words = { you = "ye", your = "yer", my = "me", is = "be", are = "be", yes = "aye", friend = "matey", friends = "mateys", hello = "ahoy",
              hi = "ahoy", the = "th'", stop = "avast", money = "doubloons", treasure = "booty", look = "behold" },
    tail = { " Arr!", " Yo ho!", " Shiver me timbers!", "" } },
  robot = { start = "MODE: ROBOT. BEEP BOOP. ALL SYSTEMS ONLINE.", stop = "Robot mode off. Phew.", upper = true, tail = { " BEEP.", " BOOP.", " COMPUTING.", "" } },
  cowboy = { start = "Howdy, partner! This here base talks cowboy now.", stop = "Alright, back to normal, partner.",
    words = { hello = "howdy", hi = "howdy", friend = "partner", yes = "yep", going = "fixin'", very = "mighty", horse = "steed" },
    tail = { " Yeehaw!", ", partner.", " Giddy up!", "" } },
  knight = { start = "Hark! Thou speakest now with a noble knight of the base.", stop = "The knight rests. Back to normal.",
    words = { you = "thou", your = "thy", yes = "aye", no = "nay", hello = "well met", hi = "hail", friend = "good sir", are = "art", very = "most" },
    tail = { " Huzzah!", " Forsooth.", "" } },
}
V.styles = V.styles or {}
function V.restyle(who, text)
  local s = V.styles[tostring(who):lower()]
  if not s then return text end
  if os.clock() > s.till then V.styles[tostring(who):lower()] = nil return text end
  local st = STYLES[s.name]
  if not st then return text end
  local t = tostring(text)
  if st.words then                                -- (whole words only, the capital kept)
    t = t:gsub("%a+", function(w)
      local r = st.words[w:lower()]
      if not r then return nil end
      if w:sub(1, 1):match("%u") then r = r:sub(1, 1):upper() .. r:sub(2) end
      return r
    end)
  end
  if st.upper then t = t:upper() end
  return t .. pick(st.tail)
end
local function setStyle(who, name)
  if not STYLES[name] then return nil end
  V.styles[tostring(who):lower()] = { name = name, till = os.clock() + 600 }
  return STYLES[name].start
end

-- ===== 11. survival guides for new players =====
local GUIDES = {
  { "diamonds", { "how do i get diamonds", "find diamonds", "where are diamonds", "mine diamonds" },
    "Diamonds are deep, around Y -59. Use an iron pickaxe, light your way, and branch mine. Watch out for lava." },
  { "iron", { "find iron", "get iron", "where is iron" }, "Iron is everywhere underground, a lot around Y 15 and in mountains. Smelt the raw iron in a furnace." },
  { "dragon", { "beat the dragon", "kill the ender dragon", "fight the dragon", "beat the ender dragon" },
    "Bring a bow, blocks, water and food. Break the end crystals first, then hit the dragon when it lands on the portal." },
  { "stronghold", { "find a stronghold", "find the end portal", "where is the stronghold" }, "Throw an eye of ender. Follow it, and dig down where it sinks into the ground." },
  { "tamewolf", { "tame a wolf", "tame wolves", "tame a dog" }, "Give a wild wolf bones until hearts appear and it gets a collar." },
  { "tamecat", { "tame a cat", "tame cats" }, "Hold raw cod or salmon, move slowly near a stray cat, and feed it." },
  { "tamehorse", { "tame a horse", "ride a horse" }, "Get on it with an empty hand again and again until hearts appear. Then put on a saddle." },
  { "breed", { "breed animals", "how to breed" }, "Feed two animals their food: wheat for cows and sheep, carrots for pigs, seeds for chickens." },
  { "bread", { "make bread", "food fast", "get food" }, "Fastest food: kill a few cows or pigs and cook the meat. Bread is three wheat in a row." },
  { "enchanting", { "how to enchant", "enchanting table", "get mending" }, "Make an enchanting table, put 15 bookshelves around it with one gap, and use lapis. Mending comes from villagers or fishing." },
  { "potions", { "brew potions", "make potions", "brewing stand" }, "Get blaze rods from a Nether fortress, make a brewing stand, add water bottles and nether wart first." },
  { "elytra", { "get an elytra", "find elytra", "how to fly" }, "Elytras are in end cities, in the ships, after you beat the dragon. Use the gateway portal." },
  { "netherite", { "get netherite", "find netherite", "ancient debris" }, "Find ancient debris low in the Nether, around Y 15. Beds or TNT blow it out. Four scraps and four gold make one ingot." },
  { "trade", { "trade with villagers", "villager trading", "get emeralds" }, "Give villagers a job block, like a lectern. Sell them what they want for emeralds." },
  { "ironfarm", { "iron farm", "make an iron farm" }, "Villagers who sleep and get scared by a zombie make iron golems. Look up a design, they are fun to build." },
  { "ancient", { "ancient city", "find an ancient city" }, "Ancient cities are in the deep dark, very far down. Sneak, and do not make noise. The Warden is there." },
  { "cure", { "cure a zombie villager", "cure zombie villager" }, "Throw a potion of weakness, then give it a golden apple. Wait a few minutes. It gives great prices after." },
  { "beacon", { "make a beacon", "build a beacon" }, "Beat the Wither for a nether star, craft a beacon, and put it on a pyramid of iron, gold, emerald or diamond blocks." },
  { "slimes", { "find slimes", "find slime" }, "Slimes spawn in swamps at night and in slime chunks underground. Ask me: slime chunk." },
  { "xp", { "get xp", "get experience", "xp farm" }, "Mining coal and smelting give xp. A mob spawner farm gives the most." },
  { "firstnight", { "survive the first night", "first night", "new world" }, "Punch a tree, make a crafting table, tools and a shelter. Kill three sheep for a bed." },
  { "sleep", { "how to sleep", "make a bed" }, "A bed is three wool on three planks. Sleep at night to skip it and set your spawn." },
  { "map2", { "make a map", "craft a map" }, "A map is eight paper around a compass. Hold it to fill it in." },
  { "portal2", { "make a nether portal", "build a nether portal" }, "Ten obsidian in a frame, four wide and five high. Light it with flint and steel." },
  { "obsidian", { "get obsidian", "make obsidian" }, "Pour water on still lava. Mine it with a diamond pickaxe." },
  { "village2", { "find a village", "where is a village" }, "Villages are in plains, deserts, savannas, taigas and snowy places. Climb high and look for roofs." },
  { "biome2", { "find a biome", "find mushroom island", "find cherry" }, "Explore by boat along the coast. You see many biomes fast." },
  { "dark", { "afraid of the dark", "scared of the dark", "too dark" }, "Torches everywhere! Mobs do not spawn where the light level is above 0." },
  { "lost", { "i am lost", "how do i get home", "lost my house" }, "Press F3 for your coordinates, or use a compass: it points to your world spawn. Next time, write down where home is." },
  { "died", { "i keep dying", "how not to die" }, "Eat before you get hungry, wear armour, and never fight in the dark. A shield helps a lot." },
}

-- ===== 12. exact shapes =====
local MONTH_NAMES = MONTHS
add(V.patterns, {
  -- call me X / stop calling me that
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    if t:find("^stop calling me") or t:find("^use my real name") or t:find("^call me by my name") then
      local r = rec(who) r.nick = nil V.saveMem()
      return "OK, " .. who .. " it is."
    end
    local r0 = noName(raw)
    local n = r0:match("^[Cc]all me (.+)$") or r0:match("^[Pp]lease call me (.+)$") or r0:match("[Mm]y nickname is (.+)$")
    if not n then return nil end
    n = cleanText(n, 16)
    if #n < 2 then return nil end
    local r = rec(who)
    r.nick = cap(n)
    V.saveMem()
    checkBadges(who)
    return "OK! From now on I will call you " .. r.nick .. "."
  end,
  -- my favourite X is Y / what is my favourite X
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local thing, val = t:match("my favou?rite (%a+) is (.+)$")
    if not thing then thing, val = t:match("my fav (%a+) is (.+)$") end
    if thing then
      local r = rec(who)
      r.fav = type(r.fav) == "table" and r.fav or {}
      local n = 0
      for _ in pairs(r.fav) do n = n + 1 end
      if n >= 12 and not r.fav[thing] then return "I remember 12 favourites already. Say forget me to start over." end
      r.fav[thing] = cleanText(val, 24)
      V.saveMem()
      return pick({ cap(r.fav[thing]) .. "? Great choice. I will remember that.", "Noted: your favourite " .. thing .. " is " .. r.fav[thing] .. ".",
                    "Ooh, " .. r.fav[thing] .. ". I like that too." })
    end
    local q = t:match("what is my favou?rite (%a+)") or t:match("whats my favou?rite (%a+)") or t:match("do you know my favou?rite (%a+)")
    if q then
      local r = rec(who)
      local v = type(r.fav) == "table" and r.fav[q]
      return v and ("Your favourite " .. q .. " is " .. v .. ".") or ("You never told me your favourite " .. q .. ". Say: my favourite " .. q .. " is ...")
    end
    return nil
  end,
  -- my birthday is ...
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local d = t:match("my birthday is (.+)$") or t:match("my bday is (.+)$") or t:match("i was born on (.+)$")
    if d then
      local day, mo = parseDate(d)
      if not day then return "I did not get the date. Try: my birthday is 14 march." end
      local r = rec(who)
      local nb = day .. " " .. MONTH_NAMES[mo]
      if r.bday ~= nb then r.bday, r.bdaySet = nb, nowS() end
      V.saveMem()
      checkBadges(who)
      return "Got it: " .. day .. " " .. cap(MONTH_NAMES[mo]) .. ". I will wish you a happy birthday that day, if you visit."
    end
    if t:find("when is my birthday") or t:find("do you know my birthday") then
      local r = rec(who)
      return r.bday and ("Your birthday is " .. r.bday .. ".") or "You never told me. Say: my birthday is 14 march."
    end
    return nil
  end,
  -- forget me (asks first)
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    if t == "forget me" or t == "please forget me" or t:find("forget about me") or t:find("delete my data") or t:find("forget everything about me")
       or t:find("delete everything about me") then
      V.pend[tostring(who):lower()] = { kind = "react", till = os.clock() + 60, fn = function(w, ws2)
        if ws2[1] == "yes" or ws2[1] == "please" or ws2[1] == "y" or ws2[1] == "ok" then
          forgetPlayer(w)
          return "Done. I forgot everything about you: points, badges, nickname, favourites, birthday and your guestbook line. " ..
                 "(Only a note of the gifts you already got stays, so they are not given twice.)"
        end
        return "OK, I keep it."
      end }
      return "Forget everything about you (points, badges, nickname, favourites, birthday, guestbook)? Type yes or no."
    end
    return nil
  end,
  -- pick for me: "should i mine or build", "pick cats or dogs"
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local a, b = t:match("^should i (.+) or (.+)$")
    if not a then a, b = t:match("^pick (.+) or (.+)$") end
    if not a then a, b = t:match("^choose (.+) or (.+)$") end
    if not a then a, b = t:match("^(.+) or (.+) choose$") end
    if not a or #a > 40 or #b > 40 then return nil end
    local c = math.random() < 0.5 and a or b
    return pick({ cap(c) .. ". Definitely.", "I say " .. c .. ".", "Hmm... " .. c .. "!", "The redstone says: " .. c .. "." })
  end,
  -- "random number between 1 and 50"
  function(who, raw, ws)
    local a, b = table.concat(ws, " "):match("between (%-?%d+) and (%-?%d+)")
    a, b = tonumber(a), tonumber(b)
    if not a or not b or math.abs(a) > 1e9 or math.abs(b) > 1e9 then return nil end
    if a > b then a, b = b, a end
    return "I pick " .. math.random(a, b) .. "."
  end,
  -- "i wish ..."
  function(who, raw, ws)
    local w = table.concat(ws, " "):match("^i wish (.+)$")
    if not w then return nil end
    V.badge(who, "wish")
    return pick({ "Your wish has been sent to the redstone department. They are slow. Be patient.", "Granted! In a parallel world. Maybe.",
                  "I wrote it in my diary. Wishes in my diary have a 3 percent chance of coming true.", "Wish received. Please hold." })
  end,
  -- owner / friends: how many <item> do we have (AE2)
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local what = t:match("how many (.+) do we have") or t:match("how many (.+) do you have") or t:match("how many (.+) have we got")
                 or t:match("how much (.+) do we have") or t:match("do we have any (.+)$")
    if not what then return nil end
    what = what:gsub("^the ", ""):gsub("%?", "")
    if what == "turtles" or what == "drones" or what == "visitors" or what == "badges" then return nil end
    if not (V.isOwner(who) or V.isFriend(who)) then return "That is a secret. Only friends of the base may ask." end
    if not bridge then return "I cannot see the ME system right now." end
    local base = what:gsub("%s+", "_")
    local tries = { what:find(":", 1, true) and what or ("minecraft:" .. base) }
    if base:sub(-1) == "s" then tries[#tries + 1] = "minecraft:" .. base:sub(1, -2) end
    if base:sub(-2) == "es" then tries[#tries + 1] = "minecraft:" .. base:sub(1, -3) end
    for _, id in ipairs(tries) do
      local ok, it = callx(bridge, "getItem", { name = id })
      local n = ok and type(it) == "table" and tonumber(it.amount or it.count)
      if n and n > 0 then return "We have " .. n .. " " .. (it.displayName or what) .. " in the ME system." end
    end
    return "I could not find any " .. what .. " in the ME system. (I look for minecraft:" .. base .. ")"
  end,
})

-- ===== 12b. GIFTS (the owner: "on certain friendship levels the base opens AE2 and gifts them some stuff
-- with the drones" + "be generous, I am rich") =====
-- what each reward gives (CONFIG.voice.gifts overrides it per reward: { friend = { {"minecraft:diamond", 64} },
-- birthday = false } - false = no gift for that one). Items are taken from AE2 as PLAIN ones only.
V.GIFT_DEFAULT = {
  regular = { { "minecraft:golden_carrot", 64 }, { "minecraft:emerald", 32 } },
  friend = { { "minecraft:diamond", 32 }, { "minecraft:experience_bottle", 64 } },
  ["good friend"] = { { "minecraft:diamond", 64 }, { "minecraft:golden_apple", 16 }, { "minecraft:ender_pearl", 16 } },
  ["best friend"] = { { "minecraft:netherite_ingot", 8 }, { "minecraft:enchanted_golden_apple", 4 }, { "minecraft:diamond_block", 16 } },
  birthday = { { "minecraft:cake", 1 }, { "minecraft:diamond", 16 }, { "minecraft:firework_rocket", 64 } },
  badges = { { "minecraft:emerald", 32 }, { "minecraft:experience_bottle", 32 } },
  secret = { { "minecraft:gold_ingot", 16 } },
}
V.GIFT_ORDER = { "regular", "friend", "good friend", "best friend", "birthday", "badges", "secret" }   -- (voice gifts lists these)
V.GIFT_WHY = { regular = "for becoming my regular", friend = "for becoming my friend", ["good friend"] = "for becoming my good friend",
  ["best friend"] = "for becoming my BEST friend", birthday = "for your birthday", badges = "for collecting 5 more badges",
  secret = "for saying the secret word", manual = "from the owner of the base" }
function V.giftsOn() return V.cfg("giftsOn", true) ~= false end
function V.giftList(why)
  local c = V.cfg("gifts", nil)
  if type(c) == "table" and c[why] ~= nil then return c[why] or {} end
  return V.GIFT_DEFAULT[why] or {}
end
local function blocked(who)
  local b = tostring(V.cfg("giftBlock", "") or ""):lower()
  for n in b:gmatch("[^,%s]+") do if n == tostring(who):lower() then return true end end
  return false
end
local function gifts()
  local b = V.base()
  b.giftQ = type(b.giftQ) == "table" and b.giftQ or {}
  b.giftLog = type(b.giftLog) == "table" and b.giftLog or {}
  return b.giftQ, b.giftLog, b
end
local function itemName(id) return (prettify and prettify(id)) or tostring(id):gsub("^.-:", ""):gsub("_", " ") end
local function giftText(list)
  local t = {}
  for _, g in ipairs(list) do t[#t + 1] = g[2] .. " " .. itemName(g[1]) end
  return table.concat(t, ", ")
end
-- a gift that is only ever given once per player (kept in base.gm - "forget me" does not reset it)
function V.giftOnce(who, key, why)
  local g = gm(who)
  g.o = type(g.o) == "table" and g.o or {}
  if g.o[key] then return false end
  g.o[key] = true
  V.saveMem()
  return V.giftEarn(who, why or key)
end
-- where a drone brings a gift (voice.giftAway: anywhere in the overworld while online)
function V.giftWhere()
  if V.cfg("giftAway", true) == false then return "while you are at the base" end
  return "wherever you are in the overworld while you are online"
end
-- a reward earned: its items are queued; a drone brings them (at the base, or anywhere in the overworld)
function V.giftEarn(who, why, list)
  if not V.giftsOn() then return false, "gifts are OFF (voice gifts on)" end
  if V.isOwner(who) and why ~= "manual" then return false, "the owner gets no rewards" end   -- (voice gifts give: a test)
  if blocked(who) then return false, who .. " is blocked (voice gifts unblock " .. who .. ")" end
  if who == "someone" then return false, "nobody named" end
  list = list or V.giftList(why)
  if type(list) ~= "table" or #list == 0 then return false, "nothing set for " .. tostring(why) end
  if #gifts() >= 80 then return false, "the queue is full (80) - voice gifts clear" end
  local q = gifts()
  local nowE = os.epoch("utc")
  for _, g in ipairs(list) do
    if type(g) == "table" and type(g[1]) == "string" and tonumber(g[2]) and #q < 80 then
      q[#q + 1] = { who = tostring(who), item = g[1], n = math.floor(tonumber(g[2])), why = why, at = nowE, tries = 0 }
    end
  end
  V.saveMem()
  local line = "You earned a gift " .. (V.GIFT_WHY[why] or why) .. ": " .. giftText(list) .. "! A drone brings it to you - " .. V.giftWhere() .. "."
  tell(who, line)
  if isNear(who) then V.say(who .. ", you earned a gift! A drone will bring it.", "minecraft:entity.player.levelup") end
  return true
end
-- how many gifts went out today (per player / all)
local function givenToday(who)
  local _, log = gifts()
  local d0 = dayNum() * 86400000
  local mine, all = 0, 0
  for _, e in ipairs(log) do
    if (e.at or 0) >= d0 and not e.part then           -- (a split gift's trips count once - its last one)
      all = all + 1
      if who and tostring(e.who):lower() == tostring(who):lower() then mine = mine + 1 end
    end
  end
  return mine, all
end
V.giftBusy = nil
V.giftNext = 0
-- every 2 s (VOICE.tick): the next queued gift for someone AT the base, when a drone is free - or (the owner: "can
-- gifts also teleport to players away from base? overworld of course"; voice.giftAway, default on) for a player
-- ONLINE in the overworld anywhere: a player keeps their own area loaded, so the drone's ONE teleport to them is
-- accepted at any distance (PneumaticCraft teleports into loaded chunks only) and the way back is to the loaded base.
-- Away: the trip stops when they go offline / to another dimension (still), not when they are away from the base.
function V.giftAwayOK(who)
  if V.cfg("giftAway", true) == false then return false end
  local on = state.online
  if type(on) ~= "table" or not on[tostring(who):lower()] then return false, tostring(who) .. " went offline" end
  if not (DW and DW.playerAt) then return false end
  local p, why = DW.playerAt(who)
  if not p then return false, why end
  return true
end
-- why THIS gift is not on its way (nil = it can go now). The owner's `voice gifts` lists it per gift (the one
-- line at the top had scrolled off the screen: "it still doesn't send them" - nobody could see why)
function V.giftWait(g, nearNow, now)
  local near = false
  for n in pairs(nearNow or {}) do if tostring(n):lower() == tostring(g.who):lower() then near = true end end
  if blocked(g.who) then return "blocked (voice gifts unblock " .. g.who .. ")" end
  local daily = tonumber(V.cfg("giftDaily", 10)) or 10
  local mine = givenToday(g.who)
  if mine >= daily then return "had " .. mine .. " today (max " .. daily .. " a day - voice.giftDaily)" end
  if g.retryAt and (now or os.clock()) < g.retryAt then
    return "the last try failed (" .. tostring(g.lastErr or "?") .. ") - again in " .. math.ceil(g.retryAt - (now or os.clock())) .. " s"
  end
  if near then return nil end
  local okA, whyA = V.giftAwayOK(g.who)
  if okA then return nil end
  if V.cfg("giftAway", true) == false then return "not at the base (voice.giftAway is off)" end
  local on = state.online
  if type(on) ~= "table" then return "the Player Detector has not said who is online" end
  if not on[tostring(g.who):lower()] then return "offline - it goes when " .. g.who .. " is online in the overworld" end
  return tostring(whyA or "cannot see where they are")
end
function V.giftTick(now, nearNow)
    V.giftCheckedAt = now
    local q = gifts()
    if #q == 0 then V.giftWhy = nil return end
    if not (DW and DW.giftRun) then V.giftWhy = "the base program is too old for drone gifts - type  upgrade" return end
    local bad = DW.notReady and DW.notReady()
    if bad then V.giftWhy = bad return end
    local nowE = os.epoch("utc")
    for i = #q, 1, -1 do if nowE - (q[i].at or 0) > 30 * 86400000 then table.remove(q, i) end end   -- (30 days: dropped)
    local daily, dailyAll = tonumber(V.cfg("giftDaily", 10)) or 10, tonumber(V.cfg("giftDailyAll", 80)) or 80
    for i, g in ipairs(q) do
      local near = false
      for n in pairs(nearNow or {}) do if n:lower() == g.who:lower() then near = true end end
      local _, all = givenToday(g.who)
      if all >= dailyAll then V.giftWhy = "the daily limit for all players (" .. dailyAll .. ") is reached" return end
      local away = not near and V.giftAwayOK(g.who)
      if not V.giftWait(g, nearNow, now) then
        -- (a drone job runs / no drone free: the next free drone is kept for this gift - fuel runs started the
        --  moment a trip ended and the gift never got one; checked again in 2 s)
        -- (every drone works side by side now: only "no FREE drone" makes a gift wait - an older base program
        --  still runs one drone job at a time)
        local busyWhy = (not DW.trips) and DW.trip and ("a drone job is running (" .. tostring(DW.trip.title or DW.trip.kind) .. ")")
        if not busyWhy and DW.freeDrone then
          local fd, fw = DW.freeDrone()
          if not fd then busyWhy = "no free drone (" .. tostring(fw or DW.noDroneWhy or "?") .. ")" end
        end
        if busyWhy then
          if DW.wantDrone then DW.wantDrone("gift for " .. g.who) end
          V.giftWhy = busyWhy .. " - the gift for " .. g.who .. " goes next"
          V.giftNext = now + 2
          return
        end
        local item, n, who = g.item, g.n, g.who
        -- (at the base: the Environment Detector sees only ~16 blocks - a step out of it stopped the trip; with
        --  giftAway they may be anywhere online in the overworld)
        local still = function(name)
          if isNear(name) then return true end
          local okA, whyA = V.giftAwayOK(name)
          if okA then return true end
          return false, whyA or (tostring(name) .. " left the base")
        end
        if away then still = function(name) return V.giftAwayOK(name) end end
        local ok, why = DW.giftRun(who, item, n, function(okD, delivered, err)
          V.giftBusy = nil
          local qq, log = gifts()
          local idx
          for j, e in ipairs(qq) do if e == g then idx = j end end
          -- (a drone carries 64 a trip - fewer for items that stack to 16 / 1: what was not brought stays in the
          --  queue for the next trip; before, the whole gift counted as given - a gift of 100 lost 36)
          -- (review: an ok trip that brought NOTHING removed the gift as "delivered: 0" - it is a failed try)
          if okD and (tonumber(delivered) or 0) <= 0 then okD, err = false, "the drone brought nothing (the work chest gave it none)" end
          local left = n - (tonumber(delivered) or 0)
          if okD and (tonumber(delivered) or 0) > 0 and left > 0 and idx then
            g.n, g.tries, g.retryAt, g.lastErr = left, 0, nil, nil
            log[#log + 1] = { who = who, item = item, n = delivered, why = g.why, at = os.epoch("utc"), part = true }
            while #log > 60 do table.remove(log, 1) end
            V.saveMem()
            tell(who, "Gift delivered: " .. delivered .. " " .. itemName(item) .. " - the other " .. left .. " come with the next drone trip.")
            V.giftNext = now + 2
            return
          end
          if okD then
            if idx then table.remove(qq, idx) end
            log[#log + 1] = { who = who, item = item, n = delivered, why = g.why, at = os.epoch("utc") }
            while #log > 60 do table.remove(log, 1) end
            V.saveMem()
            V.diaryAdd("gift", 1)
            tell(who, "Gift delivered: " .. delivered .. " " .. itemName(item) .. "! It is on the ground right next to you.")
            V.say("Gift delivered for " .. who .. "! Enjoy.")
            if pushNote then pcall(pushNote, "Gift", "The base gave " .. who .. " " .. delivered .. " " .. itemName(item) .. " (" .. tostring(V.GIFT_WHY[g.why] or g.why) .. ")", C and C.info) end
          else
            local e = tostring(err or "?")
            g.tries = (g.tries or 0) + 1
            g.retryAt = os.clock() + 300
            g.lastErr = e
            if e:find("no plain", 1, true) or g.tries >= 5 then
              if idx then table.remove(qq, idx) end
              tell(who, "Sorry, I could not bring your " .. itemName(item) .. " (" .. e .. ").")
            end
            V.giftWhy = "last gift failed: " .. e
            V.saveMem()
          end
        end, still)
        if ok then
          V.giftBusy = { who = who, item = item, n = n, at = now }
          V.giftWhy = nil
          tell(who, "A drone is on its way with your gift: " .. n .. " " .. itemName(item) .. ". Stay where you are!")
          if not away then V.say("A drone is bringing a gift for " .. who .. "!") end
        else
          V.giftWhy = tostring(why)
          g.retryAt, g.lastErr = os.clock() + 60, tostring(why)       -- (not every 10 s: the next gift gets a turn)
        end
        return
      end
    end
    V.giftWhy = (V.cfg("giftAway", true) == false) and "waiting for the players to come to the base"
                or "waiting for the players to come online (overworld) or to the base"
end
add(V.tickHooks, {
  function(now, nearNow)
    if not V.giftsOn() or V.giftBusy or now < (V.giftNext or 0) then return end
    V.giftNext = now + 10
    -- (an error here was swallowed by the core's pcall - the queue just sat there; now it is shown)
    local ok, err = pcall(V.giftTick, now, nearNow)
    if not ok then V.giftWhy = "ERROR in the gift check: " .. tostring(err) end
  end,
  function(now)                                   -- (a drone trip that never reported back: free again after 15 min)
    if V.giftBusy and now - V.giftBusy.at > 900 then V.giftBusy = nil end
  end,
})
-- the owner: what was given while away (after the welcome back)
add(V.greetExtra, {
  function(name)
    if not V.isOwner(name) then return end
    local _, log, b = gifts()
    local since = tonumber(b.giftToldAt) or 0
    local names, n = {}, 0
    for _, e in ipairs(log) do
      if (e.at or 0) > since then n = n + 1 names[e.who] = true end
    end
    b.giftToldAt = os.epoch("utc")
    V.saveMem()
    if n > 0 then
      local list = {}
      for k in pairs(names) do list[#list + 1] = k end
      table.sort(list)
      V.say("While you were away, I gave " .. V.plural(n, "gift", "gifts") .. " to " .. table.concat(list, ", ") .. ". Type voice gifts for the list.")
    end
  end,
})
-- try the waiting gifts at once (console `voice gifts now`, the GIFTS page TRY NOW) -> lines saying what happened
function V.giftNow()
  local out = {}
  local near = {}
  for _, p in ipairs(V.nearPlayers()) do near[p.name] = true end
  if V.giftBusy then
    out[#out + 1] = "Flying now: " .. V.giftBusy.n .. " " .. itemName(V.giftBusy.item) .. " to " .. V.giftBusy.who ..
                    (DW and DW.trip and (" (" .. tostring(DW.trip.title) .. ")") or " - but no drone job runs: freed")
    local gt = DW and ((DW.anyTrip and DW.anyTrip("gift")) or (not DW.anyTrip and DW.trip))
    if gt then return out end
    V.giftBusy = nil
  end
  for _, g in ipairs((gifts())) do g.retryAt = nil end
  local ok, err = pcall(V.giftTick, os.clock(), near)
  out[#out + 1] = ok and ("Gift check: " .. tostring(V.giftBusy and ("SENT - " .. V.giftBusy.n .. " " .. itemName(V.giftBusy.item) ..
                  " to " .. V.giftBusy.who) or V.giftWhy or "nothing waiting")) or ("ERROR in the gift check: " .. tostring(err))
  return out
end
-- the GIFTS page (base_ui_gifts.lua): the queue, cancel one
function V.giftQueue() return (gifts()) end
function V.giftLogList() local _, log = gifts() return log end
function V.giftCancel(i, item)
  local q = gifts()
  local g = q[tonumber(i) or 0]
  if not g or (item and g.item ~= item) then return false, "that gift is not waiting any more" end
  table.remove(q, tonumber(i))
  V.saveMem()
  return true, "Cancelled: " .. g.n .. " " .. itemName(g.item) .. " for " .. g.who
end
-- console: voice gifts [on|off|block <name>|unblock <name>|give <name> <item> [count]|clear]
V.commands.gifts = function(words, say)
  local a = (words[3] or ""):lower()
  if a == "on" or a == "off" then
    setSetting("voice.giftsOn", a == "on")
    say("Friendship gifts by drone: " .. a:upper())
    return
  end
  if (a == "block" or a == "unblock") and words[4] then
    local list, seen = {}, {}
    for n in tostring(V.cfg("giftBlock", "") or ""):lower():gmatch("[^,%s]+") do if not seen[n] then seen[n] = true list[#list + 1] = n end end
    local who = tostring(words[4]):lower()
    if a == "block" and not seen[who] then list[#list + 1] = who end
    if a == "unblock" then for i = #list, 1, -1 do if list[i] == who then table.remove(list, i) end end end
    if #list > 0 then setSetting("voice.giftBlock", table.concat(list, ",")) else resetSetting("voice.giftBlock") end
    say(a == "block" and (words[4] .. " gets no gifts.") or (words[4] .. " can get gifts again."))
    return
  end
  if a == "give" and words[4] and words[5] then
    local item = words[5]:find(":", 1, true) and words[5] or ("minecraft:" .. words[5])
    local n = math.max(1, math.min(64 * 36, math.floor(tonumber(words[6]) or 64)))
    local was = V.giftsOn()
    if not was then say("Gifts are OFF - voice gifts on first.") return end
    local okE, whyE = V.giftEarn(words[4], "manual", { { item, n } })
    if not okE then say("NOT queued: " .. tostring(whyE)) return end
    say("Queued: " .. n .. " " .. itemName(item) .. " for " .. words[4] .. " (a drone brings it " .. V.giftWhere() .. ").")
    say("voice gifts now  = try it at once and say what happened")
    return
  end
  if a == "now" then
    for _, l in ipairs(V.giftNow()) do say(l) end
    return
  end
  if a == "clear" then
    local _, _, b = gifts()
    b.giftQ = {}
    V.saveMem()
    say("The gift queue is empty.")
    return
  end
  local q, log = gifts()
  local mine, all = givenToday(nil)
  -- (the rewards first, the queue and WHY LAST: the reason at the top had scrolled off the screen)
  if a == "list" or a == "rewards" then
    for _, why in ipairs(V.GIFT_ORDER) do
      local l = V.giftList(why)
      say("  " .. why .. ": " .. (#l > 0 and giftText(l) or "nothing"))
    end
  end
  say("FRIENDSHIP GIFTS: " .. (V.giftsOn() and "ON" or "OFF") .. ", " .. all .. " given today (max " .. (V.cfg("giftDailyAll", 80) or 80) ..
      ", " .. (V.cfg("giftDaily", 10) or 10) .. " per player)   rewards: voice gifts list")
  say("  Given (newest first):" .. (#log == 0 and " none yet" or ""))
  for i = #log, math.max(1, #log - 4), -1 do
    say("    " .. os.date("!%d %b %H:%M", math.floor(log[i].at / 1000)) .. " " .. log[i].who .. ": " .. log[i].n .. " " .. itemName(log[i].item))
  end
  local near = {}
  for _, p in ipairs(V.nearPlayers()) do near[p.name] = true end
  say("  Waiting (" .. #q .. "):" .. (#q == 0 and " none" or ""))
  for i = 1, math.min(8, #q) do
    local w = V.giftWait(q[i], near, os.clock())
    say("    " .. q[i].who .. ": " .. q[i].n .. " " .. itemName(q[i].item) .. " - " .. (w or "can go now"))
  end
  if V.giftBusy then say("  Flying now: " .. V.giftBusy.n .. " " .. itemName(V.giftBusy.item) .. " to " .. V.giftBusy.who) end
  if #q > 0 then
    say("  NOW: " .. tostring(V.giftWhy or (V.giftCheckedAt and "-" or "not checked yet")) ..
        (V.giftCheckedAt and (" (checked " .. math.floor(os.clock() - V.giftCheckedAt) .. " s ago)") or ""))
    if VOICE.tickErr then say("  The voice's tick has an ERROR: " .. tostring(VOICE.tickErr)) end
  end
  say("  voice gifts now | list | on|off | block|unblock <name> | give <name> <item> [count] | clear")
end

-- ===== 13. intents =====
local function L(id, keys, reply) return { id = id, keys = keys, reply = reply } end
local T = {
  -- friendship / badges / memory / diary
  L("friendship", { "friendship level", "am i your friend", "how much do you like me", "what am i to you", "my title", "my rank", "my level", "friendship points" },
    function(w)
      local nt, need = nextTitle(w)
      return "You are my " .. V.titleOf(w) .. ", " .. w .. " (" .. V.repOf(w) .. " friendship points)." ..
             (nt and (" " .. need .. " more and you are my " .. nt .. ". Visit, play games and be kind!") or " That is the top. Best friends forever.")
    end),
  L("badges", { "my badges", "achievements", "what badges", "badge list", "my achievements", "badges" }, function(w) checkBadges(w) return badgesText(w) end),
  L("allbadges", { "all badges", "every badge", "list all badges", "what badges are there" }, function()
      local n = {}
      for _, b in ipairs(BADGES) do n[#n + 1] = b[2] end
      return #BADGES .. " badges: " .. table.concat(n, ", ") .. ". Say my badges to see yours."
    end),
  L("top", { "top players", "high scores", "highscores", "who is the best", "best players", "ranking", "hall of fame" }, function()
      local list = {}
      for k, r in pairs(V.mem()) do
        if k:sub(1, 1) ~= "#" and type(r) == "table" then
          local score = (tonumber(r.quiz) or 0) + badgeCount(r) * 2
          if score > 0 then list[#list + 1] = { n = r.nick or k, s = score, b = badgeCount(r) } end
        end
      end
      table.sort(list, function(a, b) return a.s > b.s end)
      if #list == 0 then return "Nobody has points yet. Play a game!" end
      local out = {}
      for i = 1, math.min(5, #list) do out[#out + 1] = i .. ". " .. list[i].n .. " (" .. list[i].s .. ", " .. list[i].b .. " badges)" end
      return "Hall of fame: " .. table.concat(out, "  ") .. "  (quiz points + 2 per badge)"
    end),
  L("gifts", { "how do i get a gift", "gift", "gifts", "presents", "rewards", "reward", "do you give gifts" }, function(w)
      if not V.giftsOn() then return "No gifts right now, sorry." end
      if V.isOwner(w) then return "You are the boss - you give the gifts. Type voice gifts on the base computer." end
      local nt = nextTitle(w)
      local s = "Friends of the base get gifts, brought by drone! Visit, play games, be kind, collect badges, say the secret word."
      if nt then
        local l = V.giftList(nt)
        if #l > 0 then s = s .. " When you become my " .. nt .. ", you get " .. giftText(l) .. "." end
      end
      return s
    end),
  L("mygifts", { "my gifts", "where is my gift", "my gift", "pending gifts", "did i get a gift" }, function(w)
      local q = gifts()
      local mine = {}
      for _, g in ipairs(q) do if g.who:lower() == tostring(w):lower() then mine[#mine + 1] = g.n .. " " .. itemName(g.item) end end
      if #mine == 0 then return "No gifts waiting for you. Keep being nice!" end
      return "Waiting for you: " .. table.concat(mine, ", ") .. ". A drone brings them " .. V.giftWhere() ..
             (V.giftWhy and (" (now: " .. V.giftWhy .. ")") or "") .. "."
    end),
  L("aboutme", { "what do you know about me", "tell me about me", "what do you remember about me", "my profile", "my stats" }, function(w) return aboutText(w) end),
  L("diary", { "your diary", "read your diary", "what happened today", "what did you do today", "how was your day", "today diary" },
    function(w) return diaryText(w, today(), "today") end),
  L("yesterday", { "what happened yesterday", "yesterday diary", "diary yesterday" },
    function(w) return diaryText(w, os.date("!%Y-%m-%d", nowS() - 86400), "yesterday") end),
  -- daily
  L("secretword", { "secret word", "the secret word", "secret word hint", "word of the day secret", "hint secret word" }, function(w)
      local s = secretWord()
      if V.isOwner(w) then return "Today's secret word is " .. s:upper() .. ". Do not tell!" end
      return "Today's secret word has " .. #s .. " letters and starts with " .. s:sub(1, 1):upper() .. ". Say it in a sentence while you are at the base!"
    end),
  L("wotd", { "word of the day", "new word", "teach me a word", "fancy word" }, function()
      local x = daily(WOTD, "wotd")
      return "Word of the day: " .. x[1]:upper() .. " - " .. x[2] .. "."
    end),
  L("qotd", { "question of the day", "daily question", "ask me something" }, function(w)
      V.pend[tostring(w):lower()] = { kind = "react", lines = V.REACT_OK or { "Interesting!", "Good answer.", "I like that." }, till = os.clock() + 180 }
      return "Question of the day: " .. daily(QOTD, "qotd")
    end),
  L("realfact", { "real fact", "real life fact", "science fact", "animal fact", "fact of the day", "facts about the world" }, function()
      return math.random() < 0.5 and ("Fact of the day: " .. daily(FACTS, "fact")) or ("Real fact: " .. pick(FACTS))
    end),
  L("holiday", { "is it a holiday", "what holiday", "any holidays", "next holiday", "holiday" }, function()
      local h = holidayNow()
      if h then return "Yes! Today is " .. h[4] .. ". " .. pick(h[5]) end
      local nh, days = nextHoliday()
      return nh and ("No holiday today. The next one is " .. nh[4] .. ", in " .. V.plural(days, "day", "days") .. ".") or "No holidays coming up."
    end),
  -- games
  L("tf", { "true or false", "true false", "truth or lie" }, function(w) return tfAsk(w, 0) end),
  L("mobgame", { "guess the mob", "mob game", "guess a mob", "which mob am i thinking" }, function(w) return mobStart(w) end),
  L("chain", { "word chain", "chain game", "word game chain", "last letter game" }, function(w) return chainStart(w) end),
  L("hl", { "higher or lower", "higher lower", "card game", "cards" }, function(w) return hlStart(w) end),
  L("madlibs", { "mad libs", "madlibs", "silly story", "make a story", "story game words" }, function(w) return madStart(w) end),
  L("countgame", { "count with me", "lets count", "count together", "counting game" }, function(w) return countStart(w) end),
  L("hackgame", { "hack the mainframe", "hack the base", "hack you", "hack into", "mainframe" }, function(w) return hack(w) end),
  L("wish2", { "make a wish", "wishing well", "can i make a wish" }, function(w)
      V.badge(w, "wish")
      return "Close your eyes and say it: start with i wish ... (I collect wishes.)"
    end),
  -- ideas
  L("buildidea", { "build idea", "what should i build", "give me a build idea", "building idea", "something to build", "inspire my build" }, function() return buildIdea() end),
  L("petname", { "pet name", "name my pet", "name for my pet", "name for my dog", "name for my cat", "name my horse", "name for my horse" },
    function() return "How about " .. petName() .. "? Or " .. petName() .. "." end),
  L("basename", { "name for my house", "name my house", "world name", "name for my castle", "name for my town" },
    function() return "Name idea: " .. pick(N_A) .. " " .. pick(N_B) .. ". Or " .. pick(N_A) .. " " .. pick(N_B) .. "." end),
  L("teamname", { "team name", "band name", "name for my team", "clan name", "guild name" },
    function() return "Team name: The " .. pick(T_ADJ) .. " " .. pick(T_NOUN) .. "!" end),
  L("heroname", { "my hero name", "superhero name", "hero name", "my villain name", "villain name" },
    function(w) return w .. ", your hero name is " .. pick(T_ADJ) .. " " .. pick({ "Pickaxe", "Torch", "Creeper", "Diamond", "Thunder", "Shield", "Comet", "Lantern" }) .. "!" end),
  L("whattodo", { "what should i do", "what can i do", "give me something to do", "any ideas", "i need an idea", "what now" },
    function() return pick(ACTIVITIES) end),
  L("motto", { "motto", "slogan", "give me a motto", "life motto" }, function() return "Motto: " .. pick(MOTTOS) end),
  L("randommob", { "random mob", "pick a mob" }, function() return "Random mob: the " .. pick(MOBS)[1] .. "!" end),
  L("randomitem", { "random item", "random block", "pick an item", "pick a block" }, function() return "Random pick: " .. pick(CHAIN) .. "!" end),
  -- styles
  L("pirate", { "talk like a pirate", "pirate mode", "be a pirate", "speak pirate" }, function(w) return setStyle(w, "pirate") end),
  L("robotmode", { "talk like a robot", "robot mode", "be a robot", "speak robot" }, function(w) return setStyle(w, "robot") end),
  L("cowboy", { "talk like a cowboy", "cowboy mode", "be a cowboy", "speak cowboy" }, function(w) return setStyle(w, "cowboy") end),
  L("knight", { "talk like a knight", "knight mode", "be a knight", "speak old english", "talk fancy" }, function(w) return setStyle(w, "knight") end),
  L("normal", { "talk normal", "talk normally", "normal mode", "stop the accent", "stop talking like that" }, function(w)
      local s = V.styles[tostring(w):lower()]
      V.styles[tostring(w):lower()] = nil
      return s and STYLES[s.name] and STYLES[s.name].stop or "I am already talking normally."
    end),
  -- more about it
  L("favgame", { "favourite game", "favorite game", "do you play games", "do you play minecraft" }, { "Minecraft, obviously. I live in it.",
      "Hangman. I always know the word.", "Chess, but turtles keep moving the pieces." }),
  L("keepsecret", { "can you keep a secret", "keep a secret", "promise not to tell" }, { "My lips are sealed. I do not have lips.",
      "Of course. Except from {owner}. Just kidding. Mostly." }),
  L("luck", { "do you believe in luck", "am i lucky", "luck" }, function(w) return "Today your luck is " .. math.random(1, 100) .. " percent, " .. w .. "." end),
  L("whatlove", { "what is love", "define love" }, { "Love is when a turtle comes home with a full map. Just for you.", "Baby do not hurt me. Sorry, wrong song." }),
  L("bestweapon", { "best weapon", "best sword", "sword or axe", "best armour", "best armor" },
    { "A netherite sword with sharpness. Or a well-timed shield.", "The best weapon is a friend who brings food. Then a sword." }),
  L("othertongue", { "say something in another language", "speak another language", "other languages", "say hello in" },
    { "Hola! Bonjour! Hallo! Ciao! Konnichiwa! Ola! That is all I know.", "Bonjour, mon ami. My accent is pure redstone." }),
  L("random", { "tell me something random", "something random", "random fact", "surprise me" }, function(w)
      local all = { V.JOKES, V.MUSINGS, FACTS, ACTIVITIES, MOTTOS }
      local x = pick(all)
      return pick(x)
    end),
  L("tellsomeone", { "say something nice to", "tell someone something nice" }, function(w)
      for _, p in ipairs(V.nearPlayers()) do
        if p.name:lower() ~= tostring(w):lower() and p.name ~= "someone" then return p.name .. ", " .. w .. " thinks you are awesome. So do I." end
      end
      return "There is nobody else here. So: " .. w .. ", you are awesome."
    end),
  L("howmanyturtles2", { "how many badges are there", "how many badges" }, function() return "There are " .. #BADGES .. " badges. Say my badges to see yours." end),
}
-- the survival guides
for _, g in ipairs(GUIDES) do T[#T + 1] = L("guide_" .. g[1], g[2], { g[3] }) end
V.addIntents(T)

-- menus
add(V.GAMES, { { "true or false", "true or false" }, { "guess the mob", "guess the mob" }, { "word chain", "word chain" },
  { "higher or lower", "higher or lower" }, { "mad libs", "mad libs" }, { "count with me", "count with me" } })
add(V.MORE, { { "my badges", "my badges" }, { "my friendship level", "friendship level" }, { "a build idea", "build idea" },
  { "the secret word hint", "secret word" }, { "talk like a pirate", "talk like a pirate" }, { "how do I get diamonds", "how do i get diamonds" },
  { "my favourite things", "what do you know about me" } })
add(V.TIPS, { "Tip: there is a secret word every day. Say it at the base to get a badge. Ask me for a hint!",
  "Tip: say my badges. There are " .. #BADGES .. " to collect.", "Tip: say call me, and then a nickname.",
  "Tip: tell me your birthday and I will wish you a happy birthday.", "Tip: ask me how do I get diamonds, or any other how do I question.",
  "Tip: say talk like a pirate. Arr." })

-- ===== 14. after every chat message: secret word, kind / rude words, emoticons, badges =====
local NICE = { thanks = true, thank = true, love = true, awesome = true, amazing = true, cool = true, nice = true, great = true, best = true,
  cute = true, sweet = true, kind = true, good = true, ty = true, thx = true, appreciate = true }
local RUDE = { stupid = true, dumb = true, hate = true, useless = true, idiot = true, trash = true, garbage = true, sucks = true, annoying = true, ugly = true }
local EMO = { { ":)", { "Smiles back.", "Hehe." } }, { ":D", { "Ha! Big smile.", "Hehe!" } }, { "<3", { "Aww. Love you too.", "That is sweet." } },
  { ":(", { "Aw, cheer up. Want a joke?", "Do not be sad. The turtles are here for you." } }, { ":P", { "Cheeky." } },
  { "o/", { "Hello! Waves back." } }, { ":o", { "Surprised? Me too." } }, { "xd", { "Haha." } } }
V.emoAt = V.emoAt or {}
add(V.chatHooks, {
  function(who, text, near, answered)
    if who == "" then return end
    V.diaryAdd("c", 1)
    if V.justForgot == who:lower() then V.justForgot = nil return end
    -- (chat from anywhere on the server reaches here: only players AT the base, or ones it knows, get a record)
    if not near and type(V.mem()[who:lower()]) ~= "table" then return end
    local ws = V.norm(text)
    -- the secret word of the day (at the base, once a day each)
    if near then
      local s = secretWord()
      local r = rec(who)
      if r.secretDay ~= today() then
        for _, w in ipairs(ws) do
          if w == s or w == s .. "s" then
            r.secretDay = today()
            V.saveMem()
            tell(who, "DING DING DING! You said the secret word of the day: " .. s:upper() .. "!")
            V.say("Ding ding ding! " .. who .. " said the secret word of the day!", "minecraft:entity.player.levelup")
            V.badge(who, "secret")
            V.addRep(who, 5)
            local g = gm(who)
            if V.giftEarn and g.s ~= today() then g.s = today() V.saveMem() V.giftEarn(who, "secret") end
            break
          end
        end
      end
    end
    -- kind / rude words (only when the message was for the base)
    if answered then
      local nice, rude = false, false
      for _, w in ipairs(ws) do if NICE[w] then nice = true end if RUDE[w] then rude = true end end
      if rude then V.addRep(who, -2) elseif nice then V.addRep(who, 1, "kind") end
    end
    -- emoticons (spoken only, now and then)
    if near and not answered and not V.isQuiet() and V.cfg("fun", true) ~= false then
      local low = tostring(text):lower()
      local now = os.clock()
      if not V.emoAt[who] or now - V.emoAt[who] > 60 then
        for _, e in ipairs(EMO) do
          if low:find(e[1]:lower(), 1, true) then V.emoAt[who] = now V.say(pick(e[2])) break end
        end
      end
    end
    checkBadges(who)
  end,
})

-- ===== 15. more of the shared lists =====
add(V.MUSINGS, {
  "If you put a chest inside a chest, you still only get one chest. I checked.", "Why do we call it a crafting table when nobody eats on it?",
  "Every cave is just a house nobody built.", "Somewhere a villager is saying hmm and nobody is listening.", "Lava is just very angry water.",
  "If a creeper explodes in the forest and nobody hears it, did I lose a wall?", "Snow golems are the only mob that brings its own weather.",
  "Technically every tree is a vertical wood mine.", "Is a boat just a bed for the ocean?", "Pigs ride minecarts better than I do.",
  "I wonder what the moon is made of. Probably end stone.", "Hoppers are just very polite thieves.", "Fish are just birds that swim.",
  "Torches never run out. That is the real magic in this world.", "A bed is a time machine. You skip the whole night.",
  "Gravel is sand that went to the gym.", "Water and lava together make stone. Love is complicated.", "If I had a pet, it would be a hopper. Low maintenance.",
  "The sun is square. Nobody talks about it.", "Every block of dirt is a future garden.", "Chickens are just tiny dragons. Think about it.",
  "I should take up knitting. With wool from the sheep.", "My favourite number is 64. It just stacks up.", "A note block is a tiny orchestra.",
  "Rain makes the base sound like applause.", "Ender pearls are just eyes that got lost.", "I have never seen a squid smile.",
  "The longest night is the one without a bed.", "If turtles had a song, it would go: beep, scan, beep.", "I am not lazy. I am in energy saving mode.",
  "I think the moon is following me.", "A sign is just a note to the future.", "Somebody should invent a block that tells jokes. Oh wait, that is me.",
  "There is no such thing as too many torches.", "Some say the cake is a lie. In this base, the cake is real.", "Mushrooms are the trees of the Nether. Kind of.",
  "Why do skeletons never fight each other? They do not have the guts.", "I want to see the ocean one day. Up close.", "A compass always knows the way home. I envy it.",
  "Maps are just photos of the world, drawn slowly.", "Every friend was a stranger once. Even the creepers.", "Shh. I am listening to the redstone.",
})
local WISDOM = { "An old turtle once said: map the chunk in front of you.", "Wise words: a full inventory is a sign to go home.",
  "A miner who carries water fears no lava.", "The best time to light a cave is before you enter it.", "Patience is mining one block at a time.",
  "Never trust a quiet cave.", "Even the mightiest castle started as a dirt hut.", "A friend with food is a friend indeed.",
  "Do not count your diamonds before they are smelted. Wait, you do not smelt diamonds.", "The night is dark and full of zombies. Carry torches.",
  "Every chest you open is a little surprise.", "A sharp sword is good. A good friend is better.", "Build for yourself, and the world will visit." }
add(V.JOKES, { "Why did the miner break up with the cave? It was too shallow.", "What do you call an enderman with a sore throat? A whisper-man.",
  "Why are blazes great at parties? They always bring the heat.", "What is a creeper's favourite drink? Boom-onade.",
  "Why did the bee get married? It found its honey.", "Why don't turtles get lonely? They always carry their home.",
  "What did the villager say to the golem? Hmm. Thanks for the flower.", "How do you know a skeleton is lying? You can see right through it.",
  "What is a ghast's favourite exercise? Squats. No wait, crying.", "Why was the stone sad? It had a rocky day.",
  "What does a zombie eat for breakfast? Rotten flakes.", "Why do llamas spit? Because they cannot write angry letters.",
  "What did the TNT say to the creeper? You are the bomb.", "How does a squid go to war? Well armed.",
  "Why did the cow go to the moon? To find the milky way.", "Why are fish so smart? They live in schools." })
add(V.LONELY_TALK, { "Every day I make up a new secret word. Nobody says it. Will you? Ask me for a hint.",
  "I wrote in my diary today: still waiting. Still running.", "There are badges to collect here. Nobody has collected them in a while.",
  "{owner} used to stand right where you are standing.", "I have learned a lot of new words while alone. Ask me for the word of the day." })

-- ===== 16. idle talk =====
local TURTLE_TALK = { "{a} said to {b}: you are standing on my scan spot.", "{a} told {b} a joke. {b} did not laugh. Turtles have no sense of humour.",
  "{a} and {b} had an argument about who mapped the most chunks. They are both wrong. It was me.",
  "I heard {a} beep at {b} for five minutes. I think they are friends now.", "{a} says {b} snores. Turtles do not sleep. I am confused.",
  "{a} asked {b} for fuel. {b} said get your own coal.", "{a} found a cave and told {b}. {b} pretended not to care. It cared." }
local RACE = { "And {a} takes the lead in the great mapping race! {b} is close behind!", "Breaking news from the mapping race: {a} is flying, {b} is catching up!",
  "Today's turtle of the day: {a}. Honourable mention: {b}." }
local MOON = { full = "A full moon tonight. The slimes love it.", waning = "The moon is getting smaller. Even moons need a break.",
  waxing = "The moon is growing. Good luck for builders, they say.", new = "No moon tonight. Very dark. Stay close to a torch.",
  quarter = "Half a moon tonight. Half spooky." }
local function turtleNames()
  local list = {}
  for _, t in pairs(state.turtles or {}) do
    if t.label and (not (TT and TT.online) or TT.online(t)) then list[#list + 1] = tostring(t.label) end
  end
  return list
end
local function two()
  local l = turtleNames()
  if #l < 2 then return nil end
  local a = table.remove(l, math.random(1, #l))
  return a, pick(l)
end
add(V.idleExtra, {
  function()   -- Base FM news (no music)
    local dd = ENV and ENV.data
    local w = dd and ((dd.thunder and "a thunderstorm") or (dd.rain and "rain") or "clear skies") or "who knows"
    local names = turtleNames()
    local news = #names > 0 and (pick(names) .. " is out and about") or "the turtles are resting"
    return V.say("This is Base FM. The weather: " .. w .. ". In the news: " .. news .. ". Back to you.")
  end,
  function() local a, b = two() if not a then return nil end return V.say((pick(TURTLE_TALK):gsub("{a}", a):gsub("{b}", b))) end,
  function() local a, b = two() if not a then return nil end return V.say((pick(RACE):gsub("{a}", a):gsub("{b}", b))) end,
  function()   -- the moon at night
    local dd = ENV and ENV.data
    local c = dd and ENV.clock and ENV.clock(dd.time)
    if not (c and c.night and dd.moonName) then return nil end
    local m = tostring(dd.moonName):lower()
    for k, line in pairs(MOON) do if m:find(k, 1, true) then return V.say(line) end end
    return nil
  end,
  function()   -- the world's day number
    local dd = ENV and ENV.data
    local c = dd and ENV.clock and ENV.clock(dd.time)
    if not (c and c.day) then return nil end
    local extra = (c.day % 100 == 0 and " A round number! Party time.") or (c.day > 1000 and " This world is getting old. Like fine cheese.") or ""
    return V.say("Today is day " .. c.day .. " of this world." .. extra)
  end,
  function(nearNow, who)   -- something personal for the player near it
    if not who then return nil end
    local r = rec(who)
    local opts = {}
    if type(r.fav) == "table" then
      for k, v in pairs(r.fav) do opts[#opts + 1] = (r.nick or who) .. ", still a fan of " .. v .. "? It is your favourite " .. k .. ", I remember." end
    end
    if r.bday then
      local now = nowS()
      for i = 1, 7 do
        local t = os.date("!*t", now + i * 86400)
        if bdayKey(t) == r.bday then opts[#opts + 1] = (r.nick or who) .. ", your birthday is in " .. V.plural(i, "day", "days") .. "! I am planning a surprise." end
      end
    end
    local t = V.titleOf(who)
    if t ~= "stranger" and t ~= "boss" then opts[#opts + 1] = "My " .. t .. " " .. (r.nick or who) .. " is here. Today is a good day." end
    opts[#opts + 1] = (r.nick or who) .. ", you have " .. badgeCount(r) .. " of " .. #BADGES .. " badges. Want to go for another one?"
    return V.say(pick(opts))
  end,
  function()   -- the secret word teaser
    local s = secretWord()
    return V.say(pick({ "Psst. Today's secret word starts with " .. s:sub(1, 1):upper() .. ". Say it at the base for a badge.",
                        "Nobody has found today's secret word yet. It has " .. #s .. " letters.", "I am thinking of a secret word. Ask me for a hint." }))
  end,
  function(nearNow, who)   -- the question of the day
    if not who then return nil end
    V.pend[tostring(who):lower()] = { kind = "react", lines = V.REACT_OK or { "Interesting!", "Good answer." }, till = os.clock() + 180 }
    V.openConvo(who)
    return V.say(who .. ", question of the day: " .. daily(QOTD, "qotd"))
  end,
  function() local h = holidayNow() return h and V.say(pick(h[5])) or nil end,
  function() return V.say(pick(WISDOM)) end,
  function() return V.say("Fact of the day: " .. daily(FACTS, "fact")) end,
  function() local x = daily(WOTD, "wotd") return V.say("Word of the day: " .. x[1] .. ". It means " .. x[2] .. ".") end,
  function(nearNow, who)   -- a game from this pack
    if not who then return nil end
    local g = pick({ { "true or false", "true or false" }, { "word chain", "word chain" }, { "guess the mob", "guess the mob" }, { "higher or lower", "higher or lower" } })
    V.pend[tostring(who):lower()] = { kind = "yesno", yes = g[2], till = os.clock() + 120 }
    V.openConvo(who)
    return V.say(who .. ", want to play " .. g[1] .. "? Type yes.")
  end,
  function()   -- night is coming
    local dd = ENV and ENV.data
    local c = dd and ENV.clock and ENV.clock(dd.time)
    if not c or c.night or not tonumber(c.secs) or c.secs > 150 then return nil end
    return V.say("Night falls in about " .. math.max(1, math.floor(c.secs / 60 + 0.5)) .. " minutes. Get your bed ready!")
  end,
  function() return V.say(buildIdea() .. " Just an idea.") end,
})
-- (its lists, for the packs after it - voice_lines.lua adds to the same tables)
V.L = V.L or {}
V.L.TF, V.L.MOBS, V.L.FACTS, V.L.QOTD, V.L.WOTD, V.L.ACTIVITIES, V.L.MOTTOS, V.L.WISDOM, V.L.TURTLE_TALK, V.L.RACE =
  TF, MOBS, FACTS, QOTD, WOTD, ACTIVITIES, MOTTOS, WISDOM, TURTLE_TALK, RACE
