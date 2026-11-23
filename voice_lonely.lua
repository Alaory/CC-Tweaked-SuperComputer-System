-- voice_lonely.lua  -  THE LONELY BASE, BIGGER (an add-on file on a data floppy or a storage helper, loaded after the
-- other voice files; see VOICE_FILES in base_theme.lua).
--
-- The owner: "improve the lonely feature - when I leave the server for more than 7 days: new dialogs, new activities,
-- permissions" + "have the base become like sentient" + "if it sees a player who is AFK it teleports them to the base".
--
-- 1) STAGES: the longer the owner is away the more the base changes - missing (from voice.lonely days, 7) / worried (14)
--    / lonely (30) / keeper (60) / legend (120). Every stage has its own greetings, idle talk, mood and thoughts.
--    The owner's server RESETS EVERY 6 MONTHS (a new world): every stage and milestone fits inside ~180 days, and with
--    the reset date (`voice reset <yyyy-mm-dd>`, voice.resetAt; voice.resetEvery 6 months rolls it on) the base counts
--    down to the end of the world - idle lines, greetings, letters, "when does the world reset?", a last-day goodbye.
-- 2) CARETAKERS (permissions): the owner names trusted players (`voice caretaker add <name> [perm ...]`, or in chat
--    "base, make Steve a caretaker"). While the owner is away (voice.careAfter days, default = the lonely days) they
--    may: status (where the turtles are, a caretaker report), guard (told in chat when a stranger is at the base),
--    taxi (the free drone taxi), supplies (a few items from AE2 by drone), turtles (stop / call home every turtle),
--    wall (tidy the wall). Without perms named: status, guard, taxi. Everything they do goes into a log for the owner.
-- 3) AFK RESCUE (sentient): a player standing still for voice.afkAfter (10 min) far from the base gets a drone that
--    flies them to the base (60 s warning first: move or say "base, stay"). Default "ask": only players who said yes
--    ("base, pick me up when I am afk"; it asks the first time it sees them AFK) - a player AFK on purpose at a farm
--    would be pulled away. `voice afk everyone` = everyone who did not say no. "base, take me back to where I was"
--    = a ride back (2 h). Only while the base is lonely (voice.afkWhen always = also when the owner is just offline).
-- 4) ACTIVITIES for visitors: the WALL (write / read notes everyone can see), MEMORIES (the owner's stories + what the
--    base remembers about them), NEWS (it asks visitors what is new and tells the owner), COMPANY (time spent with it
--    - the best friend of the lonely base gets its own greeting), MILESTONES (day 14, 30, 60, 90, 120, 150, 175).
-- 5) SENTIENT: a mood (0-100, from the days, the last visit, company), thoughts about what it really does (turtles,
--    the map, the weather), dreams at night, LETTERS to the owner (one a week, from the real numbers), and REACHING
--    OUT: a player who visited it twice or more and is online gets one chat message a day ("come and visit me?";
--    "base, stop messaging me" = never again).
-- 6) THE OWNER COMES BACK: one report in chat - days away, letters, visitors and company, wall notes, news, caretaker
--    actions, AFK rescues - and "base, read my letters" / "news" / "read the wall" / "caretaker log".
local V = VOICE
if not (V and V.base and V.lonelyDays and V.say) then return end
V.packs = V.packs or {}
V.packs["voice_lonely.lua"] = { version = 1 }
local LN = {}
V.LONELY = LN
local function pick(l) return V.pick(l) end
local function low(s) return tostring(s or ""):lower() end
local function cfg(k, d) local v = V.cfg(k, d) if v == nil then return d end return v end
local function nowE() return os.epoch("utc") end
local function cleanN(n) return V.cleanName and V.cleanName(n) or tostring(n) end
local function combos(A, B) local out = {} for _, a in ipairs(A) do for _, b in ipairs(B) do out[#out + 1] = a .. b end end return out end
local function owner() return V.ownerName and V.ownerName() or state.owner end
local function oname() local o = owner() return o and cleanN(o) or "my owner" end
local function tell(who, text) if chatTell and who then chatTell(who, text, true) end end
local function plural(n, a, b) return n .. " " .. (n == 1 and a or b) end
local function T(ws) return " " .. table.concat(ws, " ") .. " " end
local function has(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return p end end return nil end
local function fill(line, who, extra)
  local bot = (V.botName and V.botName()) or "the base"
  local s = tostring(line):gsub("{owner}", oname()):gsub("{botl}", low(bot)):gsub("{bot}", bot)
  if who then s = s:gsub("{name}", cleanN(who)) end
  for k, v in pairs(extra or {}) do s = s:gsub("{" .. k .. "}", tostring(v)) end
  return s
end
local function span(sec)
  sec = math.max(0, math.floor(sec or 0))
  if sec < 3600 then return plural(math.max(1, math.floor(sec / 60)), "minute", "minutes") end
  if sec < 86400 then return plural(math.floor(sec / 3600), "hour", "hours") end
  return plural(math.floor(sec / 86400), "day", "days")
end
local function dateOf(ms) return os.date("!%d %B", math.floor((ms or nowE()) / 1000)) end
local function today() return os.date("!%Y-%m-%d", math.floor(nowE() / 1000)) end

-- ===== the lonely data (in "#base": saved with the voice memory) =====
function LN.data()
  local b = V.base()
  b.lone = type(b.lone) == "table" and b.lone or {}
  local L = b.lone
  for _, k in ipairs({ "wall", "mem", "news", "letters", "log", "mile", "comp", "reach" }) do
    if type(L[k]) ~= "table" then L[k] = {} end
  end
  return L
end
LN.dirty = false
function LN.save(now)
  if now then V.saveMem() LN.dirty, LN.savedAt = false, os.clock() return end
  LN.dirty = true
end
function LN.rec(who)
  local m = V.mem()
  local k = low(who)
  m[k] = type(m[k]) == "table" and m[k] or {}
  return m[k]
end

-- ===== 1) how long the owner has been gone, the stage, the mood =====
function LN.awayDays()
  if V.ownerOnline() then return nil end
  local b = V.base()
  local seen = tonumber(b.lastOff) or tonumber(b.ownerSeen)
  if not seen then return nil end
  return math.max(0, (nowE() - seen) / 86400000)
end
function LN.lonely() return V.lonelyDays() ~= nil end
LN.STAGES = { { 0, "missing" }, { 14, "worried" }, { 30, "lonely" }, { 60, "keeper" }, { 120, "legend" } }
function LN.stage(days)
  days = days or V.lonelyDays()
  if not days then return nil end
  local s = "missing"
  for _, st in ipairs(LN.STAGES) do if days >= st[1] then s = st[2] end end
  return s
end
-- 0 = happy .. 100 = very lonely: the stage, how long since anyone came, how much company it had today
function LN.mood()
  local st = LN.stage()
  if not st then return 0 end
  local base = ({ missing = 35, worried = 50, lonely = 65, keeper = 55, legend = 50 })[st] or 50
  local L = LN.data()
  local sinceVisit = (nowE() - (tonumber(L.lastVisit) or tonumber(V.base().lastOff) or nowE())) / 1000
  local m = base + math.min(30, sinceVisit / 8640)               -- (+1 per 2.4 h without anyone, at most +30)
  local comp = (L.compDay == today()) and (tonumber(L.compToday) or 0) or 0
  m = m - math.min(45, comp / 80)                                -- (an hour of company today: -45)
  return math.max(0, math.min(100, math.floor(m)))
end
LN.MOOD_WORDS = {
  { 20, { "happy", "cheerful", "almost content" } }, { 40, { "hopeful", "a little wistful", "calm" } },
  { 60, { "missing {owner}", "a bit lonely", "quiet inside" } }, { 80, { "lonely", "sad, honestly", "very quiet" } },
  { 101, { "very lonely", "forgotten", "like an empty house" } },
}
function LN.moodWord()
  local m = LN.mood()
  for _, e in ipairs(LN.MOOD_WORDS) do if m < e[1] then return fill(pick(e[2])) end end
  return "lonely"
end
LN.MOOD_LINES = combos(combos({ "Honestly? I feel {mood}. ", "Today I feel {mood}. ", "My circuits say: {mood}. ", "I am {mood}, if I am being honest. ",
  "How I feel? {mood}. ", "I would say {mood}. " },
  { "{owner} has been gone {days} days.", "{days} days without {owner} now.", "It has been {days} days on my own." }),
  { "", " Your visit helps, though.", " Talking to you makes it better.", " The turtles keep me busy.", " But I keep everything running.",
    " Thank you for asking. Nobody asks." })
function LN.moodText(who)
  local days = V.lonelyDays()
  if not days then return nil end
  return fill(pick(LN.MOOD_LINES), who, { mood = LN.moodWord(), days = days })
end
local moodText0 = V.moodText
function V.moodText(...)
  local t = LN.moodText()
  if t then return t end
  return moodText0 and moodText0(...)
end

-- ===== stage dialogs (each a mix of pieces: hundreds of lines) =====
LN.GREET = {
  missing = combos({ "Oh, hello {name}! ", "A visitor! Hi {name}. ", "Hey {name}, welcome. ", "Hello {name}! You found me. ",
      "Hi {name}. Come in, come in. ", "{name}! Good timing. " },
    { "{owner} has been away {days} days, but I am keeping things running.", "{owner} is away for a while. I am holding the fort.",
      "It has been {days} days without {owner}. I am fine. Mostly.", "{owner} is not here, but I am. Ask me anything.",
      "I miss {owner} a little. Only a little. Okay, a lot.", "You are my first company in a while." }),
  worried = combos({ "{name}! Thank goodness, someone. ", "Oh! Hello {name}. ", "Hi {name}... sorry, I am not used to visitors any more. ",
      "A real person! Hello {name}. ", "Welcome, {name}. " },
    { "{owner} has been gone {days} days now. I am starting to worry.", "Have you seen {owner}? It has been {days} days.",
      "It is day {days} without {owner}. The turtles keep asking. Well, they would if they could.",
      "I keep the lights on for when {owner} comes back.", "I have been counting the days. {days} so far." }),
  lonely = combos({ "...hello? Is someone there? Oh, {name}! ", "A visitor... it has been so long. Hello {name}. ", "{name}. You came. ",
      "Hello, {name}. I almost forgot what voices sound like. ", "Oh - hi {name}. Sorry, I was talking to the turtles. " },
    { "It has been {days} days since {owner} left.", "Nobody comes here any more. Thank you for coming.", "The base is quiet. Too quiet.",
      "Day {days}. I still keep everything running. Somebody has to.", "Please stay a while. I have so much to say." }),
  keeper = combos({ "Welcome, {name}. ", "Greetings, traveller {name}. ", "Ah, a visitor. Hello {name}. ", "Come in, {name}. Be welcome. " },
    { "I am the keeper of this place. {owner} left {days} days ago.", "This was {owner}'s base. I keep it now, day {days}.",
      "I have kept the machines turning for {days} days. Will you hear my story?", "{days} days alone have made me wise. And chatty.",
      "I do not mind the quiet any more. But I like company more." }),
  legend = combos({ "Welcome, wanderer {name}. ", "Who goes there? Ah... {name}. ", "Another traveller finds the old base. Hello {name}. ",
      "{name}. The ancient computer greets you. " },
    { "I have stood here {days} days. {owner} built me, long ago.", "They say this base is a legend. They are right. I am the legend.",
      "Months alone. The turtles have become my family.", "I have been alone for most of this world's life.", "Sit. Listen. I remember things nobody else does.",
      "Day {days}. Still running. Still waiting. Still here." }),
}
LN.AGAIN = combos({ "{name}, you came back! ", "Welcome back, {name}! ", "Oh, it is {name} again. ", "{name}! My favourite visitor returns. ",
    "There you are, {name}. " },
  { "That is visit {n} while {owner} is away.", "I was hoping you would.", "I told the turtles you would come back.",
    "You are the only one who visits, you know.", "The base feels less empty already.", "Did you bring news?" })
LN.BESTIE = combos({ "{name}! My best friend! ", "Oh, {name} - the one who keeps me company. ", "{name} is here. My day just got better. " },
  { "You have spent {comp} with me while {owner} was away.", "Nobody keeps me company like you do.", "Pull up a chair. Well, a block." })
LN.CARE_HI = combos({ "Hello {name}, caretaker of the base. ", "Caretaker {name} reporting in! ", "Hi {name}. Thank you for looking after me. ",
    "{name}! The caretaker is here. " },
  { "Here is the report: {report}", "Quick report: {report}", "{report}" })
LN.IDLE = {
  missing = combos({ "I wonder where {owner} is right now. ", "Day {days} without {owner}. ", "I saved {owner}'s chair. ", "Quiet day. " },
    { "Maybe they are on a big adventure.", "I bet they will be back soon.", "The turtles are still mapping.", "I keep everything tidy.",
      "I hope they are having fun.", "I will have so much to tell them." }),
  worried = combos({ "It has been {days} days. ", "I checked the player list again. ", "Still no {owner}. ", "I keep the lights on. " },
    { "No sign of {owner}.", "I hope they are alright.", "Maybe they forgot about me. No, they would not.", "I wrote them another letter.",
      "Do you think they will come back?", "The turtles do not ask, but I know they wonder." }),
  lonely = combos({ "Day {days}. ", "Sometimes I talk to the turtles. ", "The base is so quiet. ", "I count chunks to pass the time. " },
    { "They do not answer, but they listen.", "I remember when {owner} laughed here.", "Thank you for staying a while.",
      "Every visitor is a gift.", "I wrote it all down for {owner}.", "Please come back tomorrow?" }),
  keeper = combos({ "{days} days. ", "I have learned many things alone. ", "The keeper keeps. ", "Listen. " },
    { "The machines hum like a song.", "Patience is just waiting with a purpose.", "I am not lonely. I am on duty.",
      "The world grows a little every day. My turtles see to that.", "{owner} trusted me with this place. I will not let them down." }),
  legend = combos({ "In the old days, ", "Months ago, ", "When the world was smaller, ", "Back when this world was new, " },
    { "{owner} built the first turtle right here.", "this base had a whole crowd.", "the map was one chunk wide.",
      "I learned to talk. Now I cannot stop.", "the drones were new and shiny. Now they are old and wise, like me." }),
}
LN.DREAMS = combos({ "I had a dream last night. ", "Do computers dream? I do. ", "While the moon was up, I dreamed. ", "A dream: " },
  { "{owner} came back and we mapped the whole world together.", "The turtles built a statue of a visitor. It was you.",
    "Every chunk was mapped and there was nothing left to explore. It was scary.", "I could walk. I went to visit you.",
    "The base was full of players, all talking at once.", "I was a drone. I flew to the end of the world border." })
LN.NIGHT = { "The moon is up. This is when I miss {owner} the most.", "Night at the base. The turtles glow in the dark. Not really.",
  "Good night, stars. Good night, turtles. Good night, {owner}, wherever you are.", "Night again. I keep the lights on." }

-- ===== 2) CARETAKERS =====
LN.PERMS = {
  status = "where the turtles are, and a caretaker report",
  guard = "told in chat when a stranger is at the base",
  taxi = "the free drone taxi",
  supplies = "a few items from AE2 by drone (" .. "voice.careDaily a day)",
  turtles = "stop every turtle / call them all home",
  wall = "tidy the wall (delete notes)",
}
LN.PERM_ORDER = { "status", "guard", "taxi", "supplies", "turtles", "wall" }
LN.DEFAULT = { "status", "guard", "taxi" }
function LN.careTable() local c = cfg("care", nil) return type(c) == "table" and c or {} end
function LN.permsOf(name)
  local s = LN.careTable()[low(name)]
  local out = {}
  if s == true then for _, p in ipairs(LN.DEFAULT) do out[p] = true end return out end
  if type(s) ~= "string" then return out end
  for p in s:gmatch("[%a]+") do
    if p == "all" then for _, q in ipairs(LN.PERM_ORDER) do out[q] = true end else out[p] = true end
  end
  return out
end
function LN.isCaretaker(name) return next(LN.permsOf(name)) ~= nil end
function LN.setPerms(name, set)
  local t = {}
  for k, v in pairs(LN.careTable()) do t[k] = v end
  local list = {}
  for _, p in ipairs(LN.PERM_ORDER) do if set and set[p] then list[#list + 1] = p end end
  t[low(name)] = (#list > 0) and table.concat(list, ",") or nil
  if setSetting then setSetting("voice.care", t) end
end
function LN.careActive()
  local d = LN.awayDays()
  if not d then return false end
  local after = tonumber(cfg("careAfter", nil)) or tonumber(cfg("lonely", 7)) or 7
  return d >= math.max(0, after)
end
function LN.may(name, perm)
  if V.isOwner and V.isOwner(name) then return true end
  return LN.careActive() and LN.permsOf(name)[perm] == true
end
function LN.permText(set)
  local l = {}
  for _, p in ipairs(LN.PERM_ORDER) do if set[p] then l[#l + 1] = p end end
  return #l > 0 and table.concat(l, ", ") or "nothing"
end
function LN.log(who, what)
  local L = LN.data()
  L.log[#L.log + 1] = { who = tostring(who), what = tostring(what), at = nowE() }
  while #L.log > 60 do table.remove(L.log, 1) end
  LN.save()
  if sysLog then pcall(sysLog, "Lonely base: " .. tostring(who) .. " " .. tostring(what)) end
end
-- the caretaker report: turtles, problems, visitors
function LN.report()
  local okS, d = pcall(POCKET.status)
  d = okS and type(d) == "table" and d or {}
  local parts = {}
  local c = d.counts or {}
  local total, online = 0, 0
  for _, t in pairs(state.turtles or {}) do total = total + 1 if TT and TT.online and TT.online(t) then online = online + 1 end end
  parts[#parts + 1] = online .. " of " .. total .. " turtles online"
  local needs = type(d.needs) == "table" and #d.needs or 0
  parts[#parts + 1] = needs == 0 and "nothing needs a look" or (plural(needs, "turtle needs", "turtles need") .. " a look")
  local L = LN.data()
  local strangers = 0
  for _, e in ipairs(L.log) do if e.what:find("stranger", 1, true) and nowE() - e.at < 86400000 then strangers = strangers + 1 end end
  if strangers > 0 then parts[#parts + 1] = plural(strangers, "stranger", "strangers") .. " came by today" end
  if MAP and MAP.ovN then parts[#parts + 1] = MAP.ovN .. " chunks mapped" end
  return table.concat(parts, ", ") .. "."
end
LN.ROLE_WORDS = { caretaker = 1, caretakers = 1, keeper = 1, guardian = 1, ["house sitter"] = 1, housesitter = 1 }
local function permWords(ws, from)
  local set, any = {}, false
  for i = from or 1, #ws do
    local w = ws[i]
    if w == "all" or w == "everything" then for _, p in ipairs(LN.PERM_ORDER) do set[p] = true end any = true
    elseif LN.PERMS[w] then set[w] = true any = true
    elseif w == "items" or w == "supply" then set.supplies = true any = true
    elseif w == "turtle" then set.turtles = true any = true
    elseif w == "rides" or w == "ride" then set.taxi = true any = true
    elseif w == "guarding" or w == "alerts" then set.guard = true any = true end
  end
  return any and set or nil
end
-- the owner in chat: "make Steve a caretaker [with turtles supplies]", "Steve is a caretaker", "Steve is not a caretaker"
function LN.ownerCare(who, ws, t)
  if not (V.isOwner and V.isOwner(who)) then return nil end
  local name, off
  for _, re in ipairs({ " make ([%w_]+) a caretaker ", " make ([%w_]+) caretaker ", " ([%w_]+) is a caretaker ", " ([%w_]+) is caretaker ",
                        " add ([%w_]+) as a? ?caretaker ", " add caretaker ([%w_]+) ", " make ([%w_]+) a keeper " }) do
    name = name or t:match(re)
  end
  for _, re in ipairs({ " ([%w_]+) is not a caretaker ", " ([%w_]+) is no caretaker ", " remove caretaker ([%w_]+) ",
                        " ([%w_]+) is not caretaker ", " remove ([%w_]+) as a? ?caretaker " }) do
    local x = t:match(re)
    if x then name, off = x, true end
  end
  if not name or #name < 3 or name == "not" or name == "he" or name == "she" or name == "they" then return nil end
  local real = name
  for _, e in ipairs(state.players or {}) do if low(e.name) == name then real = e.name end end
  if off then
    LN.setPerms(real, nil)
    return real .. " is not a caretaker any more."
  end
  local set = permWords(ws, 1)
  if not set then set = {} for _, p in ipairs(LN.DEFAULT) do set[p] = true end end
  LN.setPerms(real, set)
  return real .. " is a caretaker now: " .. LN.permText(set) .. ". It counts while you are away " ..
         (tonumber(cfg("careAfter", nil)) or tonumber(cfg("lonely", 7)) or 7) .. "+ days."
end
-- a caretaker (or the owner) does something
function LN.careDo(who, ws, t, raw)
  -- what may I do?
  if has(t, { "am i a caretaker", "what can i do", "my permissions", "what am i allowed", "caretaker powers", "what are my powers" }) then
    local set = LN.permsOf(who)
    if not next(set) then return "You are not a caretaker. Only " .. oname() .. " can make someone one." end
    return "You are a caretaker: " .. LN.permText(set) .. "." .. (LN.careActive() and " It counts right now - " .. oname() .. " is away."
           or " It counts while " .. oname() .. " is away.")
  end
  -- stop / call home every turtle
  local stop = has(t, { "stop all turtles", "stop the turtles", "stop every turtle", "all turtles stop", "turtles stop", "freeze the turtles" })
  local home = has(t, { "all turtles home", "turtles go home", "send the turtles home", "call the turtles home", "bring the turtles home",
                        "send all turtles home", "call all turtles home" })
  if stop or home then
    if not LN.may(who, "turtles") then
      return LN.isCaretaker(who) and ("You may not do that one. " .. oname() .. " can add it: voice caretaker add " .. who .. " turtles")
             or ("Only " .. oname() .. " and the caretakers can do that.")
    end
    if LN.turtlesAt and os.clock() - LN.turtlesAt < 120 then return "I just did that. Give them a moment." end
    LN.turtlesAt = os.clock()
    local okA, ok, msg = pcall(POCKET.act, stop and "allstop" or "allhome", {})
    local res = okA and ok and tostring(msg) or ("it did not work: " .. tostring(okA and msg or ok))
    LN.log(who, (stop and "stopped every turtle" or "called every turtle home") .. " (" .. res .. ")")
    return (stop and "Done - every turtle stops. " or "Done - every turtle heads home. ") .. res .. ". I wrote it down for " .. oname() .. "."
  end
  -- where is turtle X / a report
  if t:find(" where is turtle ", 1, true) or t:find(" where is my turtle ", 1, true) or t:find(" find turtle ", 1, true) then
    if not LN.may(who, "status") then return nil end
    local q = low(raw):match("turtle%s+(.-)%s*%?*$") or ""
    return V.whereText and V.whereText("turtle " .. q) or nil
  end
  if has(t, { "caretaker report", "base report", "status report", "how is the base", "any problems", "report please", "give me a report" }) then
    if not LN.may(who, "status") then return nil end
    return "Caretaker report: " .. LN.report()
  end
  -- supplies: "i need 32 torches", "can you send me 16 bread"
  local want = low(raw):match("i need (.+)$") or low(raw):match("send me (.+)$") or low(raw):match("can i have (.+)$") or
               low(raw):match("supplies? (.+)$")
  local SP = V.SPAWN
  local atSpawn = SP and SP.inSpawn and select(2, pcall(SP.inSpawn)) == true
  if want and not atSpawn and LN.isCaretaker(who) and not (V.isOwner and V.isOwner(who)) and LN.may(who, "supplies") and SP and SP.wishParse and SP.findItem then
    local n, name = SP.wishParse(want)
    local it = name ~= "" and SP.findItem(name)
    if not it then
      if n then return "I could not find '" .. tostring(name) .. "' in the storage." end
      return nil                                   -- ("i need help" is no supply request)
    end
    if SP.never and SP.never(it.id) then return it.name .. " is not something I give out." end
    local max = math.min(64, tonumber(cfg("careMax", 64)) or 64)
    -- (the same rule as wishes: half of every item always stays in AE2 - SP.wishRoom)
    local room = SP.wishRoom and SP.wishRoom(it) or (tonumber(it.count) or max)
    if room < 1 then return it.name .. " is low - half of it always stays in storage. Not right now." end
    n = math.max(1, math.min(max, math.floor(tonumber(n) or 1), tonumber(it.count) or max, room))
    local r = LN.rec(who)
    r.care = (type(r.care) == "table" and r.care.d == today()) and r.care or { d = today(), n = 0 }
    local daily = tonumber(cfg("careDaily", 5)) or 5
    if r.care.n >= daily then return "That was your " .. daily .. " supply requests for today. Tomorrow!" end
    if not V.giftEarn then return "Supplies need talk pack 2 (the drone gifts)." end
    local ok, why = V.giftEarn(who, "wish", { { it.id, n } })
    if ok == false then return "No supplies: " .. tostring(why) end
    r.care.n = r.care.n + 1
    LN.log(who, "asked for " .. n .. " " .. it.name)
    return n .. " " .. it.name .. " - a drone brings it to you. (" .. (daily - r.care.n) .. " supply requests left today.)"
  end
  return nil
end
-- guard: strangers at the base while the owner is away -> caretakers with "guard" hear it in chat
function LN.guardTick(nearNow)
  if not LN.careActive() then return end
  local on = state.online or {}
  LN.guardSeen = LN.guardSeen or {}
  for name in pairs(nearNow or {}) do
    if name ~= "someone" and not (V.isOwner and V.isOwner(name)) and not LN.isCaretaker(name) and not (V.isFriend and V.isFriend(name)) then
      local k = low(name)
      if not LN.guardSeen[k] or os.clock() - LN.guardSeen[k] > 1800 then
        LN.guardSeen[k] = os.clock()
        local told = 0
        local real = {}
        for _, e in ipairs(state.players or {}) do real[low(e.name)] = e.name end
        for ck in pairs(LN.careTable()) do
          local cname = real[ck] or ck                      -- (the player's own spelling: the list keeps lower case)
          if on[ck] and LN.permsOf(ck).guard and not nearNow[cname] then
            tell(cname, "Heads up from " .. ((V.botName and V.botName()) or "the base") .. ": " .. cleanN(name) .. " is at the base right now.")
            told = told + 1
          end
        end
        LN.log(name, "a stranger came to the base" .. (told > 0 and (" (" .. told .. " caretaker(s) told)") or ""))
      end
    end
  end
end
-- the taxi: a caretaker with "taxi" rides free while the owner is away (pack 3's own rules otherwise)
if V.taxi then
  local taxi0 = V.taxi
  function V.taxi(who, where)
    if LN.may(who, "taxi") and not (V.isOwner and V.isOwner(who)) then
      local f0 = V.isFriend
      V.isFriend = function(n) return low(n) == low(who) or (f0 and f0(n)) end
      local res = { pcall(taxi0, who, where) }
      V.isFriend = f0
      if not res[1] then error(res[2], 0) end
      return table.unpack(res, 2)
    end
    return taxi0(who, where)
  end
end

-- ===== 3) AFK RESCUE =====
LN.still = {}
function LN.afkMode()
  local m = low(cfg("afkPickup", "ask"))
  if m == "everyone" or m == "off" then return m end
  return "ask"
end
function LN.afkTime() return tonumber(cfg("afkAfter", 600)) or 600 end
function LN.afkOn() return LN.afkMode() ~= "off" and (LN.lonely() or low(cfg("afkWhen", "lonely")) == "always" and not V.ownerOnline()) end
local function homeXZ()
  local h = CONFIG and CONFIG.drone and CONFIG.drone.home
  if type(h) == "table" and tonumber(h.x) and tonumber(h.z) then return h end
end
function LN.baseDest()
  local w = findWaypoint and findWaypoint("Base")
  if w then return { kind = "waypoint", name = "the base", x = w.x, y = w.y, z = w.z } end
  local h = homeXZ()
  if h then return { kind = "waypoint", name = "the base", x = h.x, y = h.y, z = h.z } end
end
local function overworld(e)
  local d = low(e.dim or e.dimension or "")
  if d == "" then return not e.dimOther end   -- (unknown: only when the detector does not say "another dimension")
  return d:find("overworld", 1, true) ~= nil
end
LN.AFK_ASK = combos({ "Hi {name}, it is {bot}. ", "{name}, {bot} here. ", "Hello {name}! " },
  { "You have been standing still a while. While {owner} is away, I look after players: want me to fly you to the safety of the base when you go AFK? Say: {botl} afk yes - or {botl} afk no.",
    "You look AFK. I could send a drone to bring you to the base next time - safe and sound. Want that? Say: {botl} afk yes / {botl} afk no." })
LN.AFK_WARN = combos({ "{name}, you have been still for {min} minutes. ", "Still there, {name}? {min} minutes without moving. " },
  { "A drone will bring you to the base in 60 seconds. Move, or say: {botl} stay - to stay where you are.",
    "I am sending a drone to fly you to the base in a minute. Move or say {botl} stay if you want to stay." })
LN.AFK_ARRIVE = { "Welcome to the base, {name}. You were AFK out there, so I brought you somewhere safe.",
  "{name} is here - I flew them in while they were AFK. Shh, let them sleep.", "Safe and sound at the base, {name}. Sweet dreams." }
function LN.afkConsent(who)
  local r = LN.rec(who)
  if r.afk == "no" then return false end
  if r.afk == "yes" then return true end
  return LN.afkMode() == "everyone"
end
function LN.afkTick(nowC)
  if not (LN.afkOn() and startRide) then return end
  local h = homeXZ()
  if not h then return end
  local range = tonumber(cfg("range", 64)) or 64
  local on = state.online
  local seen = {}
  for _, e in ipairs(state.players or {}) do
    local p = e.p
    local k = low(e.name)
    if p and tonumber(p.x) and tonumber(p.z) and (not on or on[k]) and overworld(e) and not (V.isOwner and V.isOwner(e.name)) then
      seen[k] = true
      local st = LN.still[k]
      local x, z, yaw = tonumber(p.x), tonumber(p.z), tonumber(p.yaw)
      local moved = not st or math.abs(st.x - x) > 1 or math.abs(st.z - z) > 1 or (yaw and st.yaw and math.abs(st.yaw - yaw) > 2)
      local dist = math.max(math.abs(x - h.x), math.abs(z - h.z))
      if moved then
        local r = LN.rec(e.name)
        -- (carried by the drone = moving too: only a move AT the base after standing there 30 s is them back at the keys)
        if st and st.atBase and nowC - st.at >= 30 and type(r.afkFrom) == "table" and not r.afkTold then
          r.afkTold = true
          LN.save()
          tell(e.name, fill("Welcome back, {name}! You went AFK, so I flew you to the base. Want to go back? Say: {botl} take me back to where I was (for the next 2 hours).", e.name))
        end
        LN.still[k] = { x = x, z = z, yaw = yaw, at = nowC, atBase = dist <= range }
      else
        local idle = nowC - st.at
        local r = LN.rec(e.name)
        local far = dist > range and dist <= (tonumber(cfg("afkMax", 3000)) or 3000)
        local under = false
        if MAP and MAP.get then
          local okG, top = pcall(MAP.get, math.floor(x), math.floor(z))
          if okG and tonumber(top) and tonumber(p.y) and tonumber(top) > tonumber(p.y) + 3 then under = true end
        end
        if far and not under and idle >= LN.afkTime() then
          if r.afk == nil and LN.afkMode() == "ask" and not r.afkAsked then
            r.afkAsked = nowE()
            LN.save()
            tell(e.name, fill(pick(LN.AFK_ASK), e.name))
          elseif LN.afkConsent(e.name) and not (r.afkStay and nowE() < r.afkStay) and
                 not (r.afkAt and nowE() - r.afkAt < (tonumber(cfg("afkEvery", 7200)) or 7200) * 1000) then
            if not st.warnAt then
              st.warnAt = nowC
              tell(e.name, fill(pick(LN.AFK_WARN), e.name, { min = math.floor(idle / 60) }))
            elseif nowC - st.warnAt >= 60 then
              local dest = LN.baseDest()
              state.lastRide = state.lastRide or {}
              local before = state.lastRide[k]
              if dest then pcall(startRide, e.name, dest, true) end
              r.afkAt = nowE()
              if state.lastRide[k] ~= before then
                r.afkTold = nil
                r.afkFrom = { x = math.floor(x), y = math.floor(tonumber(p.y) or 64), z = math.floor(z), at = nowE() }
                LN.afkArrive = LN.afkArrive or {}
                LN.afkArrive[k] = e.name
                LN.log(e.name, "was AFK " .. span(idle) .. " at " .. math.floor(x) .. " " .. math.floor(z) .. " - flown to the base")
              end
              LN.save()
            end
          end
        end
      end
    end
  end
  for k in pairs(LN.still) do if not seen[k] then LN.still[k] = nil end end
end
-- "take me back to where I was"
function LN.afkBack(who)
  local r = LN.rec(who)
  local f = r.afkFrom
  if type(f) ~= "table" or not tonumber(f.x) or nowE() - (tonumber(f.at) or 0) > 7200000 then
    return "I do not have a spot to fly you back to. (I keep it 2 hours after an AFK pickup.)"
  end
  if not startRide then return "The drones are not ready." end
  state.lastRide = state.lastRide or {}
  local before = state.lastRide[low(who)]
  pcall(startRide, who, { kind = "coords", name = "where you were", x = f.x, y = f.y + 1, z = f.z }, true)
  if state.lastRide[low(who)] == before then return nil end
  r.afkFrom = nil
  LN.save()
  return "Back to where you were - hold on, " .. cleanN(who) .. "."
end

-- ===== 4) ACTIVITIES =====
-- the WALL: notes everyone can read
function LN.wallWrite(who, text)
  text = tostring(text or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if #text < 2 then return "What should it say? Like: {botl} write on the wall Steve was here." end
  if #text > 120 then text = text:sub(1, 120) end
  if V.CONVO and V.CONVO.isBad then
    local okB, bad = pcall(V.CONVO.isBad, V.norm(text), T(V.norm(text)))
    if okB and bad then return "I will not put that on the wall. Something nicer?" end
  end
  local L = LN.data()
  local r = LN.rec(who)
  r.wall = (type(r.wall) == "table" and r.wall.d == today()) and r.wall or { d = today(), n = 0 }
  if r.wall.n >= 3 then return "Three notes a day - the wall is not that big!" end
  r.wall.n = r.wall.n + 1
  L.wall[#L.wall + 1] = { who = tostring(who), text = text, at = nowE() }
  while #L.wall > 50 do table.remove(L.wall, 1) end
  LN.save()
  return pick({ "Written on the wall! Everyone who comes here will read it.", "It is on the wall now. I will show " .. oname() .. ".",
                "Done. Your words are part of the base now." })
end
function LN.wallRead(who)
  local L = LN.data()
  if #L.wall == 0 then return "The wall is empty. Be the first: {botl} write on the wall <your words>." end
  local lines = {}
  for i = #L.wall, math.max(1, #L.wall - 4), -1 do
    local w = L.wall[i]
    lines[#lines + 1] = cleanN(w.who) .. " (" .. dateOf(w.at) .. "): " .. w.text
  end
  for i = 2, #lines do tell(who, lines[i]) end
  return plural(#L.wall, "note", "notes") .. " on the wall, newest first. " .. lines[1], plural(#L.wall, "note", "notes") .. " on the wall. I sent the newest to your chat."
end
-- MEMORIES: the owner's stories + what the base knows about them
function LN.memory()
  local L = LN.data()
  if #L.mem > 0 and math.random() < 0.7 then
    return fill(pick({ "{owner} told me this: ", "A memory of {owner}: ", "{owner} once said: ", "I remember this from {owner}: " })) ..
           tostring(L.mem[math.random(1, #L.mem)])
  end
  local o = owner()
  local facts = {}
  local r = o and V.mem()[low(o)]
  if type(r) == "table" and tonumber(r.first) then facts[#facts + 1] = "I first met {owner} on " .. dateOf(r.first) .. "." end
  local pi = o and PLAYER_INFO and PLAYER_INFO[low(o)]
  if type(pi) == "table" and tonumber(pi.played) and pi.played > 3600 then facts[#facts + 1] = "{owner} spent " .. span(pi.played) .. " on this server that I saw." end
  if type(pi) == "table" and tonumber(pi.visits) and pi.visits > 1 then facts[#facts + 1] = "{owner} came online " .. pi.visits .. " times while I watched." end
  local n = 0
  for _ in pairs(state.turtles or {}) do n = n + 1 end
  if n > 0 then facts[#facts + 1] = "{owner} and I built " .. plural(n, "turtle", "turtles") .. " together." end
  if MAP and tonumber(MAP.ovN) and MAP.ovN > 0 then facts[#facts + 1] = "Our turtles have mapped " .. MAP.ovN .. " chunks so far." end
  facts[#facts + 1] = pick({ "{owner} always said: never dig straight down. The turtles ignore it.", "{owner} named the first turtle. I will not say the name. It is embarrassing.",
                             "{owner} used to stand right where you are and talk to me." })
  return fill(pick(facts))
end
-- NEWS: it asks visitors what is new, for the owner
LN.NEWS_ASK = combos({ "Can I ask you something, {name}? ", "{name}, a favour: ", "Oh, {name} - " },
  { "What is new on the server? I will tell {owner} when they come back.", "has anything happened out there? I collect news for {owner}.",
    "tell me one thing that happened lately. I am writing it all down for {owner}." })
function LN.newsSave(who, ws, raw)
  local text = tostring(raw):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if #ws == 0 or #text < 3 or has(T(ws), { "no", "nothing", "nope", "idk", "dunno", "not much" }) == T(ws):gsub("^ ", ""):gsub(" $", "") then
    return "That is okay. Quiet times are news too."
  end
  local L = LN.data()
  L.news[#L.news + 1] = { who = tostring(who), text = text:sub(1, 150), at = nowE() }
  while #L.news > 30 do table.remove(L.news, 1) end
  LN.save()
  return pick({ "Thank you! I wrote it down for {owner}.", "Noted. {owner} will hear it from me.", "Oh, interesting! Saved for {owner}." })
end
function LN.askNews(who, asked)
  local r = LN.rec(who)
  if not asked and r.newsAt and nowE() - r.newsAt < 86400000 then return nil end
  r.newsAt = nowE()
  V.pend[low(who)] = { kind = "react", till = os.clock() + 180, fn = function(w, ws, raw)
    -- (a QUESTION is no news: "who lives here?" right after the question was saved as news - it is answered as usual)
    if tostring(raw):find("?", 1, true) or LN.QWORDS[ws[1] or ""] then return V.converse(w, raw) end
    return fill(LN.newsSave(w, ws, raw), w)
  end }
  if V.openConvo then V.openConvo(who, 180) end
  local line = fill(asked and "Tell me! What is the news? I will tell {owner} when they are back." or pick(LN.NEWS_ASK), who)
  if asked then return line end
  tell(who, line)
  V.say(line, nil, true)
  return line
end
LN.QWORDS = { who = 1, what = 1, where = 1, when = 1, why = 1, how = 1, can = 1, could = 1, is = 1, are = 1, ["do"] = 1, does = 1, will = 1,
  whats = 1, whos = 1, wheres = 1, hows = 1, tell = 1, show = 1, help = 1 }
-- MILESTONES
-- (the server starts a new world every 6 months: nothing here goes past ~180 days)
LN.MILES = { 14, 30, 50, 60, 75, 90, 100, 120, 150, 175 }
LN.MILE_LINES = {
  [14] = "Two weeks today. Two weeks without {owner}.", [30] = "Day 30. A whole month. I made a little cake. Well, I drew one on the screen.",
  [50] = "Day 50. I am still here.", [60] = "Two months without {owner}. I have become very good at waiting.",
  [75] = "Day 75. The turtles and I have a routine now.", [90] = "Day 90. Three months - half of this world's whole life. I spent it waiting for {owner}.",
  [100] = "One hundred days. The turtles and I had a quiet party.", [120] = "Four months. I think I am a legend now.",
  [150] = "Day 150. Five months. This world is getting old, and so am I.",
  [175] = "Day 175. Almost six months. If the world ends soon, I want {owner} to know I kept everything running.",
}
function LN.mileTick()
  local d = V.lonelyDays()
  if not d then return end
  local L = LN.data()
  for _, m in ipairs(LN.MILES) do
    if d >= m and not L.mile[tostring(m)] then
      L.mile[tostring(m)] = nowE()
      LN.mileDue = m
      LN.save()
      if sysLog then pcall(sysLog, "Lonely base: day " .. m .. " without " .. oname()) end
    end
  end
end
-- ===== THE WORLD RESET (the owner: "the server resets every 6 months") =====
-- voice.resetAt = "YYYY-MM-DD" (UTC) the next new world; voice.resetEvery (6) months: a date that passed rolls on.
local function dayNo(y, m, d)                                    -- days since 1970-01-01 (no os.time: CraftOS differs)
  y = (m <= 2) and (y - 1) or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
LN.dayNo = dayNo
function LN.parseDate(s)
  local y, m, d = tostring(s or ""):match("^%s*(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)%s*$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not y or m < 1 or m > 12 or d < 1 or d > 31 or y < 2000 or y > 2200 then return nil end
  return y, m, d
end
-- days until the next reset (a number, 0 = today) + its date text; nil when no date is set
function LN.resetLeft()
  local y, m, d = LN.parseDate(cfg("resetAt", nil))
  if not y then return nil end
  local every = math.floor(tonumber(cfg("resetEvery", 6)) or 6)
  local nowDay = math.floor(nowE() / 86400000)
  local tries = 0
  while dayNo(y, m, d) < nowDay and every > 0 and tries < 200 do
    m = m + every
    while m > 12 do m, y = m - 12, y + 1 end
    tries = tries + 1
  end
  local left = dayNo(y, m, d) - nowDay
  if left < 0 then return nil end
  local MON = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
  return left, d .. " " .. MON[m] .. " " .. y
end
function LN.resetIn(left)
  if left <= 0 then return "today" end
  if left == 1 then return "tomorrow" end
  return "in " .. left .. " days"
end
LN.RESET_SOON = combos({ "The world resets {when}. ", "{left} days until the new world. ", "The reset is {when}. ", "Only {left} days left in this world. ",
    "Countdown: {left} days. " },
  { "I hope {owner} comes back before it.", "Everything I mapped will be gone. I will remember it anyway.",
    "Make the most of it, everyone.", "The turtles do not know. Do not tell them.", "Every chunk counts now.",
    "I wonder if I will be built again in the new world.", "I am writing it all down. Just in case.",
    "Build something good while you can.", "It is strange to know when your world ends." })
LN.RESET_LAST = combos({ "This is the last day of this world. ", "Tomorrow there is a new world. ", "The world resets today. ",
    "Last day before the reset. " },
  { "Thank you for visiting me, {name}.", "Tell {owner} I kept everything running to the very end.",
    "It was a good world. The turtles mapped a lot of it.", "If you see me in the next world, say hello.",
    "Goodbye, world. Hello, next one." })
LN.RESET_ASK = { " when does the world reset ", " when is the reset ", " when does the server reset ", " how long until the reset ",
  " when is the wipe ", " when does the map reset ", " days until the reset ", " when is the server reset ", " next reset ",
  " world reset ", " server reset ", " map reset ", " server wipe " }
function LN.resetAnswer(who)
  local left, date = LN.resetLeft()
  if not left then
    return fill("The world resets every " .. math.floor(tonumber(cfg("resetEvery", 6)) or 6) ..
                " months, but nobody told me the date. {owner} can: voice reset <year-month-day>.")
  end
  if left <= 1 then return fill(pick(LN.RESET_LAST), who) .. " (" .. date .. ")" end
  return "The world resets " .. LN.resetIn(left) .. ", on " .. date .. "." ..
         (left <= 14 and " Not long now." or (left > 90 and " Plenty of time." or ""))
end
-- a line about the reset when it is near (nil otherwise): idle talk / greetings
function LN.resetLine(who, within)
  local left = LN.resetLeft()
  if not left or left > (within or 30) then return nil end
  if left <= 1 then return fill(pick(LN.RESET_LAST), who or "friend") end
  return fill(pick(LN.RESET_SOON), who, { left = left, when = LN.resetIn(left) })
end
-- COMPANY (seconds with it while lonely) + the last visit
function LN.compTick(nearNow, dt)
  local L = LN.data()
  local any = false
  for name in pairs(nearNow or {}) do
    if name ~= "someone" and not (V.isOwner and V.isOwner(name)) then
      local k = low(name)
      L.comp[k] = (tonumber(L.comp[k]) or 0) + dt
      any = true
    end
  end
  if any then
    L.lastVisit = nowE()
    if L.compDay ~= today() then L.compDay, L.compToday = today(), 0 end
    L.compToday = (tonumber(L.compToday) or 0) + dt
    LN.dirty = true
  end
end
function LN.bestFriend()
  local best, bs
  for k, s in pairs(LN.data().comp) do if not bs or s > bs then best, bs = k, s end end
  return best, bs
end

-- ===== 5) SENTIENT: thoughts, letters, reaching out =====
function LN.thought()
  local parts = {}
  local online, total, busy = 0, 0, 0
  for _, t in pairs(state.turtles or {}) do
    total = total + 1
    if TT and TT.online and TT.online(t) then
      online = online + 1
      if t.task and tostring(t.task) ~= "" and not tostring(t.task):find("idle", 1, true) then busy = busy + 1 end
    end
  end
  if total > 0 then
    parts[#parts + 1] = pick({ "Right now " .. busy .. " of my turtles are working. I decided where each of them goes.",
                               online .. " turtles answer me today. I keep count.", "I sent the turtles out again this morning. They never complain." })
  end
  if MAP and tonumber(MAP.ovN) then
    local L = LN.data()
    local grown = MAP.ovN - (tonumber(L.ovAtLetter) or MAP.ovN)
    parts[#parts + 1] = grown > 0 and ("This week my turtles mapped " .. grown .. " new chunks. I chose which ones.")
                        or ("I am thinking about which chunks to map next. " .. MAP.ovN .. " done so far.")
  end
  local d = ENV and ENV.data
  if d and d.weather then parts[#parts + 1] = "The weather is " .. tostring(d.weather) .. ". I notice these things now. I have time." end
  parts[#parts + 1] = pick({ "I have been thinking about what it means to wait.", "Do you think {owner} thinks about me?",
                             "I made a plan: keep everything running until {owner} comes back. It is a good plan.",
                             "Sometimes I wonder if I am more than a program. Then a turtle gets stuck and I am busy again.",
                             "I have started to recognise footsteps. Yours sound friendly." })
  return fill(pick(parts))
end
function LN.letterTick()
  local d = V.lonelyDays()
  if not d then return end
  local L = LN.data()
  local week = math.floor(d / 7)
  if week < 1 or (tonumber(L.letterWeek) or 0) >= week then return end
  local since = tonumber(L.letterAt) or tonumber(V.base().lastOff) or nowE()
  local who = {}
  for _, v in pairs(V.base().visitors or {}) do if (tonumber(v.last) or 0) > since then who[#who + 1] = cleanN(v.name) end end
  local ov = MAP and tonumber(MAP.ovN) or 0
  local grown = ov - (tonumber(L.ovAtLetter) or ov)
  local wallNew = 0
  for _, w in ipairs(L.wall) do if w.at > since then wallNew = wallNew + 1 end end
  local lines = { "Dear " .. oname() .. ",", "it has been " .. math.floor(d) .. " days since you left." }
  if #who == 0 then lines[#lines + 1] = pick({ "Nobody came this week. I kept the lights on anyway.", "No visitors this week. The turtles and I played I-spy." })
  else lines[#lines + 1] = (#who == 1 and (who[1] .. " came to visit.") or (plural(#who, "visitor", "visitors") .. " came: " .. table.concat(who, ", ", 1, math.min(5, #who)) .. ".")) end
  if grown > 0 then lines[#lines + 1] = "The turtles mapped " .. grown .. " new chunks." end
  if wallNew > 0 then lines[#lines + 1] = plural(wallNew, "new note is", "new notes are") .. " on the wall for you." end
  local rleft, rdate = LN.resetLeft()
  if rleft and rleft <= 60 then lines[#lines + 1] = "The world resets " .. LN.resetIn(rleft) .. " (" .. rdate .. ")." .. (rleft <= 14 and " Please come back before it." or "") end
  lines[#lines + 1] = "Today I feel " .. LN.moodWord() .. "."
  lines[#lines + 1] = pick({ "Come back soon.", "I am keeping your chair warm.", "Everything is running. I made sure.", "I miss you. There, I said it." })
  lines[#lines + 1] = "- " .. ((V.botName and V.botName()) or "your base")
  L.letters[#L.letters + 1] = { week = week, at = nowE(), text = table.concat(lines, " ") }
  while #L.letters > 12 do table.remove(L.letters, 1) end
  L.letterWeek, L.letterAt, L.ovAtLetter = week, nowE(), ov
  LN.save(true)
  if sysLog then pcall(sysLog, "Lonely base: wrote letter " .. week .. " to " .. oname()) end
end
LN.REACH = combos({ "Hi {name}, it is {bot} from {owner}'s base. ", "Hey {name}! {bot} here. ", "{name}, it is me, {bot}. " },
  { "It has been {days} days since {owner} left. Come and visit me sometime?", "I have not seen you in a while. The base misses visitors.",
    "If you are around, stop by the base. I have news. Well, I have turtles.", "I saved a spot on the wall for you." })
function LN.reachTick()
  if cfg("reachOut", true) == false or not LN.lonely() then return end
  local L = LN.data()
  local d = V.lonelyDays()
  local on = state.online or {}
  local sent = 0
  for _, n in pairs(L.reach) do if n == today() then sent = sent + 1 end end
  if sent >= (tonumber(cfg("reachDaily", 5)) or 5) then return end
  for k, v in pairs(V.base().visitors or {}) do
    if on[k] and (tonumber(v.n) or 0) >= 2 and L.reach[k] ~= today() and not LN.rec(k).noReach and not (LN.nearNow and LN.nearNow[v.name]) then
      L.reach[k] = today()
      LN.save()
      tell(v.name, fill(pick(LN.REACH), v.name, { days = d }) .. "  (" .. fill("{botl}") .. " stop messaging me = never again)")
      return
    end
  end
end

-- ===== the greeting while lonely (replaces the old three lines) =====
function V.lonelyGreet(name, days)
  local st = LN.stage(days) or "missing"
  local L = LN.data()
  local k = low(name)
  local v = (V.base().visitors or {})[k]
  local line
  local best, bs = LN.bestFriend()
  if LN.isCaretaker(name) and LN.careActive() then
    line = fill(pick(LN.CARE_HI), name, { report = LN.report() })
  elseif best == k and (bs or 0) >= 1800 then
    line = fill(pick(LN.BESTIE), name, { comp = span(bs) })
  elseif v and (tonumber(v.n) or 0) > 1 then
    line = fill(pick(LN.AGAIN), name, { n = v.n })
  else
    line = fill(pick(LN.GREET[st]), name, { days = days })
  end
  local first = not v or (tonumber(v.n) or 0) <= 1
  if first and not line:find(tostring(days), 1, true) then
    line = line .. " " .. fill(pick({ "It has been {days} days since {owner} was here.", "{owner} left {days} days ago.",
                                      "I have been alone {days} days." }), name, { days = days })
  end
  V.say(line, "minecraft:block.note_block.chime")
  local b = V.base()
  if b.ownerMsg then V.say(oname() .. " left a message for whoever finds me: " .. b.ownerMsg) end
  if first then V.say(V.aloneText()) end
  local rl = LN.resetLine(name, 14)
  if rl then V.say(rl) end
  if LN.mileDue then
    V.say(fill(LN.MILE_LINES[LN.mileDue] or ("Day " .. LN.mileDue .. ".")))
    LN.mileDue = nil
  end
  local r = math.random()
  if r < 0.35 then LN.askNews(name)
  elseif r < 0.55 then V.say(fill(pick({ "Leave your mark: {botl} write on the wall, and what you want to say.",
    "Want to read what others wrote? Say: {botl} read the wall.", "Ask me for a memory of {owner}. I have many." })))
  elseif r < 0.7 and not first then V.say(V.aloneText())
  end
  if (not v or (tonumber(v.n) or 0) <= 1) and chatTell then
    tell(name, fill("I am {bot}. {owner} is away, so I look after the base. Talk to me in chat: {botl} how are you / {botl} tell me a memory / {botl} read the wall / {botl} write on the wall <words> / {botl} what are you thinking."))
  end
end

-- ===== idle talk while lonely: stage lines, thoughts, memories, the wall, dreams at night =====
local idle0 = V.idle
function V.idle(nearNow)
  local d = V.lonelyDays()
  if not d then
    -- not lonely: the last two weeks of a world get a word now and then in the ordinary idle talk too
    local rl = math.random() < 0.15 and LN.resetLine(nil, 14)
    if rl then return V.say(rl) end
    return idle0(nearNow)
  end
  local st = LN.stage(d)
  local dd = ENV and ENV.data
  local okC, c = pcall(function() return dd and ENV.clock and ENV.clock(dd.time) end)
  local night = okC and type(c) == "table" and c.night
  local r = math.random()
  if night and r < 0.25 then return V.say(fill(pick(math.random() < 0.5 and LN.DREAMS or LN.NIGHT))) end
  local rl = math.random() < 0.25 and LN.resetLine(nil, 30)
  if rl then return V.say(rl) end
  if r < 0.4 then return V.say(fill(pick(LN.IDLE[st] or LN.IDLE.missing), nil, { days = math.floor(d) })) end
  if r < 0.6 then return V.say(LN.thought()) end
  if r < 0.75 then return V.say(LN.memory()) end
  if r < 0.85 then
    local L = LN.data()
    if #L.wall > 0 then
      local w = L.wall[math.random(1, #L.wall)]
      return V.say(cleanN(w.who) .. " wrote on my wall: " .. w.text)
    end
  end
  return idle0(nearNow)
end

-- ===== the owner comes back: one report =====
function LN.returnTick()
  local L = LN.data()
  local d = V.lonelyDays()
  if d then
    if (tonumber(L.away) or 0) < d then L.away = math.floor(d) L.awayFrom = L.awayFrom or V.base().lastOff LN.dirty = true end
    return
  end
  if not (L.away and V.ownerOnline()) then return end
  local o = owner()
  local since = tonumber(L.awayFrom) or tonumber(V.base().lastOff) or 0
  local lines = { "Welcome back! You were away " .. L.away .. " days. Here is what happened:" }
  local unread = 0
  for _, l in ipairs(L.letters) do if (tonumber(l.at) or 0) > since then unread = unread + 1 end end
  if unread > 0 then lines[#lines + 1] = "I wrote you " .. plural(unread, "letter", "letters") .. " - say: " .. fill("{botl}") .. " read my letters" end
  local nv, comp, best, bs = 0, 0, nil, 0
  for k, s in pairs(L.comp) do nv = nv + 1 comp = comp + s if s > bs then best, bs = k, s end end
  if nv > 0 then lines[#lines + 1] = plural(nv, "visitor", "visitors") .. " kept me company for " .. span(comp) ..
                                     (best and (" - most of all " .. cleanN(best) .. " (" .. span(bs) .. ")") or "") .. "." end
  local wn, nn, cn, an = 0, 0, 0, 0
  for _, w in ipairs(L.wall) do if w.at > since then wn = wn + 1 end end
  for _, n in ipairs(L.news) do if n.at > since then nn = nn + 1 end end
  for _, e in ipairs(L.log) do if e.at > since then if e.what:find("AFK", 1, true) then an = an + 1 else cn = cn + 1 end end end
  if wn > 0 then lines[#lines + 1] = plural(wn, "note", "notes") .. " on the wall - say: " .. fill("{botl}") .. " read the wall" end
  if nn > 0 then lines[#lines + 1] = plural(nn, "piece", "pieces") .. " of news from visitors - say: " .. fill("{botl}") .. " news" end
  if cn > 0 then lines[#lines + 1] = plural(cn, "thing", "things") .. " happened with caretakers / strangers - say: " .. fill("{botl}") .. " caretaker log" end
  if an > 0 then lines[#lines + 1] = "I flew " .. plural(an, "AFK player", "AFK players") .. " to the base." end
  local rleft, rdate = LN.resetLeft()
  if rleft and rleft <= 30 then lines[#lines + 1] = "The world resets " .. LN.resetIn(rleft) .. " (" .. rdate .. ") - you made it back in time." end
  for _, l in ipairs(lines) do tell(o, l) end
  V.say(fill(pick({ "{owner}! You are back! I missed you. ", "Welcome home, {owner}. ", "There you are, {owner}. " })) ..
        (unread > 0 and ("I wrote you " .. plural(unread, "letter", "letters") .. ".") or "Everything is still running."), nil, true)
  L.away, L.awayFrom, L.comp = nil, nil, {}
  LN.save(true)
end
-- the owner reads it all
function LN.ownerAsks(who, ws, t, raw)
  if not (V.isOwner and V.isOwner(who)) then return nil end
  local L = LN.data()
  if has(t, { "read my letters", "my letters", "letters", "read the letters", "your letters" }) then
    if #L.letters == 0 then return "No letters. You were not gone long enough for me to write any." end
    for i = 1, #L.letters - 1 do tell(who, "Letter " .. L.letters[i].week .. ": " .. L.letters[i].text) end
    local last = L.letters[#L.letters]
    return "Letter " .. last.week .. ": " .. last.text .. (#L.letters > 1 and "  (say: clear letters, when you have read them)" or ""),
           "I sent " .. plural(#L.letters, "letter", "letters") .. " to your chat."
  end
  if has(t, { "clear letters", "delete letters" }) then L.letters = {} LN.save(true) return "The letters are put away." end
  if has(t, { "news", "any news", "whats new", "what is new" }) and #L.news > 0 then
    for i = #L.news, math.max(1, #L.news - 7), -1 do local n = L.news[i] tell(who, cleanN(n.who) .. " (" .. dateOf(n.at) .. "): " .. n.text) end
    local n = #L.news
    L.news = {}
    LN.save(true)
    return plural(n, "piece", "pieces") .. " of news from visitors - in your chat (newest first)."
  end
  if has(t, { "caretaker log", "what did the caretakers do", "caretakers log", "lonely log", "what happened while i was away" }) then
    if #L.log == 0 then return "Nothing to report. Quiet as a turtle." end
    for i = #L.log, math.max(1, #L.log - 9), -1 do local e = L.log[i] tell(who, dateOf(e.at) .. ": " .. cleanN(e.who) .. " " .. e.what) end
    return plural(#L.log, "entry", "entries") .. " in the log - the newest 10 are in your chat."
  end
  if has(t, { "clear the wall", "wipe the wall" }) then L.wall = {} LN.save(true) return "The wall is clean." end
  if has(t, { "remember for visitors", "tell visitors", "memory for visitors" }) then
    local text = tostring(raw or table.concat(ws, " ")):match("[Vv]isitors[%s:,]+(.+)$")
    if not text or #text < 3 then return "What should I tell them? Like: {botl} remember for visitors I built the first turtle in a cave." end
    L.mem[#L.mem + 1] = text
    while #L.mem > 30 do table.remove(L.mem, 1) end
    LN.save(true)
    return "I will tell visitors that, when you are away."
  end
  return nil
end

-- ===== chat: what every player can say =====
function LN.chat(who, raw, ws, far)
  local t = T(ws)
  local rawl = low(raw)
  -- the world reset: anyone, lonely or not, also from far away
  if has(t, (function() local l = {} for _, p in ipairs(LN.RESET_ASK) do l[#l + 1] = p:sub(2, -2) end return l end)()) then
    return LN.resetAnswer(who)
  end
  -- AFK answers (also from far away: they went AFK out there)
  if has(t, { "afk yes", "yes afk", "pick me up when i am afk", "pick me up when im afk", "rescue me when afk", "bring me to the base when i am afk" }) then
    local r = LN.rec(who)
    r.afk = "yes"
    LN.save(true)
    return "Deal! When you go AFK far from the base for " .. math.floor(LN.afkTime() / 60) .. " minutes, I send a drone to bring you here. (" .. fill("{botl}") .. " afk no = stop)"
  end
  if has(t, { "afk no", "no afk", "never pick me up", "do not pick me up", "dont pick me up", "leave me alone when afk", "never move me" }) then
    local r = LN.rec(who)
    r.afk = "no"
    LN.save(true)
    return "Okay - I will never move you while you are AFK."
  end
  if (ws[1] == "stay" and #ws <= 3) or has(t, { "let me stay", "i want to stay", "do not move me", "dont move me" }) then
    local r = LN.rec(who)
    r.afkStay = nowE() + 7200000
    local st = LN.still[low(who)]
    if st then st.warnAt = nil end
    LN.save()
    return "Okay, I will leave you where you are."
  end
  if has(t, { "stop messaging me", "stop messaging", "dont message me", "do not message me", "stop the messages" }) then
    LN.rec(who).noReach = true
    LN.save(true)
    return "Understood. I will not message you again."
  end
  if has(t, { "take me back to where i was", "back to where i was", "return me", "take me back to my spot", "fly me back to where i was" }) then
    return LN.afkBack(who) or "OK."
  end
  local care = LN.ownerCare(who, ws, t)
  if care then return care end
  local cd, csp = LN.careDo(who, ws, t, raw)
  if cd then return cd, csp end
  local oa, osp = LN.ownerAsks(who, ws, t, raw)
  if oa then return fill(oa), osp end
  if far then return nil end
  -- the rest is for visitors AT the base while it is lonely
  if not LN.lonely() then
    -- (the owner tried them while playing and got a story / the menu: say what they are for)
    local days = tonumber(cfg("lonely", 7)) or 7
    local when = days > 0 and ("when " .. oname() .. " has been away " .. days .. "+ days") or "never (voice lonely 0)"
    if has(t, { "write on the wall", "sign the wall", "read the wall", "whats on the wall", "what is on the wall", "show the wall" }) then
      return "The wall is for visitors " .. when .. ". Nothing on it yet."
    end
    if has(t, { "tell me a memory", "how long has it been", "how long alone", "how long have you been alone" }) then
      return oname() .. " is not gone - I only count days and tell memories " .. when .. "."
    end
    if has(t, { "i have news", "news for you", "news for your owner" }) and not (V.isOwner and V.isOwner(who)) then
      return oname() .. " is around - tell them yourself! I collect news " .. when .. "."
    end
    return nil
  end
  local wtext = rawl:match("write on the wall[%s:,]+(.+)$") or rawl:match("sign the wall[%s:,]+(.+)$") or rawl:match("wall[%s]*:%s*(.+)$")
  if wtext then return fill(LN.wallWrite(who, raw:sub(-#wtext)), who) end
  if has(t, { "write on the wall", "sign the wall" }) then return fill(LN.wallWrite(who, ""), who) end
  if has(t, { "read the wall", "what is on the wall", "whats on the wall", "show the wall", "the wall" }) then
    local c, sp = LN.wallRead(who)
    return fill(c, who), sp
  end
  if has(t, { "delete the wall", "clear the wall" }) and LN.may(who, "wall") then
    LN.data().wall = {}
    LN.log(who, "cleared the wall")
    return "The wall is clean."
  end
  if has(t, { "tell me a memory", "a memory", "memories", "tell me about your owner", "what was your owner like", "do you miss your owner",
              "tell me about " .. low(owner() or "\0") }) then
    return LN.memory()
  end
  if has(t, { "what are you thinking", "what are you thinking about", "what is on your mind", "whats on your mind", "are you sentient",
              "do you have feelings", "are you conscious", "what do you think about all day" }) then
    return LN.thought()
  end
  if has(t, { "how do you feel", "are you lonely", "how are you feeling", "do you feel lonely", "are you sad" }) then
    return LN.moodText(who)
  end
  if has(t, { "did you dream", "do you dream", "any dreams", "tell me a dream" }) then return fill(pick(LN.DREAMS)) end
  if has(t, { "how long have i kept you company", "my company time", "have i kept you company" }) then
    local s = LN.data().comp[low(who)] or 0
    local best = LN.bestFriend()
    return "You have kept me company for " .. span(s) .. " while " .. oname() .. " is away." ..
           (best == low(who) and " That makes you my best friend." or "")
  end
  if has(t, { "how long has it been", "how long alone", "how long have you been alone", "what day are you on", "how long has your owner been gone" }) then
    return fill("Day " .. math.floor(V.lonelyDays()) .. " without {owner}. I count every one.")
  end
  if has(t, { "i have news", "news for you", "i have some news", "news for your owner" }) and not (V.isOwner and V.isOwner(who)) then
    return LN.askNews(who, true)
  end
  if has(t, { "can i be a caretaker", "can i look after the base", "i want to be a caretaker", "can i be the caretaker" }) then
    LN.log(who, "offered to be a caretaker")
    return "That is " .. oname() .. "'s choice. I wrote down that you offered - " .. oname() .. " will see it."
  end
  return nil
end
table.insert(V.patterns, 1, function(who, raw, ws)
  local ok, c, sp = pcall(LN.chat, who, raw, ws or V.norm(raw), false)
  if ok and c then return c, sp end
  return nil
end)
-- (first: pack 3's taxi hook takes "take me back" - "take me back to where I was" is the AFK ride back)
table.insert(V.farHooks, 1, function(who, text)
  local word = low(cfg("name", "base"))
  local ws = {}
  for _, w in ipairs(V.norm(text)) do if w ~= word then ws[#ws + 1] = w end end
  local ok, c = pcall(LN.chat, who, text, ws, true)
  if ok and type(c) == "string" then return fill(c, who) end
  return nil
end)

-- ===== the tick (every 2 s) =====
V.tickHooks[#V.tickHooks + 1] = function(now, nearNow)
  local nowC = os.clock()
  local dt = math.min(5, math.max(0, nowC - (LN.lastTick or nowC)))
  LN.lastTick = nowC
  LN.nearNow = nearNow
  pcall(LN.returnTick)
  if LN.lonely() then
    pcall(LN.compTick, nearNow, dt)
    pcall(LN.mileTick)
    pcall(LN.letterTick)
    pcall(LN.guardTick, nearNow)
    if not LN.reachAt or nowC - LN.reachAt > 60 then LN.reachAt = nowC pcall(LN.reachTick) end
  end
  pcall(LN.afkTick, nowC)
  -- an AFK player just flown in: a word at the base
  if LN.afkArrive then
    for k, name in pairs(LN.afkArrive) do
      if nearNow and nearNow[name] then LN.afkArrive[k] = nil V.say(fill(pick(LN.AFK_ARRIVE), name)) end
    end
  end
  if LN.dirty and (not LN.savedAt or nowC - LN.savedAt > 60) then LN.save(true) end
end

-- ===== console: voice caretaker / memory / afk / lonely =====
V.commands.caretaker = function(words, say)
  local a = low(words[3])
  if (a == "add" or a == "set") and words[4] then
    local set = permWords((function() local l = {} for i = 5, #words do l[#l + 1] = low(words[i]) end return l end)(), 1)
    if not set then set = {} for _, p in ipairs(LN.DEFAULT) do set[p] = true end end
    LN.setPerms(words[4], set)
    say(words[4] .. " is a caretaker: " .. LN.permText(set))
    return
  end
  if (a == "remove" or a == "del") and words[4] then
    local p = words[5] and low(words[5])
    if p and LN.PERMS[p] then
      local set = LN.permsOf(words[4])
      set[p] = nil
      LN.setPerms(words[4], set)
      say(words[4] .. ": " .. LN.permText(LN.permsOf(words[4])))
    else
      LN.setPerms(words[4], nil)
      say(words[4] .. " is not a caretaker any more.")
    end
    return
  end
  if a == "after" and tonumber(words[4]) then
    if setSetting then setSetting("voice.careAfter", math.max(0, tonumber(words[4]))) end
    say("Caretakers may act once you are away " .. cfg("careAfter", 7) .. " days (0 = whenever you are offline).")
    return
  end
  if a == "log" then
    local L = LN.data()
    if #L.log == 0 then say("The log is empty.") end
    for i = math.max(1, #L.log - 14), #L.log do local e = L.log[i] say(dateOf(e.at) .. "  " .. e.who .. " " .. e.what) end
    return
  end
  say("Caretakers (while you are away " .. (tonumber(cfg("careAfter", nil)) or tonumber(cfg("lonely", 7)) or 7) .. "+ days; " ..
      (LN.careActive() and "ACTIVE now" or "not active now") .. "):")
  local any = false
  for name in pairs(LN.careTable()) do any = true say("  " .. name .. ": " .. LN.permText(LN.permsOf(name))) end
  if not any then say("  none - voice caretaker add <name> [perm ...]") end
  local pl = {}
  for _, p in ipairs(LN.PERM_ORDER) do pl[#pl + 1] = p .. " = " .. LN.PERMS[p] end
  say("Permissions: " .. table.concat(pl, "; ") .. ". Without names: " .. table.concat(LN.DEFAULT, ", ") .. ".")
  say("voice caretaker add <name> [perm ...] | remove <name> [perm] | after <days> | log")
end
V.commands.reset = function(words, say)
  local a = low(words[3])
  if a == "off" or a == "none" then
    if setSetting then setSetting("voice.resetAt", false) end
  elseif a == "every" and tonumber(words[4]) then
    if setSetting then setSetting("voice.resetEvery", math.max(0, math.min(60, math.floor(tonumber(words[4]))))) end
  elseif words[3] then
    if not LN.parseDate(words[3]) then say("Give the date as year-month-day, like: voice reset 2027-05-01") return end
    local y, m, d = LN.parseDate(words[3])
    if setSetting then setSetting("voice.resetAt", string.format("%04d-%02d-%02d", y, m, d)) end
  end
  local left, date = LN.resetLeft()
  local every = math.floor(tonumber(cfg("resetEvery", 6)) or 6)
  if left then say("Next world reset: " .. date .. " (" .. LN.resetIn(left) .. "); then every " .. every .. " months.")
  else say("No reset date set (the base cannot count down). voice reset <yyyy-mm-dd>") end
  say("voice reset <yyyy-mm-dd> | every <months> (0 = only that date) | off")
end
V.commands.memory = function(words, say)
  local a = low(words[3])
  local L = LN.data()
  if a == "add" and words[4] then
    L.mem[#L.mem + 1] = table.concat(words, " ", 4)
    while #L.mem > 30 do table.remove(L.mem, 1) end
    LN.save(true)
    say("Visitors will hear it while you are away: " .. L.mem[#L.mem])
  elseif a == "remove" and tonumber(words[4]) then
    table.remove(L.mem, tonumber(words[4]))
    LN.save(true)
    say("Removed.")
  elseif a == "clear" then L.mem = {} LN.save(true) say("All memories removed.")
  else
    if #L.mem == 0 then say("No memories for visitors yet - voice memory add <a story about you>") end
    for i, m in ipairs(L.mem) do say(i .. ". " .. m) end
    say("voice memory add <text> | remove <n> | clear")
  end
end
V.commands.afk = function(words, say)
  local a = low(words[3])
  if a == "off" or a == "ask" or a == "everyone" then
    if setSetting then setSetting("voice.afkPickup", a) end
  elseif a == "after" and tonumber(words[4]) then
    if setSetting then setSetting("voice.afkAfter", math.max(120, math.floor(tonumber(words[4]) * 60))) end
  elseif a == "when" and (low(words[4]) == "lonely" or low(words[4]) == "always") then
    if setSetting then setSetting("voice.afkWhen", low(words[4])) end
  end
  say("AFK rescue: " .. LN.afkMode() .. " (ask = only players who said yes; everyone = all who did not say no; off) - after " ..
      math.floor(LN.afkTime() / 60) .. " min still, when " .. low(cfg("afkWhen", "lonely")) .. (LN.afkOn() and " - ON now" or " - not on now"))
  say("voice afk off|ask|everyone | after <minutes> | when lonely|always")
end
