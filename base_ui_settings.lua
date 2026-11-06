-- base_ui_settings.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   SETTINGS page (SYSTEM group): every setting you may want to change while
--   playing, by TAPPING only - no keyboard:
--     numbers   [ - ] value [ + ]          choices / ON-OFF   tap the value
--     places    USE MY POSITION / BLOCK UNDER ME (stand there, tap twice)
--     RESET     back to the value in base_config.lua
--   Changes are kept in settings.dat (setSetting, base_devices.lua) and applied
--   over base_config.lua at every start; base_config.lua itself is not changed.

local function onoff(v) return v and "ON" or "OFF" end
local function secs(v)
  v = tonumber(v) or 0
  if v == 0 then return "never" end
  if v >= 120 and v % 60 == 0 then return math.floor(v / 60) .. " min" end
  return v .. " s"
end
local function plain(v) return tostring(v) end
local function pos(v)
  if type(v) ~= "table" or not v.x then return "not set" end
  return v.x .. " " .. v.y .. " " .. v.z
end

-- kinds: num (min, max, step), cycle (opts), bool, pos (mode = "feet" / "under"),
-- custom (get, next). path = where in CONFIG; default = when not set at all.
local function num(path, label, hint, default, min, max, step, fmt, also)
  return { kind = "num", path = path, label = label, hint = hint, default = default,
           min = min, max = max, step = step, fmt = fmt or plain, also = also }
end
local function cyc(path, label, hint, default, opts, fmt)
  return { kind = "cycle", path = path, label = label, hint = hint, default = default, opts = opts, fmt = fmt or plain }
end
local function bool(path, label, hint, default)
  return { kind = "bool", path = path, label = label, hint = hint, default = default, fmt = onoff }
end
local function place(path, label, hint, mode)
  return { kind = "pos", path = path, label = label, hint = hint, mode = mode, fmt = pos }
end

SETTING_GROUPS = {
  { name = "GENERAL", list = {
    { kind = "custom", label = "Theme", hint = "colours of the frame (the map always keeps its colours)",
      get = function() return (THEME_MODE == "random") and ("random: " .. tostring(THEME_NAME)) or tostring(THEME_NAME) end,
      next = function(dir)
        local list = {}
        for _, n in ipairs(THEME_ORDER) do list[#list + 1] = n end
        list[#list + 1] = "random"
        local cur = (THEME_MODE == "random") and "random" or THEME_NAME
        local idx = 1
        for i, n in ipairs(list) do if n == cur then idx = i end end
        local nxt = list[(idx - 1 + (dir or 1)) % #list + 1]
        if nxt == "random" then THEME_MODE = "random" saveTheme(nil)
        else setTheme(nxt) THEME_MODE = nxt saveTheme(nxt) end
      end },
    cyc("style", "Look", "flat = solid blocks, rounded = rounded corners and thin bars", "flat", { "flat", "rounded" }),
    cyc("notes.show", "Message boxes for", "which messages get a box (all are in EVENTS anyway; your taps always)",
        "important", { "important", "errors", "all", "none" },
        function(v) return ({ important = "warnings+errors", errors = "errors only", all = "everything", none = "none" })[v] or tostring(v) end),
    cyc("notes.where", "Message boxes at", "where the boxes appear on the monitor", "bottom", { "bottom", "top" }),
    num("notes.info", "Message boxes stay for", "seconds a message box stays in the corner", 3, 1, 60, 1,
        function(v) return v .. " s" end, { "notes.done", "notes.warning", "notes.error" }),
    num("notes.keep", "EVENTS list keeps", "messages in the EVENTS list (all are saved in events.log anyway)",
        100, 50, 1000, 50, function(v) return v .. " messages" end),
    { kind = "custom", label = "Base messages in your chat", hint = "the monitor's messages, privately (= $drone notify)",
      get = function()
        local sub = state.owner and state.notifySubs and state.notifySubs[tostring(state.owner):lower()]
        local l = sub and sub.level or "off"
        return (l == "important") and "warnings+errors" or (l == "all" and "everything" or "off")
      end,
      next = function(dir)
        if not (state.owner and state.notifySubs) then return end
        local k = tostring(state.owner):lower()
        local order = { "off", "important", "all" }
        local sub = state.notifySubs[k]
        local idx = 1
        for i, o in ipairs(order) do if o == (sub and sub.level or "off") then idx = i end end
        local nxt = order[(idx - 1 + (dir or 1)) % #order + 1]
        state.notifySubs[k] = (nxt ~= "off") and { name = state.owner, level = nxt } or nil
        pcall(saveNotifySubs)
      end },
  } },
  { name = "TURTLES", list = {
    place("turtles.fuelChest", "Fuel chest", "turtles low on fuel refuel here, one at a time - stand ON the chest", "under"),
    num("turtles.lowFuel", "Refuel below", "a turtle goes refuelling below this much fuel", 2000, 500, 50000, 500,
        function(v) return v .. " fuel" end),
    num("turtles.idleHome", "Idle turtles go home after", "a turtle with nothing to do goes home (0 = never)",
        120, 0, 3600, 30, secs),
    num("turtles.rescueAfter", "Rescue a silent turtle after", "the RESCUER goes to wake it up", 180, 60, 3600, 30, secs),
    num("turtles.avoidRange", "Keep away from players within", "a turtle stops and goes home when one comes this close (0 = off)",
        100, 0, 300, 25, function(v) return (tonumber(v) or 0) == 0 and "off" or (v .. " blocks") end),
    cyc("turtles.avoidWho", "Players to avoid", "strangers = everyone but you and your allow list", "strangers",
        { "strangers", "everyone" }, function(v) return v == "everyone" and "everyone but me" or "strangers" end),
    num("turtles.offlineAfter", "Offline after", "no report for this long = offline", 45, 15, 300, 5, secs),
    bool("turtles.autoUpdate", "Turtle program updates", "new node.lua goes to the turtles by itself", true),
    { kind = "custom", label = "Turtles dig through natural blocks",
      hint = "with a pickaxe they carry: stone, dirt, sand, leaves ... never builds, never near home. The rescuer always does",
      get = function() return CONFIG.turtles.dig and "ON" or "OFF" end,
      next = function() TT.setDig(not CONFIG.turtles.dig) end },
  } },
  { name = "MAP", list = {
    { kind = "custom", label = "Auto-map", hint = "turtles keep surveying from the base outward, by themselves",
      get = function() return MAP.auto.on and "ON" or "OFF" end,
      next = function() MAP.setAuto(not MAP.auto.on) end },
    num("map.surveyMinFuel", "Survey needs at least", "a turtle gets survey spots only with this much fuel",
        500, 100, 10000, 100, function(v) return v .. " fuel" end),
    num("map.maxChunks", "Detail kept for", "newest chunks with every block column (older: overview only)",
        300, 50, 2000, 50, function(v) return v .. " chunks" end),
    num("map.computerKB", "Map on the computer, at most", "when no floppy has room (the computer has 1 MB)",
        200, 50, 600, 25, function(v) return v .. " KB" end),
    num("map.border", "World border", "nothing is surveyed beyond +-this", 20000, 1000, 60000, 1000, plain),
  } },
  { name = "DRONES", list = {
    place("drone.home", "Base (drop-off point)", "where riders are dropped off - stand there", "feet"),
    cyc("drone.travel", "Travel", "teleport = no paths needed (best underground), fly = costs no air",
        "teleport", { "teleport", "fly" }),
    bool("drone.returnHome", "Fly home after a mission", "park on the Charging Station after every mission", true),
    num("drone.minPressure", "Missions need at least", "air (bar) to start a mission", 2, 0.5, 20, 0.5,
        function(v) return v .. " bar" end),
    num("drone.airReserve", "Keep in reserve", "never teleport below this much air - fly instead", 1.5, 0, 10, 0.5,
        function(v) return v .. " bar" end),
    num("drone.hopLength", "Long trips: hops of", "far away and not loaded: teleport hops this long", 160, 32, 320, 16,
        function(v) return v .. " blocks" end),
    num("drone.pickupTries", "Pickup tries", "tries to pick a player up before giving up", 4, 1, 10, 1, plain),
    bool("drone.liftCheck", "Lift after a pickup", "ON: lift and check the passenger came along (slower)", false),
  } },
  { name = "CHAT", list = {
    bool("chat.askOwner", "Ask me for strangers' rides", "players not on the allow list need your OK", true),
    num("chat.approveTime", "A request waits", "seconds a ride request stays open", 60, 10, 600, 10, secs),
    num("chat.cooldown", "Between rides (others)", "seconds between rides for players other than you", 120, 0, 1800, 30, secs),
    num("chat.maxDistance", "Pickups up to", "refuse pickups further than this from base (0 = no limit)", 0, 0, 40000, 500,
        function(v) return (tonumber(v) or 0) == 0 and "no limit" or (v .. " blocks") end),
    bool("chat.othersToPlayers", "Others may fly to players", "other players may ride TO a player", true),
    bool("chat.notifyOwner", "Tell me about others' rides", "a message whenever someone else gets a ride", true),
  } },
  { name = "MINING", list = {
    num("mining.dumpEvery", "Miner unloads every", "it teleports to the unload station this often", 600, 120, 3600, 60, secs),
    num("mining.rowLength", "Chunks per row", "a row goes this far forward, the next row is to its right", 16, 2, 64, 2,
        function(v) return v .. " chunks (" .. (v * 16) .. " blocks)" end),
    num("mining.noMine", "No mining near the station", "no ores taken this close to the unload station",
        64, 0, 256, 16, function(v) return v .. " blocks" end),
  } },
  { name = "ME", list = {
    num("me.refresh", "Read the network every", "seconds between ME network reads", 3, 1, 60, 1, secs),
    num("me.chunk", "Items per transfer step", "most items moved in one step", 576, 64, 2304, 64, plain),
  } },
}

-- the value shown for a setting
local function valueOf(def)
  if def.kind == "custom" then local ok, v = pcall(def.get) return ok and tostring(v) or "?" end
  local v = getConfigPath(def.path)
  if v == nil then v = def.default end
  if def.kind == "num" and v == nil then v = def.min end
  return def.fmt(v)
end

-- change a setting: dir = -1 / +1 (numbers, choices), or a toggle
function settingStep(def, dir)
  if def.kind == "custom" then return def.next(dir) end
  local v = getConfigPath(def.path)
  if v == nil then v = def.default end
  local nv
  if def.kind == "num" then
    nv = math.max(def.min, math.min(def.max, (tonumber(v) or def.min) + dir * def.step))
    nv = math.floor(nv / def.step + 0.5) * def.step                -- on the step grid
  elseif def.kind == "bool" then
    nv = not v
  elseif def.kind == "cycle" then
    local idx = 1
    for i, o in ipairs(def.opts) do if o == v then idx = i end end
    nv = def.opts[(idx - 1 + dir) % #def.opts + 1]
  else
    return
  end
  setSetting(def.path, nv)
  for _, p in ipairs(def.also or {}) do setSetting(p, nv) end
end
function settingReset(def)
  if not def.path then return end
  resetSetting(def.path)
  for _, p in ipairs(def.also or {}) do resetSetting(p) end
end
-- a place from where you stand (the Player Detector)
function settingHere(def)
  local me
  for _, e in ipairs(state.players or {}) do
    if e.name == state.owner and e.p and e.p.x then me = e.p end
  end
  if not me then return false, "your position is unknown (Player Detector, overworld)" end
  local x, y, z = math.floor(me.x), math.floor(me.y), math.floor(me.z)
  if def.mode == "under" then y = y - 1 end
  setSetting(def.path, { x = x, y = y, z = z })
  return true, def.label .. ": " .. x .. " " .. y .. " " .. z
end

function settingAt(gi, i)
  local g = SETTING_GROUPS[gi]
  return g and g.list[i]
end

function drawSettingsPage(G)
  local y0, bottom = G.y0, G.y1
  state.setGroup = math.max(1, math.min(#SETTING_GROUPS, state.setGroup or 1))
  ------------------------------------------------ groups (left)
  local lw = 20
  card(2, y0, lw, bottom - y0 + 1, "GROUPS")
  for i, g in ipairs(SETTING_GROUPS) do
    local on = state.setGroup == i
    drawButton(4, y0 + 1 + i * 3 - 1, lw - 4, 2, g.name, on and C.accent or C.empty, on and C.ink or C.text,
               "setgroup", i)
  end
  text(4, bottom - 3, trunc("Saved in", lw - 4), C.dim, C.panel)
  text(4, bottom - 2, trunc("settings.dat", lw - 4), C.dim, C.panel)

  ------------------------------------------------ the settings of the group
  local rx = 2 + lw + 1
  local rw = W - rx
  local rix, riw = rx + 2, rw - 4
  local g = SETTING_GROUPS[state.setGroup]
  card(rx, y0, rw, bottom - y0 + 1, g.name)
  local per = 3
  local rows = math.max(1, math.floor((bottom - y0 - 3) / per))
  local off = scrollBar(rx, y0 + 1, rw, "setOff" .. state.setGroup, #g.list, rows)
  -- controls on the right: [RESET] [ - ] [   value   ] [ + ]
  local vw = math.min(22, math.floor(riw * 0.3))
  local ctlW = 8 + 1 + 5 + 1 + vw + 1 + 5
  for i = 1, math.min(rows, #g.list - off) do
    local idx = off + i
    local def = g.list[idx]
    local ry = y0 + 3 + (i - 1) * per
    local labW = riw - ctlW - 2
    text(rix, ry, trunc(def.label, labW), C.text, C.panel)
    text(rix, ry + 1, trunc(def.hint or "", labW), C.dim, C.panel)
    local v = valueOf(def)
    local cx = rix + riw - ctlW
    -- RESET only when it differs from base_config.lua
    local changed = def.path and isChanged(def.path)
    if changed then drawButton(cx, ry, 8, 2, "RESET", C.empty, C.warn, "setreset", idx) end
    local bx = cx + 9
    if def.kind == "pos" then
      local w2 = ctlW - 9
      text(bx, ry, trunc(v, w2), v == "not set" and C.warn or C.text, C.panel)
      actButton(bx, ry + 1, w2, 1, def.mode == "under" and "BLOCK UNDER ME" or "USE MY POSITION",
                { kind = "setpos", name = tostring(idx), count = 0 }, true)
    else
      local on = (v == "ON")
      local step = (def.kind == "num")
      -- big enough to hit with a click: 2 rows high
      drawButton(bx, ry, 5, 2, step and "-" or "<", C.empty, C.text, "setdec", idx)
      drawButton(bx + 6, ry, vw, 2, trunc(v, vw - 2), on and C.good or (changed and C.label or C.head),
                 on and C.ink or (changed and C.ink or C.text), "setinc", idx)
      drawButton(bx + 7 + vw, ry, 5, 2, step and "+" or ">", C.empty, C.text, "setinc", idx)
    end
  end
end
