-- base_curios.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   CURIOS helpers for the CURIOS tab:
--   - what fits a slot type: items tagged curios:<slot> are NOT all of them -
--     many mods make an item wearable in code, without a tag, and with the
--     partial ME view only tagged items were ever found. So the tab also
--     shows items LEARNED to fit (worn before, or put on from here once:
--     CURIOS.fits, curios_fits.dat) and can list ANY item in the network to
--     simply try (Curios refuses what does not fit; it goes back).
--   - AUTO-EQUIP: "keep one <item> on in <slot type>" (e.g. a Totem of Undying
--     in a charm slot). CURIOS.autoTick (its OWN worker, curiosWorker) reads the
--     slots EVERY TICK (CONFIG.curios.every, 0.05 s) while there are rules and
--     puts a new one on from AE2 AT ONCE when the slot is empty again (the totem
--     was used) - the owner plays HARDCORE. curios_auto.dat.

CURIOS = { fits = {}, auto = {}, busy = {}, lastRead = -100 }
CURIO_BUSY = false                -- (a curios move is running - runAction and the every-tick auto-equip never overlap)
local FITS_FILE, AUTO_FILE = "curios_fits.dat", "curios_auto.dat"

local function load(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local t = h and textutils.unserialize(h.readAll() or "")
  if h then h.close() end
  return type(t) == "table" and t or nil
end
-- (an odd / old file never stops the base: only {slot = {item = true}} and {slot, item} rules are kept)
do
  local fits, auto = {}, {}
  for slot, list in pairs(load(FITS_FILE) or {}) do
    if type(slot) == "string" and type(list) == "table" then
      local l = {}
      for n, v in pairs(list) do if type(n) == "string" and v then l[n] = true end end
      fits[slot] = l
    end
  end
  for _, r in ipairs(load(AUTO_FILE) or {}) do
    if type(r) == "table" and type(r.slot) == "string" and type(r.item) == "string" then
      auto[#auto + 1] = { slot = r.slot, item = r.item, display = type(r.display) == "string" and r.display or nil }
    end
  end
  CURIOS.fits, CURIOS.auto = fits, auto
end
for _, list in pairs(CURIOS.fits) do
  for n in pairs(list) do if meRememberName then meRememberName(n) end end   -- (the partial ME view looks them up)
end

function CURIOS.save()
  saveFileSafe(FITS_FILE, serialSmall(CURIOS.fits))
  saveFileSafe(AUTO_FILE, serialSmall(CURIOS.auto))
end

-- item `name` fits slot type `slot` (seen worn there, or put on from here)
function CURIOS.learn(slot, name)
  if type(slot) ~= "string" or type(name) ~= "string" then return end
  CURIOS.fits[slot] = CURIOS.fits[slot] or {}
  if not CURIOS.fits[slot][name] then
    CURIOS.fits[slot][name] = true
    if meRememberName then meRememberName(name) end
    CURIOS.save()
  end
end
-- everything worn now is learned as fitting its slot type
function CURIOS.learnWorn(rows)
  for _, row in ipairs(rows or {}) do
    for _, it in pairs(row.cells or {}) do
      if type(it) == "table" and it.name then CURIOS.learn(row.name, it.name) end
    end
  end
end

-- the auto-equip rule for this slot type + item (index), if there is one
function CURIOS.ruleOf(slot, name)
  for i, r in ipairs(CURIOS.auto) do if r.slot == slot and r.item == name then return i end end
end
-- KEEP ONE ON: switch the rule on / off; returns true when it is on now
function CURIOS.toggleAuto(slot, name, display)
  local i = CURIOS.ruleOf(slot, name)
  if i then
    table.remove(CURIOS.auto, i)
    CURIOS.save()
    return false
  end
  CURIOS.auto[#CURIOS.auto + 1] = { slot = slot, item = name, display = display }
  CURIOS.learn(slot, name)
  CURIOS.save()
  CURIOS.lastRead = -100                          -- look at once
  os.queueEvent("curios_wake")
  return true
end

-- an empty slot of a row (listCurios' number for it) or nil
local function emptySlot(row)
  for pos = 1, row.count or 0 do
    if not row.cells[pos] then return (row.raw and row.raw[pos]) or (pos - 1 + (row.base or 1)), pos end
  end
end
-- is `name` worn in this row?
local function wearing(row, name)
  for _, it in pairs(row.cells or {}) do if type(it) == "table" and it.name == name then return true end end
  return false
end

-- AUTO-EQUIP (the owner: "make the equip item in intervals to be each tick" - a hardcore world: a used totem must be
-- back on before the next hit). curiosWorker calls CURIOS.autoTick(true) every CURIOS.every() s (a tick) while there are
-- rules: the slots are read, and a rule whose item is not worn in its slot type with a slot of that type free is put on
-- RIGHT THERE (direct: runAction in this worker - the action queue may be busy for seconds with a fluid ALL); another
-- curios move running at that moment (CURIO_BUSY) = the next tick. autoTick() without direct (old callers / tests):
-- queued FIRST in the action queue as before. A failure waits 15 s, none in AE2 10 s; the reason is shown on the tab.
function CURIOS.every()
  local v = tonumber(CONFIG.curios and CONFIG.curios.every)
  return math.max(0.05, v or 0.05)
end
function CURIOS.autoTick(direct)
  if #CURIOS.auto == 0 or not inv or not bridge or not fetchCurios then return end
  if os.clock() - CURIOS.lastRead < CURIOS.every() - 0.001 then return end
  CURIOS.lastRead = os.clock()
  local ok, rows, msg, note = pcall(fetchCurios)
  if not ok or type(rows) ~= "table" then return end
  state.curios, state.curiosMsg, state.curiosNote = rows, msg, note
  state.t.curios = os.clock()
  CURIOS.learnWorn(rows)
  if note then return end                          -- (a worn item cannot be read: the slots are only "last known")
  for _, r in ipairs(CURIOS.auto) do
    local row
    for _, x in ipairs(rows) do if x.name == r.slot then row = x end end
    local key = r.slot .. "|" .. r.item
    if row and not row.unreadable and not wearing(row, r.item) and os.clock() >= (CURIOS.busy[key] or 0) then
      local slotNo = emptySlot(row)
      if slotNo then
        local okI, it = callx(bridge, "getItem", { name = r.item })
        local have = okI and type(it) == "table" and (tonumber(it.count) or 0) or 0
        if have > 0 then
          r.why = nil
          local a = { kind = "cequip", name = r.item, count = 1, slotType = r.slot, slotNo = slotNo, auto = true,
                      key = "auto:" .. key, display = r.display }
          if direct and runAction then
            if CURIO_BUSY then return end              -- (a curios move of yours is running: the next tick)
            CURIOS.busy[key] = os.clock() + 20
            local okR, errR = pcall(runAction, a)
            if not okR then r.why = tostring(errR) CURIOS.busy[key] = os.clock() + 15 end
            CURIOS.lastRead = -100                     -- (read again next tick: did it go on? another one used?)
          else
            CURIOS.busy[key] = os.clock() + 20         -- (until the slots are read again after it ran)
            -- FIRST in line (before anything else you queued), the worker woken at once
            table.insert(state.actionQueue, 1, a)
            os.queueEvent("inv_action")
          end
        else
          r.why = "none left in AE2"
          CURIOS.busy[key] = os.clock() + 10
        end
      end
    end
  end
end
-- the result of an automatic put-on (runAction): learn it / remember why not
function CURIOS.autoResult(a, n, err)
  local key = a.slotType .. "|" .. a.name
  for _, r in ipairs(CURIOS.auto) do
    if r.slot == a.slotType and r.item == a.name then r.why = (n > 0) and nil or tostring(err or "did not go on") end
  end
  if n > 0 then
    CURIOS.learn(a.slotType, a.name)
    CURIOS.busy[key] = nil                         -- (another one used right after: put on at the next tick)
    if pushNote then pushNote("DONE", "Auto-equipped " .. (a.display or prettify(a.name)) .. " (" .. a.slotType .. ")", C.good) end
  else
    CURIOS.busy[key] = os.clock() + 15
  end
end
