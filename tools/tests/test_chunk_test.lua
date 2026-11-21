-- CHUNK TEST (the owner: "some copy turtles can still load their chunks - I think they were mistaken for the copy ones
-- instead of the original ones. Add some way to test if a turtle can load chunks when they ping-pong and no turtles,
-- players or force-loaded chunks are near them"). A turtle only answers from a chunk the server runs: answering for
-- 3 min with nothing else near it = its own Chunky does it (TT.chunkCheck / TT.chunkProve / TT.chunkTick).
local HOME = { x = 0, y = 70, z = 0 }
CONFIG.drone.home = HOME
MAP.auto = { on = false }
state.online = { alaory = true }
state.players = { { name = "Alaory", p = { x = 5, y = 70, z = 5 }, dim = DRONE_DIM } }
local function mk(id, x, z)
  state.turtles[id] = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 50000, task = "idle",
    pos = { x = x, y = 70, z = z or 0 }, home = { x = 2, y = 70, z = 2 }, lastSeen = os.clock(), seenEpoch = os.epoch("utc") }
  return state.turtles[id]
end
local function sentTo(id, cmd)
  local n = 0
  for _, o in ipairs(state.tOut) do if o.id == id and o.msg.cmd == cmd then n = n + 1 end end
  return n
end
-- a report every 30 s (what TT.receive does: lastSeen, then the check)
local function reports(list, secs)
  for _ = 1, math.floor(secs / 30) do
    CLOCK = CLOCK + 30
    for _, t in ipairs(list) do t.lastSeen = os.clock() TT.chunkCheck(t) end
  end
end
local src = io.open(SRC_DIR .. "/base_turtles.lua"):read("a")
CHECK(src:find("pcall(TT.chunkCheck, t)", 1, true), "every turtle report is checked (TT.receive)")
CHECK(io.open(SRC_DIR .. "/base_workers.lua"):read("a"):find("TT.chunkTick", 1, true), "the comms worker pings (TT.chunkTick)")

-- 1) a copy far out, alone, its twin OFFLINE: it holds the shared Chunky -> it moves, the twin stays
state.turtles, state.tOut = {}, {}
local real = mk(7, 3000)
real.lastSeen = os.clock() - 9999                         -- offline (frozen)
local copy = mk(100007, -2500, 800)
CHECK(TT.copyStays(copy) and not TT.copyStays(real), "before: the copy stays put, the real one may move")
reports({ copy }, 120)
CHECK(TT.copyStays(copy), "2 min alone: not decided yet")
reports({ copy }, 90)
CHECK(not TT.copyStays(copy) and copy.ownChunky, "3+ min answering alone, twin offline: the copy holds the Chunky - it may move")
CHECK(real.chunkyLent == 100007 and TT.copyStays(real), "... and the twin stays put now (its copy holds the Chunky)")
CHECK(TT.idleWhy(real):find("holds the shared Chunky", 1, true), "the twin's card says why: " .. tostring(TT.idleWhy(real)))
local hasReal = false
for _, id in ipairs(TT.available()) do if id == 7 then hasReal = true end end
CHECK(not hasReal, "the twin gets no moving jobs now")
-- saved
TT.saveList()
state.turtles = {}
TT.loadList()
CHECK(state.turtles[7] and state.turtles[7].chunkyLent == 100007 and state.turtles[100007].ownChunky, "kept in turtles.dat")
real, copy = state.turtles[7], state.turtles[100007]
-- the twin later answers alone too (while the copy does): two Chunkies - both free
real.lastSeen, copy.lastSeen = os.clock(), os.clock()
copy.loadsSelf = nil
reports({ real, copy }, 210)
CHECK(not real.chunkyLent and not TT.copyStays(real) and not TT.copyStays(copy), "both answer alone at once: two Chunkies, both move")

-- 2) both online and alone from the start: the copy has its own Chunky
state.turtles = {}
local r2, c2 = mk(8, 4000), mk(100008, -4000)
reports({ r2, c2 }, 210)
CHECK(c2.ownChunky and not r2.chunkyLent, "copy + twin both answering alone: the copy has its own Chunky (" .. tostring(c2.chunkyProof) .. ")")

-- 3) NOT alone: nothing proven (another reason keeps its chunk running)
state.turtles = {}
local r3 = mk(9, 3000)
r3.lastSeen = os.clock() - 9999
local nearPlayer = mk(100009, 60, 60)                      -- 60 blocks from Alaory
local nearBase = mk(200009, 100, -90)                      -- (Alaory moved away below)
reports({ nearPlayer }, 300)
CHECK(TT.copyStays(nearPlayer) and tostring(nearPlayer.chunkWhy):find("Alaory", 1, true), "a player near it: nothing proven (" ..
      tostring(nearPlayer.chunkWhy) .. ")")
state.players[1].p = { x = 5000, y = 70, z = 5000 }
reports({ nearBase }, 300)
CHECK(TT.copyStays(nearBase) and tostring(nearBase.chunkWhy):find("from the base", 1, true), "near the base: nothing proven (" ..
      tostring(nearBase.chunkWhy) .. ")")
local a, b = mk(300009, -3000, -3000), mk(5, -3020, -3010)
reports({ a, b }, 300)
CHECK(TT.copyStays(a) and tostring(a.chunkWhy):find("T5", 1, true), "another online turtle near it: nothing proven (" .. tostring(a.chunkWhy) .. ")")
CONFIG.turtles.loadedAreas = { { x = 8000, z = 8000, r = 64 } }
local fl = mk(400009, 8010, 7990)
reports({ fl }, 300)
CHECK(TT.copyStays(fl) and tostring(fl.chunkWhy):find("force-loaded", 1, true), "in a force-loaded area: nothing proven")
CONFIG.turtles.loadedAreas = nil
-- an unknown player position (online, overworld) = maybe near
state.players[1].p = nil
local unk = mk(500009, -6000, 100)
reports({ unk }, 300)
CHECK(TT.copyStays(unk), "a player whose position is not known: nothing proven (" .. tostring(unk.chunkWhy) .. ")")
state.players[1].p = { x = 5000, y = 70, z = 5000 }
-- a player in another dimension does not count
state.players[1].dim = "minecraft:the_nether"
state.players[1].p = { x = -6000, y = 70, z = 100 }
unk.alone = nil
reports({ unk }, 210)
CHECK(not TT.copyStays(unk), "a player in the Nether at the same x z does not load it: proven")
state.players[1].dim, state.players[1].p = DRONE_DIM, { x = 5000, y = 70, z = 5000 }
-- a silent gap (frozen for a while) starts the count again
local gap = mk(600009, -7000, 0)
reports({ gap }, 150)
CLOCK = CLOCK + 600
reports({ gap }, 60)
CHECK(TT.copyStays(gap), "a long silence in between: counting starts again")

-- 4) ping-pong: an undecided copy that is alone is pinged every 20 s; one near a player is not
state.turtles, state.tOut = {}, {}
state.players[1].p = { x = 0, y = 70, z = 0 }
local pa, pn = mk(100011, -5000, 0), mk(100012, 20, 20)
TT.chunkCheck(pa) TT.chunkCheck(pn)
for _ = 1, 6 do CLOCK = CLOCK + 10 pa.lastSeen, pn.lastSeen = os.clock(), os.clock() TT.chunkTick() end
CHECK(sentTo(100011, "ping") == 3, "an alone copy is pinged every 20 s (" .. sentTo(100011, "ping") .. ")")
CHECK(sentTo(100012, "ping") == 0, "a copy next to a player is not (nothing to learn)")
-- the console
local out = table.concat(handleCommand("turtle 100011 chunktest"), "\n")
CHECK(out:find("CHUNK TEST", 1, true) and out:find("Now:", 1, true), "turtle <id> chunktest explains it:\n" .. out)
local nc = mk(13, -9000, 0)
handleCommand("turtle 13 chunktest")
state.tOut = {}
CLOCK = CLOCK + 25
nc.lastSeen = os.clock()
TT.chunkCheck(nc)
TT.chunkTick()
CHECK(sentTo(13, "ping") == 1, "chunktest on any turtle: pinged too")
state.turtles, state.tOut = {}, {}
