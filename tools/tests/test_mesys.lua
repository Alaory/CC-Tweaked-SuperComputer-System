-- AE2 SYSTEM (base_meplus.lua MEX + base_ui_mesys.lua): with a NEW Advanced Peripherals bridge
-- (craft job objects, the me_crafting event, CPUs, drives, patterns, external storage, cancel)
-- everything is shown and your craft requests are followed to the end; with an OLD bridge
-- (no such functions) nothing breaks and the page says what is missing.
local notes = {}
local push0 = pushNote
pushNote = function(title, msg) notes[#notes + 1] = tostring(title) .. ": " .. tostring(msg) end
local function noted(s) for _, n in ipairs(notes) do if n:find(s, 1, true) then return true end end end
local cancelled, jobs, nextId = {}, {}, 0
local function job(missing)
  nextId = nextId + 1
  local j = { id = nextId, done = false }
  j.obj = { getId = function() return j.id end, isDone = function() return j.done end,
            isCanceled = function() return false end, isCalculationNotSuccessful = function() return missing ~= nil end,
            isCraftingStarted = function() return true end, getItemProgress = function() return 3 end,
            getTotalItems = function() return 4 end,
            getMissingItems = function() return missing end, cancel = function() j.cancelled = true return true end }
  jobs[#jobs + 1] = j
  return j
end
local nextMissing
bridgeKind = "ME"
bridge = {
  isOnline = function() return true end, isConnected = function() return true end,
  getItems = function() return {} end,
  getStoredEnergy = function() return 1500000 end, getEnergyCapacity = function() return 2000000 end,
  getEnergyUsage = function() return 120 end, getAverageEnergyInput = function() return 400 end,
  getTotalItemStorage = function() return 1048576 end, getUsedItemStorage = function() return 524288 end,
  getTotalExternalItemStorage = function() return 10000 end, getUsedExternalItemStorage = function() return 9500 end,
  getCraftingCPUs = function() return {
    { name = "Big CPU", isBusy = true, storage = 65536, coProcessors = 4, selectionMode = "ANY",
      craftingJob = { quantity = 64, crafted = 16, completion = 0.25, resource = { name = "minecraft:stick", displayName = "Stick" } } },
    { name = "Unnamed", isBusy = false, storage = 1024, coProcessors = 0 } } end,
  getCraftingTasks = function() return {
    { quantity = 64, crafted = 16, completion = 0.25, bridge_id = -1, resource = { name = "minecraft:stick", displayName = "Stick" },
      cpu = { name = "Big CPU" } } } end,
  getDrives = function() return {
    { name = "ME Drive", usedBytes = 3000, totalBytes = 4096, priority = 0, position = { x = 1, y = 2, z = 3 },
      cells = { { item = { name = "ae2:item_storage_cell_1k", displayName = "1k ME Storage Cell" }, usedBytes = 1000, bytes = 1024, type = "ae2:i" },
                { item = { name = "ae2:fluid_storage_cell_4k", displayName = "4k ME Fluid Cell" }, usedBytes = 2000, bytes = 4096, type = "ae2:f" } } } } end,
  getPatterns = function() return {
    { patternType = "crafting", primaryOutput = { name = "minecraft:stick", count = 4 },
      inputs = { { primaryInput = { name = "minecraft:oak_planks", count = 1 }, multiplier = 2 } } },
    { patternType = "processing", primaryOutput = { name = "minecraft:torch", count = 4 },
      inputs = { { primaryInput = { name = "minecraft:stick", count = 1 }, multiplier = 1 },
                 { primaryInput = { name = "minecraft:coal", count = 1 }, multiplier = 1 } } } } end,
  craftItem = function(f) local j = job(nextMissing) return j.obj end,
  cancelCraftingTasks = function(f) cancelled[#cancelled + 1] = f.name return 1 end,
}
state.me = { items = {}, byName = { ["minecraft:stick"] = { name = "minecraft:stick", display = "Stick", count = 5 } } }
MEX.readAt, MEX.patAt, MEX.data = -1e9, -1e9, nil
MEX.read()
local d = MEX.data
CHECK(d.cpus and #d.cpus == 2 and d.cpus[1].busy and d.cpus[1].job.name == "Stick", "CPUs: 2, the big one busy with Sticks")
CHECK(d.tasks and #d.tasks == 1 and d.tasks[1].cpu == "Big CPU", "the running job and its CPU (the CPU's own job not doubled)")
-- the owner's bridge: getCraftingTasks lists only ITS jobs -> busy CPUs' jobs are added
local gct = bridge.getCraftingTasks
bridge.getCraftingTasks = function() return {} end
local cpus0 = bridge.getCraftingCPUs
bridge.getCraftingCPUs = function() local l = cpus0()
  l[#l + 1] = { name = "Unnamed", isBusy = true, storage = 29272571904, coProcessors = 3136,
                craftingJob = { quantity = 10, resource = { chemical = "mekanism:oxygen" } } }
  return l end
MEX.read()
CHECK(#MEX.data.tasks == 2, "jobs from the busy CPUs when the bridge's own list is empty (" .. #MEX.data.tasks .. ")")
CHECK(MEX.data.tasks[2].name == "Oxygen", "a job whose resource has no name/displayName is still named (" ..
      tostring(MEX.data.tasks[2].name) .. ")")
CHECK(fmtBytes(29272571904) == "27 GB" and compact(8862200000) == "8.86b", "bytes / billions read right")
bridge.getCraftingTasks, bridge.getCraftingCPUs = gct, cpus0
MEX.read()
CHECK(d.drives and #d.drives[1].cells == 2, "the drive with its 2 cells")
local ext
for _, s in ipairs(d.store) do if s.kind == "Item" then ext = s.ext end end
CHECK(ext and ext.used == 9500 and ext.max == 10000, "external (storage bus) item storage")
CHECK(MEX.byOut["minecraft:stick"] and MEX.byOut["minecraft:stick"][1].ins[1].n == 2 and MEX.byIn["minecraft:stick"] == 1,
      "patterns: sticks are made from 2 planks, used in 1 other pattern")
-- a craft request that misses something: the event names what is missing
nextMissing = { { name = "minecraft:iron_ingot", displayName = "Iron Ingot", count = 3 } }
CHECK(craftME("minecraft:stick", 64) == true, "craftME goes through MEX")
local k1 = MEX.order[1]
CHECK(MEX.jobs[k1].state == "calculating" and MEX.jobs[k1].id == 1, "the request is followed (calculating, bridge id 1)")
MEX.event(true, 1, "MISSING_ITEMS")
MEX.jobTick()
CHECK(MEX.jobs[k1].state == "missing" and noted("missing 3 x Iron Ingot"), "MISSING: the warning names the missing items")
-- a good one: crafting, then done (event)
nextMissing = nil
craftME("minecraft:stick", 8)
local k2 = MEX.order[1]
MEX.event(false, 2, "CRAFTING_STARTED") MEX.jobTick()
CHECK(MEX.jobs[k2].state == "crafting", "crafting started")
MEX.event(false, 2, "JOB_DONE") MEX.jobTick()
CHECK(MEX.jobs[k2].state == "done" and noted("8 x Stick is ready"), "DONE: a note when it is ready")
-- no event (older bridge): the job object is asked every 10 s
craftME("minecraft:stick", 2)
local k3 = MEX.order[1]
jobs[3].done = true
CLOCK = CLOCK + 11
MEX.jobTick()
CHECK(MEX.jobs[k3].state == "done", "without an event the job object is asked (isDone)")
-- the page
local function screen()
  hits = {}
  draw()
  local out = {}
  for y = 1, H do out[#out + 1] = (MONITOR.getLine(y)) end
  return table.concat(out, "\n")
end
state.page = "mesys"
state.meSel = "minecraft:stick"
local s = screen()
CHECK(s:find("CRAFTING CPUS", 1, true) and s:find("Big CPU", 1, true) and s:find("BUSY", 1, true), "page: the CPUs")
CHECK(s:find("MISSING", 1, true) and s:find("missing: 3 x Iron Ingot", 1, true), "page: your request and what it misses")
CHECK(s:find("ME Drive", 1, true) and s:find("1k ME Storage Cell", 1, true), "page: drives and cells")
CHECK(s:find("Items in storage buses", 1, true), "page: external storage")
CHECK(s:find("MAKES 4 X STICK", 1, true) and s:find("2 x Oak Planks", 1, true), "page: the AE2 page's picked item -> its pattern")
CHECK(s:find("AE2 SYSTEM 1 job", 1, true), "the chip shows running jobs")
-- CANCEL (two taps) -> cancelCraftingTasks for the item
local function hitOf(kind, name)
  for _, h in ipairs(hits) do if h[5] == kind and type(h[6]) == "table" and h[6].kind == name then return h end end
end
local h = hitOf("act", "mecancel")
CHECK(h, "a CANCEL button on the running job")
if h then
  handleTouch(h[1], h[2])
  screen()
  h = hitOf("act", "mecancel")
  handleTouch(h[1], h[2])
  local a = table.remove(state.actionQueue, 1)
  state.busy = false
  if a then runAction(a) end
end
CHECK(cancelled[1] == "minecraft:stick", "CANCEL cancelled the Stick jobs (" .. tostring(cancelled[1]) .. ")")
-- PATTERNS can be used (the owner: "i cant interact with the patterns"): pick one, see what
-- goes in vs what AE2 has, CRAFT from it; filter by type
state.meSel = nil
s = screen()
local function hitK(kind, val)
  for _, hh in ipairs(hits) do if hh[5] == kind and (val == nil or hh[6] == val) then return hh end end
end
local row = hitK("patsel")
CHECK(row, "pattern rows can be tapped")
if row then handleTouch(row[1], row[2]) end
s = screen()
CHECK(s:find("MAKES 4 X STICK", 1, true) and s:find("SHORT - AE2 has 0", 1, true), "a picked pattern: what goes in, what is short")
local crafted
local ci = bridge.craftItem
bridge.craftItem = function(f) crafted = f return ci(f) end
local cb
for _, hh in ipairs(hits) do if hh[5] == "act" and hh[6].kind == "craft" and hh[6].count == 16 then cb = hh end end
CHECK(cb, "CRAFT x16 under the picked pattern")
if cb then
  handleTouch(cb[1], cb[2]) screen()
  for _, hh in ipairs(hits) do if hh[5] == "act" and hh[6].kind == "craft" and hh[6].count == 16 then cb = hh end end
  handleTouch(cb[1], cb[2])
  local a = table.remove(state.actionQueue, 1)
  state.busy = false
  if a then runAction(a) end
end
CHECK(crafted and crafted.name == "minecraft:stick" and crafted.count == 16, "two taps on CRAFT x16 asked AE2 for 16 sticks")
bridge.craftItem = ci
local pt = hitK("pattype", "processing")
CHECK(pt, "a PROCESSING filter button")
if pt then handleTouch(pt[1], pt[2]) end
s = screen()
local n = 0
for _, hh in ipairs(hits) do if hh[5] == "patsel" then n = n + 1 end end
CHECK(state.patType == "processing" and n == 1 and s:find("Torch", 1, true), "filtered: only the processing pattern (" .. n .. ")")
state.patType, state.patSel, MEX.pv = nil, nil, nil
-- in game: chemical outputs / inputs come back EMPTY (200+ patterns showed "?"), and some busy
-- CPUs' jobs are only { bridgeId = -1, quantity = 400000 } (`me raw`)
local gp, gc = bridge.getPatterns, bridge.getCraftingCPUs
bridge.getPatterns = function() local l = gp()
  l[#l + 1] = { patternType = "processing", inputs = { { primaryInput = { name = "mekanism:salt", count = 1 }, multiplier = 1 },
                                                       { multiplier = 1 } } }
  return l end
bridge.getCraftingCPUs = function() local l = gc()
  l[#l + 1] = { name = "Unnamed", isBusy = true, storage = 2000, coProcessors = 3136, craftingJob = { bridgeId = -1, quantity = 400000 } }
  return l end
MEX.patAt, MEX.pv = -1e9, nil
MEX.read()
local unnamedJob
for _, t in ipairs(MEX.data.tasks) do if t.qty == 400000 then unnamedJob = t end end
CHECK(unnamedJob and unnamedJob.name == MEX.UNNAMED, "a job with no resource: 'not named by the bridge' (" .. tostring(unnamedJob and unnamedJob.name) .. ")")
s = screen()
CHECK(s:find("chemical from Salt", 1, true) and not s:find("\n%?%s"), "a chemical pattern is named by what goes in")
local chemRow
for _, hh in ipairs(hits) do if hh[5] == "patsel" and tostring(hh[6]):find("^nil|processing") then chemRow = hh end end
CHECK(chemRow, "the chemical pattern can be picked")
if chemRow then handleTouch(chemRow[1], chemRow[2]) end
s = screen()
local craftBtn = false
for _, hh in ipairs(hits) do if hh[5] == "act" and hh[6].kind == "craft" then craftBtn = true end end
CHECK(s:find("MAKES A CHEMICAL", 1, true) and s:find("1 chemical(s) the bridge cannot name", 1, true) and not craftBtn,
      "picked: it makes a chemical, an unnamed input counted, no CRAFT button")
bridge.getPatterns, bridge.getCraftingCPUs = gp, gc
state.patSel, MEX.pv, MEX.patAt = nil, nil, -1e9
MEX.read()

-- an OLD bridge: none of the new functions
local new = bridge
bridge = { getItems = function() return {} end, craftItem = function() return true end }
MEX.readAt, MEX.data, MEX.patterns = -1e9, nil, nil
MEX.read()
CHECK(MEX.data.cpus == nil and MEX.data.drives == nil, "old bridge: no CPUs / drives (no error)")
CHECK(craftME("minecraft:stick", 1) == true and MEX.jobs[MEX.order[1]].state == "requested", "old bridge: craft still works (sent)")
s = screen()
CHECK(s:find("Crafting CPUs: not on this ME Bridge", 1, true), "old bridge: the page says what is missing")
bridge = new
pushNote = push0
