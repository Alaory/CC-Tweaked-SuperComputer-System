









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
local info = (c.storage and (compact(c.storage) .. "B") or "") .. (c.co and ("  " .. c.co .. " co-proc") or "")
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
meter(ix, r, iw - (bw > 0 and bw + 1 or 0), t.name .. (t.cpu and ("  (" .. t.cpu .. ")") or ""),
commas(t.done) .. " / " .. commas(t.qty), t.f, C.good)
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

local function patternsPanel(x, y, w, h)
local ix, iy, iw = panel(x, y, w, h, "PATTERNS", { right = MEX.patterns and (#MEX.patterns .. " patterns") or nil })
if not MEX.patterns then
nope(ix, iy, iw, "The pattern list")
return
end
local byType = {}
for _, p in ipairs(MEX.patterns) do byType[p.type] = (byType[p.type] or 0) + 1 end
local bx = ix
for _, t in ipairs({ "crafting", "processing", "smithing", "stonecutting", "unknown" }) do
if byType[t] then bx = bx + badge(bx, iy, byType[t] .. " " .. t, C.line, C.text) + 1 end
end
local r = iy + 2
local sel = state.meSel
if not sel then
para(ix, r, iw, "Pick an item on the AE2 page: what it is made from and what uses it shows here.", C.dim, 2)
return
end
local known = state.me and state.me.byName and state.me.byName[sel]
heading(ix, r, iw, (known and known.display or prettify(sel)):upper())
r = r + 1
local list = MEX.byOut and MEX.byOut[sel] or {}
if #list == 0 then
text(ix, r, "No pattern makes it.", C.dim, C.panel)
r = r + 1
end
for _, p in ipairs(list) do
if r > y + h - 2 then break end
local parts = {}
for _, inp in ipairs(p.ins) do
local kn = state.me and state.me.byName and state.me.byName[inp.name]
parts[#parts + 1] = commas(inp.n) .. " " .. ((kn and kn.display) or prettify(inp.name))
end
r = para(ix, r, iw, "makes " .. p.outN .. " (" .. p.type .. ") from " .. table.concat(parts, ", "), C.text,
math.max(1, y + h - 1 - r))
end
local used = MEX.byIn and MEX.byIn[sel]
if r <= y + h - 2 then
text(ix, r, used and ("Used in " .. used .. " other pattern(s)") or "No pattern uses it.", C.dim, C.panel)
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

local sh = 0
for _, s in ipairs(d.store or {}) do
if s.inner then sh = sh + 2 end
if s.ext then sh = sh + 2 end
end
sh = math.max(6, sh + 3 + 4)
storagePanel(rx, y0, rw, sh)
CLIP = nil
local dy = y0 + sh + 1
local rest = y1 - dy + 1
local dh = math.max(5, math.floor(rest * 0.55))
drivesPanel(rx, dy, rw, dh)
CLIP = nil
local py = dy + dh + 1
if y1 - py + 1 >= 5 then patternsPanel(rx, py, rw, y1 - py + 1) end
CLIP = nil
end
