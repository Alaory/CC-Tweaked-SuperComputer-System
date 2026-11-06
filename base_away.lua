-- base_away.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   AWAY MODE: the owner has been offline for CONFIG.away.after seconds
--   (default 5 min; Player Detector). While away the base uses the time:
--     * turtle program updates (they wait while you play - or 2 h at most)
--     * turtles top up their fuel (3x the usual low-fuel mark)
--     * the monitor shows the MAP, zoomed out by itself to everything mapped
--       plus where the turtles are, following them (auto-map keeps surveying)
--     * the map is saved and storage helpers are looked for every 30 min
--     * auto-map, if you switched it off, runs while you are away (off again after)
--   When you are back: a WHILE YOU WERE AWAY report (box, private chat, the
--   SYSTEM tab, `away` on the computer): how long, mining per dimension,
--   map growth, turtle updates, problems, times the base was off, and what
--   needs you now. The monitor goes back to the page you had.

AWAY = { on = false, since = nil, lastSeen = nil, snap = nil, last = nil }
local FILE = "away.dat"

function AWAY.cfg(k, default)
  local a = CONFIG.away
  local v
  if type(a) == "table" then v = a[k] end
  if v == nil then return default end
  return v
end

local function save()
  saveFileSafe(FILE, textutils.serialize({ on = AWAY.on, since = AWAY.since, lastSeen = AWAY.lastSeen,
                                           snap = AWAY.snap, last = AWAY.last, page = AWAY.page,
                                           autoOn = AWAY.autoOn }))
end
do
  if fs.exists(FILE) then
    local h = fs.open(FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then
      AWAY.on, AWAY.since, AWAY.lastSeen, AWAY.snap, AWAY.last, AWAY.page = t.on, t.since, t.lastSeen, t.snap, t.last, t.page
      AWAY.autoOn = t.autoOn
    end
  end
end

-- is the owner online? true / false, or nil when we cannot tell
function AWAY.ownerOnline()
  if not det or not state.owner then return nil end
  if not fresh("players", 120) then return nil end
  for _, e in ipairs(state.players or {}) do
    if e.isOwner or tostring(e.name):lower() == tostring(state.owner):lower() then return true end
  end
  return false
end

local function copy(t)
  local o = {}
  for k, v in pairs(t or {}) do o[k] = v end
  return o
end
-- what we compare against when you are back
local function snapshot()
  local s = { mine = {}, ovN = MAP.ovN or 0, up = 0, all = 0, offs = #((BASE_ALIVE or {}).offs or {}) }
  for dim, team in pairs(MINE and MINE.teams() or {}) do
    local m = team.miner
    if m then
      s.mine[dim] = { ores = type(m.stats) == "table" and tonumber(m.stats.ores) or 0, ci = tonumber(m.ci) or 0,
                      got = copy(m.got) }
    end
  end
  for _, t in pairs(state.turtles) do
    s.all = s.all + 1
    if CODE and t.ver == CODE.ver then s.up = s.up + 1 end
  end
  return s
end

local function fmtTime(ms)
  local okD, d = pcall(os.date, "%d.%m %H:%M", math.floor(ms / 1000))
  return okD and d or "?"
end
local function itemName(n) return (tostring(n):gsub("^[^:]+:", ""):gsub("_", " ")) end

-- the report: list of { text, colour }
function AWAY.report()
  local s = AWAY.snap or {}
  local now = os.epoch("utc")
  local lines = {}
  local function add(t, col) lines[#lines + 1] = { t = t, col = col or C.text } end
  add("Away " .. fmtSpan((now - (AWAY.since or now)) / 1000) .. " (since " .. fmtTime(AWAY.since or now) .. ")", C.label)
  -- map
  local grew = (MAP.ovN or 0) - (s.ovN or 0)
  add("Map: +" .. commas(math.max(0, grew)) .. " chunks mapped (" .. commas(MAP.ovN or 0) .. " in all)",
      grew > 0 and C.good or C.dim)
  -- mining
  for dim, team in pairs(MINE and MINE.teams() or {}) do
    local m = team.miner
    if m then
      local was = (s.mine or {})[dim] or { ores = 0, ci = 0, got = {} }
      local ores = (type(m.stats) == "table" and tonumber(m.stats.ores) or 0) - (was.ores or 0)
      local chunks = (tonumber(m.ci) or 0) - (was.ci or 0)
      local diff = {}
      for k, v in pairs(m.got or {}) do
        local d = v - ((was.got or {})[k] or 0)
        if d > 0 then diff[#diff + 1] = { k, d } end
      end
      table.sort(diff, function(a, b) return a[2] > b[2] end)
      local parts = {}
      for i = 1, math.min(4, #diff) do parts[#parts + 1] = itemName(diff[i][1]) .. " " .. commas(diff[i][2]) end
      add("Mining " .. dim .. ": +" .. math.max(0, chunks) .. " chunks, +" .. commas(math.max(0, ores)) .. " ores" ..
          (#parts > 0 and (" - " .. table.concat(parts, ", ")) or ""), ores > 0 and C.good or C.warn)
    end
  end
  -- turtle updates
  local up, all = 0, 0
  for _, t in pairs(state.turtles) do
    all = all + 1
    if CODE and t.ver == CODE.ver then up = up + 1 end
  end
  if up > (s.up or 0) then add("Turtle program: " .. (up - (s.up or 0)) .. " turtle(s) updated (" .. up .. "/" .. all .. ")", C.good) end
  -- base off
  local offs = (BASE_ALIVE or {}).offs or {}
  local nOff, tOff = 0, 0
  for _, o in ipairs(offs) do
    if (o.from or 0) >= (AWAY.since or now) then nOff, tOff = nOff + 1, tOff + ((o.to or 0) - (o.from or 0)) end
  end
  if nOff > 0 then add("The base was OFF " .. nOff .. " time(s), " .. fmtSpan(tOff / 1000) .. " in all - see SYSTEM", C.warn) end
  -- warnings from the system log while away (newest 4)
  local n = 0
  for _, e in ipairs(SYSLOG or {}) do
    if e.kind == "WARNING" or e.kind == "ERROR" then
      n = n + 1
      if n <= 4 then add("  " .. e.when .. " " .. e.msg, e.kind == "ERROR" and C.bad or C.warn) end
    end
    if e.msg and e.msg:find("away mode on", 1, true) then break end      -- older than when you left
  end
  -- what needs you now
  local need = {}
  for _, t in pairs(state.turtles) do
    local key, lab = TT.status(t)
    if key == "stuck" or key == "nofuel" or key == "still" then need[#need + 1] = (t.label or ("#" .. t.id)) .. " " .. lab end
  end
  for dim, team in pairs(MINE and MINE.teams() or {}) do
    for _, u in pairs(team) do
      local lab = MINE.status(u)
      if lab == "STOPPED" or lab == "NO FUEL" or lab == "LOW FUEL" or lab == "BLOCKED" then
        need[#need + 1] = (u.label or ("#" .. u.id)) .. " " .. lab
      end
    end
  end
  if MAP.full then need[#need + 1] = "map floppies full" end
  if #need > 0 then add("Needs you: " .. table.concat(need, ", "), C.bad)
  else add("Nothing needs you.", C.good) end
  return lines
end

function AWAY.start()
  AWAY.on, AWAY.since = true, os.epoch("utc")
  AWAY.snap = snapshot()
  AWAY.page = state.page
  -- auto-map switched off by you: on while you are away, off again when you are back
  if AWAY.cfg("autoMap", true) and MAP.auto and not MAP.auto.on and not MAP.auto.done then
    MAP.setAuto(true)
    AWAY.autoOn = true
  end
  sysLog("You left the server - away mode on (updates, fuel top-ups, map follows the turtles" ..
         (AWAY.autoOn and ", auto-map on until you are back" or "") .. ")", "INFO")
  save()
end
function AWAY.back()
  local lines = AWAY.report()
  AWAY.last = { t = os.epoch("utc"), lines = lines }
  AWAY.on = false
  if AWAY.autoOn then
    AWAY.autoOn = nil
    MAP.setAuto(false)
    lines[#lines + 1] = { t = "Auto-map is OFF again (it was on only while you were away)", col = C.dim }
  end
  -- the monitor: back to the page you had
  if AWAY.page and state.page == "map" then state.page = AWAY.page end
  AWAY.page = nil
  save()
  local texts = {}
  for _, l in ipairs(lines) do texts[#texts + 1] = l.t end
  sysLog("You are back - " .. table.concat(texts, " | "), "INFO")
  -- always a box (like something you did), shown for 5 minutes
  local was = USER_ACTION
  USER_ACTION = true
  pcall(pushNote, "WELCOME BACK", table.concat(texts, "  /  "), C.label, 300)
  USER_ACTION = was
  if state.owner and AWAY.cfg("chat", true) then
    chatTell(state.owner, "While you were away: " .. texts[1])
    for i = 2, math.min(#texts, 6) do chatTell(state.owner, texts[i]) end
  end
  os.queueEvent("inv_update")
end

-- while away: the map view follows (zoom out to everything + the turtles)
function AWAY.followMap()
  if not AWAY.cfg("map", true) then return end
  local g = state.mapGeom
  local V = MAP.view()
  local x1, z1, x2, z2
  local function grow(x, z)
    if not x then return end
    x1, x2 = math.min(x1 or x, x), math.max(x2 or x, x)
    z1, z2 = math.min(z1 or z, z), math.max(z2 or z, z)
  end
  local h = CONFIG.drone and CONFIG.drone.home
  if h then grow(h.x, h.z) end
  for _, t in pairs(state.turtles) do
    if TT.online(t) and t.pos and t.pos.x then grow(t.pos.x, t.pos.z) end
  end
  -- the survey front too
  local q = MAP.queue
  if q and q.out then
    for _, spots in pairs(q.out) do
      for _, p in ipairs(spots) do grow(p[1], p[2]) end
    end
  end
  if not x1 then return end
  local mw, mh = (g and g.mw) or 80, (g and g.mh) or 40
  local spanX, spanZ = (x2 - x1) + 64, (z2 - z1) + 64
  local zoom = 1
  for _, z in ipairs({ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512 }) do
    zoom = z
    if mw * z >= spanX and mh * z * 1.5 >= spanZ and mw * z >= spanZ and mh * z * 1.5 >= spanX then break end
  end
  V.cx, V.cz, V.zoom = math.floor((x1 + x2) / 2), math.floor((z1 + z2) / 2), zoom
end

local lastSave = 0
-- comms worker, every 2 s
function AWAY.tick()
  if AWAY.cfg("enabled", true) == false then return end
  local online = AWAY.ownerOnline()
  local now = os.epoch("utc")
  if online == true then
    AWAY.lastSeen = now
    if AWAY.on then AWAY.back() end
    return
  end
  if online == nil then return end                      -- cannot tell: change nothing
  AWAY.lastSeen = AWAY.lastSeen or now
  if not AWAY.on and (now - AWAY.lastSeen) / 1000 > (tonumber(AWAY.cfg("after", 300)) or 300) then
    AWAY.start()
  end
  if AWAY.on then
    -- the monitor shows the map, following the turtles
    if AWAY.cfg("map", true) then
      if state.page ~= "map" and state.page ~= "settings" then
        AWAY.page = AWAY.page or state.page
        state.page = "map"
      end
      pcall(AWAY.followMap)
    end
    -- every 30 min: save the map, look for new storage helpers
    if os.clock() - lastSave > 1800 then
      lastSave = os.clock()
      MAP.saveNow = true
      os.queueEvent("map_save")
    end
  end
end
