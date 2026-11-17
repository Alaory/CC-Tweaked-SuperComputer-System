-- base_meplus.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MORE OF THE ME BRIDGE (MEX; the AE2 SYSTEM page base_ui_mesys.lua): crafting CPUs,
--   every running crafting job (with CANCEL), YOUR craft requests followed to the end
--   (the bridge's job object + the "me_crafting" event: calculating -> crafting -> done,
--   or the MISSING items named), drives with every cell, internal AND external (storage
--   bus) storage, energy, and the PATTERNS (what an item is made from / used in).
--   Advanced Peripherals versions differ (the owner's server is older than the docs):
--   every function is looked up by NAME and a feature simply stays off when it is missing.

MEX = { jobs = {}, order = {}, events = {}, data = nil, patAt = -1e9, readAt = -1e9, nextId = 0 }

-- does the bridge have this function?
function MEX.has(fn) return bridge ~= nil and type(bridge[fn]) == "function" end

local function get(fn, ...)
  if not MEX.has(fn) then return nil end
  local ok, a, b = pcall(bridge[fn], ...)
  if not ok then return nil, tostring(a) end
  return a, b
end
local function first(...)                            -- the first function name that exists and answers
  for _, fn in ipairs({ ... }) do
    local v = get(fn)
    if v ~= nil then return tonumber(v) or v end
  end
end
local function nameOf(res)
  if type(res) ~= "table" then return tostring(res or "?") end
  local n = res.displayName or (res.name and prettify(tostring(res.name))) or "?"
  return (cleanName and cleanName(n)) or n
end

-- one reading (page worker: the AE2 SYSTEM page every 3 s; patterns every 5 min)
function MEX.read()
  if not bridge then MEX.data = nil return end
  local d = MEX.data or {}
  MEX.data = d
  d.t = os.clock()
  d.online = get("isOnline")
  d.connected = get("isConnected")
  -- energy
  d.energy = { stored = first("getStoredEnergy"), cap = first("getEnergyCapacity"), usage = first("getEnergyUsage"),
               inj = first("getAverageEnergyInput", "getAvgPowerInjection") }
  -- storage: internal (cells; AE2 counts bytes) and external (storage buses; counted in items / mB)
  local function store(kind, ext)
    local K = ext and ("External" .. kind) or kind
    local K2 = ext and ("Extern" .. kind) or kind
    local used = first("getUsed" .. K .. "Storage", "getUsed" .. K2 .. "Storage", ext and ("getUsedExtern" .. kind .. "Count") or "-")
    local max = first("getTotal" .. K .. "Storage", "getMax" .. K2 .. "Storage", "getMax" .. K .. "Storage",
                      ext and ("getMaxExtern" .. kind .. "Count") or "-")
    if used and max then return { used = used, max = max } end
  end
  d.store = {}
  for _, k in ipairs({ "Item", "Fluid", "Chemical" }) do
    d.store[#d.store + 1] = { kind = k, inner = store(k, false), ext = store(k, true) }
  end
  -- crafting CPUs
  local cpus = get("getCraftingCPUs")
  d.cpus = nil
  if type(cpus) == "table" then
    d.cpus = {}
    for _, c in pairs(cpus) do
      if type(c) == "table" then
        local job = type(c.craftingJob) == "table" and c.craftingJob or nil
        d.cpus[#d.cpus + 1] = { name = tostring(c.name or "Unnamed"), busy = c.isBusy == true,
          storage = tonumber(c.storage), co = tonumber(c.coProcessors), mode = c.selectionMode,
          job = job and { name = nameOf(job.resource), qty = tonumber(job.quantity) or 0,
                          done = tonumber(job.crafted), f = tonumber(job.completion) } or nil }
      end
    end
    table.sort(d.cpus, function(a, b) return a.name < b.name end)
  end
  -- every running crafting job (also ones started in a terminal)
  local tasks = get("getCraftingTasks")
  d.tasks = nil
  if type(tasks) == "table" then
    d.tasks = {}
    for _, t in pairs(tasks) do
      if type(t) == "table" then
        local res = type(t.resource) == "table" and t.resource or {}
        d.tasks[#d.tasks + 1] = { name = nameOf(res), item = res.name, qty = tonumber(t.quantity) or 0,
          done = tonumber(t.crafted) or 0, f = tonumber(t.completion) or 0, bid = tonumber(t.bridge_id),
          cpu = type(t.cpu) == "table" and t.cpu.name or nil, id = t.id }
      end
    end
  end
  -- drives with their cells
  local drives = get("getDrives")
  d.drives = nil
  if type(drives) == "table" then
    d.drives = {}
    for _, dr in pairs(drives) do
      if type(dr) == "table" then
        local cells = {}
        for _, c in pairs(type(dr.cells) == "table" and dr.cells or {}) do
          if type(c) == "table" then
            cells[#cells + 1] = { name = nameOf(c.item), used = tonumber(c.usedBytes) or 0, bytes = tonumber(c.bytes) or 0,
                                  kind = tostring(c.type or "") }
          end
        end
        local p = type(dr.position) == "table" and dr.position or {}
        d.drives[#d.drives + 1] = { name = tostring(dr.name or "Drive"), used = tonumber(dr.usedBytes) or 0,
          bytes = tonumber(dr.totalBytes) or 0, cells = cells, prio = tonumber(dr.priority),
          pos = p.x and string.format("%d %d %d", p.x, p.y, p.z) or nil }
      end
    end
  end
  -- patterns (heavy on a big network: every 5 minutes)
  if MEX.has("getPatterns") and os.clock() - MEX.patAt > 300 then
    MEX.patAt = os.clock()
    local pats = get("getPatterns")
    if type(pats) == "table" then MEX.setPatterns(pats) end
  end
  MEX.readAt = os.clock()
end

-- patterns -> { out, outN, type, ins = { {name, n} } }, by output and by input
function MEX.setPatterns(pats)
  local list, byOut, byIn = {}, {}, {}
  for _, p in pairs(pats) do
    if type(p) == "table" then
      local po = type(p.primaryOutput) == "table" and p.primaryOutput or (type(p.outputs) == "table" and p.outputs[1]) or {}
      local e = { out = tostring(po.name or "?"), outN = tonumber(po.count or po.amount) or 1,
                  type = tostring(p.patternType or "?"), ins = {} }
      for _, inp in pairs(type(p.inputs) == "table" and p.inputs or {}) do
        local pi = type(inp) == "table" and (inp.primaryInput or inp) or {}
        if type(pi) == "table" and pi.name then
          local n = (tonumber(pi.count or pi.amount) or 1) * (tonumber(inp.multiplier) or 1)
          local found
          for _, x in ipairs(e.ins) do if x.name == pi.name then found = x end end
          if found then found.n = found.n + n else e.ins[#e.ins + 1] = { name = tostring(pi.name), n = n } end
        end
      end
      list[#list + 1] = e
      byOut[e.out] = byOut[e.out] or {}
      table.insert(byOut[e.out], e)
      for _, x in ipairs(e.ins) do byIn[x.name] = (byIn[x.name] or 0) + 1 end
    end
  end
  MEX.patterns, MEX.byOut, MEX.byIn = list, byOut, byIn
end

-- page worker: read when stale
function MEX.tick(onPage)
  if not bridge then return false end
  if os.clock() - MEX.readAt < (onPage and 3 or 60) then return false end
  MEX.read()
  return true
end

---------------------------------------------------------------------
-- YOUR CRAFT REQUESTS: followed to the end
---------------------------------------------------------------------
-- (craftME / craftFluidME call this) -> ok, error
function MEX.craft(name, count, fluid)
  local fn = fluid and "craftFluid" or "craftItem"
  if not MEX.has(fn) then return false, "this bridge cannot craft" end
  local filter = fluid and { name = name, amount = count } or { name = name, count = count }
  local ok, r, e = pcall(bridge[fn], filter)
  if not ok then return false, tostring(r) end
  if r == nil or r == false then return false, tostring(e or "craft request failed") end
  MEX.nextId = MEX.nextId + 1
  local j = { key = MEX.nextId, name = name, count = count, fluid = fluid, t = os.clock(), state = "requested",
              obj = type(r) == "table" and r or nil }
  if j.obj and type(j.obj.getId) == "function" then
    local okI, id = pcall(j.obj.getId)
    if okI then j.id = tonumber(id) end
  end
  if j.obj then j.state = "calculating" end
  MEX.jobs[j.key] = j
  table.insert(MEX.order, 1, j.key)
  while #MEX.order > 20 do MEX.jobs[table.remove(MEX.order)] = nil end
  return true
end

-- the "me_crafting" / "rs_crafting" event (error, id, message): handled in MEX.jobTick
function MEX.event(err, id, msg)
  MEX.events[#MEX.events + 1] = { err = err == true, id = tonumber(id), msg = tostring(msg or "") }
end

local function jobByBridgeId(id)
  for _, k in ipairs(MEX.order) do
    local j = MEX.jobs[k]
    if j and j.id == id then return j end
  end
end
local function disp(j)
  local known = state.me and (j.fluid and state.me.byNameF or state.me.byName)
  local e = known and known[j.name]
  return (e and e.display) or prettify(j.name)
end
local function amount(j) return j.fluid and fmtBuckets(j.count) or (commas(j.count) .. " x") end

-- what is missing, as text ("3 x Iron Ingot, 1 x Redstone")
local function missingText(j)
  if not (j.obj and type(j.obj.getMissingItems) == "function") then return nil end
  local ok, m = pcall(j.obj.getMissingItems)
  if not ok or type(m) ~= "table" then return nil end
  local parts = {}
  for _, it in pairs(m) do
    if type(it) == "table" then
      parts[#parts + 1] = commas(tonumber(it.count or it.amount) or 0) .. " x " .. nameOf(it)
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

-- a job's new state (from the event, or from asking the job object)
local function setState(j, s, why)
  if j.state == s then return end
  j.state, j.why, j.at = s, why, os.clock()
  local what = amount(j) .. " " .. disp(j)
  if s == "done" then pushNote("CRAFTED", what .. " is ready in AE2", C.good, nil, "DONE")
  elseif s == "missing" then
    j.missing = missingText(j)
    pushNote("CANNOT CRAFT", what .. ": missing " .. (j.missing or "ingredients"), C.warn, nil, "WARNING")
  elseif s == "failed" then pushNote("CANNOT CRAFT", what .. ": " .. tostring(why or "failed"), C.warn, nil, "WARNING")
  elseif s == "cancelled" then pushNote("CRAFT CANCELLED", what, C.dim, nil, "INFO") end
end
local MSG = { CALCULATION_STARTED = "calculating", CRAFTING_STARTED = "crafting", JOB_DONE = "done",
              JOB_CANCELED = "cancelled", MISSING_ITEMS = "missing" }

-- comms worker: events first, then jobs that never send one (older bridges) are asked
function MEX.jobTick()
  while #MEX.events > 0 do
    local ev = table.remove(MEX.events, 1)
    local j = ev.id and jobByBridgeId(ev.id)
    if j then
      local s = MSG[ev.msg] or (ev.err and "failed") or nil
      if s then setState(j, s, (s == "failed") and prettify(ev.msg:lower()) or nil) end
      j.heard = os.clock()
    end
  end
  for _, k in ipairs(MEX.order) do
    local j = MEX.jobs[k]
    local open = j and (j.state == "calculating" or j.state == "crafting")
    if open and j.obj and os.clock() - (j.asked or 0) >= 10 then
      j.asked = os.clock()
      local function q(fn) local f = j.obj[fn] if type(f) ~= "function" then return nil end local ok, v = pcall(f) return ok and v end
      if q("isDone") then setState(j, "done")
      elseif q("isCanceled") then setState(j, "cancelled")
      elseif q("isCalculationNotSuccessful") then setState(j, "missing")
      elseif q("isCraftingStarted") then setState(j, "crafting") end
      local prog, total = q("getItemProgress"), q("getTotalItems")
      if tonumber(prog) and tonumber(total) and tonumber(total) > 0 then j.f = tonumber(prog) / tonumber(total) end
    end
  end
end

-- cancel: a request of ours (its job object), else every job for that item (cancelCraftingTasks)
function MEX.canCancel() return MEX.has("cancelCraftingTasks") end
function MEX.cancel(item, key)
  local j = key and MEX.jobs[key]
  if j and j.obj and type(j.obj.cancel) == "function" then
    local ok, r = pcall(j.obj.cancel)
    if ok and r ~= false then setState(j, "cancelled") return true end
  end
  if item and MEX.has("cancelCraftingTasks") then
    local ok, n = pcall(bridge.cancelCraftingTasks, { name = item })
    if ok and (tonumber(n) or 0) > 0 then
      for _, k in ipairs(MEX.order) do
        local jj = MEX.jobs[k]
        if jj and jj.name == item and (jj.state == "calculating" or jj.state == "crafting") then setState(jj, "cancelled") end
      end
      return true
    end
    return false, ok and "no job was running for it" or tostring(n)
  end
  return false, "this bridge cannot cancel jobs"
end

-- for the console (`me jobs` / `me cpus`)
function MEX.lines()
  local d = MEX.data or {}
  local L = {}
  if d.cpus then
    L[#L + 1] = "Crafting CPUs: " .. #d.cpus
    for _, c in ipairs(d.cpus) do
      L[#L + 1] = "  " .. c.name .. " - " .. (c.busy and ("BUSY: " .. (c.job and c.job.name or "?")) or "idle") ..
                  (c.storage and ("  " .. compact(c.storage) .. " bytes") or "") .. (c.co and ("  " .. c.co .. " co-processors") or "")
    end
  end
  for _, t in ipairs(d.tasks or {}) do
    L[#L + 1] = string.format("  job: %s %d/%d (%d%%)%s", t.name, t.done, t.qty, math.floor(t.f * 100), t.cpu and ("  on " .. t.cpu) or "")
  end
  for _, k in ipairs(MEX.order) do
    local j = MEX.jobs[k]
    if j then L[#L + 1] = "  yours: " .. amount(j) .. " " .. disp(j) .. " - " .. j.state .. (j.missing and (": missing " .. j.missing) or "") end
  end
  if MEX.patterns then L[#L + 1] = "Patterns: " .. #MEX.patterns end
  if #L == 0 then L[1] = "Nothing more from this bridge (an older Advanced Peripherals?)." end
  return L
end
