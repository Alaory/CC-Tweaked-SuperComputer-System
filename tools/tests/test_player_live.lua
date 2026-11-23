-- PLAYERS EVERY TICK (the owner: "make the player list update each tick since it doesn't cause lag"): its own
-- worker (playerWorker) reads the Player Detector again one tick after each reading; it never asks the screen to
-- redraw (the screen has its own timer) - 20 redraws a second would be lag.
local isrc = io.open(SRC_DIR .. "/inventory.lua"):read("a")
CHECK(isrc:find("playerWorker[,)]"), "inventory.lua starts playerWorker")
local reads, redraws, waits = 0, 0, {}
local det0, wf0, qe0 = det, waitFor, os.queueEvent
det = { getOnlinePlayers = function() reads = reads + 1 return { "Alaory", "Bob" } end,
        getPlayer = function(n) return { x = 10, y = 70, z = reads, dimension = "minecraft:overworld" } end }
os.queueEvent = function(e, ...) if e == "inv_update" then redraws = redraws + 1 end return qe0(e, ...) end
local n = 0
waitFor = function(t) waits[#waits + 1] = t n = n + 1 CLOCK = CLOCK + t if n >= 20 then state.running = false end end
state.running = true
playerWorker()
state.running = true
CHECK(reads == 20, "20 readings in 20 rounds (" .. reads .. ")")
CHECK(waits[1] == 0.05, "one tick between readings (" .. tostring(waits[1]) .. " s)")
CHECK(redraws == 0, "no redraw asked for (" .. redraws .. ")")
local bob
for _, e in ipairs(state.players or {}) do if e.name == "Bob" then bob = e end end
CHECK(bob and bob.p and bob.p.z == 20, "state.players has the newest reading")
-- no detector: it waits quietly (no busy loop)
det, n, waits = nil, 0, {}
state.running = true
playerWorker()
state.running = true
CHECK(waits[1] == 5, "no Player Detector: checks again every 5 s, nothing read")
det, waitFor, os.queueEvent = det0, wf0, qe0
