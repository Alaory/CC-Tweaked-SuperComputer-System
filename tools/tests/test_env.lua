-- ENVIRONMENT DETECTOR (base_env.lua ENV + WORLD page): the 0.7 functions (getMoonId /
-- getMoonName, scanEntities(radius) with a max radius) and the 0.8 ones (getMoon), the
-- game clock (day, HH:MM, night in ...), the scan sorted into hostile / animals / players,
-- a too-big range retried smaller, a cooldown answer shown (not retried), the page draws.
CHECK(envDet ~= nil, "the preview has an Environment Detector")
refreshPlayers(true)
CONFIG.env = { range = 32 }                                  -- bigger than the detector allows (16)
ENV.data, ENV.range = nil, nil
ENV.read(true)
local d = ENV.data
CHECK(d and d.biome == "minecraft:plains" and d.dim == "minecraft:overworld", "biome + dimension read")
CHECK(d.moonId == 2 and d.moonName == "Third quarter", "moon from getMoonId / getMoonName (0.7)")
CHECK(d.rain == true and d.slime == true and d.block == 11, "weather, slime chunk, light")
CHECK(d.dims and #d.dims == 5, "every dimension listed")
CHECK(d.range == 16, "range 32 refused -> scanned with 16 (" .. tostring(d.range) .. ")")
CHECK(d.count and d.count.hostile == 2 and d.count.animal == 1 and d.count.player == 1,
      "2 hostile, 1 animal, 1 player (" .. (d.count and (d.count.hostile .. "/" .. d.count.animal .. "/" .. d.count.player) or "no scan") .. ")")
CHECK(d.ents[1].name == "Alaory" and d.ents[#d.ents].name == "Cow", "nearest first")
local c = ENV.clock(d.time)
CHECK(c.day == 42 and c.hhmm == "17:48" and not c.night and c.secs == 60, "clock: day 42, 17:48, night in 60 s (" ..
      c.day .. " " .. c.hhmm .. " " .. c.secs .. ")")
local cn = ENV.clock(24000 * 3 + 18000)
CHECK(cn.night and cn.hhmm == "00:00" and cn.secs == 250, "midnight: night, day in 250 s (" .. cn.secs .. ")")
-- 0.8 names: getMoon() -> id, name
local real = envDet
envDet = setmetatable({ getMoon = function() return 0, "Full moon" end, getMoonId = function() error("old") end }, { __index = real })
ENV.read(false)
CHECK(ENV.data.moonId == 0 and ENV.data.moonName == "Full moon", "moon from getMoon (0.8)")
-- a cooldown answer: kept as the reason, the old list stays, no smaller ranges tried
local calls = 0
envDet = setmetatable({ scanEntities = function(r) calls = calls + 1 return nil, "This operation is on cooldown" end }, { __index = real })
ENV.scan()
CHECK(calls == 1 and ENV.data.scanErr and ENV.data.scanErr:find("cooldown") and ENV.data.count, "cooldown: reason kept, one call, old counts stay")
envDet = real
ENV.read(true)
-- the page
local function screen()
  hits = {}
  draw()
  local out = {}
  for y = 1, H do out[#out + 1] = (MONITOR.getLine(y)) end
  return table.concat(out, "\n")
end
state.page = "env"
local s = screen()
CHECK(s:find("AROUND THE BASE", 1, true) and s:find("Creeper", 1, true) and s:find("2 HOSTILE", 1, true), "page: the mobs around")
CHECK(s:find("Third quarter", 1, true) and s:find("Plains", 1, true) and s:find("Twilight Forest", 1, true), "page: moon, biome, dimensions")
CHECK(s:find("Night (mobs) in 60 s", 1, true), "page: when night comes")
CHECK(s:find("WORLD 2 mobs", 1, true), "the WORLD chip shows the hostile count")
-- no detector: the page says so
local keep = envDet
envDet = nil
s = screen()
CHECK(s:find("NO ENVIRONMENT DETECTOR", 1, true), "no detector: a message, no error")
envDet = keep
CONFIG.env = nil
