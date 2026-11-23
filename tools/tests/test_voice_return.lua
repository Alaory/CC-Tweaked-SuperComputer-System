-- THE WELCOME-BACK REPORT ONLY ONCE (the owner: "the reminders at base when I join the game never get cleared - I keep
-- hearing them over and over"). (1) a base RESTART while the owner plays (upgrade / crash) counted as "back" - the report
-- and the "players talked about you" chat line again after every restart; (2) "N messages for you" on EVERY return while
-- any message was unread. Now: a return = not seen online since the last log-off; only NEW messages are mentioned.
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
local say0 = V.say
V.say = function(text, ...) said[#said + 1] = tostring(text) return true end
local function online(on)
  state.online = on and { alaory = true } or {}
  state.players = on and { { name = "Alaory", p = { x = HOME.x, y = HOME.y, z = HOME.z }, dim = DRONE_DIM } } or {}
end
local function joined(t) return table.concat(t, " | ") end
local b = V.base()
local DAY = 86400000
-- the owner was online, a visitor left a message long ago (already reported once)
b.msgs = { { from = "Steve", text = "old hello", at = os.epoch("utc") - 5 * DAY } }
b.lastOff = os.epoch("utc") - 4 * DAY
b.ownerSeen = os.epoch("utc") - 4 * DAY
b.visitors = {}
-- 1) a real return after 4 days: the old message (from before the last log-off) is not "new"
V.ownerWasOn = false
online(true)
told, said = {}, {}
V.watchOwner()
CHECK(not b.report, "an OLD unread message does not make a report on every return (report = " .. tostring(b.report) .. ")")
-- 2) the owner leaves, a NEW message comes, the owner comes back: reported once
online(false)
V.watchOwner()
b.lastOff = os.epoch("utc") - 3600000
b.ownerSeen = b.lastOff
b.msgs[#b.msgs + 1] = { from = "Alex", text = "new hello", at = os.epoch("utc") - 1800000 }
online(true)
V.ownerWasOn = false
V.watchOwner()
CHECK(b.report, "a new message while away: reported")
said = {}
V.greet("Alaory")
CHECK(joined(said):find("1 new message", 1, true), "the welcome back counts only the NEW one: " .. joined(said))
CHECK(not b.report, "... and the report is cleared")
-- 3) THE BASE RESTARTS while the owner plays (upgrade): no report again
V.ownerWasOn = nil
b.ownerSeen = os.epoch("utc") - 60000            -- (seen online after the last log-off)
told, said = {}, {}
V.watchOwner()
CHECK(not b.report and #told == 0, "a base restart while the owner plays is no 'welcome back': report " .. tostring(b.report) .. ", chat " .. joined(told))
-- 4) a restart while the owner is online, and the base was off for a day while they were away
b.lastOff = os.epoch("utc") - DAY
b.ownerSeen = b.lastOff
b.msgs[#b.msgs + 1] = { from = "Kim", text = "hi", at = os.epoch("utc") - 3600000 }
V.ownerWasOn = nil
V.watchOwner()
CHECK(b.report, "a real return found after a restart (not seen online since the log-off): reported")
-- 5) THE BASE WAS OFF when the owner logged off (unloaded with them): it never saw the log-off - lastOff old, ownerSeen
-- newer. Coming back a day later is still a return (review: the restart fix lost this report)
b.lastOff = os.epoch("utc") - 5 * DAY
b.ownerSeen = os.epoch("utc") - DAY
b.report = nil
b.msgs[#b.msgs + 1] = { from = "Zed", text = "hey", at = os.epoch("utc") - 3600000 }
V.ownerWasOn = nil
V.watchOwner()
CHECK(b.report and b.reportFrom and b.reportFrom >= os.epoch("utc") - DAY - 1000, "base off at log-off: still a return, counted from the last time seen")
V.say = say0
