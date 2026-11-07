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
    getItem = function(f) return { name = f.name, amount = ME[f.name] or 0, isCraftable = CRAFTABLE[f.name] } end,
    isItemCraftable = function(f) return CRAFTABLE[f.name] or false end,
    craftItem = function(f) CRAFTS[#CRAFTS + 1] = f.name return true end,
    exportItem = function(f) local n = math.min(f.count, ME[f.name] or 0) ME[f.name] = ME[f.name] - n
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
            lastSeen = os.clock(), rescuerRole = true },
    [2] = { id = 2, label = "S2", log = {}, lastN = 0, fuel = 9000, pos = { x = 5, y = 70, z = 0 }, task = "idle", lastSeen = os.clock() } }
  FACTORY.job, FACTORY.fails, FACTORY.waitUntil, FACTORY.built, FACTORY.last, FACTORY.lastMissing = nil, 0, nil, 0, nil, nil
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
