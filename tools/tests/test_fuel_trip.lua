-- Low on fuel, idle: off to the shared fuel chest (one at a time) - but NOT a turtle that
-- carries ENDLESS fuel and tops itself up where it is (m.endless): those trips stopped its
-- top-up every 10 minutes. Out of fuel (< 20) the rescuer comes as before.
CONFIG.turtles.fuelChest = { x = 10, y = 64, z = 10 }
CONFIG.turtles.idleHome = 120
local sent = {}
local send0 = TT.send
TT.send = function(id, cmd, ...) sent[#sent + 1] = id .. ":" .. cmd return send0(id, cmd, ...) end
local function T(id, extra)
  local t = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 500, pos = { x = 100 + id, y = 70, z = 0 },
              home = { x = 0, y = 70, z = id }, task = "idle", lastSeen = os.clock() }
  for k, v in pairs(extra or {}) do t[k] = v end
  state.turtles[id] = t
  return t
end
state.turtles = {}
TT.fuelTrip = nil
T(1, { endless = true })
for _ = 1, 10 do CLOCK = CLOCK + 3 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end TT.homeTick() end
local any = table.concat(sent, " ")
CHECK(not any:find("1:fuelup", 1, true), "a turtle with endless fuel is not sent to the fuel chest (" .. any .. ")")
CHECK(not any:find("1:home", 1, true), "...nor home because of low fuel")
sent = {}
T(2)
for _ = 1, 10 do CLOCK = CLOCK + 3 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end TT.homeTick() end
any = table.concat(sent, " ")
CHECK(any:find("2:fuelup", 1, true), "a turtle without endless fuel goes to the fuel chest (" .. any .. ")")
-- the report field reaches the base
local bsrc = (io.open("base_turtles.lua") or io.open("../../base_turtles.lua")):read("a")
CHECK(bsrc:find("t.endless = m.endless", 1, true), "the base reads m.endless from the turtle's report")
TT.send = send0
