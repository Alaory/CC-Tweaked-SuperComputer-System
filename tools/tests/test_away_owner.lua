-- AWAY MODE with the REAL Inventory Manager behaviour: getOwner() answers only while
-- the card's player is ON the server (Advanced Peripherals looks the player up). The
-- base forgot the owner the moment they logged off -> away mode "could not tell" and
-- never started (the owner saw it work once or twice in months). The other away tests
-- set state.owner by hand, so they never saw it.
local online = { "Alaory", "Bob" }
local ownerOn = true
inv = inv or {}
local inv0 = inv
inv = setmetatable({ getOwner = function() if ownerOn then return "Alaory" end return nil end,
                     list = function() if not ownerOn then error("player not online") end return {} end,
                     size = function() return 41 end }, { __index = inv0 })
det = { getOnlinePlayers = function() return online end,
        getPlayer = function(n) for _, o in ipairs(online) do if o == n then
          return { x = 1, y = 70, z = 2, dimension = "minecraft:overworld" } end end error("not online") end,
        getPlayersInRange = function() return online end }
pcall(fs.delete, OWNER_FILE)
OWNER_SAVED, state.owner = nil, nil
pcall(refreshInventory)
CHECK(state.owner == "Alaory", "the owner is read from the card while online")
refreshPlayers(true)
CHECK(AWAY.ownerOnline() == true, "online")
-- the owner logs off: getOwner() gives nil now
ownerOn, online = false, { "Bob" }
pcall(refreshInventory)
CHECK(state.owner == "Alaory", "the owner's name is kept while offline (" .. tostring(state.owner) .. ")")
CHECK(state.status == "owneroff", "status says the owner is offline (" .. tostring(state.status) .. ")")
refreshPlayers(true)
CHECK(AWAY.ownerOnline() == false, "the base can tell the owner is OFFLINE (" .. tostring(AWAY.ownerOnline()) .. ")")
AWAY.on, AWAY.offSince, AWAY.startChecked = false, nil, true
MAP.loaded = true
AWAY.tick()
CLOCK = CLOCK + 400
refreshPlayers(true)
pcall(refreshInventory)
AWAY.tick()
CHECK(AWAY.on, "away mode STARTS after 5 min offline")
-- a base restart while the owner is offline: the name comes from owner.dat
state.owner = nil
OWNER_SAVED = nil
do
  local t = readSafe(OWNER_FILE)
  OWNER_SAVED = type(t) == "table" and t.name or nil
end
CHECK(OWNER_SAVED == "Alaory", "owner.dat keeps the name over a restart")
pcall(refreshInventory)
CHECK(state.owner == "Alaory", "after a restart while offline the owner is still known")
-- back online: away mode ends with a report
local notes = {}
local push0 = pushNote
pushNote = function(title) notes[#notes + 1] = tostring(title) end
ownerOn, online = true, { "Alaory" }
pcall(refreshInventory)
refreshPlayers(true)
AWAY.tick()
pushNote = push0
CHECK(not AWAY.on and state.status ~= "owneroff", "back online: away mode off, inventory readable again")
local wb = false
for _, n in ipairs(notes) do if n == "WELCOME BACK" then wb = true end end
CHECK(wb, "the WELCOME BACK report comes")
inv = inv0
