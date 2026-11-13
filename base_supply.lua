-- base_supply.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   SUPPLY: keep a storage on the wired cable stocked from AE2 (console `supply`).
--   A rule = { target = network name, kind = "item" | "fluid", name, keep }:
--   every CONFIG.supply.every s (10) the base counts what the storage holds and
--   exports the difference from AE2 (items: only PLAIN ones - never your own
--   enchanted / renamed / used ones, FACTORY.variants; fluids: exportFluid in mB).
--   It only ever PUTS things in: nothing is taken out of the storage, ever.
--   The base's own containers (AE2 buffer, give / take chests, curios barrel,
--   fluid buffer, factory chest) can not be a target. A target is also left out
--   of the fluid buffer's automatic choice (fluidBuffer in base_me.lua).
--   Saved in supply.dat. tools/tests/test_supply.lua.

SUPPLY = { rules = {}, at = -999, cache = { item = {}, fluid = {} }, cacheAt = -999 }
SUPPLY.FULL = 9e15                 -- "FULL": as much as it takes (keep topping it up)
SUPPLY.BUDGET = 2                  -- s of pumping per rule per round (the worker comes straight back)
local FILE = "supply.dat"

function SUPPLY.load()
  local path = dataPath and dataPath(FILE) or FILE
  if not fs.exists(path) then return end
  local h = fs.open(path, "r")
  local t = h and textutils.unserialize(h.readAll() or "")
  if h then h.close() end
  if type(t) == "table" then
    for _, r in ipairs(t) do
      if type(r) == "table" and r.target and r.name and tonumber(r.keep) then SUPPLY.rules[#SUPPLY.rules + 1] = r end
    end
  end
end
function SUPPLY.save()
  local out = {}
  for _, r in ipairs(SUPPLY.rules) do
    out[#out + 1] = { target = r.target, kind = r.kind, name = r.name, keep = r.keep, moved = r.moved }
  end
  local path = dataPath and dataPath(FILE) or FILE
  saveFileSafe(path, serialSmall and serialSmall(out) or textutils.serialize(out))
end
SUPPLY.load()

-- a short name gets "minecraft:" in front
function SUPPLY.fullName(s)
  s = tostring(s or ""):lower()
  if s ~= "" and not s:find(":", 1, true) then s = "minecraft:" .. s end
  return s
end

function SUPPLY.isTarget(name)
  for _, r in ipairs(SUPPLY.rules) do if r.target == name then return true end end
  return false
end

-- why a container can not be a supply target (nil = it can)
function SUPPLY.refuse(name)
  if not name or name == "" then return "no storage named" end
  local used
  for _, k in ipairs({ "buffer", "giveChest", "takeChest", "curiosChest", "fluidBuffer" }) do
    if (CONFIG.me or {})[k] == name then used = k end
  end
  if used == "fluidBuffer" then return name .. " is the base's fluid buffer (fluidbuffer to change it) - pick another storage" end
  if used then return name .. " is the base's own " .. used .. " - pick another storage" end
  if FACTORY and FACTORY.chest == name then return name .. " is the factory chest - pick another storage" end
  if not (CONFIG.me or {}).fluidBuffer and fluidBufferMem and fluidBufferMem() == name then
    return name .. " is the base's fluid buffer (fluidbuffer to change it) - pick another storage"
  end
  local okT, ty = pcall(peripheral.getType, name)
  ty = (okT and type(ty) == "string") and ty or ""
  for _, bad in ipairs({ "me_bridge", "inventory_manager", "drive", "computer", "turtle", "monitor", "modem" }) do
    if ty:find(bad, 1, true) then return name .. " is a " .. ty .. ", not a storage" end
  end
  return nil
end

-- what the storage can hold: "item", "fluid" or both
-- (a modded tank may bring its OWN computer methods instead of CC's standard
-- "fluid_storage" ones - e.g. getStored(): those are read too)
SUPPLY.FLUID_READ = { "getStored", "getFluid", "getContents", "getFluidStored", "getTankContents" }
function SUPPLY.methods(name)
  local ok, m = pcall(peripheral.getMethods, name)
  local set = {}
  if ok and type(m) == "table" then for _, k in ipairs(m) do set[k] = true end end
  return set, (ok and type(m) == "table") and m or {}
end
function SUPPLY.kinds(name)
  local function has(t) local ok, r = pcall(peripheral.hasType, name, t) return ok and r end
  local isInv, isFluid = has("inventory"), has("fluid_storage")
  if not isFluid then
    local set = SUPPLY.methods(name)
    if set.tanks then isFluid = true end
    for _, k in ipairs(SUPPLY.FLUID_READ) do if set[k] then isFluid = true end end
  end
  if not isInv then
    local set = SUPPLY.methods(name)
    if set.list and (set.pullItems or set.size) then isInv = true end
  end
  return isInv, isFluid
end

-- blocks that run the base itself - never listed as "other blocks"
local OWN = { "me_bridge", "inventory_manager", "player_detector", "chat_box", "drone_interface", "drive",
              "monitor", "computer", "turtle", "modem", "speaker", "printer", "energy_detector" }
function SUPPLY.others()
  local cands, out = {}, {}
  for _, n in ipairs(SUPPLY.candidates()) do cands[n] = true end
  for _, n in ipairs(peripheral.getNames()) do
    if not cands[n] then
      local okT, ty = pcall(peripheral.getType, n)
      ty = (okT and type(ty) == "string") and ty or "?"
      local own = false
      for _, o in ipairs(OWN) do if ty:find(o, 1, true) then own = true end end
      if not own and not n:find("^%a+$") then out[#out + 1] = n end   -- (plain sides like "top" = the computer's own)
    end
  end
  table.sort(out)
  return out
end
-- what a block offers (types + functions), for `supply check`
function SUPPLY.describe(name)
  local types = { pcall(peripheral.getType, name) }
  table.remove(types, 1)
  local _, list = SUPPLY.methods(name)
  table.sort(list)
  return table.concat(types, ", "), list
end

-- the storages on the cable that could be a target (for the list / numbers)
function SUPPLY.candidates()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    local isInv, isFluid = SUPPLY.kinds(n)
    if (isInv or isFluid) and not SUPPLY.refuse(n) then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

-- how much of it the storage holds now (nil + why if it cannot be read)
function SUPPLY.count(r)
  if r.kind == "fluid" then
    local set = SUPPLY.methods(r.target)
    -- one fluid table {name, amount} or a list of them
    local function add(t)
      if type(t) ~= "table" then return nil end
      if t.name then return (t.name == r.name) and (tonumber(t.amount or t.count) or 0) or 0 end
      local n = 0
      for _, tk in pairs(t) do
        if type(tk) == "table" and tk.name == r.name then n = n + (tonumber(tk.amount or tk.count) or 0) end
      end
      return n
    end
    local fns = { "tanks" }
    for _, k in ipairs(SUPPLY.FLUID_READ) do fns[#fns + 1] = k end
    for _, fn in ipairs(fns) do
      if set[fn] then
        local ok, t = pcall(peripheral.call, r.target, fn)
        if ok then
          if t == nil then return 0 end                    -- (an empty tank answers nothing)
          local n = add(t)
          if n then return n end
        end
      end
    end
    return nil, "cannot read how much it holds (supply check " .. r.target .. " shows what it offers)"
  end
  local ok, list = pcall(peripheral.call, r.target, "list")
  if not ok or type(list) ~= "table" then return nil, "cannot read what it holds" end
  local n = 0
  for _, it in pairs(list) do
    if type(it) == "table" and it.name == r.name then n = n + (tonumber(it.count) or 0) end
  end
  return n
end

-- amounts as text (fluids in buckets)
function SUPPLY.amount(r, n)
  n = tonumber(n) or 0
  if n >= SUPPLY.FULL then return "FULL" end
  if r.kind == "fluid" then
    local b = n / 1000
    return (b == math.floor(b) and tostring(math.floor(b)) or string.format("%.1f", b)) .. " B"
  end
  return tostring(math.floor(n))
end

-- one rule: top it up now. Returns how much was put in.
function SUPPLY.fill(r)
  r.checked = os.clock()
  if not bridge then r.why = "no ME Bridge" return 0 end
  if not peripheral.isPresent(r.target) then r.why = "not on the cable (wired modem off / block gone?)" return 0 end
  local bad = SUPPLY.refuse(r.target)
  if bad then r.why = bad return 0 end
  local have, err = SUPPLY.count(r)
  if not have then r.why = err return 0 end
  r.have = have
  local need = (tonumber(r.keep) or 0) - have
  if need <= 0 then r.why = nil r.state = "full" return 0 end
  local moved = 0
  if r.kind == "fluid" then
    -- keep calling while it moves (some tanks / bridges take 1 bucket per call) - for up to
    -- SUPPLY.BUDGET s; the supply worker comes straight back while it is still short
    local stopAt, calls = os.clock() + SUPPLY.BUDGET, 0
    while os.clock() < stopAt and calls < 2000 do
      calls = calls + 1
      local ok, res, e = transfer(bridge, { "exportFluid" }, r.target,
                                  { name = r.name, amount = math.min(need - moved, FLUID_MAX or 2147483647) })
      local n = ok and (numOf(res) or 0) or 0
      if n <= 0 then
        if moved == 0 then r.why = ok and ("AE2 has no " .. r.name .. " or the tank takes none" .. (e and (" (" .. tostring(e) .. ")") or ""))
                                     or ("AE2 said: " .. tostring(res)) end
        break
      end
      moved = moved + n
      if moved >= need then break end
    end
  else
    -- only PLAIN ones (never your own enchanted / renamed / used items)
    local plain, own, fp = need, 0, nil
    if FACTORY and FACTORY.variants then plain, own, fp = FACTORY.variants(r.name) end
    if plain <= 0 then
      r.why = "none left in AE2" .. ((own > 0) and " (only your OWN ones - not taken)" or "")
    else
      local stopAt, calls = os.clock() + SUPPLY.BUDGET, 0
      while os.clock() < stopAt and calls < 200 and moved < math.min(need, plain) do
        calls = calls + 1
        local filter = { name = r.name, count = math.min(need - moved, plain - moved, 2147483647) }
        if fp then filter.fingerprint = fp end
        local ok, res = transfer(bridge, { "exportItem" }, r.target, filter)
        local n = ok and (numOf(res) or 0) or 0
        if n <= 0 then
          if moved == 0 then r.why = ok and "the storage took none (full of other things?)" or ("AE2 said: " .. tostring(res)) end
          break
        end
        moved = moved + n
      end
    end
  end
  if moved > 0 then
    r.why = nil
    r.have = have + moved
    r.moved = (r.moved or 0) + moved
    r.lastMoved, r.lastAt = moved, os.clock()
    SUPPLY.dirty = true
  end
  r.state = (moved > 0) and "filled" or "short"
  r.busy = moved > 0 and (have + moved) < (tonumber(r.keep) or 0)    -- (still taking it: come straight back)
  -- one warning when it starts running short, again only after it worked
  if r.why and not r.warned then
    r.warned = true
    pushNote("WARNING", "Supply " .. r.target .. ": " .. r.name .. " - " .. r.why, C.warn)
  elseif not r.why then
    r.warned = nil
  end
  return moved
end

-- comms worker (every 2 s; works every CONFIG.supply.every s)
-- the storages for the AE2 tab's KEEP FILLED row (peripheral calls never in drawing:
-- refreshed here, every 10 s)
function SUPPLY.refreshCache()
  SUPPLY.cacheAt = os.clock()
  local c = { item = {}, fluid = {} }
  for _, n in ipairs(SUPPLY.candidates()) do
    local isInv, isFluid = SUPPLY.kinds(n)
    if isInv then c.item[#c.item + 1] = n end
    if isFluid then c.fluid[#c.fluid + 1] = n end
  end
  SUPPLY.cache = c
end
-- the rule for this storage + item / fluid (drawing: tables only)
function SUPPLY.ruleFor(target, kind, name)
  for i, r in ipairs(SUPPLY.rules) do
    if r.target == target and r.kind == kind and r.name == name then return r, i end
  end
end
-- one round (supplyWorker, its own coroutine: pumping never holds up the turtles' comms).
-- Every CONFIG.supply.every s (10) - but AT ONCE again while a storage is still taking it
-- (before: 16 calls every 10 s = slow when a tank takes 1 bucket per call). Returns busy.
function SUPPLY.tick()
  if os.clock() - SUPPLY.cacheAt >= 10 then pcall(SUPPLY.refreshCache) end
  if #SUPPLY.rules == 0 then return false end
  local every = tonumber(CONFIG.supply and CONFIG.supply.every) or 10
  if os.clock() - SUPPLY.at < every and not SUPPLY.busy then return false end
  SUPPLY.at = os.clock()
  local busy = false
  for _, r in ipairs(SUPPLY.rules) do
    pcall(SUPPLY.fill, r)
    if r.busy then busy = true end
  end
  SUPPLY.busy = busy
  if SUPPLY.dirty and (not busy or os.clock() - (SUPPLY.savedAt or -999) > 60) then
    SUPPLY.dirty, SUPPLY.savedAt = false, os.clock()
    pcall(SUPPLY.save)
  end
  return busy
end

-- add / change a rule (true + text | false + why)
function SUPPLY.add(target, kind, name, keep)
  local bad = SUPPLY.refuse(target)
  if bad then return false, bad end
  if not peripheral.isPresent(target) then return false, target .. " is not on the cable - put a wired modem on it and right-click the modem (red)" end
  local isInv, isFluid = SUPPLY.kinds(target)
  if kind == "fluid" and not isFluid then return false, target .. " holds no fluids" end
  if kind == "item" and not isInv then return false, target .. " holds no items" .. (isFluid and " - for a fluid: supply <storage> fluid <name> <buckets>" or "") end
  keep = tonumber(keep)
  if not keep or keep <= 0 then return false, "how many? (a number above 0)" end
  name = SUPPLY.fullName(name)
  for _, r in ipairs(SUPPLY.rules) do
    if r.target == target and r.name == name and r.kind == kind then
      r.keep, r.warned, r.why = keep, nil, nil
      SUPPLY.save()
      SUPPLY.at = -999
      return true, "Changed: " .. target .. " keeps " .. SUPPLY.amount(r, keep) .. " " .. name
    end
  end
  local r = { target = target, kind = kind, name = name, keep = keep }
  SUPPLY.rules[#SUPPLY.rules + 1] = r
  SUPPLY.save()
  SUPPLY.at = -999                                 -- (filled at the next tick)
  return true, "From now on " .. target .. " is kept at " .. SUPPLY.amount(r, keep) .. " " .. name .. " from AE2 (checked every " ..
               tostring(tonumber(CONFIG.supply and CONFIG.supply.every) or 10) .. " s; nothing is ever taken out of it)"
end

-- stop rules: by number, by storage name, or "all"; returns how many
function SUPPLY.stop(what)
  local n = 0
  local idx = tonumber(what)
  for i = #SUPPLY.rules, 1, -1 do
    local r = SUPPLY.rules[i]
    if what == "all" or i == idx or r.target == what or r.name == SUPPLY.fullName(what) then
      table.remove(SUPPLY.rules, i)
      n = n + 1
    end
  end
  if n > 0 then SUPPLY.save() end
  return n
end

-- the console command (lines to print)
function SUPPLY.command(words)
  local out = {}
  local function say(s) out[#out + 1] = s end
  local a = words[2]
  if a == "stop" then
    local n = SUPPLY.stop(words[3] or "")
    say(n > 0 and (n .. " supply rule(s) stopped. What is in the storage stays there.") or "No such rule. Type  supply  to see them.")
    return out
  end
  if a == "check" then
    local cands, others = SUPPLY.candidates(), SUPPLY.others()
    local name = words[3]
    if tonumber(name) and not peripheral.isPresent(name) then
      local i = tonumber(name)
      name = cands[i] or others[i - #cands]
    end
    if not name or not peripheral.isPresent(name) then
      say("Use:  supply check <number or name>  (the numbers from  supply)")
      return out
    end
    local ty, fns = SUPPLY.describe(name)
    local isInv, isFluid = SUPPLY.kinds(name)
    say(name .. "  type: " .. ty)
    say("  items: " .. (isInv and "yes" or "no") .. "   fluids: " .. (isFluid and "yes" or "no") ..
        (SUPPLY.refuse(name) and ("   NOT usable: " .. SUPPLY.refuse(name)) or ""))
    say("  functions: " .. (#fns > 0 and table.concat(fns, " ") or "none"))
    return out
  end
  if a == "now" then
    SUPPLY.at = -999
    SUPPLY.tick()
    a = nil
  end
  if a then
    -- supply <storage|number> <item> <count>   /   supply <storage|number> fluid <fluid> <buckets>
    local target = a
    local cands = SUPPLY.candidates()
    if tonumber(a) and cands[tonumber(a)] and not peripheral.isPresent(a) then target = cands[tonumber(a)] end
    local kind, name, keep = "item", words[3], words[4]
    if (words[3] or ""):lower() == "fluid" then
      kind, name, keep = "fluid", words[4], tonumber(words[5]) and tonumber(words[5]) * 1000
    end
    if not name or not keep then
      say("Use:  supply <storage> <item> <count>   or   supply <storage> fluid <fluid> <buckets>")
      say("e.g.  supply 1 coal 128   /   supply 2 fluid water 16")
      return out
    end
    local ok, msg = SUPPLY.add(target, kind, name, keep)
    say(msg)
    if ok then SUPPLY.tick() end
    return out
  end
  if #SUPPLY.rules == 0 then
    say("Nothing is being supplied yet.")
  else
    say("KEPT STOCKED FROM AE2:")
    for i, r in ipairs(SUPPLY.rules) do
      say(string.format(" %d. %s: %s %s  (has %s)  %s", i, r.target, SUPPLY.amount(r, r.keep), r.name,
          r.have and SUPPLY.amount(r, r.have) or "?", r.why and ("- " .. r.why) or ("ok, " .. SUPPLY.amount(r, r.moved or 0) .. " put in so far")))
    end
  end
  local cands = SUPPLY.candidates()
  if #cands > 0 then
    say("Storages on the cable (use the number or the name):")
    for i, n in ipairs(cands) do
      local isInv, isFluid = SUPPLY.kinds(n)
      say(string.format(" %d. %s  (%s)", i, n, (isInv and isFluid) and "items + fluids" or (isFluid and "fluids" or "items")))
    end
  else
    say("No usable storage on the cable yet.")
  end
  -- everything else on the cable: a modded block the base cannot fill (yet) shows up here
  local others = SUPPLY.others()
  if #others > 0 then
    say("Other blocks on the cable (the base's own, or no storage functions it knows):")
    for i, n in ipairs(others) do
      local ty = SUPPLY.describe(n)
      local why = SUPPLY.refuse(n)
      local used = why and why:match("is the base's own (%a+)") or (why and why:find("fluid buffer", 1, true) and "fluid buffer")
                   or (why and why:find("factory chest", 1, true) and "factory chest")
      say(string.format(" %d. %s  (%s)", #cands + i, n, used and ("used by the base: " .. used) or ty))
    end
    say("  supply check <number> lists what one of them offers - send me that line.")
  end
  say("Not in either list? Its modem is off: right-click the wired modem ON the block (it turns red;")
  say("  chat says 'Peripheral ... connected'). A full-block modem works on any side.")
  say("supply <storage> <item> <count> | supply <storage> fluid <fluid> <buckets> | supply stop <n|storage|all> | supply now | supply check <n>")
  return out
end
