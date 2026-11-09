-- base_factory.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   TURTLE FACTORY: keeps the fleet at a size you choose (SETTINGS > FACTORY,
--   factory.target; 0 = off). When there are fewer turtles (MISSING ones do
--   not count - a crash took them), the base:
--     1. checks the parts in the ME network (an Advanced Turtle, an Ender
--        Modem, a Geo Scanner, a Chunky upgrade, a diamond pickaxe, fuel);
--        what is missing is CRAFTED by AE2 - if there is a pattern for it.
--        No pattern: you are told which one is missing (this program cannot
--        read Minecraft's recipes - AE2 does the recipes through its patterns)
--     2. puts exactly those parts into the FACTORY CHEST (a chest on the
--        cable, next to the builder turtle)
--     3. sends the BUILDER turtle (it carries a Disk Drive + the install
--        floppy + a pickaxe - the rescue kit): it places the new turtle,
--        gives it the parts, starts it from the floppy - node.lua installs
--        itself, equips its modem and Chunky, refuels and reports here.
--   TAUGHT RECIPES (modpacks change recipes, so none are written in here): a
--   CRAFTER turtle (a crafting table equipped, home next to the factory chest)
--   learns a recipe when you lay the ingredients in its 3x3 grid and press
--   LEARN RECIPE (FACTORY.recipes, recipes.dat: [item] = { grid = 9 names,
--   count }). A part neither in stock nor craftable by AE2 is then made by the
--   crafter: FACTORY.plan works out the crafts (ingredients from stock, AE2
--   patterns or other taught recipes), "tcwait" orders / waits for the
--   ingredients, puts EXACTLY those into the factory chest, "tcraft" = the
--   crafter crafts and puts the result back, it goes into AE2.
--   `factory` on the computer: status, part check, setup.

FACTORY = { job = nil, builder = nil, chest = nil, fails = 0, last = nil, crafter = nil, recipes = {} }
local FILE = "factory.dat"
local RECIPE_FILE = "recipes.dat"

local function cfg(k, default)
  local f = CONFIG.factory
  local v
  if type(f) == "table" then v = f[k] end
  if v == nil then return default end
  return v
end
FACTORY.cfg = cfg

local function save()
  saveFileSafe(FILE, serialSmall({ job = FACTORY.job, builder = FACTORY.builder, chest = FACTORY.chest,
                                    fails = FACTORY.fails, last = FACTORY.last, built = FACTORY.built,
                                    crafter = FACTORY.crafter }))
end
local function saveRecipes() saveFileSafe(RECIPE_FILE, serialSmall(FACTORY.recipes)) end
FACTORY.save = save
do
  if fs.exists(FILE) then
    local h = fs.open(FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then
      FACTORY.job, FACTORY.builder, FACTORY.chest = t.job, t.builder, t.chest
      FACTORY.fails, FACTORY.last, FACTORY.built = t.fails or 0, t.last, t.built
      FACTORY.crafter = t.crafter
    end
  end
  if fs.exists(RECIPE_FILE) then
    local h = fs.open(RECIPE_FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then FACTORY.recipes = t end
  end
end

-- what one new turtle needs: { name, count, what }
function FACTORY.parts()
  return {
    { name = cfg("turtle", "computercraft:turtle_advanced"), count = 1, what = "Advanced Turtle" },
    { name = cfg("modem", "computercraft:wireless_modem_advanced"), count = 1, what = "Ender Modem" },
    { name = cfg("geo", "advancedperipherals:geo_scanner"), count = 1, what = "Geo Scanner" },
    { name = cfg("chunky", "advancedperipherals:chunk_controller"), count = 1, what = "Chunky upgrade (Chunk Controller)" },
    { name = cfg("pick", "minecraft:diamond_pickaxe"), count = 1, what = "diamond pickaxe" },
    { name = cfg("fuel", "minecraft:coal_block"), count = tonumber(cfg("fuelCount", 16)) or 16,
      what = "fuel: " .. prettify(cfg("fuel", "minecraft:coal_block")) },     -- (`factory fuel <item> [count]`)
  }
end

-- recipes we know for sure (ComputerCraft / vanilla) - a hint when a pattern is missing
local HINT = {
  ["computercraft:turtle_advanced"] = "7 gold ingots around an Advanced Computer, a chest below it",
  ["computercraft:computer_advanced"] = "7 gold ingots around redstone, a glass pane below it",
  ["computercraft:wireless_modem_advanced"] = "8 gold ingots around an Eye of Ender",
  ["minecraft:diamond_pickaxe"] = "3 diamonds on top, 2 sticks below the middle",
  ["minecraft:coal_block"] = "9 coal",
}

function FACTORY.hint(name) return HINT[name] end

-- an item that is someone's own: enchanted, renamed, or a computer / turtle
-- with an ID and files. The factory never takes one of those.
-- (values, not just names: 1.21 items may list defaults like damage 0 or an
-- empty enchantment list - those are plain)
local function filled(v)
  if type(v) == "table" then
    for _, x in pairs(v) do if filled(x) then return true end end
    return false
  end
  if type(v) == "number" then return v ~= 0 end
  if type(v) == "string" then return v ~= "" end
  return v == true
end
local function special(it)
  if type(it) ~= "table" then return false end
  if filled(it.enchantments) then return true end
  for _, key in ipairs({ "nbt", "components" }) do
    local t = it[key]
    if type(t) == "table" then
      for k, v in pairs(t) do
        local kk = tostring(k):lower()
        local mine = kk:find("enchant", 1, true) or kk:find("custom_name", 1, true) or kk:find("display", 1, true)
                     or kk:find("computer", 1, true) or kk:find("upgrade", 1, true) or kk:find("label", 1, true)
                     or (kk:find("damage", 1, true) and not kk:find("max", 1, true))
        if mine and filled(v) then return true end
      end
    end
  end
  return false
end
FACTORY.special = special

-- the ME network: how many, can it craft it?
local function meCount(name)
  if not bridge then return 0 end
  local ok, it = callx(bridge, "getItem", { name = name })
  if ok and type(it) == "table" then return tonumber(it.amount or it.count) or 0 end
  return 0
end
local function meCraftable(name)
  if not bridge then return false end
  for _, fn in ipairs({ "isItemCraftable", "isCraftable" }) do
    if type(bridge[fn]) == "function" then
      local ok, r = pcall(bridge[fn], { name = name })
      if ok then return r and true or false end
    end
  end
  local ok, it = callx(bridge, "getItem", { name = name })
  return ok and type(it) == "table" and it.isCraftable and true or false
end

-- every VERSION of an item in AE2 (a used / enchanted pickaxe is kept apart from
-- a fresh one): how many PLAIN ones, how many of YOURS (never taken) and the
-- fingerprint of a plain one. Before: the first version AE2 gave was taken as
-- "the" item - your used pickaxe stopped the whole factory.
local function variants(name)
  local list
  if bridge and type(bridge.getItems) == "function" then
    local ok, r = pcall(bridge.getItems, { name = name })
    if ok and type(r) == "table" then list = r end
  end
  if not list then
    local ok, it = callx(bridge, "getItem", { name = name })
    list = (ok and type(it) == "table") and { it } or {}
  end
  local plain, own, fp = 0, 0, nil
  for _, it in pairs(list) do
    if type(it) == "table" and it.name == name then
      local n = tonumber(it.amount or it.count) or 0
      if special(it) then own = own + n
      else
        plain = plain + n
        if n > 0 and not fp then fp = it.fingerprint end
      end
    end
  end
  return plain, own, fp
end
FACTORY.variants = variants

-- every part: { part, have (plain ones), own (yours - never taken), craftable, ok } - and the missing ones
function FACTORY.check()
  local rows, missing = {}, {}
  for _, p in ipairs(FACTORY.parts()) do
    local have, own = variants(p.name)
    local craftable = have < p.count and meCraftable(p.name)
    local ok = have >= p.count or craftable
    rows[#rows + 1] = { part = p, have = have, own = own, craftable = craftable, ok = ok }
    if not ok then missing[#missing + 1] = p end
  end
  return rows, missing
end

-- ===== TAUGHT RECIPES and the CRAFTER turtle =====
-- the crafter: the one you chose, else the only online turtle with a crafting table
function FACTORY.crafterTurtle()
  local id = tonumber(FACTORY.crafter)
  if id then return state.turtles[id] end
  for _, t in pairs(state.turtles) do
    if type(t.gear) == "string" and t.gear:find("crafter", 1, true) then return t end
  end
end
-- the crafter learned a recipe (TT.receive "recipe")
function FACTORY.learned(id, r)
  if type(r.out) ~= "string" or type(r.grid) ~= "table" then return end
  local grid = {}
  for k = 1, 9 do grid[k] = (type(r.grid[k]) == "string") and r.grid[k] or "" end
  FACTORY.recipes[r.out] = { grid = grid, count = math.max(1, tonumber(r.count) or 1), at = os.epoch("utc"), by = id }
  saveRecipes()
  local t = state.turtles[id]
  pushNote("DONE", "Recipe learned: " .. prettify(r.out) .. " (" .. FACTORY.recipes[r.out].count ..
           " per craft) - the factory makes it when AE2 cannot", C.good)
  if sysLog then sysLog("Recipe learned by " .. (t and t.label or ("#" .. id)) .. ": " .. r.out, "DONE") end
end
function FACTORY.forget(name)
  if not FACTORY.recipes[name] then return false end
  FACTORY.recipes[name] = nil
  saveRecipes()
  return true
end
-- the ingredients of one craft: { [name] = count }
function FACTORY.ingredients(r)
  local need = {}
  for _, n in ipairs(r.grid) do if n ~= "" then need[n] = (need[n] or 0) + 1 end end
  return need
end
-- what it takes to have `count` of `name`: AE2 crafts (orders), taught crafts
-- (in order: ingredients first) and what cannot be made. avail = stock not yet
-- planned for (shared between the parts). depth limits loops in recipes.
function FACTORY.plan(name, count, avail, out, depth)
  out = out or { ae = {}, crafts = {}, missing = {} }
  avail = avail or {}
  depth = depth or 0
  if avail[name] == nil then avail[name] = meCount(name) end
  local use = math.min(avail[name], count)
  avail[name] = avail[name] - use
  local need = count - use
  if need <= 0 then return out end
  local r = FACTORY.recipes[name]
  if depth > 6 then out.missing[#out.missing + 1] = name return out end
  if meCraftable(name) then
    out.ae[name] = (out.ae[name] or 0) + need
  elseif r then
    local times = math.ceil(need / r.count)
    for ing, per in pairs(FACTORY.ingredients(r)) do FACTORY.plan(ing, per * times, avail, out, depth + 1) end
    while times > 0 do                                   -- (one craft call: at most 64)
      local n = math.min(64, times)
      out.crafts[#out.crafts + 1] = { name = name, times = n }
      times = times - n
    end
  else
    out.missing[#out.missing + 1] = name
  end
  return out
end
-- why the crafter cannot work now (nil = it can)
function FACTORY.crafterBlocked()
  local c = FACTORY.crafterTurtle()
  if not c then return "no crafter turtle (a turtle with a crafting table) - SETTINGS > FACTORY" end
  if not TT.online(c) then return c.label .. " (crafter) is offline" end
  if not (type(c.gear) == "string" and c.gear:find("crafter", 1, true)) then
    return c.label .. " has no crafting table equipped"
  end
  return nil
end

-- the turtles that count for the fleet size (MISSING ones do not)
function FACTORY.fleet()
  local n = 0
  for _, t in pairs(state.turtles) do if not t.missing then n = n + 1 end end
  return n
end

local function builderTurtle()
  local id = tonumber(FACTORY.builder)
  if not id then
    for _, t in pairs(state.turtles) do if t.rescuerRole then id = t.id end end    -- (default: the rescuer)
  end
  return id and state.turtles[id]
end
FACTORY.builderTurtle = builderTurtle

-- what is in the factory chest (network name) - nil if it cannot be read
local function chestList()
  if not FACTORY.chest or not peripheral.isPresent(FACTORY.chest) then return nil end
  local ok, list = pcall(peripheral.call, FACTORY.chest, "list")
  if ok and type(list) == "table" then return list end
end

local function setStep(step, note)
  local j = FACTORY.job
  if not j then return end
  j.step, j.t = step, os.epoch("utc")
  if note then j.note = note end
  save()
  os.queueEvent("inv_update")
end
local function fail(why)
  -- parts already put into the chest by us: exactly those back into the ME network
  local j = FACTORY.job
  if j and j.exported and FACTORY.chest and bridge then
    for name, n in pairs(j.exported) do
      if n > 0 then pcall(transfer, bridge, { "importItem" }, FACTORY.chest, { name = name, count = n }) end
    end
  end
  FACTORY.fails = (FACTORY.fails or 0) + 1
  FACTORY.last = { t = os.epoch("utc"), ok = false, msg = why }
  FACTORY.job = nil
  FACTORY.waitUntil = os.clock() + 1800                -- try again in 30 min
  save()
  if sysLog then sysLog("Factory: " .. why, "WARNING") end
  pushNote("WARNING", "Turtle factory: " .. why, C.warn)
end

-- a container the base already uses for something else (AE2 item buffer,
-- give / take chests, the curios barrel, the fluid buffer): never the factory chest
function FACTORY.reserved(name)
  local me = CONFIG.me or {}
  if not name then return nil end
  for _, k in ipairs({ "buffer", "giveChest", "takeChest", "curiosChest", "fluidBuffer" }) do
    if me[k] == name then return k end
  end
end

-- why no turtle is built now (nil = it can build)
function FACTORY.blocked()
  local target = tonumber(cfg("target", 0)) or 0
  if target <= 0 then return "off (SETTINGS > FACTORY: keep this many turtles)" end
  if FACTORY.fleet() >= target then return "fleet complete (" .. FACTORY.fleet() .. "/" .. target .. ")" end
  if not bridge then return "no ME Bridge" end
  if not FACTORY.chest then return "no factory chest set - type  factory chest" end
  if not peripheral.isPresent(FACTORY.chest) then return "the factory chest " .. FACTORY.chest .. " is not on the cable" end
  if FACTORY.reserved(FACTORY.chest) then
    return FACTORY.chest .. " is your " .. (FACTORY.reserved(FACTORY.chest) == "curiosChest" and "curios barrel" or "AE2 buffer") ..
           " - pick ANOTHER empty chest / barrel as the factory chest"
  end
  local b = builderTurtle()
  if not b then return "no builder turtle - type  factory builder <id>  (or give a turtle the RESCUER role)" end
  if not TT.online(b) then return b.label .. " (builder) is offline" end
  if (FACTORY.fails or 0) >= 3 then return "stopped after 3 failed builds - type  factory build  to try again" end
  if not b.home then return b.label .. " (builder) has no home - its home must be next to the factory chest" end
  return nil
end

-- comms worker (every 2 s; the real work every 10 s)
local lastTick = -100
function FACTORY.tick()
  if os.clock() - lastTick < 10 then return end
  lastTick = os.clock()
  local j = FACTORY.job
  if not j and FACTORY.leaving then
    -- the turtle just built stands on the build spot: get it out of the way first
    -- (a home offer at once, then home), the next build only when the spot is free
    local L = FACTORY.leaving
    local t = L.id and state.turtles[L.id]
    local b = builderTurtle()
    local away = true
    if t and t.pos and t.pos.x and b and b.home and b.home.x then
      away = math.abs(t.pos.x - b.home.x) + math.abs(t.pos.y - b.home.y) + math.abs(t.pos.z - b.home.z) >= 2
    elseif t then
      away = false
    end
    if (t and away and TT.online(t)) or os.clock() - L.at > 1200 or (L.id == nil and os.clock() - L.at > 120) then
      if t and not away then
        pushNote("WARNING", "Turtle factory: the new turtle " .. (t.label or ("#" .. L.id)) ..
                 " did not leave the build spot in 20 minutes - move it, the next build waits for the spot", C.warn)
        FACTORY.waitUntil = os.clock() + 600
      end
      FACTORY.leaving = nil
      save()
    elseif t and TT.online(t) then
      if not t.home then t.homeOfferAt = nil                  -- (a home offer at once)
      elseif not L.sent or os.clock() - L.sent > 60 then
        L.sent = os.clock()
        TT.send(t.id, "home", {}, true)
      end
    end
    return
  end
  if not j then
    if FACTORY.waitUntil and os.clock() < FACTORY.waitUntil then return end
    if FACTORY.blocked() then return end
    local b = builderTurtle()
    if b.task and b.task ~= "idle" then return end      -- the builder is busy: later
    -- the builder works at its home (next to the factory chest): send it there first
    if not (b.home and b.pos and b.pos.x and b.pos.x == b.home.x and b.pos.y == b.home.y and b.pos.z == b.home.z) then
      if not b.home then FACTORY.homeless = true return end
      if not FACTORY.sentHome or os.clock() - FACTORY.sentHome > 120 then
        FACTORY.sentHome = os.clock()
        TT.send(b.id, "home", {}, true)
      end
      return
    end
    FACTORY.homeless = nil
    FACTORY.job = { step = "parts", t = os.epoch("utc"), builder = b.id }
    save()
    j = FACTORY.job
  end
  if j.step == "parts" then
    local rows, missing = FACTORY.check()
    if #missing > 0 then
      -- TAUGHT recipes: can the crafter make what AE2 cannot? (ingredients from
      -- stock, AE2 patterns or other taught recipes)
      local plan, cblock
      if next(FACTORY.recipes) then
        plan = { ae = {}, crafts = {}, missing = {} }
        local avail = {}
        for _, p in ipairs(missing) do FACTORY.plan(p.name, p.count, avail, plan) end
        cblock = (#plan.crafts > 0) and FACTORY.crafterBlocked() or nil
        j.rounds = (j.rounds or 0) + 1
        if j.rounds > 30 then return fail("the taught recipes do not make the missing parts (wrong recipe?) - type  factory") end
        if #plan.missing == 0 and #plan.crafts > 0 and not cblock then
          for name, n in pairs(plan.ae) do
            local ok, err = craftME(name, n)
            if not ok then return fail("AE2 could not start crafting " .. prettify(name) .. ": " .. tostring(err)) end
          end
          FACTORY.lastMissing = nil
          j.tq = plan.crafts
          setStep("tcwait", "getting the ingredients for the crafter")
          return
        end
      end
      local names = {}
      local ownOf = {}
      for _, r in ipairs(rows) do if r.own and r.own > 0 then ownOf[r.part.name] = true end end
      for _, p in ipairs(missing) do
        names[#names + 1] = p.what .. (ownOf[p.name] and " (only YOUR own one - enchanted / renamed / used - is in AE2)" or "")
      end
      if plan and #plan.missing > 0 then
        names = {}
        for _, n in ipairs(plan.missing) do names[#names + 1] = prettify(n) end
      end
      FACTORY.lastCrafter = cblock
      FACTORY.job = nil
      FACTORY.waitUntil = os.clock() + 1800
      FACTORY.lastMissing = missing
      save()
      if not FACTORY.toldMissing or os.clock() - FACTORY.toldMissing > 3600 then
        FACTORY.toldMissing = os.clock()
        pushNote("WARNING", "Turtle factory: no stock, no AE2 pattern and no taught recipe for: " .. table.concat(names, ", ") ..
                 (cblock and (" (" .. cblock .. ")") or "") .. " - type  factory  on the computer for the list", C.warn)
      end
      return
    end
    FACTORY.lastMissing = nil
    -- order what is not in stock
    for _, r in ipairs(rows) do
      if r.have < r.part.count then
        local ok, err = craftME(r.part.name, r.part.count - r.have)
        if not ok then return fail("AE2 could not start crafting " .. r.part.what .. ": " .. tostring(err)) end
      end
    end
    setStep("crafting", "AE2 is crafting the parts")
  elseif j.step == "crafting" then
    local ready = true
    for _, p in ipairs(FACTORY.parts()) do
      if (variants(p.name)) < p.count then ready = false end
    end
    if ready then
      setStep("export")
    elseif os.epoch("utc") - (j.t or 0) > 1800000 then
      fail("the parts were not crafted within 30 minutes (resources missing? crafting CPU busy?)")
    end
  elseif j.step == "export" then
    local list = chestList()
    if not list then return fail("cannot read the factory chest " .. tostring(FACTORY.chest)) end
    if next(list) then
      -- not empty: our parts from before (a build that did not start)? then use them
      local hasTurtle = false
      for _, it in pairs(list) do if tostring(it.name):find("computercraft:turtle", 1, true) then hasTurtle = true end end
      if not hasTurtle then return fail("the factory chest is not empty - it must only be used by the factory") end
    else
      j.exported = {}
      for _, p in ipairs(FACTORY.parts()) do
        -- a PLAIN one, never your own (enchanted / renamed / a used turtle);
        -- asked for by its fingerprint, so it is exactly the one looked at
        local plain, own, fp = variants(p.name)
        if plain < p.count then
          save()
          return fail("no plain " .. p.what .. " in AE2" .. ((own > 0) and " (only YOUR own one - not taken)" or "") ..
                      " - keep a plain one in stock or give AE2 a pattern for it")
        end
        local filter = { name = p.name, count = p.count }
        if fp then filter.fingerprint = fp end
        local ok, r = transfer(bridge, { "exportItem" }, FACTORY.chest, filter)
        local moved = ok and numOf(r) or 0
        j.exported[p.name] = moved
        if moved < p.count then
          save()
          return fail("could not put " .. p.what .. " into the factory chest (" .. tostring(moved) .. "/" .. p.count .. ")")
        end
      end
    end
    local b = state.turtles[j.builder]
    if not (b and TT.online(b)) then return fail("the builder turtle is offline") end
    TT.send(b.id, "build", {})
    setStep("building", "the builder is putting the turtle together")
  elseif j.step == "tcwait" then
    -- the next taught craft: its ingredients in stock? then exactly those into
    -- the chest and the crafter crafts
    local c = j.tq and j.tq[1]
    if not c then return setStep("parts") end
    local r = FACTORY.recipes[c.name]
    if not r then return fail("the recipe for " .. prettify(c.name) .. " was forgotten") end
    local need = FACTORY.ingredients(r)
    local waited = os.epoch("utc") - (j.t or 0) > 1800000
    for ing, per in pairs(need) do
      if meCount(ing) < per * c.times then
        if waited then return fail(prettify(ing) .. " for " .. prettify(c.name) .. " did not arrive within 30 minutes") end
        return
      end
    end
    local why = FACTORY.crafterBlocked()
    if why then
      if waited then return fail(why) end
      return
    end
    local cr = FACTORY.crafterTurtle()
    if cr.task and cr.task ~= "idle" then return end
    -- it works at its home (next to the factory chest)
    if cr.home and not (cr.pos and cr.pos.x == cr.home.x and cr.pos.y == cr.home.y and cr.pos.z == cr.home.z) then
      if not FACTORY.crafterSent or os.clock() - FACTORY.crafterSent > 120 then
        FACTORY.crafterSent = os.clock()
        TT.send(cr.id, "home", {}, true)
      end
      return
    end
    local list = chestList()
    if not list then return fail("cannot read the factory chest " .. tostring(FACTORY.chest)) end
    if next(list) then return fail("the factory chest is not empty - it must only be used by the factory") end
    j.exported = {}
    for ing, per in pairs(need) do
      local n = per * c.times
      local okI, it = callx(bridge, "getItem", { name = ing })
      if okI and special(it) then
        return fail("the " .. prettify(ing) .. " in your ME system looks like your OWN one (enchanted, renamed or used) - not taken")
      end
      local filter = { name = ing, count = n }
      if okI and type(it) == "table" and it.fingerprint then filter.fingerprint = it.fingerprint end
      local ok, r2 = transfer(bridge, { "exportItem" }, FACTORY.chest, filter)
      local moved = ok and numOf(r2) or 0
      j.exported[ing] = (j.exported[ing] or 0) + moved
      if moved < n then return fail("could not put " .. prettify(ing) .. " into the factory chest (" .. moved .. "/" .. n .. ")") end
    end
    j.crafter = cr.id
    TT.send(cr.id, "craft", { table.concat(r.grid, ","), c.times })
    setStep("tcraft", "the crafter makes " .. prettify(c.name))
  elseif j.step == "tcraft" then
    if os.epoch("utc") - (j.t or 0) > 300000 then
      fail("the crafter did not finish within 5 minutes - look at it (its log on the TURTLES tab)")
    end
  elseif j.step == "building" then
    if os.epoch("utc") - (j.t or 0) > 600000 then
      fail("the builder did not finish within 10 minutes - look at it (its log on the TURTLES tab)")
    end
  end
end

-- the builder answered (TT.receive: result of "build")
function FACTORY.result(id, ok, msg)
  local j = FACTORY.job
  if not j or j.builder ~= id then return end
  if not ok then return fail("the builder: " .. tostring(msg)) end
  local newId = tonumber(tostring(msg):match("built turtle (%d+)"))
  FACTORY.job = nil
  FACTORY.fails = 0
  FACTORY.built = (FACTORY.built or 0) + 1
  FACTORY.last = { t = os.epoch("utc"), ok = true, msg = msg, id = newId }
  FACTORY.waitUntil = os.clock() + 120                 -- the next one in 2 min (it moves away first)
  FACTORY.leaving = { id = newId, at = os.clock() }    -- (and only once it has left the build spot)
  save()
  if sysLog then sysLog("Factory: " .. tostring(msg), "DONE") end
  pushNote("DONE", "Turtle factory: " .. tostring(msg) .. " - it installs itself and reports in a moment", C.good)
end

-- the crafter answered (TT.receive: result of "craft")
function FACTORY.craftResult(id, ok, msg)
  local j = FACTORY.job
  if not j or j.step ~= "tcraft" or j.crafter ~= id then return end
  if not ok then return fail("the crafter: " .. tostring(msg)) end
  -- everything in the chest now came from the craft (the item + leftovers like
  -- empty buckets): into the ME network
  local left = {}
  for _, it in pairs(chestList() or {}) do
    local okT, okM, r = pcall(transfer, bridge, { "importItem" }, FACTORY.chest, { name = it.name, count = it.count })
    local moved = (okT and okM) and (numOf(r) or 0) or 0
    if moved < (it.count or 0) then left[#left + 1] = prettify(it.name) end
  end
  j.exported = nil
  local c = table.remove(j.tq or {}, 1)
  if sysLog then sysLog("Factory: the crafter " .. tostring(msg), "INFO") end
  if #left > 0 then return fail("the ME network did not take " .. table.concat(left, ", ") .. " from the factory chest") end
  setStep((j.tq and #j.tq > 0) and "tcwait" or "parts",
          c and ("made " .. prettify(c.name)) or nil)
end

-- one line for the screen
function FACTORY.statusLine()
  local j = FACTORY.job
  if j then
    local what = { parts = "checking the parts", crafting = "AE2 is crafting the parts",
                   tcwait = "getting ingredients for the crafter", tcraft = "the crafter is crafting",
                   export = "putting the parts into the chest", building = "the builder is at work" }
    return "building turtle " .. (FACTORY.fleet() + 1) .. ": " .. (what[j.step] or j.step), C.good
  end
  local why = FACTORY.blocked()
  if why then return why, (why:find("^off") or why:find("^fleet complete")) and C.dim or C.warn end
  if FACTORY.leaving then return "waiting for the new turtle to leave the build spot", C.label end
  if FACTORY.lastMissing then return "waiting for AE2 patterns - type  factory", C.warn end
  if FACTORY.waitUntil and os.clock() < FACTORY.waitUntil then return "next try in a moment", C.dim end
  return "ready", C.good
end
