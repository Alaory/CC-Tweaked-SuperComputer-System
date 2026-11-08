-- base_turtles.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   Talking to the turtles (node.lua) over a wireless / ender modem, with
--   signed messages. Shared terrain knowledge (walls, dead ends, exit route),
--   sending node.lua updates and keeping the install floppy current, the saved
--   turtle list, rescue / findlost, and splitting surveys between turtles.

-- TURTLES  (remote control over a wireless / ender modem) -----------------
TT = {}

-- small keyed checksum so other players cannot send commands to the turtles
-- (not real cryptography, but enough against casual tampering)
function TT.sign(key, t, n, cmd, args)
  local parts = {}
  for i, v in ipairs(args or {}) do parts[i] = tostring(v) end
  local str = key .. "|" .. tostring(t) .. "|" .. tostring(n) .. "|" .. tostring(cmd or "") ..
              "|" .. table.concat(parts, ",")
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end

-- a wireless or ender modem on a side of this computer
function TT.findModem()
  for _, name in ipairs(peripheral.getNames()) do
    if SIDES[name] then
      local okT, isM = pcall(peripheral.hasType, name, "modem")
      if okT and isM then
        local okW, w = pcall(peripheral.call, name, "isWireless")
        if okW and w then return name end
      end
    end
  end
end

-- a turtle's record (created on first contact)
-- a turtle that is not where it was last (the rescuer looked): probably deleted
-- by a server crash. No more rescues; its survey spots go to the others.
function TT.markMissing(t, by)
  if t.missing then return end
  t.missing = os.epoch("utc")
  TT.listDirty = true
  pcall(MAP.reclaim, t.id)
  local gear = {}
  if type(t.gear) == "string" and t.gear ~= "" then gear[1] = t.gear end
  local where = t.pos and t.pos.x and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "?"
  local msg = (t.label or ("Turtle " .. t.id)) .. " is not at its last spot (" .. where .. ")" ..
              (by and (" - " .. by .. " looked") or "") .. ". Probably deleted by a server crash" ..
              (#gear > 0 and (". It carried: " .. table.concat(gear, ", ")) or "") ..
              ". FORGET it on the TURTLES tab when you are sure."
  TT.log(t, "MISSING: " .. msg)
  setPopup("TURTLE MISSING", msg, C.bad)
  if sysLog then sysLog(msg, "WARNING") end
end
-- forget a turtle for good (deleted / taken down): off the list, its survey
-- spots back into the queue
function TT.forget(id)
  local t = state.turtles[id]
  if not t then return false end
  pcall(MAP.reclaim, id)
  local q = MAP.queue
  if q and q.ids then
    for i = #q.ids, 1, -1 do if q.ids[i] == id then table.remove(q.ids, i) end end
  end
  state.turtles[id] = nil
  if state.tSel == id then state.tSel = nil end
  TT.listDirty = true
  pcall(TT.saveList)
  if sysLog then sysLog((t.label or ("Turtle " .. id)) .. " forgotten (removed from the list)", "INFO") end
  return true
end

function TT.get(id)
  local t = state.turtles[id]
  if not t then
    t = { id = id, label = "Turtle " .. id, log = {}, lastN = 0 }
    state.turtles[id] = t
  end
  return t
end

-- add a line to a turtle's log (40 kept)
function TT.log(t, msg)
  -- real time (the game clock was confusing: it runs 72x faster)
  local okD, now = pcall(os.date, "%H:%M")
  table.insert(t.log, 1, { t = (okD and now) or textutils.formatTime(os.time(), true), msg = msg })
  while #t.log > 40 do table.remove(t.log) end
end

-- has the turtle reported recently?
function TT.online(t)
  return t.lastSeen ~= nil and (os.clock() - t.lastSeen) < CONFIG.turtles.offlineAfter
end

-- ===== what is this turtle doing, really? =====
-- key, LABEL (for the pill), colour, one line why. Used by the TURTLES page
-- and the `turtles` command. Problems come first, then work, then idle with
-- the reason it gets nothing to do.
local QUIET_TASK = { "waiting", "refuel", "gps", "install" }   -- standing still is normal there
local TROUBLE_TASK = { "backing up", "retracing", "planning a route", "following a planned route" }
function TT.stillFor(t)
  return os.clock() - math.max(t.movedAt or os.clock(), t.taskAt or 0)
end
function TT.idleWhy(t)
  local fuel = tonumber(t.fuel)
  local minFuel = tonumber(CONFIG.map.surveyMinFuel) or 500
  local q = MAP and MAP.queue
  if not (t.pos and t.pos.x) then return "position unknown - press GPS LOCATE", C.warn end
  if t.anchor then return "anchor - keeps the base loaded", C.purple end
  if t.rescuerRole then return "rescuer - waits for a turtle in trouble", C.warn end
  if fuel and fuel < minFuel then
    return "fuel " .. fuel .. " is below " .. minFuel .. " - " ..
           ((CONFIG.turtles.fuelChest and CONFIG.turtles.fuelChest.x) and "waiting for the fuel chest"
            or "needs fuel at home (fuel chest under / next to its home)"), C.warn
  end
  if q then
    if q.ids then
      local mine = false
      for _, i in ipairs(q.ids) do if i == t.id then mine = true end end
      if not mine then return "not chosen for the running survey", C.warn end
    end
    if q.excluded and q.excluded[t.id] then return "taken off the survey by STOP - any button gives it back", C.warn end
    if q.auto and MAP.full then return "auto-map paused - the map floppies are full", C.warn end
    if t.queueAt and os.clock() - t.queueAt < 30 then return "just got survey spots - starting", C.good end
    if t.packWait and q.wave then
      return "waiting for the rest of the pack (they survey together, so one visit wakes them all)", C.label
    end
    local idle = t.idleSince and os.clock() - t.idleSince or 0
    -- why the last hand-out found nothing (MAP.feedSurvey / nextBatch)
    local w = q.lastWhy
    if idle > 20 and w then
      if w.near > 0 and w.near >= w.redo then
        return "survey: " .. w.near .. " spots wait - " .. (w.who or "a player") .. " is near them", C.warn
      end
      if w.done > 0 then return "survey: skipping already mapped spots (" .. commas(w.done) .. " so far)", C.label end
    end
    if idle > 60 then return "a survey runs but it got nothing for " .. math.floor(idle) .. " s", C.warn end
    return "waiting for the next survey spots", C.good
  end
  local a = MAP and MAP.auto
  local home = t.home and t.pos and (math.abs(t.pos.x - t.home.x) + math.abs(t.pos.y - t.home.y)
                                     + math.abs(t.pos.z - t.home.z) <= 2)
  local where = home and "at home" or (t.home and "away from home" or "no home yet")
  if a and a.done then return "nothing to do (" .. where .. ") - the whole map is done", C.dim end
  if a and not a.on then return "nothing to do (" .. where .. ") - auto-map is OFF (MAP tab)", C.warn end
  return "nothing to do (" .. where .. ")", C.dim
end
function TT.status(t)
  local now = os.clock()
  if t.missing and not TT.online(t) then
    return "missing", "MISSING", C.bad,
           "not at its last spot" .. (t.pos and t.pos.x and (" " .. fmtPos(t.pos.x, t.pos.y, t.pos.z)) or "") ..
           " - probably deleted (server crash). FORGET removes it"
  end
  if not TT.online(t) then
    return "offline", "OFFLINE", C.bad,
           ((t.seenEpoch and ("last seen " .. TT.ago(t.seenEpoch)) or "never seen") ..
            (t.rescuer and " - rescue on its way" or ""))
  end
  local task = tostring(t.task or "idle")
  local busy = task ~= "idle"
  local low = task:lower()
  local fuel = tonumber(t.fuel)
  if fuel and fuel < 20 then return "nofuel", "NO FUEL", C.bad, "fuel " .. fuel .. " - it cannot move" end
  -- STUCK (reported by the turtle) - unless it has moved away since
  if t.stuck and not busy then
    local sp, p = t.stuckPos, t.pos
    local moved = sp and p and p.x and (math.abs(p.x - sp.x) + math.abs(p.z - sp.z) > 3)
    if not moved then return "stuck", "STUCK", C.bad, tostring(t.stuck) end
  end
  if t.held then return "held", "STOPPED", C.warn, "stopped by you - any button (e.g. PING) releases it" end
  if busy then
    for _, w in ipairs(TROUBLE_TASK) do
      if low:find(w, 1, true) then return "trouble", "FINDING A WAY", C.warn, "blocked - " .. task end
    end
    local quiet = false
    for _, w in ipairs(QUIET_TASK) do if low:find(w, 1, true) then quiet = true end end
    local still = TT.stillFor(t)
    if not quiet and still > 90 then
      return "still", "NOT MOVING", C.bad, "has not moved for " .. math.floor(still) .. " s - " .. task
    end
    local lab = t.anchor and "ANCHOR" or t.rescuerRole and "RESCUER" or "WORKING"
    return "busy", lab, t.anchor and C.purple or C.good, task
  end
  local why, col = TT.idleWhy(t)
  local lab = t.anchor and "ANCHOR" or t.rescuerRole and "RESCUER" or "IDLE"
  return "idle", lab, (t.anchor and C.purple) or (t.rescuerRole and C.good) or (col == C.warn and C.warn or C.label), why
end

-- comms worker: a turtle "busy" but not moving for 3 min is hung in its job -
-- STOP it (no hold). Then it is free again: it gets new work / goes home, and
-- if it really cannot move that trip fails -> STUCK -> the rescuer comes.
function TT.stallTick()
  local now = os.clock()
  for id, t in pairs(state.turtles) do
    local key = TT.online(t) and not t.held and not t.anchor and TT.status(t)
    if key == "still" and TT.stillFor(t) > 180 and (not t.stallAt or now - t.stallAt > 600) then
      t.stallAt = now
      TT.send(id, "stop", {}, true, true)
      TT.log(t, "Not moving for " .. math.floor(TT.stillFor(t)) .. " s in '" .. tostring(t.task) ..
                "' - stopped it so it can start again")
      if sysLog then sysLog((t.label or ("Turtle " .. id)) .. " hung in its job (not moving 3 min) - stopped it", "WARNING") end
    end
  end
end

-- all turtles, sorted by ID
function TT.list()
  local out = {}
  for _, t in pairs(state.turtles) do out[#out + 1] = t end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- a turtle by ID or label
function TT.find(word)
  local n = tonumber(word)
  if n and state.turtles[n] then return state.turtles[n] end
  for _, t in pairs(state.turtles) do
    if t.label:lower() == tostring(word):lower() then return t end
  end
end

-- a message from a turtle (status every few seconds, results of commands)
function TT.receive(id, m)
  if type(m) ~= "table" or type(m.n) ~= "number" or type(m.t) ~= "string" then return end
  if m.sig ~= TT.sign(CONFIG.turtles.key, m.t, m.n) then
    -- a turtle with a different key: its messages are ignored - say so (every 10 min)
    TT.badKey = TT.badKey or {}
    if not TT.badKey[id] or os.clock() - TT.badKey[id] > 600 then
      TT.badKey[id] = os.clock()
      pushNote("WARNING", "Turtle #" .. id .. (type(m.label) == "string" and (" (" .. m.label .. ")") or "") ..
               " uses a DIFFERENT KEY - its messages are ignored. Give it the key from base_config.lua" ..
               (m.mine and " (miner setup)" or ""), C.warn)
    end
    return
  end
  if m.mine then return MINE.receive(id, m) end      -- a mining-dimension team turtle (miner.lua)
  local t = TT.get(id)
  if m.n <= (t.lastN or 0) then return end           -- old / replayed message
  t.lastN = m.n
  local prevSeen = t.lastSeen
  t.lastSeen = os.clock()
  if t.missing then
    t.missing = nil
    TT.listDirty = true
    TT.log(t, "It is back - it was not deleted after all")
    if sysLog then sysLog((m.label or t.label or ("Turtle " .. id)) .. " reports again (was MISSING)", "DONE") end
  end
  if type(m.label) == "string" then t.label = m.label end
  t.fuel, t.fuelMax, t.items = m.fuel, m.fuelMax, m.items
  -- movement / task changes (for TT.status: a busy turtle that does not move)
  local op, np = t.pos, m.pos
  -- first word since the base started, or back after being offline: count from now
  if not t.movedAt or not prevSeen or os.clock() - prevSeen > CONFIG.turtles.offlineAfter then
    t.movedAt = os.clock()
  end
  if type(np) == "table" and np.x and (not (op and op.x) or math.abs(np.x - op.x) + math.abs((np.y or 0) - (op.y or 0))
                                        + math.abs(np.z - op.z) >= 1) then
    t.movedAt = os.clock()
  end
  if m.task ~= t.task then t.taskAt = os.clock() end
  t.pos, t.task, t.home = m.pos, m.task, m.home
  -- where it reported STUCK (a stuck flag is old news once it has moved away)
  if m.stuck and not t.stuck and type(np) == "table" and np.x then t.stuckPos = { x = np.x, y = np.y, z = np.z } end
  if not m.stuck then t.stuckPos = nil end
  t.stuck, t.trail = m.stuck, m.trail
  t.anchor, t.waiting = m.anchor, m.waiting
  t.rec = m.rec
  -- STOP arrived (it answers) or it is idle anyway
  if t.stopAsk and ((m.t == "result" and m.cmd == "stop") or m.task == "idle") then t.stopAsk = nil end
  -- STOPPED by you (t.held) but busy again - e.g. it was unloaded and
  -- continued its job after a reload: send STOP again
  if t.held and (m.t == "status" or m.t == "hello") and m.task and m.task ~= "idle" and not t.stopAsk then
    TT.log(t, "Busy again after STOP (" .. tostring(m.task) .. ") - sending STOP again")
    t.stopAsk = { tries = 1, last = os.clock() }
    TT.send(id, "stop", {}, true, true)
  end
  -- called back (its survey batch was far out - old survey order): stop that
  -- job (also when it resumes it after being offline), then home
  if t.recall and (m.t == "status" or m.t == "hello") and m.task then
    local task = tostring(m.task)
    if task:find("^survey") or task:find("^scanning") then
      if not t.recallAt or os.clock() - t.recallAt > 20 then
        t.recallAt = os.clock()
        TT.send(id, "stop", {}, true, true)                  -- no hold
      end
    elseif task == "idle" then
      t.recall, t.recallAt = nil, nil
      TT.listDirty = true
      if t.home then TT.send(id, "home", {}, true) end
      TT.log(t, "Called back: going home")
    end
  end
  local oldVer = t.ver
  if m.ver then t.ver = m.ver end
  t.updReady = m.updReady
  if oldVer and oldVer ~= "?" and m.ver and m.ver ~= oldVer and CODE and m.ver == CODE.ver then
    pcall(TT.updated, t, oldVer)
  end
  if m.gear then
    t.gear = m.gear
    -- equipment problems: told once per turtle (and again when it changes)
    local bad = (m.gear:find("NO CHUNKY", 1, true) and "has NO Chunky upgrade equipped (its chunk unloads when you leave)")
             or (m.gear:find("WIRELESS modem", 1, true) and "has a normal Wireless Modem (~64 blocks) - it loses contact further away; use an Ender Modem")
    if bad and t.gearWarned ~= bad then
      t.gearWarned = bad
      TT.log(t, "Equipment: " .. m.gear)
      setPopup("TURTLE EQUIPMENT", (t.label or ("Turtle " .. id)) .. " " .. bad, C.warn)
    elseif not bad then t.gearWarned = nil end
  end
  t.seenEpoch = os.epoch("utc")
  TT.listDirty = true
  if m.t == "updmiss" and CODE and m.want == CODE.ver and type(m.missing) == "table" then
    -- some pieces of the update did not arrive: send just those again
    for _, k in ipairs(m.missing) do
      local p = CODE.pieces[tonumber(k) or 0]
      if p then TT.send(id, "upd", { CODE.ver, tonumber(k), #CODE.pieces, p }, true) end
    end
    if TT.sending[id] then TT.sending[id] = os.clock() end      -- still on it: wait longer
  elseif m.t == "homebad" and tonumber(m.x) then
    -- an offered home was not free: never offer that spot to it again
    t.homeBad = t.homeBad or {}
    t.homeBad[m.x .. "," .. m.y .. "," .. m.z] = true
    t.homeOfferAt = nil
    TT.log(t, "Offered home " .. m.x .. " " .. m.y .. " " .. m.z .. " is not free - offering another")
  elseif m.t == "hello" then
    TT.log(t, "Connected")
    -- the base's dig setting (SETTINGS > TURTLES), so new / restarted turtles have it
    if CONFIG.turtles.dig ~= nil then TT.send(id, "setting", { "dig", tostring(CONFIG.turtles.dig == true) }, true) end
  elseif m.t == "scan" then
    local ok = pcall(MAP.addScan, m)
    TT.log(t, ok and ("Scan received at " .. tostring(m.x) .. " " .. tostring(m.z))
                  or "Scan could not be stored")
    -- confirm it: the turtle keeps every scan until the base has stored it
    if ok and m.sid then TT.send(id, "ack", { m.sid }, true) end
  elseif m.t == "rescued" then
    local target = tonumber(m.target) and TT.get(tonumber(m.target)) or nil
    if target and not target.label then target.label = "Turtle " .. target.id end
    local where = type(m.at) == "table" and (" at " .. tostring(m.at.x) .. " " .. tostring(m.at.y) .. " " .. tostring(m.at.z)) or ""
    TT.log(t, (m.ok and "Rescue done: " or "Rescue failed: ") .. tostring(m.msg))
    if target then
      if type(m.at) == "table" and tonumber(m.at.x) then
        target.pos = { x = tonumber(m.at.x), y = tonumber(m.at.y), z = tonumber(m.at.z), f = target.pos and target.pos.f }
      end
      TT.log(target, (m.ok and "Rescued by " or "Rescue by ") .. t.label .. (m.ok and "" or " failed") .. where)
      target.rescuer, target.rescueKind = nil, nil
      -- the rescuer was there and the turtle is NOT: gone (a server crash can delete turtles)
      if not m.ok and tostring(m.msg):find("not found within", 1, true) and not TT.online(target) then
        TT.markMissing(target, t.label)
      end
      if m.ok then target.rescueTries = nil end
      -- supplies delivered: refuel, allow digging with the new pickaxe, come home
      if m.ok and m.mode == "supply" then
        TT.send(target.id, "refuel", {})
        if tostring(m.gave or ""):find("pick", 1, true) then TT.send(target.id, "setting", { "dig", "true" }) end
        TT.send(target.id, "home", {})
      end
    end
    setToast((m.ok and "Rescue done: " or "Rescue failed: ") .. tostring(m.msg), m.ok and C.good or C.warn, 8)
    if t.rescuerRole and not t.held then TT.send(id, "home", {}) end   -- the rescuer goes back home
  elseif m.t == "learn" then
    pcall(KNOW.learn, m)
  elseif m.t == "need" then
    -- a turtle starts a trip: send it what is known around there
    local x1, z1 = tonumber(m.x1), tonumber(m.z1)
    local x2, z2 = tonumber(m.x2), tonumber(m.z2)
    if x1 and z1 and x2 and z2 then
      local okA, walls, dead = pcall(KNOW.around, x1, z1, x2, z2)
      if okA then
        -- the cruise altitude for this trip, from the map (nil = not known)
        local okC, cruise = pcall(TT.cruiseHeight, tonumber(m.fx), tonumber(m.fz), tonumber(m.tx), tonumber(m.tz))
        TT.send(id, "know", { walls, dead, EXITROUTE and EXITROUTE.route or "none",
                              EXITROUTE and EXITROUTE.t or 0, (okC and cruise) or "none" }, true)
      end
    end
  elseif m.t == "exitroute" and type(m.route) == "string" then
    local n = 0
    for _ in m.route:gmatch(";") do n = n + 1 end
    EXITROUTE = { route = m.route, t = os.epoch("utc"), n = n + 1, by = t.label }
    KNOW.dirty = true
    TT.log(t, "Exit route saved (" .. (n + 1) .. " corners) - shared with all turtles")
  elseif m.t == "result" and m.cmd == "upd" then
    TT.log(t, "Update: " .. tostring(m.msg))
    if not m.ok then
      setToast(t.label .. ": update failed - " .. tostring(m.msg), C.warn)
      TT.sending[id] = nil
      t.updRetry, t.updState, t.updNote = os.clock() + 120, "retry", tostring(m.msg)
    elseif tostring(m.msg):find("ready", 1, true) then
      setToast(t.label .. " got " .. (CODE and TT.verName(CODE.ver) or "the update") ..
               " - installs when its job is done", C.label)
    end
  elseif m.t == "look" then
    TT.lookIn(t, m)
  elseif m.t == "result" then
    if m.cmd == "drive" then
      t.driveMsg = { ok = m.ok, msg = tostring(m.msg), at = os.clock() }
      -- refused (not a natural block / close to home): DIG ANYWAY offers the same step with force
      t.driveAnyway = (not m.ok and tostring(m.msg):find("DIG ANYWAY", 1, true)) and t.driveLast or nil
    end
    if m.cmd == "fuelup" and TT.fuelTrip and TT.fuelTrip.id == id then TT.fuelTrip = nil end   -- the next one may go
    if m.cmd == "surveypts" and MAP.batchResult then pcall(MAP.batchResult, id, m.ok) end
    if m.cmd == "build" and FACTORY then pcall(FACTORY.result, id, m.ok, m.msg) end
    if m.cmd == "restart" and not m.ok and sysLog then sysLog(t.label .. ": " .. tostring(m.msg), "ERROR") end
    TT.log(t, (m.ok and "Done: " or "Failed: ") .. tostring(m.msg))
    if not m.ok then setToast(t.label .. ": " .. tostring(m.msg), C.warn, 6) end
  end
  if not state.tSel then state.tSel = id end
  os.queueEvent("inv_update")
end

-- queue a signed command for a turtle (sent by the comms worker)
-- the turtle keeping the base computer's chunk loaded (if any), and whether
-- it really sits in the same chunk as the base computer
-- ===== shared knowledge (from all turtles) =====
-- Walls the turtles bumped into and dead ends, each with its time: in
-- Minecraft blocks get placed and dug, so old knowledge fades and is dropped.
-- The same lifetimes as in node.lua (fresh + fade), in ms.
local KNOW_LIFE = { hard = 6 * 3600000 + 600000, short = 32 * 60000, door = 11 * 60000 }
local DEAD_LIFE = 3 * 3600000
KNOW = { walls = {}, dead = {}, n = 0, dirty = false, saved = 0 }
EXITROUTE = nil          -- { route = "x,y,z;...", t = time, n = corners }
-- real time in ms
local function epoch() return os.epoch("utc") end

-- drop knowledge that is too old, and the oldest walls over knowMax
function KNOW.prune()
  local t = epoch()
  for k, w in pairs(KNOW.walls) do
    if t - w.t > (KNOW_LIFE[w.k] or KNOW_LIFE.hard) then KNOW.walls[k] = nil KNOW.n = KNOW.n - 1 end
  end
  for k, d in pairs(KNOW.dead) do
    if t - d.t > DEAD_LIFE then KNOW.dead[k] = nil end
  end
  if KNOW.n > (CONFIG.turtles.knowMax or 20000) then
    local list = {}
    for k, w in pairs(KNOW.walls) do list[#list + 1] = { k = k, t = w.t } end
    table.sort(list, function(a, b) return a.t < b.t end)
    for i = 1, KNOW.n - CONFIG.turtles.knowMax do KNOW.walls[list[i].k] = nil end
    KNOW.n = CONFIG.turtles.knowMax
  end
end

-- save the shared knowledge (shrinks it if the disk is full)
function KNOW.save()
  KNOW.prune()
  local path = dataFile(CONFIG.turtles.knowFile, true)
  local function text()
    local lines = {}
    for k, w in pairs(KNOW.walls) do lines[#lines + 1] = "W " .. k .. "," .. w.k .. "," .. w.t end
    for k, d in pairs(KNOW.dead) do lines[#lines + 1] = "D " .. k .. "," .. d.t end
    return table.concat(lines, "\n") .. "\n"
  end
  local ok = saveFileSafe(path, text())
  local tries = 0
  while not ok and KNOW.n > 200 and tries < 4 do
    -- does not fit: keep only the newest half of the walls (they are relearnt)
    tries = tries + 1
    local was = CONFIG.turtles.knowMax
    CONFIG.turtles.knowMax = math.floor(KNOW.n / 2)
    KNOW.prune()
    CONFIG.turtles.knowMax = was
    ok = saveFileSafe(path, text())
  end
  if ok then dropOldCopy(CONFIG.turtles.knowFile, path, KNOW.n == 0) end
  if EXITROUTE then
    local f = fs.open(CONFIG.turtles.exitFile, "w")
    if f then f.write(textutils.serialize(EXITROUTE)) f.close() end
  elseif fs.exists(CONFIG.turtles.exitFile) then
    fs.delete(CONFIG.turtles.exitFile)
  end
  KNOW.dirty, KNOW.saved = false, os.clock()
end

-- read the saved knowledge, exit route and turtle list
function KNOW.load()
TT.loadList()
  if fs.exists(dataFile(CONFIG.turtles.knowFile)) then
    local h = fs.open(dataFile(CONFIG.turtles.knowFile), "r")
    while h do
      local line = h.readLine()
      if not line then break end
      local x, y, z, k, t = line:match("^W (-?%d+),(-?%d+),(-?%d+),(%a+),(%d+)$")
      if x then
        KNOW.walls[x .. "," .. y .. "," .. z] = { k = k, t = tonumber(t) }
        KNOW.n = KNOW.n + 1
      else
        local dx, dy, dz, dt = line:match("^D (-?%d+),(-?%d+),(-?%d+),(%d+)$")
        if dx then KNOW.dead[dx .. "," .. dy .. "," .. dz] = { t = tonumber(dt) } end
      end
    end
    if h then h.close() end
  end
  if fs.exists(CONFIG.turtles.exitFile) then
    local f = fs.open(CONFIG.turtles.exitFile, "r")
    if f then
      local t = textutils.unserialize(f.readAll() or "")
      f.close()
      if type(t) == "table" and t.route then EXITROUTE = t end
    end
  end
  KNOW.prune()
end

-- a turtle reports what it learnt
function KNOW.learn(m)
  local t = epoch()
  for x, y, z, k in tostring(m.walls or ""):gmatch("(-?%d+),(-?%d+),(-?%d+),(%a+)") do
    local key = x .. "," .. y .. "," .. z
    if not KNOW.walls[key] then KNOW.n = KNOW.n + 1 end
    KNOW.walls[key] = { k = k, t = t }
  end
  for x, y, z in tostring(m.clears or ""):gmatch("(-?%d+),(-?%d+),(-?%d+)") do
    local key = x .. "," .. y .. "," .. z
    if KNOW.walls[key] and KNOW.walls[key].t <= t then KNOW.walls[key] = nil KNOW.n = KNOW.n - 1 end
  end
  for x, y, z in tostring(m.dead or ""):gmatch("(-?%d+),(-?%d+),(-?%d+)") do
    KNOW.dead[x .. "," .. y .. "," .. z] = { t = t }
  end
  KNOW.dirty = true
end

-- what is known around an area (sent to a turtle before its trip)
function KNOW.around(x1, z1, x2, z2)
  local m = 48
  x1, z1, x2, z2 = x1 - m, z1 - m, x2 + m, z2 + m
  local list = {}
  for k, w in pairs(KNOW.walls) do
    local x, z = k:match("^(-?%d+),%-?%d+,(-?%d+)$")
    x, z = tonumber(x), tonumber(z)
    if x and x >= x1 and x <= x2 and z >= z1 and z <= z2 then list[#list + 1] = { k = k, w = w } end
  end
  table.sort(list, function(a, b) return a.w.t > b.w.t end)        -- newest first
  local walls = {}
  for i = 1, math.min(#list, 2500) do walls[i] = list[i].k .. "," .. list[i].w.k .. "," .. list[i].w.t end
  local dead = {}
  for k, d in pairs(KNOW.dead) do
    local x, z = k:match("^(-?%d+),%-?%d+,(-?%d+)$")
    x, z = tonumber(x), tonumber(z)
    if x and x >= x1 and x <= x2 and z >= z1 and z <= z2 then dead[#dead + 1] = k .. "," .. d.t end
  end
  return table.concat(walls, ";"), table.concat(dead, ";")
end

-- ===== turtle program updates =====
-- The base keeps node.lua next to inventory.lua. It fills in its own key,
-- protocol and name (so an update can never lock a turtle out), works out the
-- version (a checksum of the text) and sends it, in signed pieces, to every
-- idle turtle with another version. The turtle checks it and restarts.
CODE = nil               -- { text, ver, mod, pieces = {...} }
local CHUNK = 8000

-- readable version numbers: every new node.lua (new checksum) gets the next
-- number - v1, v2, v3 ... (kept in a small file)
local VER_FILE = "turtle_versions.dat"
TT.versions = { next = 1, byHash = {} }
do
  if fs.exists(VER_FILE) then
    local h = fs.open(VER_FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" and type(t.byHash) == "table" then TT.versions = t end
  end
end
-- "v7" for a checksum (number given when the base first loads that node.lua)
function TT.verName(hash)
  if not hash or hash == "?" then return "?" end
  local n = TT.versions.byHash[hash]
  return n and ("v" .. n) or "old"
end

-- checksum of node.lua (the turtles' version number)
-- long work in the map worker: let the screen and the other workers run now
-- and then (only there - other workers must not swallow their own events)
function TT.workYield()
  if TT.yieldCo and coroutine.running() == TT.yieldCo then
    os.queueEvent("base_working")
    os.pullEvent("base_working")
  end
end
local function codeHash(str)
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    if i % 16384 == 0 then TT.workYield() end
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end

-- replace the text value of a setting in node.lua (e.g. the key)
local function setStr(code, name, val)
  val = tostring(val):gsub("%%", "%%%%")
  return (code:gsub('(\n%s*' .. name .. '%s*=%s*)"[^"\n]*"', '%1"' .. val .. '"', 1))
end

-- node.lua: in the program folder, or (if it is not there) on a floppy -
-- the install floppy always has a copy
local function modTime(p)
  local ok, a = pcall(function() return fs.attributes and fs.attributes(p) end)
  return (ok and type(a) == "table" and tonumber(a.modified)) or 0
end

function TT.codePath()
  local name = CONFIG.turtles.codeFile or "node.lua"
  local here = fs.combine(BASE_DIR or "", name)
  -- a file dropped onto the computer can land in the top level instead of
  -- the program folder: use whichever of the two is newer
  local top = name
  if top ~= here and fs.exists(top) and (not fs.exists(here) or modTime(top) > modTime(here)) then
    return top
  end
  if fs.exists(here) then return here end
  for _, d in ipairs(mountedDisks()) do
    local p = fs.combine(d.mount, name)
    if fs.exists(p) then return p end
  end
  return here
end

-- the turtle program without comments and indentation (a floppy holds only
-- 125 KB; smaller updates too). Every line stays where it is - an error
-- message still names the right line of node.lua. Only whole-line comments
-- and --[[ ]] blocks go; code is never touched.
function TT.shrinkCode(text)
  local out, inBlock = {}, false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local t = line:match("^%s*(.-)$")
    if inBlock then
      if line:find("]]", 1, true) then inBlock = false end
      t = ""
    elseif t:sub(1, 4) == "--[[" then
      if not t:find("]]", 5, true) then inBlock = true end
      t = ""
    elseif t:sub(1, 2) == "--" then
      t = ""
    end
    out[#out + 1] = t
    if #out % 500 == 0 then TT.workYield() end
  end
  if out[#out] == "" then out[#out] = nil end
  return table.concat(out, "\n") .. "\n"
end

-- (re)read node.lua if it is new or changed
function TT.codeLoad(force)
  local path = TT.codePath()
  if not fs.exists(path) then CODE = nil return end
  -- changed? path, time AND size (a dropped-in file may keep its old time)
  local mod = path .. ":" .. modTime(path) .. ":" .. fs.getSize(path)
  if CODE and CODE.mod == mod and not force then return end
  local h = fs.open(path, "r")
  local text = h.readAll() or ""
  h.close()
  text = setStr(text, "protocol", CONFIG.turtles.protocol)
  text = setStr(text, "baseName", CONFIG.turtles.hostname)
  text = setStr(text, "key", CONFIG.turtles.key)
  -- the base runs the same Lua as the turtles: if it does not compile here,
  -- it would not compile there either - keep the version the turtles have
  TT.workYield()
  local okC, errC = load(text, "node", "t", {})
  TT.codeError = (not okC) and (path .. ": " .. tostring(errC)) or nil
  TT.workYield()
  if okC then
    -- send / install the small version (same code, no comments) if it compiles too
    local okS, small = pcall(TT.shrinkCode, text)
    if okS and load(small, "node", "t", {}) then text = small end
  end
  if not okC then
    if not (CODE and CODE.badMod == mod) then
      setPopup("TURTLE PROGRAM", "The new node.lua does not compile - not sent to the turtles: " ..
               tostring(errC), C.bad)
    end
    if CODE then CODE.badMod = mod end
    return
  end
  local pieces = {}
  for i = 1, #text, CHUNK do pieces[#pieces + 1] = text:sub(i, i + CHUNK - 1) end
  local ver = codeHash(text)
  if CODE and CODE.ver == ver then CODE.mod, CODE.path = mod, path return end   -- the same program
  CODE = { text = text, ver = ver, mod = mod, pieces = pieces, path = path }
  if not TT.versions.byHash[CODE.ver] then
    TT.versions.byHash[CODE.ver] = TT.versions.next
    TT.versions.next = TT.versions.next + 1
    saveFileSafe(VER_FILE, serialSmall(TT.versions))
    if next(state.turtles) then
      setToast("New turtle program " .. TT.verName(CODE.ver) .. " - updating the turtles one by one", C.label)
    end
    if sysLog then sysLog("New turtle program " .. TT.verName(CODE.ver) .. " (" .. #text .. " bytes)", "INFO") end
  end
  for _, t in pairs(state.turtles) do t.updSent, t.updRetry, t.updState = nil, nil, nil end
  TT.updating, TT.sending = nil, {}
  TT.writeInstallDisk()
end

-- send the program to one turtle
function TT.pushCode(id)
  if not CODE then return false end
  local t = state.turtles[id]
  for i, p in ipairs(CODE.pieces) do
    TT.send(id, "upd", { CODE.ver, i, #CODE.pieces, p }, true)
  end
  if t then
    t.updSent = os.clock()
    TT.log(t, "Sending the turtle program update " .. TT.verName(CODE.ver))
  end
  return true
end

-- updates, ONE turtle at a time (comms worker, every 2 s): send it, wait until
-- it runs the new version or has it ready (busy turtles install it after their
-- job), then the next one. No answer in 45 s: try that one again in 2 minutes.
-- Up to 3 turtles at a time. Runs when updates are on (SETTINGS) or for 10
-- minutes after UPDATE TURTLES (TT.updateForce). t.updState tells the screen
-- what is going on for each turtle: "sending", "ready", "retry", nil.
TT.sending = {}              -- [id] = time it was sent
function TT.updateTick()
  if not CODE then return end
  local forced = TT.updateForce and os.clock() < TT.updateForce
  if not CONFIG.turtles.autoUpdate and not forced then return end
  -- updates wait while you play (they restart the turtles) - at most 2 h
  if TT.codeSeenVer ~= CODE.ver then TT.codeSeenVer, TT.codeSeenAt = CODE.ver, os.clock() end
  TT.updWaiting = false
  if not forced and CONFIG.turtles.updateWhenAway ~= false and AWAY and not AWAY.on
     and AWAY.ownerOnline() == true and os.clock() - TT.codeSeenAt < 7200 then
    TT.updWaiting = true
    return
  end
  local now = os.clock()
  local busy = 0
  for id, t0 in pairs(TT.sending) do
    local t = state.turtles[id]
    if not t or t.ver == CODE.ver or t.updReady == CODE.ver then
      TT.sending[id] = nil
      if t then t.updState = (t.updReady == CODE.ver and t.ver ~= CODE.ver) and "ready" or nil end
    elseif now - t0 > 45 then
      TT.sending[id] = nil
      t.updRetry, t.updState = now + 120, "retry"
      t.updNote = "no answer in 45 s (scanning? out of range?)"
      TT.log(t, "No answer to the update - trying again in 2 min")
    else
      busy = busy + 1
    end
  end
  for _, t in ipairs(TT.list()) do
    if busy >= 3 then break end
    if TT.online(t) and TT.outdated(t) and t.updReady ~= CODE.ver and not TT.sending[t.id]
       and (not t.updRetry or now > t.updRetry) then
      TT.pushCode(t.id)
      TT.sending[t.id], t.updState = now, "sending"
      busy = busy + 1
    end
  end
  TT.updating = next(TT.sending) and { id = next(TT.sending), t0 = now } or nil
end

-- UPDATE TURTLES (button, console `update`, pocket): read node.lua again and
-- send it to every online turtle now - also while you play and when automatic
-- updates are off (10 min). A BUSY turtle that already has it waiting gets a
-- STOP (no hold): its job ends, it installs at once (a survey batch is handed
-- out again). Returns how many get it.
function TT.forceUpdate()
  pcall(TT.codeLoad, true)
  if not CODE then return nil end
  TT.updateForce = os.clock() + 600
  local n = 0
  for _, t in pairs(state.turtles) do
    if TT.online(t) and TT.outdated(t) then
      n = n + 1
      t.updRetry = nil
      if t.updState == "retry" then t.updState = nil end
      if t.updReady == CODE.ver and t.task and t.task ~= "idle" then
        TT.send(t.id, "stop", {}, true, true)
        TT.log(t, "UPDATE TURTLES: stopping its job so it installs " .. TT.verName(CODE.ver) .. " now")
      end
    end
  end
  return n
end

-- a turtle runs a new version now: tell the owner (and when all are done)
function TT.updated(t, oldVer)
  TT.log(t, "Updated: " .. TT.verName(oldVer) .. " -> " .. TT.verName(t.ver))
  setToast(t.label .. " updated to " .. TT.verName(t.ver), C.good)
  if not CODE then return end
  local n, all = 0, true
  for _, o in pairs(state.turtles) do
    if TT.online(o) then
      n = n + 1
      if o.ver ~= CODE.ver then all = false end
    end
  end
  if all and n > 1 then setToast("All " .. n .. " turtles run " .. TT.verName(CODE.ver), C.good) end
end

-- is this turtle's program older than the base's node.lua?
function TT.outdated(t)
  return CODE ~= nil and t.ver ~= nil and t.ver ~= "?" and t.ver ~= CODE.ver
end

-- the install floppy: a disk in a Disk Drive on this computer gets the
-- installer + the current program. Only empty disks or our own disk are used.
local INSTALLER = [[
-- TURTLE INSTALLER (kept up to date by the base computer).
-- Put a NEW turtle next to the disk drive with this disk and turn it on.
if not turtle then
  -- on the base computer (it booted from this floppy): start the base program instead
  for _, pattern in ipairs({ "inventory.lua", "*/inventory.lua", "*/*/inventory.lua" }) do
    for _, p in ipairs(fs.find(pattern)) do
      if fs.getDrive(p) == "hdd" then
        if fs.exists("startup.lua") then shell.run("/startup.lua") else shell.run("/" .. p) end
        return
      end
    end
  end
  print("This disk installs the turtle program - use it with a turtle.")
  return
end
local here = fs.getDir(shell.getRunningProgram())
local src = fs.combine(here, "node.lua")
if not fs.exists(src) then printError("node.lua is missing on this disk") return end
if not os.getComputerLabel() then os.setComputerLabel("Turtle " .. os.getComputerID()) end
if fs.exists("startup.lua") then
  if fs.exists("startup.old") then fs.delete("startup.old") end
  fs.move("startup.lua", "startup.old")
end
fs.copy(src, "startup.lua")
print("Turtle program installed on " .. os.getComputerLabel() .. ".")
print("Needs: an Ender (or Wireless) Modem and the Chunky upgrade equipped, fuel inside.")
print("Move it away from the drive or take the disk out. Starting now...")
sleep(2)
shell.run("/startup.lua")
]]
-- keep the install floppy up to date with the current node.lua
-- the INSTALL DRIVE: a Disk Drive only for install floppies (CONFIG.turtles.
-- installDrive, default "bottom"). A floppy put in there gets the installer
-- and the current node.lua at once; it is never used for the map.
function TT.installDrive()
  local n = CONFIG.turtles.installDrive or "bottom"
  if peripheral.isPresent(n) and peripheral.getType(n) == "drive" then return n end
end

-- write the installer + node.lua onto a mounted floppy (only what changed)
local function writeInstaller(d)
  local function put(file, text)
    local p = fs.combine(d.mount, file)
    if fs.exists(p) then                        -- unchanged: do not write again
      local h0 = fs.open(p, "r")
      local old = h0 and h0.readAll()
      if h0 then h0.close() end
      if old == text then return true end
    end
    local h = fs.open(p, "w")
    if not h then return false end
    local ok = pcall(h.write, text)
    pcall(h.close)
    return ok
  end
  local ok = put("startup.lua", INSTALLER) and put("node.lua", CODE.text) and put("turtle_installer", CODE.ver)
  pcall(disk.setLabel, d.name, "Turtle installer " .. TT.verName(CODE.ver))
  state.installDisk = d.name
  return ok
end

-- a floppy was put into the install drive: make it an install floppy
-- (empty or already an installer); never touches a data floppy or other files
function TT.prepareInstallFloppy(quiet)
  local drive = TT.installDrive()
  if not drive or not disk or not disk.hasData(drive) then return end
  if not CODE then
    setToast("No node.lua on this computer - cannot make an install floppy", C.warn)
    return
  end
  local d
  for _, m in ipairs(mountedDisks()) do if m.name == drive then d = m end end
  if not d then return end
  if d.data then
    setPopup("INSTALL DRIVE", "That is a data floppy (map) - it is not changed. Put an EMPTY floppy in.", C.warn)
    return
  end
  if not d.empty and not d.installer then
    setPopup("INSTALL DRIVE", "That floppy has other files on it - it is not changed. Put an EMPTY floppy in.", C.warn)
    return
  end
  local fresh = d.installer and fs.exists(fs.combine(d.mount, "turtle_installer"))
  if fresh then
    local h = fs.open(fs.combine(d.mount, "turtle_installer"), "r")
    fresh = h and h.readAll() == CODE.ver
    if h then h.close() end
  end
  if writeInstaller(d) then
    if not (quiet and fresh) then
      setToast("Install floppy ready (" .. TT.verName(CODE.ver) .. ") - take it out of the drive for a rescue turtle",
               C.good)
    end
  else
    setToast("Could not write the install floppy (full?)", C.bad)
  end
end

-- keep install floppies up to date (called when node.lua changes): the install
-- drive's floppy and any other installer floppy. Without an install drive the
-- first empty floppy becomes the installer (as before).
function TT.writeInstallDisk()
  if not CODE or not disk then return end
  local disks, target = mountedDisks(), {}
  local drive = TT.installDrive()
  for _, d in ipairs(disks) do
    if d.installer or (drive and d.name == drive and d.empty) then target[#target + 1] = d end
  end
  if #target == 0 and not drive then
    for _, d in ipairs(disks) do if d.empty and not d.data then target[1] = d break end end
  end
  for _, d in ipairs(target) do writeInstaller(d) end
end

-- ===== the turtle list survives restarts =====
-- Every turtle ever seen, with its last position and when it was last seen,
-- so a turtle that went quiet (e.g. while you were offline) can be found.
TT.listDirty = false
-- save every known turtle (turtles.dat)
function TT.saveList()
  local out = {}
  for id, t in pairs(state.turtles) do
    out[#out + 1] = { id = id, label = t.label, pos = t.pos, home = t.home, seen = t.seenEpoch,
                      task = t.task, ver = t.ver, gear = t.gear, anchor = t.anchor, rescuerRole = t.rescuerRole,
                      held = t.held, recall = t.recall, missing = t.missing }
  end
  saveFileSafe(CONFIG.turtles.listFile, serialSmall(out))
  TT.listDirty = false
end
-- read the saved turtle list
function TT.loadList()
  if not fs.exists(CONFIG.turtles.listFile) then return end
  local h = fs.open(CONFIG.turtles.listFile, "r")
  local list = textutils.unserialize(h.readAll() or "")
  h.close()
  if type(list) ~= "table" then return end
  for _, e in ipairs(list) do
    if type(e) == "table" and tonumber(e.id) then
      local t = TT.get(tonumber(e.id))
      if e.label then t.label = e.label end
      t.pos, t.home, t.seenEpoch, t.task = e.pos, e.home, e.seen, e.task
      t.ver, t.gear, t.anchor = e.ver, e.gear, e.anchor
      t.rescuerRole = e.rescuerRole
      t.held = e.held
      t.recall = e.recall
      t.missing = e.missing
    end
  end
end
-- "5 min ago", "14 h ago"
function TT.ago(epochMs)
  if not epochMs then return "never" end
  local s = math.floor((os.epoch("utc") - epochMs) / 1000)
  if s < 90 then return s .. " s ago" end
  if s < 5400 then return math.floor(s / 60) .. " min ago" end
  if s < 172800 then return math.floor(s / 3600) .. " h ago" end
  return math.floor(s / 86400) .. " days ago"
end

-- ===== search & rescue =====
local function hasGear(t, what)
  return type(t.gear) == "string" and ("," .. t.gear .. ","):find("," .. what .. ",", 1, true) ~= nil
end
-- what a rescue of this turtle needs: "install" (offline: reinstall it from
-- the install floppy) or "supply" (online but stuck / out of fuel)
function TT.rescueMode(t)
  if TT.online(t) then return "supply" end
  return "install"
end
-- the best turtle to send: online, idle, not the anchor, has the gear; nearest
function TT.pickRescuer(target, mode, x, z)
  local best, bestD
  for id, t in pairs(state.turtles) do
    if id ~= target.id and TT.online(t) and not t.anchor and not t.held and (t.task == nil or t.task == "idle")
       and t.pos and t.pos.x then
      local ok
      if mode == "install" then ok = hasGear(t, "drive") and hasGear(t, "floppy")
      else ok = hasGear(t, "fuel") or hasGear(t, "pick") end
      if ok then
        local d = math.abs(t.pos.x - x) + math.abs(t.pos.z - z)
        if not bestD or d < bestD then best, bestD = t, d end
      end
    end
  end
  return best
end
-- can this turtle rescue others? ("yes", or what is missing)
function TT.rescueReady(t)
  local miss = {}
  if not hasGear(t, "drive") then miss[#miss + 1] = "a Disk Drive" end
  if not hasGear(t, "floppy") then miss[#miss + 1] = "the install floppy" end
  if not hasGear(t, "scanner") then miss[#miss + 1] = "a Geo Scanner" end
  if #miss == 0 then
    return true, hasGear(t, "pick") and "can rescue lost turtles"
                 or "can rescue (no pickaxe: Disk Drives are left behind)", 0
  end
  if hasGear(t, "scanner") then
    -- enough to wake up a turtle in an unloaded area (going there loads it)
    return false, "wakes up lost turtles; reinstalling also needs " .. table.concat(miss, " + "), #miss
  end
  return false, "needs " .. table.concat(miss, " + "), #miss
end

-- nobody knows where they are: the best rescuer searches around the base and
-- reinstalls every turtle it finds that is not online
function TT.findLost(radius, cx, cy, cz)
  if not cx then
    local b = state.basePos or CONFIG.drone.home
    if not b then return false, "base position unknown - use: findlost <radius> <x> <y> <z>" end
    cx, cy, cz = b.x, b.y, b.z
  end
  local best, bestD
  local why, whyMiss = "no turtle is online and idle", math.huge
  for id, t in pairs(state.turtles) do
    if TT.online(t) and not t.anchor and not t.held and (t.task == nil or t.task == "idle") and t.pos and t.pos.x then
      local ok, msg, nmiss = TT.rescueReady(t)
      if ok then
        local d = math.abs(t.pos.x - cx) + math.abs(t.pos.z - cz)
        if not bestD or d < bestD then best, bestD = t, d end
      elseif nmiss < whyMiss then
        why, whyMiss = t.label .. " " .. msg, nmiss            -- the turtle closest to ready
      end
    end
  end
  if not best then return false, why end
  local skip = {}
  for id, t in pairs(state.turtles) do if TT.online(t) then skip[#skip + 1] = id end end
  radius = radius or 96
  TT.send(best.id, "sweep", { cx, cy, cz, radius, table.concat(skip, ",") })
  TT.log(best, "Searching for lost turtles within " .. radius .. " blocks of " .. cx .. " " .. cy .. " " .. cz)
  return true, best.label .. " is searching for lost turtles (" .. radius .. " blocks around the base)"
end

-- send a rescue; x y z = where to look (default: where it was last seen)
-- visit = true: the rescuer may go without reinstall gear (a turtle that is
-- only in an unloaded area wakes up when the rescuer gets there)
function TT.rescue(targetId, x, y, z, radius, forced, visit)
  local target = state.turtles[targetId]
  if not target then
    target = TT.get(targetId)
    target.label = target.label or ("Turtle " .. targetId)
  end
  if not x then
    if not (target.pos and target.pos.x) then return false, "its last position is unknown - give x y z" end
    x, y, z = target.pos.x, target.pos.y, target.pos.z
  end
  local mode = TT.rescueMode(target)
  local r = forced or TT.pickRescuer(target, mode, x, z)
  if forced then
    -- the permanent rescuer must carry what this rescue needs
    if mode == "install" and not visit and not (hasGear(forced, "drive") and hasGear(forced, "floppy")) then
      return false, forced.label .. " needs a Disk Drive and the install floppy to reinstall a turtle"
    elseif mode == "supply" and not (hasGear(forced, "fuel") or hasGear(forced, "pick")) then
      return false, forced.label .. " needs fuel (coal ...) or a spare pickaxe to bring"
    end
  end
  if not r then
    return false, mode == "install"
      and "no free turtle with a Disk Drive + the install floppy (and a Geo Scanner to search)"
      or "no free turtle with fuel or a spare pickaxe"
  end
  TT.send(r.id, "rescue", { target.id, x, y, z, mode, radius or 24 })
  TT.log(target, "Rescue on its way: " .. r.label .. " (" .. mode .. ")")
  target.rescuer = r.id
  return true, r.label .. " is on its way (" .. (mode == "install" and "reinstall" or "supplies") .. ")"
end

-- ===== cruise altitude =====
-- How high a turtle has to fly for a trip, from the map: the highest known
-- ground along its way (turtles go along X first, then Z - an L shape) plus a
-- few blocks. Detail columns are exact (+3); where only the overview (one
-- AVERAGE height per chunk) is known, +10 for hills inside the chunk. nil when
-- too much of the way is not mapped (the turtle then uses the sky highway).
function TT.cruiseHeight(fx, fz, tx, tz)
  if not (fx and fz and tx and tz) then return nil end
  local top, known, total = -64, 0, 0
  local function look(x, z)
    total = total + 1
    local h = MAP.get(x, z)
    if h then
      known = known + 1
      if h + 3 > top then top = h + 3 end
      return
    end
    h = MAP.getOverview(x, z)
    if h then
      known = known + 1
      if h + 10 > top then top = h + 10 end
    end
  end
  local function line(ax, az, bx, bz)
    local n = math.max(math.abs(bx - ax), math.abs(bz - az))
    local steps = math.max(1, math.floor(n / 4))
    for i = 0, steps do
      local x = ax + math.floor((bx - ax) * i / steps + 0.5)
      local z = az + math.floor((bz - az) * i / steps + 0.5)
      for d = -2, 2, 2 do                          -- a little to each side too
        if ax == bx then look(x + d, z) else look(x, z + d) end
      end
    end
  end
  line(fx, fz, tx, fz)                             -- first along X ...
  line(tx, fz, tx, tz)                             -- ... then along Z
  if total == 0 or known / total < 0.7 then return nil end
  return math.floor(top)
end

-- ===== the permanent RESCUE turtle =====
-- A turtle with the rescuer job (t.rescuerRole, RESCUER button) stays at home
-- and is sent out by the base when a turtle has a real problem:
--   no fuel  - online, fuel < 20 for over a minute (it would have refuelled itself)
--   stuck    - online, reports "stuck", idle for over a minute
--   lost     - silent for CONFIG.turtles.rescueAfter seconds (default 600)
-- A short disconnect is never mistaken for a lost turtle: 10 minutes of
-- silence, nothing in the first 5 minutes after the base starts, nothing when
-- half or more of the turtles are offline at once (server / base trouble),
-- and the rescue is called off when the turtle comes back.
TT.startedAt = os.clock()
local RETRY_AFTER, MAX_TRIES = 1800, 3

-- the rescuer(s): online ones first
function TT.rescuers()
  local list = {}
  for _, t in pairs(state.turtles) do if t.rescuerRole then list[#list + 1] = t end end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- what is wrong with a turtle (nil = nothing to do): "fuel", "stuck", "lost"
local function problemOf(t)
  local now = os.clock()
  if t.missing and not TT.online(t) then return nil end     -- looked for, not there: no more trips
  if TT.online(t) then
    t.offlineNoted = nil
    local idle = (t.task == nil or t.task == "idle")
    local fuel = tonumber(t.fuel)
    if fuel and fuel < 20 then t.lowFuelSince = t.lowFuelSince or now else t.lowFuelSince = nil end
    if t.stuck and idle then t.stuckSince = t.stuckSince or now else t.stuckSince = nil end
    if t.lowFuelSince and now - t.lowFuelSince > 60 then return "fuel" end
    if t.stuckSince and now - t.stuckSince > 60 then return "stuck" end
    return nil
  end
  -- offline: how long, by the real clock (also from before the base started)
  if not (t.pos and t.pos.x and t.seenEpoch) then return nil end
  local after = tonumber(CONFIG.turtles.rescueAfter) or 180
  if (os.epoch("utc") - t.seenEpoch) / 1000 < after then return nil end
  return "lost"
end

-- comms worker, every 2 s: send the rescuer where it is needed
function TT.patrolTick()
  local rescuers = TT.rescuers()
  if #rescuers == 0 then return end
  local now = os.clock()
  local total, offline = 0, 0
  for _, t in pairs(state.turtles) do
    if not t.rescuerRole and not t.missing then
      total = total + 1
      if not TT.online(t) then offline = offline + 1 end
    end
  end
  local massOffline = total >= 2 and offline * 2 >= total
  local warmingUp = now - TT.startedAt < 300
  -- every turtle's problem, every tick (so the "for over a minute" timers run
  -- also while the rescuer is busy)
  local problems = {}
  for id, t in pairs(state.turtles) do
    if not t.rescuerRole then problems[id] = problemOf(t) end
    -- fine for 5 minutes: its rescue tries start again from 0
    if TT.online(t) and not problems[id] and not t.rescuer then
      t.fineSince = t.fineSince or now
      if now - t.fineSince > 300 then t.rescueTries, t.rescueAt = nil, nil end
    else
      t.fineSince = nil
    end
  end
  for _, t in pairs(state.turtles) do
    -- a rescue on its way: called off if the turtle is fine again
    if t.rescuer and t.rescueKind then
      local r = state.turtles[t.rescuer]
      local fine = (t.rescueKind == "lost" and TT.online(t))
                   or (t.rescueKind ~= "lost" and TT.online(t) and not problems[t.id])
      if fine then
        if r then
          TT.send(r.id, "stop", {})
          TT.send(r.id, "home", {})
          TT.log(r, "Rescue of " .. t.label .. " called off - it is fine again")
        end
        TT.log(t, "Fine again - rescue called off")
        t.rescuer, t.rescueKind = nil, nil
        t.rescueTries, t.rescueAt = nil, nil         -- a new problem later gets new tries
      end
    end
  end
  for _, r in ipairs(rescuers) do
    local free = TT.online(r) and (r.task == nil or r.task == "idle") and not r.stopAsk and not r.held
    if free then
      -- the turtle with the oldest problem first
      local pick, pickKind, pickScore
      for _, t in pairs(state.turtles) do
        if not t.rescuerRole and not t.rescuer and (t.rescueTries or 0) < MAX_TRIES
           and (not t.rescueAt or now - t.rescueAt > RETRY_AFTER) then
          local kind = problems[t.id]
          -- many offline at once (a server restart / crash): first wait - they may
          -- come back by themselves; still silent after rescueAfterCrash: go
          local silent = t.seenEpoch and (os.epoch("utc") - t.seenEpoch) / 1000 or 0
          if kind == "lost" and (warmingUp or (massOffline and silent < (tonumber(CONFIG.turtles.rescueAfterCrash) or 600))) then
            kind = nil
          end
          -- one already on its way to a turtle close by: arriving there wakes this one too
          if kind == "lost" then
            for _, o in pairs(state.turtles) do
              if o.rescuer and o.rescueKind == "lost" and o.pos and o.pos.x and t.pos and t.pos.x
                 and math.abs(o.pos.x - t.pos.x) <= 48 and math.abs(o.pos.z - t.pos.z) <= 48 then kind = nil end
            end
          end
          if kind then
            -- lost turtles: the biggest group first (one trip wakes the whole pack)
            local score = 0
            if kind == "lost" then
              for oid, o in pairs(state.turtles) do
                if problems[oid] == "lost" and o.pos and o.pos.x and t.pos and t.pos.x
                   and math.abs(o.pos.x - t.pos.x) <= 48 and math.abs(o.pos.z - t.pos.z) <= 48 then score = score + 1 end
              end
            else
              score = 1000                          -- no fuel / stuck (online): first
            end
            if not pick or score > pickScore then pick, pickKind, pickScore = t, kind, score end
          end
        end
      end
      if pick then
        local ok, msg = TT.rescue(pick.id, nil, nil, nil, nil, r, pickKind == "lost")
        pick.rescueAt, pick.rescueTries = now, (pick.rescueTries or 0) + 1
        if ok then
          pick.rescueKind = pickKind
          if pickKind == "lost" and (pickScore or 0) > 1 then
            TT.log(r, "Going to " .. pick.label .. " - " .. pickScore .. " offline turtles are there together")
          end
          setToast("Rescuer " .. r.label .. " sent to " .. pick.label .. " (" ..
                   (pickKind == "lost" and "offline - going there wakes it up" or pickKind == "fuel" and "no fuel" or "stuck") .. ")",
                   C.label)
        else
          TT.log(r, "Cannot rescue " .. pick.label .. ": " .. tostring(msg))
        end
        if pick.rescueTries >= MAX_TRIES and not ok then
          setPopup("TURTLE NEEDS YOU", pick.label .. " could not be rescued " .. MAX_TRIES .. " times - please look at it (" ..
                   (pick.pos and fmtPos(pick.pos.x, pick.pos.y, pick.pos.z) or "position unknown") .. ")", C.warn)
        end
      end
    end
  end
end

-- digging on/off for every turtle (the SETTINGS page): sent to all online ones
function TT.setDig(on)
  setSetting("turtles.dig", on and true or false)
  local n = 0
  for id, t in pairs(state.turtles) do
    if TT.online(t) then TT.send(id, "setting", { "dig", tostring(on and true or false) }, true) n = n + 1 end
  end
  return n
end

-- ===== keep away from other players =====
-- The Player Detector knows where every online player is; turtles that have
-- a player to avoid within CONFIG.turtles.avoidRange blocks (default 100,
-- 0 = off) stop their job and go home; survey spots near them wait.
-- Who: "strangers" (default: not you, not on the allow list) or "everyone"
-- (everyone but you). Overworld only (where the turtles are).
function TT.threats()
  local range = tonumber(CONFIG.turtles.avoidRange or 100) or 0
  if range <= 0 then return {}, 0 end
  -- owner not known yet (Inventory Manager not read): nobody is avoided, so
  -- the owner is never mistaken for a stranger
  if not state.owner then return {}, 0 end
  local me = tostring(state.owner):lower()
  local who = CONFIG.turtles.avoidWho or "strangers"
  local list = {}
  for _, e in ipairs(state.players or {}) do
    local friend = e.isOwner or tostring(e.name):lower() == me or (who ~= "everyone" and state.access and state.access.allowed
                                 and state.access.allowed[tostring(e.name):lower()])
    -- only players KNOWN to be in the overworld: one in another dimension (a
    -- mining dimension uses the same x z) must not hold the turtles back
    local here = e.p and e.p.x and not e.dimOther and e.dim == (DRONE_DIM or "minecraft:overworld")
    if not friend and here then list[#list + 1] = { name = e.name, x = e.p.x, z = e.p.z } end
  end
  return list, range
end
-- the nearest player to avoid from x z: name, distance (nil if none in range)
function TT.nearThreat(x, z, list, range)
  local best, bd
  for _, p in ipairs(list) do
    local d = math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2)
    if d <= range and (not bd or d < bd) then best, bd = p.name, d end
  end
  return best, bd
end
-- comms worker: surveying turtles near a player stop and go home
function TT.avoidTick()
  local list, range = TT.threats()
  if #list == 0 then
    -- the player has gone: no trip home needed any more (it gets work again)
    for _, t in pairs(state.turtles) do t.avoidHome = nil end
    return
  end
  local now = os.clock()
  for id, t in pairs(state.turtles) do
    if TT.online(t) and t.pos and t.pos.x and not t.anchor and not t.held then
      -- a player AT THIS TURTLE'S HOME (a visitor at the base) is not avoided:
      -- the turtle only passes them on its way out / in, and sending it home
      -- would bring it right back to them (a loop)
      local away = list
      if t.home and t.home.x then
        away = {}
        for _, p in ipairs(list) do
          if math.sqrt((p.x - t.home.x) ^ 2 + (p.z - t.home.z) ^ 2) > range then away[#away + 1] = p end
        end
      end
      local name, d = TT.nearThreat(t.pos.x, t.pos.z, away, range)
      -- only map work is given up (survey / scans); trips home, refuelling and rescues go on
      local task = tostring(t.task or "")
      local work = task:find("^survey") or task:find("^scanning")
      local recently = t.avoidAt and now - t.avoidAt < 60
      if name and work and not recently then
        t.avoidAt, t.avoidHome = now, true
        TT.send(id, "stop", {}, true, true)                    -- not a STOP by you: no hold
        TT.log(t, "Player " .. name .. " " .. math.floor(d) .. " blocks away - stopping, going home")
        if not t.avoidSaid or now - t.avoidSaid > 600 then
          t.avoidSaid = now
          setPopup("PLAYER NEAR A TURTLE", (t.label or ("Turtle " .. id)) .. ": " .. name .. " is " .. math.floor(d) ..
                   " blocks away (" .. math.floor(t.pos.x) .. " " .. math.floor(t.pos.z) .. ") - it went home", C.warn)
        end
      end
    end
    -- stopped because of a player: home as soon as it is idle
    if t.avoidHome and TT.online(t) and (t.task == nil or t.task == "idle") then
      t.avoidHome = nil
      if t.home then TT.send(id, "home", {}, true) end
    end
  end
end

-- ===== homes and idle turtles =====
-- A turtle without a home is offered one: next to another turtle's home (one
-- block along X or Z, same height), never a spot that is already a home, an
-- offer to another turtle, or a spot it reported as not free.
function TT.homeSpot(t)
  local taken, homes = {}, {}
  for _, o in pairs(state.turtles) do
    if o.home and o.home.x then
      taken[o.home.x .. "," .. o.home.y .. "," .. o.home.z] = true
      if o.id ~= t.id then homes[#homes + 1] = o end
    end
    if o.homeOffer and o.id ~= t.id then taken[o.homeOffer] = true end
  end
  table.sort(homes, function(a, b) return a.id < b.id end)
  local bad = t.homeBad or {}
  for _, o in ipairs(homes) do
    local h = o.home
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local x, y, z = h.x + d[1], h.y, h.z + d[2]
      local k = x .. "," .. y .. "," .. z
      if not taken[k] and not bad[k] then return x, y, z end
    end
  end
end

-- comms worker, every 2 s: offer homes, send idle turtles home
function TT.homeTick()
  local now = os.clock()
  local idleHome = tonumber(CONFIG.turtles.idleHome or 120) or 0    -- seconds; 0 = off
  local queueIds
  for id, t in pairs(state.turtles) do
    local on = TT.online(t)
    -- 1) no home yet: offer one (once a minute at most)
    if on and not t.home then
      if not t.homeOfferAt or now - t.homeOfferAt > 60 then
        t.homeOfferAt = now
        local x, y, z = TT.homeSpot(t)
        if x then
          t.homeOffer = x .. "," .. y .. "," .. z
          TT.send(id, "homeoffer", { x, y, z }, true)
          TT.log(t, "No home yet - offered " .. x .. " " .. y .. " " .. z .. " (next to another turtle's home)")
        elseif not t.homeNoSpotSaid then
          t.homeNoSpotSaid = true
          TT.log(t, "No home yet, and no other turtle has one to sit next to - press SET HOME on one turtle")
        end
      end
    elseif t.home then
      t.homeOffer = nil
    end
    -- 2) idle away from home: go home (a turtle out there keeps its chunk
    --    loaded for nothing). Not: stopped by you, the anchor, stuck, a turtle
    --    a running big survey still needs.
    local idle = on and (t.task == nil or t.task == "idle")
    if idle then t.idleSince = t.idleSince or now else t.idleSince = nil end
    -- low on fuel: home after 10 s (the fuel chest is there), not after idleHome
    local fuel = tonumber(t.fuel)
    -- while you are away they top up earlier (full tanks when you are back)
    local low = fuel and fuel < (tonumber(CONFIG.turtles.lowFuel) or 2000) * ((AWAY and AWAY.on) and 3 or 1)
    -- the shared fuel chest (CONFIG.turtles.fuelChest): one turtle at a time
    -- goes there, refuels and goes home
    local fc = CONFIG.turtles.fuelChest
    if TT.fuelTrip and (not state.turtles[TT.fuelTrip.id] or now - TT.fuelTrip.t0 > 600) then TT.fuelTrip = nil end
    if low and fc and fc.x and idle and on and t.pos and t.pos.x and not t.held and not t.anchor and not t.stuck
       and not t.rescuer and not TT.fuelTrip and now - t.idleSince > 10
       and (not t.fuelTripAt or now - t.fuelTripAt > 600) then
      t.fuelTripAt = now
      TT.fuelTrip = { id = id, t0 = now }
      TT.send(id, "fuelup", { fc.x, fc.y, fc.z }, true)
      TT.log(t, "Low on fuel (" .. fuel .. ") - going to the fuel chest at " .. fc.x .. " " .. fc.y .. " " .. fc.z)
      low = false                        -- not also sent home below
      t.idleHomeAt = now
    elseif low and fc and fc.x and (not t.fuelTripAt or now - t.fuelTripAt > 600) then
      low = "wait"                       -- the fuel chest is busy: wait for it, do not go home first
    end
    local wait = low and 10 or idleHome
    if low ~= "wait" and idleHome > 0 and idle and t.home and t.pos and t.pos.x and not t.held and not t.anchor
       and not t.stuck and not t.rescuer and now - t.idleSince > wait
       and (not t.idleHomeAt or now - t.idleHomeAt > 600) then
      local away = math.abs(t.pos.x - t.home.x) + math.abs(t.pos.y - t.home.y) + math.abs(t.pos.z - t.home.z)
      local needed = false
      if MAP.queue and not t.rescuerRole and not low then     -- low on fuel: it gets no batches anyway
        queueIds = queueIds or MAP.queue.ids or TT.available()
        for _, qid in ipairs(queueIds) do
          if qid == id and not (MAP.queue.excluded and MAP.queue.excluded[id]) then needed = true end
        end
      end
      if away > 2 and not needed then
        t.idleHomeAt = now
        TT.send(id, "home", {}, true)
        TT.log(t, low and ("Low on fuel (" .. fuel .. ") - going home to the fuel chest")
                   or ("Idle for " .. math.floor(now - t.idleSince) .. " s away from home - going home"))
      end
    end
    -- 3) STUCK and it carries a pickaxe (e.g. the rescuer after a rescue, in a cave):
    --    it digs its own way home - natural blocks only (node.lua). Every 10 min,
    --    3 tries; a turtle that is fine again starts counting from 0.
    if not t.stuck then t.digOutTries = nil end
    if on and idle and t.stuck and t.home and not t.held and not t.anchor and not t.missing
       and tostring(t.gear or ""):find("pick", 1, true)
       and now - (t.idleSince or now) > 30 and (t.digOutTries or 0) < 3
       and (not t.digOutAt or now - t.digOutAt > 600) then
      t.digOutAt, t.digOutTries = now, (t.digOutTries or 0) + 1
      TT.send(id, "home", { "dig" }, true)
      TT.log(t, "Stuck (" .. tostring(t.stuck) .. ") - digging its way home through natural blocks (try " ..
                t.digOutTries .. "/3)")
    end
  end
end

-- DRIVE page: one step by hand ("f" "b" "u" "d" "l" "r", "digf/u/d", "minef/u/d", "look");
-- force = DIG ANYWAY. Quiet (no log line per step); a STOP hold ends.
function TT.drive(id, act, force)
  local t = state.turtles[id]
  if not t then return end
  t.held = nil
  t.driveLast, t.driveSent, t.driveMsg = act, os.clock(), nil
  if not force then t.driveAnyway = nil end
  TT.send(id, "drive", { act, force and "force" or nil }, true)
  TT.listDirty = true
end
local LOOKDIR = { north = { 0, -1 }, east = { 1, 0 }, south = { 0, 1 }, west = { -1, 0 } }
-- what a driven turtle sees: front / up / down, and (LOOK) a scan of radius 3.
-- Kept in WORLD positions (t.view.cells["x,y,z"] = name), so it stays right as it moves.
function TT.lookIn(t, m)
  local p = m.pos or t.pos
  local v = t.view or {}
  if type(v.cells) ~= "table" then v.cells = {} end
  if p and p.x and type(m.scan) == "string" then
    v.cells, v.scanAt = {}, os.clock()
    -- the scan lists blocks only: everything else within its radius (3) is AIR
    local f = math.floor
    for ax = -3, 3 do for ay = -3, 3 do for az = -3, 3 do
      v.cells[f(p.x + ax) .. "," .. f(p.y + ay) .. "," .. f(p.z + az)] = false
    end end end
    for dx, dy, dz, name in m.scan:gmatch("(-?%d+),(-?%d+),(-?%d+),([^;]+)") do
      local f = math.floor
      v.cells[f(p.x + tonumber(dx)) .. "," .. f(p.y + tonumber(dy)) .. "," .. f(p.z + tonumber(dz))] = name
    end
  end
  local function set(x, y, z, name)
    local k = math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
    if not name or name == "air" or name:find(":air$") then v.cells[k] = false
    else v.cells[k] = tostring(name):gsub("^minecraft:", "") end
  end
  if p and p.x then
    set(p.x, p.y, p.z, nil)                                   -- (where it stands is free)
    set(p.x, p.y + 1, p.z, m.up)
    set(p.x, p.y - 1, p.z, m.down)
    local d = LOOKDIR[tostring(p.f)]
    if d then set(p.x + d[1], p.y, p.z + d[2], m.front) end
  end
  v.front, v.up, v.down, v.at, v.scanErr = m.front, m.up, m.down, os.clock(), m.scanErr
  t.view = v
end

-- the anchor turtle, and whether it is in the base's chunk
function TT.anchorInfo()
  for _, t in pairs(state.turtles) do
    if t.anchor then
      local inChunk
      local b = state.basePos
      if b and t.pos and t.pos.x then
        inChunk = math.floor(t.pos.x / 16) == math.floor(b.x / 16)
              and math.floor(t.pos.z / 16) == math.floor(b.z / 16)
      end
      return t, inChunk
    end
  end
end

-- turtles that can take a job right now: online, position known, idle,
-- and not the anchor (a STOPPED one counts: you choose it yourself)
function TT.available()
  local list = {}
  for id, t in pairs(state.turtles) do
    if TT.online(t) and t.pos and t.pos.x and (t.task == nil or t.task == "idle") and not t.anchor
       and not t.rescuerRole then
      list[#list + 1] = id
    end
  end
  table.sort(list)
  return list
end

-- split survey spots between turtles: one strip per turtle (along the longer
-- side of the area), each strip going to the turtle closest to it
function TT.splitSurvey(spots, ids)
  local out = {}
  -- only turtles with a known position can take a share
  local known = {}
  for _, id in ipairs(ids) do
    local t = state.turtles[id]
    if t and t.pos and t.pos.x then known[#known + 1] = id end
  end
  ids = known
  if #ids == 0 or #spots == 0 then return out end
  local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(spots) do
    minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
    minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
  end
  -- cut the strips along the direction the turtles are spread out in (so each
  -- works on its own side); if they stand close together, along the longer side
  local alongX = (maxX - minX) >= (maxZ - minZ)
  if #ids >= 2 then
    local tminX, tmaxX, tminZ, tmaxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, id in ipairs(ids) do
      local p = state.turtles[id].pos
      tminX, tmaxX = math.min(tminX, p.x), math.max(tmaxX, p.x)
      tminZ, tmaxZ = math.min(tminZ, p.z), math.max(tmaxZ, p.z)
    end
    local sx, sz = tmaxX - tminX, tmaxZ - tminZ
    if math.max(sx, sz) >= 17 then alongX = sx >= sz end
  end
  local sorted = {}
  for i, p in ipairs(spots) do sorted[i] = p end
  table.sort(sorted, function(a, b)
    if alongX then return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end
    return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1])
  end)
  local n = math.min(#ids, #sorted)
  local groups = {}
  for i = 1, n do groups[i] = {} end
  for i, p in ipairs(sorted) do
    local gi = math.floor((i - 1) * n / #sorted) + 1
    groups[gi][#groups[gi] + 1] = p
  end
  -- closest turtle/strip pairs first
  local pairsList = {}
  for _, id in ipairs(ids) do
    local t = state.turtles[id]
    for gi, g in ipairs(groups) do
      local sx, sz = 0, 0
      for _, p in ipairs(g) do sx, sz = sx + p[1], sz + p[2] end
      sx, sz = sx / #g, sz / #g
      pairsList[#pairsList + 1] = { id = id, gi = gi, d = math.abs(t.pos.x - sx) + math.abs(t.pos.z - sz) }
    end
  end
  table.sort(pairsList, function(a, b) return a.d < b.d end)
  local usedT, usedG = {}, {}
  for _, pr in ipairs(pairsList) do
    if not usedT[pr.id] and not usedG[pr.gi] then
      usedT[pr.id], usedG[pr.gi] = true, true
      out[pr.id] = groups[pr.gi]
    end
  end
  return out
end

-- send one turtle its list of spots
function TT.sendSpots(id, spots, r)
  local args = { r }
  for _, p in ipairs(spots) do
    args[#args + 1] = p[1]
    args[#args + 1] = p[2]
  end
  TT.send(id, "surveypts", args)
end

-- queue a signed command for a turtle (sent by the comms worker)
-- STOP must arrive: a surveying turtle takes its modem off for every scan
-- (the Geo Scanner goes in its place) and hears nothing then. So STOP is sent
-- again every 3 s until the turtle answers or is idle (up to a minute), and
-- the turtle gets no more batches from a big survey.
function TT.stopTick()
  for _, t in pairs(state.turtles) do
    local s = t.stopAsk
    if s and os.clock() - s.last >= 3 then
      if s.tries >= 20 then
        t.stopAsk = nil
        TT.log(t, "STOP: no answer for a minute - sent again when it is back")
        setToast(t.label .. " does not answer STOP - it gets STOP again as soon as it is back", C.warn)
      else
        s.tries, s.last = s.tries + 1, os.clock()
        TT.send(t.id, "stop", {}, true, true)
      end
    end
  end
end

function TT.send(id, cmd, args, quiet, again)
  local n = os.epoch("utc")
  if n <= state.tLastN then n = state.tLastN + 1 end
  state.tLastN = n
  local a = {}
  for i, v in ipairs(args or {}) do a[i] = v end
  state.tOut[#state.tOut + 1] = { id = id, msg = { t = "cmd", n = n, cmd = cmd, args = a,
                                    sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) } }
  local t = state.turtles[id]
  -- any command you give (not the quiet automatic ones) ends a STOP hold
  if t and t.held and cmd ~= "stop" and not quiet then t.held = nil TT.listDirty = true end
  if cmd == "stop" and t and not again then
    t.stopAsk = { tries = 1, last = os.clock() }
    t.held = true                                -- stays stopped (also after a reload)
    TT.listDirty = true
    if MAP.queue then
      MAP.queue.excluded = MAP.queue.excluded or {}
      MAP.queue.excluded[id] = true                -- no more big-survey batches for it
    end
  end
  if t and not quiet then
    local shown = {}
    for i, v in ipairs(a) do shown[i] = tostring(v) end
    if cmd == "surveypts" then
      TT.log(t, "> survey: " .. math.floor((#a - 1) / 2) .. " spots")
    else
      TT.log(t, "> " .. cmd .. (#shown > 0 and (" " .. table.concat(shown, " ")) or ""))
    end
  end
  os.queueEvent("turtle_send")
end


KNOW.load()
