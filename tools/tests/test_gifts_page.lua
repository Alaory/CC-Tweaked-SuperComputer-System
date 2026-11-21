-- GIFTS PAGE (the owner: "add a new tab for gifts where I can add gifts to the list of possible gifts from AE2,
-- and send gifts from that tab to other players"). The real voice add-on + talk packs (from data floppies), an AE2
-- item list, every button tapped: pick an item, x count, TO a player, SEND (two taps) -> queued for a drone; ADD TO
-- a reward (two taps) -> that reward gives it (settings.dat), REMOVE, RESET; the queue says why a gift waits,
-- CANCEL; without the add-on the page says how to install it.
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
state.page = "gifts"
-- 1) no add-on: the page explains, no GIFTS tab
VOICE = nil
local okD, errD = pcall(draw)
CHECK(okD, "the page draws without the add-on: " .. tostring(errD))
local function onScreen(s)
  for y = 1, H do
    local _, t = pcall(function() return win.getLine(y) end)
    if type(t) == "string" and t:find(s, 1, true) then return true end
  end
  return false
end
CHECK(onScreen("voice install"), "... and says: voice install")
local hasTab = false
for _, t in ipairs(pageTabs()) do if t[1] == "gifts" then hasTab = true end end
CHECK(not hasTab, "no GIFTS tab without the add-on")

-- 2) the add-on and its packs on data floppies
local realExists = fs.exists
local HIDDEN = { ["voice_addon.lua"] = true, ["voice_talk.lua"] = true, ["voice_talk2.lua"] = true, ["voice_talk3.lua"] = true,
                 ["voice_lines.lua"] = true, ["voice_idle.lua"] = true, ["voice_lore.lua"] = true }
fs.exists = function(p) if HIDDEN[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
local function put(p, t) local h = fs.open(p, "w") h.write(t) h.close() end
local k = 20
for _, f in ipairs({ "voice_addon.lua", "voice_talk.lua", "voice_talk2.lua", "voice_talk3.lua" }) do
  k = k + 1
  addDrive("drive_" .. k, "disk" .. k)
  put("disk" .. k .. "/base_data", "data")
  put("disk" .. k .. "/" .. f, io.open(SRC_DIR .. "/dist/" .. f):read("a"))
end
if dataPathReset then dataPathReset() end
loadVoiceChain()
CHECK(VOICE and VOICE.giftEarn and VOICE.giftNow, "the voice add-on + pack 2 loaded")
http = nil
bridgeKind = bridgeKind or "ME"
bridge = bridge or { getItems = function() return {} end }
state.me = { items = {
  { name = "minecraft:diamond", display = "Diamond", count = 500 },
  { name = "minecraft:dirt", display = "Dirt", count = 9000 },
  { name = "minecraft:emerald", display = "Emerald", count = 40 },
  { name = "minecraft:golden_apple", display = "Golden Apple", count = 3 } }, byName = {} }
state.owner = "Alaory"
state.online = { alaory = true, kevin = true, bob = true }
state.players = { { name = "Alaory", p = { x = HOME.x, y = HOME.y, z = HOME.z }, dim = DRONE_DIM },
                  { name = "Kevin", p = { x = HOME.x + 900, y = 70, z = HOME.z }, dim = DRONE_DIM },
                  { name = "Bob", p = { x = HOME.x - 500, y = 70, z = HOME.z }, dim = DRONE_DIM } }
for _, t in ipairs(pageTabs()) do if t[1] == "gifts" then hasTab = true end end
CHECK(hasTab, "the GIFTS tab is there with the add-on")
local function hitOf(kind, val)
  for _, h in ipairs(hits) do
    local v = h[6]
    if h[5] == kind and (val == nil or v == val or (type(v) == "table" and (v.kind == val or v.name == val))) then return h end
  end
end
local function tap(kind, val, twice)
  draw()
  local h = hitOf(kind, val)
  CHECK(h, "the page shows a button for " .. kind .. " " .. tostring(val))
  if not h then return end
  handleTouch(h[1], h[2])
  if twice then draw() h = hitOf(kind, val) if h then handleTouch(h[1], h[2]) end end
end
-- every size draws
for _, sz in ipairs({ { 100, 40 }, { 121, 50 }, { 164, 81 }, { 200, 100 } }) do
  if setMonitorSize then setMonitorSize(sz[1], sz[2]) end
  local ok, e = pcall(draw)
  CHECK(ok, "draws at " .. sz[1] .. "x" .. sz[2] .. ": " .. tostring(e))
end
-- pick: the letter D, then Diamond
tap("giftletter", "D")
draw()
CHECK(state.giftLetter == "D" and hitOf("giftitem", "minecraft:diamond") and not hitOf("giftitem", "minecraft:emerald"),
      "a letter shows only its items")
tap("giftitem", "minecraft:diamond")
draw()
CHECK(state.giftItem == "minecraft:diamond" and onScreen("AE2 has 500"), "tapping an item picks it (AE2 has 500)")
tap("giftcount")
CHECK(GIFTS.count() == 32, "x16 > = 32 (" .. GIFTS.count() .. ")")
-- TO: cycles the online players
local first = GIFTS.to()
tap("giftto")
CHECK(GIFTS.to() ~= first, "TO > = the next online player (" .. tostring(first) .. " -> " .. tostring(GIFTS.to()) .. ")")
while GIFTS.to() ~= "Kevin" do tap("giftto") end
-- SEND (two taps): queued for Kevin
local q = VOICE.giftQueue()
local n0 = #q
tap("act", "giftsend", true)
q = VOICE.giftQueue()
CHECK(#q == n0 + 1 and q[#q].who == "Kevin" and q[#q].item == "minecraft:diamond" and q[#q].n == 32,
      "SEND (two taps): 32 diamonds queued for Kevin")
-- the queue shows it with its reason, CANCEL (two taps)
draw()
CHECK(hitOf("act", "giftcancel"), "the waiting gift has a CANCEL button")
tap("act", "giftcancel", true)
CHECK(#VOICE.giftQueue() == n0, "CANCEL (two taps) takes it out of the queue")
-- REWARDS: pick "friend", ADD the diamonds (two taps), REMOVE, RESET
tap("giftwhy", "friend")
CHECK(GIFTS.reward() == "friend", "a reward button picks it")
local before = #VOICE.giftList("friend")
tap("act", "giftadd", true)
local found
for _, g in ipairs(VOICE.giftList("friend")) do if g[1] == "minecraft:diamond" then found = g[2] end end
CHECK(found == 32, "ADD (two taps): the friend gift gives 32 diamonds now (" .. tostring(found) .. ")")
tap("giftitem", "minecraft:diamond")          -- (unpick)
tap("giftletter", "E")
tap("giftitem", "minecraft:emerald")
tap("act", "giftadd", true)
local hasEm = false
for _, g in ipairs(VOICE.giftList("friend")) do if g[1] == "minecraft:emerald" then hasEm = true end end
CHECK(hasEm and #VOICE.giftList("friend") == before + (found and 0 or 1) + 1, "a new item is added to the list")
CHECK(SETTINGS["voice.gifts.friend"] ~= nil, "kept in settings.dat")
draw()
for _ = 1, 2 do
  local hd
  for _, h in ipairs(hits) do if h[5] == "act" and h[6].kind == "giftdel" and h[6].name == "minecraft:emerald" then hd = h end end
  CHECK(hd, "the emerald has a REMOVE button")
  if hd then handleTouch(hd[1], hd[2]) end
  draw()
end
hasEm = false
for _, g in ipairs(VOICE.giftList("friend")) do if g[1] == "minecraft:emerald" then hasEm = true end end
CHECK(not hasEm, "REMOVE (two taps) takes it out")
-- an earned friend title now brings what you set
VOICE.giftEarn("Bob", "friend")
local bobDiamonds = 0
for _, g in ipairs(VOICE.giftQueue()) do if g.who == "Bob" and g.item == "minecraft:diamond" then bobDiamonds = g.n end end
CHECK(bobDiamonds == 32, "a player who becomes a friend gets YOUR list (" .. bobDiamonds .. " diamonds)")
tap("act", "giftreset", true)
CHECK(SETTINGS["voice.gifts.friend"] == nil, "RESET (two taps): back to the default")
-- TRY NOW: says what happened
setPopup = setPopup
local pop
local sp = setPopup
setPopup = function(t, m) pop = m end
tap("giftnow")
setPopup = sp
CHECK(pop and pop:find("Gift check", 1, true), "TRY NOW says what happened: " .. tostring(pop))
-- refusals are said: nobody picked
state.giftItem = nil
local ok, msg = GIFTS.send("Kevin", nil, 1)
CHECK(not ok and msg:find("pick an AE2 item", 1, true), "SEND without an item says so")
for _, g in ipairs(VOICE.giftQueue()) do g.retryAt = nil end
VOICE.base().giftQ = {}
state.page = "home"
