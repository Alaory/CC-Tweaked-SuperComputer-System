-- base_ui_system.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   SYSTEM tab: how the base is doing (running time, when it was off, disk and
--   floppy space, turtle program, theme, auto-map), the SYSTEM LOG (system
--   things only - kept apart from the everyday EVENTS), the times the base
--   was off, and a few actions. Settings have their own page
--   (base_ui_settings.lua). The numbers come from sysRefresh() (comms worker).

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
  local sh = 14
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
  kv(ix, r + 9, iw, "Storage helpers", (s.helpers and s.helpers > 0) and (s.helpers .. " (" .. kb(s.helperFree) .. " free)")
     or "none (store.lua on a computer on the cable)", (s.helpers and s.helpers > 0) and C.text or C.dim)

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

  ------------------------------------------------ times the base was off
  local actH = 9
  local oh = bottom - y0 + 1 - actH - 1
  card(rx, y0, rw, oh, "TIMES THE BASE WAS OFF")
  local offs = A.offs or {}
  if #offs == 0 then
    text(rix, y0 + 3, trunc("None noticed yet. (A gap of more than 90 s counts.)", riw), C.dim, C.panel)
  end
  for i = 1, math.min(#offs, math.floor((oh - 4) / 2)) do
    local o = offs[i]
    local ry = y0 + 3 + (i - 1) * 2
    local okW, w = pcall(os.date, "%d.%m %H:%M", math.floor(o.from / 1000))
    local why = tostring(o.why)
    local col = why:find("ERROR", 1, true) and C.bad or (why:find("stopped", 1, true) and C.dim or C.warn)
    text(rix, ry, (okW and w or "?") .. "   off for " .. fmtSpan((o.to - o.from) / 1000), C.text, C.panel)
    text(rix + 2, ry + 1, trunc(why, riw - 2), col, C.panel)
  end

  ------------------------------------------------ actions
  local ay = y0 + oh + 1
  card(rx, ay, rw, actH, "ACTIONS  (tap twice)")
  local aw = math.floor((riw - 2) / 3)
  actButton(rix, ay + 3, aw, 2, "SAVE MAP NOW", { kind = "syssave", name = "map", count = 0 }, true)
  actButton(rix + aw + 1, ay + 3, aw, 2, "UPDATE TURTLES", { kind = "sysupdate", name = "turtles", count = 0 }, true)
  actButton(rix + 2 * (aw + 1), ay + 3, riw - 2 * (aw + 1), 2, "RESTART BASE",
            { kind = "sysrestart", name = "base", count = 0 }, true)
  drawButton(rix, ay + 6, riw, 2, "SETTINGS  >", C.accent, C.ink, "page", "settings")
end
