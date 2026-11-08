-- base_pocket.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   POCKET REMOTE: your Advanced Pocket Computer (with a wireless / ender modem
--   upgrade) running pocket.lua. Pairing once: the pocket asks, the monitor
--   shows a 6-digit code, you type it on the pocket - the base gives that pocket
--   its own key (sent scrambled with the code, so listening does not get it).
--   Every message is signed with that key and numbered (no replays).
--   The pocket can ask for the status (turtles, mining, factory, survey,
--   drones, places) and do: drone rides (to the base / a place / back),
--   turtle STOP / HOME / GPS (one or all), mining START / PAUSE / UNLOAD,
--   work-area corners where you stand, a survey around you, factory retry.
--   Warnings and errors from the monitor are sent to it as they happen.

POCKET = { PROTO = "basepocket", pockets = {}, pairing = nil, out = {} }
local FILE = "pockets.dat"

do
  if fs.exists(FILE) then
    local h = fs.open(FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then POCKET.pockets = t end
  end
end
local function save() saveFileSafe(FILE, serialSmall(POCKET.pockets)) end
POCKET.save = save

local function sign(key, t, n, a, args) return TT.sign(key, t, n, a, args) end
local seq = 0
local function nextN()
  seq = seq + 1
  return os.epoch("utc") * 100 + seq % 100
end
-- a message for a pocket (sent by the comms worker), signed with its key
local function send(id, t, body, key)
  local m = body or {}
  m.t, m.n = t, nextN()
  m.sig = sign(key or (POCKET.pockets[id] and POCKET.pockets[id].key) or "", m.t, m.n)
  POCKET.out[#POCKET.out + 1] = { id = id, msg = m }
  os.queueEvent("turtle_send")
end
POCKET.send = send

-- the code's scramble for the key: a number stream from the code and the pocket's id
function POCKET.stream(code, id, len)
  local out, i = {}, 0
  while #out < len do
    i = i + 1
    local h = sign(tostring(code), "ks", tostring(id) .. ":" .. i)
    for k = 1, #h, 2 do out[#out + 1] = tonumber(h:sub(k, k + 1), 16) end
  end
  return out
end
function POCKET.scramble(text, code, id, back)
  local ks = POCKET.stream(code, id, #text)
  local o = {}
  for i = 1, #text do
    local b = text:byte(i)
    o[i] = string.char(back and (b - ks[i]) % 256 or (b + ks[i]) % 256)
  end
  return table.concat(o)
end
local function randomKey()
  local t = {}
  for i = 1, 24 do t[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(t)
end

----------------------------------------------------------------- what the pocket sees
local function short(s, n) s = tostring(s or "") return #s > n and (s:sub(1, n - 1) .. ".") or s end
function POCKET.status()
  local d = { base = os.getComputerLabel() or ("Base " .. os.getComputerID()), t = os.epoch("utc") }
  -- turtles
  local counts, needs, list = {}, {}, {}
  for _, t in ipairs(TT.list()) do
    local key, lab, _, why = TT.status(t)
    counts[key] = (counts[key] or 0) + 1
    if key == "stuck" or key == "nofuel" or key == "still" or key == "missing" then
      needs[#needs + 1] = { id = t.id, label = short(t.label, 12), lab = lab, why = short(why, 60) }
    end
    if #list < 40 then
      list[#list + 1] = { id = t.id, label = short(t.label, 12), lab = lab, key = key, fuel = tonumber(t.fuel),
                          pick = tostring(t.gear or ""):find("pick", 1, true) and true or nil,
                          task = short(t.task, 40), why = short(why, 60) }
    end
  end
  d.counts, d.needs, d.turtles = counts, needs, list
  -- mining teams
  d.mining = {}
  for dim, team in pairs(MINE and MINE.teams() or {}) do
    local l = team.loader
    local T = MINE.totals(team)
    local gone = {}
    for _, m in ipairs(team.miners) do
      if not MINE.online(m) and m.seenEpoch and os.epoch("utc") - m.seenEpoch > 1200000 then
        gone[#gone + 1] = { id = m.id, label = short(m.label or ("#" .. m.id), 12) }
      end
    end
    d.mining[#d.mining + 1] = { dim = dim, loader = l and l.id, label = l and MINE.status(l) or "MISSING",
                                running = l and l.running and true or false, miners = #team.miners,
                                ci = tonumber(T.ci) or 0, rate = math.floor(T.rate or 0), ores = T.ores, gone = gone }
  end
  -- factory, survey, away
  if FACTORY then d.factory = FACTORY.statusLine() end
  local frac = MAP.surveyProgress and MAP.surveyProgress()
  d.survey = frac and math.floor(frac * 100) or nil
  d.auto = MAP.auto and MAP.auto.on or false
  local x1, z1, x2, z2 = MAP.area()
  d.area = x1 and (x1 .. " " .. z1 .. " to " .. x2 .. " " .. z2) or "whole world"
  d.away = AWAY and AWAY.on or false
  -- drones + places
  d.drones = {}
  for _, k in ipairs(droneOrder or {}) do
    local dr = drones[k]
    d.drones[#d.drones + 1] = { label = dr.label, busy = dr.busy and true or false, conn = dr.conn and true or false,
                                bar = dr.pressure and math.floor(dr.pressure * 10) / 10 }
  end
  d.places = {}
  for _, w in ipairs(state.waypoints or {}) do if #d.places < 24 then d.places[#d.places + 1] = w.name end end
  d.back = state.owner and backSpots and backSpots[state.owner:lower()] and true or false
  return d
end

-- the turtle being driven from the pocket: the same six rows as the monitor
function POCKET.driveView(id)
  local t = id and state.turtles[id]
  if not t then return nil end
  local rows = {}
  for _, r in ipairs(driveRows(t)) do
    rows[#rows + 1] = { dir = r.dir, what = driveWord(r.name), seen = r.name ~= nil, key = r.key, act = r.act, does = r.does }
  end
  local m = t.driveMsg
  return { id = t.id, label = short(t.label, 14), facing = t.pos and t.pos.f, fuel = tonumber(t.fuel), rows = rows,
           online = TT.online(t), waiting = (t.driveSent and not m) and math.floor(os.clock() - t.driveSent) or nil,
           msg = m and ((m.ok and "OK: " or "NO: ") .. short(m.msg, 60)) or nil, anyway = t.driveAnyway }
end

----------------------------------------------------------------- what the pocket can do
local TCMDS = { stop = true, home = true, locate = true, ping = true, digup = true }
local DRIVE_ACTS = { minef = true, mineu = true, mined = true, l = true, r = true, b = true, around = true, look = true,
                     digf = true, digu = true, digd = true }
-- the owner is in another dimension (the Player Detector knows): positions from
-- the pocket's GPS there are not overworld places
local function elsewhere()
  local d = state.playerDim
  if d and d ~= (DRONE_DIM or "minecraft:overworld") then return "you are in " .. (dimName and dimName(d) or tostring(d)) ..
    " - corners / surveys are for the overworld" end
end
local function ownerPos()
  for _, e in ipairs(state.players or {}) do
    if e.name == state.owner and e.p and e.p.x then return math.floor(e.p.x), math.floor(e.p.y), math.floor(e.p.z) end
  end
end
function POCKET.act(a, args, pos)
  args = args or {}
  local owner = state.owner
  if a == "ride" then
    -- ride: "base" / a place name / "back"
    if not owner then return false, "who you are is not known yet (Inventory Manager)" end
    local where = tostring(args[1] or "base")
    local dest
    if where == "back" then
      local b = backSpots and backSpots[owner:lower()]
      if not b then return false, "no earlier spot known for you" end
      dest = { kind = "coords", name = b.why .. " (" .. b.x .. " " .. b.y .. " " .. b.z .. ")", x = b.x, y = b.y + 1, z = b.z }
    else
      local w = findWaypoint(where == "base" and "Base" or where)
      if not w and where == "base" and CONFIG.drone.home then
        local h = CONFIG.drone.home
        w = { name = "Base", x = h.x, y = h.y, z = h.z }
      end
      if not w then return false, "no place called " .. where end
      dest = { kind = "waypoint", name = w.name, x = w.x, y = w.y, z = w.z }
    end
    local problem = rideProblem(owner, dest)
    if problem then return false, problem end
    startRide(owner, dest, true)
    return true, "a drone is on its way to you (to " .. dest.name .. ")"
  elseif a == "ridestop" then
    local n = 0
    for _, k in ipairs(droneOrder or {}) do
      local dr = drones[k]
      if dr.busy and dr.requester == owner then submitDrone(dr, { kind = "stop" }) n = n + 1 end
    end
    return n > 0, n > 0 and ("stopped " .. n .. " drone(s)") or "no drone is working for you"
  elseif a == "turtle" then
    local t = state.turtles[tonumber(args[1]) or -1]
    local c = tostring(args[2] or "")
    if not t then return false, "no such turtle" end
    if not TCMDS[c] then return false, "not allowed from the pocket: " .. c end
    local targs = {}
    if c == "digup" then
      if not tostring(t.gear or ""):find("pick", 1, true) then return false, t.label .. " has no pickaxe" end
      local h = t.pos and t.pos.x and MAP.get(t.pos.x, t.pos.z)
      if type(h) == "number" and t.pos.y and h >= t.pos.y then targs[1] = h + 1 end      -- the surface there
    end
    TT.send(t.id, c, targs)
    return true, (c == "digup" and "mining up to the surface" or c) .. " - " .. t.label
  elseif a == "drive" then
    -- one DRIVE step from the pocket (keys / taps); "force" = DIG ANYWAY
    local t = state.turtles[tonumber(args[1]) or -1]
    if not t then return false, "no such turtle" end
    local step = tostring(args[2] or "")
    if not DRIVE_ACTS[step] then return false, "not a drive step: " .. step end
    TT.drive(t.id, step, args[3] == "force")
    return true, "sent"
  elseif a == "forget" then
    -- a turtle that is gone (deleted by a server crash): off the list - only while offline
    local t = state.turtles[tonumber(args[1]) or -1]
    if not t then return false, "no such turtle" end
    if TT.online(t) then return false, t.label .. " is online - not forgotten" end
    local label = t.label
    TT.forget(t.id)
    return true, label .. " forgotten (its survey spots go to the others)"
  elseif a == "minedrop" then
    return MINE.drop(tonumber(args[1]))
  elseif a == "allstop" or a == "allhome" then
    local n = 0
    for id, t in pairs(state.turtles) do
      if TT.online(t) and not t.anchor then TT.send(id, a == "allstop" and "stop" or "home", {}) n = n + 1 end
    end
    return true, (a == "allstop" and "STOP" or "HOME") .. " sent to " .. n .. " turtle(s)"
  elseif a == "mine" then
    local id, c = tonumber(args[1]), tostring(args[2] or "")
    if not (id and MINE.units[id]) then return false, "no such mining turtle" end
    if c ~= "start" and c ~= "pause" and c ~= "unload" then return false, "not allowed: " .. c end
    MINE.cmd(id, c, {})
    return true, c:upper() .. " sent to the loader"
  elseif a == "corner" then
    -- a work-area corner where you stand (the pocket's GPS, else the Player Detector)
    local why = elsewhere()
    if why then return false, why end
    local x, y, z = tonumber(pos and pos.x), tonumber(pos and pos.y), tonumber(pos and pos.z)
    if not x then x, y, z = ownerPos() end
    if not x then return false, "your position is unknown (no GPS on the pocket, no Player Detector)" end
    local k = (tostring(args[1]) == "2") and "map.areaB" or "map.areaA"
    setSetting(k, { x = math.floor(x), y = math.floor(y), z = math.floor(z) })
    return true, "work-area corner " .. (k == "map.areaB" and 2 or 1) .. ": " .. math.floor(x) .. " " .. math.floor(z)
  elseif a == "wholeworld" then
    resetSetting("map.areaA")
    resetSetting("map.areaB")
    return true, "work area: the whole world again"
  elseif a == "surveyhere" then
    local why = elsewhere()
    if why then return false, why end
    local x, y, z = tonumber(pos and pos.x), tonumber(pos and pos.y), tonumber(pos and pos.z)
    if not x then x, y, z = ownerPos() end
    if not x then return false, "your position is unknown" end
    local r = math.max(16, math.min(256, tonumber(args[1]) or 64))
    local n, skipped = MAP.addSurvey(math.floor(x) - r, math.floor(z) - r, math.floor(x) + r, math.floor(z) + r,
                                     CONFIG.map.scanRadius or 8)
    if n == 0 then return true, "already mapped around you (" .. tostring(skipped) .. " spots)" end
    return true, n .. " survey spots around you queued"
  elseif a == "factoryretry" then
    if not FACTORY then return false, "no factory" end
    FACTORY.fails, FACTORY.waitUntil = 0, nil
    FACTORY.save()
    return true, "factory: " .. (FACTORY.statusLine())
  elseif a == "updateall" then
    local n = TT.forceUpdate()
    if not n then return false, "no node.lua on the base computer" end
    return true, n == 0 and ("all online turtles run " .. TT.verName(CODE.ver))
                         or (n .. " turtle(s) get " .. TT.verName(CODE.ver) .. " now")
  end
  return false, "unknown action " .. tostring(a)
end

----------------------------------------------------------------- messages from pockets
function POCKET.receive(id, m)
  if type(m) ~= "table" or type(m.t) ~= "string" then return end
  if m.t == "pairreq" then
    -- a pocket wants to pair: a code on the monitor (2 minutes)
    if POCKET.pairing and POCKET.pairing.id == id and os.clock() < POCKET.pairing.exp then return end
    local code = string.format("%06d", math.random(0, 999999))
    POCKET.pairing = { id = id, code = code, exp = os.clock() + 120, name = tostring(m.name or ("Pocket " .. id)) }
    local was = USER_ACTION
    USER_ACTION = true
    pcall(pushNote, "POCKET PAIRING", "Type  " .. code .. "  on the pocket computer (" .. POCKET.pairing.name ..
          ", #" .. id .. ") - within 2 minutes. If that is not your pocket: ignore this.", C.label, 120)
    USER_ACTION = was
    if sysLog then sysLog("Pocket #" .. id .. " asks to pair", "INFO") end
    return
  end
  if m.t == "pair" then
    local p = POCKET.pairing
    if not (p and p.id == id and os.clock() < p.exp) then return send(id, "pairfail", { why = "no pairing running - ask again" }, "") end
    if m.proof ~= sign(p.code, "pair", id) then
      p.tries = (p.tries or 0) + 1
      if p.tries >= 3 then POCKET.pairing = nil end
      return send(id, "pairfail", { why = "wrong code" }, "")
    end
    local key = randomKey()
    POCKET.pockets[id] = { key = key, name = p.name, lastN = 0, since = os.epoch("utc") }
    save()
    POCKET.pairing = nil
    send(id, "paired", { k = POCKET.scramble(key, p.code, id), base = os.getComputerLabel() or ("Base " .. os.getComputerID()) }, "")
    pcall(pushNote, "DONE", "Pocket " .. p.name .. " (#" .. id .. ") is paired - it can control the base now", C.good)
    if sysLog then sysLog("Pocket #" .. id .. " paired", "DONE") end
    return
  end
  -- everything else: a paired pocket, signed, newer than the last message
  local p = POCKET.pockets[id]
  if not p then return send(id, "unpaired", {}, "") end
  if type(m.n) ~= "number" or m.n <= (p.lastN or 0) then return end
  -- older than a minute (the numbers are the server clock): a recorded message
  -- sent again - also after a base restart, when lastN starts from the file
  if m.n / 100 < os.epoch("utc") - 60000 then return end
  if m.sig ~= sign(p.key, m.t, m.n, m.a, m.args) then return end
  p.lastN, p.seen = m.n, os.epoch("utc")
  if m.t == "req" then
    local data = POCKET.status()
    -- DRIVE mode on the pocket: the six directions of that turtle
    if m.a == "drive" and type(m.args) == "table" then data.drive = POCKET.driveView(tonumber(m.args[1])) end
    send(id, "status", { data = data, re = m.n })
  elseif m.t == "act" then
    local okA, ok, msg = pcall(POCKET.act, tostring(m.a), m.args, m.pos)
    if not okA then ok, msg = false, "error: " .. tostring(ok) end
    send(id, "res", { ok = ok and true or false, msg = tostring(msg), re = m.n })
    if sysLog then sysLog("Pocket: " .. tostring(m.a) .. " " .. table.concat(m.args or {}, " ") .. " -> " .. tostring(msg), "INFO") end
    os.queueEvent("inv_update")
  end
end

-- the monitor's warnings / errors (pushNote) go to every paired pocket
function POCKET.note(title, msg, col)
  if not next(POCKET.pockets) then return end
  local kind = noteKind and noteKind(col) or "INFO"
  if kind ~= "WARNING" and kind ~= "ERROR" and kind ~= "DONE" then return end
  if title == "POCKET PAIRING" then return end
  for id in pairs(POCKET.pockets) do
    send(id, "note", { kind = kind, title = tostring(title or ""), msg = tostring(msg or ""), at = os.epoch("utc") })
  end
end

function POCKET.unpair(id)
  if not POCKET.pockets[id] then return false end
  POCKET.pockets[id] = nil
  save()
  return true
end
