--[[
  POCKET REMOTE for the base (Advanced Pocket Computer with a Wireless or Ender
  Modem upgrade). Copy this file onto the pocket computer and run:  pocket
  It installs itself as startup.lua (starts by itself from then on).

  First time: it asks the base to pair - the base MONITOR shows a 6-digit code;
  type it here. After that, everything is by tapping:
    HOME  turtles, mining, factory, survey at a glance
    RIDE  a drone takes you to the base / a place / back where you died
    BOTS  every turtle: STOP / HOME / GPS - or all of them
    MINE  mining teams: START / PAUSE / UNLOAD
    MSG   the base's warnings and errors (they arrive as they happen)
    +     work-area corners where you stand, survey around you, factory
  An Ender Modem reaches the base from anywhere (also other dimensions); a
  wireless modem only nearby.
]]

local PROTO = "basepocket"
local TESTING = _G.POCKET_TEST                 -- (tools/tests: functions only, no main loop)
local FILE = "pocket.dat"
local W, H = term.getSize()

-- run as "pocket" (not startup.lua)? install as startup.lua
local me = shell and shell.getRunningProgram() or "startup.lua"
if not TESTING and me ~= "startup.lua" then
  if fs.exists("startup.lua") then
    if fs.exists("startup.old") then fs.delete("startup.old") end
    fs.move("startup.lua", "startup.old")
  end
  fs.copy(me, "startup.lua")
end

P = { key = nil, base = nil, baseName = nil, tab = "home", data = nil, got = nil, notes = {}, unread = 0,
      scroll = {}, sel = nil, confirm = nil, toast = nil, hits = {}, seq = 0, waitPair = false }

-- the base's signature (same as the base computer: TT.sign)
function sign(key, t, n, a, args)
  local parts = {}
  for i, v in ipairs(args or {}) do parts[i] = tostring(v) end
  local str = key .. "|" .. tostring(t) .. "|" .. tostring(n) .. "|" .. tostring(a or "") .. "|" .. table.concat(parts, ",")
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end
-- the pairing scramble (same as the base: POCKET.stream / scramble)
function unscramble(text, code, id)
  local ks, i = {}, 0
  while #ks < #text do
    i = i + 1
    local h = sign(tostring(code), "ks", tostring(id) .. ":" .. i)
    for k = 1, #h, 2 do ks[#ks + 1] = tonumber(h:sub(k, k + 1), 16) end
  end
  local o = {}
  for j = 1, #text do o[j] = string.char((text:byte(j) - ks[j]) % 256) end
  return table.concat(o)
end

function loadState()
  if fs.exists(FILE) then
    local h = fs.open(FILE, "r")
    local t = textutils.unserialize(h.readAll() or "")
    h.close()
    if type(t) == "table" then P.key, P.base, P.baseName = t.key, t.base, t.baseName end
  end
end
function saveState()
  local h = fs.open(FILE, "w")
  if h then h.write(textutils.serialize({ key = P.key, base = P.base, baseName = P.baseName })) h.close() end
end

function nextN()
  P.seq = P.seq + 1
  return os.epoch("utc") * 100 + P.seq % 100
end
function findBase()
  if P.base then return P.base end
  local id = rednet.lookup(PROTO)
  P.base = id
  return id
end
function sendBase(t, a, args, extra)
  local id = findBase()
  if not id then P.toast = "base not found - is it on?" return false end
  local m = extra or {}
  m.t, m.n, m.a, m.args = t, nextN(), a, args
  m.sig = sign(P.key or "", m.t, m.n, a, args)
  rednet.send(id, m, PROTO)
  return true
end
-- (in DRIVE mode the base also sends that turtle's six directions)
function refresh()
  if P.drive then sendBase("req", "drive", { P.drive }) else sendBase("req") end
end
-- an action; some need where you stand (the pocket's GPS)
function act(a, args, withPos)
  local extra = {}
  if withPos and gps then
    local x, y, z = gps.locate(2)
    if x then extra.pos = { x = x, y = y, z = z } end
  end
  P.toast = "sending ..."
  sendBase("act", a, args, extra)
end

-- a message from the base
function handle(id, m)
  if type(m) ~= "table" or type(m.t) ~= "string" then return end
  if m.t == "paired" and P.waitPair then
    P.key = unscramble(tostring(m.k or ""), P.code, os.getComputerID())
    P.base, P.baseName, P.waitPair, P.code = id, m.base, false, nil
    saveState()
    P.toast = "paired with " .. tostring(m.base)
    refresh()
    return
  elseif m.t == "pairfail" then
    P.waitPair, P.pairError = false, tostring(m.why)
    return
  elseif m.t == "unpaired" and id == P.base then
    P.key, P.toast = nil, "the base does not know this pocket - pair again"
    saveState()
    return
  end
  if not P.key or id ~= P.base or m.sig ~= sign(P.key, m.t, m.n) then return end
  if m.t == "status" then
    P.data, P.got = m.data, os.clock()
  elseif m.t == "res" then
    P.toast = (m.ok and "OK: " or "NO: ") .. tostring(m.msg)
    refresh()
  elseif m.t == "note" then
    table.insert(P.notes, 1, { kind = m.kind, title = m.title, msg = m.msg, at = m.at })
    while #P.notes > 40 do table.remove(P.notes) end
    if P.tab ~= "msg" then P.unread = P.unread + 1 end
    if m.kind == "ERROR" or m.kind == "WARNING" then P.toast = "! " .. tostring(m.title) .. ": " .. tostring(m.msg) end
  end
end

----------------------------------------------------------------- drawing
-- Rows 1-2 stay put (tabs, base + scroll arrows); the rest of the screen is the
-- page, which SCROLLS (^ v on row 2, or the mouse wheel / arrow keys). Pages
-- write at "page rows" (put / button / text); nothing is ever cut off - long
-- text wraps onto the next line.
local C = { bg = colors.black, text = colors.white, dim = colors.lightGray, head = colors.gray, good = colors.lime,
            warn = colors.yellow, bad = colors.red, acc = colors.lightBlue, ink = colors.black, btn = colors.gray }
local KEYCOL = { busy = C.good, trouble = C.acc, still = C.warn, stuck = C.bad, nofuel = C.bad, held = C.warn,
                 idle = C.dim, offline = C.bad, missing = C.bad }
-- list order on BOTS: what needs you first, offline last
local RANK = { stuck = 1, nofuel = 2, missing = 3, still = 4, trouble = 5, held = 6, busy = 7, idle = 8, offline = 9 }
local TOP = 3                                       -- first page row on the screen
local BOTTOM = H - 1                                -- last page row (row H = the message bar)
-- on the screen (rows 1-2 and the toast)
function at(x, y, s, fg, bg)
  if y < 1 or y > H then return end
  term.setCursorPos(x, y)
  term.setTextColor(fg or C.text)
  term.setBackgroundColor(bg or C.bg)
  term.write(s)
end
function off() return P.scroll[P.tab] or 0 end
-- on the page (scrolls)
function put(x, y, s, fg, bg)
  local sy = y - off()
  if sy < TOP or sy > BOTTOM then return end
  at(x, sy, s, fg, bg)
end
function cut(s, n) s = tostring(s or "") return #s > n and s:sub(1, n) or s end
function pad(s, w) s = cut(s, w) return s .. string.rep(" ", w - #s) end
-- a tap anywhere on a page row
function tapRow(y, fn)
  local sy = y - off()
  if sy >= TOP and sy <= BOTTOM then P.hits[#P.hits + 1] = { x = 1, y = sy, w = W, fn = fn } end
end
-- a button: tap = action(); confirm = needs a second tap within 3 s. fixed = screen row (not scrolled)
function button(x, y, w, label, bg, action, confirm, fixed)
  local sy = fixed and y or (y - off())
  if sy < (fixed and 1 or TOP) or sy > (fixed and H or BOTTOM) then return end
  local armed = P.confirm and P.confirm.key == label and os.clock() < P.confirm.exp
  local l = armed and "TAP AGAIN" or label
  local p = math.max(0, w - #l)
  at(x, sy, string.rep(" ", math.floor(p / 2)) .. cut(l, w) .. string.rep(" ", p - math.floor(p / 2)),
     C.ink, armed and C.warn or (bg or C.btn))
  P.hits[#P.hits + 1] = { x = x, y = sy, w = w, fn = action, confirm = confirm and label }
end
function wrap(s, w)
  local out, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    while #word > w do                                -- a word longer than the screen
      if #line > 0 then out[#out + 1] = line line = "" end
      out[#out + 1] = word:sub(1, w) word = word:sub(w + 1)
    end
    if #line == 0 then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line line = word end
  end
  if #line > 0 then out[#out + 1] = line end
  return out
end
-- wrapped text from column x (next lines indented the same); returns the next free row
function text(y, s, col, x, tap)
  x = x or 1
  for _, l in ipairs(wrap(s, W - x + 1)) do
    put(x, y, l, col or C.text)
    if tap then tapRow(y, tap) end
    y = y + 1
  end
  return y
end
-- a section bar; tap = open that tab
function section(y, title, tab)
  put(1, y, pad(" " .. title .. (tab and "  >" or ""), W), C.text, C.head)
  if tab then tapRow(y, function() P.tab, P.sel = tab, nil refresh() end) end
  return y + 1
end
function half() return math.floor((W - 1) / 2) end
-- "Survey2" before "Survey10"
function natural(s)
  return (tostring(s):lower():gsub("%d+", function(n) return string.rep("0", 8 - #n) .. n end))
end
function fuelText(f)
  f = tonumber(f)
  if not f then return "?" end
  if f >= 10000 then return math.floor(f / 1000) .. "k" end
  return tostring(math.floor(f))
end

local TABS = { { "home", "HOME" }, { "ride", "RIDE" }, { "bots", "BOTS" }, { "mine", "MINE" }, { "msg", "MSG" }, { "more", "+" } }
function drawTabs()
  local x = 1
  for _, t in ipairs(TABS) do
    local label = t[2]
    if t[1] == "msg" and P.unread > 0 then label = "MSG" .. math.min(9, P.unread) end
    local on = P.tab == t[1]
    at(x, 1, label, on and C.ink or C.text, on and C.acc or C.head)
    P.hits[#P.hits + 1] = { x = x, y = 1, w = #label, fn = function() P.tab, P.sel = t[1], nil if t[1] == "msg" then P.unread = 0 end refresh() end }
    x = x + #label + 1
  end
end

function pageHome(d, y)
  local c = d.counts or {}
  local work = (c.busy or 0) + (c.trouble or 0)
  local offl, miss = c.offline or 0, c.missing or 0
  y = section(y, "TURTLES", "bots")
  y = text(y, work .. " working, " .. (c.idle or 0) .. " idle" .. ((c.held or 0) > 0 and (", " .. c.held .. " stopped") or ""), C.text)
  if offl + miss > 0 then
    y = text(y, offl .. " offline" .. (miss > 0 and (", " .. miss .. " missing") or ""), C.warn)
  end
  local needs = d.needs or {}
  if #needs == 0 then y = text(y, "nothing needs a look", C.good)
  else
    for i, n in ipairs(needs) do
      if i > 4 then y = text(y, "+" .. (#needs - 4) .. " more - BOTS tab", C.warn) break end
      local id = n.id
      y = text(y, "! " .. n.label .. ": " .. n.lab, C.warn, 1, function() P.tab, P.sel = "bots", id end)
    end
  end
  if #(d.mining or {}) > 0 then
    y = section(y, "MINING", "mine")
    for _, m in ipairs(d.mining) do
      y = text(y, m.dim .. ": " .. m.label, m.running and C.good or C.text)
      if #(m.gone or {}) > 0 then y = text(y, "! " .. #m.gone .. " miner(s) gone", C.warn, 1) end
      y = text(y, "chunk " .. m.ci .. ", " .. m.miners .. " miners, " .. m.rate .. " ores/h", C.dim, 2)
    end
  end
  y = section(y, "MAP + FACTORY", "more")
  local sv
  if d.survey then sv = "Survey: " .. d.survey .. "% done" .. (d.auto and " (auto-map)" or "")
  else sv = d.auto and "Auto-map: on" or "Survey: none, auto-map off" end
  y = text(y, sv, C.dim)
  y = text(y, "Area: " .. tostring(d.area), C.dim)
  if d.factory then y = text(y, "Factory: " .. d.factory, C.dim) end
  if d.away then y = text(y, "Away mode is on", C.acc) end
  y = y + 1
  button(1, y, W, "TAKE ME TO THE BASE", C.good, function() act("ride", { "base" }) end) y = y + 2
  local hw = half()
  button(1, y, hw, "STOP ALL", C.bad, function() act("allstop") end, true)
  button(hw + 2, y, W - hw - 1, "ALL HOME", C.acc, function() act("allhome") end, true) y = y + 1
  return y
end

function pageRide(d, y)
  button(1, y, W, "TAKE ME TO THE BASE", C.good, function() act("ride", { "base" }) end) y = y + 2
  if d.back then button(1, y, W, "BACK WHERE I WAS / DIED", C.acc, function() act("ride", { "back" }) end) y = y + 2 end
  button(1, y, W, "STOP MY RIDE", C.bad, function() act("ridestop") end) y = y + 2
  if #(d.drones or {}) > 0 then
    y = section(y, "DRONES")
    for _, dr in ipairs(d.drones) do
      y = text(y, dr.label .. ": " .. (not dr.conn and "not connected" or (dr.busy and "busy" or "free")) ..
               (dr.bar and (", " .. dr.bar .. " bar") or ""), dr.busy and C.warn or C.dim)
    end
  end
  if #(d.places or {}) > 0 then
    y = section(y, "PLACES (tap = fly there)")
    for _, name in ipairs(d.places) do
      button(1, y, W, name, C.btn, function() act("ride", { name }) end) y = y + 1
    end
  end
  return y
end

function pageBots(d, y)
  local hw = half()
  if P.sel then
    local t
    for _, x in ipairs(d.turtles or {}) do if x.id == P.sel then t = x end end
    if not t then P.sel = nil return pageBots(d, y) end
    button(1, y, W, "< ALL TURTLES", C.head, function() P.sel = nil end) y = y + 2
    y = text(y, t.label .. "  #" .. t.id, C.text)
    put(1, y, " " .. t.lab .. " ", C.ink, KEYCOL[t.key] or C.dim) y = y + 1
    if t.why and t.why ~= "" then y = text(y, t.why, C.dim) end
    y = text(y, "fuel " .. tostring(t.fuel or "?"), C.dim)
    y = text(y, "task " .. tostring(t.task), C.dim) y = y + 1
    button(1, y, hw, "STOP", C.bad, function() act("turtle", { t.id, "stop" }) end)
    button(hw + 2, y, W - hw - 1, "HOME", C.acc, function() act("turtle", { t.id, "home" }) end) y = y + 2
    button(1, y, hw, "GPS", C.btn, function() act("turtle", { t.id, "locate" }) end)
    if t.key == "offline" or t.key == "missing" then
      -- gone (a server crash can delete turtles): off the list - two taps
      button(hw + 2, y, W - hw - 1, "FORGET", C.bad, function() act("forget", { t.id }) P.sel = nil end, true)
    else
      button(hw + 2, y, W - hw - 1, "PING", C.btn, function() act("turtle", { t.id, "ping" }) end)
    end
    if t.pick and t.key ~= "offline" and t.key ~= "missing" then
      y = y + 2
      button(1, y, W, "MINE UP TO THE SURFACE", C.warn, function() act("turtle", { t.id, "digup" }) end, true)
    end
    if t.key ~= "offline" and t.key ~= "missing" then
      y = y + 2
      button(1, y, W, "DRIVE IT (keys W A S D)", C.good, function() startDrive(t.id) end)
    end
    return y + 1
  end
  button(1, y, hw, "STOP ALL", C.bad, function() act("allstop") end, true)
  button(hw + 2, y, W - hw - 1, "ALL HOME", C.acc, function() act("allhome") end, true) y = y + 2
  local list = {}
  for _, t in ipairs(d.turtles or {}) do list[#list + 1] = t end
  table.sort(list, function(a, b)
    local ra, rb = RANK[a.key] or 5, RANK[b.key] or 5
    if ra ~= rb then return ra < rb end
    return natural(a.label) < natural(b.label)
  end)
  if #list == 0 then put(1, y, "no turtles", C.dim) return y + 1 end
  put(1, y, pad("name", W - 15) .. " fuel  status", C.dim) y = y + 1
  for _, t in ipairs(list) do
    local lab = cut(t.lab, 9)
    local f = fuelText(t.fuel)
    local fcol = (tonumber(t.fuel) or 0) < 1000 and C.bad or ((tonumber(t.fuel) or 0) < 5000 and C.warn or C.dim)
    put(1, y, cut(t.label, W - 16), C.text)
    put(W - 14, y, string.rep(" ", 5 - #f) .. f, fcol)
    put(W - #lab + 1, y, lab, C.ink, KEYCOL[t.key] or C.dim)
    local id = t.id
    tapRow(y, function() P.sel = id end)
    y = y + 1
  end
  return y
end

function pageMine(d, y)
  if #(d.mining or {}) == 0 then put(1, y, "no mining teams", C.dim) return y + 1 end
  local hw = half()
  for _, m in ipairs(d.mining) do
    y = section(y, string.upper(m.dim))
    y = text(y, m.label, m.running and C.good or C.text)
    y = text(y, "chunk " .. m.ci .. ", " .. m.miners .. " miners", C.dim)
    y = text(y, m.ores .. " ores, " .. m.rate .. " ores/h", C.dim)
    if m.loader then
      if m.running then button(1, y, hw, "PAUSE", C.warn, function() act("mine", { m.loader, "pause" }) end)
      else button(1, y, hw, "START", C.good, function() act("mine", { m.loader, "start" }) end) end
      button(hw + 2, y, W - hw - 1, "UNLOAD", C.btn, function() act("mine", { m.loader, "unload" }) end)
      y = y + 2
    end
    -- a miner gone 20+ min (server crash?): out of the team - two taps
    for _, g in ipairs(m.gone or {}) do
      y = text(y, g.label .. " is gone (20+ min). If it was lost in a crash, drop it so the team goes on:", C.warn)
      button(1, y, W, "DROP " .. g.label, C.bad, function() act("minedrop", { g.id }) end, true)
      y = y + 2
    end
  end
  return y
end

function pageMsg(_, y)
  if #P.notes == 0 then put(1, y, "no messages yet", C.dim) return y + 1 end
  button(1, y, W, "CLEAR MESSAGES", C.btn, function() P.notes = {} P.scroll.msg = 0 end, true) y = y + 2
  for _, n in ipairs(P.notes) do
    local col = (n.kind == "ERROR" and C.bad) or (n.kind == "WARNING" and C.warn) or C.good
    local okD, when = pcall(os.date, "%H:%M", math.floor((n.at or 0) / 1000))
    y = text(y, (okD and when or "") .. " " .. tostring(n.title), col)
    y = text(y, tostring(n.msg), C.dim, 2)
  end
  return y
end

function pageMore(d, y)
  local hw = half()
  y = section(y, "WORK AREA")
  y = text(y, tostring(d.area), C.text)
  y = text(y, "Corners = where you stand:", C.dim)
  button(1, y, hw, "CORNER 1", C.acc, function() act("corner", { 1 }, true) end)
  button(hw + 2, y, W - hw - 1, "CORNER 2", C.acc, function() act("corner", { 2 }, true) end) y = y + 2
  button(1, y, W, "WHOLE WORLD AGAIN", C.btn, function() act("wholeworld") end, true) y = y + 2
  y = section(y, "SURVEY")
  button(1, y, W, "SURVEY 64 AROUND ME", C.good, function() act("surveyhere", { 64 }, true) end) y = y + 2
  if d.factory then
    y = section(y, "TURTLE FACTORY")
    y = text(y, d.factory, C.dim)
    button(1, y, W, "FACTORY: TRY AGAIN", C.btn, function() act("factoryretry") end) y = y + 2
  end
  y = section(y, "TURTLE PROGRAM")
  button(1, y, W, "UPDATE TURTLES NOW", C.acc, function() act("updateall") end, true) y = y + 2
  y = section(y, "THIS POCKET")
  button(1, y, W, "UNPAIR THIS POCKET", C.bad, function() P.key = nil saveState() end, true)
  return y + 1
end

-- ===== DRIVE: steer one turtle like playing Minecraft =====
-- W forward, A / D turn, S back, SPACE up, SHIFT down (W / SPACE / SHIFT dig
-- first when a block is in the way). Or tap the rows. Q / BACKSPACE: back.
function startDrive(id)
  P.drive, P.driveArmed = id, nil
  P.scroll[P.tab] = 0
  refresh()
end
function driveStep(step, force)
  if not P.drive then return end
  act("drive", { P.drive, step, force and "force" or nil })
end
DRIVE_KEYS = nil
function driveKey(k)
  if not DRIVE_KEYS then
    DRIVE_KEYS = {}
    for name, step in pairs({ w = "minef", up = "minef", s = "b", down = "b", a = "l", left = "l", d = "r", right = "r",
                              space = "mineu", leftShift = "mined", rightShift = "mined", c = "around", x = "look",
                              f = "digf", r = "digu", v = "digd" }) do
      if keys[name] then DRIVE_KEYS[keys[name]] = step end
    end
  end
  if k == keys.q or k == keys.backspace then P.drive = nil refresh() return true end
  if k == keys.t then act("turtle", { P.drive, "stop" }) return true end
  if k == keys.h then act("turtle", { P.drive, "home" }) return true end
  local s = DRIVE_KEYS[k]
  if s then driveStep(s) return true end
  return false
end
function pageDrive(d, y)
  local v = d.drive
  if not v then put(1, y, "asking the base ...", C.dim) return y + 1 end
  y = text(y, "DRIVING " .. v.label .. " - facing " .. string.upper(tostring(v.facing or "?")), C.acc)
  if not v.online then y = text(y, "OFFLINE - it cannot move now", C.bad) end
  if v.waiting then y = text(y, "waiting for it ... " .. v.waiting .. " s", v.waiting > 5 and C.warn or C.dim)
  elseif v.msg then y = text(y, v.msg, v.msg:find("^OK") and C.good or C.warn) end
  y = y + 1
  for _, r in ipairs(v.rows or {}) do
    put(1, y, pad(r.dir, 7), C.dim)
    put(8, y, cut(r.what, W - 7), r.seen and C.text or C.dim)
    y = y + 1
    local step = r.act
    button(1, y, W, "[" .. r.key .. "] " .. r.does, (step == "l" or step == "r" or step == "b") and C.btn or C.acc,
           function() driveStep(step) end)
    y = y + 2
  end
  local hw = half()
  button(1, y, hw, "[X] SCAN", C.acc, function() driveStep("look") end)
  button(hw + 2, y, W - hw - 1, "[T] STOP", C.bad, function() act("turtle", { P.drive, "stop" }) end) y = y + 2
  button(1, y, hw, "[H] HOME", C.good, function() act("turtle", { P.drive, "home" }) end)
  button(hw + 2, y, W - hw - 1, "[Q] BACK", C.btn, function() P.drive = nil refresh() end) y = y + 2
  if v.anyway then
    local s = v.anyway
    button(1, y, W, "DIG ANYWAY", C.warn, function() driveStep(s, true) end, true) y = y + 2
  end
  y = text(y, "C = turn around. F / R / V = only dig ahead / up / down.", C.dim)
  return y
end

local PAGES = { home = pageHome, ride = pageRide, bots = pageBots, mine = pageMine, msg = pageMsg, more = pageMore }
P.maxOff = {}
function drawOnce()
  P.hits = {}
  term.setBackgroundColor(C.bg)
  term.clear()
  drawTabs()
  local d = P.data
  local last = TOP
  if d then
    local ok, res = pcall(P.drive and pageDrive or PAGES[P.tab] or pageHome, d, TOP)
    if not ok then at(1, TOP, cut("error: " .. tostring(res), W), C.bad)
    else last = tonumber(res) or TOP end
  elseif P.tab == "msg" then
    last = pageMsg(nil, TOP)
  else
    at(1, TOP + 1, "asking the base ...", C.dim)
  end
  P.maxOff[P.tab] = math.max(0, last - 1 - BOTTOM)
  -- row 2: the base, and ^ v when the page is longer than the screen
  local scrollable = P.maxOff[P.tab] > 0
  local age = P.got and math.floor(os.clock() - P.got) or nil
  local s = (P.baseName or "base") .. (age and (age > 15 and (" - no answer " .. age .. "s") or " - live") or " - waiting")
  at(1, 2, pad(s, W), (age and age <= 15) and C.good or C.warn)
  if scrollable then
    button(W - 6, 2, 3, off() > 0 and "^" or " ", C.btn, function() scroll(-(H - 4)) end, nil, true)
    button(W - 2, 2, 3, off() < P.maxOff[P.tab] and "v" or " ", C.btn, function() scroll(H - 4) end, nil, true)
  end
  if P.toast then at(1, H, pad(P.toast, W), C.ink, C.acc) end
end
function draw()
  drawOnce()
  local o = off()
  if o > (P.maxOff[P.tab] or 0) then P.scroll[P.tab] = P.maxOff[P.tab] drawOnce() end
end

function click(x, y)
  for i = #P.hits, 1, -1 do
    local h = P.hits[i]
    if y == h.y and x >= h.x and x < h.x + h.w then
      if h.confirm and not (P.confirm and P.confirm.key == h.confirm and os.clock() < P.confirm.exp) then
        P.confirm = { key = h.confirm, exp = os.clock() + 3 }
        return
      end
      P.confirm = nil
      h.fn()
      return
    end
  end
end
function scroll(dir)
  P.scroll[P.tab] = math.max(0, math.min(P.maxOff[P.tab] or 0, (P.scroll[P.tab] or 0) + dir))
end
----------------------------------------------------------------- pairing + main loop
function pairScreen()
  term.setBackgroundColor(C.bg)
  term.clear()
  at(1, 1, "POCKET REMOTE - PAIRING", C.acc)
  local y = 3
  for _, l in ipairs(wrap("The base MONITOR now shows a 6-digit code. Type it here and press Enter:", W)) do at(1, y, l, C.text) y = y + 1 end
  if P.pairError then at(1, y + 4, cut("last try: " .. P.pairError, W), C.bad) end
  term.setCursorPos(1, y + 1)
  term.setTextColor(C.warn)
end

function openModem()
  local m = peripheral.find and peripheral.find("modem", function(_, w) return w.isWireless and w.isWireless() end)
  if not m then return false end
  rednet.open(peripheral.getName(m))
  return true
end

function main()
  loadState()
  if not openModem() then
    print("This pocket computer has no Wireless / Ender Modem upgrade.")
    print("Craft it with a modem (pocket + modem) and run  pocket  again.")
    return
  end
  while not P.key do
    if not findBase() then
      print("Looking for the base ... (is it on, with its wireless modem?)")
      sleep(3)
    else
      P.base = nil
      sendBase("pairreq", nil, nil, { name = os.getComputerLabel() or ("Pocket " .. os.getComputerID()) })
      pairScreen()
      local code = read()
      P.code, P.waitPair, P.pairError = code, true, nil
      sendBase("pair", nil, nil, { proof = sign(code, "pair", os.getComputerID()) })
      local t0 = os.clock()
      while P.waitPair and os.clock() - t0 < 6 do
        local id, m = rednet.receive(PROTO, 1)
        if id then handle(id, m) end
      end
      if P.waitPair then P.waitPair, P.pairError = false, "no answer from the base" end
    end
  end
  refresh()
  local tick = os.startTimer(5)
  draw()
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "rednet_message" and c == PROTO then handle(a, b)
    elseif ev == "mouse_click" then click(b, c)
    elseif ev == "mouse_scroll" then scroll(a)
    elseif ev == "key" and P.drive and driveKey(a) then
      -- (DRIVE mode: the keys steer the turtle)
    elseif ev == "key" and a == keys.up then scroll(-1)
    elseif ev == "key" and a == keys.down then scroll(1)
    elseif ev == "timer" and a == tick then
      tick = os.startTimer(P.drive and 1 or 5)          -- DRIVE: what it sees, every second
      refresh()
      if P.toast and P.toastAt and os.clock() - P.toastAt > 6 then P.toast = nil end
    end
    if P.toast ~= P.lastToast then P.lastToast, P.toastAt = P.toast, os.clock() end
    if not P.key then os.reboot() end                 -- unpaired: pair again
    draw()
  end
end

if TESTING then return P end
local ok, err = pcall(main)
if not ok and tostring(err) ~= "Terminated" then
  printError("pocket: " .. tostring(err))
  print("Restarting in 5 s ...")
  sleep(5)
  os.reboot()
end
