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
  saveFileSafe(FILE, serialSmall({ on = AWAY.on, since = AWAY.since, lastSeen = AWAY.lastSeen,
                                           snap = AWAY.snap, last = AWAY.last, page = AWAY.page,
                                           autoOn = AWAY.autoOn, left = AWAY.left, acc = AWAY.acc, prev = AWAY.prev }))
end
do
  if fs.exists(FILE) then
    local h = fs.open(FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then
      AWAY.on, AWAY.since, AWAY.lastSeen, AWAY.snap, AWAY.last, AWAY.page = t.on, t.since, t.lastSeen, t.snap, t.last, t.page
      AWAY.autoOn = t.autoOn
      AWAY.left, AWAY.acc, AWAY.prev = t.left, t.acc, t.prev
    end
  end
end

-- is the owner online? true / false, or nil when we cannot tell
function AWAY.ownerOnline()
  if not det or not state.owner then return nil end
  -- the server's list of online players (getOnlinePlayers, read with the players)
  if state.online and state.onlineT and os.clock() - state.onlineT < 120 then
    return state.online[tostring(state.owner):lower()] == true
  end
  if not fresh("players", 120) then return nil end
  -- no online list: the owner counts as online only when the detector FOUND them
  for _, e in ipairs(state.players or {}) do
    if (e.isOwner or tostring(e.name):lower() == tostring(state.owner):lower()) and e.p then return true end
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
  local s = { mine = {}, ovN = MAP.ovN or 0, up = 0, all = 0, offs = #((BASE_ALIVE or {}).offs or {}),
              built = (FACTORY and FACTORY.built) or 0, missing = {}, offline = {} }
  for dim, team in pairs(MINE and MINE.teams() or {}) do
    if #team.miners > 0 then
      local T = MINE.totals(team)
      s.mine[dim] = { ores = T.ores, ci = tonumber(T.ci) or 0, got = copy(T.got) }
    end
  end
  for id, t in pairs(state.turtles) do
    s.all = s.all + 1
    if CODE and t.ver == CODE.ver then s.up = s.up + 1 end
    if t.missing then s.missing[#s.missing + 1] = id
    elseif not TT.online(t) then s.offline[#s.offline + 1] = id end
  end
  return s
end

-- MINING GAINS while you are away, counted AS THEY COME (per miner): a miner's own counters
-- start again at 0 when it restarts (server restart, update), so "now minus when you left"
-- came out as +0. A counter that went DOWN started again: all of its new value is new.
local function gain(cur, was)
  cur, was = tonumber(cur) or 0, tonumber(was) or 0
  if cur >= was then return cur - was end
  return cur
end
function AWAY.track()
  AWAY.acc, AWAY.prev = AWAY.acc or {}, AWAY.prev or {}
  local changed = false
  for id, u in pairs(MINE and MINE.units or {}) do
    local dim = u.dim or "?"
    local key = tostring(id)
    local cur = { ores = type(u.stats) == "table" and tonumber(u.stats.ores) or 0, ci = tonumber(u.ci) or 0, got = {} }
    for k, v in pairs(u.got or {}) do cur.got[k] = tonumber(v) or 0 end
    local p = AWAY.prev[key]
    if p then
      local a = AWAY.acc[dim] or { ores = 0, chunks = 0, got = {} }
      AWAY.acc[dim] = a
      if u.role == "loader" then
        local c = gain(cur.ci, p.ci)
        if c > 0 then a.chunks = a.chunks + c changed = true end
      else
        local o = gain(cur.ores, p.ores)
        if o > 0 then a.ores = a.ores + o changed = true end
        for k, v in pairs(cur.got) do
          local g = gain(v, (p.got or {})[k])
          if g > 0 then a.got[k] = (a.got[k] or 0) + g changed = true end
        end
      end
    end
    AWAY.prev[key] = cur
  end
  return changed
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
  local left = AWAY.left or AWAY.since or now
  add("Away " .. fmtSpan((now - left) / 1000) .. " (since " .. fmtTime(left) .. ")", C.label)
  -- map
  local grew = (MAP.ovN or 0) - (s.ovN or 0)
  add("Map: +" .. commas(math.max(0, grew)) .. " chunks mapped (" .. commas(MAP.ovN or 0) .. " in all)",
      grew > 0 and C.good or C.dim)
  -- mining: counted as it came in (AWAY.track) - restarts do not wipe it
  if AWAY.acc then
    pcall(AWAY.track)
    local dims = {}
    for dim in pairs(AWAY.acc) do dims[#dims + 1] = dim end
    table.sort(dims)
    for _, dim in ipairs(dims) do
      local a = AWAY.acc[dim]
      local diff = {}
      for k, v in pairs(a.got or {}) do if v > 0 then diff[#diff + 1] = { k, v } end end
      table.sort(diff, function(x, y) return x[2] > y[2] end)
      local parts = {}
      for i = 1, math.min(4, #diff) do parts[#parts + 1] = itemName(diff[i][1]) .. " " .. commas(diff[i][2]) end
      add("Mining " .. dim .. ": +" .. (a.chunks or 0) .. " chunks, +" .. commas(a.ores or 0) .. " ores" ..
          (#parts > 0 and (" - " .. table.concat(parts, ", ")) or ""), (a.ores or 0) > 0 and C.good or C.warn)
    end
  end
  for dim, team in pairs((not AWAY.acc) and MINE and MINE.teams() or {}) do
    if #team.miners > 0 then
      local T = MINE.totals(team)
      local was = (s.mine or {})[dim] or { ores = 0, ci = 0, got = {} }
      local ores = T.ores - (was.ores or 0)
      local chunks = (tonumber(T.ci) or 0) - (was.ci or 0)
      local diff = {}
      for k, v in pairs(T.got or {}) do
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
  -- the fleet: new turtles from the factory, turtles lost and found
  local built = ((FACTORY and FACTORY.built) or 0) - (s.built or 0)
  if built > 0 then add("Factory: built " .. built .. " new turtle(s) - " .. all .. " turtles now", C.good) end
  local wasMissing, wasOff = {}, {}
  for _, id in ipairs(s.missing or {}) do wasMissing[id] = true end
  for _, id in ipairs(s.offline or {}) do wasOff[id] = true end
  local back, gone = {}, {}
  for id, t in pairs(state.turtles) do
    local name = t.label or ("#" .. id)
    if (wasOff[id] or wasMissing[id]) and TT.online(t) then back[#back + 1] = name end
    if t.missing and not wasMissing[id] then gone[#gone + 1] = name end
  end
  table.sort(back) table.sort(gone)
  if #back > 0 then add("Found again: " .. table.concat(back, ", "), C.good) end
  if #gone > 0 then add("Marked MISSING (not found where they were): " .. table.concat(gone, ", "), C.warn) end
  -- base off
  local offs = (BASE_ALIVE or {}).offs or {}
  local nOff, tOff = 0, 0
  for _, o in ipairs(offs) do
    if (o.from or 0) >= left then nOff, tOff = nOff + 1, tOff + ((o.to or 0) - (o.from or 0)) end
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
    if key == "stuck" or key == "nofuel" or key == "still" or key == "missing" then need[#need + 1] = (t.label or ("#" .. t.id)) .. " " .. lab end
    if TT.dupText(t) then need[#need + 1] = (t.label or ("#" .. t.id)) .. " HAS COPIES" end
  end
  for dim, team in pairs(MINE and MINE.teams() or {}) do
    local all = { team.loader }
    for _, m in ipairs(team.miners) do all[#all + 1] = m end
    for _, u in pairs(all) do
      local lab = MINE.status(u)
      if lab == "STOPPED" or lab == "NO FUEL" or lab == "LOW FUEL" or lab == "BLOCKED" then
        need[#need + 1] = (u.label or ("#" .. u.id)) .. " " .. lab
      end
    end
  end
  if MAP.full then need[#need + 1] = "map floppies full" end
  if FACTORY and FACTORY.lastMissing and #FACTORY.lastMissing > 0 then
    need[#need + 1] = "the turtle factory needs AE2 patterns (" .. FACTORY.lastMissing[1].what .. "...)"
  end
  if #need > 0 then add("Needs you: " .. table.concat(need, ", "), C.bad)
  else add("Nothing needs you.", C.good) end
  return lines
end

function AWAY.start()
  AWAY.on, AWAY.since = true, os.epoch("utc")
  AWAY.left = AWAY.offSince or AWAY.since            -- (when you LEFT - away mode starts `after` s later)
  AWAY.snap = snapshot()
  AWAY.acc, AWAY.prev = {}, {}
  pcall(AWAY.track)                                  -- (the counters as they are now)
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
  -- a few seconds / minutes only (e.g. you counted as offline while the base was
  -- starting): no report - before, "Away 1 s" came after a 10-hour absence
  local short = (os.epoch("utc") - (AWAY.left or AWAY.since or 0)) / 1000 < (tonumber(AWAY.cfg("after", 300)) or 300)
  if short then
    AWAY.on = false
    if AWAY.autoOn then AWAY.autoOn = nil MAP.setAuto(false) end
    if AWAY.page and state.page == "map" then state.page = AWAY.page end
    AWAY.page = nil
    save()
    return
  end
  -- (an error in the report must never leave away mode stuck ON - it then never made a
  -- report again and the next absence used a days-old snapshot)
  local okR, lines = pcall(AWAY.report)
  if not okR then
    local err = tostring(lines)
    lines = { { t = "Away " .. fmtSpan((os.epoch("utc") - (AWAY.left or AWAY.since or 0)) / 1000), col = C.label },
              { t = "(the report could not be made: " .. err .. ")", col = C.bad } }
    if sysLog then sysLog("Away report error: " .. err, "ERROR") end
  end
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
  -- and on the pocket remote (it shows info messages only when sent on purpose)
  if POCKET and POCKET.note then pcall(POCKET.note, "WELCOME BACK", table.concat(texts, "  /  "), C.good) end
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
  -- move the view only when it must (a new view = the whole map drawn again):
  -- another zoom, or the middle off by more than a quarter of the screen
  local cx, cz = math.floor((x1 + x2) / 2), math.floor((z1 + z2) / 2)
  if V.zoom ~= zoom or math.abs(cx - (V.cx or 0)) > mw * zoom / 4 or math.abs(cz - (V.cz or 0)) > mh * zoom * 1.5 / 4 then
    V.cx, V.cz, V.zoom = cx, cz, zoom
  end
end

local lastSave = 0
-- comms worker, every 2 s
function AWAY.tick()
  if AWAY.cfg("enabled", true) == false then return end
  local online = AWAY.ownerOnline()
  local now = os.epoch("utc")
  if online == true then
    -- the base was OFF while you were away (its chunk unloads when you leave):
    -- away mode could not run - say so once, so you know why there is no report
    if not AWAY.on and not AWAY.startChecked then
      AWAY.startChecked = true
      local o = ((BASE_ALIVE or {}).offs or {})[1]
      local after = (tonumber(AWAY.cfg("after", 300)) or 300) * 1000
      if o and o.to and o.from and now - o.to < 600000 and o.to - o.from > after then
        local was = USER_ACTION
        USER_ACTION = true
        local msg = "The base was OFF for " .. fmtSpan((o.to - o.from) / 1000) ..
              " - nothing could run (" .. tostring(o.why or "unloaded") .. "). If its chunk unloads when you log off, " ..
              "keep it loaded (a chunk loader at the base) so away mode can work."
        pcall(pushNote, "WHILE YOU WERE AWAY", msg, C.warn, 300)
        USER_ACTION = was
        if state.owner and AWAY.cfg("chat", true) and chatTell then pcall(chatTell, state.owner, msg) end
      end
    end
    AWAY.lastSeen = now
    AWAY.offSince = nil
    AWAY.offLogged = nil
    if AWAY.on then
      local okB, errB = pcall(AWAY.back)
      if not okB then
        AWAY.on = false                              -- (never stuck ON)
        if sysLog then sysLog("Away mode: coming back failed - " .. tostring(errB), "ERROR") end
        save()
      end
    end
    return
  end
  if online == nil then return end                      -- cannot tell (yet): change nothing
  -- (offline does NOT end the "base was off" check: right after a start the
  -- player list may say offline for a tick - the message only comes within 10
  -- min of the base starting anyway)
  AWAY.lastSeen = AWAY.lastSeen or now
  -- away = THIS run of the base saw you offline for `after` seconds. (Not the
  -- saved lastSeen: after the base was off for hours, it counted you as away at
  -- once - one tick before it saw you online -> "Away 1 s".)
  AWAY.offSince = AWAY.offSince or now
  -- (so you can see that the base noticed: SYSTEM log)
  if not AWAY.offLogged and not AWAY.on then
    AWAY.offLogged = true
    if sysLog then
      sysLog("You are offline (server player list) - away mode starts in " ..
             fmtSpan(tonumber(AWAY.cfg("after", 300)) or 300) .. (MAP.loaded and "" or " (after the map is read)"), "INFO")
    end
  end
  -- (not before the map is read: the "before" numbers would be 0)
  if not AWAY.on and MAP.loaded and (now - AWAY.offSince) / 1000 > (tonumber(AWAY.cfg("after", 300)) or 300) then
    AWAY.start()
  end
  if AWAY.on then
    if AWAY.track() then save() end                  -- (mining gains as they come)
    -- the monitor shows the map, following the turtles
    -- (only when there is a MAP tab: turtles, a modem for them or map data)
    if AWAY.cfg("map", true) and (state.tModem or next(state.turtles) or MAP.hasData()) then
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
