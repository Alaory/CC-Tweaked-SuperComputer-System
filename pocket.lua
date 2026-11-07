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
function refresh() sendBase("req") end
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
local C = { bg = colors.black, text = colors.white, dim = colors.lightGray, head = colors.gray, good = colors.lime,
            warn = colors.yellow, bad = colors.red, acc = colors.lightBlue, ink = colors.black, btn = colors.gray }
local KEYCOL = { busy = C.good, trouble = C.acc, still = C.warn, stuck = C.bad, nofuel = C.bad, held = C.warn,
                 idle = C.dim, offline = C.bad, missing = C.bad }
function put(x, y, s, fg, bg)
  if y < 1 or y > H then return end
  term.setCursorPos(x, y)
  term.setTextColor(fg or C.text)
  term.setBackgroundColor(bg or C.bg)
  term.write(s)
end
function cut(s, n) s = tostring(s or "") return #s > n and s:sub(1, n) or s end
-- a button: tap = action(); confirm = needs a second tap within 3 s
function button(x, y, w, label, bg, action, confirm)
  local armed = P.confirm and P.confirm.key == label and os.clock() < P.confirm.exp
  local l = armed and "TAP AGAIN" or label
  local pad = math.max(0, w - #l)
  put(x, y, string.rep(" ", math.floor(pad / 2)) .. cut(l, w) .. string.rep(" ", pad - math.floor(pad / 2)),
      C.ink, armed and C.warn or (bg or C.btn))
  P.hits[#P.hits + 1] = { x = x, y = y, w = w, fn = action, confirm = confirm and label }
end
function wrap(s, w)
  local out, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    if #line == 0 then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line line = word end
  end
  if #line > 0 then out[#out + 1] = line end
  return out
end

local TABS = { { "home", "HOME" }, { "ride", "RIDE" }, { "bots", "BOTS" }, { "mine", "MINE" }, { "msg", "MSG" }, { "more", "+" } }
function drawTabs()
  local x = 1
  for _, t in ipairs(TABS) do
    local label = t[2]
    if t[1] == "msg" and P.unread > 0 then label = "MSG" .. math.min(9, P.unread) end
    local on = P.tab == t[1]
    put(x, 1, label, on and C.ink or C.text, on and C.acc or C.head)
    P.hits[#P.hits + 1] = { x = x, y = 1, w = #label, fn = function() P.tab, P.sel = t[1], nil if t[1] == "msg" then P.unread = 0 end refresh() end }
    x = x + #label + 1
  end
end

function pageHome(d, y)
  local c = d.counts or {}
  local work = (c.busy or 0) + (c.trouble or 0)
  put(1, y, "Turtles: " .. work .. " work, " .. (c.idle or 0) .. " idle", C.text) y = y + 1
  local off = (c.offline or 0) + (c.missing or 0)
  local need = #(d.needs or {})
  put(1, y, "  " .. off .. " offline, " .. need .. " need a look", (need > 0 or off > 0) and C.warn or C.dim) y = y + 1
  for i, n in ipairs(d.needs or {}) do
    if i > 3 then break end
    put(1, y, cut(" " .. n.label .. " " .. n.lab, W), C.warn) y = y + 1
  end
  for _, m in ipairs(d.mining or {}) do
    put(1, y, cut("Mine " .. m.dim .. ": " .. m.label, W), m.running and C.good or C.dim) y = y + 1
    put(1, y, cut("  chunk " .. m.ci .. "  " .. m.rate .. "/h  " .. m.miners .. " miners", W), C.dim) y = y + 1
  end
  if d.factory then put(1, y, cut("Factory: " .. d.factory, W), C.dim) y = y + 1 end
  put(1, y, cut("Survey: " .. (d.survey and (d.survey .. "%") or "none") .. (d.auto and " (auto-map)" or ""), W), C.dim) y = y + 1
  put(1, y, cut("Area: " .. tostring(d.area), W), C.dim) y = y + 1
  if d.away then put(1, y, "Away mode is on", C.acc) y = y + 1 end
end

function pageRide(d, y)
  button(1, y, W, "TAKE ME TO THE BASE", C.good, function() act("ride", { "base" }) end) y = y + 2
  if d.back then button(1, y, W, "BACK WHERE I WAS / DIED", C.acc, function() act("ride", { "back" }) end) y = y + 2 end
  button(1, y, W, "STOP MY RIDE", C.bad, function() act("ridestop") end) y = y + 2
  for _, dr in ipairs(d.drones or {}) do
    put(1, y, cut(dr.label .. ": " .. (not dr.conn and "not connected" or (dr.busy and "busy" or "free")) ..
        (dr.bar and ("  " .. dr.bar .. " bar") or ""), W), dr.busy and C.warn or C.dim) y = y + 1
  end
  y = y + 1
  put(1, y, "Places (tap = fly there):", C.dim) y = y + 1
  local off = P.scroll.ride or 0
  for i = 1 + off, #(d.places or {}) do
    if y > H - 1 then break end
    local name = d.places[i]
    button(1, y, W, cut(name, W), C.btn, function() act("ride", { name }) end) y = y + 1
  end
end

function pageBots(d, y)
  if P.sel then
    local t
    for _, x in ipairs(d.turtles or {}) do if x.id == P.sel then t = x end end
    if not t then P.sel = nil return pageBots(d, y) end
    put(1, y, cut(t.label .. " #" .. t.id, W), C.text) y = y + 1
    put(1, y, t.lab, C.ink, KEYCOL[t.key] or C.dim) y = y + 1
    for _, l in ipairs(wrap(t.why, W)) do if y > 8 then break end put(1, y, l, C.dim) y = y + 1 end
    put(1, y, cut("fuel " .. tostring(t.fuel or "?"), W), C.dim) y = y + 1
    put(1, y, cut("task " .. tostring(t.task), W), C.dim) y = y + 2
    local hw = math.floor((W - 1) / 2)
    button(1, y, hw, "STOP", C.bad, function() act("turtle", { t.id, "stop" }) end)
    button(hw + 2, y, W - hw - 1, "HOME", C.acc, function() act("turtle", { t.id, "home" }) end) y = y + 2
    button(1, y, hw, "GPS", C.btn, function() act("turtle", { t.id, "locate" }) end)
    button(hw + 2, y, W - hw - 1, "PING", C.btn, function() act("turtle", { t.id, "ping" }) end) y = y + 2
    button(1, y, W, "< ALL TURTLES", C.head, function() P.sel = nil end)
    return
  end
  local hw = math.floor((W - 1) / 2)
  button(1, y, hw, "STOP ALL", C.bad, function() act("allstop") end, true)
  button(hw + 2, y, W - hw - 1, "ALL HOME", C.acc, function() act("allhome") end, true) y = y + 2
  local off = P.scroll.bots or 0
  local list = d.turtles or {}
  for i = 1 + off, #list do
    if y > H - 1 then break end
    local t = list[i]
    local lab = cut(t.lab, 10)
    put(1, y, cut(t.label, W - #lab - 1), C.text)
    put(W - #lab + 1, y, lab, C.ink, KEYCOL[t.key] or C.dim)
    P.hits[#P.hits + 1] = { x = 1, y = y, w = W, fn = function() P.sel = t.id end }
    y = y + 1
  end
  if #list == 0 then put(1, y, "no turtles", C.dim) end
end

function pageMine(d, y)
  if #(d.mining or {}) == 0 then put(1, y, "no mining teams", C.dim) return end
  for _, m in ipairs(d.mining) do
    put(1, y, cut(m.dim .. ": " .. m.label, W), m.running and C.good or C.text) y = y + 1
    put(1, y, cut("chunk " .. m.ci .. "  " .. m.ores .. " ores  " .. m.rate .. "/h", W), C.dim) y = y + 1
    if m.loader then
      local hw = math.floor((W - 1) / 2)
      if m.running then button(1, y, hw, "PAUSE", C.warn, function() act("mine", { m.loader, "pause" }) end)
      else button(1, y, hw, "START", C.good, function() act("mine", { m.loader, "start" }) end) end
      button(hw + 2, y, W - hw - 1, "UNLOAD", C.btn, function() act("mine", { m.loader, "unload" }) end)
      y = y + 2
    end
    y = y + 1
  end
end

function pageMsg(_, y)
  if #P.notes == 0 then put(1, y, "no messages yet", C.dim) return end
  local off = P.scroll.msg or 0
  for i = 1 + off, #P.notes do
    local n = P.notes[i]
    local col = (n.kind == "ERROR" and C.bad) or (n.kind == "WARNING" and C.warn) or C.good
    local okD, when = pcall(os.date, "%H:%M", math.floor((n.at or 0) / 1000))
    for j, l in ipairs(wrap((okD and when or "") .. " " .. tostring(n.title) .. ": " .. tostring(n.msg), W)) do
      if y > H - 1 then return end
      put(1, y, l, j == 1 and col or C.dim)
      y = y + 1
    end
  end
end

function pageMore(d, y)
  put(1, y, "Work area (corners = here):", C.dim) y = y + 1
  put(1, y, cut(tostring(d.area), W), C.text) y = y + 1
  local hw = math.floor((W - 1) / 2)
  button(1, y, hw, "SET CORNER 1", C.acc, function() act("corner", { 1 }, true) end)
  button(hw + 2, y, W - hw - 1, "SET CORNER 2", C.acc, function() act("corner", { 2 }, true) end) y = y + 2
  button(1, y, W, "WHOLE WORLD AGAIN", C.btn, function() act("wholeworld") end, true) y = y + 2
  button(1, y, W, "SURVEY 64 AROUND ME", C.good, function() act("surveyhere", { 64 }, true) end) y = y + 2
  if d.factory then
    for _, l in ipairs(wrap("Factory: " .. d.factory, W)) do if y > H - 5 then break end put(1, y, l, C.dim) y = y + 1 end
    button(1, y, W, "FACTORY: TRY AGAIN", C.btn, function() act("factoryretry") end) y = y + 2
  end
  button(1, H - 1, W, "UNPAIR THIS POCKET", C.bad, function() P.key = nil saveState() end, true)
end

local PAGES = { home = pageHome, ride = pageRide, bots = pageBots, mine = pageMine, msg = pageMsg, more = pageMore }
function draw()
  P.hits = {}
  term.setBackgroundColor(C.bg)
  term.clear()
  drawTabs()
  local d = P.data
  local age = P.got and math.floor(os.clock() - P.got) or nil
  put(1, 2, cut((P.baseName or "base") .. (age and (age > 15 and (" - no answer " .. age .. " s") or " - live") or " - waiting"), W),
      (age and age <= 15) and C.good or C.warn)
  if d then
    local ok, err = pcall(PAGES[P.tab] or pageHome, d, 3)
    if not ok then put(1, 4, cut("error: " .. tostring(err), W), C.bad) end
  elseif P.tab == "msg" then
    pageMsg(nil, 3)
  else
    put(1, 4, "asking the base ...", C.dim)
  end
  if P.toast then put(1, H, cut(P.toast, W), C.ink, C.acc) end
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
  P.scroll[P.tab] = math.max(0, (P.scroll[P.tab] or 0) + dir)
end

----------------------------------------------------------------- pairing + main loop
function pairScreen()
  term.setBackgroundColor(C.bg)
  term.clear()
  put(1, 1, "POCKET REMOTE - PAIRING", C.acc)
  local y = 3
  for _, l in ipairs(wrap("The base MONITOR now shows a 6-digit code. Type it here and press Enter:", W)) do put(1, y, l, C.text) y = y + 1 end
  if P.pairError then put(1, y + 4, cut("last try: " .. P.pairError, W), C.bad) end
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
    elseif ev == "key" and a == keys.up then scroll(-1)
    elseif ev == "key" and a == keys.down then scroll(1)
    elseif ev == "timer" and a == tick then
      tick = os.startTimer(5)
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
