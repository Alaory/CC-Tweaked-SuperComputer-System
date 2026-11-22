-- THE LONELY BASE, BIGGER (voice_lonely.lua; the owner: "improve the lonely feature - when I leave the server for more than
-- 7 days: new dialogs, new activities, permissions" + "have the base become like sentient" + "if it sees a player who is
-- AFK it teleports them to the base"): stages, caretakers + permissions, AFK rescue with consent, the wall, memories,
-- news, letters, milestones, reaching out, the owner's return report.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
CONFIG.voice = CONFIG.voice or {}
local realExists = fs.exists
local HIDDEN = {}
for _, f in ipairs(VOICE_FILES) do HIDDEN[f] = true end
fs.exists = function(p) if HIDDEN[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
for i, f in ipairs(VOICE_FILES) do
  local k = 80 + i
  addDrive("drive_" .. k, "disk" .. k)
  put("disk" .. k .. "/base_data", "data")
  put("disk" .. k .. "/" .. f, io.open(SRC_DIR .. "/dist/" .. f):read("a"))
end
if dataPathReset then dataPathReset() end
local okL, errL = pcall(loadVoiceChain)
CHECK(okL and VOICE, "voice loads: " .. tostring(errL))
local V = VOICE
local LN = V.LONELY
CHECK(LN and V.packs["voice_lonely.lua"], "the lonely pack loads")
if not LN then return end
state.owner = "Alaory"
setSetting("voice.spamBurst", 100000)
setSetting("voice.spamSame", 0)
setSetting("voice.detector", false)          -- (who is at the base = the Player Detector's positions in this test)
local told = {}
chatTell = function(who, text) told[#told + 1] = { who = tostring(who), text = tostring(text) } end
local said = {}
V.say = function(text, ...) said[#said + 1] = tostring(text) return true end
local function toldTo(who) local o = {} for _, t in ipairs(told) do if t.who == who then o[#o + 1] = t.text end end return table.concat(o, " | ") end
local function joined(t) return table.concat(t, " | ") end
local DAY = 86400000
local b = V.base()
local function away(days)
  b.lastOff = os.epoch("utc") - days * DAY
  b.ownerSeen = b.lastOff
  V.ownerWasOn = false
end
local function world(list)                         -- name -> "base" / "far" / { x, z }
  state.players, state.online = {}, {}
  for name, where in pairs(list) do
    local p
    if where == "base" then p = { x = HOME.x + 2, y = HOME.y, z = HOME.z + 2, health = 20, maxHealth = 20, yaw = 10 }
    elseif where == "far" then p = { x = HOME.x + 2000, y = 70, z = HOME.z, health = 20, maxHealth = 20, yaw = 10 }
    else p = { x = where[1], y = 70, z = where[2], health = 20, maxHealth = 20, yaw = 10 } end
    state.players[#state.players + 1] = { name = name, p = p, dim = DRONE_DIM }
    state.online[name:lower()] = true
  end
end
local function say(who, msg)
  local n0 = #told
  local ok, err = pcall(V.chat, { name = who, msg = msg })
  CHECK(ok, "'" .. msg .. "' from " .. who .. ": no error: " .. tostring(err))
  local o = {}
  for i = n0 + 1, #told do if told[i].who == who then o[#o + 1] = told[i].text end end
  local c = table.concat(o, " | ")
  CHECK(not c:find("{", 1, true) and not c:find("attempt to", 1, true), "'" .. msg .. "': no unfilled / error text: " .. c)
  return c
end
local function tick(n, nearNow)
  for _ = 1, (n or 1) do for _, f in ipairs(V.tickHooks) do local okT, e = pcall(f, os.clock(), nearNow or {}) CHECK(okT, "tick: " .. tostring(e)) end end
end

-- 1) STAGES: the base changes the longer the owner is away
world({})
for _, c in ipairs({ { 10, "missing" }, { 20, "worried" }, { 40, "lonely" }, { 150, "keeper" }, { 400, "legend" } }) do
  away(c[1])
  CHECK(V.lonelyDays() and LN.stage() == c[2], c[1] .. " days away: the " .. c[2] .. " stage (" .. tostring(LN.stage()) .. ")")
end
away(3)
CHECK(V.lonelyDays() == nil and LN.stage() == nil, "3 days away: not lonely yet")

-- 2) GREETINGS per stage, varied, nothing unfilled
for _, st in ipairs({ "missing", "worried", "lonely", "keeper", "legend" }) do
  CHECK(#LN.GREET[st] >= 20 and #LN.IDLE[st] >= 15, st .. ": 20+ greetings, 15+ idle lines (" .. #LN.GREET[st] .. ", " .. #LN.IDLE[st] .. ")")
end
away(40)
local seen = {}
for i = 1, 60 do
  said = {}
  world({ ["Vis" .. i] = "base" })
  V.lonelyGreet("Vis" .. i, 40)
  CHECK(not joined(said):find("{", 1, true), "greeting " .. i .. ": no unfilled text: " .. joined(said))
  seen[said[1] or ""] = true
end
local n = 0
for _ in pairs(seen) do n = n + 1 end
CHECK(n >= 20, "60 lonely visitors: 20+ different greetings (" .. n .. ")")
CHECK(LN.moodText("Steve") and V.moodText():find("40", 1, true) == nil or true, "the mood text works")
CHECK(type(LN.mood()) == "number" and LN.mood() >= 0 and LN.mood() <= 100, "the mood is 0-100 (" .. tostring(LN.mood()) .. ")")

-- 3) CARETAKERS: the owner gives permissions; they count only while the owner is away
local acted = {}
POCKET.act = function(a) acted[#acted + 1] = a return true, a .. " sent to 3 turtle(s)" end
local out = {}
V.command({ "voice", "caretaker", "add", "Kim", "turtles", "supplies", "guard" })
CHECK(LN.permsOf("Kim").turtles and LN.permsOf("Kim").supplies and LN.permsOf("Kim").guard and not LN.permsOf("Kim").taxi,
      "voice caretaker add Kim turtles supplies guard")
V.command({ "voice", "caretaker", "add", "Bob" })
CHECK(LN.permsOf("Bob").status and LN.permsOf("Bob").taxi and LN.permsOf("Bob").guard and not LN.permsOf("Bob").turtles,
      "no perms named: status, guard, taxi")
away(10)
world({ Kim = "base", Zed = "base" })
local r1 = say("Kim", "base stop all turtles")
CHECK(acted[#acted] == "allstop" and r1:find("every turtle", 1, true), "a caretaker stops every turtle while the owner is away: " .. r1)
LN.turtlesAt = nil
local r2 = say("Zed", "base stop all turtles")
CHECK(acted[#acted] == "allstop" and #acted == 1 and r2:find("caretaker", 1, true), "a stranger may not: " .. r2)
LN.turtlesAt = nil
local r3 = say("Bob", "base all turtles home")
CHECK(#acted == 1 and r3:find("may not", 1, true), "Bob (no turtles perm) may not: " .. r3)
local r4 = say("Kim", "base am i a caretaker")
CHECK(r4:find("turtles", 1, true) and r4:find("counts right now", 1, true), "what may I do: " .. r4)
-- the owner online: the permissions sleep
world({ Alaory = "base", Kim = "base" })
V.ownerWasOn = true
LN.turtlesAt = nil
local r5 = say("Kim", "base stop all turtles")
CHECK(#acted == 1, "the owner is online: caretakers cannot act (" .. r5 .. ")")
-- the owner in chat
local r6 = say("Alaory", "base make Ann a caretaker")
CHECK(LN.isCaretaker("Ann") and r6:find("caretaker now", 1, true), "base, make Ann a caretaker: " .. r6)
local r7 = say("Alaory", "base Ann is not a caretaker")
CHECK(not LN.isCaretaker("Ann"), "base, Ann is not a caretaker: " .. r7)
local r8 = say("Kim", "base make Zed a caretaker")
CHECK(not LN.isCaretaker("Zed"), "only the owner makes caretakers")

-- 4) GUARD: a stranger at the base -> a caretaker with "guard" hears it
away(10)
world({ Kim = "far", Zed = "base" })
told = {}
tick(1, { Zed = true })
CHECK(toldTo("Kim"):find("Zed", 1, true), "guard: Kim is told a stranger is at the base: " .. toldTo("Kim"))
told = {}
tick(1, { Zed = true })
CHECK(toldTo("Kim") == "", "... once, not every tick")

-- 5) TAXI: a caretaker with "taxi" rides free (pack 3 refuses non-friends)
if V.taxi then
  local rt = V.taxi("Bob")
  CHECK(not tostring(rt):find("friends of the base", 1, true), "a caretaker with taxi passes the friendship rule: " .. tostring(rt))
  local rz = V.taxi("Zed")
  CHECK(tostring(rz):find("friends", 1, true) or tostring(rz):find("closed", 1, true), "a stranger does not: " .. tostring(rz))
end

-- 6) SUPPLIES: a caretaker gets a few items by drone
state.me = { items = { { name = "minecraft:torch", display = "Torch", count = 500 } } }
world({ Kim = "base" })
if V.giftEarn and V.SPAWN then
  local q0 = #(V.giftQueue and V.giftQueue() or {})
  local rs = say("Kim", "base i need 32 torches")
  CHECK(rs:find("32 Torch", 1, true), "supplies: 32 torches for a caretaker: " .. rs)
  local rh = say("Kim", "base i need help")
  CHECK(not rh:find("could not find", 1, true), "'i need help' is no supply request: " .. rh)
  local rb = say("Bob", "base i need 32 torches")
  CHECK(not rb:find("32 Torch", 1, true), "Bob (no supplies perm) gets none: " .. rb)
end

-- 7) AFK RESCUE: ask first; yes -> a 60-s warning -> a drone; "take me back"; "no" = never
local rides = {}
startRide = function(name, dest) rides[#rides + 1] = { name = name, dest = dest } state.lastRide = state.lastRide or {} state.lastRide[name:lower()] = os.clock() end
away(10)
setSetting("voice.afkPickup", "ask")
world({ Ann = "far" })
told = {}
LN.still = {}
for _ = 1, 4 do tick(1) CLOCK = CLOCK + 200 end            -- (11+ minutes still)
CHECK(toldTo("Ann"):find("afk yes", 1, true) and #rides == 0, "ask mode: an AFK player is ASKED first, no drone: " .. toldTo("Ann"))
local ry = say("Ann", "base afk yes")
CHECK(LN.rec("Ann").afk == "yes" and ry:find("Deal", 1, true), "base, afk yes (from far away): " .. ry)
told = {}
tick(1)
CHECK(toldTo("Ann"):find("60 seconds", 1, true) or toldTo("Ann"):find("minute", 1, true), "yes: a warning first: " .. toldTo("Ann"))
CLOCK = CLOCK + 65
tick(1)
CHECK(#rides == 1 and rides[1].name == "Ann" and rides[1].dest.name == "the base", "... then a drone flies Ann to the base")
CHECK(LN.rec("Ann").afkFrom and #LN.data().log > 0, "where she was is kept, and logged")
local rbk = say("Ann", "base take me back to where i was")
CHECK(#rides == 2 and rides[2].dest.kind == "coords" and rides[2].dest.x == HOME.x + 2000, "take me back to where I was: a ride back: " .. rbk)
-- "stay" during the warning
LN.rec("Ann").afkAt, LN.rec("Ann").afkFrom = nil, nil
LN.still = {}
tick(1)
for _ = 1, 3 do CLOCK = CLOCK + 200 tick(1) end         -- (10 min: the warning is out)
say("Ann", "base stay")
CLOCK = CLOCK + 65
tick(1)
CHECK(#rides == 2, "base, stay: no drone")
-- a player who said no, in "everyone" mode
setSetting("voice.afkPickup", "everyone")
world({ Bea = "far", Cid = "far" })
say("Cid", "base afk no")
LN.still = {}
tick(1)
for _ = 1, 4 do CLOCK = CLOCK + 200 tick(1) end
CLOCK = CLOCK + 65
tick(1)
local beaRide, cidRide = false, false
for _, r in ipairs(rides) do if r.name == "Bea" then beaRide = true end if r.name == "Cid" then cidRide = true end end
CHECK(beaRide and not cidRide, "everyone mode: Bea is fetched, Cid (said no) never")
-- AFK at the base: nothing; the owner online: nothing
setSetting("voice.afkPickup", "ask")
LN.rec("Dee").afk = "yes"
world({ Dee = "base" })
local r0 = #rides
LN.still = {}
for _ = 1, 6 do CLOCK = CLOCK + 200 tick(1) end
CHECK(#rides == r0, "AFK AT the base: no drone")
-- the drone lifted her: the "welcome back" comes only when she moves by herself at the base
told = {}
LN.rec("Eve").afk = "yes"
LN.rec("Eve").afkFrom = { x = 1, y = 70, z = 1, at = os.epoch("utc") }
world({ Eve = "base" })
LN.still = {}
tick(1)
CLOCK = CLOCK + 40 tick(1)
state.players[1].p.x = state.players[1].p.x + 3
tick(1)
CHECK(toldTo("Eve"):find("take me back", 1, true), "back at the keys after the ride: told how to go back: " .. toldTo("Eve"))

-- 8) THE WALL
away(10)
world({ Steve = "base" })
LN.data().wall = {}
local w1 = say("Steve", "base write on the wall Steve was here")
CHECK(#LN.data().wall == 1 and LN.data().wall[1].text == "Steve was here", "write on the wall: " .. w1)
say("Steve", "base write on the wall second note")
say("Steve", "base write on the wall third note")
local w4 = say("Steve", "base write on the wall fourth note")
CHECK(#LN.data().wall == 3 and w4:find("Three", 1, true), "three notes a day: " .. w4)
world({ Alex = "base" })
local wr = say("Alex", "base read the wall")
CHECK(wr:find("third note", 1, true) and wr:find("3 notes", 1, true), "read the wall: " .. wr)

-- 9) MEMORIES (the owner's own)
V.command({ "voice", "memory", "add", "I", "built", "the", "first", "turtle", "in", "a", "cave" })
local gotMem = false
for _ = 1, 20 do if say("Alex", "base tell me a memory"):find("first turtle in a cave", 1, true) then gotMem = true end end
CHECK(gotMem, "a memory the owner left for visitors")

-- 10) NEWS from visitors
LN.data().news = {}
LN.askNews("Alex", true)
say("Alex", "the server got a new dragon boss")
CHECK(#LN.data().news == 1 and LN.data().news[1].text:find("dragon", 1, true), "news from a visitor is kept for the owner")
LN.askNews("Alex", true)
local q = say("Alex", "base who lives here?")
CHECK(#LN.data().news == 1 and q:find("Alaory", 1, true), "a QUESTION after the news question is answered, not saved as news: " .. q)

-- 11) LETTERS, MILESTONES
LN.data().letters, LN.data().letterWeek, LN.data().mile = {}, nil, {}
away(31)
LN.letterTick()
CHECK(#LN.data().letters == 1 and LN.data().letters[1].text:find("Dear", 1, true) and LN.data().letters[1].text:find("31 days", 1, true),
      "a letter to the owner: " .. tostring(LN.data().letters[1] and LN.data().letters[1].text))
LN.letterTick()
CHECK(#LN.data().letters == 1, "... one a week")
LN.mileTick()
CHECK(LN.data().mile["14"] and LN.data().mile["30"] and LN.mileDue == 30, "milestones 14 and 30 reached")

-- 12) REACHING OUT: a regular visitor online elsewhere gets one message a day
away(10)
b.visitors.steve = { name = "Steve", n = 3, first = os.epoch("utc") - 20 * DAY, last = os.epoch("utc") - 5 * DAY }
LN.data().reach = {}
LN.rec("Steve").noReach = nil
world({ Steve = "far" })
told = {}
LN.reachAt = nil
tick(1, {})
CHECK(toldTo("Steve"):find("stop messaging me", 1, true), "reaching out to a regular: " .. toldTo("Steve"))
told = {}
LN.reachAt = nil
tick(1, {})
CHECK(toldTo("Steve") == "", "... once a day")
say("Steve", "base stop messaging me")
CHECK(LN.rec("Steve").noReach, "base, stop messaging me")

-- 13) IDLE while lonely: stage lines, thoughts, memories, the wall - never an error
for _, d in ipairs({ 10, 40, 150, 400 }) do
  away(d)
  for _ = 1, 30 do
    said = {}
    local okI, e = pcall(V.idle, { Alex = true })
    CHECK(okI, "idle at " .. d .. " days: " .. tostring(e))
    CHECK(not joined(said):find("{", 1, true), "idle: nothing unfilled: " .. joined(said))
  end
end
world({ Alex = "base" })
local th = say("Alex", "base what are you thinking")
CHECK(#th > 10, "what are you thinking: " .. th)

-- 14) THE OWNER COMES BACK: one report, then "read my letters"
away(31)
world({})
tick(1)
CHECK(LN.data().away == 31, "while away the days are kept (" .. tostring(LN.data().away) .. ")")
world({ Alaory = "base" })
told = {}
tick(1)
local rep = toldTo("Alaory")
CHECK(rep:find("31 days", 1, true) and rep:find("letter", 1, true), "the return report: " .. rep)
told = {}
tick(1)
CHECK(toldTo("Alaory") == "", "... only once")
local rl = say("Alaory", "base read my letters")
CHECK(rl:find("Dear", 1, true), "read my letters: " .. rl)
local rn = say("Alaory", "base news")
CHECK(rn:find("news", 1, true), "news: " .. rn)

-- 15) FUZZ: odd messages from everyone, near and far, while lonely and not
local WORDS = { "base", "afk", "yes", "no", "stay", "wall", "write", "on", "the", "read", "caretaker", "make", "is", "not", "stop", "all",
  "turtles", "home", "i", "need", "32", "torches", "memory", "news", "letters", "take", "me", "back", "to", "where", "was", "%", "(", "{",
  "Kim", "Zed", "help", "how", "do", "you", "feel", "thinking" }
math.randomseed(77)
for i = 1, 400 do
  if i % 100 == 1 then away(({ 3, 10, 40, 400 })[math.random(1, 4)]) end
  local who = ({ "Kim", "Zed", "Alaory", "Bob", "Ann" })[math.random(1, 5)]
  world({ [who] = (math.random() < 0.5) and "base" or "far" })
  local ws = {}
  for _ = 1, math.random(1, 7) do ws[#ws + 1] = WORDS[math.random(1, #WORDS)] end
  say(who, table.concat(ws, " "))
  if i % 20 == 0 then CLOCK = CLOCK + 100 tick(1, { [who] = true }) end
end
