-- Minimal ComputerCraft stand-in: enough to load the base program and draw.
local SRC = SRC_DIR
colors = {}
local names = {"white","orange","magenta","lightBlue","yellow","lime","pink","gray","lightGray","cyan","purple","blue","brown","green","red","black"}
for i, n in ipairs(names) do colors[n] = 2 ^ (i - 1) end
for k, v in pairs(colors) do colors[k] = math.floor(v) end
colours = colors
local function hexOf(c) local i = 0 while c > 1 do c = c // 2 i = i + 1 end return string.format("%x", i) end
CLOCK = 100
local NATIVE = {}
term = { nativePaletteColor = function(c) return 0.5, 0.5, 0.5 end }

-- a text buffer: monitor or window
local function newBuffer(w, h)
  local B = { w = w, h = h, cx = 1, cy = 1, fg = colors.white, bg = colors.black, rows = {}, pal = {} }
  local function blank(y) B.rows[y] = { t = (" "):rep(w), f = ("0"):rep(w), b = ("f"):rep(w) } end
  for y = 1, h do blank(y) end
  local function put(s, f, b)
    local y = B.cy
    if y >= 1 and y <= h then
      local r = B.rows[y]
      for i = 1, #s do
        local x = B.cx + i - 1
        if x >= 1 and x <= w then
          r.t = r.t:sub(1, x - 1) .. s:sub(i, i) .. r.t:sub(x + 1)
          r.f = r.f:sub(1, x - 1) .. f:sub(i, i) .. r.f:sub(x + 1)
          r.b = r.b:sub(1, x - 1) .. b:sub(i, i) .. r.b:sub(x + 1)
        end
      end
    end
    B.cx = B.cx + #s
  end
  local o = {}
  function o.write(s) s = tostring(s) put(s, hexOf(B.fg):rep(#s), hexOf(B.bg):rep(#s)) end
  function o.blit(t, f, b) put(t, f, b) end
  function o.setCursorPos(x, y) B.cx, B.cy = math.floor(x), math.floor(y) end
  function o.getCursorPos() return B.cx, B.cy end
  function o.setTextColor(c) B.fg = c end
  function o.setTextColour(c) B.fg = c end
  function o.setBackgroundColor(c) B.bg = c end
  function o.setBackgroundColour(c) B.bg = c end
  function o.getBackgroundColor() return B.bg end
  function o.getTextColor() return B.fg end
  function o.clear() local hb = hexOf(B.bg) for y = 1, h do B.rows[y] = { t = (" "):rep(w), f = ("0"):rep(w), b = hb:rep(w) } end end
  function o.clearLine() local hb = hexOf(B.bg) B.rows[B.cy] = { t = (" "):rep(w), f = ("0"):rep(w), b = hb:rep(w) } end
  function o.getSize() return w, h end
  function o.getLine(y) local r = B.rows[y] return r.t, r.f, r.b end
  function o.setPaletteColor(c, rgb) B.pal[c] = rgb end
  o.setPaletteColour = o.setPaletteColor
  function o.getPaletteColor(c) return 0.5, 0.5, 0.5 end
  function o.setVisible() end
  function o.isColor() return true end
  o.isColour = o.isColor
  function o.setTextScale() end
  function o.setCursorBlink() end
  function o.redraw() end
  function o.scroll() end
  o._buf = B
  return o
end
-- monitor size in characters: env MONW / MONH (default 164 x 81)
MON_W = tonumber(os.getenv("MONW") or "") or 164
MON_H = tonumber(os.getenv("MONH") or "") or 81
MONITOR = newBuffer(MON_W, MON_H)
window = { create = function(parent, x, y, w, h) return newBuffer(w, h) end }

-- files: in memory
FILES = {}
fs = {}
function fs.exists(p) return FILES[p] ~= nil or (p ~= "" and io.open(SRC .. "/" .. p, "r") ~= nil) end
function fs.open(p, mode)
  if mode == "r" then
    local text = FILES[p]
    if not text then local f = io.open(SRC .. "/" .. p, "r") if not f then return nil end text = f:read("a") f:close() end
    local pos = 1
    return { readAll = function() local r = text:sub(pos) pos = #text + 1 return r end,
             readLine = function() if pos > #text then return nil end local e = text:find("\n", pos, true) or (#text + 1)
               local l = text:sub(pos, e - 1) pos = e + 1 return l end,
             close = function() end }
  end
  local buf = {}
  return { write = function(s) buf[#buf + 1] = tostring(s) end, writeLine = function(s) buf[#buf + 1] = tostring(s) .. "\n" end,
           flush = function() end, close = function() FILES[p] = table.concat(buf) end }
end
function fs.delete(p) FILES[p] = nil end
function fs.move(a, b) FILES[b] = FILES[a] FILES[a] = nil end
function fs.copy(a, b) FILES[b] = FILES[a] end
function fs.combine(a, b) if a == "" then return b end return a .. "/" .. b end
function fs.getDir(p) return p:match("^(.*)/[^/]*$") or "" end
function fs.getName(p) return p:match("([^/]*)$") end
function fs.getFreeSpace() return 500000 end
function fs.getSize(p) return #(FILES[p] or "") end
function fs.list() return {} end
function fs.isDir() return false end
function fs.attributes(p) return { size = fs.getSize(p), modified = 0 } end

textutils = {}
local function ser(v, ind)
  local t = type(v)
  if t == "table" then
    local out = {}
    for k, x in pairs(v) do out[#out + 1] = "[" .. ser(k) .. "]=" .. ser(x) end
    return "{" .. table.concat(out, ",") .. "}"
  elseif t == "string" then return string.format("%q", v)
  else return tostring(v) end
end
textutils.serialize = ser
textutils.serialise = ser
function textutils.unserialize(s) local f = load("return " .. tostring(s), "u", "t", {}) if not f then return nil end local ok, r = pcall(f) return ok and r or nil end
textutils.unserialise = textutils.unserialize
function textutils.formatTime(t, h24) return string.format("%d:%02d", math.floor(t), math.floor((t % 1) * 60)) end
function textutils.serializeJSON(v) return ser(v) end

local realOs = os
os = { clock = function() return CLOCK end, time = function() return 14.5 end,
       epoch = function() return 1761990000000 + CLOCK * 1000 end,
       date = function(f) return (f == "%H:%M") and "14:30" or "01.11 14:30" end, queueEvent = function() end,
       startTimer = function() return 1 end, cancelTimer = function() end,
       getComputerID = function() return 1 end, getComputerLabel = function() return "base" end,
       setComputerLabel = function() end, pullEvent = function() error("no events") end,
       pullEventRaw = function() error("no events") end }
sleep = function() end
parallel = { waitForAll = function(...) for _, f in ipairs({ ... }) do f() end end,
             waitForAny = function(f) f() end }
rednet = { open = function() end, host = function() end, send = function() end }
http = nil
shell = nil
keys = {}
printError = print
print = function() end   -- keep the load quiet

-- peripherals: name -> { types = {...}, obj = {...} }
PERIPHS = PERIPHS or {}
peripheral = {}
function peripheral.getNames() local n = {} for k in pairs(PERIPHS) do n[#n + 1] = k end table.sort(n) return n end
function peripheral.hasType(n, t) local p = PERIPHS[n] if not p then return false end for _, x in ipairs(p.types) do if x == t then return true end end return false end
function peripheral.getType(n) local p = PERIPHS[n] return p and p.types[1] end
function peripheral.wrap(n) local p = PERIPHS[n] return p and p.obj end
function peripheral.isPresent(n) return PERIPHS[n] ~= nil end
function peripheral.getName(o) for k, p in pairs(PERIPHS) do if p.obj == o then return k end end end
function peripheral.getMethods(n) local m = {} for k, v in pairs(PERIPHS[n].obj) do if type(v) == "function" then m[#m + 1] = k end end return m end
function peripheral.call(n, fn, ...) return PERIPHS[n].obj[fn](...) end
