-- HUMBLE + NO FORTUNES (the owner: "remove the tell me the fortune speech" + "when a player says the base / sparky is like a
-- god or a lord, make it clear it is just a bot; if the owner / boss is like a god or a lord, tell them they are just a
-- regular player who had time to waste - keep things humble").
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
CONFIG.voice = CONFIG.voice or {}
local realExists = fs.exists
local HIDDEN = {}
for _, f in ipairs(VOICE_FILES) do HIDDEN[f] = true end
fs.exists = function(p) if HIDDEN[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
for i, f in ipairs(VOICE_FILES) do
  local k = 40 + i
  addDrive("drive_" .. k, "disk" .. k)
  put("disk" .. k .. "/base_data", "data")
  put("disk" .. k .. "/" .. f, io.open(SRC_DIR .. "/dist/" .. f):read("a"))
end
if dataPathReset then dataPathReset() end
local okL, errL = pcall(loadVoiceChain)
CHECK(okL and VOICE, "voice loads: " .. tostring(errL))
local V = VOICE
if not V then return end
state.owner = "Alaory"
setSetting("voice.spamBurst", 100000)
setSetting("voice.spamSame", 0)
setSetting("voice.detector", false)
setSetting("voice.name", "sparky")
local told = {}
chatTell = function(who, text) told[#told + 1] = { who = tostring(who), text = tostring(text) } end
local said = {}
V.say = function(text) said[#said + 1] = tostring(text) return true end
local function world(list)
  state.players, state.online = {}, {}
  for name, where in pairs(list) do
    local p = where == "base" and { x = HOME.x + 2, y = HOME.y, z = HOME.z + 2 } or { x = HOME.x + 3000, y = 70, z = HOME.z }
    state.players[#state.players + 1] = { name = name, p = p, dim = DRONE_DIM }
    state.online[name:lower()] = true
  end
end
local function say(who, msg)
  local n0 = #told
  V.convo, V.pend, V.games, V.chatAt, V.talkingTo = {}, {}, {}, {}, {}
  local ok, err = pcall(V.chat, { name = who, msg = msg })
  CHECK(ok, "'" .. msg .. "': no error: " .. tostring(err))
  local o = {}
  for i = n0 + 1, #told do if told[i].who == who then o[#o + 1] = told[i].text end end
  local c = table.concat(o, " | ")
  CHECK(not c:find("{", 1, true) and not c:find("attempt to", 1, true), "'" .. msg .. "': no unfilled / error text: " .. c)
  return c
end

-- 1) WHO IS IT ABOUT
local cases = {
  { "you are a god", "bot" }, { "sparky you are a god", "bot" }, { "you are literally a god", "bot" }, { "ur a god", "bot" },
  { "you are like a lord", "bot" }, { "are you a god?", "bot" }, { "you must be a god", "bot" }, { "all hail sparky", "bot" },
  { "i worship you", "bot" }, { "bow down to the base", "bot" }, { "yes my lord", "bot" }, { "the bot is a god", "bot" },
  { "praise the speaker", "bot" }, { "you are the almighty one", "bot" }, { "sparky is godlike", "bot" },
  { "alaory is a god", "owner" }, { "your owner is a god", "owner" }, { "is your boss a lord?", "owner" }, { "all hail alaory", "owner" },
  { "lord alaory", "owner" }, { "your creator is like a god", "owner" }, { "the owner is a literal god", "owner" },
  { "alaory must be a god", "owner" }, { "i worship alaory", "owner" }, { "bow to your owner", "owner" },
  { "i am a god", "self" }, { "im a god", "self" },
  { "oh my god", nil }, { "omg", nil }, { "thank god", nil }, { "god apple pls", nil }, { "that build is god tier", nil },
  { "my god this is cool", nil }, { "how do i kill the boss", nil }, { "god damn creepers", nil }, { "what is a god apple", nil },
  { "do you believe in god", nil }, { "god mode", nil }, { "tell me a joke", nil }, { "the king of the hill game", nil },
}
for _, c in ipairs(cases) do
  local ok, k = pcall(V.humbleKind, c[1], false)
  CHECK(ok and k == c[2], "'" .. c[1] .. "' -> " .. tostring(c[2]) .. " (got " .. tostring(k) .. ")")
end
-- not called by name: "you" is another player
for _, c in ipairs({ { "you are a god", nil }, { "dude you are a god", nil }, { "i think sparky is a god", "bot" },
                     { "alaory is a god lol", "owner" }, { "i am a god", nil }, { "all hail alaory", "owner" } }) do
  CHECK(V.humbleKind(c[1], true) == c[2], "(not called) '" .. c[1] .. "' -> " .. tostring(c[2]) .. " (got " .. tostring(V.humbleKind(c[1], true)) .. ")")
end

-- 2) THE ANSWERS: humble, varied
world({ Kim = "base", Alaory = "far" })
local seenB, seenO = {}, {}
local nb, no = 0, 0
for _ = 1, 60 do
  local c = say("Kim", "sparky you are a god")
  CHECK(c:lower():find("bot", 1, true), "the base as a god -> just a bot: " .. c)
  if not seenB[c] then seenB[c] = true nb = nb + 1 end
  local c2 = say("Kim", "sparky alaory is a god")
  CHECK(c2:lower():find("player", 1, true), "the owner as a god -> a regular player: " .. c2)
  if not seenO[c2] then seenO[c2] = true no = no + 1 end
end
CHECK(nb >= 40 and no >= 40, "varied: " .. nb .. " / " .. no .. " different answers in 60")
CHECK(#V.L.HUMBLE_BOT >= 100 and #V.L.HUMBLE_OWNER >= 100, "100+ lines each")
local ts = 0
for _, l in ipairs(V.L.HUMBLE_OWNER) do if l:find("time to waste", 1, true) then ts = ts + 1 end end
CHECK(ts >= 20, "'time to waste' said often enough (" .. ts .. ")")
local c3 = say("Alaory", "sparky i am a god")
CHECK(c3 == "No, you are just wasting your time.", "the owner saying 'I am a god': simply 'No, you are just wasting your time.' - " .. c3)
CHECK(say("Alaory", "sparky im a god") == "No, you are just wasting your time.", "... 'im a god' too")
local c4 = say("Kim", "sparky i am a god")
CHECK(c4:lower():find("player", 1, true) or c4:lower():find("bot", 1, true) or c4:lower():find("creeper", 1, true), "a visitor saying 'I am a god': " .. c4)

-- 3) SAID WITHOUT CALLING IT: a word anyway (spoken at the base), once per 10 min per player
told, said = {}, {}
V.humbleAt = {}
world({ Kim = "base", Bob = "base" })
say("Kim", "i think sparky is a god")
CHECK(#told >= 1 and told[#told].text:lower():find("bot", 1, true), "'i think sparky is a god' (not called) -> just a bot: " .. tostring(told[#told] and told[#told].text))
CHECK(#said >= 1, "... spoken at the base")
local n1 = #told
say("Kim", "seriously sparky is a god")
CHECK(#told == n1, "... not again within 10 min")
say("Bob", "oh my god look at that")
CHECK(#told == n1, "'oh my god' -> nothing")

-- 4) NO FORTUNES
CHECK(V.L.FORTUNES == nil and V.L.DAILY_FORTUNE == nil, "the fortune lists are gone")
for _, m in ipairs({ "sparky tell me my fortune", "sparky fortune cookie", "sparky tell me the fortune", "sparky fortune of the day",
                     "sparky tell me a fortune" }) do
  local c = say("Kim", m)
  local l = c:lower()
  CHECK(#c > 5 and not l:find("fortune cookie says", 1, true) and not l:find("fortune for today", 1, true)
        and (l:find("bot", 1, true) or l:find("future", 1, true)), "'" .. m .. "' -> a humble no: " .. c)
end
local menu = {}
for _, it in ipairs(V.MORE or {}) do menu[#menu + 1] = tostring(it[1]) end
CHECK(not table.concat(menu, " "):lower():find("fortune", 1, true), "no fortune in the menus")
said = {}
for _ = 1, 300 do pcall(V.idle, { Kim = true }) end
local idleTxt = table.concat(said, " "):lower()
CHECK(not idleTxt:find("fortune", 1, true) and not idleTxt:find("i predict", 1, true), "no fortunes in idle talk")
