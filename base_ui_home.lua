-- base_ui_home.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   HOME: every page in one place - grouped like the tabs at the top, each a
--   big button with what it is for and a live number - and how the base is
--   doing. So you never have to hunt for a tab.

-- one line on how the base is doing
local function homeStatus()
  local on, all, work, bad = 0, 0, 0, 0
  for _, t in pairs(state.turtles or {}) do
    all = all + 1
    if TT.online(t) then
      on = on + 1
      local key = TT.status(t)
      if key == "busy" or key == "trouble" then work = work + 1 end
      if key == "stuck" or key == "nofuel" or key == "still" then bad = bad + 1 end
    end
  end
  local out = {}
  out[#out + 1] = { (state.status == "ok") and "\7 base running" or "\7 base: " .. tostring(state.status),
                    state.status == "ok" and C.good or C.bad }
  if all > 0 then
    out[#out + 1] = { all .. " turtles: " .. on .. " online, " .. work .. " working" .. (bad > 0 and (", " .. bad .. " need you") or ""),
                      bad > 0 and C.warn or C.text }
  end
  local unread = state.noteUnread or 0
  if unread > 0 then out[#out + 1] = { unread .. " new messages", C.warn } end
  if AWAY and AWAY.on then out[#out + 1] = { "away mode is on", C.label } end
  if state.diskLow then out[#out + 1] = { "disk almost full", C.bad } end
  return out
end

function drawHomePage(G)
  local y0, bottom = G.y0, G.y1
  -- the status strip
  card(2, y0, W - 2, 4, nil)
  text(4, y0 + 1, "WELCOME" .. (state.owner and (", " .. state.owner) or ""), C.label, C.panel)
  local sx = 4
  for _, s in ipairs(homeStatus()) do
    text(sx, y0 + 2, s[1], s[2], C.panel)
    sx = sx + #s[1] + 4
  end
  -- the groups, as cards of big buttons (3 per row), as tall as their buttons
  local groups = {}
  for _, g in ipairs(headerTabs()) do if g[1] ~= "home" then groups[#groups + 1] = g end end
  local cols = 3
  local cw = math.floor((W - 2 - (cols - 1)) / cols)
  local bh = 4
  local y = y0 + 5
  for r0 = 1, #groups, cols do
    local rowH = 0
    for i = r0, math.min(#groups, r0 + cols - 1) do rowH = math.max(rowH, 4 + #groups[i].members * (bh + 1)) end
    for i = r0, math.min(#groups, r0 + cols - 1) do
      local g = groups[i]
      local x = 2 + (i - r0) * (cw + 1)
      local name = g[2]
      if #g.members == 1 then name = pageName(g.members[1][1]) end
      card(x, y, cw, rowH, name)
      local by = y + 3
      for _, m in ipairs(g.members) do
        local info = PAGE_INFO[m[1]] or { m[2], "" }
        fill(x + 2, by, cw - 4, bh, C.empty)
        round(x + 2, by, cw - 4, bh, C.empty, C.panel)
        text(x + 4, by + 1, trunc(m[2], cw - 14), C.label, C.empty)
        if m[3] then
          local b = " " .. m[3] .. " "
          text(x + cw - 5 - #b, by + 1, b, m[4] and C.ink or C.text, m[4] or C.head)
        end
        text(x + 4, by + 2, trunc(info[2], cw - 9), C.text, C.empty)
        addHit(x + 2, by, cw - 4, bh, "page", m[1])
        by = by + bh + 1
      end
    end
    y = y + rowH + 1
  end
  -- quick actions (two taps each)
  if y + 6 <= bottom then
    card(2, y, W - 2, 7, "QUICK ACTIONS  (tap twice)")
    local acts = {}
    if next(state.turtles) then
      acts[#acts + 1] = { "STOP ALL TURTLES", { kind = "quick", name = "allstop", count = 0 } }
      acts[#acts + 1] = { "ALL TURTLES HOME", { kind = "quick", name = "allhome", count = 0 } }
      acts[#acts + 1] = { "UPDATE TURTLES", { kind = "sysupdate", name = "all", count = 0 } }
    end
    if #(droneOrder or {}) > 0 then
      acts[#acts + 1] = { "DRONE: TAKE ME TO BASE", { kind = "quick", name = "ride", args = { "base" }, count = 0 } }
    end
    acts[#acts + 1] = { "SAVE THE MAP", { kind = "syssave", name = "map", count = 0 } }
    local n = #acts
    local aw = math.floor((W - 6 - (n - 1)) / n)
    for i, a in ipairs(acts) do
      actButton(4 + (i - 1) * (aw + 1), y + 3, aw, 3, a[1], a[2])
    end
  end
end
