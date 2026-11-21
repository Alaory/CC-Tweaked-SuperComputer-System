-- base_ui_gifts.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   GIFTS (PLAYERS group; the owner: "a new tab for gifts where I can add gifts to the list of possible gifts
--   from AE2, and send gifts from that tab to other players"). The gift system lives in the voice add-on's TALK
--   PACK 2 (voice_talk2.lua: VOICE.giftEarn / giftList / giftWait / giftNow - a drone brings the gift); this page
--   is its screen:
--     * AE2 ITEMS (left): letters + the AE2 item list (state.me.items) - tap one to pick it
--     * GIVE: the picked item, how many (x1 .. x1024 >), TO: an online player >, SEND (two taps) = a gift from
--       you ("manual") into the queue; ADD TO <reward> (two taps) = it becomes part of that reward
--     * REWARDS: what each reward gives (regular, friend ... = friendship titles, birthday, badges, secret word,
--       streaks) - REMOVE an item (two taps), RESET to the default list. Saved in settings.dat as
--       voice.gifts.<reward> (VOICE.giftList reads CONFIG.voice.gifts[<reward>])
--     * WAITING: every queued gift with WHY it waits (VOICE.giftWait), CANCEL (two taps), TRY NOW; GIVEN: newest
-- Drawing reads only state / VOICE tables; the taps are handled in base_input.lua (hit kinds gift*).

GIFTS = {}
GIFTS.COUNTS = { 1, 4, 8, 16, 32, 64, 128, 256, 512, 1024 }

-- the add-on part that does the work (nil = not installed)
function GIFTS.ready() return VOICE and VOICE.giftEarn and VOICE.giftList and VOICE.GIFT_ORDER and true or false end
function GIFTS.count() return tonumber(state.giftCount) or 16 end
function GIFTS.reward() return state.giftReward or "regular" end

-- players a gift can go to: online first (the Player Detector), then the ones the base knows (voice memory)
function GIFTS.players()
  local out, seen = {}, {}
  local on = state.online
  for _, e in ipairs(state.players or {}) do
    local n = tostring(e.name)
    if not seen[n:lower()] and (not on or on[n:lower()]) then seen[n:lower()] = true out[#out + 1] = n end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end
function GIFTS.to()
  local list = GIFTS.players()
  for _, n in ipairs(list) do if n == state.giftTo then return n end end
  return state.giftTo or list[1]
end

-- the reward lists (settings.dat voice.gifts.<reward>); a copy is changed, never the add-on's defaults
local function copyList(l)
  local out = {}
  for _, g in ipairs(type(l) == "table" and l or {}) do
    if type(g) == "table" and type(g[1]) == "string" and tonumber(g[2]) then out[#out + 1] = { g[1], math.floor(tonumber(g[2])) } end
  end
  return out
end
function GIFTS.addTo(why, item, n)
  if not GIFTS.ready() then return false, "the voice add-on (talk pack 2) is not installed - voice install" end
  if type(item) ~= "string" or item == "" then return false, "pick an AE2 item first" end
  n = math.max(1, math.floor(tonumber(n) or 1))
  local l = copyList(VOICE.giftList(why))
  for _, g in ipairs(l) do
    if g[1] == item then
      g[2] = n
      setSetting("voice.gifts." .. why, l)
      return true, prettify(item) .. ": now " .. n .. " in the " .. why .. " gift"
    end
  end
  if #l >= 8 then return false, "the " .. why .. " gift has 8 items already - remove one first" end
  l[#l + 1] = { item, n }
  setSetting("voice.gifts." .. why, l)
  return true, n .. " " .. prettify(item) .. " added to the " .. why .. " gift"
end
function GIFTS.delFrom(why, item)
  if not GIFTS.ready() then return false, "the voice add-on is not installed" end
  local l, out = copyList(VOICE.giftList(why)), {}
  for _, g in ipairs(l) do if g[1] ~= item then out[#out + 1] = g end end
  setSetting("voice.gifts." .. why, out)
  return true, prettify(item) .. " is no longer in the " .. why .. " gift" .. (#out == 0 and " (it gives nothing now)" or "")
end
function GIFTS.reset(why)
  resetSetting("voice.gifts." .. why)
  return true, "The " .. why .. " gift is back to its default"
end
function GIFTS.send(who, item, n)
  if not GIFTS.ready() then return false, "the voice add-on (talk pack 2) is not installed - voice install" end
  if not who then return false, "nobody to send it to - nobody is online" end
  if type(item) ~= "string" or item == "" then return false, "pick an AE2 item first" end
  local ok, why = VOICE.giftEarn(who, "manual", { { item, math.max(1, math.floor(tonumber(n) or 1)) } })
  if not ok then return false, "not sent: " .. tostring(why) end
  VOICE.giftNext = 0                              -- (the gift check runs in the next voice tick)
  return true, n .. " " .. prettify(item) .. " for " .. who .. " - a drone brings it " ..
               (VOICE.giftWhere and VOICE.giftWhere() or "")
end

-- the AE2 items for the list: a letter filter (like the AE2 page), sorted by name
local function itemView()
  local me = state.me or {}
  local out = {}
  local L = state.giftLetter
  for _, it in ipairs(me.items or {}) do
    local d = tostring(it.display or it.name or "")
    local first = d:sub(1, 1):upper()
    if not L or (L == "#" and not first:match("%a")) or first == L then out[#out + 1] = it end
  end
  table.sort(out, function(a, b) return tostring(a.display):lower() < tostring(b.display):lower() end)
  return out
end
function GIFTS.have(item)
  local me = state.me or {}
  for _, it in ipairs(me.items or {}) do if it.name == item then return tonumber(it.count) or 0 end end
  return 0
end

local function itemsPanel(x, y, w, h)
  local view = itemView()
  local ix, iy, iw, ih = panel(x, y, w, h, "AE2 ITEMS", { right = commas(#view) .. " shown" })
  local tokens = { { "ALL", false } }
  for c = 65, 90 do tokens[#tokens + 1] = { string.char(c), string.char(c) } end
  tokens[#tokens + 1] = { "#", "#" }
  -- the letters in two rows of 2-row buttons (the list is narrow)
  local per = math.ceil(#tokens / 2)
  for k, t in ipairs(tokens) do
    local r = (k <= per) and 0 or 1
    local c = (k <= per) and (k - 1) or (k - 1 - per)
    local active = (state.giftLetter == (t[2] or nil))
    -- (spread evenly over the row; ALL gets 5 columns of the first row, the rest share what is left)
    local x0, w0, n0, c0 = ix, iw, per, c
    if r == 0 then x0, w0, n0, c0 = ix + 5, iw - 5, per - 1, c - 1 end
    local bx = x0 + math.floor(c0 * w0 / n0)
    local bw = x0 + math.floor((c0 + 1) * w0 / n0) - bx
    if r == 0 and c == 0 then bx, bw = ix, 5 end
    button(bx, iy + r * 2, bw, 2, t[1], active and C.accent or C.line, "giftletter", t[2], active)
  end
  local ry0 = iy + 5
  if not bridge then
    para(ix, ry0, iw, "No ME Bridge - gifts come out of AE2.", C.warn, 2)
    return
  end
  if #view == 0 then
    text(ix, ry0, trunc((state.me and state.me.items and #state.me.items > 0) and "No items with this letter." or
         "AE2 not read yet - a moment.", iw), C.dim, C.panel)
    return
  end
  local rows = math.max(1, y + h - 2 - ry0)
  local off = scrollBar(x, y, w, "giftOff", #view, rows)
  local maxCount = 1
  for _, it in ipairs(view) do if (it.count or 0) > maxCount then maxCount = it.count end end
  for i = 1, rows do
    local it = view[off + i]
    if not it then break end
    local ry = ry0 + i - 1
    drawBarRow(ix, ry, iw, it.display or prettify(it.name), commas(it.count or 0), (it.count or 0) / maxCount,
               hashColor(it.name), state.giftItem == it.name, 14)
    addHit(ix, ry, iw, 1, "giftitem", it.name)
  end
end

local function givePanel(x, y, w, h)
  local item = state.giftItem
  local ix, iy, iw = panel(x, y, w, h, "GIVE", { right = item and "picked" or "pick an item on the left",
                                                  rcol = item and C.good or C.dim })
  if item then
    local have = GIFTS.have(item)
    text(ix, iy, trunc(prettify(item), iw), C.label, C.panel)
    text(ix, iy + 1, trunc(item .. "   -   AE2 has " .. commas(have), iw), have > 0 and C.dim or C.warn, C.panel)
  else
    para(ix, iy, iw, "Tap an item in the AE2 list. Then SEND it to a player, or ADD it to a reward below.", C.dim, 2)
  end
  local n = GIFTS.count()
  local who = GIFTS.to()
  local bw = math.floor((iw - 2) / 3)
  local by = iy + 3
  button(ix, by, bw, 3, "x" .. n .. " >", C.line, "giftcount")
  button(ix + bw + 1, by, bw, 3, "TO: " .. (who or "nobody online") .. " >", C.line, "giftto")
  actButton(ix + 2 * (bw + 1), by, iw - 2 * (bw + 1), 3, "SEND " .. (who and ("TO " .. who) or ""),
            { kind = "giftsend", name = item or "", count = n, target = who }, true, C.accent)
  local why = GIFTS.reward()
  actButton(ix, by + 4, iw, 3, "ADD x" .. n .. " TO THE " .. why:upper() .. " GIFT",
            { kind = "giftadd", name = item or "", count = n, target = why }, false, C.good)
end

local function rewardsPanel(x, y, w, h)
  local why = GIFTS.reward()
  local list = VOICE.giftList(why) or {}
  local changed = isChanged("voice.gifts." .. why)
  local ix, iy, iw, ih = panel(x, y, w, h, "REWARDS", { right = changed and "yours" or "default", rcol = changed and C.label or C.dim })
  -- every reward as a button (the picked one bright)
  local order = VOICE.GIFT_ORDER
  local cols = iw >= 70 and 5 or (iw >= 44 and 3 or 2)
  local cw = math.floor((iw - (cols - 1)) / cols)
  for k, r in ipairs(order) do
    local c, rr = (k - 1) % cols, math.floor((k - 1) / cols)
    local on = r == why
    button(ix + c * (cw + 1), iy + rr * 2, (c == cols - 1) and (iw - c * (cw + 1)) or cw, 2, r:upper(), on and C.accent or C.line,
           "giftwhy", r, on)
  end
  local yy = iy + math.ceil(#order / cols) * 2 + 1
  local wt = VOICE.GIFT_WHY and VOICE.GIFT_WHY[why]
  text(ix, yy, trunc(why:upper() .. (wt and ("  -  given " .. wt) or ""), iw), C.label, C.panel)
  yy = yy + 1
  if #list == 0 then
    text(ix, yy, trunc("Gives nothing. Pick an item and tap ADD.", iw), C.dim, C.panel)
    yy = yy + 2
  end
  for _, g in ipairs(list) do
    if yy + 1 > y + h - 5 then break end
    kv(ix, yy, iw - 12, prettify(g[1]), "x" .. tostring(g[2]) .. "  (AE2 " .. compact(GIFTS.have(g[1])) .. ")",
       GIFTS.have(g[1]) < (tonumber(g[2]) or 0) and C.warn or C.text)
    actButton(ix + iw - 10, yy, 10, 2, "REMOVE", { kind = "giftdel", name = g[1], count = 0, target = why }, false, C.bad)
    yy = yy + 2
  end
  if changed then
    actButton(ix, y + h - 4, iw, 3, "RESET THE " .. why:upper() .. " GIFT TO THE DEFAULT", { kind = "giftreset", name = why, count = 0 },
              false, C.warn)
  end
end

local function queuePanel(x, y, w, h)
  local q = VOICE.giftQueue and VOICE.giftQueue() or {}
  local log = VOICE.giftLogList and VOICE.giftLogList() or {}
  local ix, iy, iw, ih = panel(x, y, w, h, "WAITING + GIVEN", { right = #q .. " waiting", rcol = #q > 0 and C.warn or C.good })
  button(ix + iw - 14, iy, 14, 2, "TRY NOW", C.accent, "giftnow")
  local busy = VOICE.giftBusy
  local top = busy and ("Flying now: " .. busy.n .. " " .. prettify(busy.item) .. " to " .. busy.who)
              or (#q > 0 and ("Now: " .. tostring(VOICE.giftWhy or "checking ..."))) or "Nothing waiting."
  para(ix, iy, iw - 16, top, busy and C.good or C.dim, 2)
  if VOICE.tickErr then text(ix, iy + 2, trunc("VOICE ERROR: " .. tostring(VOICE.tickErr), iw), C.bad, C.panel) end
  local near = {}
  for _, p in ipairs((VOICE.nearPlayers and VOICE.nearPlayers()) or {}) do near[p.name] = true end
  local yy = iy + 3
  local logRows = math.min(#log, 4)
  local last = y + h - 2 - (logRows > 0 and (logRows + 1) or 0)
  for i, g in ipairs(q) do
    if yy + 1 > last then text(ix, yy, "+" .. (#q - i + 1) .. " more (console: voice gifts)", C.dim, C.panel) break end
    local okW, wait = pcall(VOICE.giftWait, g, near, os.clock())
    wait = okW and wait or nil
    text(ix, yy, trunc(g.who .. ": " .. g.n .. " " .. prettify(g.item) .. "  (" .. tostring(g.why) .. ")", iw - 12), C.text, C.panel)
    text(ix, yy + 1, trunc(wait or "can go now", iw - 12), wait and C.warn or C.good, C.panel)
    actButton(ix + iw - 10, yy, 10, 2, "CANCEL", { kind = "giftcancel", name = g.item, count = i }, false, C.bad)
    yy = yy + 3
  end
  if logRows > 0 then
    local ly = y + h - 2 - logRows
    heading(ix, ly, iw, "GIVEN (NEWEST FIRST)")
    for k = 1, logRows do
      local e = log[#log - k + 1]
      text(ix, ly + k, trunc(os.date("!%d %b %H:%M", math.floor((tonumber(e.at) or 0) / 1000)) .. "  " .. tostring(e.who) .. ": " ..
           tostring(e.n) .. " " .. prettify(e.item), iw), C.dim, C.panel)
    end
  end
end

function drawGiftsPage(G)
  local y0, bottom = G.y0, G.y1
  local th = bottom - y0 + 1
  if not GIFTS.ready() then
    local ix, iy, iw = panel(2, y0, W - 2, th, "GIFTS", { right = "not installed", rcol = C.warn })
    para(ix, iy, iw, "Gifts are part of the talking base (the voice add-on with its TALK PACK 2). Type  voice install  on " ..
         "this computer's console - it goes onto a data floppy. Then friends earn gifts and you can send AE2 items " ..
         "to players from here; a drone brings them.", C.text, 6)
    return
  end
  local lw = math.floor((W - 3) * 0.40)
  local rx, rw = 2 + lw + 1, W - (2 + lw + 1)
  itemsPanel(2, y0, lw, th)
  local gh = 12
  local half = math.floor((rw - 1) / 2)
  givePanel(rx, y0, rw, gh)
  rewardsPanel(rx, y0 + gh + 1, half, th - gh - 1)
  queuePanel(rx + half + 1, y0 + gh + 1, rw - half - 1, th - gh - 1)
end
