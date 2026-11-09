-- Turtle factory with a fake ME network: parts in stock, parts crafted first,
-- a missing pattern, a failed build (exactly the parts go back), fleet full,
-- a MISSING turtle is replaced.
local function setup(mode)
  local ME = { ["computercraft:turtle_advanced"] = 1, ["computercraft:wireless_modem_advanced"] = 2,
               ["advancedperipherals:geo_scanner"] = 1, ["advancedperipherals:chunk_controller"] = 1,
               ["minecraft:diamond_pickaxe"] = 3, ["minecraft:coal_block"] = 64 }
  local CRAFTABLE, CRAFTS, CHEST = {}, {}, {}
  if mode == "craft" then
    ME["computercraft:turtle_advanced"], ME["advancedperipherals:geo_scanner"] = 0, 0
    CRAFTABLE["computercraft:turtle_advanced"], CRAFTABLE["advancedperipherals:geo_scanner"] = true, true
  end
  if mode == "missing" then ME["advancedperipherals:chunk_controller"] = 0 end
  bridgeKind = "ME"
  bridge = {
    getItem = function(f)
      local it = { name = f.name, amount = ME[f.name] or 0, isCraftable = CRAFTABLE[f.name], fingerprint = "FP-" .. f.name,
                   components = { ["minecraft:damage"] = 0, ["minecraft:enchantments"] = { levels = {} } } }   -- plain (defaults)
      if mode == "own" and f.name == "minecraft:diamond_pickaxe" then
        it.components["minecraft:enchantments"] = { levels = { ["minecraft:efficiency"] = 5 } }               -- YOUR pickaxe
      end
      return it
    end,
    isItemCraftable = function(f) return CRAFTABLE[f.name] or false end,
    craftItem = function(f) CRAFTS[#CRAFTS + 1] = f.name return true end,
    exportItem = function(f) FPS = FPS or {} FPS[#FPS + 1] = f.fingerprint
                             local n = math.min(f.count, ME[f.name] or 0) ME[f.name] = ME[f.name] - n
                             CHEST[f.name] = (CHEST[f.name] or 0) + n return n end,
    importItem = function(f) local n = math.min(f.count, CHEST[f.name] or 0) CHEST[f.name] = CHEST[f.name] - n
                             ME[f.name] = (ME[f.name] or 0) + n return n end,
  }
  peripheral.isPresent = function(n) return n == "minecraft:chest_9" end
  local call0 = peripheral.call
  peripheral.call = function(n, m)
    if n == "minecraft:chest_9" and m == "list" then
      local l, i = {}, 0
      for k, v in pairs(CHEST) do if v > 0 then i = i + 1 l[i] = { name = k, count = v } end end
      return l
    end
    return call0(n, m)
  end
  CONFIG.factory = { target = 3 }
  state.turtles = {
    [1] = { id = 1, label = "Builder", log = {}, lastN = 0, fuel = 9000, pos = { x = 0, y = 70, z = 0 }, task = "idle",
            lastSeen = os.clock(), rescuerRole = true, home = { x = 0, y = 70, z = 0 } },
    [2] = { id = 2, label = "S2", log = {}, lastN = 0, fuel = 9000, pos = { x = 5, y = 70, z = 0 }, task = "idle", lastSeen = os.clock() } }
  FACTORY.job, FACTORY.fails, FACTORY.waitUntil, FACTORY.built, FACTORY.last, FACTORY.lastMissing = nil, 0, nil, 0, nil, nil
  FACTORY.leaving = nil
  FACTORY.chest, FACTORY.builder = "minecraft:chest_9", nil
  return ME, CRAFTABLE, CRAFTS, CHEST
end
local function run(mode, onBuild, steps)
  local ME, CRAFTABLE, CRAFTS, CHEST = setup(mode)
  local sent = {}
  local send0 = TT.send
  TT.send = function(id, c, ...) sent[#sent + 1] = c return send0(id, c, ...) end
  local done = false
  for step = 1, steps or 12 do
    CLOCK = CLOCK + 11
    for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
    FACTORY.tick()
    if mode == "craft" and step == 4 then ME["computercraft:turtle_advanced"], ME["advancedperipherals:geo_scanner"] = 1, 1 end
    if FACTORY.job and FACTORY.job.step == "building" and not done then
      done = true
      onBuild(CHEST)
    end
  end
  TT.send = send0
  return ME, CRAFTS, CHEST, table.concat(sent, ",")
end

-- parts in stock: built
local ME, CRAFTS, CHEST, sent = run("stock", function(chest)
  for k in pairs(chest) do chest[k] = nil end
  FACTORY.result(1, true, "built turtle 7")
end)
CHECK(sent:find("build"), "stock: the builder is sent")
CHECK(#CRAFTS == 0, "stock: nothing crafted")
CHECK(FACTORY.built == 1 and FACTORY.last and FACTORY.last.id == 7, "stock: turtle 7 built")
CHECK(ME["computercraft:turtle_advanced"] == 0 and ME["minecraft:coal_block"] == 48, "stock: exactly one turtle's parts used")

-- parts crafted first
ME, CRAFTS = run("craft", function(chest)
  for k in pairs(chest) do chest[k] = nil end
  FACTORY.result(1, true, "built turtle 8")
end)
CHECK(#CRAFTS == 2, "craft: the 2 missing parts were ordered (" .. #CRAFTS .. ")")
CHECK(FACTORY.built == 1, "craft: built after crafting")

-- no pattern for the Chunky: nothing moved, you are told which
ME, CRAFTS, CHEST, sent = run("missing", function() end)
CHECK(not sent:find("build") and next(CHEST) == nil, "missing: nothing built, nothing moved")
CHECK(FACTORY.lastMissing and FACTORY.lastMissing[1].name == "advancedperipherals:chunk_controller", "missing: the Chunky is named")

-- the builder fails: exactly the parts go back into the ME network
ME, CRAFTS, CHEST = run("fail", function()
  FACTORY.result(1, false, "the spot for the new turtle is not free - the parts are back in the chest")
end)
local left = 0
for _, v in pairs(CHEST) do left = left + v end
CHECK(left == 0, "fail: the chest is empty again")
CHECK(ME["computercraft:turtle_advanced"] == 1 and ME["minecraft:coal_block"] == 64, "fail: every part back in the ME network")
CHECK(FACTORY.fails == 1, "fail: counted")

-- fleet full: nothing happens; a MISSING turtle does not count (it is replaced)
setup("stock")
CONFIG.factory.target = 2
CHECK(FACTORY.blocked() and FACTORY.blocked():find("complete"), "fleet of 2 = target 2: nothing to build")
state.turtles[2].missing = os.epoch("utc")
CHECK(FACTORY.blocked() == nil, "a MISSING turtle is replaced")
-- 3 failures in a row: it stops until  factory build
FACTORY.fails = 3
CHECK(FACTORY.blocked() and FACTORY.blocked():find("3 failed"), "stops after 3 failures")

-- plain items with default entries (damage 0, no enchantments) are fine; they are asked for by fingerprint
FPS = {}
run("stock", function(chest) for k in pairs(chest) do chest[k] = nil end FACTORY.result(1, true, "built turtle 9") end)
CHECK(FACTORY.built == 1, "plain items (default damage 0 / empty enchantments) are taken")
CHECK(#FPS == 6 and FPS[1] == "FP-computercraft:turtle_advanced", "exported by fingerprint (exactly the item looked at)")

-- your OWN enchanted pickaxe in the ME network: not taken, everything back
ME, CRAFTS, CHEST, sent = run("own", function() end)
CHECK(not sent:find("build"), "own pickaxe: no build")
CHECK(FACTORY.lastMissing and FACTORY.lastMissing[1].name == "minecraft:diamond_pickaxe",
      "own pickaxe only: it counts as missing (never taken), named")
CHECK(ME["minecraft:diamond_pickaxe"] == 3 and ME["computercraft:turtle_advanced"] == 1, "own pickaxe: every part back in the ME network")

-- YOUR used pickaxe AND a plain one in AE2 (two versions): the plain one is taken
do
  local ME, CRAFTABLE, CRAFTS, CHEST = setup("stock")
  bridge.getItems = function(f)
    if f.name == "minecraft:diamond_pickaxe" then
      return { { name = f.name, amount = 1, fingerprint = "FP-USED", components = { ["minecraft:damage"] = 412 } },
               { name = f.name, amount = 2, fingerprint = "FP-NEW", components = { ["minecraft:damage"] = 0 } } }
    end
    return { bridge.getItem(f) }
  end
  FPS = {}
  local sent = {}
  local send0 = TT.send
  TT.send = function(id, c, ...) sent[#sent + 1] = c return send0(id, c, ...) end
  for _ = 1, 6 do CLOCK = CLOCK + 11 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end FACTORY.tick() end
  TT.send = send0
  local usedNew = false
  for _, fp in ipairs(FPS) do if fp == "FP-NEW" then usedNew = true end if fp == "FP-USED" then usedNew = false break end end
  CHECK(usedNew and table.concat(sent, ","):find("build", 1, true), "your used pickaxe + a plain one: the PLAIN one goes into the turtle")
  local rows = FACTORY.check()
  local pick
  for _, r in ipairs(rows) do if r.part.name == "minecraft:diamond_pickaxe" then pick = r end end
  CHECK(pick and pick.own == 1, "check: your used one is counted apart (" .. tostring(pick and pick.own) .. ")")
  bridge.getItems = nil
end

-- the builder is out (not at its home next to the chest): sent home first
setup("stock")
state.turtles[1].pos = { x = 40, y = 70, z = 9 }
local sent2 = {}
local send0 = TT.send
TT.send = function(id, c, ...) sent2[#sent2 + 1] = c return send0(id, c, ...) end
FACTORY.sentHome = nil
CLOCK = CLOCK + 11
FACTORY.tick()
TT.send = send0
CHECK(FACTORY.job == nil and table.concat(sent2, ","):find("home"), "builder away: sent home, no build yet")
state.turtles[1].home = nil
CHECK(FACTORY.blocked() and FACTORY.blocked():find("no home"), "builder without a home: told")

-- TAUGHT recipe: no Chunky in stock and no AE2 pattern, but the CRAFTER learned
-- it (8 iron around an ender pearl). Iron is out of stock but AE2 can craft it.
do
  local ME, CRAFTABLE, CRAFTS, CHEST = setup("missing")
  ME["minecraft:iron_ingot"], ME["minecraft:ender_pearl"] = 0, 1
  CRAFTABLE["minecraft:iron_ingot"] = true
  state.turtles[3] = { id = 3, label = "Crafty", log = {}, lastN = 0, fuel = 9000, pos = { x = 1, y = 70, z = 0 },
                       home = { x = 1, y = 70, z = 0 }, task = "idle", lastSeen = os.clock(),
                       gear = "L=wireless_modem_advanced R=crafting_table,crafter" }
  FACTORY.recipes = {}
  FACTORY.learned(3, { out = "advancedperipherals:chunk_controller", count = 1,
    grid = { "minecraft:iron_ingot", "minecraft:iron_ingot", "minecraft:iron_ingot", "minecraft:iron_ingot",
             "minecraft:ender_pearl", "minecraft:iron_ingot", "minecraft:iron_ingot", "minecraft:iron_ingot",
             "minecraft:iron_ingot" } })
  CHECK(FACTORY.recipes["advancedperipherals:chunk_controller"], "learned recipe kept")
  CONFIG.factory.target = 4                             -- (3 turtles now: the crafter counts too)
  local sent, craftArgs = {}, nil
  local send0 = TT.send
  TT.send = function(id, c, a, ...) sent[#sent + 1] = id .. ":" .. c if c == "craft" then craftArgs = a end return send0(id, c, a, ...) end
  local built = false
  for step = 1, 20 do
    CLOCK = CLOCK + 11
    for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
    FACTORY.tick()
    if step == 2 then ME["minecraft:iron_ingot"] = 8 end           -- AE2 finished the iron
    local j = FACTORY.job
    if j and j.step == "tcraft" and CHEST["minecraft:iron_ingot"] == 8 then
      -- the crafter does its job: the ingredients become one Chunky in the chest
      CHEST["minecraft:iron_ingot"], CHEST["minecraft:ender_pearl"] = 0, 0
      CHEST["advancedperipherals:chunk_controller"] = 1
      FACTORY.craftResult(3, true, "crafted 1 advancedperipherals:chunk_controller")
    end
    if j and j.step == "building" and not built then
      built = true
      for k in pairs(CHEST) do CHEST[k] = nil end
      FACTORY.result(1, true, "built turtle 11")
    end
  end
  TT.send = send0
  local s = table.concat(sent, ",")
  local orderedIron = false
  for _, n in ipairs(CRAFTS) do if n == "minecraft:iron_ingot" then orderedIron = true end end
  CHECK(orderedIron, "taught: AE2 was asked for the iron (an ingredient it can craft)")
  CHECK(s:find("3:craft", 1, true) and craftArgs and craftArgs[1]:find("minecraft:ender_pearl", 1, true) and craftArgs[2] == 1,
        "taught: the crafter got the recipe (" .. s .. ")")
  CHECK(built and FACTORY.last and FACTORY.last.id == 11, "taught: the turtle was built with the crafted Chunky")
  CHECK(ME["minecraft:ender_pearl"] == 0 and ME["minecraft:iron_ingot"] == 0, "taught: exactly the ingredients were used")
  -- the planner on its own: nested taught recipes, and something nobody can make
  FACTORY.recipes["minecraft:ender_pearl"] = { grid = { "", "", "", "", "minecraft:gold_ingot", "", "", "", "" }, count = 1 }
  ME["minecraft:ender_pearl"], ME["minecraft:gold_ingot"] = 0, 0
  local p = FACTORY.plan("advancedperipherals:chunk_controller", 1, {})
  CHECK(#p.crafts == 2 and p.crafts[1].name == "minecraft:ender_pearl" and p.crafts[2].name == "advancedperipherals:chunk_controller",
        "plan: the ingredient's own recipe first")
  CHECK(#p.missing == 1 and p.missing[1] == "minecraft:gold_ingot", "plan: what nobody can make is named")
  FACTORY.recipes = {}
end

-- a barrel the base already uses (the AE2 item buffer) is never the factory chest
CONFIG.me = CONFIG.me or {}
local oldBuf = CONFIG.me.buffer
CONFIG.me.buffer = "minecraft:chest_9"
setup("stock")
CHECK(FACTORY.blocked() and FACTORY.blocked():find("AE2 buffer", 1, true), "the AE2 buffer as factory chest: refused, told why")
CONFIG.me.buffer = oldBuf
CHECK(FACTORY.reserved("minecraft:barrel_77") == nil, "any other barrel is fine")

-- factory fuel <item> [count]: the fuel a new turtle gets (saved in settings.dat)
handleCommand("factory fuel minecraft:charcoal 8")
local fp = FACTORY.parts()[6]
CHECK(fp.name == "minecraft:charcoal" and fp.count == 8, "factory fuel: charcoal x8 (" .. fp.name .. " x" .. fp.count .. ")")
CHECK(SETTINGS["factory.fuel"] == "minecraft:charcoal", "factory fuel: saved as a setting (base_config.lua untouched)")
handleCommand("factory fuel reset")
fp = FACTORY.parts()[6]
CHECK(fp.name == "minecraft:coal_block" and fp.count == 16, "factory fuel reset: back to 16 coal blocks")

-- the NEW turtle stands on the build spot: never offered it as its home, sent
-- home, and the next build waits until it has left the spot
do
  setup("stock")
  CONFIG.factory.target = 9
  FACTORY.job = { step = "building", builder = 1, t = os.epoch("utc") }
  FACTORY.result(1, true, "built turtle 40")           -- (builder 1, home 0 70 0)
  state.turtles[40] = { id = 40, label = "New", log = {}, lastN = 0, fuel = 900, pos = { x = 0, y = 70, z = 1 },
                        task = "idle", lastSeen = CLOCK }
  local x, y, z = TT.homeSpot(state.turtles[40])
  CHECK(x and not (math.abs(x) + math.abs(z) <= 1 and y == 70), "no home offered next to the builder (" ..
        tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. ")")
  state.turtles[40].home = { x = 30, y = 70, z = 30 }
  local sent = {}
  local send0 = TT.send
  TT.send = function(id, c, ...) sent[#sent + 1] = id .. ":" .. c return send0(id, c, ...) end
  FACTORY.waitUntil = nil
  for _ = 1, 3 do CLOCK = CLOCK + 11 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end FACTORY.tick() end
  CHECK(table.concat(sent, ","):find("40:home", 1, true), "the new turtle is sent home")
  CHECK(FACTORY.job == nil and not table.concat(sent, ","):find("1:build", 1, true), "no next build while it is on the spot")
  CHECK(FACTORY.statusLine():find("leave", 1, true), "the status says why it waits")
  -- the home trip fails (walls around the build spot): after 3 min you are told why
  do
    local m = { t = "result", cmd = "home", ok = false, msg = "no way found to 30 70 30", n = os.epoch("utc") + 5000 }
    m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
    TT.receive(40, m)
  end
  local notes0 = #(NOTES or {})
  local said
  local push0 = pushNote
  pushNote = function(kind, msg, ...) if tostring(msg):find("cannot leave the build spot", 1, true) then said = msg end
                                      return push0(kind, msg, ...) end
  for _ = 1, 20 do CLOCK = CLOCK + 11 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end FACTORY.tick() end
  pushNote = push0
  CHECK(said and said:find("no way found", 1, true), "stuck on the build spot: you are told why (" .. tostring(said) .. ")")
  CHECK(FACTORY.statusLine():find("no way found", 1, true), "the status line says why too")
  -- the new turtle gets the turtle program update AT ONCE, even while you play
  -- (the builder's floppy may hold an old one); others still wait
  do
    local code0, cfg0, own0 = CODE, CONFIG.turtles.autoUpdate, AWAY.ownerOnline
    CODE = { ver = "NEWVER", pieces = { "a" }, text = "x" }
    CONFIG.turtles.autoUpdate = true
    AWAY.ownerOnline = function() return true end
    local aw0 = AWAY.on AWAY.on = false
    TT.codeSeenVer, TT.codeSeenAt = CODE.ver, os.clock()
    TT.sending = {}
    for _, t in pairs(state.turtles) do t.ver, t.updReady, t.updRetry = "OLD", nil, nil end
    local pushed = {}
    local pc0 = TT.pushCode
    TT.pushCode = function(id) pushed[#pushed + 1] = id return true end
    TT.updateTick()
    TT.pushCode = pc0
    CHECK(#pushed == 1 and pushed[1] == 40, "while you play only the new turtle is updated (" .. table.concat(pushed, ",") .. ")")
    CODE, CONFIG.turtles.autoUpdate, AWAY.ownerOnline, AWAY.on = code0, cfg0, own0, aw0
    TT.sending = {}
  end
  state.turtles[40].pos = { x = 12, y = 70, z = 12 }        -- it has gone
  for _ = 1, 3 do CLOCK = CLOCK + 11 for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end FACTORY.tick() end
  CHECK(FACTORY.leaving == nil, "it left: the factory goes on")
  TT.send = send0
end

-- SPEED: everything in stock -> the builder gets "build" within 2 checks (3 s
-- apart while busy; before: parts / crafting / export = 3 checks 10 s apart),
-- and after a build only 5 s + the free spot, not 2 minutes
do
  setup("stock")
  local sentBuild
  local send0 = TT.send
  TT.send = function(id, c, ...) if c == "build" then sentBuild = true end return send0(id, c, ...) end
  local ticks = 0
  for _ = 1, 10 do
    CLOCK = CLOCK + 3
    for _, t in pairs(state.turtles) do t.lastSeen = CLOCK end
    FACTORY.tick()
    ticks = ticks + 1
    if sentBuild then break end
  end
  TT.send = send0
  -- (the first ~10 s = the idle check interval; the job then runs parts -> export ->
  -- build in ONE check)
  CHECK(sentBuild and ticks * 3 <= 12, "parts in stock: build sent after " .. ticks * 3 .. " s")
  FACTORY.result(1, true, "built turtle 77")
  CHECK(FACTORY.waitUntil - os.clock() <= 5, "after a build: only a short wait (then the free spot decides)")
  CHECK(tostring(FACTORY.last.msg):find(" in %d+ s"), "the build time is written down (" .. tostring(FACTORY.last.msg) .. ")")
end

-- the factory turtles stay at the factory: a HAND-PICKED builder and the crafter
-- get no survey batches, no search party, and say why they are idle
do
  setup("stock")
  state.turtles[1].rescuerRole = nil
  state.turtles[3] = { id = 3, label = "Crafty", log = {}, lastN = 0, fuel = 9000, pos = { x = 1, y = 70, z = 0 },
                       task = "idle", lastSeen = os.clock(), gear = "crafter" }
  FACTORY.builder, FACTORY.crafter = 1, nil
  local avail = table.concat(TT.available(), ",")
  CHECK(avail == "2", "factory builder + crafter get no survey work (available: " .. avail .. ")")
  CHECK(TT.factoryRole(state.turtles[1]) == "builder" and TT.factoryRole(state.turtles[3]) == "crafter"
        and TT.factoryRole(state.turtles[2]) == nil, "factory roles found")
  CHECK(tostring((TT.idleWhy(state.turtles[1]))):find("factory builder", 1, true), "idle reason names the factory builder")
  for _, t in pairs(state.turtles) do t.lastSeen = os.clock() end
  state.turtles[9] = { id = 9, label = "Lost", log = {}, lastN = 0, fuel = 9000, pos = { x = 200, y = 70, z = 0 },
                       task = "idle", lastSeen = os.clock() - 100000 }
  CONFIG.drone = CONFIG.drone or {}
  CONFIG.drone.home = CONFIG.drone.home or { x = 0, y = 70, z = 0 }
  local ok = pcall(TT.partyStart)
  CHECK(not state.turtles[1].party and not state.turtles[3].party, "factory turtles never join the search party")
  pcall(TT.partyStop)
  state.turtles[3], state.turtles[9] = nil, nil
  FACTORY.builder = nil
end
