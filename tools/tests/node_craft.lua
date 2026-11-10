-- node.lua's CRAFTER: learnRecipe (the items in the 3x3 grid -> what they make)
-- and craftRecipe (ingredients from the chest in front, laid out exactly,
-- crafted, everything back into the chest). A fake turtle + chest.
--   lua5.3 tools/tests/node_craft.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a + 1, true)
  assert(a and b, "not found: " .. from)
  return src:sub(a, b - 1)
end
load(piece("GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }", "function build()"))()
-- the fake world: 16 slots, a chest in front (a list of stacks)
local INV, SEL, CHEST, SENT = {}, 1, {}, {}
local RECIPES = {   -- grid (9 names, "" = empty) -> output
  ["minecraft:oak_planks,,,minecraft:oak_planks,,,,,"] = { "minecraft:stick", 4 },
  ["minecraft:coal,,,minecraft:stick,,,,,"] = { "minecraft:torch", 4 },
}
local function at(i) return INV[i] end
turtle = {
  getItemDetail = function(i) local s = INV[i] return s and { name = s.name, count = s.count } end,
  getItemCount = function(i) return INV[i] and INV[i].count or 0 end,
  select = function(i) SEL = i return true end,
  transferTo = function(to, n)
    local s = INV[SEL]
    if not s or to == SEL then return false end
    n = math.min(n or s.count, s.count)
    local d = INV[to]
    if d and d.name ~= s.name then return false end
    local room = 64 - (d and d.count or 0)
    n = math.min(n, room)
    if n <= 0 then return false end
    INV[to] = { name = s.name, count = (d and d.count or 0) + n }
    s.count = s.count - n
    if s.count == 0 then INV[SEL] = nil end
    return true
  end,
  suck = function()
    local s = table.remove(CHEST, 1)
    if not s then return false end
    -- into the selected slot, else the next free one (like the game)
    local slot = SEL
    if INV[slot] and INV[slot].name ~= s.name then
      slot = nil
      for i = 1, 16 do if not INV[i] then slot = i break end end
    end
    if not slot then table.insert(CHEST, 1, s) return false end
    INV[slot] = { name = s.name, count = (INV[slot] and INV[slot].count or 0) + s.count }
    return true
  end,
  drop = function()
    local s = INV[SEL]
    if not s then return false end
    CHEST[#CHEST + 1] = { name = s.name, count = s.count }
    INV[SEL] = nil
    return true
  end,
  craft = function(times)
    times = times or 64
    for i = 1, 16 do if INV[i] and not ISGRID[i] then return false, "No matching recipes" end end
    local names, minC = {}, 64
    for k, s in ipairs(GRID) do
      names[k] = INV[s] and INV[s].name or ""
      if INV[s] then minC = math.min(minC, INV[s].count) end
    end
    local out = RECIPES[table.concat(names, ",")]
    if not out then return false, "No matching recipes" end
    times = math.min(times, minC)
    for _, s in ipairs(GRID) do
      if INV[s] then INV[s].count = INV[s].count - times if INV[s].count == 0 then INV[s] = nil end end
    end
    local n = out[2] * times
    local slot = SEL
    while n > 0 do
      if not INV[slot] then
        local k = math.min(64, n)
        INV[slot] = { name = out[1], count = k }
        n = n - k
      end
      slot = slot % 16 + 1
    end
    return true
  end,
}
peripheral = { call = function(side, fn) if side == "front" and fn == "list" then return CHEST end end }
function right() end
function send(t, extra) SENT[#SENT + 1] = { t = t, extra = extra } end
local function chestCount(name) local n = 0 for _, s in ipairs(CHEST) do if s.name == name then n = n + s.count end end return n end
local function empty() for i = 1, 16 do if INV[i] then return false end end return true end

-- LEARN: 2 planks in slots 1 and 5 make 4 sticks
INV = { [1] = { name = "minecraft:oak_planks", count = 3 }, [5] = { name = "minecraft:oak_planks", count = 3 } }
local ok, msg = learnRecipe()
CHECK(ok, "learn: " .. tostring(msg))
local r = SENT[1] and SENT[1].extra.recipe
CHECK(r and r.out == "minecraft:stick" and r.count == 4 and r.grid[1] == "minecraft:oak_planks" and r.grid[4] == "minecraft:oak_planks"
      and r.grid[2] == "", "learn: the layout + what it makes is sent to the base")
-- an item outside the grid: refused (it would not be a clean recipe)
INV = { [1] = { name = "minecraft:oak_planks", count = 1 }, [4] = { name = "minecraft:dirt", count = 1 } }
ok, msg = learnRecipe()
CHECK(not ok and tostring(msg):find("3x3 grid", 1, true), "learn: an item outside the grid is refused")

-- CRAFT 3 x sticks: 6 planks come out of the chest as ONE stack into slot 1
INV, CHEST = {}, { { name = "minecraft:oak_planks", count = 6 } }
ok, msg = craftRecipe("minecraft:oak_planks,,,minecraft:oak_planks,,,,,", 3)
CHECK(ok, "craft sticks: " .. tostring(msg))
CHECK(chestCount("minecraft:stick") == 12 and chestCount("minecraft:oak_planks") == 0 and empty(),
      "craft sticks: 12 sticks back in the chest, nothing left in the turtle")
-- CRAFT 5 torches: coal + sticks arrive mixed (sticks first)
INV, CHEST = {}, { { name = "minecraft:stick", count = 5 }, { name = "minecraft:coal", count = 5 } }
ok, msg = craftRecipe("minecraft:coal,,,minecraft:stick,,,,,", 5)
CHECK(ok and chestCount("minecraft:torch") == 20 and empty(), "craft torches from mixed ingredients: " .. tostring(msg))
-- not empty: refused (never mix your items in)
INV, CHEST = { [8] = { name = "minecraft:diamond", count = 1 } }, { { name = "minecraft:stick", count = 1 } }
ok, msg = craftRecipe("minecraft:coal,,,minecraft:stick,,,,,", 1)
CHECK(not ok and tostring(msg):find("EMPTY", 1, true) and INV[8], "craft: refused while it holds items")
-- too few ingredients: everything back into the chest
INV, CHEST = {}, { { name = "minecraft:coal", count = 2 }, { name = "minecraft:stick", count = 1 } }
ok, msg = craftRecipe("minecraft:coal,,,minecraft:stick,,,,,", 2)
CHECK(not ok and chestCount("minecraft:coal") == 2 and chestCount("minecraft:stick") == 1 and empty(),
      "craft: not enough -> everything back in the chest (" .. tostring(msg) .. ")")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
