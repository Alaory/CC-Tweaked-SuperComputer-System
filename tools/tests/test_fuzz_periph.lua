-- FLAKY PERIPHERALS (the owner: "go over every feature and check them"). In the game a peripheral can error
-- (a chunk unloads, a server-side crash like AE2's getItems "invalid dist"), answer nil, or answer something of
-- an unexpected shape (another mod version). The workers pcall the READING, so an error there only skips a
-- refresh - but what was read lands in state.* and the SCREEN draws it, and draw() is NOT pcall'd in uiLoop:
-- one odd value there and the whole base stops (startup.lua starts it again, into the same data).
-- Every peripheral function here: sometimes an error, sometimes nil, sometimes an odd value. Then every
-- reading function and background job runs, and every page must draw.
dofile(SRC_DIR .. "/tools/tests/lib/fake_ae2.lua")
math.randomseed(4321)
os.reboot, os.shutdown = function() end, function() end
local errors, seen, jobErr = {}, {}, {}
local function note(where, err)
  local k = where .. " | " .. tostring(err):gsub("%d+", "#")
  if not seen[k] then seen[k] = true errors[#errors + 1] = where .. ": " .. tostring(err) end
end
local function guarded(f, ...)
  local args = table.pack(...)
  debug.sethook(function() error("RUNS TOO LONG (endless loop?)") end, "", 5e7)
  local ok, r = xpcall(function() return f(table.unpack(args, 1, args.n)) end, function(e)
    -- (where it came from: the first lines of the traceback that are base files)
    local tb, out = debug.traceback(tostring(e), 2), {}
    for l in tb:gmatch("[^\n]+") do if l:find("base_") and #out < 4 then out[#out + 1] = l:gsub("^%s+", "") end end
    return table.concat(out, " <- ")
  end)
  debug.sethook()
  return ok, r
end
local ODD = { function() return "odd" end, function() return 7 end, function() return {} end,
              function() return { 1, "x", {} } end, function() return { name = 5, amount = "x", count = {}, x = "a" } end,
              function() return true end, function() return -1 end, function() return { { name = {}, amount = "?" }, 4 } end }
local P = 0      -- the share of calls that go wrong (set per round)
local function flaky(f)
  return function(...)
    if math.random() < P then
      local r = math.random(1, 3)
      if r == 1 then error("peripheral flaked", 0) end
      if r == 2 then return nil end
      return ODD[math.random(1, #ODD)]()
    end
    return f(...)
  end
end
-- every peripheral object (not the monitor: the screen itself is not the subject here)
local wrapped = {}
local function wrapAll(obj)
  if type(obj) ~= "table" or wrapped[obj] or obj == mon then return end
  wrapped[obj] = true
  for k, v in pairs(obj) do if type(v) == "function" then obj[k] = flaky(v) end end
end
for name, p in pairs(PERIPHS) do if name ~= "right" then wrapAll(p.obj) end end
for _, g in ipairs({ "bridge", "inv", "det", "envDet", "chatBox" }) do wrapAll(_ENV[g]) end
for _, dr in pairs(drones or {}) do wrapAll(dr.p) wrapAll(dr.iface) end

local READS = { "refreshInventory", "refreshPlayers", "refreshStorage", "refreshDrones", "fetchCurios", "fetchME",
                "MEX.tick", "ENV.tick", "trackPlayers", "settleOwed", "parkCheck", "sysRefresh", "TT.updateTick",
                "TT.patrolTick", "TT.homeTick", "TT.avoidTick", "MAP.feedSurvey", "MAP.autoTick", "MINE.updTick",
                "FACTORY.tick", "AWAY.tick", "DW.tick", "SUPPLY.tick", "CURIOS.autoTick", "POCKET.status", "MEX.jobTick",
                "MAP.checkSpace", "MAP.floppySpace", "MAP.diskUse", "TT.prepareInstallFloppy" }
local PAGES = { "home", "inventory", "storage", "curios", "players", "env", "access", "me", "mesys", "drone", "work", "gifts",
                "turtles", "drive", "map", "mining", "system", "events", "settings" }
local function find(j)
  local f = _ENV
  for part in j:gmatch("[^%.]+") do f = f and f[part] end
  return type(f) == "function" and f or nil
end
local draws = 0
for round, share in ipairs({ 0.1, 0.3, 0.6, 1, 0.3, 0 }) do
  P = share
  CLOCK = CLOCK + 70
  for _, j in ipairs(READS) do
    local f = find(j)
    if f then
      local ok, r = guarded(f, true)
      -- (as the workers do it: what fetchME / fetchCurios hand back goes into state)
      if ok and j == "fetchME" and type(r) == "table" then state.me = r end
      if not ok then jobErr[j] = tostring(r) end
    end
  end
  for _, pg in ipairs(PAGES) do
    state.page = pg
    local ok, e = guarded(draw)
    draws = draws + 1
    if not ok then note("round " .. round .. " (" .. math.floor(share * 100) .. " % flaky) page " .. pg, e) end
  end
end
P = 0
local nj = 0
for _ in pairs(jobErr) do nj = nj + 1 end
CHECK(#errors == 0, #errors .. " page(s) broke on flaky peripherals:\n  " .. table.concat(errors, "\n  ", 1, math.min(#errors, 40)))
CHECK(draws >= 100, "pages drawn: " .. draws .. " (reading jobs that errored - caught by the workers: " .. nj .. ")")
