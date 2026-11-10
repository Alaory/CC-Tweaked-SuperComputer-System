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
--     in a charm slot). CURIOS.autoTick (comms worker) reads the slots every
--     8 s while there are rules and puts a new one on from AE2 when the slot
--     is empty again (the totem was used). curios_auto.dat.

CURIOS = { fits = {}, auto = {}, busy = {}, lastRead = -100 }
local FITS_FILE, AUTO_FILE = "curios_fits.dat", "curios_auto.dat"

local function load(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local t = h and textutils.unserialize(h.readAll() or "")
  if h then h.close() end
  return type(t) == "table" and t or nil
end
CURIOS.fits = load(FITS_FILE) or {}
CURIOS.auto = load(AUTO_FILE) or {}
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

-- AUTO-EQUIP (comms worker, every 2 s; reads the slots every 2 s while there
-- are rules). A rule whose item is not worn in its slot type and a slot of that
-- type is free: one comes out of AE2 and is put on (the action worker runs it,
-- like a tap). After a failure it waits 60 s; the reason is shown on the tab.
function CURIOS.autoTick()
  if #CURIOS.auto == 0 or not inv or not bridge or not fetchCurios then return end
  -- every comms tick (2 s): a used totem must be replaced FAST (was every 8 s)
  if os.clock() - CURIOS.lastRead < 1.5 then return end
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
          CURIOS.busy[key] = os.clock() + 20         -- (until the slots are read again after it ran)
          r.why = nil
          -- FIRST in line (before anything else you queued), the worker woken at once
          table.insert(state.actionQueue, 1, { kind = "cequip", name = r.item, count = 1, slotType = r.slot,
                                               slotNo = slotNo, auto = true, key = "auto:" .. key })
          os.queueEvent("inv_action")
        else
          r.why = "none left in AE2"
          CURIOS.busy[key] = os.clock() + 60
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
    if pushNote then pushNote("DONE", "Auto-equipped " .. (a.display or prettify(a.name)) .. " (" .. a.slotType .. ")", C.good) end
  else
    CURIOS.busy[key] = os.clock() + 60
  end
end
