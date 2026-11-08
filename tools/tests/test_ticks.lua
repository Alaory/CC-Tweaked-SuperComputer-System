-- Every background job of the base, many times, in a messy world - WITHOUT the
-- pcall the workers wrap them in (in the game an error there is swallowed: the
-- feature just silently stops). Also every page draws in between.
local HOME = { x = -5292, y = 68, z = 10839 }
CONFIG.drone.home = HOME
state.owner = "Alaory"
local now = os.epoch("utc")
local function T(id, fields)
  local t = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 9000, pos = { x = HOME.x + id, y = 70, z = HOME.z },
              home = { x = HOME.x + id, y = 70, z = HOME.z }, task = "idle", lastSeen = os.clock(), seenEpoch = now }
  for k, v in pairs(fields or {}) do t[k] = v end
  state.turtles[id] = t
  return t
end
state.turtles = {}
T(21) T(22, { task = "survey: spot 3/9" }) T(23, { stuck = "blocked", stuckPos = { x = HOME.x + 23, y = 70, z = HOME.z } })
T(24, { held = true }) T(25, { fuel = 5 }) T(26, { lastSeen = os.clock() - 9999, seenEpoch = now - 4000000 })
T(27, { missing = now, lastSeen = nil, seenEpoch = now - 9000000 }) T(28, { rescuerRole = true, gear = "pickaxe, drive, floppy" })
T(29, { anchor = true }) T(30, { home = nil }) T(31, { recall = true, task = "survey: going" })
T(32, { task = "planning a route", movedAt = os.clock() - 500, taskAt = os.clock() - 500 })
-- a survey running, a work area, players around (a stranger near a turtle)
CONFIG.map.areaA, CONFIG.map.areaB = { x = -6000, y = 0, z = 10000 }, { x = -4500, y = 0, z = 11500 }
MAP.auto = { on = true, cursor = 0 }
MAP.queue = nil
MAP.queueSurvey(-6000, 10000, -4500, 11500, 8, nil)
state.players = { { name = "Alaory", isOwner = true, p = { x = HOME.x, y = 70, z = HOME.z }, dim = "minecraft:overworld" },
                  { name = "Stranger", p = { x = HOME.x + 30, y = 70, z = HOME.z }, dim = "minecraft:overworld" } }
state.online, state.onlineT = { alaory = true, stranger = true }, os.clock()
state.t.players = os.clock()
-- mining: a team, one miner gone
MINE.units = {
  [10] = { id = 10, role = "loader", dim = "overworld", label = "L", running = true, partner = 11, team = { 11, 12 }, ci = 3,
           lastSeen = os.clock(), seenEpoch = now, log = {}, queue = {}, fuel = 50000, task = "chunk 3" },
  [11] = { id = 11, role = "miner", dim = "overworld", label = "M1", leader = 10, partner = 10, running = true, idx = 1,
           lastSeen = os.clock(), seenEpoch = now, log = {}, queue = {}, fuel = 9000, stats = { ores = 50, dumps = 1 } },
  [12] = { id = 12, role = "miner", dim = "overworld", label = "M2", leader = 10, partner = 10, running = true, idx = 2,
           lastSeen = os.clock() - 9999, seenEpoch = now - 3600000, log = {}, queue = {}, fuel = 9000 } }
-- the factory wants more turtles; a pocket is paired
CONFIG.factory = { target = 20 }
FACTORY.chest, FACTORY.builder = "minecraft:chest_9", 28
POCKET.pockets = { [55] = { key = "k", name = "P", lastN = 0 } }

local JOBS = {
  { "MAP.feedSurvey", function() MAP.feedSurvey() end }, { "TT.updateTick", function() TT.updateTick() end },
  { "TT.stopTick", function() TT.stopTick() end }, { "TT.patrolTick", function() TT.patrolTick() end },
  { "TT.homeTick", function() TT.homeTick() end }, { "TT.avoidTick", function() TT.avoidTick() end },
  { "TT.stallTick", function() TT.stallTick() end }, { "MAP.autoTick", function() MAP.autoTick() end },
  { "AWAY.tick", function() AWAY.tick() end }, { "FACTORY.tick", function() FACTORY.tick() end },
  { "TT.saveList", function() TT.saveList() end }, { "baseAliveTick", function() baseAliveTick() end },
  { "sysRefresh", function() sysRefresh() end }, { "parkCheck", function() parkCheck() end },
  { "MAP.save", function() MAP.save() end }, { "MAP.checkSpace", function() MAP.checkSpace() end },
  { "MAP.autoSave", function() MAP.autoSave() end }, { "KNOW.save", function() KNOW.save() end },
  { "MINE.save", function() MINE.save() end }, { "SCHEM.processPending", function() SCHEM.processPending() end },
  { "POCKET.status", function() POCKET.status() end }, { "TT.codeLoad", function() TT.codeLoad() end },
}
local PAGES = { "inventory", "players", "drone", "access", "turtles", "drive", "map", "mining", "system", "events", "settings", "me" }
local failed = {}
for round = 1, 40 do
  CLOCK = CLOCK + 2
  for _, j in ipairs(JOBS) do
    local ok, err = pcall(j[2])
    if not ok and not failed[j[1]] then
      failed[j[1]] = true
      CHECK(false, j[1] .. " (round " .. round .. "): " .. tostring(err))
    end
  end
  -- the owner leaves half way: away mode
  if round == 20 then
    state.online = { stranger = true }
    state.players = { state.players[2] }
    AWAY.lastSeen = os.epoch("utc") - 3600000
  end
  if round % 8 == 0 then
    for _, pg in ipairs(PAGES) do
      state.page = pg
      local ok, err = pcall(draw)
      if not ok and not failed["page " .. pg] then
        failed["page " .. pg] = true
        CHECK(false, "page " .. pg .. " (round " .. round .. "): " .. tostring(err))
      end
    end
  end
end
CHECK(next(failed) == nil, "every background job and page ran without an error")
CHECK(AWAY.on, "away mode started when the owner left")
