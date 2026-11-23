-- inventory.lua's loader on a fake disk (lua5.3 tools/tests/inventory_load.lua <repo root>):
-- PACKED base files (base_*.luz) are unpacked with unzip.lua into memory, a plain base_x.lua next to one is used
-- instead, unzip.lua missing / a broken .luz / a missing file stop it with a clear message, and the pauses while
-- unpacking lose no event.
local ROOT = arg[1] or "."
local FAILS, N = 0, 0
local function CHECK(c, m) N = N + 1 if not c then FAILS = FAILS + 1 print("FAIL: " .. m) end end
local function readReal(p) local h = io.open(ROOT .. "/" .. p, "rb") if not h then return nil end local s = h:read("a") h:close() return s end
local realLoad = load

local INV = readReal("inventory.lua")
local MODULES = {}
for name in INV:match("local MODULES = (%b{})"):gmatch('"([%w_]+)"') do MODULES[#MODULES + 1] = name end

local function run(disk, events)
  local LOADED, Q, printed = {}, events or {}, {}
  local E = {}
  E.fs = {
    exists = function(p) return disk[p] ~= nil end,
    combine = function(a, b) return (a == "" and b) or (a .. "/" .. b) end,
    getDir = function(p) return p:match("^(.*)/") or "" end,
    open = function(p) local s = disk[p] if not s then return nil end
      return { readAll = function() return s end, close = function() end } end,
  }
  E.shell = { getRunningProgram = function() return "base/inventory.lua" end }
  E.settings = { get = function() return false end }
  E.os = { queueEvent = function(...) Q[#Q + 1] = table.pack(...) end,
           pullEventRaw = function() local e = table.remove(Q, 1) assert(e, "no event") return table.unpack(e, 1, e.n) end }
  E.print = function(s) printed[#printed + 1] = s end
  E.table, E.string, E.math, E.ipairs, E.pairs, E.pcall, E.error, E.tostring, E.type, E.select =
    table, string, math, ipairs, pairs, pcall, error, tostring, type, select
  -- base files: recorded, not run; unzip.lua: really run
  E.load = function(text, chunk, mode, env)
    LOADED[#LOADED + 1] = { name = chunk, text = text }
    return function() end
  end
  E.loadfile = function(p, mode, env)
    if not disk[p] then return nil, "no file " .. p end
    if p:match("unzip%.lua$") then return realLoad(disk[p], "@" .. p, "t", _ENV) end
    LOADED[#LOADED + 1] = { name = "@" .. p, text = disk[p], plain = true }
    return function() end
  end
  E.buildWindow = function() error("LOADED_ALL", 0) end
  local fn = assert(realLoad(INV, "=inventory.lua", "t", E))
  local ok, err = pcall(fn)
  return ok, tostring(err), LOADED, Q, printed
end

local function packedDisk()
  local d = { ["base/unzip.lua"] = readReal("dist/unzip.lua"), ["base/base_config.lua"] = "CONFIG = {}" }
  for _, m in ipairs(MODULES) do
    if m ~= "base_config" then d["base/" .. m .. ".luz"] = assert(readReal("dist/z/" .. m .. ".luz"), m) end
  end
  return d
end

-- 1) everything packed (+ your plain base_config.lua): each one unpacked, the same text as the slim file, the same
--    chunk name as the plain file (error messages say base_x.lua:<line>)
local disk = packedDisk()
local timerEv = { "timer", 7, n = 2 }
local ok, err, L, Q, printed = run(disk, { timerEv })
CHECK(err == "LOADED_ALL", "every file loaded (" .. err .. ")")
local wrong = {}
for i, m in ipairs(MODULES) do
  local l = L[i]
  if not l or l.name ~= "@base/" .. m .. ".lua" then wrong[#wrong + 1] = m .. " (name " .. tostring(l and l.name) .. ")"
  elseif m ~= "base_config" and l.text ~= readReal("dist/" .. m .. ".lua") then wrong[#wrong + 1] = m .. " (text)" end
end
CHECK(#L == #MODULES and #wrong == 0, "in order, unpacked to the slim text, chunk names base/<file>.lua (" .. table.concat(wrong, ", ") .. ")")
CHECK(L[1].plain, "base_config.lua (plain - your settings) read as it is")
local timerLeft = false
for _, e in ipairs(Q) do if e[1] == "timer" and e[2] == 7 then timerLeft = true end end
CHECK(timerLeft, "an event that came while unpacking is still there afterwards (put back)")
CHECK(printed[1] and printed[1]:find("Unpacking", 1, true), "it says it is unpacking")

-- 2) a plain base_me.lua next to its .luz (dragged in by hand): the plain one is used
disk = packedDisk()
disk["base/base_me.lua"] = "-- my own copy"
ok, err, L = run(disk)
local me
for _, l in ipairs(L) do if l.name == "@base/base_me.lua" then me = l end end
CHECK(me and me.plain and me.text == "-- my own copy", "a plain base_me.lua is used before base_me.luz")

-- 3) all plain (an older install / `upgrade slim`): no unzip.lua needed
disk = { ["base/base_config.lua"] = "CONFIG = {}" }
for _, m in ipairs(MODULES) do if m ~= "base_config" then disk["base/" .. m .. ".lua"] = "-- " .. m end end
ok, err, L = run(disk)
CHECK(err == "LOADED_ALL" and #L == #MODULES, "all plain files, no unzip.lua: loads as before (" .. err .. ")")

-- 4) unzip.lua missing: a clear message
disk = packedDisk()
disk["base/unzip.lua"] = nil
ok, err = run(disk)
CHECK(not ok and err:find("unzip.lua", 1, true) and err:find("upgrade", 1, true), "no unzip.lua: says so (" .. err .. ")")

-- 5) a broken .luz: names the file
disk = packedDisk()
disk["base/base_map.luz"] = disk["base/base_map.luz"]:sub(1, 500)
ok, err = run(disk)
CHECK(not ok and err:find("base_map.luz", 1, true), "a broken packed file: named (" .. err .. ")")

-- 6) a file missing: all missing ones listed
disk = packedDisk()
disk["base/base_me.luz"], disk["base/base_ui_map.luz"] = nil, nil
ok, err = run(disk)
CHECK(not ok and err:find("base_me.lua", 1, true) and err:find("base_ui_map.lua", 1, true), "missing files: all named (" .. err .. ")")

print((FAILS == 0 and "PASS" or "FAIL") .. " (" .. N .. " checks, " .. FAILS .. " failed)")
os.exit(FAILS == 0 and 0 or 1)
