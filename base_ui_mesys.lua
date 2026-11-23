-- base_ui_mesys.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   AE2 SYSTEM page (the AE2 group; data from MEX in base_meplus.lua): crafting CPUs
--   (busy / idle, bytes, co-processors, the job each one runs), every running crafting
--   job with CANCEL, YOUR craft requests (calculating / crafting / done / MISSING ...),
--   storage in cells and on storage buses, energy, every drive with its cells, and the
--   PATTERNS (count by type; the item picked on the AE2 page: made from / used in).
--   What the bridge cannot do on this server is said, not drawn empty.

local function pct(u, m) return (m and m > 0) and math.max(0, math.min(1, u / m)) or 0 end
local function fillCol(f) return f < 0.6 and C.good or (f < 0.85 and C.warn or C.bad) end
local function nope(x, y, w, what)
  para(x, y, w, what .. ": not on this ME Bridge (an older Advanced Peripherals).", C.dim, 2)
end

local function cpuPanel(x, y, w, h)
  local d = MEX.data or {}
  local cpus = d.cpus
  local busy = 0
  for _, c in ipairs(cpus or {}) do if c.busy then busy = busy + 1 end end
  local ix, iy, iw = panel(x, y, w, h, "CRAFTING CPUS", { right = cpus and (busy .. " / " .. #cpus .. " busy") or nil })
  if not cpus then nope(ix, iy, iw, "Crafting CPUs") return end
  if #cpus == 0 then text(ix, iy, "No crafting CPU on the network - AE2 cannot craft.", C.warn, C.panel) return end
  local r = iy
  for _, c in ipairs(cpus) do
    if r + 1 > y + h - 2 then break end
    local tag = c.busy and "BUSY" or "IDLE"
    local bw = badge(ix + iw - #tag - 2, r, tag, c.busy and C.warn or C.good)
    local info = (c.storage and fmtBytes(c.storage) or "") .. (c.co and ("  " .. c.co .. " co-proc") or "")
    text(ix, r, trunc(c.name, iw - bw - #info - 3), C.text, C.panel)
    text(ix + iw - bw - 1 - #info, r, info, C.dim, C.panel)
    if c.job then
      local f = c.job.f or (c.job.done and c.job.qty > 0 and c.job.done / c.job.qty) or 0
      local v = (c.job.done and (commas(c.job.done) .. "/") or "") .. commas(c.job.qty)
      text(ix + 2, r + 1, trunc(c.job.name, math.max(1, iw - 2 - #v - 12)), C.dim, C.panel)
      gauge(ix + iw - #v - 11, r + 1, 10, f, C.good)
      text(ix + iw - #v, r + 1, v, C.text, C.panel)
    else
      text(ix + 2, r + 1, "free", C.dim, C.panel)
    end
    r = r + 3
  end
end

local function jobsPanel(x, y, w, h)
  local d = MEX.data or {}
  local tasks = d.tasks
  local ix, iy, iw = panel(x, y, w, h, "CRAFTING NOW", { right = tasks and (#tasks .. " running") or nil })
  if not tasks then nope(ix, iy, iw, "The job list") return end
  if #tasks == 0 then text(ix, iy, "Nothing is being crafted.", C.dim, C.panel) return end
  local canX = MEX.canCancel()
  local r = iy
  for i, t in ipairs(tasks) do
    if r + 1 > y + h - 2 then
      text(ix, y + h - 2, "+" .. (#tasks - i + 1) .. " more", C.dim, C.panel)
      break
    end
    local bw = (canX and t.item) and 10 or 0
    meter(ix, r, iw - (bw > 0 and bw + 1 or 0), t.name .. ((t.cpu and t.cpu ~= "Unnamed") and ("  (" .. t.cpu .. ")") or ""),
          (t.done and t.done > 0 and (commas(t.done) .. " / ") or "") .. commas(t.qty), t.f, C.good)
    if bw > 0 then
      actButton(ix + iw - bw, r, bw, 2, "CANCEL", { kind = "mecancel", name = t.item, count = 0, label = t.name }, false, C.bad)
    end
    r = r + 3
  end
end

local STATE = { requested = { "SENT", "dim" }, calculating = { "CALCULATING", "info" }, crafting = { "CRAFTING", "accent" },
                done = { "DONE", "good" }, missing = { "MISSING", "warn" }, failed = { "FAILED", "bad" },
                cancelled = { "CANCELLED", "dim" } }
local function minePanel(x, y, w, h)
  local ix, iy, iw = panel(x, y, w, h, "YOUR CRAFT REQUESTS", { right = "from this base" })
  if #MEX.order == 0 then
    para(ix, iy, iw, "Nothing asked for yet. CRAFT on the AE2 page (and the factory) is followed here: calculating, " ..
         "crafting, done - or which ingredients are MISSING.", C.dim, 4)
    return
  end
  local r = iy
  for _, k in ipairs(MEX.order) do
    local j = MEX.jobs[k]
    if j then
      if r > y + h - 2 then break end
      local st = STATE[j.state] or { j.state:upper(), "dim" }
      local bw = badge(ix, r, st[1], C[st[2]] or C.dim, C.ink)
      local known = state.me and (j.fluid and state.me.byNameF or state.me.byName)
      local nm = (known and known[j.name] and known[j.name].display) or prettify(j.name)
      local amt = j.fluid and fmtBuckets(j.count) or (commas(j.count) .. " x")
      local ago = fmtSpan(os.clock() - j.t) .. " ago"
      text(ix + bw + 1, r, trunc(amt .. " " .. nm, math.max(1, iw - bw - #ago - 3)), C.text, C.panel)
      text(ix + iw - #ago, r, ago, C.dim, C.panel)
      r = r + 1
      if j.missing and r <= y + h - 2 then
        r = para(ix + 2, r, iw - 2, "missing: " .. j.missing, C.warn, math.min(3, y + h - 1 - r))
      elseif j.why and r <= y + h - 2 then
        r = para(ix + 2, r, iw - 2, tostring(j.why), C.dim, 1)
      elseif j.f and j.state == "crafting" and r <= y + h - 2 then
        gauge(ix + 2, r, iw - 2, j.f, C.accent)
        r = r + 1
      end
    end
  end
end

local function storagePanel(x, y, w, h)
  local d = MEX.data or {}
  local ix, iy, iw = panel(x, y, w, h, "STORAGE + ENERGY", { right = (d.online == false) and "OFFLINE" or "online",
                                                             rcol = (d.online == false) and C.bad or C.good })
  local r = iy
  local en = d.energy or {}
  if en.stored and en.cap and en.cap > 0 then
    meter(ix, r, iw, "Energy", compact(en.stored) .. " / " .. compact(en.cap) .. " AE", pct(en.stored, en.cap), C.warn)
    r = r + 2
  end
  if en.usage or en.inj then
    kv(ix, r, iw, "Use / coming in", (en.usage and (compact(en.usage) .. " AE/t") or "?") .. "  /  " ..
       (en.inj and (compact(en.inj) .. " AE/t") or "?"), (en.usage and en.inj and en.usage > en.inj) and C.warn or C.text)
    r = r + 2
  end
  local any = false
  for _, s in ipairs(d.store or {}) do
    for _, part in ipairs({ { s.inner, "cells", s.kind ~= "Item" }, { s.ext, "storage buses", s.kind ~= "Item" } }) do
      local st = part[1]
      if st and st.max and st.max > 0 and r + 1 <= y + h - 2 then
        any = true
        local f = pct(st.used, st.max)
        local v = (part[3] and fmtBuckets(st.used) .. " / " .. fmtBuckets(st.max)) or (compact(st.used) .. " / " .. compact(st.max))
        meter(ix, r, iw, s.kind .. "s in " .. part[2], v, f, fillCol(f))
        r = r + 2
      end
    end
  end
  if not any and r <= y + h - 2 then text(ix, r, "No storage numbers from this bridge.", C.dim, C.panel) end
end

local function drivesPanel(x, y, w, h)
  local d = MEX.data or {}
  local drives = d.drives
  local ix, iy, iw = panel(x, y, w, h, "DRIVES", { right = drives and (#drives .. " drives") or nil })
  if not drives then
    -- older bridges: the cells only (summed by kind on the AE2 page)
    local me = state.me or {}
    if #(me.cellTypes or {}) == 0 then nope(ix, iy, iw, "The drive list") return end
    local r = iy
    for _, ct in ipairs(me.cellTypes) do
      if r + 1 > y + h - 2 then break end
      local f = pct(ct.used, ct.total)
      meter(ix, r, iw, ct.n .. "x " .. ct.label, math.floor(f * 100 + 0.5) .. "% full", f, fillCol(f))
      r = r + 2
    end
    return
  end
  local r = iy
  for i, dr in ipairs(drives) do
    if r + 1 > y + h - 2 then
      text(ix, y + h - 2, "+" .. (#drives - i + 1) .. " more drives", C.dim, C.panel)
      break
    end
    local f = pct(dr.used, dr.bytes)
    meter(ix, r, iw, dr.name .. (dr.pos and ("  " .. dr.pos) or "") .. "  " .. #dr.cells .. " cells",
          math.floor(f * 100 + 0.5) .. "%", f, fillCol(f))
    r = r + 2
    -- its cells, two to a row
    local cw = math.floor((iw - 1) / 2)
    for c, cell0 in ipairs(dr.cells) do
      if r > y + h - 2 then break end
      local cx = ix + ((c - 1) % 2) * (cw + 1)
      local cf = pct(cell0.used, cell0.bytes)
      local v = math.floor(cf * 100 + 0.5) .. "%"
      led(cx, r, fillCol(cf))
      text(cx + 2, r, trunc(cell0.name, math.max(1, cw - #v - 3)), C.dim, C.panel)
      text(cx + cw - #v, r, v, C.text, C.panel)
      if c % 2 == 0 or c == #dr.cells then r = r + 1 end
    end
    r = r + 1
  end
end

-- the patterns to list: filtered by type and first letter, sorted by the output's name
-- (cached: 1000+ patterns are not sorted on every draw)
local function itemName(n)
  local me = state.me or {}
  local e = (me.byName and me.byName[n]) or (me.byNameF and me.byNameF[n])
  return (e and e.display) or prettify(tostring(n))
end
local function patView()
  local key = tostring(MEX.patterns) .. "|" .. tostring(state.patType or "all") .. "|" .. tostring(state.patLetter or "")
  if MEX.pv and MEX.pv.key == key then return MEX.pv.list end
  local list = {}
  for i, p in ipairs(MEX.patterns or {}) do
    if not state.patType or p.type == state.patType then
      local nm
      if p.out then nm = itemName(p.out)
      else
        -- no output name (a chemical): named by what goes in, listed after the named ones
        local ins = {}
        for k2, x in ipairs(p.ins) do if k2 <= 2 then ins[#ins + 1] = itemName(x.name) end end
        nm = "~chemical" .. (#ins > 0 and (" from " .. table.concat(ins, ", ")) or " (nothing named)")
      end
      local c = nm:sub(1, 1):upper()
      local L = state.patLetter
      if not L or (L == "#" and not c:match("%a")) or c == L then
        list[#list + 1] = { p = p, name = nm, key = tostring(p.out) .. "|" .. p.type .. "|" .. i }
      end
    end
  end
  table.sort(list, function(a2, b2) return a2.name < b2.name end)
  MEX.pv = { key = key, list = list }
  return list
end
-- what AE2 has of an item / fluid (0 when not known)
local function haveOf(n)
  local me = state.me or {}
  local e = (me.byName and me.byName[n]) or (me.byNameF and me.byNameF[n])
  return e and (tonumber(e.count) or 0) or 0, (me.byNameF and me.byNameF[n]) ~= nil
end

local function patternsPanel(x, y, w, h)
  local ix, iy, iw = panel(x, y, w, h, "PATTERNS", { right = MEX.patterns and (#MEX.patterns .. " patterns") or nil })
  if not MEX.patterns then
    nope(ix, iy, iw, "The pattern list")
    return
  end
  local bottom = y + h - 2
  -- type filter (2-row buttons, wrap)
  local byType = {}
  for _, p in ipairs(MEX.patterns) do byType[p.type] = (byType[p.type] or 0) + 1 end
  local chips = { { nil, "ALL " .. #MEX.patterns } }
  for _, t in ipairs({ "crafting", "processing", "smithing", "stonecutting", "unknown" }) do
    if byType[t] then chips[#chips + 1] = { t, t:upper() .. " " .. byType[t] } end
  end
  local bx, by = ix, iy
  for _, c in ipairs(chips) do
    local bw = #c[2] + 2
    if bx > ix and bx + bw > ix + iw then bx, by = ix, by + 3 end
    local on = state.patType == c[1]
    button(bx, by, bw, 2, c[2], on and C.accent or C.line, "pattype", c[1] or "all", on)
    bx = bx + bw + 1
  end
  -- first letter (2-row buttons)
  local ly = by + 3
  local toks = { { "ALL", false } }
  for c = 65, 90 do toks[#toks + 1] = { string.char(c), string.char(c) } end
  toks[#toks + 1] = { "#", "#" }
  local lw = math.max(2, math.floor((iw - 5) / (#toks - 1)))
  local lx = ix
  for k, t in ipairs(toks) do
    local tw = (k == 1) and 5 or lw                         -- ("ALL" + its margins)
    if lx + tw - 1 > ix + iw - 1 then break end
    local on = (state.patLetter == (t[2] or nil))
    button(lx, ly, tw, 2, t[1], on and C.accent or C.line, "patletter", t[2] or "all", on)
    lx = lx + tw
  end
  -- the picked pattern (by its key; else the item picked on the AE2 page)
  local view = patView()
  local sel
  for _, v in ipairs(view) do if v.key == state.patSel then sel = v end end
  if not sel and state.meSel and MEX.byOut and MEX.byOut[state.meSel] then
    for _, v in ipairs(view) do if v.p.out == state.meSel then sel = v break end end
  end
  local detailH = sel and math.min(8 + #sel.p.ins, math.floor(h * 0.5)) or 0
  -- the list (1 row per pattern; tap = pick; arrows in the top line scroll)
  local r0 = ly + 3
  local rows = math.max(1, (bottom - detailH) - r0 + 1)
  local off = scrollBar(x, y, w, "patOff", #view, rows)
  if #view == 0 then text(ix, r0, "No pattern matches this filter.", C.dim, C.panel) end
  for i = 1, rows do
    local v = view[off + i]
    if not v then break end
    local ry = r0 + i - 1
    local on = sel and v.key == sel.key
    local bg = rowBg(ix, ry, iw, on)
    local tag = v.p.type
    local amt = v.p.outN > 1 and ("x" .. v.p.outN .. "  ") or ""
    local shown = v.name:gsub("^~", "")
    text(ix + 1, ry, trunc(shown, iw - #tag - #amt - 3), on and C.accent or (v.p.out and C.text or C.dim), bg)
    text(ix + iw - #tag - #amt, ry, amt .. tag, C.dim, bg)
    addHit(ix, ry, iw, 1, "patsel", v.key)
  end
  if not sel then return end
  -- the picked one: what goes in (vs what AE2 has), what comes out, CRAFT
  local dy = bottom - detailH + 2
  heading(ix, dy - 1, iw, (sel.p.out and ("MAKES " .. sel.p.outN .. " x " .. sel.name) or "MAKES A CHEMICAL"):upper())
  local r = dy
  for _, inp in ipairs(sel.p.ins) do
    if r > bottom - 4 then break end
    local have = haveOf(inp.name)
    local enough = have >= inp.n
    led(ix, r, enough and C.good or C.bad)
    kv(ix + 2, r, iw - 2, commas(inp.n) .. " x " .. itemName(inp.name), (enough and "" or "SHORT - ") .. "AE2 has " .. compact(have),
       enough and C.dim or C.bad)
    r = r + 1
  end
  if (sel.p.unknownIn or 0) > 0 and r <= bottom - 4 then
    text(ix, r, "+ " .. sel.p.unknownIn .. " chemical(s) the bridge cannot name", C.dim, C.panel)
    r = r + 1
  end
  local used = sel.p.out and MEX.byIn and MEX.byIn[sel.p.out]
  if r <= bottom - 4 then
    text(ix, r, sel.p.type .. " pattern" .. (used and ("  -  used in " .. used .. " other pattern(s)") or ""), C.dim, C.panel)
  end
  if not sel.p.out then
    para(ix, bottom - 2, iw, "Its output is a chemical: this Advanced Peripherals cannot name it, so it cannot be crafted from here " ..
         "(an AE2 terminal can).", C.dim, 3)
    return
  end
  local _, isFluid = haveOf(sel.p.out)
  local cw = math.floor((iw - 3) / 4)
  local amounts = isFluid and { { "1 B", 1000 }, { "16 B", 16000 }, { "64 B", 64000 }, { "256 B", 256000 } }
                  or { { "x1", 1 }, { "x16", 16 }, { "x64", 64 }, { "x256", 256 } }
  for k, a2 in ipairs(amounts) do
    actButton(ix + (k - 1) * (cw + 1), bottom - 2, (k == 4) and (iw - 3 * (cw + 1)) or cw, 3, "CRAFT " .. a2[1],
              { kind = isFluid and "fcraft" or "craft", name = sel.p.out, count = a2[2] }, false, C.good)
  end
end

function drawMESysPage(G)
  if not bridge then
    drawMessage("NO ME / RS BRIDGE", deviceHelpLines("ME/RS Bridge"), C.warn)
    return
  end
  if not MEX.data then
    drawMessage("LOADING", { "Reading the crafting CPUs, jobs and drives..." }, C.label)
    return
  end
  local y0, y1 = G.y0, G.y1
  local lw = math.floor((W - 3) * 0.55)
  local rx = 2 + lw + 1
  local rw = W - rx
  local d = MEX.data
  -- left: CPUs (as tall as they are), jobs, your requests
  local nCpu = d.cpus and math.max(1, #d.cpus) or 1
  local ch = math.min(3 + nCpu * 3, math.floor((y1 - y0 + 1) * 0.35))
  cpuPanel(2, y0, lw, ch)
  CLIP = nil
  local nJob = d.tasks and math.max(1, #d.tasks) or 1
  local jy = y0 + ch + 1
  local jh = math.min(3 + nJob * 3, math.floor((y1 - jy + 1) * 0.5))
  jobsPanel(2, jy, lw, jh)
  CLIP = nil
  local my = jy + jh + 1
  if y1 - my + 1 >= 5 then minePanel(2, my, lw, y1 - my + 1) end
  CLIP = nil
  -- right: storage + energy, drives, patterns
  local sh = 0
  for _, s in ipairs(d.store or {}) do
    if s.inner then sh = sh + 2 end
    if s.ext then sh = sh + 2 end
  end
  sh = math.max(6, math.min(sh + 3 + 4, math.floor((y1 - y0 + 1) * 0.3)))   -- (patterns need the room)
  storagePanel(rx, y0, rw, sh)
  CLIP = nil
  local dy = y0 + sh + 1
  local rest = y1 - dy + 1
  -- drives: only when the bridge lists them (or the AE2 page has cell sums) - an empty
  -- "not on this bridge" panel took half the column (storage buses only: no drives)
  local hasDrives = d.drives or #((state.me or {}).cellTypes or {}) > 0
  local py = dy
  if hasDrives then
    local need = 3
    for _, dr in ipairs(d.drives or {}) do need = need + 3 + math.ceil(#dr.cells / 2) end
    if not d.drives then need = 3 + 2 * #((state.me or {}).cellTypes or {}) end
    local dh = math.max(5, math.min(need, math.floor(rest * 0.35)))
    drivesPanel(rx, dy, rw, dh)
    CLIP = nil
    py = dy + dh + 1
  end
  if y1 - py + 1 >= 5 then patternsPanel(rx, py, rw, y1 - py + 1) end
  CLIP = nil
end
