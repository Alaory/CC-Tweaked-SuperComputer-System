-- DRONE WORK (DW): PneumaticCraft drones doing jobs for the base, with items from AE2.
--
--   * the WORK CHEST: an EMPTY chest / barrel on the wired cable that the drones can reach
--     (near their home). The base puts items into it from AE2 (exact counts, PLAIN items only -
--     never your own: FACTORY.variants), the drone takes them; what comes back goes into AE2.
--     Only the base and the drones use it.  dw chest <n|name> <me|place|x y z>
--   * FUEL RUNS: a turtle with NO FUEL is still on, and its Chunky keeps its own chunk loaded -
--     the drone can teleport straight to it: fuel from AE2 into the turtle's inventory (node.lua
--     burns it within a minute: idleEmptyFuel). Automatic (dw auto on|off), or  dw fuel <id>.
--     The rescuer turtle waits while a run is on (problemOf asks DW.fuelBusy).
--   * SCHEMATIC BUILD:  schem build <name> <me|place|x y z> [rot 90|180|270] [clear]
--     the drone places the blocks layer by layer, bottom up, one item and one chunk per trip
--     (clear = first dig what the schematic says is air, top down). Progress is saved
--     (dronework.dat) - a restart goes on where it was. A site nobody keeps loaded (no player,
--     no turtle in that chunk): a free turtle flies there first and waits ABOVE the build as
--     its chunk anchor (t.dwAnchor), moving along chunk by chunk.
--     Drones place blocks the default way round: stairs / doors / logs may face another way.
--
-- Every drone job is one MISSION (kind "work", base_drones.lua runMission): the steps run in the
-- drone worker; DW.tick (comms worker, every 2 s) only plans and reads the results.
DW = DW or {}
DW.FILE = "dronework.dat"
DW.job = nil                 -- the schematic build
-- EVERY DRONE AT ONCE (the owner: "why use 1 drone? why not use more?"): one trip per free drone, side by side
-- (gifts, fuel runs, several build trips). The work chest is only taken while a drone LOADS or UNLOADS there
-- (DW.chestBy - after it has flown to the chest; the others wait their turn).
DW.trips = {}                -- [drone key] = the mission running on it: { kind, dr, J, title, at ... }
DW.trip = nil                -- (one of them - older talk packs / quick checks)
DW.runs = {}                 -- fuel runs: [turtle id] = { t, state, why }
DW.auto = nil                -- automatic fuel runs (nil = the setting)

local function cfg(k, default)
  local d = CONFIG.drone or {}
  if d[k] ~= nil then return d[k] end
  return default
end
local function now() return os.clock() end

------------------------------------------------------------------ settings
function DW.chestName() return cfg("workChest") end
function DW.chestAt()
  local a = cfg("workChestAt")
  if type(a) == "table" and tonumber(a.x) then return math.floor(a.x), math.floor(a.y), math.floor(a.z) end
end
function DW.fuelItem()
  return cfg("fuelItem") or (CONFIG.factory and CONFIG.factory.fuel) or "minecraft:coal",
         tonumber(cfg("fuelCount")) or 32
end
function DW.autoOn()
  if DW.auto ~= nil then return DW.auto end
  return cfg("fuelRuns", true) ~= false
end

function DW.syncTrip()
  DW.trip = nil
  for _, t in pairs(DW.trips) do DW.trip = t break end
end
function DW.anyTrip(kind)
  for _, t in pairs(DW.trips) do if not kind or t.kind == kind then return t end end
end
-- the running trips, oldest first
function DW.tripList()
  local l = {}
  for _, t in pairs(DW.trips) do l[#l + 1] = t end
  table.sort(l, function(a, b) return (a.at or 0) < (b.at or 0) end)
  return l
end
-- THE WORK CHEST, ONE DRONE AT A TIME: taken after the drone has flown there, only for its load / unload
-- (a few seconds); a holder whose mission is over / 120 s old is no longer waited for
function DW.chestTake(dr, maxWait)
  local t0 = now()
  while DW.chestBy and DW.chestBy ~= dr.key do
    local h = drones[DW.chestBy]
    if not (h and h.busy) or now() - (DW.chestSince or 0) > 120 then break end
    if now() - t0 > (maxWait or 180) then return false, "the work chest stayed busy (another drone)" end
    sleep(0.5)
  end
  DW.chestBy, DW.chestSince = dr.key, now()
  return true
end
function DW.chestFree(dr)
  if DW.chestBy == (dr and dr.key) then DW.chestBy = nil end
end

-- can the drones work at all? nil = yes, else why not
function DW.notReady()
  if not bridge then return "no ME Bridge" end
  local c = DW.chestName()
  if not c then return "no work chest - stand ON an empty chest on the cable and type  dw chest  (it lists them)" end
  if not peripheral.isPresent(c) then return "the work chest " .. c .. " is not on the cable" end
  if not DW.chestAt() then return "the work chest's position is not set -  dw chest " .. c .. " me  (standing ON it)" end
  if #droneOrder == 0 then return "no Drone Interface" end
end

-- A GIFT WAITS (the owner: "gifts via drones get queued and never get sent"): fuel runs started in the same tick a
-- trip ended (DW.tick), the gift check comes every few seconds - with several NO FUEL turtles it never found a free
-- drone. DW.wantDrone(what) (voice_talk2 when a gift is ready): for 30 s no fuel run / build trip starts.
function DW.wantDrone(what) DW.wanted = { what = tostring(what or "?"), at = now() } end
function DW.yielding() return DW.wanted ~= nil and now() - DW.wanted.at < 30 end

-- a free drone: connected, nothing to do, nobody on board (CONFIG.drone.worker = its key / label)
-- okFn(dr) -> true | false, why: only a drone that can do THIS trip (DW.airFor: enough air for a far one)
function DW.freeDrone(okFn)
  local want = cfg("worker")
  local why = {}
  for _, k in ipairs(droneOrder) do
    local dr = drones[k]
    if dr and (not want or want == k or want == dr.label) then
      local w
      if dr.gone or dr.conn == false then w = "not connected"
      elseif dr.busy or #(dr.queue or {}) > 0 then w = "busy" .. (dr.mission and dr.mission.title and (": " .. tostring(dr.mission.title)) or "")
      elseif dr.rider then w = tostring(dr.rider) .. " on board" end
      if not w and okFn then
        local okA, whyA = okFn(dr)
        if not okA then w = tostring(whyA) end
      end
      if not w then return dr end
      why[#why + 1] = tostring(dr.label or k) .. " " .. w
    end
  end
  -- (2nd value: why none is free - shown by  voice gifts  /  dw)
  DW.noDroneWhy = #why > 0 and table.concat(why, ", ") or (want and ("no drone named " .. tostring(want))) or "no drones"
  return nil, DW.noDroneWhy
end

-- AIR FOR THE WHOLE TRIP (the owner: "drone gifts teleport up to the sky, get lost and I never see them again"): a
-- trip further than the drone can fly safely (base_drones.lua flySafe) needs a teleport THERE and one BACK (+ one that
-- may be refused) + the reserve - started with less, the drone ended up flying across unloaded land and was lost.
function DW.airFor(dr, x, z)
  -- (below the mission minimum a trip fails at its start - "Pressure too low" - and paused the whole build 2 min:
  --  a drone that low charges, the others work)
  pcall(refreshDrone, dr)
  local p = dronePressure(dr)
  if p and p < (tonumber(CONFIG.drone.minPressure) or 2) then
    return false, string.format("%s charges (%.1f bar)", tostring(dr.label), p)
  end
  local hx, _, hz = DW.chestAt()
  if not hx then local h = CONFIG.drone.home or {} hx, hz = h.x, h.z end
  if not (hx and tonumber(x)) then return true end
  if math.max(math.abs(x - hx), math.abs(z - hz)) <= (tonumber(cfg("workFly", 64)) or 64) then return true end
  if CONFIG.drone.travel == "fly" then return true end
  pcall(refreshDrone, dr)
  if canTeleport(dr, 2) then return true end
  return false, string.format("%s has %.1f bar - a trip that far needs %.1f (a teleport there and back + the " ..
                              "reserve): it charges first", tostring(dr.label), dronePressure(dr) or 0,
                              teleportCost(dr) * 3 + (CONFIG.drone.airReserve or 1.5))
end

-- how many slots one trip can carry (64 items each)
-- ONE SLOT = 64 items a trip (the owner: "a drone can only carry a max of 64 items"): Inventory Upgrades are NOT
-- counted by themselves any more - CONFIG.drone.slots (settings) says how many slots the drones really have
function DW.slots(dr)
  local s = tonumber(cfg("slots"))
  if s then return math.max(1, math.floor(s)) end
  return 1
end

------------------------------------------------------------------ the work chest
local function chestList()
  local c = DW.chestName()
  if not c then return nil end
  local ok, l = pcall(peripheral.call, c, "list")
  if ok and type(l) == "table" then return l end
end
local function chestCount(name)
  local n = 0
  for _, it in pairs(chestList() or {}) do
    if not name or it.name == name then n = n + (tonumber(it.count) or 0) end
  end
  return n
end
DW.chestCount = chestCount
-- everything in the work chest back into AE2 (only the base and the drones put things there):
-- { [item] = count } moved
function DW.chestToAE2()
  local moved = {}
  for _, it in pairs(chestList() or {}) do
    local ok, r = transfer(bridge, { "importItem" }, DW.chestName(), { name = it.name, count = it.count })
    local n = ok and numOf(r) or 0
    if n > 0 then moved[it.name] = (moved[it.name] or 0) + n end
  end
  return moved
end
-- n PLAIN ones of an item from AE2 into the work chest (never your own: enchanted, renamed,
-- used ...): count moved, or 0 + why
function DW.giveToChest(name, count)
  local plain, own, fp = FACTORY.variants(name)
  if plain <= 0 then
    return 0, "no plain " .. prettify(name) .. " in AE2" .. ((own > 0) and " (only your own one - not taken)" or "")
  end
  local n = math.min(count, plain)
  local filter = { name = name, count = n }
  if fp then filter.fingerprint = fp end
  local ok, r = transfer(bridge, { "exportItem" }, DW.chestName(), filter)
  local moved = ok and numOf(r) or 0
  if moved <= 0 then return 0, "could not put " .. prettify(name) .. " into the work chest" .. (ok and "" or (": " .. tostring(r))) end
  return moved
end

------------------------------------------------------------------ mission steps
-- ALL SIDES of the block may be used: a computer-controlled drone starts with NO side selected
-- (PneumaticCraft ProgWidgetCC: sides = new boolean[6]; DroneEntityAIInventoryImport only uses
-- isSideSelected sides) - inventory import / export then did NOTHING. In game: "the drone took
-- nothing from the work chest" with the right spot. setSides order: down up north south west east.
function DW.allSides(d)
  if d.setSides then
    local ok = pcall(d.setSides, true, true, true, true, true, true)
    if ok then return true end
  end
  if d.setSide then
    for _, s in ipairs({ "down", "up", "north", "south", "west", "east" }) do pcall(d.setSide, s, true) end
    return true
  end
  return false
end
local function act(dr, action, pts, limit)
  local d = dr.periph
  return droneDo(dr, action, function()
    d.clearArea()
    for _, p in ipairs(pts) do d.addArea(math.floor(p.x), math.floor(p.y), math.floor(p.z)) end
    if d.clearWhitelistItemFilter then pcall(d.clearWhitelistItemFilter) end
    if d.setUseCount then pcall(d.setUseCount, false) end
    DW.allSides(d)
  end, 1, limit)
end
-- close by (CONFIG.drone.workFly, 64 blocks): FLY there - flying costs no air, a teleport ~0.85 bar
-- (a build trip goes chest -> site -> chest); further: the normal travel (teleport / hops)
-- (measured, tools/tests/lib/drone_sim.lua: within 64 it FLEW with the teleport's 8-s limit - 160 ticks = 24 blocks
--  at 0.15 a tick: every leg over 24 blocks flew 160 ticks, was stopped, then teleported anyway = 281 ticks for a
--  121-tick teleport). Now: fly when that is quicker than a teleport (flyQuicker) or the air is low, with a limit
--  that fits the distance; else teleport.
local function goNear(dr, x, y, z, loaded)
  local px, py, pz = droneXYZ(dr)
  local r = tonumber(cfg("workFly", 64)) or 64
  if px and math.abs(px - x) <= r and math.abs(pz - z) <= r and math.abs(py - y) <= r then
    local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2)
    -- (a build makes many trips: teleporting every leg empties a 12-teleport drone - it then has to recharge.
    --  Teleport only with air to spare for 4 more; else fly - slower, but no air)
    if flyQuicker(dr, d) or not canTeleport(dr, 4) then
      local ok, why = droneMoveTo(dr, "pneumaticcraft:goto", x, y, z, flyLimit(dr, d) + 7)
      if ok then return true end
      if why == "stopped" or why == "the drone disconnected" then return false, why end
    end
  end
  return travelTo(dr, x, y, z, nil, nil, loaded)
end
DW.goNear = goNear
local function toChest(dr)
  local x, y, z = DW.chestAt()
  local ok, why = goNear(dr, x, y + 2, z, true)
  if not ok then return false, "could not get to the work chest: " .. tostring(why) end
  return true
end
-- empty the drone into the work chest; all of it back into AE2. J.back = { [item] = n }
-- first = the trip's first step: nothing to do when its last trip ended with an unload that worked (dr.dwEmpty) -
-- before, every trip flew to the chest, took it and exported an EMPTY drone first
local function stepUnload(dr, J, text, first)
  return { text = text or "Empty the drone into the work chest", fn = function()
    if first and dr.dwEmpty then return true end
    local ok, why = toChest(dr)
    if not ok then return false, why end
    ok, why = DW.chestTake(dr)
    if not ok then return false, why end
    local x, y, z = DW.chestAt()
    ok, why = act(dr, "pneumaticcraft:inventory_export", { { x = x, y = y, z = z } })
    if not ok then DW.chestFree(dr) return false, why end
    local back = DW.chestToAE2()
    J.back = J.back or {}
    for k, v in pairs(back) do J.back[k] = (J.back[k] or 0) + v end
    local left = chestCount()
    DW.chestFree(dr)
    if left > 0 then return false, "the work chest is not empty (AE2 full?)" end
    dr.dwEmpty = true
    return true
  end }
end
-- `want` of an item from AE2 -> the work chest -> the drone. J.carried = how many it holds
local function stepLoad(dr, J, item, want)
  return { text = "Get " .. want .. " " .. prettify(item) .. " from AE2", fn = function()
    -- (to the chest first, THEN the chest is this drone's: other drones may be loading meanwhile)
    local ok, err = toChest(dr)
    if not ok then return false, err end
    local tW = os.epoch("utc")
    ok, err = DW.chestTake(dr)
    if not ok then return false, err end
    local tG = os.epoch("utc")
    J.tWait = tG - tW                               -- (where a load's time goes: schem status)
    if chestCount() > 0 then DW.chestToAE2() end
    if chestCount() > 0 then DW.chestFree(dr) return false, "the work chest is not empty - only the base and the drones may use it" end
    local moved, why = DW.giveToChest(item, want)
    if moved <= 0 then DW.chestFree(dr) J.missing = item return false, why end
    local tI = os.epoch("utc")
    J.tGive = tI - tG
    dr.dwEmpty = false
    local x, y, z = DW.chestAt()
    ok, err = act(dr, "pneumaticcraft:inventory_import", { { x = x, y = y, z = z } })
    J.tTake = os.epoch("utc") - tI
    local left = chestCount(item)
    if left > 0 then DW.chestToAE2() end           -- (more than it could carry: the rest goes back)
    DW.chestFree(dr)
    J.carried = moved - left
    if not ok then return false, err end
    if J.carried <= 0 then
      local px, py, pz = droneXYZ(dr)
      return false, "the drone took nothing from the work chest. Saved spot: " .. x .. " " .. y .. " " .. z ..
             (px and (", the drone was at " .. math.floor(px) .. " " .. math.floor(py) .. " " .. math.floor(pz)) or "") ..
             ". Is that the chest's real spot (F3: Targeted Block) and is the block ON TOP of it air?"
    end
    return true
  end }
end
local function stepGo(dr, text, getPos, loaded)
  return { text = text, fn = function()
    local x, y, z = getPos()
    if not x then return false, y end
    return goNear(dr, x, y, z, loaded)
  end }
end
local function submit(dr, title, steps, trip)
  trip.dr, trip.title, trip.at = dr.key, title, now()
  DW.trips[dr.key] = trip
  DW.syncTrip()
  -- (a build trip: the drone stays at the work chest for the next one while it has air - flying home to the charger
  --  after EVERY trip and back to the chest for the next was a big part of a trip)
  local stay = trip.kind == "dig" or trip.kind == "place"
  if not submitDrone(dr, { kind = "work", title = title, steps = steps, stay = stay }) then
    DW.trips[dr.key] = nil
    DW.syncTrip()
    return false, "the drone is busy"
  end
  return true
end

------------------------------------------------------------------ fuel runs
-- the rescuer waits while a drone brings fuel (and 3 min after, while the turtle burns it)
function DW.fuelBusy(t)
  local r = t and DW.runs[t.id]
  if not r then return false end
  if r.state == "flying" then return true end
  return r.state == "delivered" and now() - (r.doneAt or 0) < 180
end

-- a drone can take fuel to a turtle now? (the drones are set up and fuel runs are on)
function DW.canFuel()
  return DW.autoOn() and not DW.notReady() and #droneOrder > 0
end
function DW.fuelRun(id, why, edge)
  local t = state.turtles[tonumber(id) or id]
  if not t then return false, "no turtle " .. tostring(id) end
  local bad = DW.notReady()
  if bad then return false, bad end
  if not TT.online(t) then return false, t.label .. " is offline - its chunk is not loaded (a rescue turtle has to go)" end
  if not (t.pos and t.pos.x) then return false, t.label .. "'s position is unknown" end
  local dr, whyD = DW.freeDrone(function(d) return DW.airFor(d, t.pos.x, t.pos.z) end)
  if not dr then return false, "no free drone (" .. tostring(whyD) .. ")" end
  local item, count = DW.fuelItem()
  -- a turtle at the survey edge gets a full load (instead of a trip home and back - ~5,000 blocks)
  if edge then count = DW.slots(dr) * 64 end
  local J = { kind = "fuel", id = t.id }
  local tid = t.id
  local function where()
    local tt = state.turtles[tid]
    if not (tt and tt.pos and tt.pos.x) then return nil, "the turtle's position is unknown" end
    return tt.pos.x, tt.pos.y + 2, tt.pos.z
  end
  local steps = {
    stepUnload(dr, J, "Empty the drone first", true),
    stepLoad(dr, J, item, count),
    stepGo(dr, "Fly to " .. t.label, where, true),        -- (its own Chunky keeps it loaded)
    { text = "Put the fuel into " .. t.label, fn = function()
        local tt = state.turtles[tid]
        if not (tt and TT.online(tt)) then return false, "the turtle went offline" end
        return act(dr, "pneumaticcraft:inventory_export", { { x = tt.pos.x, y = tt.pos.y, z = tt.pos.z } })
      end },
    stepUnload(dr, J, "Bring back what is left"),
  }
  local ok, err = submit(dr, "Fuel for " .. t.label, steps, { kind = "fuel", id = t.id, J = J, item = item })
  if not ok then return false, err end
  DW.runs[t.id] = { t = now(), state = "flying", why = why }
  TT.log(t, "A drone brings it fuel (" .. count .. " " .. prettify(item) .. ")")
  return true, dr.label .. " brings " .. count .. " " .. prettify(item) .. " to " .. t.label
end

-- automatic: a turtle with NO FUEL for 30 s (online - its chunk is loaded) gets a drone run
-- (max 3 tries per turtle, 10 min apart; the rescuer takes over after that)
function DW.fuelTick()
  for id, r in pairs(DW.runs) do
    local t = state.turtles[id]
    if r.state == "delivered" and t then
      if not r.burnAsked then
        -- (a turtle that can still get home does not burn carried fuel by itself: tell it to)
        r.burnAsked = true
        TT.send(id, "refuel", {}, true)
      end
      local need = t.dwWant and TT.surveyFuelNeed(t) or 20
      if (tonumber(t.fuel) or 0) >= need and not t.fuelShort then
        DW.runs[id] = nil
        t.dwWant = nil
        t.dwTries = nil
        TT.log(t, "Fuel from the drone burned - " .. tostring(t.fuel) .. " fuel")
        pushNote("DONE", "A drone brought fuel to " .. t.label .. " - it has " .. tostring(t.fuel) .. " now", C.good)
      elseif now() - r.doneAt > 180 then
        DW.runs[id] = nil
        if t.dwWant then t.dwWant, t.dwEdgeFail = nil, now() end     -- (next time: the trip home)
        pushNote("WARNING", "A drone brought fuel to " .. t.label .. " but it did not burn it (full inventory? old program?)", C.warn)
      end
    elseif r.state == "failed" and t and t.dwWant then
      t.dwWant, t.dwEdgeFail = nil, now()                              -- the trip home instead
      DW.runs[id] = nil
    elseif r.state == "failed" and now() - r.t > 600 then
      DW.runs[id] = nil
    end
  end
  if not DW.autoOn() or DW.notReady() or DW.yielding() then return end
  for _, t in pairs(state.turtles) do
    local fuel = tonumber(t.fuel)
    if TT.online(t) and fuel and (fuel < 20 or t.fuelShort or t.dwWant) and not t.missing and not t.dups and t.pos and t.pos.x then
      t.dwLowSince = t.dwLowSince or now()
      local wait = t.dwWant and 10 or 30
      if now() - t.dwLowSince > wait and not DW.runs[t.id] and (t.dwTries or 0) < 3
         and now() - (t.dwTryAt or -9999) > (t.dwWant and 60 or 600) and DW.freeDrone() then
        t.dwTries, t.dwTryAt = (t.dwTries or 0) + 1, now()
        local ok, why = DW.fuelRun(t.id, "auto", t.dwWant or t.fuelShort)
        if not ok then
          TT.log(t, "No drone fuel run: " .. tostring(why))
          if t.dwWant then t.dwWant, t.dwEdgeFail = nil, now() end   -- the trip home instead
        end
        return
      end
    else
      t.dwLowSince = nil
    end
  end
end

------------------------------------------------------------------ gifts
-- (the talking base, voice_talk2.lua: friendship rewards) a drone brings `count` PLAIN `item`s from AE2
-- (never your own: FACTORY.variants via the work chest) to a player AT THE BASE and drops them right
-- next to them (Drop Item, straight down). still(name) = is the player still at the base (else the trip
-- stops - it never chases anyone across the world). cb(ok, delivered, why) when the trip is over.
local function playerAt(name)
  for _, e in ipairs(state.players or {}) do
    if tostring(e.name):lower() == tostring(name):lower() and e.p and tonumber(e.p.x) then
      if e.dim and DRONE_DIM and e.dim ~= DRONE_DIM then return nil, tostring(name) .. " is in another dimension" end
      return e.p
    end
  end
  return nil, "cannot see where " .. tostring(name) .. " is"
end
DW.playerAt = playerAt
function DW.giftRun(name, item, count, cb, still)
  local bad = DW.notReady()
  if bad then return false, bad end
  local p0, why = playerAt(name)
  if not p0 then return false, why end
  local dr, whyD = DW.freeDrone(function(d) return DW.airFor(d, p0.x, p0.z) end)
  if not dr then return false, "no free drone (" .. tostring(whyD) .. ")" end
  count = math.max(1, math.min(math.floor(tonumber(count) or 1), DW.slots(dr) * 64))
  local J = { kind = "gift" }
  -- still(name) -> false[, why]: the trip stops (nothing dropped) - "left the base" / "went offline" ...
  local function here()
    if still then
      local okS, whyS = still(name)
      if not okS then return nil, whyS or (tostring(name) .. " left the base") end
    end
    return playerAt(name)
  end
  local steps = {
    stepUnload(dr, J, "Empty the drone first", true),
    stepLoad(dr, J, item, count),
    stepGo(dr, "Fly to " .. name, function()
      local p, w = here()
      if not p then return nil, w end
      return math.floor(p.x), math.floor(p.y) + 3, math.floor(p.z)
    end, true),
    { text = "Drop the gift next to " .. name, fn = function()
        local p, w = here()
        if not p then return false, w end
        local d = dr.periph
        return droneDo(dr, "pneumaticcraft:drop_item", function()
          d.clearArea()
          d.addArea(math.floor(p.x), math.floor(p.y) + 1, math.floor(p.z))
          if d.clearWhitelistItemFilter then pcall(d.clearWhitelistItemFilter) end
          if d.setUseCount then pcall(d.setUseCount, false) end
          if d.setDropStraight then pcall(d.setDropStraight, true) end
        end, 1, 30)
      end },
    stepUnload(dr, J, "Bring back what is left"),
  }
  local ok, err = submit(dr, "Gift for " .. name, steps, { kind = "gift", who = name, item = item, J = J, cb = cb })
  if not ok then return false, err end
  DW.wanted = nil
  return true, dr.label .. " brings " .. count .. " " .. prettify(item) .. " to " .. name
end

------------------------------------------------------------------ testing the work chest
-- (the owner: "how do I test the drone chest") `dw test [item]`: 1) the checks + one PLAIN item
-- AE2 -> work chest -> AE2 (the base's side), 2) when you stand near the chest: a drone takes one
-- out of the chest and drops it at your feet (the drone's side - the chest's position, its reach).
-- say(line) prints; the drone part ends with a DONE / WARNING note. Returns true when it got that far.
DW.TEST_ITEMS = { "minecraft:cobblestone", "minecraft:dirt", "minecraft:stone", "minecraft:cobbled_deepslate",
                  "minecraft:oak_planks", "minecraft:coal", "minecraft:torch" }
-- tell(msg): the drone part's result also goes there (chat: `$drone test` at the chest - the console
-- may be far away); again = the command to type again ("dw test" / "$drone test").
function DW.test(say, item, tell, again)
  say = say or function() end
  again = again or "dw test"
  local bad = DW.notReady()
  if bad then say("NOT READY: " .. bad) return false end
  local c = DW.chestName()
  local x, y, z = DW.chestAt()
  say("Work chest: " .. c .. " at " .. x .. " " .. y .. " " .. z)
  local inside = chestCount()
  if inside > 0 then say("  note: it holds " .. inside .. " item(s) already - keep it EMPTY (they go to AE2 on the next trip)") end
  local home = CONFIG.drone and CONFIG.drone.home
  if type(home) == "table" and tonumber(home.x) then
    local d = math.floor(math.sqrt((x - home.x) ^ 2 + (y - home.y) ^ 2 + (z - home.z) ^ 2))
    say("  " .. d .. " blocks from the drones' home" .. (d > 64 and " - far: the drones must fly / teleport there each trip" or ""))
  end
  -- 1) AE2 -> chest -> AE2
  if not item then
    for _, it in ipairs(DW.TEST_ITEMS) do
      local okV, plain = pcall(FACTORY.variants, it)
      if okV and (plain or 0) > 0 then item = it break end
    end
  end
  if not item then say("No test item in AE2 (cobblestone, dirt, stone ...) - name one:  " .. again .. " <item>") return false end
  local holder = DW.chestBy and drones[DW.chestBy]
  if holder and holder.busy then say("A drone is loading at the work chest right now - type  " .. again .. "  again in a moment") return false end
  local n, why = DW.giveToChest(item, 1)
  if n <= 0 then say("FAILED: AE2 -> work chest: " .. tostring(why)) return false end
  local got = chestCount(item)
  say("  OK: AE2 put 1 " .. prettify(item) .. " into the work chest" .. (got >= 1 and "" or " (but the chest does not show it!)"))
  local back = DW.chestToAE2()
  local nb = 0
  for _, v in pairs(back) do nb = nb + v end
  if nb <= 0 then say("FAILED: work chest -> AE2: nothing went back (is the ME Bridge allowed to take from it?)") return false end
  say("  OK: it went back into AE2")
  -- 2) the drone
  local owner = knownOwner and knownOwner() or state.owner
  local p = owner and DW.playerAt(owner)
  local function near(pp) return pp and math.abs(pp.x - x) <= 48 and math.abs(pp.z - z) <= 48 and math.abs(pp.y - y) <= 32 end
  if not near(p) then
    say("The base side works. For the DRONE part stand within 48 blocks of the work chest and type  " .. again .. "  again")
    say("(a drone then takes 1 " .. prettify(item) .. " out of the chest and drops it at your feet).")
    return true
  end
  local ok, msg = DW.giftRun(owner, item, 1, function(done, delivered, w)
    local m
    if done then
      m = "DRONE TEST: it works - the drone took " .. delivered .. " " .. prettify(item) ..
          " out of the work chest and dropped it next to you"
      pushNote("DONE", m, C.good)
    else
      m = "DRONE TEST: the drone trip did not work: " .. tostring(w or "?") ..
          " - wrong spot? Look at the chest, F3 shows Targeted Block: x y z, then type  $drone workchest x y z"
      pushNote("WARNING", m, C.warn)
    end
    if tell then pcall(tell, m) end
  end, function() return near(DW.playerAt(owner)) end)
  if not ok then say("FAILED: no drone trip: " .. tostring(msg)) return false end
  say("  " .. msg .. " - watch it: it flies to the chest, takes it, comes to you and drops it.")
  say("  You get a message when it is over (DRONE TEST ...).")
  return true
end

------------------------------------------------------------------ schematic build
-- WHERE IT GOES AND WHICH WAY IT FACES (the owner: "make it intuitive - if I want to rotate a schematic in a direction"):
--   * TURN = quarter turns CLOCKWISE seen from above (90 = turned right once). "facing east" = the side that was NORTH
--     in the file now faces east (= 90); north 0, east 90, south 180, west 270.
--   * IN FRONT OF YOU ("here" / me / no place): it stands on the ground in front of you, in the direction you LOOK,
--     centred on you, its near edge 2 blocks ahead, its bottom layer where your feet are.
--   * a saved place / x y z = the GROUND block: the build stands ON it - its bottom layer one above - with that block
--     at its north-west corner, or in the middle with "centered".
DW.DIRS = { north = 0, east = 1, south = 2, west = 3, n = 0, e = 1, s = 2, w = 3 }
DW.DIRNAME = { [0] = "north", "east", "south", "west" }
-- the way a player looks (Player Detector yaw: 0 = south, 90 = west, 180 = north, 270 = east) -> 0..3 (N E S W)
function DW.lookDir(yaw)
  yaw = tonumber(yaw)
  if not yaw then return nil end
  yaw = yaw % 360
  if yaw >= 315 or yaw < 45 then return 2 elseif yaw < 135 then return 3 elseif yaw < 225 then return 0 end
  return 1
end
-- the footprint after turning: width (x), depth (z)
function DW.footprint(s, rot)
  local k = math.floor((tonumber(rot) or 0) / 90) % 4
  if k % 2 == 1 then return s.size.z, s.size.x end
  return s.size.x, s.size.z
end
-- the build's north-west bottom corner for a placement:
--   how = "front" (x y z = your feet, look = 0..3), "center" or "corner" (x y z = the ground block)
function DW.origin(s, rot, how, x, y, z, look)
  local w, d = DW.footprint(s, rot)
  if how == "front" then
    look = look or 2
    local ox, oz
    if look == 0 then ox, oz = x - math.floor(w / 2), z - 2 - (d - 1)
    elseif look == 2 then ox, oz = x - math.floor(w / 2), z + 2
    elseif look == 1 then ox, oz = x + 2, z - math.floor(d / 2)
    else ox, oz = x - 2 - (w - 1), z - math.floor(d / 2) end
    return ox, y, oz
  elseif how == "center" then
    return x - math.floor(w / 2), y + 1, z - math.floor(d / 2)
  end
  return x, y + 1, z
end
-- "from 100 64 200 to 111 71 209" for a placement
function DW.areaText(s, rot, ox, oy, oz)
  local w, d = DW.footprint(s, rot)
  return "from " .. fmtPos(ox, oy, oz) .. " to " .. fmtPos(ox + w - 1, oy + s.size.y - 1, oz + d - 1)
end
-- what TURN means in words
function DW.turnText(rot)
  local k = math.floor((tonumber(rot) or 0) / 90) % 4
  return ({ [0] = "as saved", "turned right", "turned around", "turned left" })[k] ..
         " (its north side faces " .. DW.DIRNAME[k] .. ")"
end
-- words -> a turn: "facing east", "turn right / left / around", "rot 90"; returns rot, the next index
function DW.turnWords(words, i, rot)
  local w, v = tostring(words[i] or ""):lower(), tostring(words[i + 1] or ""):lower()
  if (w == "facing" or w == "face") and DW.DIRS[v] then return DW.DIRS[v] * 90, i + 2 end
  if w == "turn" or w == "turned" then
    if v == "right" or v == "clockwise" then return ((rot or 0) + 90) % 360, i + 2 end
    if v == "left" then return ((rot or 0) + 270) % 360, i + 2 end
    if v == "around" or v == "back" then return ((rot or 0) + 180) % 360, i + 2 end
  end
  if (w == "rot" or w == "rotate") and tonumber(v) then return (math.floor(tonumber(v) / 90) * 90) % 360, i + 2 end
  return nil
end
-- blocks that HANG on others (torches, signs, buttons, ladders, rails, carpets, doors ...) are placed after all the
-- solid ones - placed first they had nothing to stick to and dropped as items
DW.LATE = { "torch", "_button", "lever", "_sign", "ladder", "banner", "rail", "_carpet", "pressure_plate", "redstone",
            "repeater", "comparator", "tripwire", "vine", "lantern", "_door", "_bed", "candle", "_head", "_skull", "_fan",
            "flower_pot", "sapling", "flower", "_trapdoor", "chain", "bell", "item_frame", "painting", "snow" }
-- blocks that FALL (sand, gravel, concrete powder, an anvil ...): placed only once every layer below is done - the
-- others may go into any layer side by side (a drone places a block in mid-air)
function DW.isGravity(item)
  local id = tostring(item):match(":(.+)$") or tostring(item)
  if id == "sand" or id == "red_sand" or id == "gravel" or id:find("concrete_powder", 1, true) or id:find("anvil", 1, true)
     or id == "dragon_egg" or id == "scaffolding" or id == "pointed_dripstone" or id:find("^suspicious_") then return true end
  return false
end
function DW.isLate(item)
  item = tostring(item)
  for _, w in ipairs(DW.LATE) do if item:find(w, 1, true) then return true end end
  return false
end

-- a placement from command words (console `schem build|preview`, chat `$drone build`): words[i..] =
-- [here|me | a saved place | x y z] [facing <dir> | turn left|right|around | rot <deg>] [centered|corner] [clear]
-- -> { rot, how, ox, oy, oz, clear, look, text } or nil, why. No place = in front of you.
function DW.where(s, words, i, who, rot)
  rot = tonumber(rot) or 0
  local w = tostring(words[i] or ""):lower()
  local how, x, y, z, look
  local OPT = { clear = true, centered = true, center = true, middle = true, corner = true, facing = true, face = true,
                turn = true, turned = true, rot = true, rotate = true }
  if w == "" or w == "here" or w == "me" or OPT[w] then
    local p, why = playerAt(who or state.owner)
    if not p then return nil, why end
    x, y, z = math.floor(p.x), math.floor((tonumber(p.y) or 64) + 0.001), math.floor(p.z)
    look, how = DW.lookDir(p.yaw) or 2, "front"
    if w == "here" or w == "me" then i = i + 1 end
  else
    local ni
    x, y, z, ni = posArg(words, i, who)
    if not x then return nil, y end
    how, i = "corner", ni
  end
  local clear = false
  while words[i] do
    local r, ni = DW.turnWords(words, i, rot)
    local o = tostring(words[i]):lower()
    if r then rot, i = r, ni
    else
      if o == "clear" then clear = true
      elseif (o == "centered" or o == "center" or o == "middle") and how ~= "front" then how = "center"
      elseif o == "corner" and how ~= "front" then how = "corner" end
      i = i + 1
    end
  end
  return DW.placeAt(s, rot, how, x, y, z, look, clear)
end
-- the placement for a spot (how / x y z / look as DW.origin) - also to TURN a waiting one where it was asked for
function DW.placeAt(s, rot, how, x, y, z, look, clear)
  local ox, oy, oz = DW.origin(s, rot, how, x, y, z, look)
  local wdt, dep = DW.footprint(s, rot)
  local where = (how == "front" and ("in front of you to the " .. DW.DIRNAME[look]))
                or (how == "center" and ("centred on " .. fmtPos(x, y, z))) or ("north-west corner on " .. fmtPos(x, y, z))
  local text = wdt .. " wide (x) x " .. dep .. " deep (z) x " .. s.size.y .. " high, " .. DW.turnText(rot) .. ", " .. where ..
               ": " .. DW.areaText(s, rot, ox, oy, oz)
  return { rot = rot, how = how, ox = ox, oy = oy, oz = oz, clear = clear, look = look, text = text, bx = x, by = y, bz = z }
end

-- the plan: every block to place { x y z item } bottom up (one item at a time per layer; blocks that hang on
-- others in a second round), and (clear) every spot the schematic says is air, top down
function DW.plan(s, ox, oy, oz, rot)
  local sx, sz = s.size.x, s.size.z
  rot = (math.floor((tonumber(rot) or 0) / 90)) % 4
  local function turn(dx, dz)
    if rot == 1 then return sz - 1 - dz, dx
    elseif rot == 2 then return sx - 1 - dx, sz - 1 - dz
    elseif rot == 3 then return dz, sx - 1 - dx end
    return dx, dz
  end
  local place, air, skipped = {}, {}, {}
  for _, b in ipairs(s.blocks) do
    local e = s.palette[b[4]]
    local dx, dz = turn(b[1], b[3])
    local p = { x = ox + dx, y = oy + b[2], z = oz + dz }
    if e and SCHEM.isAir(e) then
      air[#air + 1] = p
    elseif e then
      local it = SCHEM.itemOf(e)
      if it and it:find("_bucket", 1, true) then skipped[it] = (skipped[it] or 0) + 1     -- (fluids: not by drone)
      elseif it then p.item, p.late, p.grav = it, DW.isLate(it) or nil, DW.isGravity(it) or nil place[#place + 1] = p end
    end
  end
  local function ck(p) return math.floor(p.x / 16) * 100000 + math.floor(p.z / 16) end
  table.sort(place, function(a, b)
    if (a.late or false) ~= (b.late or false) then return not a.late end
    if a.y ~= b.y then return a.y < b.y end
    if a.item ~= b.item then return a.item < b.item end
    if ck(a) ~= ck(b) then return ck(a) < ck(b) end
    if a.x ~= b.x then return a.x < b.x end
    return a.z < b.z
  end)
  table.sort(air, function(a, b)
    if a.y ~= b.y then return a.y > b.y end
    if ck(a) ~= ck(b) then return ck(a) < ck(b) end
    if a.x ~= b.x then return a.x < b.x end
    return a.z < b.z
  end)
  return { place = place, air = air, skipped = skipped, top = oy + s.size.y }
end

-- (times on the os.clock are NOT saved: it starts at 0 again after a server restart - a build "waiting 5 min"
--  waited hours, the anchor's goto was never sent again)
DW.MEMORY_ONLY = { plan = true, waitUntil = true, anchorSent = true, short = true }
function DW.save()
  local J = DW.job
  if not J then pcall(fs.delete, dataPath(DW.FILE)) return end
  local keep = {}
  for k, v in pairs(J) do if not DW.MEMORY_ONLY[k] then keep[k] = v end end
  saveFileSafe(dataPath(DW.FILE), serialSmall(keep))
end
function DW.load()
  local t = readSafe(dataPath(DW.FILE))
  if type(t) == "table" and type(t.name) == "string" and type(t.done) == "string" and type(t.dug or "") == "string"
     and tonumber(t.x) and tonumber(t.y) and tonumber(t.z) and tonumber(t.rot or 0) then
    t.dug = t.dug or ""
    for k in pairs(DW.MEMORY_ONLY) do t[k] = nil end    -- (the plan is rebuilt from the schematic; old files had clock times)
    DW.job = t
  end
end

-- the plan of the running build (rebuilt from the schematic after a restart: same order). Never waits: a schematic
-- not in memory is read by the map worker (nil, "reading")
local function planOf(J)
  if J.plan then return J.plan end
  local s = SCHEM.get(J.name)
  if not s then
    local why = SCHEM.failed[J.name]
    if why then SCHEM.failed[J.name] = nil return nil, why end
    if SCHEM.wanted[J.name] or not SCHEM.request(J.name) then
      why = SCHEM.failed[J.name]
      if why then SCHEM.failed[J.name] = nil return nil, why end
      return nil, "reading", true
    end
    s = SCHEM.get(J.name)
  end
  local plan = DW.plan(s, J.x, J.y, J.z, J.rot)
  if not J.clear then plan.air = {} end          -- (as at the start: without clear the air spots are no work - the
                                                 --  check below "changed" EVERY build without clear after a restart)
  if #J.done ~= #plan.place or #J.dug ~= #plan.air then return nil, "the schematic " .. J.name .. " changed - start the build again" end
  J.plan = plan
  return plan
end
DW.planOf = planOf

-- what the build needs from AE2 now: { {item, need, have} } and the missing ones
function DW.materials(J)
  local plan = planOf(J)
  if not plan then return {}, {} end
  local need = {}
  for i, p in ipairs(plan.place) do
    if J.done:sub(i, i) == "0" then need[p.item] = (need[p.item] or 0) + 1 end
  end
  local rows, missing = {}, {}
  for item, n in pairs(need) do
    local have = bridge and (FACTORY.variants(item)) or 0
    rows[#rows + 1] = { item = item, need = n, have = have }
    if have < n then missing[#missing + 1] = rows[#rows] end
  end
  table.sort(rows, function(a, b) return a.need > b.need end)
  return rows, missing
end

-- AUTO-CRAFT THE MATERIALS (the owner: "can the stuff for schematics get auto crafted?"): what a running build still
-- needs and AE2 does not have, AE2 is asked to craft (only items it has a pattern for) - checked every 30 s; an item is
-- not asked for again while its craft runs (MEX job calculating / crafting) or for 10 min after a request. CONFIG.drone.
-- buildCraft (default on;  schem craft on|off). J.craft[item] = { n, at (epoch s), err }, J.noPattern[item] = true.
function DW.craftOn() return cfg("buildCraft", true) ~= false end
local function craftRunning(item)
  for _, k in ipairs((MEX and MEX.order) or {}) do
    local j = MEX.jobs[k]
    if j and j.name == item and not j.fluid and (j.state == "calculating" or j.state == "crafting"
       or (j.state == "requested" and os.clock() - (j.t or 0) < 600)) then return true end
  end
  return false
end
function DW.craftTick(J, force)
  J = J or DW.job
  if not J or not bridge or not DW.craftOn() then return 0 end
  local nowE = math.floor(os.epoch("utc") / 1000)
  if not force and nowE - (J.craftAt or 0) < 30 then return 0 end
  J.craftAt = nowE
  local _, missing = DW.materials(J)
  J.craft, J.noPattern = J.craft or {}, {}
  local asked = {}
  for _, m in ipairs(missing) do
    local short = m.need - m.have
    local c = J.craft[m.item]
    if short > 0 and not craftRunning(m.item) and (force or not c or nowE - (c.at or 0) > 600 or (c.at or 0) > nowE) then
      if FACTORY.meCraftable and FACTORY.meCraftable(m.item) then
        local ok, err = craftME(m.item, short)
        J.craft[m.item] = { n = short, at = nowE, err = (not ok) and tostring(err) or nil }
        if ok then asked[#asked + 1] = short .. " " .. prettify(m.item) end
      else
        J.noPattern[m.item] = true
      end
    end
  end
  if #asked > 0 then
    local msg = "Build " .. J.name .. ": asked AE2 to craft " .. table.concat(asked, ", ")
    pushNote("INFO", msg, C.info)
    if sysLog then sysLog(msg) end
    -- (an item that waited as "AE2 has none" is looked at again soon)
    for item in pairs(J.short or {}) do if J.craft[item] then J.short[item] = math.min(J.short[item], now() + 60) end end
  end
  return #asked
end

function DW.startBuild(name, x, y, z, rot, clear)
  if DW.job then return false, "a build is running (" .. DW.job.name .. ") -  schem stop  first" end
  local bad = DW.notReady()
  if bad then return false, bad end
  local s, why = SCHEM.load(name)
  if not s then return false, why end
  local plan = DW.plan(s, x, y, z, rot)
  if #plan.place == 0 and not (clear and #plan.air > 0) then return false, "nothing to place in " .. name end
  local J = { name = name, x = x, y = y, z = z, rot = tonumber(rot) or 0, clear = clear and true or false,
              done = string.rep("0", #plan.place), dug = string.rep("0", clear and #plan.air or 0),
              placed = 0, skippedN = 0, startedE = os.epoch("utc"), fails = 0 }
  if not clear then plan.air = {} end
  J.plan = plan
  DW.job = J
  DW.save()
  local _, missing = DW.materials(J)
  local msg = "Building " .. name .. " " .. DW.areaText(s, rot, x, y, z) .. ", " .. DW.turnText(rot) .. ": " .. #plan.place .. " blocks" ..
              (clear and (", " .. #plan.air .. " spots cleared first") or "")
  if #missing > 0 then
    local n = DW.craftTick(J, true)
    msg = msg .. " - " .. #missing .. " item(s) short in AE2" .. (n > 0 and (", " .. n .. " sent to AE2 to craft") or "") .. " (schem status)"
  end
  if sysLog then sysLog(msg) end
  return true, msg
end

local function anchorTurtle(J)
  return J.anchor and state.turtles[J.anchor]
end
local function releaseAnchor(J)
  local t = anchorTurtle(J)
  if t then
    t.dwAnchor = nil
    TT.send(t.id, "home", {}, true)
    TT.log(t, "Build anchor no longer needed - going home")
  end
  J.anchor = nil
end
function DW.stopBuild(why)
  local J = DW.job
  if not J then return false, "no build is running" end
  releaseAnchor(J)
  DW.job = nil
  DW.save()
  local msg = "Build of " .. J.name .. " " .. (why or "stopped") .. " - " .. J.placed .. " blocks placed"
  if sysLog then sysLog(msg) end
  return true, msg
end

-- is the chunk of x z loaded? a player close by, an online turtle in that chunk (its Chunky),
-- or the drones' home chunk
function DW.loaded(x, z)
  local cx, cz = math.floor(x / 16), math.floor(z / 16)
  for _, e in ipairs(state.players or {}) do
    local p = e.p
    -- (only players KNOWN to be in the overworld: a mining dimension uses the same x z)
    if p and p.x and not e.dimOther and e.dim == DRONE_DIM
       and math.abs(p.x - x) <= 64 and math.abs(p.z - z) <= 64 then return true, "player" end
  end
  for _, t in pairs(state.turtles) do
    if TT.online(t) and t.pos and t.pos.x and math.floor(t.pos.x / 16) == cx and math.floor(t.pos.z / 16) == cz then
      return true, "turtle", t
    end
  end
  local h = CONFIG.drone.home
  if h and math.floor(h.x / 16) == cx and math.floor(h.z / 16) == cz then return true, "home" end
  return false
end

-- the next trip: { kind = "dig", idx } or { kind = "place", item, idx } (one chunk, one layer)
-- busy = { dig = {[k] = true}, place = {...} }: spots another drone is on now (left out)
function DW.nextTrip(J, cap, busy)
  local plan = planOf(J)
  if not plan then return nil end
  busy = busy or {}
  local bd, bp = busy.dig or {}, busy.place or {}
  local function ck(p) return math.floor(p.x / 16) .. "," .. math.floor(p.z / 16) end
  for i = 1, #J.dug do
    if J.dug:sub(i, i) == "0" and not bd[i] then
      local p0, idx = plan.air[i], {}
      for k = i, #J.dug do
        local p = plan.air[k]
        if J.dug:sub(k, k) == "0" and not bd[k] and ck(p) == ck(p0) then idx[#idx + 1] = k end
        if #idx >= 64 then break end
      end
      return { kind = "dig", idx = idx, at = p0 }
    end
  end
  -- (still being cleared by another drone: nothing is placed before every dig is done)
  if J.dug:find("0", 1, true) then return nil end
  -- (an item AE2 could not give is left for J.short's 5 min - the rest of the build goes on; it stopped at that item)
  local short, waiting = J.short or {}, nil
  for i = 1, #J.done do
    if J.done:sub(i, i) == "0" and not bp[i] then
      local p0, idx = plan.place[i], {}
      if short[p0.item] and now() < short[p0.item] then
        waiting = waiting or {}
        waiting[p0.item] = true
      else
        for k = i, #J.done do
          local p = plan.place[k]
          if p.y ~= p0.y then break end
          if J.done:sub(k, k) == "0" and not bp[k] and p.item == p0.item and ck(p) == ck(p0) then idx[#idx + 1] = k end
          if #idx >= cap then break end
        end
        return { kind = "place", item = p0.item, idx = idx, at = p0, late = p0.late, grav = p0.grav }
      end
    end
  end
  if waiting then
    local names = {}
    for it in pairs(waiting) do names[#names + 1] = prettify(it) end
    table.sort(names)
    return nil, "only " .. table.concat(names, ", ") .. " left - AE2 has none (it looks again every 5 min)"
  end
end

local function mark(s, idx, n, ch)
  local b = {}
  for i = 1, #s do b[i] = s:sub(i, i) end
  for k = 1, math.min(n, #idx) do b[idx[k]] = ch end
  return table.concat(b)
end

-- the result of the finished trip
-- WHERE A BUILD TRIP'S TIME GOES (real seconds, averaged): the steps' own times (runMission ms.ms) + the load's parts
-- (waiting for the work chest / AE2 into the chest / the drone taking it) -> schem status
DW.stats = DW.stats or { n = 0 }
local function noteTimes(trip, m)
  local T = trip.J or {}
  local got = {}
  for _, st in ipairs((m and m.steps) or {}) do
    local t = tostring(st.text)
    local k = (t:find("^Empty") and "empty") or (t:find("^Get ") and "load") or (t:find("^Fly") and "fly")
              or ((t:find("^Place") or t:find("^Clear")) and "place") or (t:find("^Bring back") and "back") or nil
    if k and tonumber(st.ms) then got[k] = (got[k] or 0) + st.ms / 1000 end
  end
  if T.tWait then got.wait = T.tWait / 1000 end
  if T.tGive then got.give = T.tGive / 1000 end
  if T.tTake then got.take = T.tTake / 1000 end
  local S = DW.stats
  S.n = S.n + 1
  local a = (S.n == 1) and 1 or 0.25
  for k, v in pairs(got) do S[k] = S[k] and (S[k] + (v - S[k]) * a) or v end
  local total = 0
  for _, k in ipairs({ "empty", "load", "fly", "place", "back" }) do total = total + (got[k] or 0) end
  S.trip = S.trip and (S.trip + (total - S.trip) * a) or total
end
function DW.timesLine()
  local S = DW.stats
  if not S or (S.n or 0) == 0 then return nil end
  local function f(k) return string.format("%.0f", S[k] or 0) end
  return "Trip time (avg of " .. S.n .. "): " .. f("trip") .. " s = load " .. f("load") .. " s (chest wait " .. f("wait") ..
         ", AE2 -> chest " .. f("give") .. ", drone takes " .. f("take") .. "), fly " .. f("fly") .. ", place " .. f("place") ..
         ", back " .. f("back") .. ((S.empty or 0) >= 0.5 and (", empty first " .. f("empty")) or "")
end
local function tripDone(trip, dr)
  local m = dr and dr.mission
  local ok = m and m.state == "done"
  if not ok and dr then dr.dwEmpty = false end           -- (a failed trip may have left items in the drone)
  if (trip.kind == "dig" or trip.kind == "place") and m then pcall(noteTimes, trip, m) end
  local J, T = DW.job, trip.J
  if trip.kind == "gift" then
    -- delivered = what it carried minus what came back (a failed trip: nothing counted - the next
    -- trip's first step empties the drone into AE2 anyway)
    local back = T and T.back and T.back[trip.item] or 0
    local delivered = ok and math.max(0, ((T and T.carried) or 0) - back) or 0
    if trip.cb then pcall(trip.cb, ok and delivered > 0, delivered, ok and (delivered == 0 and "nothing was dropped" or nil) or (m and m.err)) end
    return
  end
  if trip.kind == "fuel" then
    local r = DW.runs[trip.id]
    if r then
      if ok then r.state, r.doneAt = "delivered", now()
      else r.state, r.why = "failed", m and m.err end
    end
    if not ok then
      local t = state.turtles[trip.id]
      if t then TT.log(t, "Drone fuel run failed: " .. tostring(m and m.err)) end
    end
    return
  end
  if not J then return end
  if not ok then
    J.fails = (J.fails or 0) + 1
    J.why = m and m.err or "the drone mission failed"
    -- low air / nothing in AE2: wait, not a failure of the build
    -- (low air: that drone charges - DW.airFor keeps it out; the others go on, no wait for the build)
    if tostring(J.why):find("Pressure too low", 1, true) then J.fails = J.fails - 1
    elseif T.missing then
      J.fails = J.fails - 1
      J.short = J.short or {}
      J.short[T.missing] = now() + 300            -- (that item waits; the next trip takes another one)
    else J.waitUntil = now() + 60 end
    if J.fails >= 5 then
      J.paused = "5 failed trips in a row - " .. tostring(J.why) .. " (schem resume)"
      pushNote("WARNING", "Drone build of " .. J.name .. " paused: " .. J.paused, C.warn)
    end
    DW.save()
    return
  end
  J.fails, J.why = 0, nil
  if J.short and trip.item then J.short[trip.item] = nil end
  if trip.kind == "dig" then
    J.dug = mark(J.dug, trip.idx, #trip.idx, "1")
  else
    local carried = T.carried or 0
    local back = (T.back or {})[trip.item] or 0
    local placed = math.max(0, math.min(carried, #trip.idx) - back)
    J.placed = J.placed + placed
    J.skippedN = J.skippedN + math.max(0, math.min(carried, #trip.idx) - placed)
    J.done = mark(J.done, trip.idx, carried, "1")
  end
  DW.save()
end

-- comms worker, every 2 s
function DW.tick()
  if state.page == "work" and now() - (DW.view.at or -999) > 10 then pcall(DW.refreshView) end
  -- trips that finished (every drone's own)
  for k, trip in pairs(DW.trips) do
    local dr = drones[trip.dr]
    if dr and (dr.busy or #(dr.queue or {}) > 0) and now() - trip.at < 3600 then
      -- still on it
    else
      DW.trips[k] = nil
      if DW.chestBy == k then DW.chestBy = nil end
      pcall(tripDone, trip, dr)
    end
  end
  DW.syncTrip()
  pcall(DW.fuelTick)
  local J = DW.job
  if J then pcall(DW.craftTick, J) end
  if not J or J.paused then return end
  -- as many build trips as there are free drones (each on its own spots)
  for _ = 1, math.max(1, #droneOrder) do
    if DW.job ~= J or J.paused or not DW.buildOne(J) then break end
  end
end

-- the lowest layer with a block still to place (or out with a drone) - nil when none
function DW.lowestOpen(J, plan, busy)
  local low = math.huge
  for i = 1, #J.done do
    local p = plan.place[i]
    if p and (J.done:sub(i, i) == "0" or (busy and busy.place[i])) and p.y < low then low = p.y end
  end
  return low
end
-- the build trips out now: busy spots, how many, their layer / kind / late
local function buildFlying()
  local busy, n, layer, kind, late, solid = { dig = {}, place = {} }, 0, nil, nil, false, false
  for _, t in pairs(DW.trips) do
    if t.kind == "dig" or t.kind == "place" then
      n = n + 1
      for _, k in ipairs(t.idx or {}) do busy[t.kind][k] = true end
      layer, kind = t.layer, t.kind
      if t.late then late = true else solid = true end
    end
  end
  return busy, n, layer, kind, late, solid
end

-- start ONE build trip on a free drone; true = started (another may follow this tick)
function DW.buildOne(J)
  if DW.yielding() then J.why = "a " .. DW.wanted.what .. " goes first" return false end
  if J.waitUntil and now() < J.waitUntil then return false end
  local plan, why, reading = planOf(J)
  if not plan then
    if reading then J.why = "reading the schematic " .. J.name .. " ..." else J.paused = tostring(why) end
    return false
  end
  local busy, flying, layer, fkind, flate, fsolid = buildFlying()
  local dr = DW.freeDrone(function(d) return DW.airFor(d, J.x, J.z) end)
  if not dr then if flying == 0 then J.why = "waiting for a free drone" end return false end
  local bad = DW.notReady()
  if bad then J.why = bad return false end
  -- (a group that must wait - a falling block above an open layer, a torch while walls are out - is passed over and the
  --  NEXT group tried: test1's gravel came before its salt in the plan and kept the free drone idle)
  local tr, waitWhy
  for _ = 1, 20 do
    tr, waitWhy = DW.nextTrip(J, DW.slots(dr) * 64, busy)
    if not tr then break end
    local blocked = flying > 0 and (tr.kind ~= fkind or (tr.kind == "dig" and tr.at.y ~= layer) or (tr.late and fsolid))
    if not blocked and tr.grav and DW.lowestOpen(J, plan, busy) < tr.at.y then blocked = true end
    if not blocked then break end
    for _, k in ipairs(tr.idx) do busy[tr.kind][k] = true end
    tr = nil
    waitWhy = "waiting"
  end
  if not tr and waitWhy == "waiting" then
    if flying == 0 then J.why = "falling blocks (sand, gravel ...) wait for the layer below - something there is short in AE2" end
    return false
  end
  if not tr and waitWhy then J.why = waitWhy return false end
  if not tr then
    if flying > 0 then return false end              -- (the last trips are still out - finished when they are back)
    local msg = "Drone build of " .. J.name .. " finished: " .. J.placed .. " blocks placed" ..
                (J.skippedN > 0 and (", " .. J.skippedN .. " spots were taken") or "")
    pushNote("DONE", msg, C.good)
    if sysLog then sysLog(msg) end
    DW.stopBuild("finished")
    return false
  end
  -- (SIDE BY SIDE - the owner's test1: 4 kinds in layer 1, 4 salt blocks in layer 2, "3 drones work, then 1 continues":
  --  placing goes on in ANY layer at once - a drone places a block in mid-air; clearing stays in one layer, top down;
  --  blocks that FALL wait for every layer below; blocks that hang - torches, doors - until every solid one is in.
  --  Checked in the loop above.)
  -- the chunk must be loaded: else a turtle goes there first and waits above the build
  local cx, cz = math.floor(tr.at.x / 16), math.floor(tr.at.z / 16)
  local loaded = DW.loaded(tr.at.x, tr.at.z)
  local a = anchorTurtle(J)
  if a and not TT.online(a) then a.dwAnchor = nil J.anchor = nil a = nil end
  if not loaded then
    if flying > 0 then return false end              -- (the anchor stays while drones work where it is)
    local gx, gy, gz = cx * 16 + 8, math.min(310, plan.top + 3), cz * 16 + 8
    if not a then
      local best, bd
      for _, id in ipairs(TT.available()) do
        local t = state.turtles[id]
        if (tonumber(t.fuel) or 0) > 2000 and not t.held then
          local d = math.abs(t.pos.x - gx) + math.abs(t.pos.z - gz)
          if not bd or d < bd then best, bd = t, d end
        end
      end
      if not best then J.why = "the site is not loaded and no free turtle (fuel > 2000) can go and keep it loaded" return false end
      a = best
      J.anchor, a.dwAnchor = a.id, true
      TT.log(a, "Goes to the drone build " .. J.name .. " to keep its chunk loaded")
    end
    if not J.anchorGoal or J.anchorGoal ~= cx .. "," .. cz or now() - (J.anchorSent or -999) > 300 then
      J.anchorGoal, J.anchorSent = cx .. "," .. cz, now()
      TT.send(a.id, "goto", { gx, gy, gz }, true)
    end
    J.why = a.label .. " is on its way to keep the build site loaded"
    return false
  end
  local _, by = DW.loaded(tr.at.x, tr.at.z)
  J.why = nil
  local T = {}
  local pts = {}
  if tr.kind == "dig" then
    for _, k in ipairs(tr.idx) do pts[#pts + 1] = plan.air[k] end
  else
    for _, k in ipairs(tr.idx) do pts[#pts + 1] = plan.place[k] end
  end
  local p0 = pts[1]
  local function site() return p0.x, plan.top + 2, p0.z end
  local steps = { stepUnload(dr, T, "Empty the drone first", true) }
  if tr.kind == "place" then steps[#steps + 1] = stepLoad(dr, T, tr.item, #pts) end
  steps[#steps + 1] = stepGo(dr, "Fly to the build site", site, true)
  if tr.kind == "dig" then
    steps[#steps + 1] = { text = "Clear " .. #pts .. " spots", fn = function()
      dr.dwEmpty = false
      return act(dr, "pneumaticcraft:dig", pts, 60 + 4 * #pts) end }
  else
    steps[#steps + 1] = { text = "Place " .. #pts .. " " .. prettify(tr.item), fn = function()
      local n = math.min(#pts, T.carried or #pts)
      local some = {}
      for k = 1, n do some[k] = pts[k] end
      return act(dr, "pneumaticcraft:place", some, 60 + 4 * n) end }
  end
  steps[#steps + 1] = stepUnload(dr, T, "Bring back what is left")
  tr.J, tr.layer = T, p0.y                         -- (tr.at becomes the start time in submit)
  local title = (tr.kind == "dig" and "Clear" or "Build") .. " " .. J.name .. " (layer " .. (p0.y - J.y + 1) .. ")"
  local ok, err = submit(dr, title, steps, tr)
  J.loadedBy = by
  if not ok then J.why = err return false end
  return true
end

------------------------------------------------------------------ the DRONE WORK page
-- what the page shows, read here (comms worker) - never peripheral / disk calls while drawing
DW.view = { cands = {}, schems = {}, fuels = {}, at = -999 }
DW.ui = { rot = 0, clear = false, at = 0 }       -- the page's choices (BUILD options)
function DW.refreshView()
  local v = { cands = {}, schems = {}, fuels = {}, at = now() }
  v.bad = DW.notReady()
  -- chests / barrels on the cable that can be the work chest: empty, <= 54 slots, not used
  for _, name in ipairs(peripheral.getNames()) do
    local okI, isI = pcall(peripheral.hasType, name, "inventory")
    if okI and isI and not name:find("drive", 1, true) then
      local okS, size = pcall(peripheral.call, name, "size")
      local used = FACTORY.reserved(name)
      if okS and tonumber(size) and tonumber(size) <= 54 and (not used or used == "drone work chest") then
        local okL, list = pcall(peripheral.call, name, "list")
        if name == DW.chestName() or (okL and type(list) == "table" and next(list) == nil) then v.cands[#v.cands + 1] = name end
      end
    end
  end
  table.sort(v.cands)
  -- fuels AE2 has (plain ones) for the FUEL button on the page
  local item = DW.fuelItem()
  local seen = {}
  for _, f in ipairs({ item, "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block", "minecraft:blaze_rod",
                       "minecraft:lava_bucket", CONFIG.factory and CONFIG.factory.fuel }) do
    if f and not seen[f] then
      seen[f] = true
      local okV, have = pcall(FACTORY.variants, f)
      if (okV and (tonumber(have) or 0) > 0) or f == item then v.fuels[#v.fuels + 1] = { name = f, have = okV and tonumber(have) or 0 } end
    end
  end
  local okL, list = pcall(SCHEM.list)
  local seen = {}
  for name in pairs(okL and list or {}) do seen[name] = true end
  for name in pairs(SCHEM.cache or {}) do seen[name] = true end      -- (just dropped / read)
  for name in pairs(seen) do v.schems[#v.schems + 1] = name end
  table.sort(v.schems)
  DW.view = v
end
-- the next work chest on the cable (the page's CHEST button)
function DW.nextChest()
  local c = DW.view.cands
  if #c == 0 then return false, "no EMPTY chest / barrel on the cable - put a wired modem on one (right-click it: red)" end
  local cur, pick = DW.chestName(), c[1]
  for i, n in ipairs(c) do if n == cur then pick = c[i % #c + 1] end end
  setSetting("drone.workChest", pick)
  DW.view.at = -999
  return true, "Work chest: " .. pick .. " - now stand ON it and tap BLOCK UNDER ME"
end
function DW.chestHere()
  if not DW.chestName() then return false, "pick the chest first (CHEST button)" end
  local x, y, z = playerBlock(state.owner)
  if not x then return false, "where are you? " .. tostring(y) end
  setSetting("drone.workChestAt", { x = x, y = y, z = z })
  DW.view.at = -999
  return true, "Work chest " .. DW.chestName() .. " at " .. fmtPos(x, y, z)
end
-- the page's FUEL buttons: the next fuel AE2 has / the next amount per run
DW.COUNTS = { 8, 16, 32, 64 }
function DW.nextFuel()
  local f = DW.view.fuels or {}
  if #f == 0 then return false, "AE2 has no fuel item (coal, charcoal, coal blocks, blaze rods, lava buckets)" end
  local cur, pick = DW.fuelItem(), f[1].name
  for i, e in ipairs(f) do if e.name == cur then pick = f[i % #f + 1].name end end
  setSetting("drone.fuelItem", pick)
  local _, n = DW.fuelItem()
  return true, "Fuel runs bring " .. n .. " " .. prettify(pick)
end
function DW.nextFuelCount()
  local _, n = DW.fuelItem()
  local pick = DW.COUNTS[1]
  for i, c in ipairs(DW.COUNTS) do if c == n then pick = DW.COUNTS[i % #DW.COUNTS + 1] end end
  setSetting("drone.fuelCount", pick)
  return true, "Fuel runs bring " .. pick .. " " .. prettify((DW.fuelItem()))
end
-- SAVE MY SPOT: the block under you as "Place N" (rename in chat:  $drone mark <name>)
function DW.markHere()
  local x, y, z = playerBlock(state.owner)
  if not x then return false, "where are you? " .. tostring(y) end
  local n = 1
  while findWaypoint("Place " .. n) do n = n + 1 end
  addWaypoint("Place " .. n, x, y, z)
  return true, "Saved Place " .. n .. " at " .. fmtPos(x, y, z) .. " (the block under you)"
end
-- a schematic picked on the page: its size + what it needs (AE2 read here, on the tap)
function DW.select(name)
  -- (tapped on the screen: a file not in memory is read by the map worker - unpacking a big one here froze the screen
  --  and could stop the computer; SCHEM.processPending calls this again when it is read)
  local s = SCHEM.get(name)
  if not s then
    local why = SCHEM.failed[name]
    if why then SCHEM.failed[name] = nil DW.sel = { name = name, err = why } return end
    SCHEM.request(name)
    s = SCHEM.get(name)
    if not s then
      why = SCHEM.failed[name] or (not SCHEM.wanted[name] and select(2, SCHEM.read(name)))
      if why then SCHEM.failed[name] = nil DW.sel = { name = name, err = tostring(why) } return end
      DW.sel = { name = name, err = "Reading " .. name .. " ...", reading = true }
      return
    end
  end
  local need, place, air, fluids = SCHEM.materials(s)
  local rows, short = {}, 0
  for it, n in pairs(need) do
    local have = bridge and (FACTORY.variants(it)) or 0
    rows[#rows + 1] = { item = it, need = n, have = have }
    if have < n then short = short + 1 end
  end
  table.sort(rows, function(a, b) return a.need > b.need end)
  -- the TOP VIEW for the preview: the highest block of every column (x, z as in the file)
  local top, topY = {}, {}
  for _, b in ipairs(s.blocks) do
    local e = s.palette[b[4]]
    if e and not SCHEM.isAir(e) and SCHEM.itemOf(e) then
      local k = b[3] * s.size.x + b[1] + 1
      if not topY[k] or b[2] > topY[k] then topY[k], top[k] = b[2], SCHEM.itemOf(e) end
    end
  end
  DW.sel = { name = name, size = s.size, place = place, air = air, rows = rows, short = short, top = top, fluids = fluids }
end
-- the item seen from above at a TURNED column (rx, rz) of the selected schematic, or nil
function DW.topAt(sel, rot, rx, rz)
  local sx, sz = sel.size.x, sel.size.z
  local k = math.floor((tonumber(rot) or 0) / 90) % 4
  local dx, dz = rx, rz
  if k == 1 then dx, dz = rz, sz - 1 - rx
  elseif k == 2 then dx, dz = sx - 1 - rx, sz - 1 - rz
  elseif k == 3 then dx, dz = sx - 1 - rz, rx end
  if dx < 0 or dz < 0 or dx >= sx or dz >= sz then return nil end
  return sel.top and sel.top[dz * sx + dx + 1]
end
-- where BUILD puts it (the page): 0 = in front of you (where you stand and look), else the n-th saved place (centred
-- on it). Returns the placement (DW.where) or nil, why
function DW.buildSpot(s)
  local i = DW.ui.at or 0
  if i > 0 then
    local w = state.waypoints[i]
    if w then return DW.where(s, { w.name, "centered" }, 1, state.owner, DW.ui.rot) end
    DW.ui.at = 0
  end
  return DW.where(s, {}, 1, state.owner, DW.ui.rot)
end

-- for the status lines (console / pocket)
function DW.statusLines()
  local out = {}
  local bad = DW.notReady()
  out[#out + 1] = "Work chest: " .. (DW.chestName() or "not set") ..
                  (DW.chestAt() and (" at " .. fmtPos(DW.chestAt())) or "") .. (bad and ("  - " .. bad) or "")
  local item, count = DW.fuelItem()
  out[#out + 1] = "Fuel runs: " .. (DW.autoOn() and "AUTO" or "off") .. " (" .. count .. " " .. prettify(item) .. " per run)"
  for id, r in pairs(DW.runs) do
    local t = state.turtles[id]
    out[#out + 1] = "  " .. (t and t.label or ("#" .. id)) .. ": " .. r.state .. (r.why and (" - " .. tostring(r.why)) or "")
  end
  for _, t in ipairs(DW.tripList()) do
    local dr = drones[t.dr]
    out[#out + 1] = "Now: " .. tostring(t.title) .. (dr and (" - " .. tostring(dr.label)) or "")
  end
  local J = DW.job
  if J then
    local left = 0
    for i = 1, #J.done do if J.done:sub(i, i) == "0" then left = left + 1 end end
    local dug = 0
    for i = 1, #J.dug do if J.dug:sub(i, i) == "1" then dug = dug + 1 end end
    out[#out + 1] = "Build " .. J.name .. " at " .. fmtPos(J.x, J.y, J.z) .. (J.rot ~= 0 and (" rot " .. J.rot) or "") ..
                    ": " .. J.placed .. " placed, " .. left .. " to go" .. (J.clear and (", cleared " .. dug .. "/" .. #J.dug) or "") ..
                    (J.skippedN > 0 and (", " .. J.skippedN .. " spots taken") or "")
    if J.paused then out[#out + 1] = "  PAUSED: " .. J.paused end
    local sh = {}
    for it, t in pairs(J.short or {}) do if now() < t then sh[#sh + 1] = prettify(it) end end
    if #sh > 0 then
      table.sort(sh)
      out[#out + 1] = "  AE2 has none of: " .. table.concat(sh, ", ") .. " - those spots wait, the rest goes on"
    end
    local cr, np = {}, {}
    local nowE = math.floor(os.epoch("utc") / 1000)
    for it, c in pairs(J.craft or {}) do
      cr[#cr + 1] = c.n .. " " .. prettify(it) .. (c.err and (" (refused: " .. c.err .. ")") or
                    (" (" .. math.max(0, math.floor((nowE - (c.at or nowE)) / 60)) .. " min ago)"))
    end
    for it in pairs(J.noPattern or {}) do np[#np + 1] = prettify(it) end
    table.sort(cr) table.sort(np)
    if not DW.craftOn() then out[#out + 1] = "  Auto-craft: OFF (schem craft on)"
    elseif #cr > 0 then out[#out + 1] = "  AE2 asked to craft: " .. table.concat(cr, ", ") end
    if #np > 0 then out[#out + 1] = "  No AE2 pattern for: " .. table.concat(np, ", ") .. " - add some to AE2 by hand" end
    if J.why then out[#out + 1] = "  " .. J.why end
    local tl = DW.timesLine()
    if tl then out[#out + 1] = "  " .. tl end
    local a = anchorTurtle(J)
    if a then out[#out + 1] = "  Keeping the site loaded: " .. a.label end
  end
  return out
end

DW.load()
