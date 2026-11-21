-- DRONE TIMING MODEL (the owner: "the drones are slow" + "you know a server will have a low TPS"). Runs the REAL
-- mission code (runMission) against a drone that behaves like PneumaticCraft's (source, 1.21 branch,
-- EntityPathNavigateDrone + DroneEntity), counted in SERVER TICKS - a laggy server makes fewer ticks a second, but
-- every rule below is per tick, so ticks are what to save:
--   * teleport: a 120-tick warm-up (TELEPORT_TICKS), then it happens only if the spot is LOADED and free - else
--     nothing (the air is used anyway) and it keeps trying
--   * goto (fly): a path within PATH blocks = flies at SPEED blocks a tick (0.15 = no Speed Upgrades); no path ->
--     a teleport (the same 120 ticks)
--   * entity import: flies to the player, grabs; entity export: 10 ticks; a condition check: at once
--   * a computer call costs nothing (PneumaticCraft answers on the computer's thread)
-- DRONE_SIM.run(opt) -> { ticks, teleports, refused, flights, log }. opt: players {name = pos}, home, ground (Y of
-- the land), loadedR (blocks around a player / the base that are loaded), speed, mission (cmd), dest.
DRONE_SIM = {}
function DRONE_SIM.run(opt)
  local W = { pos = { x = opt.start.x, y = opt.start.y, z = opt.start.z }, P = opt.players, carry = nil, act = nil,
              tp = 0, refused = 0, flights = 0, flown = 0, log = {},
              air = opt.air or 10, vol = opt.volume or 12000 }   -- (bar; mL - PneumaticValues DRONE_VOLUME)
  local SPEED, PATH, LR = opt.speed or 0.15, opt.path or 64, opt.loadedR or 128
  local GROUND = opt.ground or 64
  local function loaded(p)
    if math.abs(p.x - opt.home.x) <= LR and math.abs(p.z - opt.home.z) <= LR then return true end
    for _, q in pairs(W.P) do
      if math.abs(p.x - q.x) <= LR and math.abs(p.z - q.z) <= LR then return true end
    end
    for _, q in ipairs(opt.loadedAt or {}) do
      if math.abs(p.x - q.x) <= LR and math.abs(p.z - q.z) <= LR then return true end
    end
    return false
  end
  local function free(p) return p.y > GROUND end
  local function d3(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
  local function tick() return math.floor(CLOCK * 20 + 0.5) end
  local function note(s) W.log[#W.log + 1] = string.format("%6d  %s", tick() - W.t0, s) end
  -- one action's plan: when it ends and what happens then
  local function start(a)
    local t = W.target
    W.act, W.kind = a, nil
    if a == "pneumaticcraft:teleport" or (a == "pneumaticcraft:goto" and t and (d3(W.pos, t) > PATH or not loaded(t))) then
      W.kind, W.doneAt = "tp", tick() + 121
      W.tp = W.tp + 1
    elseif a == "pneumaticcraft:goto" then
      W.kind, W.doneAt = "fly", tick() + math.max(1, math.ceil(d3(W.pos, t) / SPEED))
      W.flights, W.flown = W.flights + 1, W.flown + d3(W.pos, t)
    elseif a == "pneumaticcraft:entity_import" then
      local who
      for n, p in pairs(W.P) do if math.abs(p.x - t.x) <= 2 and math.abs(p.z - t.z) <= 2 and math.abs(p.y - t.y) <= 3 then who = n end end
      W.kind, W.who = "grab", who
      W.doneAt = tick() + (who and math.max(1, math.ceil(d3(W.pos, W.P[who]) / SPEED)) or 20)
    elseif a == "pneumaticcraft:entity_export" then
      W.kind, W.doneAt = "drop", tick() + 10
    elseif a:find("condition", 1, true) then
      W.act = nil
    else
      W.kind, W.doneAt = "other", tick() + 20
    end
  end
  os.pullEventRaw = function()
    CLOCK = CLOCK + 0.05                                   -- one server tick
    if W.act and W.kind and tick() >= W.doneAt then
      local t = W.target
      if W.kind == "tp" then
        W.air = W.air - 10000 / W.vol                      -- (DRONE_USAGE_TELEPORT, also when refused)
        if loaded(t) and free(t) then
          W.pos = { x = t.x, y = t.y, z = t.z }
          note("teleported to " .. t.x .. " " .. t.y .. " " .. t.z)
          W.act = nil
        else
          W.refused = W.refused + 1
          note("teleport REFUSED (not loaded / blocked) " .. t.x .. " " .. t.y .. " " .. t.z)
          W.doneAt = tick() + 121                          -- it keeps trying
        end
      elseif W.kind == "fly" then
        W.pos = { x = t.x, y = t.y, z = t.z }
        note("flew to " .. t.x .. " " .. t.y .. " " .. t.z)
        W.act = nil
      elseif W.kind == "grab" then
        if W.who then W.pos = { x = W.P[W.who].x, y = W.P[W.who].y + 1, z = W.P[W.who].z } W.carry = W.who end
        note("grabbed " .. tostring(W.who))
        W.act = nil
      elseif W.kind == "drop" then
        if W.carry then W.P[W.carry] = { x = W.pos.x, y = W.pos.y, z = W.pos.z } end
        note("let go of " .. tostring(W.carry))
        W.carry, W.act = nil, nil
      else
        W.act = nil
      end
    end
    if W.carry then W.P[W.carry] = { x = W.pos.x, y = W.pos.y - 1, z = W.pos.z } end
    -- (what the base's Player Detector reads put in state.players)
    local pl = {}
    for n, p in pairs(W.P) do pl[#pl + 1] = { name = n, p = { x = p.x, y = p.y, z = p.z }, dim = DRONE_DIM } end
    state.players = pl
    return "timer", 1
  end
  os.pullEvent = os.pullEventRaw
  local per = {
    clearArea = function() end, addArea = function(x, y, z) W.target = { x = x, y = y, z = z } end,
    setAction = function(a) start(a) end,
    isConnectedToDrone = function() return true end, abortAction = function() W.act = nil end,
    getDronePosition = function() return W.pos.x + 0.5, W.pos.y + 0.5, W.pos.z + 0.5 end,
    isActionDone = function() return W.act == nil end, getDronePressure = function() return W.air end,
    clearWhitelistText = function() W.filter = nil end, clearBlacklistText = function() end,
    addWhitelistText = function(t) W.filter = t end, setOperator = function() end, setCount = function() end,
    evaluateCondition = function() return W.carry ~= nil and (W.filter == nil or W.filter == '"' .. W.carry .. '"') end,
    setUseCount = function() end, exitPiece = function() end, getAction = function() return W.act end,
    setSides = function() end, setDropStraight = function() end, getUpgrades = function() return {} end }
  local det0 = det
  det = { getPlayer = function(n) local p = W.P[n] return p and { x = p.x, y = p.y, z = p.z, dimension = "minecraft:overworld" } end,
          getOnlinePlayers = function() local l = {} for n in pairs(W.P) do l[#l + 1] = n end return l end }
  local pdn = playerDimNow
  playerDimNow = function() return DRONE_DIM end
  local saved = { CONFIG.drone.travel, CONFIG.drone.home, CONFIG.drone.returnHome, CONFIG.drone.charger, CONFIG.drone.liftCheck }
  CONFIG.drone.travel, CONFIG.drone.home, CONFIG.drone.returnHome, CONFIG.drone.charger = "teleport", opt.home, true, nil
  local dr = drones[droneOrder[1]]
  dr.periph, dr.gone, dr.busy, dr.queue, dr.mission = per, false, false, {}, nil
  dr.rider, dr.failedAt, dr.lastPark, dr.awaySince, dr.mdest, dr.checkAboard, dr.notAboard = nil, nil, nil, nil, nil, nil, nil
  dr.dest = opt.dest
  local rd = refreshDrone
  refreshDrone = function(d) d.conn = true d.pos = { x = W.pos.x + 0.5, y = W.pos.y + 0.5, z = W.pos.z + 0.5 } end
  local players0, turtles0 = state.players, state.turtles
  state.turtles = opt.turtles or {}
  dr.hopOK, dr.speedBT = opt.hopOK, nil
  W.t0 = tick()
  if opt.run then opt.run(dr) else runMission(dr, opt.mission) end
  local res = { air = W.air, ticks = tick() - W.t0, teleports = W.tp, refused = W.refused, flights = W.flights, flown = W.flown,
                log = W.log, state = dr.mission and dr.mission.state, err = dr.mission and dr.mission.err, P = W.P, pos = W.pos }
  det, playerDimNow, refreshDrone = det0, pdn, rd
  state.players, state.turtles = players0, turtles0
  CONFIG.drone.travel, CONFIG.drone.home, CONFIG.drone.returnHome, CONFIG.drone.charger, CONFIG.drone.liftCheck =
    saved[1], saved[2], saved[3], saved[4], saved[5]
  return res
end
