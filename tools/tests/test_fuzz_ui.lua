-- EVERY BUTTON ON EVERY PAGE (the owner: "go over every feature and check them"): each page at several monitor
-- sizes, in the normal preview world and in a messy one (turtles offline / stuck / missing, a mining team with a
-- lost miner, a survey, a drone build, AE2 offline ...): draw it, tap EVERY tap area (twice - a 2-tap button
-- asks first) and run whatever the tap queued (runAction, as the action worker does). In the game the input /
-- action workers pcall these: an error there = a button that silently does nothing. Every error counts here.
local PAGES = { "home", "inventory", "storage", "curios", "players", "env", "access", "me", "mesys", "drone", "work",
                "turtles", "drive", "map", "mining", "system", "events", "settings" }
local SIZES = { { 121, 50 }, { 164, 81 }, { 200, 100 }, { 100, 40 } }
local errors, seen = {}, {}
local actionsRun, kinds, actTaps = 0, {}, 0
local function note(where, err)
  local k = where .. " | " .. tostring(err):gsub("%d+", "#")
  if not seen[k] then seen[k] = true errors[#errors + 1] = where .. ": " .. tostring(err) end
end
-- never really restart / stop / sleep in a test
os.reboot = function() end
os.shutdown = function() end
-- (an endless loop is an error too)
local function guarded(f, ...)
  local args = table.pack(...)
  debug.sethook(function() error("RUNS TOO LONG (endless loop?)") end, "", 5e7)
  local ok, err = pcall(f, table.unpack(args, 1, args.n))
  debug.sethook()
  return ok, err
end
local function drain(where)
  local n = 0
  while #state.actionQueue > 0 and n < 20 do
    n = n + 1
    local a = table.remove(state.actionQueue, 1)
    actionsRun = actionsRun + 1
    kinds[tostring(a and a.kind)] = true
    USER_ACTION = true                               -- (exactly as the action worker runs it)
    local ok, err = guarded(runAction, a)
    USER_ACTION = false
    state.busy = false
    if not ok then note(where .. " -> action " .. tostring(a and a.kind), err) end
  end
  state.actionQueue, state.busy = {}, false
end
local function tapAll(pg, label)
  state.page = pg
  local ok, err = guarded(draw)
  if not ok then note(label .. " " .. pg .. " draw", err) return 0 end
  -- one of each kind + value (long lists: the first few of each kind); after every tap the page is scanned
  -- again - a selected item / turtle / drone shows NEW buttons (GET x64, STOP, FLY TO ...)
  local todo, perKind, n = {}, {}, 0
  local function scan()
    for _, h in ipairs(hits) do
      local v = h[6]
      local vk = type(v) == "table" and (tostring(v.kind) .. ":" .. tostring(v.name)) or tostring(v)
      local group = h[5] .. (type(v) == "table" and (":" .. tostring(v.kind)) or "")
      local key = tostring(h[5]) .. "=" .. vk
      if not todo[key] then
        perKind[group] = (perKind[group] or 0) + 1
        if perKind[group] <= 4 then todo[key] = { h[1], h[2], h[3], h[4], h[5], h[6], kind = h[5], val = v } todo[#todo + 1] = key end
      end
    end
  end
  scan()
  local i = 0
  while i < #todo and n < 160 do
    i = i + 1
    local key = todo[i]
    local h = todo[key]
    state.page = pg
    guarded(draw)                                    -- (fresh tap areas, as on the real screen)
    -- (find the same button again on this screen - a list may have moved)
    local hx
    for _, hh in ipairs(hits) do
      local v = hh[6]
      local vk = type(v) == "table" and (tostring(v.kind) .. ":" .. tostring(v.name)) or tostring(v)
      if tostring(hh[5]) .. "=" .. vk == key then hx = hh break end
    end
    if hx then
      local x, y = math.floor((hx[1] + hx[3]) / 2), math.floor((hx[2] + hx[4]) / 2)
      if hx[5] == "act" then actTaps = actTaps + 1 end
      for tap = 1, 2 do
        USER_ACTION = true                           -- (the input worker sets it around handleTouch)
        local okT, errT = guarded(handleTouch, x, y)
        USER_ACTION = false
        if not okT then note(label .. " " .. pg .. " tap " .. key, errT) break end
        drain(label .. " " .. pg .. " tap " .. key)
        if state.page ~= pg then break end             -- (it opened another page)
        guarded(draw)
      end
      n = n + 1
      local okD, errD = guarded(draw)
      if not okD then note(label .. " " .. state.page .. " draw after tap " .. key, errD)
      elseif state.page == pg then scan() end
      state.pending, state.popup = nil, nil
    end
  end
  return n
end

local function messyWorld()
  local HOME = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
  local now = os.epoch("utc")
  local function T(id, f)
    local t = { id = id, label = "T" .. id, log = { { t = "12:00", msg = "hello" } }, lastN = 0, fuel = 9000,
                pos = { x = HOME.x + id, y = 70, z = HOME.z }, home = { x = HOME.x + id, y = 70, z = HOME.z },
                task = "idle", lastSeen = os.clock(), seenEpoch = now, gear = "modem, scanner, pickaxe" }
    for k, v in pairs(f or {}) do t[k] = v end
    state.turtles[id] = t
  end
  T(41, { task = "survey: spot 3/9" }) T(42, { stuck = "blocked", stuckPos = { x = HOME.x + 42, y = 70, z = HOME.z } })
  T(43, { held = true }) T(44, { fuel = 0 }) T(45, { lastSeen = os.clock() - 99999, seenEpoch = now - 9000000 })
  T(46, { missing = now }) T(47, { rescuerRole = true }) T(48, { home = nil, pos = nil }) T(49, { dups = { { ses = "x", at = os.clock() } } })
  T(50, { view = { cells = { [(HOME.x + 51) .. ",70," .. HOME.z] = "minecraft:stone" } }, label = "Drive me" })
  MINE.units = MINE.units or {}
  MINE.units[90] = { id = 90, role = "loader", dim = "overworld", label = "L", running = true, team = { 91, 92 }, ci = 2,
                     lastSeen = os.clock(), seenEpoch = now, log = {}, queue = {}, fuel = 50000 }
  MINE.units[91] = { id = 91, role = "miner", dim = "overworld", label = "M1", leader = 90, idx = 1, running = true,
                     lastSeen = os.clock() - 99999, seenEpoch = now - 9000000, log = {}, queue = {} }
  MAP.queueSurvey(HOME.x - 200, HOME.z - 200, HOME.x + 200, HOME.z + 200, 8, nil)
  state.diskLow = "DISK ALMOST FULL: test"
  if type(state.me) == "table" then state.me.online = false end
  state.players = state.players or {}
  state.players[#state.players + 1] = { name = "Stranger", p = { x = HOME.x + 30, y = 70, z = HOME.z }, dim = "minecraft:overworld",
                                        health = 3, maxHealth = 20 }
  if DW then   -- (a paused build, shaped as DW.start makes it)
    DW.job = DW.job or { name = "house", x = HOME.x, y = 70, z = HOME.z, rot = 90, clear = true, done = "0101", dug = "11",
                         placed = 2, skippedN = 1, startedE = now, fails = 2, paused = "waiting for air",
                         plan = { place = {}, air = {}, skipped = {}, top = 80 } }
  end
end

dofile(SRC_DIR .. "/tools/tests/lib/fake_ae2.lua")         -- (an AE2 network: the preview world has none)

local W0, H0 = W, H
local total = 0
-- (every size once: two with the normal world, two with the messy one - all four in both took 3 minutes)
for pass = 1, 2 do
  if pass == 2 then pcall(messyWorld) end
  for si, sz in ipairs(SIZES) do
    if (si % 2 == 1) == (pass == 1) then
    W, H = sz[1], sz[2]
    win = window.create(mon, 1, 1, W, H, false)
    applyPalette(win)
    state.mapImage = nil
    for _, pg in ipairs(PAGES) do
      total = total + tapAll(pg, (pass == 1 and "world" or "messy") .. " " .. W .. "x" .. H)
    end
    end
  end
end
W, H = W0, H0
win = window.create(mon, 1, 1, W, H, false)
applyPalette(win)
CHECK(#errors == 0, #errors .. " error(s) in " .. total .. " taps:\n  " .. table.concat(errors, "\n  ", 1, math.min(#errors, 40)))
CHECK(total > 300, "taps done: " .. total)
local nk = 0
for _ in pairs(kinds) do nk = nk + 1 end
CHECK(actTaps > 80 and actionsRun >= 4 and nk >= 2, "actions really run: " .. actTaps .. " action buttons, " .. actionsRun ..
      " queued transfers run (" .. nk .. " kinds)")
