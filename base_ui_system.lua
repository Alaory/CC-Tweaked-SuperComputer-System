-- base_ui_system.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   SYSTEM tab: how the base is doing (running time, when it was off, disk and
--   floppy space, turtle program, theme, auto-map), the SYSTEM LOG (system
--   things only - kept apart from the everyday EVENTS), the SETTINGS (tap a
--   value to change it; kept in settings.dat over base_config.lua) and a few
--   actions. The numbers come from sysRefresh() in the comms worker.

-- a setting stored in CONFIG (path like "turtles.idleHome"): tap = next option
local function cfgSetting(label, path, opts, default, fmt, also)
  return {
    label = label,
    get = function()
      local v = getConfigPath(path)
      if v == nil then v = default end
      return fmt and fmt(v) or tostring(v)
    end,
    next = function()
      local v = getConfigPath(path)
      if v == nil then v = default end
      local idx = 0
      for i, o in ipairs(opts) do if o == v then idx = i end end
      local nv = opts[idx % #opts + 1]
      setSetting(path, nv)
      for _, p in ipairs(also or {}) do setSetting(p, nv) end
    end,
  }
end
local function secs(v) v = tonumber(v) or 0 if v == 0 then return "never" end
  return (v >= 120 and v % 60 == 0) and (math.floor(v / 60) .. " min") or (v .. " s") end
local function onoff(v) return v and "ON" or "OFF" end

SYS_SETTINGS = {
  { label = "Auto-map (turtles survey by themselves)",
    get = function() return MAP.auto.on and "ON" or "OFF" end,
    next = function() MAP.setAuto(not MAP.auto.on) end },
  { label = "Theme (colours of the frame)",
    get = function() return (THEME_MODE == "random") and ("random: " .. tostring(THEME_NAME)) or tostring(THEME_NAME) end,
    next = function()
      local list = {}
      for _, n in ipairs(THEME_ORDER) do list[#list + 1] = n end
      list[#list + 1] = "random"
      local cur = (THEME_MODE == "random") and "random" or THEME_NAME
      local idx = 0
      for i, n in ipairs(list) do if n == cur then idx = i end end
      local nxt = list[idx % #list + 1]
      if nxt == "random" then THEME_MODE = "random" saveTheme(nil)
      else setTheme(nxt) THEME_MODE = nxt saveTheme(nxt) end
    end },
  { label = "Base messages in your chat",
    get = function()
      local sub = state.owner and state.notifySubs and state.notifySubs[tostring(state.owner):lower()]
      local l = sub and sub.level or "off"
      return (l == "important") and "warnings+errors" or (l == "all" and "everything" or "off")
    end,
    next = function()
      if not (state.owner and state.notifySubs) then return end
      local k = tostring(state.owner):lower()
      local sub = state.notifySubs[k]
      local l = sub and sub.level or "off"
      local nxt = (l == "off") and "important" or (l == "important" and "all" or "off")
      state.notifySubs[k] = (nxt ~= "off") and { name = state.owner, level = nxt } or nil
      pcall(saveNotifySubs)
    end },
  cfgSetting("Message boxes stay for", "notes.info", { 3, 5, 10, 20 }, 3, function(v) return v .. " s" end,
             { "notes.done", "notes.warning", "notes.error" }),
  cfgSetting("EVENTS list keeps", "notes.keep", { 100, 200, 500 }, 100, function(v) return v .. " messages" end),
  cfgSetting("Idle turtles go home after", "turtles.idleHome", { 0, 60, 120, 300, 600 }, 120, secs),
  cfgSetting("Turtles go refuelling below", "turtles.lowFuel", { 1000, 2000, 5000, 10000 }, 2000,
             function(v) return v .. " fuel" end),
  cfgSetting("Rescue a silent turtle after", "turtles.rescueAfter", { 90, 180, 300, 600, 1200 }, 180, secs),
  cfgSetting("Turtle program updates", "turtles.autoUpdate", { true, false }, true, onoff),
  cfgSetting("Drone travel", "drone.travel", { "teleport", "fly" }, "teleport"),
  cfgSetting("Drones fly home after a mission", "drone.returnHome", { true, false }, true, onoff),
}

local KIND_COL = { ERROR = "bad", WARNING = "warn", DONE = "good", INFO = "label" }
local function kb(b) return b and (math.floor(b / 1024) .. " KB") or "..." end

function drawSystemPage(G)
  local y0, bottom = G.y0, G.y1
  local lx = 2
  local leftW = math.floor((W - 3) * 0.5)
  local rx = lx + leftW + 1
  local rw = W - rx
  local ix, iw = lx + 2, leftW - 4
  local rix, riw = rx + 2, rw - 4
  local s = state.sys or {}
  local A = BASE_ALIVE or {}
  local now = os.epoch("utc")

  ------------------------------------------------ status
  local sh = 13
  card(lx, y0, leftW, sh, "STATUS")
  local r = y0 + 3
  kv(ix, r, iw, "Running for", fmtSpan((now - (A.since or now)) / 1000) .. "   (start #" .. tostring(A.starts or "?") .. ")")
  local off = A.offs and A.offs[1]
  if off then
    local short = tostring(off.why):find("ERROR", 1, true) and "crashed"
                  or (tostring(off.why):find("stopped", 1, true) and "you stopped it" or "unloaded / server restart")
    kv(ix, r + 1, iw, "Last time off", fmtSpan((off.to - off.from) / 1000) .. " - " .. short,
       short == "crashed" and C.bad or (short == "you stopped it" and C.text or C.warn))
  else
    kv(ix, r + 1, iw, "Last time off", "never noticed")
  end
  kv(ix, r + 2, iw, "Computer disk", (s.pcFree and s.pcCap) and (kb(s.pcFree) .. " free of " .. kb(s.pcCap)) or "...",
     (s.pcFree and s.pcFree < 65536) and C.bad or C.text)
  kv(ix, r + 3, iw, "Map", s.mapBytes and (kb(s.mapBytes) .. " in " .. tostring(s.mapFiles) .. " files") or "...")
  kv(ix, r + 4, iw, "Map floppies", s.mapFloppies and (s.mapFloppies .. " (" .. kb(s.mapFree) .. " free)") or "...",
     (s.mapFree and s.mapFree < 40960) and C.warn or C.text)
  kv(ix, r + 5, iw, "Turtle program", (CODE and TT.verName(CODE.ver) or "none") ..
     (s.turtlesAll and s.turtlesAll > 0 and ("   " .. s.turtlesUp .. "/" .. s.turtlesAll .. " up to date") or ""))
  kv(ix, r + 6, iw, "Auto-map", (MAP.auto.on and "ON" or "OFF") ..
     "   " .. math.floor(MAP.autoRadius()) .. " blocks around the base", MAP.auto.on and C.good or C.dim)
  kv(ix, r + 7, iw, "Messages", #state.noteLog .. " in EVENTS, " .. kb(s.eventsLog) .. " saved")
  kv(ix, r + 8, iw, "Theme", tostring(THEME_NAME) .. ((THEME_MODE == "random") and " (random each start)" or ""))

  ------------------------------------------------ system log (kept apart from EVENTS)
  local ly = y0 + sh + 1
  local lh = bottom - ly + 1
  card(lx, ly, leftW, lh, "SYSTEM LOG (" .. #SYSLOG .. ")")
  if #SYSLOG == 0 then
    text(ix, ly + 3, trunc("Nothing yet: base off / crashes, new turtle program, floppies ...", iw), C.dim, C.panel)
  end
  local rows = math.max(1, math.floor((lh - 4) / 2))
  local offL = scrollBar(lx, ly + 1, leftW, "sysLogOff", #SYSLOG, rows)
  for i = 1, math.min(rows, #SYSLOG - offL) do
    local e = SYSLOG[offL + i]
    local ry = ly + 3 + (i - 1) * 2
    local col = C[KIND_COL[e.kind] or "label"]
    text(ix, ry, e.when, C.dim, C.panel)
    text(ix + #e.when + 1, ry, " " .. e.kind .. " ", C.ink, col)
    local rest = iw - #e.when - #e.kind - 4
    local msg = tostring(e.msg)
    local cut = #msg
    if #msg > rest then
      cut = msg:sub(1, rest):match("^.*() ") or (rest + 1)          -- break at the last space
      if cut < rest / 2 then cut = rest + 1 end
      cut = cut - 1
    end
    text(ix + #e.when + #e.kind + 4, ry, msg:sub(1, cut), C.text, C.panel)
    if #msg > cut then
      text(ix + 2, ry + 1, trunc((msg:sub(cut + 1):gsub("^ +", "")), iw - 2), C.text, C.panel)
    end
  end

  ------------------------------------------------ settings
  local actH = 6
  local sh2 = bottom - y0 + 1 - actH - 1
  card(rx, y0, rw, sh2, "SETTINGS  (tap a value to change it)")
  local bw = math.min(24, math.floor(riw * 0.45))
  local per = 2
  local srows = math.max(1, math.floor((sh2 - 4) / per))
  local offS = scrollBar(rx, y0 + 1, rw, "sysSetOff", #SYS_SETTINGS, srows)
  for i = 1, math.min(srows, #SYS_SETTINGS - offS) do
    local def = SYS_SETTINGS[offS + i]
    local ry = y0 + 3 + (i - 1) * per
    local okG, v = pcall(def.get)
    v = okG and tostring(v) or "?"
    text(rix, ry, trunc(def.label, riw - bw - 2), C.text, C.panel)
    local on = (v == "ON")
    drawButton(rix + riw - bw, ry, bw, 1, trunc(v, bw - 2), on and C.good or C.empty, on and C.ink or C.text,
               "sysset", offS + i)
  end
  text(rix, y0 + sh2 - 2, trunc("Kept in settings.dat (base_config.lua is not changed)", riw), C.dim, C.panel)

  ------------------------------------------------ actions
  local ay = y0 + sh2 + 1
  card(rx, ay, rw, actH, "ACTIONS  (tap twice)")
  local aw = math.floor((riw - 2) / 3)
  actButton(rix, ay + 3, aw, 2, "SAVE MAP NOW", { kind = "syssave", name = "map", count = 0 }, true)
  actButton(rix + aw + 1, ay + 3, aw, 2, "UPDATE TURTLES", { kind = "sysupdate", name = "turtles", count = 0 }, true)
  actButton(rix + 2 * (aw + 1), ay + 3, riw - 2 * (aw + 1), 2, "RESTART BASE",
            { kind = "sysrestart", name = "base", count = 0 }, true)
end
