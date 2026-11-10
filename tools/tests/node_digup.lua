-- node.lua's real digUp (MINE UP) + tryDig + natural in a one-column fake world.
--   lua5.3 tools/tests/node_digup.lua node.lua      (exit 1 when a check fails)
local NODE = arg[1] or "node.lua"
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(NODE):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a + 1, true)
  assert(a and b, "not found: " .. from)
  return src:sub(a, b - 1)
end
local code = piece("function natural(name)", "function isOre(b)") .. piece("function digUp(top)", "function runJob(j)")
local function run(world, top, home)
  local Y = 0
  local dug = {}
  turtle = {
    detectUp = function() return world[Y + 1] ~= nil end,
    inspectUp = function() if world[Y + 1] then return true, { name = world[Y + 1] } end return false end,
    digUp = function() dug[#dug + 1] = world[Y + 1] world[Y + 1] = nil return true end,
  }
  CONFIG = { dig = false, digNearHome = 24, digOk = { "stone", "dirt", "gravel", "deepslate", "*_ore" } }
  S = { pos = { x = 100, y = 0, z = 100 }, home = home }
  stopFlag, DIG_JOB, HOMEPROBE = false, true, nil
  function withEquipped(_, f) return f() end
  function fmt() return "Y " .. Y end
  function up() if world[Y + 1] then return false end Y = Y + 1 S.pos.y = Y return true end
  assert(load(code))()
  local ok, msg = digUp(top)
  return ok, msg, Y, dug
end
local function column(t) local w = {} for y, n in pairs(t) do w[y] = n end return w end
-- surface known (map says ground top at Y 5 -> stop at 6)
local ok, msg, y, dug = run(column({ [1] = "minecraft:stone", [2] = "minecraft:dirt", [3] = "minecraft:gravel",
                                     [4] = "minecraft:dirt", [5] = "minecraft:grass_block" }), 6)
CHECK(not ok and msg:find("grass_block", 1, true), "grass_block is not in this test's natural list: refused (" .. tostring(msg) .. ")")
ok, msg, y = run(column({ [1] = "minecraft:stone", [2] = "minecraft:dirt", [3] = "minecraft:iron_ore", [5] = "minecraft:stone" }), 6)
CHECK(ok and y == 6, "surface known: dug up to Y 6 (" .. tostring(msg) .. ", at " .. y .. ")")
-- surface unknown: up until 6 free blocks in a row (a cave pocket on the way does not count)
ok, msg, y = run(column({ [1] = "minecraft:stone", [4] = "minecraft:stone", [5] = "minecraft:dirt" }))
CHECK(ok and y == 10, "surface unknown: stops after 6 free blocks (" .. tostring(msg) .. ", at " .. y .. ")")
-- something built above: never dug
ok, msg, y = run(column({ [1] = "minecraft:stone", [2] = "minecraft:oak_planks" }), 10)
CHECK(not ok and y == 1 and msg:find("not a natural block", 1, true), "planks above: stops, says why (" .. tostring(msg) .. ")")
-- near home: no digging at all
ok, msg, y = run(column({ [1] = "minecraft:stone" }), 10, { x = 100, y = 70, z = 110 })
CHECK(not ok and y == 0 and msg:find("too close to home", 1, true), "near home: no digging (" .. tostring(msg) .. ")")
print(FAILS == 0 and "OK" or (FAILS .. " failed"))
os.exit(FAILS == 0 and 0 or 1)
