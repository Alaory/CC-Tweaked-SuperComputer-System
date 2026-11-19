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
DW.trip = nil                -- the mission running now: { kind, dr, J ... }
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

-- can the drones work at all? nil = yes, else why not
function DW.notReady()
  if not bridge then return "no ME Bridge" end
  local c = DW.chestName()
  if not c then return "no work chest - stand ON an empty chest on the cable and type  dw chest  (it lists them)" end
  if not peripheral.isPresent(c) then return "the work chest " .. c .. " is not on the cable" end
  if not DW.chestAt() then return "the work chest's position is not set -  dw chest " .. c .. " me  (standing ON it)" end
  if #droneOrder == 0 then return "no Drone Interface" end
end

-- a free drone: connected, nothing to do, nobody on board (CONFIG.drone.worker = its key / label)
function DW.freeDrone()
  local want = cfg("worker")
  for _, k in ipairs(droneOrder) do
    local dr = drones[k]
    if dr and dr.conn ~= false and not dr.gone and not dr.busy and #(dr.queue or {}) == 0 and not dr.rider
       and (not want or want == k or want == dr.label) then
      return dr
    end
  end
end

-- how many items one trip can carry: 1 slot + 1 per Inventory Upgrade (CONFIG.drone.slots wins)
function DW.slots(dr)
  local s = tonumber(cfg("slots"))
  if s then return math.max(1, math.floor(s)) end
  if dr.workSlots then return dr.workSlots end
  local n = 0
  local ok, up = pcall(dr.periph.getUpgrades)
  if ok and type(up) == "table" then
    for k, v in pairs(up) do
      local name, cnt = k, v
      if type(v) == "table" then name, cnt = v.name or v.id or k, v.count or v.amount or 1 end
      if tostring(name):lower():find("inventory", 1, true) and tonumber(cnt) then n = n + tonumber(cnt) end
    end
  end
  dr.workSlots = math.min(36, 1 + n)
  return dr.workSlots
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
local function act(dr, action, pts, limit)
  local d = dr.periph
  return droneDo(dr, action, function()
    d.clearArea()
    for _, p in ipairs(pts) do d.addArea(math.floor(p.x), math.floor(p.y), math.floor(p.z)) end
    if d.clearWhitelistItemFilter then pcall(d.clearWhitelistItemFilter) end
    if d.setUseCount then pcall(d.setUseCount, false) end
  end, 1, limit)
end
-- close by (CONFIG.drone.workFly, 64 blocks): FLY there - flying costs no air, a teleport ~0.85 bar
-- (a build trip goes chest -> site -> chest); further: the normal travel (teleport / hops)
local function goNear(dr, x, y, z, loaded)
  local px, py, pz = droneXYZ(dr)
  local r = tonumber(cfg("workFly", 64)) or 64
  if px and math.abs(px - x) <= r and math.abs(pz - z) <= r and math.abs(py - y) <= r then
    local ok, why = droneMoveTo(dr, "pneumaticcraft:goto", x, y, z, CONFIG.drone.travelTimeout)
    if ok then return true end
    if why == "stopped" or why == "the drone disconnected" then return false, why end
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
local function stepUnload(dr, J, text)
  return { text = text or "Empty the drone into the work chest", fn = function()
    local ok, why = toChest(dr)
    if not ok then return false, why end
    local x, y, z = DW.chestAt()
    ok, why = act(dr, "pneumaticcraft:inventory_export", { { x = x, y = y, z = z } })
    if not ok then return false, why end
    local back = DW.chestToAE2()
    J.back = J.back or {}
    for k, v in pairs(back) do J.back[k] = (J.back[k] or 0) + v end
    if chestCount() > 0 then return false, "the work chest is not empty (AE2 full?)" end
    return true
  end }
end
-- `want` of an item from AE2 -> the work chest -> the drone. J.carried = how many it holds
local function stepLoad(dr, J, item, want)
  return { text = "Get " .. want .. " " .. prettify(item) .. " from AE2", fn = function()
    if chestCount() > 0 then DW.chestToAE2() end
    if chestCount() > 0 then return false, "the work chest is not empty - only the base and the drones may use it" end
    local moved, why = DW.giveToChest(item, want)
    if moved <= 0 then J.missing = item return false, why end
    local ok, err = toChest(dr)
    if not ok then DW.chestToAE2() return false, err end
    local x, y, z = DW.chestAt()
    ok, err = act(dr, "pneumaticcraft:inventory_import", { { x = x, y = y, z = z } })
    local left = chestCount(item)
    if left > 0 then DW.chestToAE2() end           -- (more than it could carry: the rest goes back)
    J.carried = moved - left
    if not ok then return false, err end
    if J.carried <= 0 then return false, "the drone took nothing from the work chest (can it reach it? is its inventory full?)" end
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
  DW.trip = trip
  if not submitDrone(dr, { kind = "work", title = title, steps = steps }) then
    DW.trip = nil
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

function DW.fuelRun(id, why)
  local t = state.turtles[tonumber(id) or id]
  if not t then return false, "no turtle " .. tostring(id) end
  local bad = DW.notReady()
  if bad then return false, bad end
  if not TT.online(t) then return false, t.label .. " is offline - its chunk is not loaded (a rescue turtle has to go)" end
  if not (t.pos and t.pos.x) then return false, t.label .. "'s position is unknown" end
  if DW.trip then return false, "a drone job is running (" .. tostring(DW.trip.title) .. ")" end
  local dr = DW.freeDrone()
  if not dr then return false, "no free drone" end
  local item, count = DW.fuelItem()
  local J = { kind = "fuel", id = t.id }
  local tid = t.id
  local function where()
    local tt = state.turtles[tid]
    if not (tt and tt.pos and tt.pos.x) then return nil, "the turtle's position is unknown" end
    return tt.pos.x, tt.pos.y + 2, tt.pos.z
  end
  local steps = {
    stepUnload(dr, J, "Empty the drone first"),
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
      if (tonumber(t.fuel) or 0) >= 20 then
        DW.runs[id] = nil
        t.dwTries = nil
        TT.log(t, "Fuel from the drone burned - " .. tostring(t.fuel) .. " fuel")
        pushNote("DONE", "A drone brought fuel to " .. t.label .. " - it has " .. tostring(t.fuel) .. " now", C.good)
      elseif now() - r.doneAt > 180 then
        DW.runs[id] = nil
        pushNote("WARNING", "A drone brought fuel to " .. t.label .. " but it did not burn it (full inventory? old program?)", C.warn)
      end
    elseif r.state == "failed" and now() - r.t > 600 then
      DW.runs[id] = nil
    end
  end
  if not DW.autoOn() or DW.trip or DW.notReady() then return end
  for _, t in pairs(state.turtles) do
    local fuel = tonumber(t.fuel)
    if TT.online(t) and fuel and fuel < 20 and not t.missing and not t.dups and t.pos and t.pos.x then
      t.dwLowSince = t.dwLowSince or now()
      if now() - t.dwLowSince > 30 and not DW.runs[t.id] and (t.dwTries or 0) < 3
         and now() - (t.dwTryAt or -9999) > 600 and DW.freeDrone() then
        t.dwTries, t.dwTryAt = (t.dwTries or 0) + 1, now()
        local ok, why = DW.fuelRun(t.id, "auto")
        if not ok then TT.log(t, "No drone fuel run: " .. tostring(why)) end
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
  if DW.trip then return false, "a drone job is running (" .. tostring(DW.trip.title) .. ")" end
  local dr = DW.freeDrone()
  if not dr then return false, "no free drone" end
  local p0, why = playerAt(name)
  if not p0 then return false, why end
  count = math.max(1, math.min(math.floor(tonumber(count) or 1), DW.slots(dr) * 64))
  local J = { kind = "gift" }
  local function here()
    if still and not still(name) then return nil, tostring(name) .. " left the base" end
    return playerAt(name)
  end
  local steps = {
    stepUnload(dr, J, "Empty the drone first"),
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
  return true, dr.label .. " brings " .. count .. " " .. prettify(item) .. " to " .. name
end

------------------------------------------------------------------ schematic build
-- the plan: every block to place { x y z item } bottom up (one item at a time per layer),
-- and (clear) every spot the schematic says is air, top down
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
      elseif it then p.item = it place[#place + 1] = p end
    end
  end
  local function ck(p) return math.floor(p.x / 16) * 100000 + math.floor(p.z / 16) end
  table.sort(place, function(a, b)
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

function DW.save()
  local J = DW.job
  if not J then pcall(fs.delete, dataPath(DW.FILE)) return end
  local keep = {}
  for k, v in pairs(J) do if k ~= "plan" then keep[k] = v end end
  saveFileSafe(dataPath(DW.FILE), serialSmall(keep))
end
function DW.load()
  local t = readSafe(dataPath(DW.FILE))
  if type(t) == "table" and t.name and t.done then DW.job = t end
end

-- the plan of the running build (rebuilt from the schematic after a restart: same order)
local function planOf(J)
  if J.plan then return J.plan end
  local s, why = SCHEM.load(J.name)
  if not s then return nil, why end
  J.plan = DW.plan(s, J.x, J.y, J.z, J.rot)
  if #J.done ~= #J.plan.place or #J.dug ~= #J.plan.air then return nil, "the schematic " .. J.name .. " changed - start the build again" end
  return J.plan
end

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
  local msg = "Building " .. name .. " at " .. fmtPos(x, y, z) .. ": " .. #plan.place .. " blocks" ..
              (clear and (", " .. #plan.air .. " spots cleared first") or "")
  if #missing > 0 then msg = msg .. " - " .. #missing .. " item(s) short in AE2 (schem status)" end
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
function DW.nextTrip(J, cap)
  local plan = planOf(J)
  if not plan then return nil end
  local function ck(p) return math.floor(p.x / 16) .. "," .. math.floor(p.z / 16) end
  for i = 1, #J.dug do
    if J.dug:sub(i, i) == "0" then
      local p0, idx = plan.air[i], {}
      for k = i, #J.dug do
        local p = plan.air[k]
        if J.dug:sub(k, k) == "0" and ck(p) == ck(p0) then idx[#idx + 1] = k end
        if #idx >= 64 then break end
      end
      return { kind = "dig", idx = idx, at = p0 }
    end
  end
  for i = 1, #J.done do
    if J.done:sub(i, i) == "0" then
      local p0, idx = plan.place[i], {}
      for k = i, #J.done do
        local p = plan.place[k]
        if p.y ~= p0.y then break end
        if J.done:sub(k, k) == "0" and p.item == p0.item and ck(p) == ck(p0) then idx[#idx + 1] = k end
        if #idx >= cap then break end
      end
      return { kind = "place", item = p0.item, idx = idx, at = p0 }
    end
  end
end

local function mark(s, idx, n, ch)
  local b = {}
  for i = 1, #s do b[i] = s:sub(i, i) end
  for k = 1, math.min(n, #idx) do b[idx[k]] = ch end
  return table.concat(b)
end

-- the result of the finished trip
local function tripDone(trip, dr)
  local m = dr and dr.mission
  local ok = m and m.state == "done"
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
    if tostring(J.why):find("Pressure too low", 1, true) then J.fails = J.fails - 1 J.waitUntil = now() + 120
    elseif T.missing then J.fails = J.fails - 1 J.waitUntil = now() + 300
    else J.waitUntil = now() + 60 end
    if J.fails >= 5 then
      J.paused = "5 failed trips in a row - " .. tostring(J.why) .. " (schem resume)"
      pushNote("WARNING", "Drone build of " .. J.name .. " paused: " .. J.paused, C.warn)
    end
    DW.save()
    return
  end
  J.fails, J.why = 0, nil
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
  -- a trip finished?
  local trip = DW.trip
  if trip then
    local dr = drones[trip.dr]
    if dr and (dr.busy or #(dr.queue or {}) > 0) and now() - trip.at < 3600 then
      -- still on it
    else
      DW.trip = nil
      pcall(tripDone, trip, dr)
    end
  end
  pcall(DW.fuelTick)
  local J = DW.job
  if not J or DW.trip or J.paused then return end
  if J.waitUntil and now() < J.waitUntil then return end
  local plan, why = planOf(J)
  if not plan then J.paused = tostring(why) return end
  local dr = DW.freeDrone()
  if not dr then J.why = "waiting for a free drone" return end
  local bad = DW.notReady()
  if bad then J.why = bad return end
  local tr = DW.nextTrip(J, DW.slots(dr) * 64)
  if not tr then
    local msg = "Drone build of " .. J.name .. " finished: " .. J.placed .. " blocks placed" ..
                (J.skippedN > 0 and (", " .. J.skippedN .. " spots were taken") or "")
    pushNote("DONE", msg, C.good)
    if sysLog then sysLog(msg) end
    DW.stopBuild("finished")
    return
  end
  -- the chunk must be loaded: else a turtle goes there first and waits above the build
  local cx, cz = math.floor(tr.at.x / 16), math.floor(tr.at.z / 16)
  local loaded = DW.loaded(tr.at.x, tr.at.z)
  local a = anchorTurtle(J)
  if a and not TT.online(a) then a.dwAnchor = nil J.anchor = nil a = nil end
  if not loaded then
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
      if not best then J.why = "the site is not loaded and no free turtle (fuel > 2000) can go and keep it loaded" return end
      a = best
      J.anchor, a.dwAnchor = a.id, true
      TT.log(a, "Goes to the drone build " .. J.name .. " to keep its chunk loaded")
    end
    if not J.anchorGoal or J.anchorGoal ~= cx .. "," .. cz or now() - (J.anchorSent or -999) > 300 then
      J.anchorGoal, J.anchorSent = cx .. "," .. cz, now()
      TT.send(a.id, "goto", { gx, gy, gz }, true)
    end
    J.why = a.label .. " is on its way to keep the build site loaded"
    return
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
  local steps = { stepUnload(dr, T, "Empty the drone first") }
  if tr.kind == "place" then steps[#steps + 1] = stepLoad(dr, T, tr.item, #pts) end
  steps[#steps + 1] = stepGo(dr, "Fly to the build site", site, true)
  if tr.kind == "dig" then
    steps[#steps + 1] = { text = "Clear " .. #pts .. " spots", fn = function()
      return act(dr, "pneumaticcraft:dig", pts, 60 + 4 * #pts) end }
  else
    steps[#steps + 1] = { text = "Place " .. #pts .. " " .. prettify(tr.item), fn = function()
      local n = math.min(#pts, T.carried or #pts)
      local some = {}
      for k = 1, n do some[k] = pts[k] end
      return act(dr, "pneumaticcraft:place", some, 60 + 4 * n) end }
  end
  steps[#steps + 1] = stepUnload(dr, T, "Bring back what is left")
  tr.J = T
  local title = (tr.kind == "dig" and "Clear" or "Build") .. " " .. J.name .. " (layer " .. (p0.y - J.y + 1) .. ")"
  local ok, err = submit(dr, title, steps, tr)
  if not ok then J.why = err end
  J.loadedBy = by
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
  local s, why = SCHEM.load(name)
  if not s then DW.sel = { name = name, err = why } return end
  local need, place, air = SCHEM.materials(s)
  local rows, short = {}, 0
  for it, n in pairs(need) do
    local have = bridge and (FACTORY.variants(it)) or 0
    rows[#rows + 1] = { item = it, need = n, have = have }
    if have < n then short = short + 1 end
  end
  table.sort(rows, function(a, b) return a.need > b.need end)
  DW.sel = { name = name, size = s.size, place = place, air = air, rows = rows, short = short }
end
-- where BUILD puts it: 0 = the block under you, else the n-th saved place
function DW.buildSpot()
  local i = DW.ui.at or 0
  if i > 0 then
    local w = state.waypoints[i]
    if w then return w.x, w.y, w.z, w.name end
    DW.ui.at = 0
  end
  local x, y, z = playerBlock(state.owner)
  if not x then return nil, y end
  return x, y, z, "under you"
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
  if DW.trip then out[#out + 1] = "Now: " .. tostring(DW.trip.title) end
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
    if J.why then out[#out + 1] = "  " .. J.why end
    local a = anchorTurtle(J)
    if a then out[#out + 1] = "  Keeping the site loaded: " .. a.label end
  end
  return out
end

DW.load()
