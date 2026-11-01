-- Part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.

-- chat requests ------------------------------------------------------------
-- Ride for `name` to saved place `w`: the nearest free drone with enough air
-- picks THEM up (the filter is always their own name) and delivers them.
-- `dest` is { kind = "waypoint", name, x, y, z } or { kind = "player", name }
-- is the owner on the server right now? (unknown = assume yes)
function ownerIsOnline()
  if not state.owner or not det then return true end
  if det.getOnlinePlayers then
    local ok, list = pcall(det.getOnlinePlayers)
    if ok and type(list) == "table" then
      for _, n in pairs(list) do
        if tostring(n):lower() == state.owner:lower() then return true end
      end
      return false
    end
  end
  return (playerPos(state.owner)) ~= nil
end

function startRide(name, dest, owner)
  local label = dest.name
  refreshDrones()
  local px, py, pz = playerPos(name)
  if not px then
    local d = playerDimNow(name)
    if d and d ~= DRONE_DIM then
      chatTell(name, "You are in " .. dimName(d) .. " - drones only fly in the overworld.")
    else
      chatTell(name, "I cannot find you (out of the Player Detector's range?).")
    end
    return
  end
  if dest.kind == "player" then
    local tx, why = playerPos(dest.name)
    if not tx then
      chatTell(name, "Cannot fly you to " .. dest.name .. ": " .. cleanErr(why) .. ".")
      return
    end
  end
  if CONFIG.chat.maxDistance and not owner and CONFIG.drone.home then
    local h = CONFIG.drone.home
    if dist3(px, py, pz, h.x, h.y, h.z) > CONFIG.chat.maxDistance then
      chatTell(name, "You are too far from base (limit " .. CONFIG.chat.maxDistance .. " blocks).")
      return
    end
  end

  local best, bestD
  for _, k in ipairs(droneOrder) do
    local dr = drones[k]
    if dr.conn and not dr.busy and (not dr.pressure or dr.pressure >= rideMinPressure()) then
      -- most air first (every teleport costs air), then the nearest
      local dd = dr.pos and dist3(dr.pos.x, dr.pos.y, dr.pos.z, px, py, pz) or math.huge
      local pr = dr.pressure or 0
      if not best or pr > (best.pressure or 0) + 0.5
         or (math.abs(pr - (best.pressure or 0)) <= 0.5 and dd < bestD) then
        best, bestD = dr, dd
      end
    end
  end
  if not best then
    -- tell the rider why, so they know whether waiting helps
    local busy, low, off = 0, 0, 0
    for _, k in ipairs(droneOrder) do
      local dr = drones[k]
      if not dr.conn then off = off + 1
      elseif dr.busy then busy = busy + 1
      elseif dr.pressure and dr.pressure < rideMinPressure() then low = low + 1 end
    end
    local why
    if #droneOrder == 0 or off == #droneOrder then why = "No drone is connected right now."
    elseif busy > 0 then why = "All drones are busy. Try again in a minute."
    elseif low > 0 then why = "The drones are low on air and charging. Try again in a few minutes."
    else why = "No drone is free right now. Try again in a moment." end
    chatTell(name, why)
    return
  end

  best.dest = dest
  best.passenger = name
  best.requester = name
  if submitDrone(best, { kind = "ferry", passenger = name }) then
    state.lastRide[name:lower()] = os.clock()
    local far = bestD < math.huge and (" (" .. fl(bestD) .. " blocks away)") or ""
    chatTell(name, best.label .. " is coming to you" .. far .. ". Stand still!")
    droneLog(best, "Chat: " .. name .. " asked for a ride to " .. label)
    if CONFIG.chat.notifyOwner and state.owner and name ~= state.owner then
      chatTell(state.owner, name .. " is getting a ride to " .. label .. " (" .. best.label .. ")")
    end
    if dest.kind == "player" and CONFIG.chat.tellTarget and dest.name ~= name then
      chatTell(dest.name, name .. " is being flown to you by drone.")
    end
  else
    best.requester = nil
  end
end

function findOnlinePlayer(n)
  n = tostring(n or ""):gsub("^@", "")
  if n == "" or not det or not det.getOnlinePlayers then return nil end
  local ok, list = pcall(det.getOnlinePlayers)
  if not ok or type(list) ~= "table" then return nil end
  for _, p in pairs(list) do
    if type(p) == "string" and p:lower() == n:lower() then return p end
  end
end

function handleChat(m)
  local text = tostring(m.msg or ""):gsub("^%$", "")
  local words = {}
  for w in text:gmatch("%S+") do words[#words + 1] = w end
  if (words[1] or ""):lower() ~= CONFIG.chat.command:lower() then return end

  local name, uuid = tostring(m.name or ""), m.uuid
  if name == "" or name == "[say]" then return end
  local sub = (words[2] or "help"):lower()
  local owner = isOwner(uuid, name)
  local trusted = owner or isAllowed(uuid, name)
  local c = "$" .. CONFIG.chat.command
  local function reply(t) chatTell(name, t) end

  -- strangers only get help and the ride request (which goes to the owner)
  if not trusted and (sub == "places" or sub == "status" or sub == "stop") then
    reply("You are not on the drone list. Ask " .. tostring(state.owner) .. " to allow you.")
    return
  end

  if sub == "help" then
    reply("Use: " .. c .. " home | " .. c .. " to <place" ..
          ((owner or CONFIG.chat.othersToPlayers) and "|player" or "") .. "> | " .. c .. " back | " ..
          c .. " places | " .. c .. " status | " .. c .. " stop")
    if owner then reply("Owner: " .. c .. " allow/deny <name> | " ..
                        c .. " allowed | " .. c .. " yes/no <name>") end

  elseif sub == "places" then
    local n = {}
    for _, w in ipairs(state.waypoints) do n[#n + 1] = w.name end
    reply("Places: " .. (#n > 0 and table.concat(n, ", ") or "none"))

  elseif sub == "status" then
    if #droneOrder == 0 then reply("No drones.") end
    for _, k in ipairs(droneOrder) do
      local dr = drones[k]
      reply(dr.label .. ": " .. (not dr.conn and "not connected" or
            (dr.busy and ((dr.mission and dr.mission.title) or "busy") or "free")))
    end

  elseif sub == "stop" then
    local n = 0
    for _, k in ipairs(droneOrder) do
      local dr = drones[k]
      if dr.busy and (dr.requester == name or (owner and words[3] == "all")) then
        submitDrone(dr, { kind = "stop" })
        n = n + 1
      end
    end
    reply(n > 0 and ("Stopped " .. n .. " drone(s).") or "No drone is working for you.")

  elseif sub == "allow" or sub == "deny" or sub == "allowed" or sub == "yes" or sub == "no" then
    if not owner then
      reply("Only " .. tostring(state.owner) .. " can do that.")
      return
    end
    local who = words[3] and canonPlayer(words[3]) or nil
    if sub == "allowed" then
      local n = allowedNames()
      reply("Allowed: " .. (#n > 0 and table.concat(n, ", ") or "nobody else"))
    elseif not who then
      reply("Usage: " .. c .. " " .. sub .. " <name>")
    elseif sub == "allow" then
      allowPlayer(who)
      reply(who .. " may now use " .. c .. ".")
      chatTell(who, tostring(state.owner) .. " allowed you to use the drones: " .. c .. " help")
    elseif sub == "deny" then
      denyPlayer(who)
      reply(who .. " can no longer use " .. c .. ".")
    else
      local p = state.rideRequests[who:lower()]
      if not p or os.clock() > p.exp then
        reply("No open request from " .. who .. ".")
      elseif sub == "no" then
        state.rideRequests[who:lower()] = nil
        reply("Declined.")
        chatTell(p.name, tostring(state.owner) .. " declined your request.")
      else
        state.rideRequests[who:lower()] = nil
        reply("Approved.")
        if p.dest then startRide(p.name, p.dest, false) end
      end
    end

  elseif sub == "home" or sub == "to" or sub == "back" then
    local place = (sub == "home") and "Base" or table.concat(words, " ", 3)
    if sub == "to" and place == "" then
      reply("Use: " .. c .. " to <place|player>   (" .. c .. " places shows the places)")
      return
    end
    -- a saved place, or (with @ or when no place has that name) a player
    local dest
    local w = (sub ~= "back" and place:sub(1, 1) ~= "@") and findWaypoint(place) or nil
    if sub == "back" then
      -- where this player was before a big jump, or where they died (overworld)
      local b = backSpots[name:lower()]
      if not b or os.epoch("utc") - (b.t or 0) > CONFIG.back.keepHours * 3600000 then
        reply("I know no earlier spot for you. I remember where you died, or where you were before a jump " ..
              "of more than " .. CONFIG.back.jump .. " blocks - in the overworld only.")
        return
      end
      local dim = playerDimNow(name)
      if dim and dim ~= "minecraft:overworld" then
        reply("That only works in the overworld - you are in " .. dim .. ".")
        return
      end
      dest = { kind = "coords", name = b.why .. " (" .. b.x .. " " .. b.y .. " " .. b.z .. ")",
               x = b.x, y = b.y + 1, z = b.z }
      if b.why == "where you died" then
        reply("Careful: if you died in lava or water, it may still be there.")
      end
    elseif w then
      dest = { kind = "waypoint", name = w.name, x = w.x, y = w.y, z = w.z }
    else
      local p = findOnlinePlayer(place)
      if not p then
        reply("No saved place or online player called '" .. place .. "'. Try " .. c .. " places")
        return
      end
      if p == name then
        reply("You are already where you are.")
        return
      end
      if not owner and not CONFIG.chat.othersToPlayers then
        reply("Only " .. tostring(state.owner) .. " can fly to other players.")
        return
      end
      dest = { kind = "player", name = p }
    end
    local label = dest.name
    setToast("Chat: " .. name .. " asked for a ride to " .. label, C.label, 6)

    if not trusted then
      -- the owner can only approve when online
      local ownerOnline = ownerIsOnline()
      if CONFIG.chat.askOwner and state.owner and not ownerOnline then
        reply(state.owner .. " is offline - only players on the allowed list can ride right now.")
        return
      end
      if CONFIG.chat.askOwner and state.owner then
        state.rideRequests[name:lower()] = { name = name, uuid = uuid, dest = dest,
                                        exp = os.clock() + CONFIG.chat.approveTime }
        reply("You are not on the list - asking " .. state.owner .. " for permission...")
        chatTell(state.owner, name .. " wants a ride to " .. label .. ". Reply " ..
                 c .. " yes " .. name .. "  or  " .. c .. " no " .. name)
      else
        reply("You are not allowed to use the drones.")
      end
      return
    end

    if not owner then
      local last = state.lastRide[name:lower()]
      if last and os.clock() - last < CONFIG.chat.cooldown then
        reply("Please wait " .. math.ceil(CONFIG.chat.cooldown - (os.clock() - last)) ..
              " s before the next ride.")
        return
      end
    end
    startRide(name, dest, owner)

  else
    reply("Unknown command. Try " .. c .. " help")
  end
end

