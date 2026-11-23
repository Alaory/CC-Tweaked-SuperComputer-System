-- REMINDERS (voice_talk3.lua RM; the owner's chat replayed): "base remind me mekanims needs fixing" got "Tell me when ..."
-- and the text was gone; "tommorow" got the same line again; mancelaz's "Al what time is it for you now" (to Alaory, by a
-- short name) was answered by the base. Now: the text is kept and it asks WHEN; tomorrow / next time / in N min; saved;
-- real time; said when the player is online; "Al ..." = talking to Alaory.
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
state.owner = "Alaory"
local told = {}
chatTell = function(who, text) told[#told + 1] = tostring(text) end
local said = {}

V.useEnv = function() return false end
pcall(ENV.read, true)
local CLOCK = 1000
local realClock, realEpoch = os.clock, os.epoch
local EP = realEpoch("utc")
os.clock = function() return CLOCK end
os.epoch = function(k) if k == "utc" then return EP + math.floor(CLOCK * 1000) end return realEpoch(k) end
local function at(n) return { x = HOME.x + n, y = HOME.y, z = HOME.z } end
local function playing(list)
  state.online, state.players = {}, {}
  for i, n in ipairs(list) do
    state.online[n:lower()] = true
    state.players[#state.players + 1] = { name = n, p = at(i), dim = DRONE_DIM }
  end
end
local function chat(who, msg)
  told, said = {}, {}
  V.chat({ name = who, msg = msg, uuid = "u-" .. who })
  CLOCK = CLOCK + 3
  return table.concat(told, " | ")
end
local function tick(s) CLOCK = CLOCK + (s or 2) told, said = {}, {} pcall(V.tick) return table.concat(told, " | ") end
local function mine(who)
  local n, out = 0, {}
  for _, r in ipairs(V.REMIND.list()) do if r.k == who:lower() then n = n + 1 out[#out + 1] = r.text end end
  return n, table.concat(out, "; ")
end
CHECK(V.REMIND and V.pendKinds and V.pendKinds.remindwhen, "the reminder pack is loaded")

-- 1) the owner's chat, exactly
playing({ "Alaory", "SpookyTheNobody", "DSLGLITCHERS", "mancelaz" })
local r = chat("Alaory", "base remind me mekanims needs fixing")
CHECK(r:find("When should I remind you", 1, true) and r:find("mekanims needs fixing", 1, true), "no time: it keeps the text and asks WHEN: " .. r)
chat("SpookyTheNobody", "in the end ? me ? pfff idk what you talk about")
chat("DSLGLITCHERS", "So should I run a gate pearl to select the mobs and then do another afterwards?")
r = chat("Alaory", "tommorow")
CHECK(r:find("tomorrow", 1, true) and r:find("mekanims needs fixing", 1, true), "\"tommorow\" answers it: " .. r)
local n, txt = mine("Alaory")
CHECK(n == 1 and txt == "mekanims needs fixing", "one reminder kept: " .. txt)
r = chat("mancelaz", "Al what time is it for you now")
CHECK(r == "", "\"Al what time is it\" is for Alaory - the base stays out: " .. r)
CHECK(mine("mancelaz") == 0, "... and sets no reminder")
CHECK(V.namesOther("mancelaz", {}, "Al what time is it") == "alaory", "\"Al\" = Alaory (the start of one online name)")
CHECK(V.namesOther("mancelaz", {}, "so what time is it") == nil, "\"so\" is a word, not a name")
CHECK(V.namesOther("Alaory", {}, "ma what time is it") == "mancelaz", "\"ma\" = mancelaz")

-- 2) due: 12 h later, said when online; offline -> waits
tick(6 * 3600)
CHECK(mine("Alaory") == 1, "not due after 6 h")
playing({ "SpookyTheNobody" })
CLOCK = CLOCK + 7 * 3600
r = tick()
CHECK(mine("Alaory") == 1 and r == "", "due while Alaory is OFF: it waits")
playing({ "Alaory" })
r = tick()
CHECK(r:find("reminder: mekanims needs fixing", 1, true) and mine("Alaory") == 0, "back online: reminded: " .. r)

-- 3) other ways to ask
playing({ "Alaory" })
r = chat("Alaory", "base remind me in 30 min to check the furnace")
CHECK(r:find("in 30 min", 1, true) and r:find("check the furnace", 1, true), "in 30 min to ...: " .. r)
r = chat("Alaory", "base remind me to feed the cows in 2 hours")
CHECK(r:find("in 2 h", 1, true) and r:find("feed the cows", 1, true), "... in 2 hours (at the end): " .. r)
r = chat("Alaory", "base remind me next time to fix the drone")
CHECK(r:find("next time you come online", 1, true) and r:find("fix the drone", 1, true), "next time: " .. r)
r = chat("Alaory", "base set a reminder for half an hour")
CHECK(r:find("what should I remind you about", 1, true), "a time, no text: asks what: " .. r)
r = chat("Alaory", "water the crops")
CHECK(r:find("in 30 min", 1, true) and r:find("water the crops", 1, true), "... the next line is the text: " .. r)
r = chat("Alaory", "base remind me to sleep")
r = chat("Alaory", "nah")
CHECK(r:find("no reminder", 1, true), "\"nah\" = no reminder: " .. r)
r = chat("Alaory", "base my reminders")
CHECK(r:find("check the furnace", 1, true) and r:find("feed the cows", 1, true) and r:find("water the crops", 1, true), "my reminders: " .. r)
-- 30 min later the furnace one comes (said at the base + chat)
CLOCK = CLOCK + 31 * 60
r = tick()
CHECK(r:find("check the furnace", 1, true) and r:find("water the crops", 1, true), "30 min: both due ones: " .. r)
-- next time = after being offline
playing({})
tick()
playing({ "Alaory" })
r = tick()
CHECK(r:find("fix the drone", 1, true), "next time online: " .. r)
r = chat("Alaory", "base forget my reminders")
CHECK(r:find("1 reminder", 1, true) and mine("Alaory") == 0, "forget my reminders: " .. r)

-- the owner: "I did set a reminder for 24 hours which in turn became 4 hours" (the old code cut everything at 4 h)
r = chat("Alaory", "base remind me in 24 hours to check the reactor")
CHECK(r:find("in 24 h", 1, true), "24 hours stays 24 hours: " .. r)
r = chat("Alaory", "base remind me in 3 days to renew the claim")
CHECK(r:find("in 72 h", 1, true), "3 days: " .. r)
CLOCK = CLOCK + 5 * 3600
r = tick()
CHECK(not r:find("reactor", 1, true), "not after 4 or 5 hours: " .. r)
-- not around when it is due (offline): it waits; back online after 30 h -> said then
playing({})
CLOCK = CLOCK + 25 * 3600
r = tick()
CHECK(r == "", "due while offline: nothing said")
playing({ "Alaory" })
r = tick()
CHECK(r:find("check the reactor", 1, true) and not r:find("renew the claim", 1, true), "online again: the 24-hour one comes, the 3-day one waits: " .. r)
chat("Alaory", "base forget my reminders")

-- 4) saved: a restart keeps them
chat("Alaory", "base remind me tomorrow to build the factory")
local m = V.mem()
CHECK(m["#base"] and m["#base"].rem and #m["#base"].rem == 1, "in the memory file (#base.rem)")

-- 5) a far-away owner answering "when?" without the base's name
playing({ "Alaory" })
state.players[1].p = { x = HOME.x + 3000, y = 70, z = HOME.z }
r = chat("Alaory", "base remind me to restock")
CHECK(r:find("When should I remind you", 1, true), "far away: asks when: " .. r)
r = chat("Alaory", "in 10 minutes")
CHECK(r:find("in 10 min", 1, true) and r:find("restock", 1, true), "far away: the answer without the name counts: " .. r)
-- someone else's message never answers MY question
r = chat("Alaory", "base remind me to eat")
playing({ "Alaory", "Bob" })
r = chat("Bob", "tomorrow")
CHECK(not r:find("remind", 1, true) and mine("Bob") == 0, "Bob saying tomorrow answers nothing: " .. r)
os.clock, os.epoch = realClock, realEpoch
