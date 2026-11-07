-- AWAY: online / offline from the server's list (not the player list the base
-- fills in), the "base was off" box after a restart, no away start before the
-- map is read. STORAGE HELPERS: only ours are turned on / restarted.
state.owner = "Alaory"
local online = {}
det = { getOnlinePlayers = function() return online end,
        getPlayer = function(n) for _, o in ipairs(online) do if o == n then
          return { x = 1, y = 70, z = 2, dimension = "minecraft:overworld" } end end return {} end,
        getPlayersInRange = function() return online end }
refreshPlayers(true)
CHECK(AWAY.ownerOnline() == false, "nobody online: the owner is offline (" .. tostring(AWAY.ownerOnline()) .. ")")
online = { "Bob" } refreshPlayers(true)
CHECK(AWAY.ownerOnline() == false, "only Bob online: the owner is offline")
online = { "Bob", "Alaory" } refreshPlayers(true)
CHECK(AWAY.ownerOnline() == true, "the owner online")

-- the base was OFF for an hour, just restarted; the owner is online but the
-- player list is not read yet in the first ticks -> the box still comes
local notes = {}
local push0 = pushNote
pushNote = function(title, msg) notes[#notes + 1] = tostring(title) end
local nowE = os.epoch("utc")
BASE_ALIVE = { offs = { { from = nowE - 3600000, to = nowE - 5000, why = "server restart" } } }
AWAY.on, AWAY.startChecked = false, nil
state.online, state.t.players = nil, nil
AWAY.tick()                                          -- cannot tell yet
online = { "Alaory" } refreshPlayers(true)
AWAY.tick()
local box = false
for _, n in ipairs(notes) do if n == "WHILE YOU WERE AWAY" then box = true end end
CHECK(box, "the 'base was off' box after a restart")
pushNote = push0

-- offline, but the map is still loading: away mode waits
online = {} refreshPlayers(true)
AWAY.lastSeen = os.epoch("utc") - 3600000
local loaded = MAP.loaded
MAP.loaded = false
AWAY.tick()
CHECK(not AWAY.on, "away mode waits until the map is read")
MAP.loaded = true
AWAY.tick()
CHECK(AWAY.on, "away mode starts once the map is read")
MAP.loaded = loaded

-- storage helpers on the cable
local PC = {
  computer_1 = { id = 31, label = "Store 31", on = false },        -- used before, off
  computer_2 = { id = 42, label = "Store 42", on = false },        -- labelled as a helper, off
  computer_3 = { id = 33, label = "Store 33", on = true },         -- on, answers
  computer_4 = { id = 50, label = "Farm control", on = false },    -- someone else's
  computer_5 = { id = 60, label = "Store 60", on = true },         -- used before, on, silent
}
STORE.known = { [31] = true, [60] = true, [33] = true }
STORE.kicked = {}
local reboots = {}
peripheral.getNames = function() local o = {} for k in pairs(PC) do o[#o + 1] = k end table.sort(o) return o end
peripheral.hasType = function(n, t) return PC[n] ~= nil and t == "computer" end
peripheral.call = function(n, m) local c = PC[n]
  if m == "isOn" then return c.on elseif m == "turnOn" then c.on = true return
  elseif m == "reboot" then reboots[#reboots + 1] = c.id return
  elseif m == "getID" then return c.id elseif m == "getLabel" then return c.label end end
local nW = STORE.wakeAll()
CHECK(nW == 2 and PC.computer_1.on and PC.computer_2.on, "the 2 helpers that were off are turned on")
CHECK(not PC.computer_4.on, "someone else's computer is left alone")
STORE.helpers = { [33] = { id = 33 } }               -- only 33 answered
local nK = STORE.kickSilent()
CHECK(nK == 1 and reboots[1] == 60, "the silent helper (on, not answering) is restarted - only that one")
CHECK(STORE.kickSilent() == 0, "not again within 10 minutes")
