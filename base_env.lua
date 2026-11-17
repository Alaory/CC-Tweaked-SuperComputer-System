-- base_env.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   ENVIRONMENT DETECTOR (Advanced Peripherals; ENV): what the world is like at the base
--   - the game time (day number, day / night and how long until it changes), weather,
--   moon phase, light levels, biome, dimension, slime chunk, every dimension of the
--   world, Mekanism radiation - and the LIVING THINGS around the detector (scanEntities):
--   hostile mobs, animals, players, with distance, direction and health.
--   Read by the page worker (the WORLD page every 2 s, else once a minute); drawing
--   reads ENV.data only. Function names differ between versions (0.7: getMoonId /
--   getMoonName, scanEntities(radius); 0.8: getMoon, scanEntities(range, detailed,
--   filter)) - each is looked up by name and skipped when it is not there.

ENV = { data = nil, scanAt = 0, range = nil }

function ENV.cfg(k, default)
  local e = CONFIG.env
  local v
  if type(e) == "table" then v = e[k] end
  if v == nil then return default end
  return v
end

-- a detector function's result (nil when it does not exist / fails)
local function call(name, ...)
  local fn = envDet and envDet[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil, tostring(a) end
  return a, b
end

-- hostile mobs by their (English) name: the scan gives the display name only
ENV.HOSTILE = {}
for _, n in ipairs({ "zombie", "husk", "drowned", "skeleton", "stray", "bogged", "creeper", "spider", "cave spider",
                     "enderman", "witch", "slime", "magma cube", "phantom", "pillager", "vindicator", "evoker", "ravager",
                     "vex", "blaze", "ghast", "wither skeleton", "piglin brute", "hoglin", "zoglin", "zombie villager",
                     "silverfish", "endermite", "guardian", "elder guardian", "shulker", "breeze", "warden", "wither",
                     "ender dragon", "illusioner", "creaking" }) do ENV.HOSTILE[n] = true end

-- what kind of living thing a scan entry is: "player" / "hostile" / "animal" / "other"
function ENV.kind(e)
  local n = tostring(e.name or ""):lower()
  if state.online and state.online[n] then return "player" end
  for _, p in ipairs(state.players or {}) do if tostring(p.name):lower() == n then return "player" end end
  if ENV.HOSTILE[n] or e.aggressive == true then return "hostile" end
  if e.baby ~= nil or e.inLove ~= nil then return "animal" end         -- (only animals carry these)
  return "other"
end

-- the game time: day number, "HH:MM", is it night, seconds until it changes
-- (24000 ticks a day = 20 min; tick 0 = 06:00; mobs spawn ~13000 .. 23000)
function ENV.clock(t)
  t = tonumber(t)
  if not t then return nil end
  local day = math.floor(t / 24000) + 1
  local d = t % 24000
  local mins = math.floor(((d / 1000) + 6) % 24 * 60)
  local hhmm = string.format("%02d:%02d", math.floor(mins / 60), mins % 60)
  local night = d >= 13000 and d < 23000
  local untilT = night and (23000 - d) or ((d < 13000) and (13000 - d) or (24000 - d + 13000))
  return { day = day, hhmm = hhmm, night = night, secs = math.floor(untilT / 20) }
end

-- one reading of everything (page worker; envDet calls only here)
function ENV.read(withScan)
  if not envDet then ENV.data = nil return end
  local d = ENV.data or {}
  ENV.data = d                                       -- (the scan below adds to this same table)
  d.t = os.clock()
  d.biome = call("getBiome")
  d.block = call("getBlockLightLevel")
  d.sky = call("getSkyLightLevel")
  d.daylight = call("getDayLightLevel")
  d.time = call("getTime")
  d.slime = call("isSlimeChunk")
  d.dim = call("getDimension") or call("getDimensionPaN") or call("getDimensionName")
  d.rain, d.thunder, d.sunny = call("isRaining"), call("isThunder"), call("isSunny")
  d.sleep = call("canSleepHere")
  -- the moon: 0.8 getMoon() -> id, name; 0.7 getMoonId() + getMoonName()
  local mid, mname = call("getMoon")
  if mid == nil then mid, mname = call("getMoonId"), call("getMoonName") end
  d.moonId, d.moonName = tonumber(mid), mname and tostring(mname) or nil
  -- every dimension of the world (read once, it does not change)
  if not d.dims then
    local list = call("listDimensions")
    if type(list) == "table" then
      local out = {}
      for k, v in pairs(list) do
        local s = type(v) == "string" and v or (type(k) == "string" and k) or nil
        if s then out[#out + 1] = s end
      end
      table.sort(out)
      d.dims = out
    end
  end
  -- Mekanism radiation (only with Mekanism)
  local rad = call("getRadiation")
  d.rad = type(rad) == "table" and (tostring(rad.radiation or "?") .. " " .. tostring(rad.unit or "")) or nil
  d.radRaw = tonumber((call("getRadiationRaw")))
  if withScan then ENV.scan() end
  ENV.data = d
end

-- the living things around the detector (relative x y z), nearest first
function ENV.scan()
  if not (envDet and envDet.scanEntities) then return end
  local d = ENV.data or {}
  ENV.data = d
  local want = tonumber(ENV.cfg("range", 16)) or 16
  local tries = {}
  for _, r in ipairs({ ENV.range or want, want, 16, 8, 4 }) do
    if r <= want and not tries[r] then tries[#tries + 1] = r tries[r] = true end
  end
  local list, err
  for _, r in ipairs(tries) do
    local ok, a, b = pcall(envDet.scanEntities, r)
    if ok and type(a) == "table" then list, ENV.range = a, r break end
    err = ok and tostring(b or "no answer") or tostring(a)
    -- (a cooldown / not enough fuel: a smaller range will not help - try again later)
    if not tostring(err):lower():find("radius") and not tostring(err):lower():find("range") then break end
  end
  ENV.scanAt = os.clock()
  if not list then d.scanErr = err return end
  d.scanErr = nil
  local out, count = {}, { hostile = 0, animal = 0, player = 0, other = 0 }
  for _, e in pairs(list) do
    if type(e) == "table" and tonumber(e.x) then
      local x, y, z = tonumber(e.x), tonumber(e.y) or 0, tonumber(e.z)
      local k = ENV.kind(e)
      count[k] = count[k] + 1
      out[#out + 1] = { name = tostring(e.name or "?"), kind = k, x = x, y = y, z = z,
                        dist = math.sqrt(x * x + y * y + z * z),
                        hp = tonumber(e.health), max = tonumber(e.maxHealth), baby = e.baby == true }
    end
  end
  table.sort(out, function(a, b) return a.dist < b.dist end)
  d.ents, d.count, d.scanT, d.range = out, count, os.clock(), ENV.range
end

-- for the page worker: read when stale (the WORLD page: 2 s, scan every 5 s; else 60 s)
function ENV.tick(onPage)
  if not envDet then return false end
  local age = ENV.data and (os.clock() - ENV.data.t) or math.huge
  if age < (onPage and 2 or 60) then return false end
  ENV.read(onPage and os.clock() - ENV.scanAt >= (tonumber(ENV.cfg("scanEvery", 5)) or 5))
  return true
end

-- text lines for the console (`env`)
function ENV.lines()
  local d = ENV.data
  if not envDet then return { "No Environment Detector on the computer or the cable." } end
  if not d then return { "Not read yet - try again in a moment." } end
  local c = ENV.clock(d.time)
  local L = {}
  if c then L[#L + 1] = "Day " .. c.day .. ", " .. c.hhmm .. " - " .. (c.night and "NIGHT" or "day") ..
                        " (" .. (c.night and "day" or "night") .. " in " .. fmtSpan(c.secs) .. ")" end
  L[#L + 1] = "Weather: " .. ((d.thunder and "THUNDER") or (d.rain and "rain") or (d.sunny and "sunny") or "?") ..
              (d.moonName and ("   Moon: " .. d.moonName) or "")
  L[#L + 1] = "Biome: " .. tostring(d.biome and prettify(d.biome) or "?") .. "   Dimension: " .. tostring(d.dim and prettify(d.dim) or "?") ..
              (d.slime and "   SLIME CHUNK" or "")
  L[#L + 1] = "Light: block " .. tostring(d.block or "?") .. ", sky " .. tostring(d.sky or "?") .. ", daylight " .. tostring(d.daylight or "?")
  if d.rad then L[#L + 1] = "Radiation: " .. d.rad end
  if d.count then
    L[#L + 1] = string.format("Around (%d blocks): %d hostile, %d animals, %d players, %d other",
                              d.range or 0, d.count.hostile, d.count.animal, d.count.player, d.count.other)
  elseif d.scanErr then L[#L + 1] = "Scan: " .. d.scanErr end
  if d.dims then L[#L + 1] = "Dimensions (" .. #d.dims .. "): " .. table.concat(d.dims, ", ") end
  return L
end
