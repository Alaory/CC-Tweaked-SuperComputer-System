-- GREETINGS ONLY IN THE OVERWORLD (the owner: "check the player greeting detection to include if a player is in the
-- overworld"): a player at the base's x z in ANOTHER dimension is not at the base - not greeted, not counted near.
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
setSetting("voice.detector", false)
local function near(e)
  state.players, state.online = { e }, { [e.name:lower()] = true }
  for _, n in ipairs(V.nearPlayers()) do if n.name == e.name then return true end end
  return false
end
local AT = { x = HOME.x + 2, y = HOME.y, z = HOME.z + 2 }
CHECK(near({ name = "Steve", p = AT, dim = DRONE_DIM }), "Steve at the base in the overworld: near")
CHECK(not near({ name = "Steve", p = AT, dim = "minecraft:the_nether" }), "Steve at the same x z in the Nether: NOT near")
CHECK(not near({ name = "Steve", p = AT, dimOther = true }), "dimension unknown but the detector says another one: NOT near")
CHECK(near({ name = "Steve", p = AT }), "dimension not known at all (an old detector): near, as before")
-- greeted only in the overworld
local said = {}
V.say = function(text) said[#said + 1] = tostring(text) return true end
V.greeted, V.near = {}, {}
state.players = { { name = "Steve", p = AT, dim = "minecraft:the_nether" } }
state.online = { steve = true }
for _ = 1, 5 do CLOCK = CLOCK + 3 pcall(V.tick) end
local hi = false
for _, l in ipairs(said) do if l:find("Steve", 1, true) or l:lower():find("visitor", 1, true) then hi = true end end
CHECK(not hi, "a player in the Nether under the base is not greeted (" .. table.concat(said, " | ") .. ")")
CHECK(V.inOverworld({ dim = DRONE_DIM }) and not V.inOverworld({ dim = "minecraft:the_end" }) and not V.inOverworld({ dimOther = true }),
      "VOICE.inOverworld")
-- the spawn speaker and the lonely base use the same rule
for _, f in ipairs({ "voice_spawn.lua", "voice_lonely.lua" }) do
  local src = io.open(SRC_DIR .. "/" .. f):read("a")
  CHECK(src:find("dimOther", 1, true), f .. ": an unknown dimension the detector calls 'another one' does not count")
end
