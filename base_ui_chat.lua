-- base_ui_chat.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   CHAT tab: the '$drone' allow list (who may ride) and the chat commands.
--   It is not a chat log.

-- page drawing
function drawAccessPage(G)
  local y0, bottom = G.y0, G.y1
  local lx = 2
  local leftW = math.floor((W - 3) / 2)
  local rx = lx + leftW + 1
  local rw = W - rx
  local c = "$" .. CONFIG.chat.command
  local owner = state.owner

  local online = {}
  for _, e in ipairs(state.players or {}) do online[e.name:lower()] = true end

  ------------------------------------------------ ONLINE PLAYERS
  card(lx, y0, leftW, bottom - y0 + 1, "ONLINE PLAYERS")
  local ix, iw = lx + 2, leftW - 4
  local list = state.players or {}
  if not det then
    text(ix, y0 + 3, "No Player Detector connected - use  allow <name>  on the computer.",
         C.warn, C.panel)
  elseif not state.t.players then
    text(ix, y0 + 3, "Reading players...", C.dim, C.panel)
  else
    local rows = math.max(1, math.floor((bottom - y0 - 3) / 3))
    local off = scrollBar(lx, y0 + 1, leftW, "accOnlineOff", #list, rows)
    for i = 1, math.min(rows, #list - off) do
      local e = list[off + i]
      local ry = y0 + 3 + (i - 1) * 3
      local isOwnerRow = owner and e.name == owner
      local allowed = state.access.allowed[e.name:lower()] ~= nil
      local st, col = "NOT ALLOWED", C.dim
      if isOwnerRow then st, col = "OWNER", C.label
      elseif allowed then st, col = "ALLOWED", C.good end
      if isOwnerRow or allowed then
        mark(lx + 1, ry, col)
        mark(lx + 1, ry + 1, col)
      end
      text(ix, ry, trunc(e.name, iw - 14), C.text, C.panel)
      text(ix, ry + 1, st, col, C.panel)
      local bx = lx + leftW - 2 - 12
      if not isOwnerRow then
        if allowed then
          actButton(bx, ry, 12, 2, "REMOVE", { kind = "accdeny", name = e.name, count = 0 })
        else
          drawButton(bx, ry, 12, 2, "ALLOW", C.good, C.ink, "acc_allow", e.name)
        end
      end
    end
  end

  ------------------------------------------------ WAITING REQUESTS
  local rix, riw = rx + 2, rw - 4
  local reqs = {}
  for _, r in pairs(state.rideRequests or {}) do
    if os.clock() < r.exp then reqs[#reqs + 1] = r end
  end
  table.sort(reqs, function(a, b) return a.exp < b.exp end)
  local qh = math.max(8, math.min(16, 4 + #reqs * 3))
  card(rx, y0, rw, qh, "WAITING FOR YOUR OK")
  if #reqs == 0 then
    text(rix, y0 + 3, trunc("No requests. Players who are not allowed and type  " .. c ..
         " home  show up here.", riw), C.dim, C.panel)
  end
  for i = 1, math.min(#reqs, math.floor((qh - 4) / 3)) do
    local r = reqs[i]
    local ry = y0 + 3 + (i - 1) * 3
    local where = r.dest and ((r.dest.kind == "player" and "@" or "") .. tostring(r.dest.name)) or "?"
    text(rix, ry, trunc(r.name .. "  >  " .. where, riw - 30), C.text, C.panel)
    text(rix, ry + 1, "expires in " .. math.max(0, math.ceil(r.exp - os.clock())) .. " s",
         C.warn, C.panel)
    local bx2 = rx + rw - 2 - 12
    local bx1 = bx2 - 13
    drawButton(bx1, ry, 12, 2, "APPROVE", C.good, C.ink, "acc_yes", r.name)
    drawButton(bx2, ry, 12, 2, "DECLINE", C.bad, C.ink, "acc_no", r.name)
  end

  ------------------------------------------------ the base's messages in chat ($drone notify)
  local ny = y0 + qh + 1
  local nh = 8
  card(rx, ny, rw, nh, "BASE MESSAGES IN YOUR CHAT")
  local sub = owner and state.notifySubs and state.notifySubs[tostring(owner):lower()]
  local level = sub and sub.level or "off"
  text(rix, ny + 3, trunc("The monitor's messages, sent privately to " .. tostring(owner) ..
       " in chat (at most 6 a minute)", riw), C.dim, C.panel)
  local opts = { { "off", "OFF" }, { "important", "WARNINGS + ERRORS" }, { "all", "EVERYTHING" } }
  local bw = math.floor((riw - 2) / 3)
  for i, o in ipairs(opts) do
    local on = level == o[1]
    drawButton(rix + (i - 1) * (bw + 1), ny + 5, (i == 3) and (riw - 2 * (bw + 1)) or bw, 2, o[2],
               on and C.accent or C.empty, on and C.ink or C.text, "cnotify", o[1])
  end

  ------------------------------------------------ ALLOWED LIST (also offline people)
  local ay = ny + nh + 1
  local ah = bottom - ay + 1
  if ah >= 6 then
    local names = allowedNames()
    card(rx, ay, rw, ah, "ALLOWED PLAYERS (" .. #names .. ")")
    if #names == 0 then
      text(rix, ay + 3, "Nobody yet - only " .. tostring(owner) .. " can use the chat commands.",
           C.dim, C.panel)
    end
    local rows = math.max(1, math.floor((ah - 4) / 3))
    local off = scrollBar(rx, ay + 1, rw, "accAllowedOff", #names, rows)
    for i = 1, math.min(rows, #names - off) do
      local n = names[off + i]
      local e = state.access.allowed[n:lower()] or {}
      local ry = ay + 3 + (i - 1) * 3
      local on = online[n:lower()]
      text(rix, ry, trunc(n, riw - 16), C.text, C.panel)
      text(rix + math.min(#n, riw - 16) + 2, ry, "\7", on and C.good or C.dim, C.panel)
      local sub = (on and "online" or "offline") .. "   " ..
                  (e.uuid and "tied to their account" or "not used yet")
      text(rix, ry + 1, trunc(sub, riw - 16), C.dim, C.panel)
      actButton(rx + rw - 2 - 12, ry, 12, 2, "REMOVE", { kind = "accdeny", name = n, count = 0 })
    end
  end
end
