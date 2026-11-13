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

SUPPLY = { rules = {}, at = -999 }
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
  if used then return name .. " is the base's own " .. used .. " - pick another storage" end
  if FACTORY and FACTORY.chest == name then return name .. " is the factory chest - pick another storage" end
  local okT, ty = pcall(peripheral.getType, name)
  ty = (okT and type(ty) == "string") and ty or ""
  for _, bad in ipairs({ "me_bridge", "inventory_manager", "drive", "computer", "turtle", "monitor", "modem" }) do
    if ty:find(bad, 1, true) then return name .. " is a " .. ty .. ", not a storage" end
  end
  return nil
end

-- what the storage can hold: "item", "fluid" or both
function SUPPLY.kinds(name)
  local function has(t) local ok, r = pcall(peripheral.hasType, name, t) return ok and r end
  return has("inventory"), has("fluid_storage")
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
    local ok, t = pcall(peripheral.call, r.target, "tanks")
    if not ok or type(t) ~= "table" then return nil, "cannot read its tanks" end
    local n = 0
    for _, tk in pairs(t) do
      if type(tk) == "table" and tk.name == r.name then n = n + (tonumber(tk.amount) or 0) end
    end
    return n
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
    for _ = 1, 16 do                             -- (some tanks take 1 bucket per call)
      local ok, res, e = transfer(bridge, { "exportFluid" }, r.target, { name = r.name, amount = need - moved })
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
      local filter = { name = r.name, count = math.min(need, plain) }
      if fp then filter.fingerprint = fp end
      local ok, res = transfer(bridge, { "exportItem" }, r.target, filter)
      moved = ok and (numOf(res) or 0) or 0
      if moved <= 0 then r.why = ok and "the storage took none (full of other things?)" or ("AE2 said: " .. tostring(res)) end
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
function SUPPLY.tick()
  if #SUPPLY.rules == 0 then return end
  local every = tonumber(CONFIG.supply and CONFIG.supply.every) or 10
  if os.clock() - SUPPLY.at < every then return end
  SUPPLY.at = os.clock()
  for _, r in ipairs(SUPPLY.rules) do pcall(SUPPLY.fill, r) end
  if SUPPLY.dirty then SUPPLY.dirty = false pcall(SUPPLY.save) end
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
    say("No free storage on the cable: put a wired modem on it and right-click the modem (it turns red).")
  end
  say("supply <storage> <item> <count> | supply <storage> fluid <fluid> <buckets> | supply stop <n|storage|all> | supply now")
  return out
end
