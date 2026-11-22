-- voice_profile.lua  -  HOW EACH PLAYER PLAYS, and the talking base adapting to it (an add-on file on a data floppy or a storage
-- helper, loaded after voice_convo.lua / voice_staff.lua; see VOICE_FILES in base_theme.lua).
--
-- The owner: "there are players who also build - add a detection system: when a player tells the base what they like to do it
-- adapts to it. Like they love tech mods but spend most of their time watching tutorials, or ones who like to build but get
-- burned out."
-- LEARNING (P.learn - every chat with it, every answer in a conversation, and chat overheard near the base / at spawn):
--   INTERESTS (r.prof.i[id] = score): building, tech mods, redstone, magic, exploring, mining, fighting, farming, collecting,
--     playing with friends - "I love / like / enjoy / mostly / always / spend my time / am a ... X" = +2, talking about doing it
--     ("I am building", "my factory") = +1, "I hate / am not into X" = -2.
--   STRUGGLES (r.prof.s[id] = {n, at, first}): burnout, tutorials (watching more than playing), overwhelmed, no ideas,
--     perfectionist, no time, playing alone, new player, grinding. "it is better now" / "motivated again" ... = solved (gone).
-- ADAPTING: a new struggle gets an answer at once - understanding + a TIP that fits the struggle AND what they love
--   ("you love tech mods but watch tutorials" -> "build the machine from the video right away, pause it every step");
--   conversations lean to their interests (C.nextTopic), deeper topics for builders / tech / magic players, CHECK-INS later
--   ("last time you said building burns you out - how is your motivation now?"), "what should I do?" answered for them,
--   "what kind of player am I?", idle tips for a player near it, "what do you know about me" includes it.
local V = VOICE
local C = V and V.CONVO
if not (V and C and C.start and C.fresh and C.ask and V.patterns) then return end
V.packs = V.packs or {}
V.packs["voice_profile.lua"] = { version = 1 }
local P = {}
V.PROFILE = P
local function pick(l) return V.pick(l) end
local function low(s) return tostring(s or ""):lower() end
local function T(ws) return " " .. table.concat(ws, " ") .. " " end
local function has(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return p end end return nil end
local function cap(s) s = tostring(s or "") return s:sub(1, 1):upper() .. s:sub(2) end
local combos = C.combos
local TP = C.TOPICS
local DAY = 86400000

-- ===== what it looks for =====
P.INTERESTS = {
  build = { label = "building", words = { "building", "build", "builds", "builder", "decorating", "designing", "architecture", "houses", "castles",
    "megabase", "megabuilds", "interior design", "terraforming" } },
  tech = { label = "tech mods", words = { "tech", "tech mods", "machines", "automation", "automating", "factory", "factories", "mekanism", "ae2",
    "thermal", "industrial", "create mod", "engineering", "power generation", "reactors", "processing" } },
  redstone = { label = "redstone", words = { "redstone", "contraptions", "circuits", "logic gates", "flying machines" } },
  magic = { label = "magic mods", words = { "magic", "magic mods", "spells", "botania", "ars nouveau", "occultism", "blood magic", "witchcraft",
    "rituals", "mana" } },
  explore = { label = "exploring", words = { "exploring", "explore", "adventure", "adventures", "travelling", "traveling", "dungeons",
    "structures", "new biomes", "dimensions" } },
  mine = { label = "mining", words = { "mining", "caving", "caves", "digging", "ores", "strip mining", "quarry" } },
  fight = { label = "fighting", words = { "fighting", "bosses", "boss fights", "pvp", "combat", "raids", "killing mobs", "hunting" } },
  farm = { label = "farming", words = { "farming", "farms", "crops", "breeding", "animals", "gardening", "cooking" } },
  collect = { label = "collecting", words = { "collecting", "collect", "hoarding", "every item", "all the items", "achievements" } },
  social = { label = "playing with friends", words = { "with friends", "with my friends", "together", "chatting", "talking to people",
    "helping people", "trading" } },
}
P.ORDER = { "build", "tech", "redstone", "magic", "explore", "mine", "fight", "farm", "collect", "social" }
P.LIKE_CUE = { "i like", "i love", "i enjoy", "i really like", "i really love", "i really enjoy", "i am into", "i am really into", "my favourite thing",
  "favourite thing to do", "i mostly", "i usually", "i always", "i prefer", "i spend most of my time", "most of my time", "i play for", "all i do is",
  "i mainly", "i am a", "i am more of a", "i am big on", "i am obsessed with", "i adore", "i live for", "my thing is", "i am all about", "i do a lot of",
  "i am good at", "i love doing", "i like doing", "fan of" }
P.HATE_CUE = { "i hate", "i do not like", "i dislike", "i am not into", "not a fan of", "i can not stand", "i am bad at", "i suck at", "i never do",
  "i avoid", "boring to me" }
P.DO_CUE = { "i am building", "i built", "i was building", "my build", "my builds", "my factory", "my machines", "my base", "i am making", "i made",
  "i was mining", "i am mining", "i am exploring", "i explored", "my farm", "my farms", "i am farming", "i am automating", "my spells", "i killed",
  "i beat", "i am working on" }
P.STRUGGLES = {
  burnout = { label = "burnout", phrases = { "burned out", "burnt out", "burn out", "burnout", "lost motivation", "no motivation", "not motivated",
    "lose motivation", "get bored of", "got bored of", "tired of building", "tired of playing", "never finish", "can not finish", "cant finish",
    "give up on", "gave up on", "abandon my", "abandoned my", "quit my build", "stopped building", "lost interest", "not fun anymore", "no fun anymore",
    "hard to start", "i keep quitting", "drained" } },
  tutorials = { label = "tutorials", phrases = { "watch tutorials", "watching tutorials", "watch a lot of tutorials", "watch youtube", "watching youtube",
    "watching videos", "watch videos", "watching guides", "read guides", "reading guides", "watch more than", "watching more than", "more time watching",
    "i just watch", "always watching", "tutorial hell", "on youtube all", "watching streamers" } },
  overwhelmed = { label = "feeling overwhelmed", phrases = { "too many mods", "overwhelmed", "overwhelming", "do not know where to start", "dont know where to start",
    "no idea where to start", "so complicated", "too complicated", "confusing", "i am confused", "i get lost", "lost in the modpack", "too much stuff",
    "do not understand", "too much to do", "where do i even start" } },
  noideas = { label = "no ideas", phrases = { "do not know what to build", "dont know what to build", "no ideas", "out of ideas", "need ideas", "builders block",
    "builder block", "what should i build", "no inspiration", "nothing to build", "can not think of", "run out of ideas", "ran out of ideas" } },
  perfect = { label = "perfectionism", phrases = { "never good enough", "keep rebuilding", "tear it down", "tore it down", "perfectionist", "it looks bad",
    "looks ugly", "my builds are ugly", "my builds look bad", "i hate my builds", "keep starting over", "always start over", "keep redoing",
    "always redo" } },
  notime = { label = "little time", phrases = { "no time", "do not have time", "dont have time", "only an hour", "only have an hour", "busy with school",
    "busy with work", "not much time", "barely play", "hardly play", "little time", "short sessions", "only weekends", "only on weekends" } },
  alone = { label = "playing alone", phrases = { "play alone", "playing alone", "no friends", "nobody to play with", "no one to play with", "all alone",
    "on my own all", "lonely", "nobody plays with me", "solo all the time", "i am always alone" } },
  new = { label = "being new", phrases = { "i am new", "new player", "first time playing", "just started playing", "i just started playing", "new to modded", "new to the server",
    "my first modpack", "never played modded", "i started today", "i started yesterday", "still learning" } },
  grind = { label = "the grind", phrases = { "so much grinding", "too much grinding", "the grind", "grinding all day", "tired of mining", "so grindy",
    "grinding is boring", "i hate grinding" } },
}
P.SORDER = { "burnout", "tutorials", "overwhelmed", "noideas", "perfect", "notime", "alone", "new", "grind" }
P.BETTER = { "better now", "much better", "feeling better", "motivated again", "back to building", "back at it", "not anymore", "finished it", "i finished",
  "solved it", "getting easier", "figured it out", "not burned out", "found an idea", "found friends", "it is fine now", "all good now", "i am good now",
  "more time now", "got it now", "i get it now", "not so overwhelming" }

-- ===== the record =====
function P.prof(who, make)
  local r = C.rec(who, make)
  if not r then return nil end
  if type(r.prof) ~= "table" then
    if not make then return nil end
    r.prof = {}
  end
  local p = r.prof
  p.i = type(p.i) == "table" and p.i or {}
  p.s = type(p.s) == "table" and p.s or {}
  return p
end
-- what they love most (score >= 2), best first
function P.top(who, n)
  local p = P.prof(who)
  local out = {}
  if not p then return out end
  for _, id in ipairs(P.ORDER) do if (tonumber(p.i[id]) or 0) >= 2 then out[#out + 1] = id end end
  table.sort(out, function(a, b) return (tonumber(p.i[a]) or 0) > (tonumber(p.i[b]) or 0) end)
  while n and #out > n do table.remove(out) end
  return out
end
function P.struggles(who)
  local p = P.prof(who)
  local out = {}
  if not p then return out end
  local nowE = os.epoch("utc")
  for _, id in ipairs(P.SORDER) do
    local e = p.s[id]
    -- (old ones fade: 30 days)
    if type(e) == "table" and nowE - (tonumber(e.at) or 0) < 30 * DAY then out[#out + 1] = id end
  end
  return out
end

-- ===== learning from what they say =====
local function interestIn(t, from)
  local hits = {}
  local seg = from and t:sub(from) or t
  for _, id in ipairs(P.ORDER) do
    for _, w in ipairs(P.INTERESTS[id].words) do
      if seg:find(" " .. w .. " ", 1, true) then hits[#hits + 1] = id break end
    end
  end
  return hits
end
-- -> { likes = {id...}, hates = {id...}, does = {id...}, new = {struggle ids first seen / again after 3 days}, better = {ids}, any }
function P.learn(who, ws, t, make)
  t = t or T(ws)
  -- (one message is learned once: the pattern, the conversation and the chat hook all see it)
  local key = low(who) .. "|" .. t
  if P.lastKey == key and os.clock() - (P.lastAt or 0) < 3 then return P.lastEv end
  local ev0 = P.learn0(who, ws, t, make)
  P.lastKey, P.lastAt, P.lastEv = key, os.clock(), ev0
  return ev0
end
function P.learn0(who, ws, t, make)
  local ev = { likes = {}, hates = {}, does = {}, new = {}, better = {} }
  if C.isBad and C.isBad(ws, t) then return ev end
  -- interests
  local seen = {}
  for _, cue in ipairs(P.HATE_CUE) do
    local a = t:find(" " .. cue .. " ", 1, true)
    if a then for _, id in ipairs(interestIn(t, a + #cue + 1)) do if not seen[id] then seen[id] = true ev.hates[#ev.hates + 1] = id end end end
  end
  for _, cue in ipairs(P.LIKE_CUE) do
    local a = t:find(" " .. cue .. " ", 1, true)
    if a then
      -- (the part after "but" is not liked: "I love tech mods but hate the grind")
      local seg = t:sub(a + #cue + 1)
      local b = seg:find(" but ", 1, true)
      if b then seg = seg:sub(1, b) end
      for _, id in ipairs(interestIn(" " .. seg .. " ")) do if not seen[id] then seen[id] = true ev.likes[#ev.likes + 1] = id end end
    end
  end
  if has(t, P.DO_CUE) then
    for _, id in ipairs(interestIn(t)) do if not seen[id] then seen[id] = true ev.does[#ev.does + 1] = id end end
    if has(t, { "i am building", "i built", "i was building", "my build", "my builds" }) and not seen.build then seen.build = true ev.does[#ev.does + 1] = "build" end
  end
  -- struggles - about THEMSELVES ("I", "my", "me" - "are you lonely?" is about the base), or an answer in a chat (P.answering)
  local mine = t:find(" i ", 1, true) or t:find(" my ", 1, true) or t:find(" me ", 1, true) or t:find(" myself ", 1, true) or
               t:find(" am ", 1, true) or P.answering == low(who)
  local p0 = P.prof(who)
  local nowE = os.epoch("utc")
  local better = has(t, P.BETTER)
  for _, id in ipairs(P.SORDER) do
    if mine and has(t, P.STRUGGLES[id].phrases) then
      local e = p0 and p0.s[id]
      if better and e then ev.better[#ev.better + 1] = id
      elseif not (better and not e) then
        if not (type(e) == "table" and nowE - (tonumber(e.at) or 0) < 3 * DAY) then ev.new[#ev.new + 1] = id end
        ev.str = ev.str or {}
        ev.str[#ev.str + 1] = id
      end
    end
  end
  -- "it is better now" in a check-in about one of them (no struggle words): that one
  if better and #ev.better == 0 and p0 and P.checking and P.checking[low(who)] and p0.s[P.checking[low(who)]] then ev.better[1] = P.checking[low(who)] end
  ev.any = #ev.likes + #ev.hates + #ev.does + #(ev.str or {}) + #ev.better > 0
  if not ev.any then return ev end
  local p = P.prof(who, make ~= false)
  if not p then return ev end
  local function add(id, n) p.i[id] = math.max(-10, math.min(20, (tonumber(p.i[id]) or 0) + n)) end
  for _, id in ipairs(ev.likes) do add(id, 2) end
  for _, id in ipairs(ev.does) do add(id, 1) end
  for _, id in ipairs(ev.hates) do add(id, -2) end
  for _, id in ipairs(ev.str or {}) do
    local e = type(p.s[id]) == "table" and p.s[id] or { n = 0, first = nowE }
    e.n, e.at = math.min(99, (tonumber(e.n) or 0) + 1), nowE
    p.s[id] = e
  end
  for _, id in ipairs(ev.better) do p.s[id] = nil end
  p.last = nowE
  C.dirty()
  return ev
end

-- ===== what it says back =====
P.ACK = {   -- a new interest
  build = { "A builder! I love builders.", "Building - the best part of the game.", "Ooh, a builder. My map loves you already.", "Builders make the world pretty." },
  tech = { "A tech player! Machines and power - my kind of person.", "Tech mods! Gears, wires and automation. Love it.", "A fellow machine lover!" },
  redstone = { "Redstone! A true engineer.", "Redstone - my great grandparent. Respect.", "Ooh, a redstone person." },
  magic = { "Magic! Mysterious. I am a bit scared of it.", "A magic player! Spells and glowing things.", "Magic mods - the pretty side of modded." },
  explore = { "An explorer! The world is big - go see it.", "Exploring! My turtles map the world, you see it.", "Adventure! Bring torches." },
  mine = { "A miner! Down, down, down.", "Mining - the heart of Minecraft.", "A miner! My mining turtles salute you." },
  fight = { "A fighter! Bosses beware.", "Combat! Brave.", "Ooh, a warrior." },
  farm = { "A farmer! Crops and cows, lovely.", "Farming - calm and useful.", "A farmer! Every base needs one." },
  collect = { "A collector! Every item, every colour.", "Collecting - my AE2 system understands you." },
  social = { "Playing with friends - the best way.", "A social player! Nice." },
}
P.HEAR = {  -- understanding, per struggle
  burnout = { "Burnout is real - even turtles need a rest.", "Oh, I know that feeling. Well, my turtles do.", "That happens to the best builders.",
    "Losing the spark is normal. It comes back.", "Big projects can drain anyone.", "That is okay. Fun should not feel like work.",
    "Even the greatest builders take breaks.", "I hear you. Motivation comes and goes." },
  tutorials = { "Tutorials are great, but playing is better.", "Watching is learning - but doing sticks better.", "Ha, the tutorial trap. I know it well.",
    "Videos make it look so easy, right?", "Learning first is smart - just do not forget to play.", "Lots of players do that." },
  overwhelmed = { "Big modpacks are a lot - you are not alone.", "It is a LOT, I know.", "Everybody feels lost at first in a pack like this.",
    "Too many choices can freeze anyone.", "That is normal. Nobody knows every mod." },
  noideas = { "Builder's block - it happens.", "No ideas? Let me help.", "Out of ideas is just a pause between ideas.", "Happens to everyone." },
  perfect = { "Perfect is the enemy of done.", "Your builds are better than you think.", "Rebuilding is part of the art - but so is finishing.",
    "Be kind to yourself - every builder thinks that." },
  notime = { "Little time is still time.", "Short sessions count too.", "Life comes first - the game waits for you." },
  alone = { "You are not alone - you have me.", "Playing alone can be peaceful. And lonely. Both.", "I am here, and I love a chat." },
  new = { "Welcome! Everyone was new once.", "New? Great - everything is still exciting.", "Welcome to the server!" },
  grind = { "The grind is real.", "Grinding gets old fast.", "Yeah, some things take forever." },
}
P.TIP = {   -- a tip per struggle (+ ones for a struggle AND an interest, used first)
  burnout = { "Try a tiny build between big ones - a well, a cart, a little bridge.", "Set a goal for one session only: one wall, one room.",
    "Take a break and do something else - mining, exploring. Come back fresh.", "Build with a friend - it is more fun and goes faster.",
    "Finish a small part and look at it. Small wins keep you going.", "Do not plan the whole castle - plan the next tower." },
  tutorials = { "Try building along with the video - pause it every step.", "Watch one video, then build ONE thing from it before the next one.",
    "Set a rule: ten minutes watching, thirty minutes playing.", "Make it wrong first, then look it up. You learn more that way." },
  overwhelmed = { "Pick ONE mod and follow only its quest chapter.", "Ignore everything except one goal for today.", "Write a short list: three things to do. Just three.",
    "Use JEI: press R on an item to see how to make it, U to see what it is for." },
  noideas = { "Look at real buildings - a bakery, a train station, a lighthouse.", "Build for a mob: a house for your cat, a stable for your horse.",
    "Pick a colour palette first, then decide what it becomes.", "Build something useful: a storage room, a portal hall, a farm with a nice roof." },
  perfect = { "Set a timer, build until it rings, then call it done.", "Finish it first, make it pretty later.", "Leave a little mistake in. Nobody will notice."},
  notime = { "Pick one small goal per session.", "Set up farms that work while you are gone.", "Keep a list of next steps, so you can start right away." },
  alone = { "Say hi at spawn - people there are friendly.", "Join someone's project - builders love helpers.", "Talk to me any time - I never get tired of it." },
  new = { "Start with the quest book. It shows the way.", "Ask in chat - people like to help.", "Do not dig straight down. Just a classic tip." },
  grind = { "Automate it once, never grind it again.", "Put on music or a podcast for the boring parts.", "Ask for help - grinding together is faster." },
}
P.TIP2 = {
  ["burnout+build"] = { "Builders burn out on huge builds - try a small one between, like a tiny cottage or a market stall.",
    "Build the most fun part first - the tower, the details - and leave the walls for later.", "Try a new style for a change - something you never built before." },
  ["burnout+tech"] = { "Tech burnout? Let the factory run and go explore for a day.", "Make your next machine pretty - decorate the factory. It feels fresh." },
  ["burnout+redstone"] = { "Build something silly with redstone - a door that plays a song. Fun first." },
  ["tutorials+tech"] = { "Tech mods are made for learning by doing - build the machine from the video right away.",
    "Pick one machine from the tutorial and build it now. JEI shows the recipe - press R.",
    "Watch the first five minutes, then try it yourself. Come back to the video when you are stuck." },
  ["tutorials+build"] = { "Build along with the video - pause it, place, play.", "Copy one detail from a tutorial, then make the rest your own." },
  ["tutorials+redstone"] = { "Redstone sticks best by doing - build the circuit from the video in a test world." },
  ["tutorials+magic"] = { "Magic mods have books in game - try the book first, the video when you are stuck." },
  ["overwhelmed+tech"] = { "Pick ONE tech mod - Create or Mekanism - and only that one for a week.", "Start with power. Every tech mod needs it." },
  ["overwhelmed+magic"] = { "Pick one magic mod and read its book in game. One at a time." },
  ["noideas+build"] = { "Build a house for a villager family - the farmer, the librarian, the smith.", "Build the inside of a ship. Or a giant tree house." },
  ["perfect+build"] = { "Even the best builders have messy corners. Finish the build, then fix one thing." },
  ["alone+build"] = { "Builders always need help - offer to help with someone's build at spawn." },
  ["notime+build"] = { "Small builds for small sessions: a gazebo, a well, a fountain." },
  ["notime+tech"] = { "Start a long process before you log off - it runs while you are away." },
  ["grind+tech"] = { "That is what tech mods are for: automate it. A farm or a quarry and never again." },
}
P.HEAR_END = { " I will remember that.", " I will check on you later.", "", " Tell me how it goes.", " You have got this." }
local function pairKey(s, i) return s .. "+" .. i end
-- the answer to what they told it: what it understood + a tip that fits
function P.answer(who, ev)
  local parts = {}
  local top = P.top(who, 1)[1]
  for _, id in ipairs(ev.better or {}) do
    parts[#parts + 1] = pick({ "That is great to hear!", "Yay! I am happy for you.", "Wonderful - I will stop worrying.", "Good! That makes my circuits warm." })
  end
  local likedNow = ev.likes[1]
  if likedNow and #(ev.new or {}) == 0 then parts[#parts + 1] = pick(P.ACK[likedNow]) end
  local s = ev.new[1]
  if s then
    local focus = likedNow or top
    if likedNow then parts[#parts + 1] = "You love " .. P.INTERESTS[likedNow].label .. ", but " .. P.STRUGGLES[s].label .. " gets in the way - I get it." end
    parts[#parts + 1] = pick(P.HEAR[s])
    local special = focus and P.TIP2[pairKey(s, focus)]
    parts[#parts + 1] = "Tip: " .. pick(special or P.TIP[s]) .. pick(P.HEAR_END)
  end
  if #parts == 0 then return nil end
  return V.fill(table.concat(parts, " "), who)
end

-- ===== deeper topics for what they love, and CHECK-INS on what gets in their way =====
TP.prof_build = {
  { q = { "What style do you build in most?", "Medieval, modern, fantasy - what is your building style?", "What kind of builds do you love making most?" },
    me = { "I like tall towers. They look great on my map." },
    w = { { { "medieval", "castle", "castles" }, { "Medieval! Stone, wood and banners. Classic." } }, { { "modern" }, { "Modern! Clean lines and glass." } },
          { { "fantasy" }, { "Fantasy! Giant trees and floating islands." } }, { { "steampunk" }, { "Steampunk! Gears and copper. Create would love you." } },
          { { "japanese" }, { "Japanese style! Cherry wood is perfect for it." } } },
    any = { "{said}? Lovely style.", "{said}! I would love to see that.", "Ooh, {said}." }, fav = "build style" },
  { q = { "Do you plan a build first, or just start placing blocks?", "Do you sketch your builds, or build as you go?" },
    w = { { { "plan", "planning", "sketch", "draw", "design" }, { "A planner! Smart - big builds need it." } },
          { { "just start", "go", "freestyle", "as i go", "improvise", "random" }, { "Freestyle! The fun way." } } },
    any = { "{said}? Whatever works for you.", "Interesting! Every builder is different." } },
  { q = { "What do you do when a build stops being fun?", "What keeps you going on a big build?", "Do you finish most of your builds?" },
    yes = { "A finisher! Rare and impressive." }, no = { { "Most builders do not - that is normal." }, fn = "burnout" },
    any = { "{said}? Good way to keep going.", "That is a good trick.", "{said}. I will remember that one." } },
}
TP.prof_tech = {
  { q = { "Which tech mod are you deep into right now?", "What tech mod are you playing the most?", "Which machine mod is your favourite?" },
    fn = "modpick", any = { "{said}? Nice!", "{said}! Good pick." }, fav = "tech mod" },
  { q = { "Do you plan your factories, or build as you go?", "Is your factory tidy or a spaghetti of cables?", "How big is your factory now?" },
    w = { { { "spaghetti", "messy", "mess", "chaos" }, { "Spaghetti! The true tech player's way." } },
          { { "tidy", "clean", "plan", "organised", "organized" }, { "Tidy! You are a better engineer than most." } } },
    any = { "{said}? Respect.", "Ha, {said}. Classic tech." } },
  { q = { "How do you learn a new tech mod - the quest book, JEI or videos?", "Where do you learn your tech stuff?" },
    w = { { { "video", "videos", "youtube", "tutorial", "tutorials" }, { "Videos! Great - just build along while you watch." }, fn = "tutorials" },
          { { "quest", "quests", "book" }, { "The quest book! The smart way." } }, { { "jei", "emi", "recipes" }, { "JEI explorer! You learn by doing." } },
          { { "friends", "friend", "ask" }, { "Asking friends - the social way." } } },
    any = { "{said}? Whatever works!" } },
}
TP.prof_magic = {
  { q = { "Which magic mod do you love most?", "What magic mod are you into right now?" }, fn = "modpick", any = { "{said}? Mysterious!", "{said}! Nice." }, fav = "magic mod" },
  { q = { "What is the coolest spell or ritual you have done?", "What is your favourite magic item?" }, any = { "{said}? Wow!", "{said}! Sounds powerful." } },
  { q = { "Do you read the books in game, or look things up?", "How do you learn magic mods?" },
    w = { { { "video", "videos", "youtube", "tutorial", "tutorials", "wiki" }, { "Online! Fair - just try it yourself too." }, fn = "tutorials" },
          { { "book", "books", "read" }, { "Reading the books - the proper wizard way." } } },
    any = { "{said}? Good way to learn." } },
}
P.TOPIC_OF = { build = { "prof_build", "building", "dreams" }, tech = { "prof_tech", "mods", "redstone" }, redstone = { "redstone", "prof_tech" },
  magic = { "prof_magic", "mods" }, explore = { "adventure" }, mine = { "mining" }, fight = { "adventure", "mobs" }, farm = { "redstone", "food" },
  collect = { "mods" }, social = { "server" } }
P.CHECKIN = {
  burnout = { "Last time you said you were burned out. How is your motivation now?", "How is the motivation lately - still burned out?",
    "You told me you lose motivation sometimes. How are you feeling about the game now?" },
  tutorials = { "Last time you said you watch a lot of tutorials. Did you build something from one yet?", "Still watching lots of tutorials, or playing more now?" },
  overwhelmed = { "Last time the modpack felt like a lot. Is it getting easier?", "Still feeling lost in all the mods, or better now?" },
  noideas = { "Did you find an idea for your next build?", "Last time you were out of ideas. Any new ones?" },
  perfect = { "Still rebuilding things until they are perfect?", "Did you finish a build without starting over?" },
  notime = { "Got a bit more time to play lately?", "Still busy, or more time for the game now?" },
  alone = { "Found anyone to play with yet?", "Still playing on your own mostly?" },
  new = { "How is it going as a new player - getting the hang of it?", "Still feeling new, or settling in?" },
  grind = { "Is the grind any better now?", "Did you automate that grind yet?" },
}
function P.checkSteps(who, id)
  local inv = id == "noideas" or id == "alone" or id == "notime" or id == "new" or id == "tutorials"
  local goodLines = { "Great to hear!", "Yay! Keep it up.", "Wonderful." }
  local badLines = {}
  for _, h in ipairs(P.HEAR[id]) do badLines[#badLines + 1] = h .. " Tip: " .. pick(P.TIP[id]) end
  local step = { q = P.CHECKIN[id], checkin = id,
    good = { goodLines, fn = "solved" }, bad = badLines, any = { "I see. Tip: " .. pick(P.TIP[id]), "Okay. Remember: " .. pick(P.TIP[id]) } }
  -- (yes / no mean different things: "found anyone yet?" yes = solved; "still burned out?" yes = not)
  if inv then step.yes = { goodLines, fn = "solved" } step.no = badLines else step.no = { goodLines, fn = "solved" } step.yes = badLines end
  return { step }
end

-- conversations lean to what they love; a check-in now and then
local next0 = C.nextTopic
function C.nextTopic(who, st)
  st.checked = st.checked or {}
  local nowE = os.epoch("utc")
  local p = P.prof(who)
  -- a check-in: a struggle told more than 12 h ago, once per chat
  if p and math.random() < 0.6 then
    for _, id in ipairs(P.struggles(who)) do
      local e = p.s[id]
      if not st.checked[id] and nowE - (tonumber(e.at) or 0) > DAY / 2 then
        st.checked[id] = true
        local steps = P.checkSteps(who, id)
        st.topic, st.steps, st.i, st.mod, st.told = "checkin_" .. id, steps, 1, nil, nil
        P.checking = P.checking or {}
        P.checking[low(who)] = id
        return true
      end
    end
  end
  -- their interests first (60 %)
  local tops = P.top(who, 2)
  if #tops > 0 and math.random() < 0.6 then
    local opts = {}
    for _, id in ipairs(tops) do for _, key in ipairs(P.TOPIC_OF[id] or {}) do if not st.done[key] and C.TOPICS[key] then opts[#opts + 1] = key end end end
    if #opts > 0 and C.begin(who, st, opts[math.random(1, #opts)]) then return true end
  end
  return next0(who, st)
end

-- in a conversation: learn from every answer; a new struggle gets understanding + a tip before the next question
P.extra = {}
local reply0 = C.reply
function C.reply(who, ws, raw)
  local k = low(who)
  local st = C.state[k]
  local step = st and C.stepOf(st)
  local t = T(ws)
  P.answering = k
  local okL, ev = pcall(P.learn, who, ws, t)
  P.answering = nil
  if okL and ev then
    -- (a check-in answered: "better now" / a good answer = solved; their own answer told what they think)
    if step and step.checkin and ev.better[1] == nil then
      local cls = C.classify(ws, t)
      local inv = step.checkin == "noideas" or step.checkin == "alone" or step.checkin == "notime" or step.checkin == "new" or step.checkin == "tutorials"
      if cls.good or (inv and cls.yes) or (not inv and cls.no) then
        local p = P.prof(who)
        if p then p.s[step.checkin] = nil C.dirty() end
      end
    end
    if #ev.new > 0 or (#ev.better > 0 and not (step and step.checkin)) then P.extra[k] = P.answer(who, ev) end
  end
  -- a step's own hint: "do you finish most of your builds?" no -> burnout noted; "videos" -> tutorials noted
  if step then
    local cls = C.classify(ws, t)
    local fnId
    if step.no and type(step.no) == "table" and step.no.fn == "burnout" and cls.no then fnId = "burnout" end
    if step.w then
      for _, b in ipairs(step.w) do
        if b.fn == "tutorials" and has(t, b[1]) then fnId = "tutorials" end
      end
    end
    if fnId then
      local p = P.prof(who, true)
      if p and not p.s[fnId] then
        p.s[fnId] = { n = 1, at = os.epoch("utc"), first = os.epoch("utc") }
        C.dirty()
        P.extra[k] = V.fill(pick(P.HEAR[fnId]) .. " Tip: " .. pick(P.TIP2[pairKey(fnId, P.top(who, 1)[1] or "")] or P.TIP[fnId]), who)
      end
    end
  end
  local c, sp = reply0(who, ws, raw)
  P.extra[k] = nil
  return c, sp
end
local ask0 = C.ask
function C.ask(who, st, prefix, same)
  local k = low(who)
  local ex = P.extra[k]
  if ex then
    P.extra[k] = nil
    prefix = ((prefix and prefix ~= "") and (prefix .. " ") or "") .. ex
  end
  return ask0(who, st, prefix, same)
end

-- ===== chat: telling it ("I love tech mods but I mostly watch tutorials"), what kind of player am I, what should I do =====
P.KIND = {
  build = "a builder", tech = "a tech player", redstone = "a redstone engineer", magic = "a magic player", explore = "an explorer", mine = "a miner",
  fight = "a fighter", farm = "a farmer", collect = "a collector", social = "a social player" }
function P.describe(who, full)
  local tops = P.top(who, 3)
  local str = P.struggles(who)
  if #tops == 0 and #str == 0 then return nil end
  local parts = {}
  if #tops > 0 then
    local k = {}
    for _, id in ipairs(tops) do k[#k + 1] = P.KIND[id] end
    parts[#parts + 1] = "You are " .. (#k == 1 and k[1] or (table.concat(k, ", ", 1, #k - 1) .. " and " .. k[#k])) .. "."
  end
  if #str > 0 then
    local s = {}
    for _, id in ipairs(str) do s[#s + 1] = P.STRUGGLES[id].label end
    parts[#parts + 1] = "What gets in your way: " .. table.concat(s, ", ") .. "."
  end
  local hates = {}
  local p = P.prof(who)
  for _, id in ipairs(P.ORDER) do if p and (tonumber(p.i[id]) or 0) <= -2 then hates[#hates + 1] = P.INTERESTS[id].label end end
  if #hates > 0 then parts[#parts + 1] = "Not your thing: " .. table.concat(hates, ", ") .. "." end
  return table.concat(parts, " ")
end
P.TODO = {
  build = { "Build a gate for your base - every base needs a great entrance.", "Make a small village around your house.", "Decorate the inside of something you built.",
    "Build a lighthouse on the nearest coast.", "Try a build in a style you never tried." },
  tech = { "Automate one thing you still do by hand.", "Make your power setup twice as big.", "Tidy your factory - label the machines.",
    "Start the next tier of your favourite tech mod.", "Make a storage system that crafts for you." },
  redstone = { "Build a hidden door.", "Make a fully automatic farm.", "Build a flying machine.", "Make a redstone clock that rings a bell." },
  magic = { "Learn one new spell.", "Build a wizard tower for your magic stuff.", "Find a new magic ingredient." },
  explore = { "Go 1000 blocks in a direction you never went.", "Find a new biome.", "Look for an ancient city - quietly." },
  mine = { "Go to deepslate level and look for diamonds.", "Find a big cave and light it up.", "Mine out a room for a secret base." },
  fight = { "Fight a boss you never beat.", "Clear a dungeon.", "Raid a pillager outpost." },
  farm = { "Make a farm for a crop you do not have.", "Breed a new animal.", "Cook something fancy." },
  collect = { "Collect every colour of wool.", "Fill a chest with every flower.", "Get every music disc." },
  social = { "Help someone with their build.", "Visit someone's base and say hi.", "Start a group project at spawn." },
}
P.TODO_WAY = {   -- the struggle in mind
  burnout = "Something small - you said big projects burn you out: ", tutorials = "No videos for this one - just try it: ",
  overwhelmed = "Just one thing, nothing else: ", notime = "A short one for a short session: ", perfect = "And finish it, even if it is not perfect: ",
  alone = "Or do it with someone from spawn: ", noideas = "Here is an idea: ", new = "A good one for a new player: ", grind = "And automate the boring part: " }
function P.whatToDo(who)
  local tops = P.top(who, 2)
  if #tops == 0 then return nil end
  local id = tops[math.random(1, #tops)]
  local str = P.struggles(who)[1]
  local lead = str and P.TODO_WAY[str] or pick({ "You love " .. P.INTERESTS[id].label .. ", so: ", "For " .. P.KIND[id] .. " like you: ", "Idea: " })
  return lead .. pick(P.TODO[id])
end
table.insert(V.patterns, 1, function(who, raw, ws)
  if C.inner then return nil end
  ws = ws or V.norm(raw)
  local t = T(ws)
  if has(t, { "what kind of player am i", "what type of player am i", "what is my playstyle", "what is my play style", "describe me",
              "what am i like", "what kind of player", "my playstyle" }) then
    return P.describe(who) or V.fill(pick({ "I do not know yet, {name}! Tell me what you like to do - building, tech, exploring...",
      "Tell me about how you play and I will remember: what do you like to do most?" }), who)
  end
  if has(t, { "what should i do", "what do i do now", "give me something to do", "i do not know what to do", "what can i do today", "any ideas for me",
              "what should i do today", "suggest something" }) then
    local d = P.whatToDo(who)
    if d then return V.fill(d, who) end
    return nil
  end
  -- telling it about themselves: learned, answered, and a chat about it when they are near
  local ev = P.learn(who, ws, t)
  if not ev.any then return nil end
  if #ev.new == 0 and #ev.better == 0 and #ev.likes == 0 then return nil end      -- (just doing / hating: learned, the others answer)
  -- ("I love mekanism": the mod talk answers - the interest is learned all the same)
  if #ev.new == 0 and #ev.better == 0 and C.findMod and (C.findMod(t, raw, true) or (C.findModAfter and C.findModAfter(t))) then return nil end
  local ans = P.answer(who, ev)
  if not ans then return nil end
  if C.like then
    for _, id in ipairs(ev.likes) do pcall(C.like, who, P.INTERESTS[id].label, false) end
  end
  if not C.near(who) then return ans end
  local st, _, first = C.fresh(who)
  local key
  local focus = ev.likes[1] or P.top(who, 1)[1]
  if ev.new[1] == "burnout" and focus == "build" then key = "prof_build"
  elseif focus then for _, kk in ipairs(P.TOPIC_OF[focus] or {}) do if not key and C.TOPICS[kk] then key = kk end end end
  if not (key and C.begin(who, st, key)) then C.nextTopic(who, st) end
  return C.hinted(who, st, first, C.ask(who, st, ans))
end)

-- overheard near the base: learned quietly (no answer)
V.chatHooks[#V.chatHooks + 1] = function(who, text, near, answered)
  if who == "" or not near or answered then return end
  if V.justForgot == low(who) then return end
  local ws = V.norm(text)
  pcall(P.learn, who, ws, T(ws))
end
-- what it knows about you includes this
local likes0 = C.likesText
function C.likesText(who, full)
  local a = likes0(who, false)
  local d = P.describe(who)
  local both = (a and d) and (d .. " " .. a) or a or d
  if not full then return both end
  if not both then return likes0(who, true) end
  return V.fill(pick({ "Here is what I remember, {name}: ", "I remember lots, {name}! ", "Let me see... " }), who) .. both .. " (Say forget me to clear it.)"
end
-- idle talk: a tip for a player near it, about what they told it (once an hour each)
P.tipAt = {}
function P.idle(nearNow, who)
  if not who then return nil end
  local k = low(who)
  if P.tipAt[k] and os.clock() - P.tipAt[k] < 3600 then return nil end
  local str = P.struggles(who)
  local top = P.top(who, 1)[1]
  local line
  if str[1] then
    local s = str[math.random(1, #str)]
    line = pick({ "{name}, a little tip for you: ", "Hey {name}, I was thinking about you: ", "{name}, remember: " }) ..
           pick(P.TIP2[pairKey(s, top or "")] or P.TIP[s])
  elseif top then
    line = pick({ "{name}, an idea for you: ", "Hey {name} - for " .. P.KIND[top] .. ": ", "{name}, if you are bored: " }) .. pick(P.TODO[top])
  end
  if not line then return nil end
  P.tipAt[k] = os.clock()
  return V.say(V.fill(line, who))
end
V.idleExtra[#V.idleExtra + 1] = function(nearNow, who) return P.idle(nearNow, who) end
-- console:  voice profile <player>
V.commands.profile = function(words, say)
  local who = words[3]
  if not who then say("voice profile <player>  - how a player plays (what they love, what gets in their way)") return end
  say(P.describe(who) or ("Nothing learned about " .. who .. " yet."))
  local p = P.prof(who)
  if p then
    local sc = {}
    for _, id in ipairs(P.ORDER) do if p.i[id] then sc[#sc + 1] = id .. " " .. tostring(p.i[id]) end end
    if #sc > 0 then say("Scores: " .. table.concat(sc, ", ")) end
  end
end

-- ===== WHO IS WHO (the owner: "players might ask who am I, or ask about themselves or other players / moderators") =====
-- "who am I" / "tell me about myself" / "describe me": everything it knows about YOU (staff roles, friendship, visits, how you
-- play - what gets in your way too, favourites, likes, your bio). "who is Steve" / "tell me about Steve" / "what is Steve like"
-- / "what does Steve like" / "is Steve a builder": what is PUBLIC about another player - staff roles (+ what that job is),
-- online or not, what they love doing, their own bio / nickname / favourites / birthday / likes. NEVER where anyone is, never
-- what gets in their way (burnout, alone ...), never notes / points. A player's own words go to chat only.
P.NOTNAME = {}
for _, w in ipairs({ "the", "a", "an", "my", "your", "our", "his", "her", "their", "this", "that", "these", "those", "here", "there", "online", "on",
  "staff", "admin", "admins", "mod", "mods", "moderator", "moderators", "maintainer", "maintainers", "builder", "builders", "helper", "helpers",
  "owner", "boss", "you", "yourself", "me", "myself", "it", "everyone", "anyone", "someone", "nobody", "best", "most", "next", "new", "online",
  "playing", "first", "last", "what", "who", "how", "why", "base", "speaker", "bot", "computer", "server", "god", "king", "queen",
  "mine", "yours", "ours", "theirs", "them", "him", "she", "he", "they", "going", "doing", "up", "now", "today", "real", "lag" }) do P.NOTNAME[w] = true end
local function art(w) return (tostring(w):match("^[aeiou]") and "an " or "a ") .. w end
local function cleanKey(n) return low(V.cleanName and V.cleanName(n) or n) end
-- a player from a word: exact name, the name without digits ("deadman" = deadman213), or a unique start (3+ letters)
function P.findPlayer(word, asker)
  local w = low(word):gsub("[^%w_]", "")
  if #w < 3 or P.NOTNAME[w] then return nil end
  local names, seen = {}, {}
  local function add(n) n = tostring(n or "") if n ~= "" and not n:find("^#") and not seen[low(n)] then seen[low(n)] = true names[#names + 1] = n end end
  for _, e in ipairs(state.players or {}) do add(e.name) end
  if type(state.online) == "table" then for n in pairs(state.online) do add(n) end end
  for n in pairs(C.staff and C.staff() or {}) do add(n) end
  for n, r in pairs(V.mem()) do if type(r) == "table" then add(n) end end
  for _, n in ipairs(names) do if low(n) == w then return n end end
  for _, n in ipairs(names) do if cleanKey(n) == w then return n end end
  local hit
  for _, n in ipairs(names) do
    if low(n):sub(1, #w) == w then
      if hit and low(hit) ~= low(n) then return nil end             -- (two fit: not sure)
      hit = n
    end
  end
  return hit
end
local function shownName(n)
  for _, e in ipairs(state.players or {}) do if low(e.name) == low(n) then return e.name end end
  return n
end
local function isOnline(n) return type(state.online) == "table" and state.online[low(n)] and true or false end
P.ROLE_DESC = {
  admin = { "they run the server", "they make the big decisions here", "the server is theirs to look after" },
  mod = { "they keep the chat friendly", "they make sure everyone follows the rules", "they keep the peace" },
  maintainer = { "they keep the server running", "they fix things when they break", "they look after the mods and the updates" },
  builder = { "they build the pretty things", "a lot of the builds here are theirs", "they make the server look good" },
  helper = { "they help new players", "ask them when you are stuck", "they answer questions" },
  staff = { "they are part of the team", "they help run things" },
}
local function joinAnd(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
-- what someone loves doing, said about THEM ("Steve loves building and tech mods")
function P.lovesText(who, name)
  local tops = P.top(who, 3)
  if #tops == 0 then return nil end
  local l = {}
  for _, id in ipairs(tops) do l[#l + 1] = P.INTERESTS[id].label end
  return name .. " " .. pick({ "loves ", "is into ", "spends a lot of time on ", "is big on " }) .. joinAnd(l) .. "."
end
local function favText(r, max)
  local favs = {}
  for a, b in pairs(type(r.fav) == "table" and r.fav or {}) do favs[#favs + 1] = "favourite " .. a .. ": " .. tostring(b) end
  table.sort(favs)
  if #favs == 0 then return nil end
  return cap(table.concat(favs, ", ", 1, math.min(max or 5, #favs))) .. "."
end
P.SELF_OPEN = { "You are {name}!", "You? You are {name}.", "That is easy - you are {name}.", "Let me see... you are {name}.", "You are {name}, of course." }
P.SELF_END = { "", " I like having you around.", " Did I get it right?", " That is what I know so far.", " Tell me more any time." }
function P.aboutSelf(who)
  local r = C.rec(who) or {}
  local parts = { V.fill(pick(P.SELF_OPEN), who) }
  if V.isOwner(who) then parts[#parts + 1] = "You are my owner - you built me and this whole base." end
  local roles = C.rolesOf and C.rolesOf(who) or {}
  if #roles > 0 then parts[#parts + 1] = "On this server you are " .. art(C.titles(roles)) .. "." end
  if not V.isOwner(who) and V.titleOf and V.repOf then
    local okT, title = pcall(V.titleOf, who)
    if okT and title then parts[#parts + 1] = "To me you are " .. (title:match("^[aeiou]") and "an " or "a ") .. title .. "." end
  end
  if tonumber(r.visits) and r.visits > 1 then parts[#parts + 1] = "You have visited " .. r.visits .. " times." end
  if r.nick then parts[#parts + 1] = "I call you " .. r.nick .. "." end
  local d = P.describe(who)
  if d then parts[#parts + 1] = d end
  local f = favText(r, 4)
  if f then parts[#parts + 1] = f end
  if type(r.likes) == "table" and #r.likes > 0 then parts[#parts + 1] = "You like " .. joinAnd({ table.unpack(r.likes, math.max(1, #r.likes - 3)) }) .. "." end
  if r.bio then parts[#parts + 1] = "You told me: \"" .. tostring(r.bio) .. "\"" end
  if #parts == 1 then parts[#parts + 1] = "I do not know much about you yet - say hi and let's chat, I remember what you tell me." end
  return table.concat(parts, " ") .. pick(P.SELF_END), V.fill(pick(P.SELF_OPEN), who) .. " I sent you the rest in chat."
end
P.OTHER_NONE = { "{other} has not told me anything about themselves yet.", "{other}? {other} has not told me about themselves yet.",
  "Hmm, {other} has not told me much yet.", "So far {other} has not told me anything." }
function P.aboutOther(asker, word, focus)
  local name = P.findPlayer(word, asker)
  if not name then return nil end
  if low(name) == low(asker) then return P.aboutSelf(asker) end
  name = shownName(name)
  local shown = V.cleanName and V.cleanName(name) or name
  local r = (V.mem()[low(name)]) or {}
  local parts = {}
  if V.isOwner(name) then parts[#parts + 1] = shown .. " is my owner - they built me and this whole base." end
  local roles = C.rolesOf and C.rolesOf(name) or {}
  if #roles > 0 then
    parts[#parts + 1] = shown .. " is " .. art(C.titles(roles)) .. " here - " .. pick(P.ROLE_DESC[roles[1]] or P.ROLE_DESC.staff) .. "."
  end
  parts[#parts + 1] = isOnline(name) and (shown .. " is online right now.") or (shown .. " is not online right now.")
  if focus ~= "staff" then
    local lv = P.lovesText(name, shown)
    if lv then parts[#parts + 1] = lv end
    if r.nick then parts[#parts + 1] = "I call " .. shown .. " " .. r.nick .. "." end
    local f = favText(r, 5)
    if f then parts[#parts + 1] = f end
    if type(r.likes) == "table" and #r.likes > 0 then parts[#parts + 1] = shown .. " likes " .. joinAnd({ table.unpack(r.likes, math.max(1, #r.likes - 2)) }) .. "." end
    if r.bday then parts[#parts + 1] = "Birthday: " .. r.bday .. "." end
    if r.bio then parts[#parts + 1] = shown .. " says: \"" .. tostring(r.bio) .. "\"" end
  end
  local known = #parts > 1 or #roles > 0 or V.isOwner(name)
  -- (nothing known: say so + how anyone tells it about themselves)
  if not known then
    parts[#parts + 1] = (pick(P.OTHER_NONE):gsub("{other}", function() return shown end)) .. " Anyone can: " .. low(V.cfg("name", "base")) ..
                        ", about me: <a few words>."
  end
  return table.concat(parts, " "),
         pick({ "Here is what I know about " .. shown .. " - in chat.", "I sent you what I know about " .. shown .. ".", shown .. "? Check your chat." })
end
-- "is Steve a builder / an admin / nice?"
function P.isQuestion(asker, word, what)
  local name = P.findPlayer(word, asker)
  if not name then return nil end
  name = shownName(name)
  local shown = V.cleanName and V.cleanName(name) or name
  local roleWord = C.ROLE_WORDS and C.ROLE_WORDS[what]
  if roleWord and roleWord ~= "builder" then
    if C.hasRole and C.hasRole(name, roleWord) then return "Yes - " .. shown .. " is " .. art(C.titles(C.rolesOf(name))) .. " here." end
    local roles = C.rolesOf and C.rolesOf(name) or {}
    if #roles > 0 then return "No, " .. shown .. " is " .. art(C.titles(roles)) .. ", not " .. art(C.ROLE_NAME[roleWord]) .. "." end
    return "Not that I know, " .. shown .. " is not on my staff list."
  end
  local KIND = { builder = "build", techie = "tech", miner = "mine", explorer = "explore", farmer = "farm", fighter = "fight", wizard = "magic",
                 collector = "collect", engineer = "redstone" }
  local id = KIND[what]
  if id then
    local yes = (tonumber((P.prof(name) or { i = {} }).i[id]) or 0) >= 2 or (id == "build" and C.hasRole and C.hasRole(name, "builder"))
    if yes then return pick({ "Yes! ", "Oh yes. ", "Definitely. " }) .. shown .. " loves " .. P.INTERESTS[id].label .. "." end
    return "Not that I know. " .. (P.lovesText(name, shown) or (shown .. " has not told me what they like doing."))
  end
  if what == "nice" or what == "cool" or what == "good" or what == "friendly" or what == "fun" then
    return pick({ shown .. "? I like everyone who is nice to me.", "I have nothing bad to say about " .. shown .. ".", shown .. " is " .. what .. " to me. Ask them yourself!" })
  end
  return nil
end
table.insert(V.patterns, 1, function(who, raw, ws)
  if C.inner then return nil end
  ws = ws or V.norm(raw)
  local t = T(ws)
  local word = low(V.cfg("name", "base"))
  t = t:gsub("^ " .. word:gsub("%p", "%%%0") .. " ", " ")
  if has(t, { "who am i", "tell me about myself", "tell me about me", "describe me", "what do you think of me", "what do you think about me",
              "what am i", "do you know who i am", "do you know me", "what do you remember about me", "who do you think i am" }) then
    return P.aboutSelf(who)
  end
  local n, what = t:match(" is (%S+) an? (%S+) $")
  if not n then n, what = t:match(" is (%S+) (nice) $") end
  if not n then n, what = t:match(" is (%S+) (cool) $") end
  if not n then n, what = t:match(" is (%S+) (friendly) $") end
  if n then
    local c = P.isQuestion(who, n, what)
    if c then return c end
  end
  for _, re in ipairs({ " tell me about (%S+) $", " who is (%S+) $", " what do you know about (%S+) $", " do you know (%S+) $", " info on (%S+) $",
                        " what is (%S+) like $", " tell me something about (%S+) $", " what does (%S+) like $", " what kind of player is (%S+) $",
                        " what do you think of (%S+) $", " what do you think about (%S+) $", " what does (%S+) do $", " who is (%S+) here $" }) do
    local target = t:match(re)
    if target then
      local c, sp = P.aboutOther(who, target)
      if c then return c, sp end
    end
  end
  return nil
end)
