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
DW.MEMORY_ONLY = { plan = true, waitUntil = true, anchorSent = true, anchorAt = true, short = true, againUntil = true, digWait = true }
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
    for k in pairs(DW.MEMORY_ONLY) do t[k] = nil end
    if t.kind == "drain" or t.kind == "dig" then
      if type(t.box) ~= "table" then return end
      for k = 1, 6 do if not tonumber(t.box[k]) then return end end
      if type(t.fill) ~= "string" then t.fill = nil end
    elseif t.kind ~= nil and t.kind ~= "unbuild" then return end
    -- (one turtle per chunk now: an older file kept ONE in t.anchor)
    local an = {}
    if type(t.anchors) == "table" then
      for ck, id in pairs(t.anchors) do if type(ck) == "string" and tonumber(id) then an[ck] = tonumber(id) end end
    end
    if tonumber(t.anchor) then an[type(t.anchorGoal) == "string" and t.anchorGoal or "old"] = tonumber(t.anchor) end
    t.anchors, t.anchor, t.anchorGoal = an, nil, nil
    for _, id in pairs(an) do if state.turtles[id] then state.turtles[id].dwAnchor = true end end
    local ag, an2 = {}, {}
    if type(t.again) == "table" then for k, v in pairs(t.again) do if tonumber(k) and tonumber(v) then ag[tonumber(k)] = tonumber(v) end end end
    if type(t.againN) == "table" then for k, v in pairs(t.againN) do if tonumber(k) and tonumber(v) then an2[tonumber(k)] = tonumber(v) end end end
    t.again, t.againN = ag, an2
    local dga = {}
    if type(t.digAgain) == "table" then for k, v in pairs(t.digAgain) do if tonumber(k) then dga[tonumber(k)] = 1 end end end
    t.digAgain = dga
    t.noDrops, t.dugGot = tonumber(t.noDrops), tonumber(t.dugGot)
    t.placed, t.skippedN, t.fails = tonumber(t.placed) or 0, tonumber(t.skippedN) or 0, tonumber(t.fails) or 0    -- (the plan is rebuilt from the schematic; old files had clock times)
    DW.job = t
  end
end

-- the plan of the running build (rebuilt from the schematic after a restart: same order). Never waits: a schematic
-- not in memory is read by the map worker (nil, "reading")
local function planOf(J)
  if J.plan then return J.plan end
  if J.kind == "drain" or J.kind == "dig" then
    local plan = J.kind == "dig" and DW.digPlan(J) or DW.drainPlan(J)
    if #J.done ~= #plan.place or #J.dug ~= #plan.air then return nil, "the clearing job changed - start it again" end
    J.plan = plan
    return plan
  end
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
  if J.kind == "unbuild" then
    local plan = DW.unbuildPlan(s, J)
    if #J.dug ~= #plan.air then return nil, "the schematic " .. J.name .. " changed - start taking it down again" end
    J.plan = plan
    return plan
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

------------------------------------------------------------------ CLEAR WATER / LAVA (make free space)
-- (the owner: "use a drone to clear an ocean out of water or the nether out of lava to make free space"): drones
-- cannot carry a sea away - so the box gets WALLS on its outer ring (they stay, every layer), the inside is FILLED with
-- a plain block (placing a block into water / lava removes the fluid), then the inside is DUG OUT top down (the blocks
-- go back into AE2 each trip). Everything inside the walls is dug - also the sea floor / terrain in the box. The top
-- of the box should be at the surface (water above it would flow in). Overworld only (the drones' dimension).
function DW.drainBox(J)
  local b = J.box
  return math.min(b[1], b[4]), math.min(b[2], b[5]), math.min(b[3], b[6]),
         math.max(b[1], b[4]), math.max(b[2], b[5]), math.max(b[3], b[6])
end
function DW.drainPlan(J)
  local x1, y1, z1, x2, y2, z2 = DW.drainBox(J)
  local item = J.fill or "minecraft:cobblestone"
  local place, air = {}, {}
  -- (everything is placed BOTTOM UP, a layer at a time - grav: a block over an open spot would shut the water below in,
  --  out of a drone's reach; the walls first in each layer)
  local function cols(y, inner, fn)
    for cx = math.floor(x1 / 16), math.floor(x2 / 16) do for cz = math.floor(z1 / 16), math.floor(z2 / 16) do
      for x = math.max(x1, cx * 16), math.min(x2, cx * 16 + 15) do for z = math.max(z1, cz * 16), math.min(z2, cz * 16 + 15) do
        local edge = x == x1 or x == x2 or z == z1 or z == z2
        if edge ~= inner then fn(x, y, z) end
      end end
    end end
  end
  for y = y1, y2 do
    cols(y, false, function(x, yy, z) place[#place + 1] = { x = x, y = yy, z = z, item = item, grav = true } end)
    cols(y, true, function(x, yy, z) place[#place + 1] = { x = x, y = yy, z = z, item = item, grav = true } end)
  end
  for y = y2, y1, -1 do                                        -- then the inside dug out - top down
    cols(y, true, function(x, yy, z) air[#air + 1] = { x = x, y = yy, z = z } end)
  end
  return { place = place, air = air, skipped = {}, top = y2 + 1 }
end
DW.DRAIN_MAX = 20000
function DW.startDrain(x1, y1, z1, x2, y2, z2, fill)
  if DW.job then return false, "a build is running (" .. DW.job.name .. ") -  schem stop  first" end
  local bad = DW.notReady()
  if bad then return false, bad end
  fill = fill or cfg("drainBlock") or "minecraft:cobblestone"
  if not fill:find(":", 1, true) then fill = "minecraft:" .. fill end
  if DW.isGravity(fill) or DW.isLate(fill) then return false, prettify(fill) .. " falls / hangs - take a plain block (cobblestone, dirt ...)" end
  local J = { kind = "drain", box = { x1, y1, z1, x2, y2, z2 }, fill = fill, rot = 0, clear = true, digLast = true,
              placed = 0, skippedN = 0, startedE = os.epoch("utc"), fails = 0 }
  local ax, ay, az, bx, by, bz = DW.drainBox(J)
  local w, h, d = bx - ax + 1, by - ay + 1, bz - az + 1
  if w < 3 or d < 3 then return false, "the box must be at least 3 x 3 (its outer ring becomes the walls)" end
  if w * h * d > (tonumber(cfg("drainMax")) or DW.DRAIN_MAX) then
    return false, "that box is " .. w * h * d .. " blocks - at most " .. (tonumber(cfg("drainMax")) or DW.DRAIN_MAX) ..
                  " in one job (clear it in parts)"
  end
  J.name = "clear " .. w .. "x" .. d .. "x" .. h
  J.x, J.y, J.z = ax, ay, az
  local plan = DW.drainPlan(J)
  J.done, J.dug, J.plan = string.rep("0", #plan.place), string.rep("0", #plan.air), plan
  DW.job = J
  DW.save()
  local msg = "Clearing " .. fmtPos(ax, ay, az) .. " to " .. fmtPos(bx, by, bz) .. " (" .. w .. " x " .. d .. " x " .. h ..
              "): walls round it, the inside filled with " .. prettify(fill) .. " (" .. #plan.place .. " blocks, they come back) " ..
              "and dug out top down - everything inside the walls goes"
  if sysLog then sysLog(msg) end
  if DW.craftTick then DW.craftTick(J, true) end
  return true, msg
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
  pcall(DW.noteBuilt, J)
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

------------------------------------------------------------------ TAKING THINGS DOWN
-- (the owner: "a way to break built schematics, and tell drones to clear an area or break a block"):
--   kind "dig"     = every block in a box (J.box), top down - `dw dig <corner> <corner>`, `dw break <spot>`
--   kind "unbuild" = every block a schematic put there (J.name x y z rot - the build it was), top down, one kind of
--                    block per trip: the drone brings them back into AE2. `schem unbuild [<n>|<name>]`
-- No placing (J.done = ""), only J.dug. Never the work chest, the drones' charger or their home spot.
function DW.isDigJob(J) return J ~= nil and (J.kind == "dig" or J.kind == "unbuild") end
function DW.jobWord(J)
  if not J then return "Build" end
  if J.kind == "dig" then return "Digging" elseif J.kind == "unbuild" then return "Taking down"
  elseif J.kind == "drain" then return "Clearing" end
  return "Build"
end
local function protected()
  local keep = {}
  local function add(p) if p and tonumber(p.x) then keep[math.floor(p.x) .. "," .. math.floor(p.y) .. "," .. math.floor(p.z)] = true end end
  local cx, cy, cz = DW.chestAt()
  if cx then add({ x = cx, y = cy, z = cz }) end
  add(CONFIG.drone.charger)
  add(CONFIG.drone.home)
  return keep
end
local function topDown(list)
  table.sort(list, function(a, b)
    if a.y ~= b.y then return a.y > b.y end
    local ca, cb = math.floor(a.x / 16) * 100000 + math.floor(a.z / 16), math.floor(b.x / 16) * 100000 + math.floor(b.z / 16)
    if ca ~= cb then return ca < cb end
    if (a.item or "") ~= (b.item or "") then return (a.item or "") < (b.item or "") end
    if a.x ~= b.x then return a.x < b.x end
    return a.z < b.z
  end)
  return list
end
function DW.digPlan(J)
  local x1, y1, z1, x2, y2, z2 = DW.drainBox(J)
  local keep, air = protected(), {}
  for y = y2, y1, -1 do for x = x1, x2 do for z = z1, z2 do
    if not keep[x .. "," .. y .. "," .. z] then air[#air + 1] = { x = x, y = y, z = z } end
  end end end
  return { place = {}, air = topDown(air), skipped = {}, top = y2 + 1 }
end
function DW.unbuildPlan(s, J)
  local p = DW.plan(s, J.x, J.y, J.z, J.rot)
  local keep, air = protected(), {}
  for _, q in ipairs(p.place) do
    if not keep[q.x .. "," .. q.y .. "," .. q.z] then air[#air + 1] = { x = q.x, y = q.y, z = q.z, item = q.item } end
  end
  return { place = {}, air = topDown(air), skipped = {}, top = p.top }
end
local function digJob(kind, name)
  return { kind = kind, name = name, rot = 0, clear = true, done = "", placed = 0, skippedN = 0,
           startedE = os.epoch("utc"), fails = 0 }
end
function DW.startDig(x1, y1, z1, x2, y2, z2, name)
  if DW.job then return false, "a job is running (" .. DW.job.name .. ") -  schem stop  first" end
  local bad = DW.notReady()
  if bad then return false, bad end
  local J = digJob("dig")
  J.box = { x1, y1, z1, x2, y2, z2 }
  local ax, ay, az, bx, by, bz = DW.drainBox(J)
  local w, h, d = bx - ax + 1, by - ay + 1, bz - az + 1
  local max = tonumber(cfg("drainMax")) or DW.DRAIN_MAX
  if w * h * d > max then return false, "that box is " .. w * h * d .. " blocks - at most " .. max .. " in one job (dig it in parts)" end
  J.name = name or (w * h * d == 1 and ("break " .. fmtPos(ax, ay, az)) or ("dig " .. w .. "x" .. d .. "x" .. h))
  J.x, J.y, J.z = ax, ay, az
  local plan = DW.digPlan(J)
  if #plan.air == 0 then return false, "nothing to dig there (the work chest, the charger and the drones' home are never dug)" end
  J.dug, J.plan = string.rep("0", #plan.air), plan
  DW.job = J
  DW.save()
  local msg = (w * h * d == 1 and ("Breaking the block at " .. fmtPos(ax, ay, az))
              or ("Digging " .. fmtPos(ax, ay, az) .. " to " .. fmtPos(bx, by, bz) .. " (" .. w .. " x " .. d .. " x " .. h ..
                  ", " .. #plan.air .. " spots), top down")) .. " - what the drones dig goes into AE2"
  if sysLog then sysLog(msg) end
  return true, msg
end
function DW.startUnbuild(name, x, y, z, rot)
  if DW.job then return false, "a job is running (" .. DW.job.name .. ") -  schem stop  first" end
  local bad = DW.notReady()
  if bad then return false, bad end
  local s, why = SCHEM.load(name)
  if not s then return false, why end
  local J = digJob("unbuild", name)
  J.x, J.y, J.z, J.rot = x, y, z, tonumber(rot) or 0
  local plan = DW.unbuildPlan(s, J)
  if #plan.air == 0 then return false, "nothing to take down in " .. name end
  J.dug, J.plan = string.rep("0", #plan.air), plan
  DW.job = J
  DW.save()
  local msg = "Taking down " .. name .. " " .. DW.areaText(s, J.rot, x, y, z) .. ": " .. #plan.air ..
              " blocks, top down - they go back into AE2"
  if sysLog then sysLog(msg) end
  return true, msg
end
-- the builds started here (newest first, 20): what `schem unbuild` can take down again - drone_built.dat
DW.BUILT_FILE = "drone_built.dat"
function DW.builtList()
  if not DW.built then
    DW.built = {}
    local t = readSafe(dataPath(DW.BUILT_FILE))
    if type(t) == "table" then
      for _, b in ipairs(t) do
        if type(b) == "table" and type(b.name) == "string" and tonumber(b.x) and tonumber(b.y) and tonumber(b.z) then
          DW.built[#DW.built + 1] = { name = b.name, x = tonumber(b.x), y = tonumber(b.y), z = tonumber(b.z),
                                      rot = tonumber(b.rot) or 0, at = tonumber(b.at) or 0 }
        end
        if #DW.built >= 20 then break end
      end
    end
  end
  return DW.built
end
function DW.noteBuilt(J)
  local l = DW.builtList()
  for i = #l, 1, -1 do
    local b = l[i]
    if b.name == J.name and b.x == J.x and b.y == J.y and b.z == J.z and b.rot == (J.rot or 0) then table.remove(l, i) end
  end
  table.insert(l, 1, { name = J.name, x = J.x, y = J.y, z = J.z, rot = J.rot or 0, at = math.floor(os.epoch("utc") / 1000) })
  while #l > 20 do table.remove(l) end
  pcall(saveFileSafe, dataPath(DW.BUILT_FILE), serialSmall(l))
end
function DW.forgetBuilt(J)
  local l = DW.builtList()
  for i = #l, 1, -1 do
    local b = l[i]
    if b.name == J.name and b.x == J.x and b.y == J.y and b.z == J.z then table.remove(l, i) end
  end
  pcall(saveFileSafe, dataPath(DW.BUILT_FILE), serialSmall(l))
end
-- "" (the newest) | "<n>" | "<name>" (its newest) -> the built entry
function DW.findBuilt(what)
  local l = DW.builtList()
  if not what or what == "" or what == "last" then return l[1] end
  if tonumber(what) then return l[tonumber(what)] end
  for _, b in ipairs(l) do if b.name:lower() == tostring(what):lower() then return b end end
end

------------------------------------------------------------------ the QUEUE + CHAINS (a road in pieces)
-- (the owner: "place a chain of structures one next to another - a road split into several schematic files"):
--   schem chain road1,road2*5,road3 [here|place|x y z] [toward <dir>] [turn ..|facing ..] [clear]
-- the first piece goes where a single build would; each next one right after the one before, toward the way you look
-- (or `toward <dir>`), centred on it; all turned the same way. Builds wait in DW.queue (dronequeue.dat) and start one
-- after another; a clearing job can wait there too. `schem queue [clear]`.
DW.queue = DW.queue or {}
DW.QFILE = "dronequeue.dat"
function DW.saveQueue()
  if #DW.queue == 0 then pcall(fs.delete, dataPath(DW.QFILE)) return end
  saveFileSafe(dataPath(DW.QFILE), serialSmall(DW.queue))
end
function DW.loadQueue()
  DW.queue = {}
  local t = readSafe(dataPath(DW.QFILE))
  if type(t) ~= "table" then return end
  for _, q in ipairs(t) do
    if type(q) == "table" and type(q.name) == "string" and tonumber(q.x) and tonumber(q.y) and tonumber(q.z) then
      local e = { name = q.name, x = tonumber(q.x), y = tonumber(q.y), z = tonumber(q.z), rot = tonumber(q.rot) or 0,
                  clear = q.clear and true or nil }
      if (q.kind == "drain" or q.kind == "dig") and type(q.box) == "table" and #q.box == 6 then
        local ok = true
        for k = 1, 6 do if not tonumber(q.box[k]) then ok = false end end
        if ok then e.kind, e.box, e.fill = q.kind, q.box, type(q.fill) == "string" and q.fill or nil end
      elseif q.kind == "unbuild" then e.kind = "unbuild" end
      if (q.kind ~= "drain" and q.kind ~= "dig") or e.kind then DW.queue[#DW.queue + 1] = e end
    end
  end
end
-- "road1,road2*3" -> { "road1", "road2", "road2", "road2" }
function DW.chainNames(spec)
  local out = {}
  for part in tostring(spec or ""):gmatch("[^,]+") do
    local nm, n = part:match("^(.-)%*(%d+)$")
    if not nm then nm, n = part, 1 end
    for _ = 1, math.min(tonumber(n) or 1, 200) do if #out < 400 then out[#out + 1] = nm end end
  end
  return out
end
DW.DIRNUM = { north = 0, n = 0, east = 1, e = 1, south = 2, s = 2, west = 3, w = 3 }
-- the pieces' places -> list, text  (nil, why)
function DW.chainPlan(spec, words, i, who)
  local names = DW.chainNames(spec)
  if #names == 0 then return nil, "no schematics named (road1,road2*5,road3)" end
  local w2, dir = {}, nil
  local j = 1
  while j <= #words do
    local lw = tostring(words[j]):lower()
    if j >= i and (lw == "toward" or lw == "towards" or lw == "along" or lw == "direction") then
      dir = DW.DIRNUM[tostring(words[j + 1] or ""):lower()]
      if not dir then return nil, "toward north | east | south | west" end
      j = j + 2
    else
      w2[#w2 + 1] = words[j]
      j = j + 1
    end
  end
  local cache = {}
  local function sch(n)
    if cache[n] then return cache[n] end
    local s0, why = SCHEM.load(n)
    if not s0 then return nil, tostring(n) .. ": " .. tostring(why) end
    cache[n] = s0
    return s0
  end
  local s1, why1 = sch(names[1])
  if not s1 then return nil, why1 end
  local pl, whyW = DW.where(s1, w2, i, who, 0)
  if not pl then return nil, whyW end
  dir = dir or (pl.how == "front" and pl.look) or nil
  if not dir then return nil, "which way does it go on? add  toward north | east | south | west" end
  local list = { { name = names[1], x = pl.ox, y = pl.oy, z = pl.oz, rot = pl.rot, clear = pl.clear } }
  local pw, pd = DW.footprint(s1, pl.rot)
  local px, pz = pl.ox, pl.oz
  for k = 2, #names do
    local s0, why = sch(names[k])
    if not s0 then return nil, why end
    local w, d = DW.footprint(s0, pl.rot)
    local x, z
    if dir == 1 then x, z = px + pw, pz + math.floor((pd - d) / 2)
    elseif dir == 3 then x, z = px - w, pz + math.floor((pd - d) / 2)
    elseif dir == 2 then x, z = px + math.floor((pw - w) / 2), pz + pd
    else x, z = px + math.floor((pw - w) / 2), pz - d end
    list[#list + 1] = { name = names[k], x = x, y = pl.oy, z = z, rot = pl.rot, clear = pl.clear }
    px, pz, pw, pd = x, z, w, d
  end
  local f = list[1]
  local text = #list .. " piece(s) toward " .. DW.DIRNAME[dir] .. ", " .. DW.turnText(pl.rot) .. ": from " ..
               fmtPos(f.x, f.y, f.z) .. " to " .. fmtPos(px + pw - 1, pl.oy, pz + pd - 1)
  return list, text
end
-- into the queue (the first starts now when nothing is being built)
function DW.enqueue(list)
  for _, q in ipairs(list) do DW.queue[#DW.queue + 1] = q end
  DW.saveQueue()
  DW.queueTick()
end
-- the next queued build when none runs (comms worker - never waits: a schematic not read yet is asked for)
function DW.queueTick()
  if DW.job or #DW.queue == 0 then return end
  local q = DW.queue[1]
  local ok, msg
  if q.kind == "drain" then
    ok, msg = DW.startDrain(q.box[1], q.box[2], q.box[3], q.box[4], q.box[5], q.box[6], q.fill)
  elseif q.kind == "dig" then
    ok, msg = DW.startDig(q.box[1], q.box[2], q.box[3], q.box[4], q.box[5], q.box[6])
  else
    if not SCHEM.get(q.name) then
      local why = SCHEM.failed[q.name]
      if why then SCHEM.failed[q.name] = nil ok, msg = false, why
      elseif SCHEM.wanted[q.name] or not SCHEM.request(q.name) then return end
      if ok == nil and not SCHEM.get(q.name) then return end
    end
    if ok == nil then
      if q.kind == "unbuild" then ok, msg = DW.startUnbuild(q.name, q.x, q.y, q.z, q.rot)
      else ok, msg = DW.startBuild(q.name, q.x, q.y, q.z, q.rot, q.clear) end
    end
  end
  table.remove(DW.queue, 1)
  DW.saveQueue()
  if not ok then
    pushNote("WARNING", "Queued build " .. q.name .. " not started: " .. tostring(msg), C.warn)
  elseif sysLog then sysLog("Next queued build: " .. tostring(msg) .. " (" .. #DW.queue .. " more waiting)") end
end

-- KEEPING THE SITE LOADED (the owner: "a turtle can only load the chunk it is in"): one turtle PER CHUNK that has work and
-- is not loaded - J.anchors = { ["cx,cz"] = turtle id }, at most one per drone. A turtle whose chunk is done moves on to
-- the next one (or goes home); all go home when the job ends.
function DW.anchorList(J)
  local out = {}
  for ck, id in pairs(J.anchors or {}) do
    local t = state.turtles[id]
    if t then out[#out + 1] = { ck = ck, t = t } end
  end
  table.sort(out, function(a, b) return a.ck < b.ck end)
  return out
end
local function releaseOne(J, ck, why)
  local id = (J.anchors or {})[ck]
  local t = id and state.turtles[id]
  if t then
    t.dwAnchor = nil
    TT.send(t.id, "home", {}, true)
    TT.log(t, why or "Build anchor no longer needed - going home")
  end
  if J.anchors then J.anchors[ck] = nil end
  if J.anchorAt then J.anchorAt[ck] = nil end
end
local function releaseAnchor(J)
  for ck in pairs(J.anchors or {}) do releaseOne(J, ck) end
  J.anchors, J.anchor = {}, nil
end
-- the chunks with work left (a spot still to do, or out with a drone)
local function openChunks(J, plan)
  local open = {}
  local function add(p) open[math.floor(p.x / 16) .. "," .. math.floor(p.z / 16)] = true end
  for i = 1, #J.done do if J.done:sub(i, i) == "0" and plan.place[i] then add(plan.place[i]) end end
  for i = 1, #J.dug do if J.dug:sub(i, i) == "0" and plan.air[i] then add(plan.air[i]) end end
  for _, t in pairs(DW.trips) do if t.at and type(t.box) == "table" then add({ x = t.box[1], z = t.box[3] }) end end
  return open
end
DW.openChunks = openChunks
-- a turtle for chunk cx cz (the build's top + 3, the chunk's middle) -> the text for J.why
function DW.anchorFor(J, plan, cx, cz)
  J.anchors = J.anchors or {}
  J.anchorAt = J.anchorAt or {}
  local ck = cx .. "," .. cz
  for k, id in pairs(J.anchors) do                       -- (gone offline: another one goes)
    local t = state.turtles[id]
    if not t or not TT.online(t) then
      if t then t.dwAnchor = nil end
      J.anchors[k], J.anchorAt[k] = nil, nil
    end
  end
  local a = J.anchors[ck] and state.turtles[J.anchors[ck]]
  if not a then
    local n = 0
    for _ in pairs(J.anchors) do n = n + 1 end
    if n >= math.max(1, #droneOrder) then
      -- (all out: one whose chunk is finished moves here)
      local open = openChunks(J, plan)
      for k, id in pairs(J.anchors) do
        if not open[k] then
          a = state.turtles[id]
          J.anchors[k], J.anchorAt[k] = nil, nil
          break
        end
      end
      if not a then return "waiting for a turtle keeping another chunk of the site loaded" end
    else
      local gx, gz = cx * 16 + 8, cz * 16 + 8
      local best, bd
      for _, id in ipairs(TT.available()) do
        local t = state.turtles[id]
        if t and t.pos and t.pos.x and (tonumber(t.fuel) or 0) > 2000 and not t.held and not t.dwAnchor then
          local d = math.abs(t.pos.x - gx) + math.abs(t.pos.z - gz)
          if not bd or d < bd then best, bd = t, d end
        end
      end
      if not best then return "the site is not loaded and no free turtle (fuel > 2000) can go and keep it loaded" end
      a = best
    end
    J.anchors[ck], a.dwAnchor = a.id, true
    TT.log(a, "Goes to the drone job " .. J.name .. " to keep chunk " .. ck .. " loaded")
  end
  if now() - (J.anchorAt[ck] or -999) > 300 then
    J.anchorAt[ck] = now()
    TT.send(a.id, "goto", { cx * 16 + 8, math.min(310, plan.top + 3), cz * 16 + 8 }, true)
  end
  return a.label .. " is on its way to keep part of the site loaded"
end
-- every 30 s: a turtle whose chunk has nothing left goes home
function DW.anchorTick(J)
  if not J.anchors or not next(J.anchors) then return end
  local plan = planOf(J)
  if not plan then return end
  local open = openChunks(J, plan)
  for ck in pairs(J.anchors) do
    if not open[ck] then releaseOne(J, ck, "Its chunk of the drone job is done - going home") end
  end
end
DW.DIG_WHY = "a claimed chunk where drones may not break blocks, no free block next to it for the drone, or a block " ..
            "that drops nothing without a pickaxe - the drone's log on the DRONES page says what it did"
function DW.dugCount(J)
  local n = 0
  for i = 1, #(J.dug or "") do if J.dug:sub(i, i) == "1" then n = n + 1 end end
  return n
end
function DW.stopBuild(why)
  local J = DW.job
  if not J then return false, "no build is running" end
  releaseAnchor(J)
  DW.job = nil
  DW.save()
  local msg = DW.isDigJob(J) and (DW.jobWord(J) .. " " .. J.name .. " " .. (why or "stopped") .. " - " .. DW.dugCount(J) .. " spots dug")
              or ("Build of " .. J.name .. " " .. (why or "stopped") .. " - " .. J.placed .. " blocks placed")
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
  -- (a trip's spots are in ONE 8 x 8 square of one chunk - compact, so two drones can work squares apart: DW.tooClose)
  local function ck(p) return math.floor(p.x / 8) .. "," .. math.floor(p.z / 8) end
  local digWait = J.digWait and now() < J.digWait
  local dag = J.digAgain or {}
  local digWaiting = false
  local function digTrip()
    for i = 1, #J.dug do
      if digWait and dag[i] and J.dug:sub(i, i) == "0" and not bd[i] then digWaiting = true end
      if J.dug:sub(i, i) == "0" and not bd[i] and not (digWait and dag[i]) then
        local p0, idx = plan.air[i], {}
        for k = i, #J.dug do
          local p = plan.air[k]
          if p.y ~= p0.y then break end                      -- (one layer: top down)
          if J.dug:sub(k, k) == "0" and not bd[k] and not (digWait and dag[k]) and ck(p) == ck(p0) and p.item == p0.item then
            idx[#idx + 1] = k
          end
          if #idx >= 64 then break end
        end
        return { kind = "dig", idx = idx, at = p0 }
      end
    end
  end
  -- (a CLEARING job - J.digLast - fills first and digs after: below; a build clears first)
  if not J.digLast then
    local t = digTrip()
    if t then return t end
    if digWaiting then return nil, "the drone brought nothing back - trying those spots again in a moment" end
    -- (still being cleared by another drone: nothing is placed before every dig is done)
    if J.dug:find("0", 1, true) then return nil end
  end
  -- (an item AE2 could not give is left for J.short's 5 min - the rest of the build goes on; it stopped at that item)
  local short, waiting = J.short or {}, nil
  -- (spots that refused a block wait J.againUntil before the 2nd try - the drone in the way has moved on by then)
  local ag, againWait = J.again or {}, J.againUntil and now() < J.againUntil
  local retryWait = false
  for i = 1, #J.done do
    if againWait and ag[i] and J.done:sub(i, i) == "0" and not bp[i] then retryWait = true end
    if J.done:sub(i, i) == "0" and not bp[i] and not (againWait and ag[i]) then
      local p0, idx = plan.place[i], {}
      if short[p0.item] and now() < short[p0.item] then
        waiting = waiting or {}
        waiting[p0.item] = true
      elseif ag[i] then
        -- (a 2nd try: only that trip's spots, only as many blocks as came back - a filled spot refuses, the drone
        --  puts them into the free ones)
        local g = ag[i]
        for k = i, #J.done do
          if ag[k] == g and J.done:sub(k, k) == "0" and not bp[k] then idx[#idx + 1] = k end
        end
        return { kind = "place", item = p0.item, idx = idx, at = p0, late = p0.late, grav = p0.grav, group = g,
                 want = math.max(1, math.min(#idx, (J.againN or {})[g] or #idx)) }
      else
        for k = i, #J.done do
          local p = plan.place[k]
          if p.y ~= p0.y then break end
          if J.done:sub(k, k) == "0" and not bp[k] and not ag[k] and p.item == p0.item and ck(p) == ck(p0) then
            idx[#idx + 1] = k
          end
          if #idx >= cap then break end
        end
        return { kind = "place", item = p0.item, idx = idx, at = p0, late = p0.late, grav = p0.grav }
      end
    end
  end
  if retryWait then return nil, "a few spots refused their block (a drone or a mob in the way?) - trying them again soon" end
  if waiting then
    local names = {}
    for it in pairs(waiting) do names[#names + 1] = prettify(it) end
    table.sort(names)
    return nil, "only " .. table.concat(names, ", ") .. " left - AE2 has none (it looks again every 5 min)"
  end
  if J.digLast then
    if J.done:find("0", 1, true) then return nil end            -- (blocks still out with a drone: dig after)
    local t = digTrip()
    if not t and digWaiting then return nil, "the drone brought nothing back - trying those spots again in a moment" end
    return t
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
    -- (the owner: "I gave the drone the exact block to break and it did not break it" - the dig action ends "done" also
    --  when the drone could not get to the block or was not allowed to break it (a claimed chunk): a BREAK / TAKE-DOWN
    --  trip that brought NOTHING back gets one more try after 20 s, then it is counted as "nothing came back" and said)
    local got = 0
    for _, n in pairs(T.back or {}) do got = got + (tonumber(n) or 0) end
    J.dugGot = (J.dugGot or 0) + got
    local check = J.kind == "unbuild" or (J.kind == "dig" and #J.dug == 1)
    if check and got == 0 then
      J.digAgain = J.digAgain or {}
      local again = false
      for _, i in ipairs(trip.idx) do
        if not J.digAgain[i] then J.digAgain[i] = 1 again = true end
      end
      if again then
        J.digWait = now() + 20
        J.why = "the drone came back with nothing from " .. fmtPos(trip.at and trip.at.x or J.x, trip.at and trip.at.y or J.y,
                trip.at and trip.at.z or J.z) .. " - trying once more"
        DW.save()
        return
      end
      J.noDrops = (J.noDrops or 0) + #trip.idx
    end
    J.dug = mark(J.dug, trip.idx, #trip.idx, "1")
  else
    local carried = T.carried or 0
    local back = (T.back or {})[trip.item] or 0
    local tried = math.min(carried, #trip.idx)
    local placed = math.max(0, tried - back)
    J.placed = J.placed + placed
    -- (blocks that came back: their spot was taken - by a block already there, or by a DRONE / mob / player in the way
    --  for a moment. Which spot is not known: all of this trip's spots get ONE more try after 20 s - a filled one simply
    --  sends its block back again. A spot's 2nd try counts it as done.)
    J.again, J.againN = J.again or {}, J.againN or {}
    local b = {}
    for i = 1, #J.done do b[i] = J.done:sub(i, i) end
    if trip.group then                                    -- (the 2nd try: done, what came back again was really taken)
      for _, i in ipairs(trip.idx) do J.again[i] = nil b[i] = "1" end
      J.againN[trip.group] = nil
      J.skippedN = J.skippedN + back
    elseif back > 0 then
      J.againSeq = (tonumber(J.againSeq) or 0) + 1
      local g = J.againSeq
      for k = 1, tried do J.again[trip.idx[k]] = g end
      J.againN[g] = back
      J.againUntil = now() + 20
    else
      for k = 1, tried do b[trip.idx[k]] = "1" end
    end
    J.done = table.concat(b)
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
  if not DW.job and #DW.queue > 0 then pcall(DW.queueTick) end
  local J = DW.job
  if J then pcall(DW.craftTick, J) end
  if J and now() - (DW.anchorCheck or -999) > 30 then DW.anchorCheck = now() pcall(DW.anchorTick, J) end
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
  local boxes = {}
  for _, t in pairs(DW.trips) do
    if t.kind == "dig" or t.kind == "place" then
      n = n + 1
      if type(t.box) == "table" then boxes[#boxes + 1] = t.box end
      for _, k in ipairs(t.idx or {}) do busy[t.kind][k] = true end
      layer, kind = t.layer, t.kind
      if t.late then late = true else solid = true end
    end
  end
  return busy, n, layer, kind, late, solid, boxes
end
-- the box round a trip's spots {x1, y1, z1, x2, y2, z2}
function DW.boxOf(pts)
  local b
  for _, p in ipairs(pts) do
    if not b then b = { p.x, p.y, p.z, p.x, p.y, p.z }
    else
      b[1], b[2], b[3] = math.min(b[1], p.x), math.min(b[2], p.y), math.min(b[3], p.z)
      b[4], b[5], b[6] = math.max(b[4], p.x), math.max(b[5], p.y), math.max(b[6], p.z)
    end
  end
  return b
end
-- KEEPING APART (the owner: "a drone will try to place a block where another drone is standing"): a drone places from
-- the block next to its spot - two drones working closer than CONFIG.drone.buildGap (3) blocks get in each other's way
-- (a block cannot go where a drone is). Two trips' boxes must be that far apart on at least one axis.
function DW.gap() return math.max(1, tonumber(cfg("buildGap")) or 3) end
function DW.tooClose(a, b, gap)
  if not a or not b then return false end
  gap = gap or DW.gap()
  local far = 0
  for k = 1, 3 do
    local d = math.max(a[k] - b[k + 3], b[k] - a[k + 3])
    if d > far then far = d end
  end
  return far < gap
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
  local busy, flying, layer, fkind, flate, fsolid, boxes = buildFlying()
  local dr = DW.freeDrone(function(d) return DW.airFor(d, J.x, J.z) end)
  if not dr then if flying == 0 then J.why = "waiting for a free drone" end return false end
  local bad = DW.notReady()
  if bad then J.why = bad return false end
  -- (a group that must wait - a falling block above an open layer, a torch while walls are out - is passed over and the
  --  NEXT group tried: test1's gravel came before its salt in the plan and kept the free drone idle)
  -- (a chunk that is not loaded: a turtle is sent there and the group passed over - other chunks go on meanwhile)
  local tr, waitWhy, anchorWhy, digY, pts
  local gap = DW.gap()
  for _ = 1, 20 do
    tr, waitWhy = DW.nextTrip(J, DW.slots(dr) * 64, busy)
    if not tr then break end
    pts = {}
    for _, k in ipairs(tr.idx) do pts[#pts + 1] = (tr.kind == "dig" and plan.air or plan.place)[k] end
    tr.box = DW.boxOf(pts)
    if tr.kind == "dig" then digY = digY or tr.at.y end
    local blocked = flying > 0 and (tr.kind ~= fkind or (tr.kind == "dig" and tr.at.y ~= layer) or (tr.late and fsolid))
    if not blocked and tr.kind == "dig" and tr.at.y ~= digY then blocked = true end      -- (clearing: top down)
    if not blocked and tr.grav and DW.lowestOpen(J, plan, busy) < tr.at.y then blocked = true end
    if not blocked then
      for _, b in ipairs(boxes) do if DW.tooClose(tr.box, b, gap) then blocked = true break end end
    end
    if not blocked and not DW.loaded(tr.at.x, tr.at.z) then
      anchorWhy = DW.anchorFor(J, plan, math.floor(tr.at.x / 16), math.floor(tr.at.z / 16))
      blocked = true
    end
    if not blocked then break end
    for _, k in ipairs(tr.idx) do busy[tr.kind][k] = true end
    tr = nil
    waitWhy = "waiting"
  end
  if not tr and anchorWhy then
    if flying == 0 then J.why = anchorWhy end
    return false
  end
  if not tr and waitWhy == "waiting" then
    if flying == 0 then J.why = "falling blocks (sand, gravel ...) wait for the layer below - something there is short in AE2" end
    return false
  end
  if not tr and waitWhy then J.why = waitWhy return false end
  if not tr then
    if flying > 0 then return false end              -- (the last trips are still out - finished when they are back)
    local msg = DW.isDigJob(J) and ("Drones finished " .. DW.jobWord(J):lower() .. " " .. J.name .. ": " .. DW.dugCount(J) .. " spots dug" ..
                ((J.noDrops or 0) > 0 and (" - but " .. J.noDrops .. " of them brought NOTHING back: those blocks may still be " ..
                 "there (" .. DW.DIG_WHY .. ")") or ""))
                or ("Drone build of " .. J.name .. " finished: " .. J.placed .. " blocks placed" ..
                    (J.skippedN > 0 and (", " .. J.skippedN .. " spots were taken") or ""))
    if J.kind == "unbuild" then DW.forgetBuilt(J) end
    if (J.noDrops or 0) > 0 then pushNote("WARNING", msg, C.warn) else pushNote("DONE", msg, C.good) end
    if sysLog then sysLog(msg) end
    DW.stopBuild("finished")
    return false
  end
  -- (SIDE BY SIDE - the owner's test1: 4 kinds in layer 1, 4 salt blocks in layer 2, "3 drones work, then 1 continues":
  --  placing goes on in ANY layer at once - a drone places a block in mid-air; clearing stays in one layer, top down;
  --  blocks that FALL wait for every layer below; blocks that hang - torches, doors - until every solid one is in.
  --  Checked in the loop above.)
  local _, by = DW.loaded(tr.at.x, tr.at.z)
  J.why = nil
  local T = {}
  local p0 = pts[1]
  local function site() return p0.x, plan.top + 2, p0.z end
  local steps = { stepUnload(dr, T, "Empty the drone first", true) }
  if tr.kind == "place" then steps[#steps + 1] = stepLoad(dr, T, tr.item, tr.want or #pts) end
  steps[#steps + 1] = stepGo(dr, "Fly to the build site", site, true)
  if tr.kind == "dig" then
    steps[#steps + 1] = { text = "Clear " .. #pts .. " spots", fn = function()
      dr.dwEmpty = false
      return act(dr, "pneumaticcraft:dig", pts, 60 + 4 * #pts) end }
  else
    steps[#steps + 1] = { text = "Place " .. #pts .. " " .. prettify(tr.item), fn = function()
      local n = math.min(#pts, T.carried or #pts)
      local some = {}
      for k = 1, (tr.group and #pts or n) do some[k] = pts[k] end
      return act(dr, "pneumaticcraft:place", some, 60 + 4 * #some) end }
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
    if DW.isDigJob(J) then
      out[#out + 1] = DW.jobWord(J) .. " " .. J.name .. " at " .. fmtPos(J.x, J.y, J.z) .. ": " .. dug .. " of " .. #J.dug .. " spots dug"
    else
      out[#out + 1] = DW.jobWord(J) .. " " .. J.name .. " at " .. fmtPos(J.x, J.y, J.z) .. (J.rot ~= 0 and (" rot " .. J.rot) or "") ..
                      ": " .. J.placed .. " placed, " .. left .. " to go" .. (J.clear and (", cleared " .. dug .. "/" .. #J.dug) or "") ..
                      (J.skippedN > 0 and (", " .. J.skippedN .. " spots taken") or "")
    end
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
    for _, e in ipairs(DW.anchorList(J)) do
      out[#out + 1] = "  Keeping chunk " .. e.ck .. " loaded: " .. e.t.label .. (TT.online(e.t) and "" or " (offline)")
    end
  end
  for k, q in ipairs(DW.queue) do
    if k > 6 then out[#out + 1] = "  ... " .. (#DW.queue - 6) .. " more" break end
    out[#out + 1] = (k == 1 and "Waiting: " or "         ") .. k .. ". " .. q.name ..
                    (q.kind == "drain" and "" or (" at " .. fmtPos(q.x, q.y, q.z)))
  end
  return out
end

DW.load()
DW.loadQueue()
