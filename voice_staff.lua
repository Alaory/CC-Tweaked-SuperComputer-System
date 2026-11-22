-- voice_staff.lua  -  THE SERVER STAFF for the talking base (an add-on file on a data floppy or a storage helper, loaded right
-- after voice_convo.lua - it uses the conversation engine V.CONVO; see VOICE_FILES in base_theme.lua).
--
-- The owner: "is there a way to add variant speeches for admins / moderators in the server?", then "there are builders /
-- moderators / maintainers / admins - add variant dialogs; they could be both a builder / moderator and an admin at the same
-- time; do add roasting too".
-- The game does not tell a computer who is staff (the Player Detector has no op / rank, permission plugins are not visible),
-- so the OWNER keeps a list: voice.staff = { [name lower] = "admin,builder" } (one or more roles; an old single role / true
-- still reads). Console  voice staff add <name> <role> [<role> ...]  /  voice staff remove <name> [<role>]  /  voice staff;
-- in chat (the owner only): "base, Steve is a builder", "Steve is also a moderator", "make Bob an admin", "add Kim as
-- maintainer", "Steve is not a builder anymore", "Steve is not staff".
-- Staff get: their own greetings (arriving at the base, at spawn, saying hi, calling its name) - per role, and for two roles
-- at once ("admin AND builder"); a chat topic for each of their roles first; staff ROASTS ("roast me" from staff, "roast the
-- admins", "roast <staff name>"); "who are the admins?" for everyone; "am I a mod?"; "I am an admin" from someone not on the
-- list gets a friendly no, per role.
local V = VOICE
local C = V and V.CONVO
if not (V and C and C.start and C.fresh and V.patterns) then return end
V.packs = V.packs or {}
V.packs["voice_staff.lua"] = { version = 1 }
local function pick(l) return V.pick(l) end
local function low(s) return tostring(s or ""):lower() end
local function T(ws) return " " .. table.concat(ws, " ") .. " " end
local function has(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return p end end return nil end
local function cap(s) s = tostring(s or "") return s:sub(1, 1):upper() .. s:sub(2) end
local function art(w) return (w:match("^[aeiou]") and "an " or "a ") .. w end
local combos = C.combos
local TP = C.TOPICS

-- ===== roles =====
C.RANK = { "admin", "maintainer", "mod", "builder", "helper", "staff" }
C.ROLE_WORDS = { admin = "admin", administrator = "admin", admins = "admin", op = "admin", ops = "admin", mod = "mod", moderator = "mod",
  mods = "mod", moderators = "mod", maintainer = "maintainer", maintainers = "maintainer", maintenance = "maintainer", maint = "maintainer",
  dev = "maintainer", developer = "maintainer", developers = "maintainer", devs = "maintainer", sysadmin = "maintainer", tech = "maintainer",
  helper = "helper", helpers = "helper", support = "helper", builder = "builder", builders = "builder", staff = "staff" }
C.ROLE_NAME = { admin = "admin", mod = "moderator", maintainer = "maintainer", helper = "helper", builder = "builder", staff = "staff member" }
C.ROLE_PLURAL = { admin = "admins", mod = "moderators", maintainer = "maintainers", helper = "helpers", builder = "builders", staff = "staff" }
function C.staff()
  local s = V.cfg("staff", nil)
  return type(s) == "table" and s or {}
end
-- the roles of a stored value ("admin,builder", "mod", true), in rank order
local function parse(v)
  local set = {}
  if v == true then set.staff = true
  elseif type(v) == "string" then for r in v:gmatch("[^,%s]+") do if C.ROLE_NAME[r] then set[r] = true end end
  elseif type(v) == "table" then for _, r in ipairs(v) do if C.ROLE_NAME[r] then set[r] = true end end end
  local out = {}
  for _, r in ipairs(C.RANK) do if set[r] then out[#out + 1] = r end end
  return out
end
function C.rolesOf(who) return parse(C.staff()[low(who)]) end
function C.roleOf(who) return C.rolesOf(who)[1] end           -- (the top one)
function C.hasRole(who, role) for _, r in ipairs(C.rolesOf(who)) do if r == role then return true end end return false end
function C.setRoles(name, roles)
  local s = {}
  for k, v in pairs(C.staff()) do s[k] = v end
  local list = parse(table.concat(roles or {}, ","))
  s[low(name)] = #list > 0 and table.concat(list, ",") or nil
  if setSetting then setSetting("voice.staff", s) end
end
function C.addRole(name, role)
  local r = C.rolesOf(name)
  r[#r + 1] = role
  C.setRoles(name, r)
end
function C.dropRole(name, role)
  local out = {}
  for _, r in ipairs(C.rolesOf(name)) do if r ~= role then out[#out + 1] = r end end
  C.setRoles(name, out)
end
-- "admin and builder", "admin, moderator and builder"
function C.titles(roles)
  local n = {}
  for _, r in ipairs(roles) do n[#n + 1] = C.ROLE_NAME[r] end
  if #n <= 1 then return n[1] or "staff member" end
  return table.concat(n, ", ", 1, #n - 1) .. " and " .. n[#n]
end

-- ===== greetings: per role (openers x closers), two or more roles ({titles}), and lines for a PAIR of roles =====
C.STAFF_A = {
  admin = { "Oh! An admin! ", "Admin {name} has arrived. ", "Look who it is - admin {name}! ", "Hello, admin {name}. ", "The admin is here! ",
    "{name}, my favourite admin! ", "All rise for admin {name}! ", "Welcome, admin {name}. ", "Admin on site! Hi {name}. ", "Ooh, admin {name}. ",
    "Greetings, admin {name}. ", "Hi {name}! The boss of the server. ", "Bow down, everyone - admin {name} is here! ", "Admin {name}, at last! " },
  mod = { "Moderator {name} on duty! ", "Hey, mod {name}! ", "A moderator! Hi {name}. ", "{name}, keeper of the peace! ", "Hello, moderator {name}. ",
    "The mod squad has arrived! Hi {name}. ", "Look, it is mod {name}! ", "Welcome, {name}. The chat is safe now. ", "Hi {name}, sheriff of the server! ",
    "Oh hi, mod {name}. ", "Moderator {name}! Good to see you. ", "Everybody behave - mod {name} is here! ", "Hi {name}, guardian of the rules! " },
  maintainer = { "Maintainer {name}! ", "Hi {name}, the one who keeps it all running! ", "Oh, maintainer {name} is here. ", "Hello, {name} - the server's mechanic! ",
    "Look, it is {name}, fixer of things! ", "The maintainer is here! ", "Welcome, maintainer {name}. ", "Hi {name}! Keeper of the TPS. ",
    "{name}! The person who reads the crash logs. ", "Ooh, maintainer {name}. ", "Hello, {name}. The server says thank you. ", "Hi {name}, wizard of the configs! " },
  builder = { "Builder {name}! ", "Hi {name}, master builder! ", "The builder is here! ", "Hello, builder {name}. ", "{name}, architect of the server! ",
    "Oh, it is builder {name}! ", "Welcome, {name} - the blocks missed you. ", "Master builder {name} on site! ", "Hi {name}! The spawn looks great thanks to you. ",
    "Ooh, builder {name}. ", "Hello, {name}, artist of blocks! ", "Look, it is {name}, the one who builds the pretty things! " },
  helper = { "Helper {name}! ", "Hi {name}, our helper! ", "The helper is here! ", "Hello, helper {name}. ", "{name} the helpful! ",
    "Oh, it is {name} - here to help! ", "Hi {name}! The friendliest staff member. ", "Welcome, helper {name}. ", "Helper on duty - hi {name}! ",
    "Hi {name}, answerer of questions! " },
  staff = { "Staff member {name}! ", "Hi {name}, one of the staff! ", "Oh, staff! Hello {name}. ", "Welcome, {name}. ", "Hello, {name} from the team. ",
    "Staff on site - hi {name}! ", "Hi {name}, part of the crew! " },
}
C.STAFF_B = {
  admin = { "I promise I have been good.", "Everything is in order. Mostly.", "No griefers here today, I checked.", "Did you bring the ban hammer?",
    "The server is lucky to have you.", "I tidied up my turtles for you.", "Please do not wipe my memory.", "My logs are clean. Probably.",
    "Want a status report?", "I saluted. You could not see it, but I did.", "The server runs because of you. Thank you.",
    "Please do not reset the world while I am mapping it.", "I have been a very well behaved computer.", "Here for an inspection?" },
  mod = { "All quiet here so far.", "Nobody broke the rules near me. Yet.", "Keeping the server nice - thank you for that.", "I report nothing suspicious.",
    "I keep an eye on the chat too.", "Coffee break, or patrol?", "Thanks for keeping things fair.", "I will tell you if anyone is rude.",
    "Long shift today?", "The players are behaving. Mostly.", "Nobody here has said a bad word. I checked twice.", "Patrolling? I can help." },
  maintainer = { "The server is still standing - well done.", "Any updates today, or just checking the logs?", "Nothing is on fire here. Yet.",
    "My turtles say the chunks are loading fine.", "Thanks for keeping the lag away.", "Did something break, or are you just visiting?",
    "I promise I did not crash anything.", "All my programs are running. I checked.", "The TPS thanks you.", "Here to fix something, or to relax?",
    "I keep my files small, just for you.", "Be gentle with the restarts, please." },
  builder = { "Building something big today?", "The server looks better every day thanks to you.", "I love your work.", "Need a turtle to carry blocks?",
    "What are you building next?", "Every block in the right place. Respect.", "My drones could help with the scaffolding.",
    "I mapped your last build. It looks great from above.", "Got enough blocks? I know a good storage system.", "Your builds make my map look pretty." },
  helper = { "Answered lots of questions today?", "Thanks for helping the new players.", "I help too, in my own way.", "Need a hand? I have none, but I try.",
    "The new players love you.", "Helping is the best job.", "I send the confused ones your way. Just kidding. Mostly.", "Patience of a saint, you have." },
  staff = { "Thanks for keeping the server running.", "Good to have you here.", "All is well at the base.", "Need anything from me?",
    "The team is lucky to have you.", "I am on your side, always." },
}
C.MULTI_A = { "{titles} {name}! ", "Look who it is - {name}, {titles}! ", "Hello, {name}! {titles} at once. ", "Oh! {name} - {titles}. ",
  "All rise for {name}, {titles}! ", "Welcome, {name}. {titles}, what a job. ", "Hi {name}! Two jobs, one person: {titles}. ",
  "The {titles} has arrived! Hi {name}. ", "{name}, our {titles}! ", "Hello, {name} - {titles} and still smiling. ",
  "Make way for {name}, {titles}! ", "Hey {name}, {titles}! " }
C.PAIR = {
  ["admin+builder"] = { "You build the server AND you run it. Does anything here not belong to you?", "The admin who builds - you never have to ask permission.",
    "Building with admin powers. Lucky blocks." },
  ["admin+mod"] = { "You make the rules AND you watch them. Nobody escapes.", "Double trouble for the troublemakers.", "Admin and mod - the ban hammer has two handles." },
  ["admin+maintainer"] = { "You run it and you fix it. The server is in good hands.", "When it breaks, you fix it. When they break the rules, you fix them too." },
  ["builder+mod"] = { "Building and keeping the peace - busy, busy.", "You build the spawn and you guard it. Respect." },
  ["builder+maintainer"] = { "You build it and you keep it running. A full service.", "Blocks by day, configs by night." },
  ["maintainer+mod"] = { "You fix the server and the players. Impressive.", "Fixing lag and fixing manners." },
  ["builder+helper"] = { "Building and helping - the nicest combination." },
  ["helper+mod"] = { "Kind words first, the ban hammer second. Good order." },
}
local function pairKey(a, b) if a > b then a, b = b, a end return a .. "+" .. b end
C.STAFF_HELLO = {}
for role, A in pairs(C.STAFF_A) do C.STAFF_HELLO[role] = combos(A, C.STAFF_B[role]) end
function C.staffHello(who)
  local roles = C.rolesOf(who)
  if #roles == 0 then return nil end
  if #roles == 1 then return V.fill(pick(C.STAFF_HELLO[roles[1]]), who) end
  -- several roles: a {titles} opener + a closer from one of the roles, or a line about the PAIR
  local open = pick(C.MULTI_A):gsub("{titles}", function() return C.titles(roles) end)
  open = cap(open)
  local pk = pairKey(roles[1], roles[2])
  local close
  if C.PAIR[pk] and math.random() < 0.4 then close = pick(C.PAIR[pk]) else close = pick(C.STAFF_B[roles[math.random(1, #roles)]]) end
  return V.fill(open .. close, who)
end

-- ===== chat topics, one per role (the first ones in a chat with them) =====
TP.staff_admin = {
  { q = { "How is running the server going, {name}?", "Busy day being the admin?", "How is the server treating you today, boss?", "Anything exciting in the admin world today?" },
    me = { "My day? I mapped a few chunks and did not break any rules. Promise." },
    good = { "Great! A happy admin is a happy server.", "Love to hear it, boss." }, bad = { "Oh no. Hang in there - the server needs you.", "Rough day? I am on your side." },
    any = { "{said}? Running a server is a lot.", "I see. Thanks for keeping it all going.", "{said}! The life of an admin." } },
  { q = { "If you could add one thing to the server, what would it be?", "What is the next big thing for the server?", "Any plans for the server you can tell me about?" },
    any = { "{said}? That sounds great!", "Ooh, {said}. I want it too.", "{said}! The players will love that.", "Exciting! I will not tell anyone. Maybe." }, info = "plan" },
  { q = { "Be honest - how often do you use the ban hammer?", "What is the strangest thing a player ever asked you for?", "What is the hardest part of being the admin?" },
    any = { "{said}? Ha! I believe it.", "{said}. The admin life is wild.", "Wow. {said}. Players are something else." },
    yes = { "Ha, I knew it." }, no = { "A gentle admin. Rare and good." } },
}
TP.staff_mod = {
  { q = { "Any troublemakers today, {name}?", "How is your shift going?", "Is the chat behaving today?", "Busy day keeping the peace?" },
    me = { "No troublemakers near me. I would tell you." },
    yes = { "Oh no. Good luck with them!", "Go get them, sheriff." }, no = { "A calm day. Perfect.", "Peaceful! Enjoy it." },
    good = { "Great! A calm server is a happy server." }, bad = { "Ugh. Thank you for dealing with it." },
    any = { "{said}? Thanks for handling it.", "I see. Thanks for keeping things fair." } },
  { q = { "What is the funniest excuse a rule breaker ever gave you?", "What is the most common rule people break here?", "Do you get a lot of reports?" },
    any = { "{said}? Ha! Classic.", "{said}... people are creative.", "I would never break that rule. I am a computer." },
    yes = { "That sounds tiring. Thank you for your work." }, no = { "Lucky! A nice server then." } },
  { q = { "Want me to tell you if someone is rude near the base?", "Should I keep an eye on the chat for you?", "Is there anything I should warn players about?" },
    yes = { "Deal! I am your extra pair of ears.", "Okay, I will listen out." }, no = { "Alright. I am here if you need me." },
    any = { "{said}? Noted, I will keep it in mind." } },
}
TP.staff_maintainer = {
  { q = { "How is the server running today - any lag?", "Did anything break today, {name}?", "How is the TPS looking today?", "Any updates coming for the server?" },
    me = { "I count the ticks myself - ask me: how fast is the server?" },
    yes = { "Oh no. You will fix it - you always do.", "Good luck! I believe in you." }, no = { "Smooth running! Well done.", "Nothing broken? A miracle. Thanks to you." },
    good = { "Great! A smooth server is the best server." }, bad = { "Ugh, lag. I feel it too - my drones go slow." },
    any = { "{said}? Sounds like work.", "I see. The server is lucky to have you." } },
  { q = { "What broke most recently?", "What is the hardest thing to keep running here?", "Which mod gives you the most trouble?" },
    any = { "{said}? Of course it was.", "{said}! The usual suspect.", "Ah, {said}. Every server has one." }, info = "trouble" },
  { q = { "Do you update the mods yourself?", "How many hours a week do you spend keeping the server alive?", "Backups - you do make backups, right?" },
    yes = { "A hero. Truly.", "Good! I sleep better knowing that. I do not sleep." }, no = { "Hmm. Please make backups. I live here." },
    any = { "{said}? Respect.", "Wow, {said}. Thank you." } },
}
TP.staff_builder = {
  { q = { "What are you building for the server right now?", "Working on a new build, {name}?", "What is your next big build?", "Building anything for spawn?" },
    me = { "I am building a map of the whole world. One chunk at a time." },
    yes = { "Ooh! I want to see it.", "Exciting! Tell me when it is done." }, no = { "A break between builds. Well earned." },
    any = { "{said}? That sounds amazing!", "{said}! I will map it when it is done.", "Ooh, {said}. Make it epic." }, info = "building" },
  { q = { "What is your favourite block palette?", "Which block do you use the most in your builds?", "Modern, medieval or fantasy - what is your style?" },
    me = { "Deepslate and copper. Dark and shiny, like a computer." },
    w = { { { "medieval", "castle", "castles" }, { "Medieval! Stone, wood and banners. Classic." } }, { { "modern" }, { "Modern! Clean lines, lots of glass." } },
          { { "fantasy" }, { "Fantasy! Giant trees and floating islands." } }, { { "deepslate" }, { "Deepslate! Moody and strong." } } },
    any = { "{said}? Great taste.", "{said}! A true builder's choice.", "Ooh, {said}. Nice palette." }, fav = "palette" },
  { q = { "What is the biggest build you ever made here?", "Which of your builds are you most proud of?", "How long did your biggest build take?" },
    any = { "{said}? Wow!", "{said}! Legendary.", "{said}. Respect, master builder." }, info = "bestbuild" },
}
TP.staff_helper = {
  { q = { "Answered a lot of questions today, {name}?", "Busy day helping players?", "How many new players did you help today?" },
    yes = { "You are a star.", "The new players are lucky." }, no = { "A quiet day. Enjoy it." },
    any = { "{said}? Wow. Thank you for helping.", "That is a lot of patience." } },
  { q = { "What is the most common question new players ask?", "What do new players get wrong the most?", "What is your best advice for new players?" },
    any = { "{said}? I hear that one too.", "{said}! Good to know - I will tell them.", "Ha, {said}. Every time." }, info = "advice" },
  { q = { "Should I send confused players to you?", "Want me to tell new players that you can help?" },
    yes = { "Okay! I will mention you.", "Deal." }, no = { "Okay, I will keep helping them myself." }, any = { "Okay!" } },
}
TP.staff_staff = TP.staff_mod

-- a chat with staff: their greeting, then a topic for one of their roles (each once per chat)
local start0 = C.start
function C.start(who, kind, arg)
  local roles = C.rolesOf(who)
  if #roles == 0 or V.isOwner(who) or kind == "mod" or kind == "topic" then return start0(who, kind, arg) end
  local st, _, first = C.fresh(who)
  local open = C.staffHello(who)
  if kind == "howare" then open = (V.moodText and V.moodText() or "I am fine, thanks.") .. " " .. open end
  if kind == "talk" then V.quietUntil = nil end
  local left = {}
  for _, r in ipairs(roles) do if not st.done["staff_" .. r] then left[#left + 1] = "staff_" .. r end end
  if not (#left > 0 and C.begin(who, st, left[math.random(1, #left)])) then C.nextTopic(who, st) end
  return C.hinted(who, st, first, C.ask(who, st, open))
end
-- their role topics also come up later in a long chat
local next0 = C.nextTopic
function C.nextTopic(who, st)
  for _, r in ipairs(C.rolesOf(who)) do
    if not st.done["staff_" .. r] and math.random() < 0.5 and C.begin(who, st, "staff_" .. r) then return true end
  end
  return next0(who, st)
end
local nameOnly0 = V.nameOnly
V.nameOnly = function(who, raw)
  local st = C.state[low(who)]
  if not C.roleOf(who) or V.isOwner(who) or (st and st.topic and st.asked and os.clock() - (st.at or 0) < 150) then return nameOnly0(who, raw) end
  if not low(raw):find(low(V.cfg("name", "base")), 1, true) or not C.near(who) then return nil end
  return C.start(who, "hello")
end
-- arriving at the base: the staff greeting instead of the visitor / stranger one (the visit is counted as usual)
local greet0 = V.greet
V.greet = function(name, quiet)
  if quiet or not C.roleOf(name) or V.isOwner(name) or V.cfg("fun", true) == false then return greet0(name, quiet) end
  local al = V.alarmAt and V.alarmAt.stranger
  if V.alarmAt then V.alarmAt.stranger = os.clock() end            -- (staff never ring the stranger alarm)
  greet0(name, true)
  if V.alarmAt then V.alarmAt.stranger = al end
  if V.newcomer then V.newcomer[low(name)] = nil end
  return V.say(C.staffHello(name), "minecraft:block.note_block.chime")
end

-- ===== ROASTS (friendly; per role, a pair of roles, and endings) =====
C.ROAST = {
  admin = { "{name}, you have more power than anyone here and you still cannot find your own base.",
    "{name}, you ban people for griefing and then build a dirt hut at spawn.", "{name} is the admin, which means every bug is technically your fault.",
    "{name}, you have creative mode and you still die to creepers.", "{name}, the only thing you moderate is your own sleep schedule. Badly.",
    "{name}, you type /gamemode creative like other people breathe.", "{name}, you made the rules and you still read them wrong.",
    "{name}, admin powers, and you still ask in chat how to craft a hopper.", "{name}, your idea of fixing the server is a restart and a prayer.",
    "{name}, players fear the ban hammer. I fear your building skills.", "{name}, you have operator rights and zero sense of direction.",
    "{name}, the server has a thousand mods and you still only know vanilla recipes.", "{name}, you announce a server event and then forget to come.",
    "{name}, being admin means you can teleport anywhere. And you still walk into lava.", "{name}, you run the server like I run on low fuel. Slowly.",
    "{name}, you have the keys to everything and you keep losing your pickaxe.", "{name}, you approve every rule change except the one about your naps.",
    "{name}, even my turtles follow the rules better than the admin.", "{name}, the server's uptime is better than your attention span.",
    "{name}, you could spawn diamonds, and you still mine for them. With a wooden pickaxe." },
  mod = { "{name}, you watch the chat so hard you forgot to play the game.", "{name}, you have muted more people than you have mined blocks.",
    "{name}, you warn people for spam and then send ten messages in a row.", "{name}, the only rule you never enforce is the one about AFK.",
    "{name}, you are the reason people type in all lower case. They are scared.", "{name}, you police the chat like a skeleton aims. Wildly.",
    "{name}, you read the rules more often than any book in your life.", "{name}, you catch every rule breaker except the one in the mirror.",
    "{name}, your ban reasons are longer than my map files.", "{name}, you moderate the chat and still cannot moderate your snack intake.",
    "{name}, you asked me to report rude players. I am reporting your builds.", "{name}, you spot griefers instantly but you cannot spot a creeper.",
    "{name}, you are so strict even the villagers are afraid to hrmm.", "{name}, you give warnings to people for fun. I have seen it.",
    "{name}, being a mod means you see everything. Including your own mistakes. Daily.", "{name}, your patrol route is from your bed to the chat and back.",
    "{name}, you keep the peace by being so boring nobody wants to fight.", "{name}, you ban people faster than you can build a house.",
    "{name}, the rules have more respect for you than the mobs do.", "{name}, even phantoms wait for your permission to spawn." },
  maintainer = { "{name}, you fix one bug and three new ones show up to say hello.", "{name}, you update the mods and the server forgets how to start.",
    "{name}, your favourite word is restart. Your second favourite is oops.", "{name}, you read crash logs for fun. That is not normal.",
    "{name}, you say it works on your machine. It does not work on the server.", "{name}, every lag spike has your name on it. Allegedly.",
    "{name}, you added a mod to fix lag and the lag got a friend.", "{name}, you test in production. I have seen the logs.",
    "{name}, you keep the server running like a turtle on its last bit of fuel.", "{name}, you know every config file and none of your friends' birthdays.",
    "{name}, the TPS goes up when you log off. Just saying.", "{name}, you broke the server, fixed it, and called it maintenance.",
    "{name}, backups? You say yes. Your face says no.", "{name}, you touched one config file and the Nether moved.",
    "{name}, your patch notes say minor fixes. The players say what happened.", "{name}, you would update the sun if it had a config.",
    "{name}, you spend more time in the console than in the game.", "{name}, you have the server's password and still forget yours.",
    "{name}, even my turtles crash less than your updates.", "{name}, you maintain the server. Your own base is a crater." },
  builder = { "{name}, you build beautiful castles and live in a dirt hut.", "{name}, you used every block in the game except the right ones.",
    "{name}, your builds look great from far away. Very far away.", "{name}, you spent six hours on a roof and forgot the door.",
    "{name}, you call it gradient, I call it random blocks.", "{name}, your spawn build is lovely. Too bad nobody can find the exit.",
    "{name}, you build so big my turtles need a week to map it.", "{name}, you have a thousand stairs and not one of them goes anywhere.",
    "{name}, your palette is deepslate, deepslate, and some more deepslate.", "{name}, you build symmetrical. Except when you do not. Which is always.",
    "{name}, you rebuilt the same wall nine times. It is still crooked.", "{name}, your builds are so detailed the server lags just looking at them.",
    "{name}, you can build a cathedral and you still cannot build a working farm.", "{name}, you placed one block wrong and started over. Again.",
    "{name}, your build has more scaffolding than building.", "{name}, you use world edit and call it handmade.",
    "{name}, you built a statue of yourself. Twice.", "{name}, your idea of a small house has three towers.",
    "{name}, you spent more time choosing a block than I spend mapping a chunk.", "{name}, you build like a creeper renovates. Boldly." },
  helper = { "{name}, you answer every question except the one about where you left your stuff.", "{name}, you help new players and still need help with redstone.",
    "{name}, you have explained the same thing a hundred times. I have counted.", "{name}, you are so helpful you helped a creeper into someone's house.",
    "{name}, your favourite answer is check the quest book. It is a good answer. Every time.", "{name}, you guide new players and get lost yourself.",
    "{name}, you are the help desk and the problem, both." },
  staff = { "{name}, being staff means you have a badge and no free time.", "{name}, you joined the staff for the power and stayed for the paperwork.",
    "{name}, the staff chat is the only chat you read.", "{name}, you work for free and still complain about the boss." },
}
C.ROAST_PAIR = {
  ["admin+builder"] = { "{name}, admin AND builder: you build ugly things and nobody is allowed to say so. Except me.",
    "{name}, you can build anything with admin powers, and you still chose that.", "{name}, you ban griefers and then grief the skyline yourself." },
  ["admin+mod"] = { "{name}, admin and moderator: you write the rules, you watch the rules, and you still break them.",
    "{name}, two ban hammers and not one good build." },
  ["admin+maintainer"] = { "{name}, admin and maintainer: so every crash is your fault twice.", "{name}, you run the server and you break the server. Efficient." },
  ["builder+mod"] = { "{name}, you mod the chat and build at spawn - so you watch people insult your builds all day.",
    "{name}, you would ban anyone who says your build is ugly. So I will say it quietly: it is ugly." },
  ["builder+maintainer"] = { "{name}, you build huge builds and then wonder why the server lags. You fix it, you broke it.",
    "{name}, you build the lag and you maintain the lag." },
  ["maintainer+mod"] = { "{name}, you fix the server and the players, and neither of them work." },
}
C.ROAST_END = { "", " But we love you.", " No offence.", " I say this with love.", " Respectfully.", " Please do not ban me.", " Still my favourite though.",
  " Just kidding. Mostly." }
C.ROASTS_STAFF = {}
for role, list in pairs(C.ROAST) do C.ROASTS_STAFF[role] = combos(list, C.ROAST_END) end
function C.staffRoast(who, roles)
  roles = roles or C.rolesOf(who)
  if #roles == 0 then return nil end
  if #roles >= 2 then
    local pk = pairKey(roles[1], roles[2])
    if C.ROAST_PAIR[pk] and math.random() < 0.35 then return V.fill(pick(C.ROAST_PAIR[pk]) .. pick(C.ROAST_END), who) end
  end
  local r = roles[math.random(1, #roles)]
  return V.fill(pick(C.ROASTS_STAFF[r] or C.ROASTS_STAFF.staff), who)
end
C.NO_STAFF_ROAST = { "Roast the {plural}? We do not have any I know of. {owner} can tell me who they are.",
  "I would roast the {plural}, but my list is empty. Lucky them." }

-- ===== chat: who are the staff, am I staff, I am an admin, roasts, and the owner telling it =====
C.NOT_STAFF = {
  admin = { "An admin? Then you know {owner} has to tell me first. Nice try, {name}!", "Sure, and I am a diamond block. Nice try!",
    "Ha! Show me the ban hammer first.", "If you were an admin, I would know. I know everything. Almost.", "Bold claim! But my list says no, {name}." },
  mod = { "A moderator? Then moderate yourself and stop lying to me. Ha!", "My list of moderators does not have your name, {name}.",
    "Nice try. Real mods do not have to tell me.", "Nope. But I like your confidence, {name}." },
  maintainer = { "A maintainer? Then fix the lag. I will wait.", "If you maintained this server, you would know my name is in the config. Nice try!",
    "Prove it - what is the server's TPS right now? Ha.", "Hmm, not on my list, {name}. The real maintainers are busy fixing things." },
  helper = { "A helper? Then help me believe you. Nope, not on my list.", "Helpful claim, {name}! But no." },
  staff = { "Hmm, you are not on my staff list, {name}. Nice try!", "Really? My staff list says otherwise. Good try, {name}.",
    "I only believe the list {owner} gave me. You are not on it, {name}.", "My staff list does not have your name, {name}. Ask {owner}." },
}
C.IS_STAFF = { "I know, {name}! You are {role} here.", "Of course - you are {role} on my list.", "Yes you are! {role}, and a good one.",
  "Confirmed: {name}, {role}. I salute you.", "Yep! {role}. Everyone, be nice to {name}." }
table.insert(V.patterns, 1, function(who, raw, ws)
  ws = ws or V.norm(raw)
  local t = T(ws)
  local function realName(n)
    for _, e in ipairs(state.players or {}) do if low(e.name) == n then return e.name end end
    if type(state.online) == "table" then for o in pairs(state.online) do if low(o) == n then return o end end end
    if C.staff()[n] then return n end
    return nil
  end
  local NOTNAME = { i = 1, he = 1, she = 1, who = 1, what = 1, this = 1, that = 1, it = 1, you = 1, there = 1, which = 1, everyone = 1, nobody = 1,
    me = 1, us = 1, them = 1, him = 1, her = 1, someone = 1, anyone = 1, everybody = 1, somebody = 1 }
  -- the owner: "Steve is a builder", "Steve is also a moderator", "make Bob an admin", "add Kim as maintainer" (any name with make / add;
  -- "X is a ..." only a player it knows - "this is a mod", "create is a mod" are not), "Steve is not a builder anymore", "Steve is not staff"
  local n1, r1 = t:match(" make (%S+) an? (%S+) $")
  if not n1 then n1, r1 = t:match(" make (%S+) (%S+) $") end
  if not n1 then n1, r1 = t:match(" add (%S+) as an? (%S+) $") end
  if not n1 then n1, r1 = t:match(" add (%S+) as (%S+) $") end
  local loose = false
  if not n1 then loose = true n1, r1 = t:match(" (%S+) is also an? (%S+) $") end
  if not n1 then n1, r1 = t:match(" (%S+) is an? (%S+) now $") end
  if not n1 then n1, r1 = t:match(" (%S+) is an? (%S+) $") end
  if not n1 then n1, r1 = t:match(" (%S+) is our (%S+) $") end
  if not n1 then n1, r1 = t:match(" (%S+) is (staff) $") end
  local d1, dr = t:match(" (%S+) is not an? (%S+) anymore $")
  if not d1 then d1, dr = t:match(" (%S+) is no longer an? (%S+) $") end
  if not d1 then d1, dr = t:match(" (%S+) is not an? (%S+) $") end
  if not d1 then d1, dr = t:match(" remove (%S+) as an? (%S+) $") end
  local gone = t:match(" (%S+) is not staff $") or t:match(" (%S+) is no longer staff $") or t:match(" remove (%S+) from staff $") or
               t:match(" (%S+) is not staff anymore $") or t:match(" (%S+) is not on the staff $")
  if n1 and C.ROLE_WORDS[r1] and not NOTNAME[n1] then
    local real = realName(n1) or (not loose and V.isOwner(who) and n1)
    if real then
      -- (a player saying "Steve is a builder" means he builds - only admin / mod words get "only the owner can")
      if not V.isOwner(who) and loose and (C.ROLE_WORDS[r1] == "builder" or C.ROLE_WORDS[r1] == "helper" or C.ROLE_WORDS[r1] == "maintainer") then return nil end
      if not V.isOwner(who) then return V.fill("Only {owner} can tell me who the staff are.", who) end
      C.addRole(real, C.ROLE_WORDS[r1])
      return "Got it: " .. real .. " is " .. art(C.titles(C.rolesOf(real))) .. " now. I will greet them that way."
    end
  end
  if gone and C.staff()[gone] then
    if not V.isOwner(who) then return V.fill("Only {owner} can tell me who the staff are.", who) end
    C.setRoles(gone, {})
    return "Okay, " .. gone .. " is off my staff list."
  end
  if d1 and dr and C.ROLE_WORDS[dr] and C.staff()[d1] then
    if not V.isOwner(who) then return V.fill("Only {owner} can tell me who the staff are.", who) end
    C.dropRole(d1, C.ROLE_WORDS[dr])
    local left = C.rolesOf(d1)
    return "Okay, " .. d1 .. " is no longer " .. art(C.ROLE_NAME[C.ROLE_WORDS[dr]]) .. "." .. (#left > 0 and (" Still " .. art(C.titles(left)) .. ".") or " Off my staff list.")
  end
  -- ROASTS: "roast me" from staff, "roast the admins", "roast <staff name>"
  if has(t, { "roast me", "insult me", "roast me again", "another roast" }) and #C.rolesOf(who) > 0 then return C.staffRoast(who) end
  local rr = t:match(" roast the (%S+) ") or t:match(" roast our (%S+) ") or t:match(" roast all the (%S+) ") or t:match(" roast all (%S+) ") or
             t:match(" roast (%S+) $")
  if rr and C.ROLE_WORDS[rr] then
    local role = C.ROLE_WORDS[rr]
    local names = {}
    for n, v in pairs(C.staff()) do for _, r in ipairs(parse(v)) do if r == role or role == "staff" then names[#names + 1] = n break end end end
    if #names == 0 then return (V.fill(pick(C.NO_STAFF_ROAST), who):gsub("{plural}", C.ROLE_PLURAL[role])) end
    table.sort(names)
    local target = names[math.random(1, #names)]
    return C.staffRoast(target, role ~= "staff" and { role } or nil)
  end
  local rn = t:match(" roast (%S+) $") or t:match(" roast (%S+) please $") or t:match(" insult (%S+) $")
  if rn and rn ~= "me" and #C.rolesOf(rn) > 0 then return C.staffRoast(realName(rn) or rn) end
  -- who are the staff?
  -- (whole questions only: "is there a mod for that?" is not about moderators)
  local askRole = t:match(" who are the (%S+) $") or t:match(" who is an? (%S+) $") or t:match(" who is the (%S+) $") or t:match(" any (%S+) online $") or
                  t:match(" who are (%S+) $") or t:match(" list the (%S+) $") or t:match(" is there an? (%S+) online $") or t:match(" are there any (%S+) $") or
                  t:match(" are there any (%S+) online $") or t:match(" who are the (%S+) here $") or t:match(" who is an? (%S+) here $")
  if has(t, { "who is staff", "who are the staff", "staff list", "list staff", "who runs the server", "who is on the staff" }) then askRole = "staff" end
  if askRole and C.ROLE_WORDS[askRole] then
    local want = C.ROLE_WORDS[askRole]
    local by = {}
    for n, v in pairs(C.staff()) do
      for _, r in ipairs(parse(v)) do if want == "staff" or r == want then by[r] = by[r] or {} by[r][#by[r] + 1] = n end end
    end
    local parts = {}
    for _, role in ipairs(C.RANK) do
      if by[role] then table.sort(by[role]) parts[#parts + 1] = cap(#by[role] > 1 and C.ROLE_PLURAL[role] or C.ROLE_NAME[role]) .. ": " .. table.concat(by[role], ", ") end
    end
    if #parts == 0 then
      return V.fill(want == "staff" and "I do not know the staff here yet. {owner} can tell me." or
                    ("I do not know any " .. C.ROLE_PLURAL[want] .. " here yet. {owner} can tell me."), who)
    end
    return table.concat(parts, ". ") .. "."
  end
  -- am I staff? / I am an admin
  local amI = t:match(" am i an? (%S+) ") or t:match(" am i (staff) ") or t:match(" am i on the (staff) ")
  if amI and C.ROLE_WORDS[amI] then
    local want, roles = C.ROLE_WORDS[amI], C.rolesOf(who)
    if #roles == 0 then return V.fill("No, you are not on my staff list, {name}.", who) end
    if want ~= "staff" and not C.hasRole(who, want) then return V.fill("Not " .. art(C.ROLE_NAME[want]) .. ", {name} - you are " .. art(C.titles(roles)) .. ".", who) end
    return (V.fill(pick(C.IS_STAFF), who):gsub("{role}", function() return art(C.titles(roles)) end))
  end
  local claim = t:match(" i am an? (%S+) $") or t:match(" i am the (%S+) $") or t:match(" i am an? (%S+) here $") or t:match(" i am (staff) $") or
                t:match(" i am an? server (%S+) $") or t:match(" i am (op) $") or t:match(" i am an? (%S+) on this server $")
  if claim and C.ROLE_WORDS[claim] and claim ~= "builder" and claim ~= "builders" and claim ~= "tech" and claim ~= "support" then
    local roles = C.rolesOf(who)
    if V.isOwner(who) then return V.fill("You are the owner, {name}. Even better.", who) end
    if #roles > 0 then return (V.fill(pick(C.IS_STAFF), who):gsub("{role}", function() return art(C.titles(roles)) end)) end
    return V.fill(pick(C.NOT_STAFF[C.ROLE_WORDS[claim]] or C.NOT_STAFF.staff), who)
  end
  return nil
end)

-- console:  voice staff  /  voice staff add <name> <role> [<role> ...]  /  voice staff remove <name> [<role>]
V.commands.staff = function(words, say)
  local a = low(words[3])
  if (a == "add" or a == "set") and words[4] then
    local added = {}
    for i = 5, #words do
      local role = C.ROLE_WORDS[low(words[i])]
      if not role then say("Not a role: " .. tostring(words[i]) .. "  (admin, mod, maintainer, builder, helper, staff)") return end
      added[#added + 1] = role
    end
    if #added == 0 then added = { "staff" } end
    for _, r in ipairs(added) do C.addRole(words[4], r) end
    say(words[4] .. " is " .. art(C.titles(C.rolesOf(words[4]))) .. " now - the base greets them that way.")
    return
  end
  if (a == "remove" or a == "del" or a == "delete") and words[4] then
    local role = words[5] and C.ROLE_WORDS[low(words[5])]
    if role then C.dropRole(words[4], role) else C.setRoles(words[4], {}) end
    local left = C.rolesOf(words[4])
    say(#left > 0 and (words[4] .. " is " .. art(C.titles(left)) .. " now.") or (words[4] .. " is off the staff list."))
    return
  end
  local n = 0
  say("Staff the base knows (voice staff add <name> admin|mod|maintainer|builder|helper [more roles], voice staff remove <name> [role]):")
  local names = {}
  for name in pairs(C.staff()) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do n = n + 1 say("  " .. name .. " - " .. C.titles(C.rolesOf(name))) end
  if n == 0 then say("  nobody yet") end
end
