-- MESSAGES FROM OUTSIDE (the owner: "go over every feature and check them"): turtles (node.lua), mining turtles
-- (miner.lua - old and new versions send different fields), the pocket computer. Real-looking SIGNED messages with
-- one to three fields broken (missing, a word for a number, a table for a word, huge, negative ...), plus garbage.
-- None may crash the base - and what they store must not break a page or a background job LATER either.
math.randomseed(1234)
local errors, seen = {}, {}
local function note(where, err)
  local k = where:gsub("%d+", "#") .. " | " .. tostring(err):gsub("%d+", "#")
  if not seen[k] then seen[k] = true errors[#errors + 1] = where .. ": " .. tostring(err) end
end
local function guarded(f, ...)
  local args = table.pack(...)
  debug.sethook(function() error("RUNS TOO LONG (endless loop?)") end, "", 5e7)
  local ok, r = pcall(f, table.unpack(args, 1, args.n))
  debug.sethook()
  return ok, r
end
local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
local ODD = { function() return nil end, function() return "abc" end, function() return "12" end, function() return {} end,
              function() return { "x", 2 } end, function() return true end, function() return -1 end, function() return 1e15 end,
              function() return 0 end, function() return { x = "a" } end, function() return math.huge end, function() return "" end }
local function odd() return ODD[math.random(1, #ODD)]() end
local SEQ = os.epoch("utc") + 1000
local function signed(m)
  SEQ = SEQ + 1
  m.n = SEQ
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  return m
end

-- 1) turtles: every message kind, realistic, then broken
local TYPES = { "status", "hello", "result", "scan", "look", "need", "homebad", "learn", "recipe", "rescued", "turtlesseen",
                "updmiss", "exitroute" }
local function turtleMsg(t)
  return { t = t, label = "Fuzz", task = "idle", fuel = 5000, fuelMax = 20000, items = 3, freeSlots = 10,
           pos = { x = HOME.x + 5, y = 70, z = HOME.z }, home = { x = HOME.x + 5, y = 70, z = HOME.z }, gear = "modem, scanner",
           ver = "abc", cmd = "goto", ok = true, msg = "done", scan = { x = HOME.x, y = 70, z = HOME.z, r = 8, cols = {} },
           seen = { { x = 1, y = 2, z = 3 } }, want = "fuel", recipe = { out = "minecraft:stick", count = 4, grid = {} },
           front = "minecraft:stone", up = false, down = "minecraft:dirt", walls = {}, route = {}, trail = {} }
end
local KEYS = {}
for k in pairs(turtleMsg("status")) do KEYS[#KEYS + 1] = k end
table.sort(KEYS)
for i = 1, 3000 do
  local id = math.random(1, 6)
  local m = turtleMsg(TYPES[math.random(1, #TYPES)])
  for _ = 1, math.random(1, 3) do m[KEYS[math.random(1, #KEYS)]] = odd() end
  local ok, err = guarded(TT.receive, id, signed(m))
  if not ok then note("turtle " .. m.t .. " msg", err) end
end
-- garbage: not a table, unsigned, wrong key, no number
for _, g in ipairs({ "hello", 42, {}, { t = "status" }, { t = "status", n = "x" }, { t = {}, n = 1 }, { t = "status", n = 1, sig = "bad" } }) do
  local ok, err = guarded(TT.receive, 3, g)
  if not ok then note("turtle garbage", err) end
end

-- 2) mining turtles: miner.lua reports (m.mine), old and new fields, broken
local function minerMsg(role)
  return { t = "status", mine = true, role = role, label = "Miner", dim = "overworld", task = "mining", fuel = 9000, fuelMax = 20000,
           free = 10, pos = { x = 1, y = 2, z = 3 }, partner = 1, running = true, ci = 2, li = 3, nl = 9, phase = "work",
           station = { x = 1, y = 2, z = 3 }, carry = { ["minecraft:coal"] = 3 }, got = { ["minecraft:iron_ore"] = 5 },
           stats = { ores = 10, dumps = 1 }, ver = "m25", rowLength = 8, team = { 2, 3 }, leader = 1, ready = false, idx = 1,
           transit = 0, code = "abcd", updReady = nil, nextDump = 300, notes = { "hello" }, lastCmd = 0, err = nil }
end
local MKEYS = {}
for k in pairs(minerMsg("miner")) do if k ~= "mine" and k ~= "t" then MKEYS[#MKEYS + 1] = k end end
table.sort(MKEYS)
for i = 1, 3000 do
  local id = 200 + math.random(1, 5)
  local m = minerMsg(math.random() < 0.3 and "loader" or "miner")
  for _ = 1, math.random(1, 3) do m[MKEYS[math.random(1, #MKEYS)]] = odd() end
  local ok, err = guarded(TT.receive, id, signed(m))
  if not ok then note("miner msg", err) end
end

-- 3) the pocket: paired, signed, every action with odd arguments; garbage too
local PID = 77
POCKET.pockets[PID] = { key = "fuzzkey", name = "Fuzz pocket", lastN = 0 }
local pn = os.epoch("utc") * 100
local ACTS = { "ride", "ridestop", "turtle", "drive", "forget", "minedrop", "party", "allhome", "allstop", "mine", "corner",
               "wholeworld", "surveyhere", "factoryretry", "updateall", "zzz" }
local ARGS = { {}, { "1" }, { "base" }, { "x", "y" }, { 5 }, { {} }, "notatable", { "stop" }, { "1", "stop" }, { "start" } }
for i = 1, 600 do
  pn = pn + 1
  local a = ACTS[math.random(1, #ACTS)]
  local args = ARGS[math.random(1, #ARGS)]
  local t = math.random() < 0.8 and "act" or "req"
  local m = { t = t, n = pn, a = a, args = args, pos = math.random() < 0.5 and { x = 1, y = 2, z = 3 } or odd() }
  m.sig = TT.sign("fuzzkey", m.t, m.n, m.a, type(m.args) == "table" and m.args or nil)
  local ok, err = guarded(POCKET.receive, PID, m)
  if not ok then note("pocket " .. t .. " " .. a .. " args " .. tostring(type(args) == "table" and #args or args), err) end
end
for _, g in ipairs({ "x", 5, {}, { t = "act" }, { t = "pairreq" }, { t = "pair", proof = "1" }, { t = "req", n = 1 } }) do
  local ok, err = guarded(POCKET.receive, 99, g)
  if not ok then note("pocket garbage", err) end
end

-- 4) what was stored must not break anything LATER: every page draws, every background job runs
local PAGES = { "home", "turtles", "drive", "map", "mining", "system", "events", "drone", "work", "players" }
for _, pg in ipairs(PAGES) do
  state.page = pg
  for _, id in ipairs({ 1, 2, 3, 4, 5, 6 }) do
    state.selTurtle, state.dsel = id, id
    local ok, err = guarded(draw)
    if not ok then note("page " .. pg .. " after the messages (turtle " .. id .. " picked)", err) end
  end
end
local JOBS = { "TT.updateTick", "TT.patrolTick", "TT.homeTick", "TT.avoidTick", "TT.stallTick", "TT.stopTick", "TT.partyTick",
               "MAP.feedSurvey", "MINE.updTick", "MINE.silentTick", "FACTORY.tick", "AWAY.tick", "TT.saveList", "MINE.save",
               "POCKET.status", "DW.tick" }
for round = 1, 5 do
  CLOCK = CLOCK + 30
  for _, j in ipairs(JOBS) do
    local f = _ENV
    for part in j:gmatch("[^%.]+") do f = f and f[part] end
    if type(f) == "function" then
      local ok, err = guarded(f)
      if not ok then note("job " .. j .. " after the messages", err) end
    end
  end
end
for _, t in ipairs({ "turtles", "mine" }) do
  local ok, out = guarded(handleCommand, t)
  if not ok then note("console '" .. t .. "' after the messages", out) end
end
CHECK(#errors == 0, #errors .. " problem(s):\n  " .. table.concat(errors, "\n  ", 1, math.min(#errors, 60)))
