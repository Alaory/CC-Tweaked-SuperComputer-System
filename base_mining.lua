-- base_mining.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   MINING TEAMS in a mining dimension (miner.lua on two turtles: a MINER and
--   a LOADER). They talk over the same protocol as the other turtles, marked
--   m.mine, and are kept apart from them (state.turtles is overworld only:
--   map, surveys, homes, rescue never see them).
--   The miner swaps its modem in only now and then, so commands wait in a
--   queue (u.queue) until its report says it has them (m.lastCmd).

MINE = { units = {}, dirty = false, saved = 0 }
local FILE = "mining.dat"

-- settings (CONFIG.mining in base_config.lua and the SETTINGS page)
function MINE.cfg(k, default)
  local m = CONFIG.mining
  local v
  if type(m) == "table" then v = m[k] end
  if v == nil then return default end
  return v
end
-- what the turtles get as "cfg" (strings only: they are part of the signature)
function MINE.cfgArgs()
  local function list(v)
    if type(v) ~= "table" then return "" end
    local out = {}
    for _, s in ipairs(v) do out[#out + 1] = tostring(s) end
    return table.concat(out, ",")
  end
  return { "dumpEvery=" .. tostring(MINE.cfg("dumpEvery", 600)),
           "rowLength=" .. tostring(MINE.cfg("rowLength", 16)),
           "noMine=" .. tostring(MINE.cfg("noMine", 64)),
           "want=" .. list(MINE.cfg("want", {})),
           "keep=" .. list(MINE.cfg("keep", {})),
           "extraOres=" .. list(MINE.cfg("ores", {})),
           "skipOres=" .. list(MINE.cfg("skipOres", {})),
           "fuelItems=" .. list(MINE.cfg("fuelItems", { "*mining_dim_core*" })) }
end

function MINE.load()
  local path = dataPath and dataPath(FILE) or FILE     -- (a data floppy when there is one)
  local t = readSafe(path)
  if type(t) == "table" then
    for id, u in pairs(t) do
      local uid = tonumber(id) or (type(u) == "table" and tonumber(u.id))
      if uid and type(u) == "table" then          -- (an odd / old file: kept out like a bad message)
        -- (only what MINE.save writes; odd values cleaned like a bad message)
        local c = { label = u.label, role = u.role, dim = u.dim, got = u.got, stats = u.stats, pos = u.pos }
        if TT.clean then TT.clean(c) end
        local log = {}
        for _, e in ipairs(type(u.log) == "table" and u.log or {}) do if type(e) == "table" then log[#log + 1] = e end end
        c.id, c.log, c.queue, c.seenEpoch = uid, log, {}, tonumber(u.seenEpoch)
        MINE.units[uid] = c
      end
    end
  end
end
function MINE.save()
  local out = {}
  for id, u in pairs(MINE.units) do
    out[id] = { id = u.id, label = u.label, role = u.role, dim = u.dim, got = u.got, stats = u.stats,
                seenEpoch = u.seenEpoch, pos = u.pos, log = u.log }
  end
  saveFileSafe(dataPath and dataPath(FILE) or FILE, serialSmall(out))
  MINE.dirty, MINE.saved = false, os.clock()
end
MINE.load()

function MINE.log(u, msg)
  local okD, t = pcall(os.date, "%H:%M")
  table.insert(u.log, 1, { t = okD and t or "", e = os.epoch("utc"), msg = msg })
  while #u.log > 30 do table.remove(u.log) end
end

-- seen recently? (the miner reports every ~30 s; long tunnels take longer)
function MINE.online(u)
  local limit = (u.role == "miner") and 150 or 60
  return u.lastSeen ~= nil and os.clock() - u.lastSeen < limit
end

-- a command for a unit: queued until its report shows it has it
function MINE.cmd(id, cmd, args, quiet)
  local u = MINE.units[id]
  if not u then return end
  local n = os.epoch("utc")
  if n <= state.tLastN then n = state.tLastN + 1 end
  state.tLastN = n
  local a = {}
  for i, v in ipairs(args or {}) do a[i] = tostring(v) end
  -- while it has COPIES (server crash) only the real one obeys (its session)
  local ses = (u.dups and #u.dups > 0) and u.mainSes or nil
  local msg = { t = "cmd", n = n, cmd = cmd, args = a, ses = ses, sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) }
  u.queue = u.queue or {}
  u.queue[#u.queue + 1] = msg
  state.tOut[#state.tOut + 1] = { id = id, msg = msg }
  if not quiet then MINE.log(u, "> " .. cmd) end
  os.queueEvent("turtle_send")
end

-- a report from a unit (already checked: signature, m.mine)
function MINE.receive(id, m)
  local u = MINE.units[id]
  if not u then
    u = { id = id, log = {}, queue = {} }
    MINE.units[id] = u
  end
  -- an extra COPY of this id (server crash): stopped, its reports kept apart
  if type(m.ses) == "string" and TT.dupSeen and TT.dupSeen(u, id, m, {
       where = true,                       -- (the copy where the real one was stays)
       canUse = function(mm) return mm.role ~= "loader" end,   -- (one loader per dimension: its copies are parked)
       log = function(text) MINE.log(u, text) end,
       stop = function(ses, cmd, args)
         cmd, args = cmd or "dupstop", args or {}
         local n = os.epoch("utc")
         if n <= state.tLastN then n = state.tLastN + 1 end
         state.tLastN = n
         local a = {}
         for i, v in ipairs(args) do a[i] = tostring(v) end
         state.tOut[#state.tOut + 1] = { id = id, msg = { t = "cmd", n = n, cmd = cmd, args = a, ses = ses,
                                                          sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) } }
         os.queueEvent("turtle_send")
       end }) then return end
  if m.n <= (u.lastN or 0) then return end
  u.lastN = m.n
  u.lastSeen, u.seenEpoch = os.clock(), os.epoch("utc")
  for _, k in ipairs({ "label", "role", "dim", "task", "fuel", "fuelMax", "free", "pos", "partner", "running", "err",
                       "ci", "li", "nl", "phase", "station", "carry", "got", "stats", "ver", "rowLength",
                       "team", "leader", "ready", "idx", "transit", "code", "updReady" }) do
    u[k] = m[k]
  end
  -- ores per hour: counted from when it was first seen running
  local ores = type(u.stats) == "table" and tonumber(u.stats.ores) or 0
  if u.running then
    if not u.runT0 then u.runT0, u.ores0 = os.clock(), ores end
  else
    u.runT0, u.ores0 = nil, nil
  end
  u.nextDump = m.nextDump and (os.clock() + m.nextDump) or nil
  for _, msg in ipairs(type(m.notes) == "table" and m.notes or {}) do
    msg = tostring(msg)
    MINE.log(u, msg)
    if msg:find("STOPPED", 1, true) or msg:find("Could not", 1, true) or msg:find("failed", 1, true)
       or msg:find("STUCK", 1, true) or msg:find("full", 1, true) then
      pushNote("WARNING", (u.label or ("#" .. id)) .. ": " .. msg, C.warn)
      if sysLog then sysLog("Mining " .. tostring(u.dim) .. ": " .. (u.label or ("#" .. id)) .. " - " .. msg, "WARNING") end
    end
  end
  -- commands it does not have yet: again
  local keep = {}
  for _, q in ipairs(u.queue or {}) do
    if q.n > (tonumber(m.lastCmd) or 0) then
      keep[#keep + 1] = q
      state.tOut[#state.tOut + 1] = { id = id, msg = q }
    end
  end
  u.queue = keep
  -- settings changed (or never sent): send them
  local cfg = MINE.cfgArgs()
  local key = table.concat(cfg, ";")
  if u.cfgSent ~= key then
    u.cfgSent = key
    MINE.cmd(id, "cfg", cfg, true)
  end
  if #keep > 0 then os.queueEvent("turtle_send") end
  MINE.dirty = true
  if os.clock() - MINE.saved > 60 then pcall(MINE.save) end
end

-- teams per dimension: { loader = u, miners = { u, ... } (by ID), miner = miners[1] }
function MINE.teams()
  local t = {}
  for _, u in pairs(MINE.units) do
    local d = u.dim or "?"
    t[d] = t[d] or { miners = {} }
    if u.role == "loader" then
      local cur = t[d].loader
      if not cur or (u.seenEpoch or 0) > (cur.seenEpoch or 0) then t[d].loader = u end
    elseif u.role == "miner" then
      t[d].miners[#t[d].miners + 1] = u
    end
  end
  for _, team in pairs(t) do
    table.sort(team.miners, function(a, b) return a.id < b.id end)
    team.miner = team.miners[1]
  end
  return t
end
-- the whole team together: ores, unloads, delivered / carried items, ores per hour
function MINE.totals(team)
  local T = { ores = 0, dumps = 0, got = {}, carry = {}, rate = 0, ci = team.loader and team.loader.ci }
  -- (the chunks crossed in the air to get away from the unload station do not count)
  local tr = team.loader and tonumber(team.loader.transit)
  if T.ci and tr then T.ci, T.moving = math.max(0, T.ci - tr), T.ci < tr end
  for _, m in ipairs(team.miners or {}) do
    local st = type(m.stats) == "table" and m.stats or {}
    T.ores, T.dumps = T.ores + (tonumber(st.ores) or 0), T.dumps + (tonumber(st.dumps) or 0)
    for k, v in pairs(m.got or {}) do T.got[k] = (T.got[k] or 0) + v end
    for k, v in pairs(m.carry or {}) do T.carry[k] = (T.carry[k] or 0) + v end
    if m.runT0 and os.clock() - m.runT0 > 300 then
      T.rate = T.rate + ((tonumber(st.ores) or 0) - (m.ores0 or 0)) / ((os.clock() - m.runT0) / 3600)
    end
  end
  return T
end

-- what is the miner / loader doing: LABEL, colour, line
function MINE.status(u)
  if not u then return "MISSING", C.bad, "no turtle yet - run miner.lua on it" end
  if not MINE.online(u) then
    return "OFFLINE", C.bad, "last seen " .. (u.seenEpoch and TT.ago(u.seenEpoch) or "never")
  end
  local task = tostring(u.task or "")
  local fuel = tonumber(u.fuel)
  if fuel and fuel < 100 then
    return "NO FUEL", C.bad, "fuel " .. fuel .. " - put coal in it and type  refuel all  on the turtle"
  end
  if u.role == "loader" and fuel and fuel < 2000 then
    return "LOW FUEL", C.warn, "fuel " .. fuel .. " - give it fuel: an endless fuel item (if your pack has one) or coal"
  end
  if u.role == "loader" then
    if task:find("STUCK", 1, true) or task:find("blocked", 1, true) then return "BLOCKED", C.bad, task end
    if u.err and not u.running then return "STOPPED", C.bad, tostring(u.err) end
    if not u.partner then return "NO MINERS", C.warn, task end
    if not u.running then return "PAUSED", C.label, task end
    if task:find("crossing", 1, true) then return "MOVING", C.good, task end
    return "LOADING", C.good, task
  end
  if u.err and not u.running then return "STOPPED", C.bad, tostring(u.err) end
  if not u.partner then return "NO LOADER", C.warn, task end
  if not u.running then return "PAUSED", C.label, task end
  if task:find("teleport", 1, true) or task:find("unload", 1, true) or task:find("Import", 1, true) then
    return "UNLOADING", C.purple, task
  end
  if task:find("waiting for the loader", 1, true) or task:find("ready at my lane", 1, true)
     or task:find("team mate", 1, true) or task:find("asking the loader", 1, true) then
    return "WAITING", C.label, task
  end
  return "MINING", C.good, task
end

-- a miner that is gone for good (deleted by a server crash): out of its team -
-- the loader hands its work to the others (console  mine drop  / DROP button)
function MINE.drop(id)
  local u = MINE.units[id]
  if not u then return false, "no mining turtle #" .. tostring(id) end
  if u.role ~= "miner" then
    -- a lost LOADER: off the list; its miners join a new loader by themselves
    -- (after 10 min without a word from the old one - miner.lua m15)
    MINE.units[id] = nil
    pcall(MINE.save)
    return true, "loader #" .. id .. " forgotten. Put a new loader (miner.lua, role l) in the same dimension: " ..
                 "the miners join it after 10 min without their old loader, then press START TEAM"
  end
  local team = MINE.teams()[u.dim or "?"]
  local l = team and team.loader
  if not l then return false, "no loader for " .. tostring(u.dim) .. " - nothing to drop it from" end
  MINE.cmd(l.id, "drop", { id })
  MINE.units[id] = nil
  pcall(MINE.save)
  return true, "the loader #" .. l.id .. " takes miner #" .. id .. " out of the team (its layer goes to the others)" ..
               (MINE.online(l) and "" or " - the loader is offline: it gets this when it reports again")
end

-- ===== MINER UPDATES (mine update; miner.lua m21+) =====
-- miner.lua is NOT kept on this computer (1 MB): `mine update` downloads it from GitHub
-- (upgrade.lua, checked: size, checksum, compiles) and keeps it on a DATA FLOPPY
-- (miner_code.lua via dataFile; the computer only when there is no floppy). A miner.lua
-- dragged next to inventory.lua is used first (and moved onto the floppy).
-- Sending: every RUNNING team is PAUSED first (just in case), then each online turtle
-- whose program checksum (m.code) differs gets the program in pieces; a turtle installs
-- it only while paused (never in a crossing) and restarts - its state file (role, team,
-- field, job, station) is separate, so it carries on. Once the whole team runs it, the
-- base presses START again for the teams it paused. Turtles with m20 or older report no
-- checksum: copy miner.lua onto them by hand once; their team is left alone.
MINE.CODE_FILE = "miner_code.lua"
MINE.PIECE = 8000
function MINE.codeHash(text)                     -- (the same as miner.lua's codeHash / make_manifest h)
  local h = 0
  for i = 1, #text, 64 do
    local b = { string.byte(text, i, math.min(#text, i + 63)) }
    for k = 1, #b do h = (h * 31 + b[k]) % 4294967296 end
  end
  return string.format("%08x", h)
end
local function readAll(p)
  if not (p and fs.exists(p)) or fs.isDir(p) then return nil end
  local h = fs.open(p, "rb")
  if not h then return nil end
  local s = h.readAll()
  h.close()
  return s
end
-- the program as { text, ver, pieces, from } (nil + why)
function MINE.setCode(text, from)
  local fn, err = load(text, "=miner.lua", "t", {})
  if not fn then return nil, "miner.lua does not compile: " .. tostring(err) end
  if not text:find("MYVER", 1, true) then return nil, "that is not miner.lua" end
  local pieces = {}
  for i = 1, #text, MINE.PIECE do pieces[#pieces + 1] = text:sub(i, i + MINE.PIECE - 1) end
  local mv = text:match('MYVER%s*=%s*"([^"]+)"')
  MINE.code = { text = text, ver = MINE.codeHash(text), pieces = pieces, from = from, myver = mv }
  return MINE.code
end
-- WHERE IT IS KEPT (the owner's `disks`: "disk13/miner_code.lua not saved (45 KB free, needs 82 KB)" with ~2.5 MB free on
-- the storage helpers): like node.lua (TT.codeStore) - a STORAGE HELPER with room first (read back to check), else a data
-- floppy; miner_where.dat says where. The old copy elsewhere is deleted (a full floppy gets its room back).
MINE.WHERE_FILE = "miner_where.dat"
function MINE.codeWhere()
  local okR, w = pcall(readSafe, MINE.WHERE_FILE)
  if okR and type(w) == "table" and type(w.path) == "string" then return w end
  return nil
end
-- the stored program's text (a helper copy is asked over the cable), else nil
function MINE.readStored()
  local w = MINE.codeWhere()
  if w then
    if STORE and STORE.isRemote(w.path) then
      local okR, t = pcall(STORE.read, w.path)
      if okR and type(t) == "string" and #t > 0 then return t end
    else
      local t = readAll(w.path)
      if t then return t end
    end
  end
  return readAll(dataFile and dataFile(MINE.CODE_FILE) or MINE.CODE_FILE)
end
-- keep it: true + where | false + why
function MINE.storeCode(text)
  local w = MINE.codeWhere()
  if w and MINE.readStored() == text then return true, w.path end
  local where
  if STORE and STORE.helpers then
    local ids = {}
    for id, h in pairs(STORE.helpers) do
      if STORE.usable(h) and (h.free or 0) >= #text + 32 * 1024 then ids[#ids + 1] = id end
    end
    local oldId = w and STORE.parse(w.path)
    table.sort(ids, function(a, b)
      if (a == oldId) ~= (b == oldId) then return a == oldId end
      return (STORE.helpers[a].free or 0) > (STORE.helpers[b].free or 0)
    end)
    for _, id in ipairs(ids) do
      local p = "store:" .. id .. "/" .. MINE.CODE_FILE
      local okW = pcall(STORE.write, p, text)
      local okR, back = pcall(STORE.read, p)
      if okW and okR and back == text then where = p break end
    end
  end
  if not where then
    local p = dataFile and dataFile(MINE.CODE_FILE, true) or MINE.CODE_FILE
    if readAll(p) == text then where = p
    else
      local okS = saveFileSafe(p, text)
      if okS ~= false and fs.exists(p) then where = p end
    end
  end
  if not where then
    return false, "no room for miner.lua (" .. math.ceil(#text / 1024) .. " KB): no storage helper / data floppy with that much free"
  end
  writeSafe(MINE.WHERE_FILE, serialSmall({ path = where }))
  -- the copy that was somewhere else goes (a floppy gets its room back)
  if w and w.path ~= where then
    if STORE and STORE.isRemote(w.path) then pcall(STORE.delete, w.path) elseif fs.exists(w.path) then pcall(fs.delete, w.path) end
  end
  if STORE and STORE.isRemote(where) then
    for _, d in ipairs(mountedDisks and mountedDisks() or {}) do
      local p = fs.combine(d.mount, MINE.CODE_FILE)
      if fs.exists(p) then pcall(fs.delete, p) end
    end
    if fs.exists(MINE.CODE_FILE) then pcall(fs.delete, MINE.CODE_FILE) end
  end
  return true, where
end
-- find the program: a miner.lua dragged in > the stored copy; download = GitHub first
-- the NEWEST of: a miner.lua dragged next to inventory.lua, GitHub (download), the stored copy.
-- (Before: a miner.lua lying next to inventory.lua always won - an OLD one dragged in once kept
-- "mine update" on that version.) The winner is kept on the data storage; a dragged file is
-- moved there (or deleted when it is older).
function MINE.verNum(text)
  return tonumber(tostring(text or ""):match('MYVER%s*=%s*"m(%d+)"')) or -1
end
function MINE.loadCode(download, log)
  log = log or function() end
  local cands = {}
  local here = fs.combine(BASE_DIR or "", "miner.lua")
  local hereText = readAll(here)
  if hereText then cands[#cands + 1] = { text = hereText, from = "miner.lua on this computer" } end
  if download and http then
    local path = fs.combine(BASE_DIR or "", "upgrade.lua")
    local fn = fs.exists(path) and loadfile(path, "t", _ENV)
    if fn then
      local okR, done, body, v = pcall(fn, { fetch = "miner.lua", group = "miner", dir = BASE_DIR or "", log = log })
      if okR and done and type(body) == "string" then cands[#cands + 1] = { text = body, from = "GitHub " .. tostring(v) }
      else log("Download did not work - using what is here") end
    end
  end
  local stored = MINE.readStored()
  if stored then cands[#cands + 1] = { text = stored, from = "the stored copy" } end
  if #cands == 0 then
    return nil, "no miner.lua: drag one onto this computer (next to inventory.lua) or allow http for  mine update"
  end
  local best, why
  for _, c in ipairs(cands) do
    local okC, e = MINE.setCode(c.text, c.from)     -- (must compile and be miner.lua)
    if okC then
      c.n = MINE.verNum(c.text)
      if not best or c.n > best.n then best = c end
    else
      why = e
    end
  end
  if not best then return nil, why end
  if #cands > 1 then
    local list = {}
    for _, c in ipairs(cands) do list[#list + 1] = c.from .. " = m" .. tostring(c.n or "?") end
    log("Found " .. table.concat(list, ", ") .. " - using the newest: " .. best.from)
  end
  local c = MINE.setCode(best.text, best.from)
  local okS, where = MINE.storeCode(best.text)
  if okS and hereText then
    pcall(fs.delete, here)                          -- (kept on the data storage now, or it was older)
    log("miner.lua next to inventory.lua " .. (best.text == hereText and "moved onto the data storage" or "was older - removed"))
  elseif not okS then
    log("Not kept: " .. tostring(where))
  end
  return c
end

-- the units that can be updated; whole teams (dim) with an old program are skipped
function MINE.updPlan(ver)
  local teams = MINE.teams()
  local plan = { send = {}, old = {}, skipDim = {} }
  for d, team in pairs(teams) do
    local members = { team.loader }
    for _, m in ipairs(team.miners) do members[#members + 1] = m end
    local oldIds = {}
    for _, u in ipairs(members) do
      if u and MINE.online(u) and u.code == nil then oldIds[#oldIds + 1] = "#" .. u.id end
    end
    if #oldIds > 0 then
      plan.skipDim[d] = oldIds
      for _, s in ipairs(oldIds) do plan.old[#plan.old + 1] = s end
    else
      for _, u in ipairs(members) do
        if u and MINE.online(u) and u.code ~= ver then plan.send[#plan.send + 1] = u end
      end
    end
  end
  return plan
end

-- `mine update`: pause the running teams, send, start them again (lines for the console)
function MINE.startUpdate(code)
  local out = {}
  MINE.code = code or MINE.code
  local c = MINE.code
  if not c then return { "No miner.lua to send." } end
  local plan = MINE.updPlan(c.ver)
  local U = { ver = c.ver, t0 = os.clock(), last = -99, resume = {}, dims = {}, sent = 0 }
  for d, team in pairs(MINE.teams()) do
    if not plan.skipDim[d] then
      U.dims[d] = true
      local l = team.loader
      if l and l.running and MINE.online(l) then
        MINE.cmd(l.id, "pause")
        U.resume[l.id] = d
        out[#out + 1] = "Team in " .. tostring(d) .. " PAUSED for the update - started again when all of it runs the new program"
      end
    else
      out[#out + 1] = "Team in " .. tostring(d) .. " left alone: " .. table.concat(plan.skipDim[d], " ") ..
                      " run m20 or older - copy miner.lua onto them by hand once, after that  mine update  works"
    end
  end
  if #plan.send == 0 then
    out[#out + 1] = "Every mining turtle that can be updated already runs this program (" .. tostring(c.myver) .. ")."
    for id in pairs(U.resume) do MINE.cmd(id, "start") end
    MINE.upd = nil
    return out
  end
  MINE.upd = U
  out[#out + 1] = ("Sending miner.lua %s (%s, %d KB) to %d turtle(s); each installs it while paused and restarts.")
                  :format(tostring(c.myver), c.from or "?", math.ceil(#c.text / 1024), #plan.send)
  MINE.updTick()
  return out
end

-- the pieces straight to the sender (not into u.queue: that resends on every report)
function MINE.sendCode(u)
  local c = MINE.code
  if not c then return end
  for i, p in ipairs(c.pieces) do
    local n = os.epoch("utc")
    if n <= state.tLastN then n = state.tLastN + 1 end
    state.tLastN = n
    local a = { c.ver, tostring(i), tostring(#c.pieces), p }
    local ses = (u.dups and #u.dups > 0) and u.mainSes or nil
    state.tOut[#state.tOut + 1] = { id = u.id, msg = { t = "cmd", n = n, cmd = "upd", args = a, ses = ses,
                                    sig = TT.sign(CONFIG.turtles.key, "cmd", n, "upd", a) } }
  end
  u.updSentAt = os.clock()
  os.queueEvent("turtle_send")
end

-- comms worker (every 2 s; works every 20 s): send to who still runs the old one,
-- start the paused teams that are done, give up after 1 h
function MINE.updTick()
  local U, c = MINE.upd, MINE.code
  if not U or not c or c.ver ~= U.ver then return end
  if os.clock() - U.last < 20 then return end
  U.last = os.clock()
  local teams = MINE.teams()
  local left = 0
  for d in pairs(U.dims) do
    local team = teams[d]
    local members = team and { team.loader } or {}
    for _, m in ipairs(team and team.miners or {}) do members[#members + 1] = m end
    local todo = 0
    for _, u in ipairs(members) do
      if u and MINE.online(u) and u.code ~= nil and u.code ~= U.ver then
        todo = todo + 1
        -- (it says it has it complete: wait for the install, else send again every 60 s)
        if u.updReady ~= U.ver and os.clock() - (u.updSentAt or -999) > 60 then
          MINE.sendCode(u)
          U.sent = U.sent + 1
          MINE.log(u, "> update " .. tostring(c.myver) .. " sent")
        end
      end
    end
    left = left + todo
    if todo == 0 then
      for id, dd in pairs(U.resume) do
        if dd == d then
          MINE.cmd(id, "start")
          U.resume[id] = nil
          pushNote("DONE", "Mining team in " .. tostring(d) .. " updated to " .. tostring(c.myver) .. " - started again", C.good)
        end
      end
      U.dims[d] = nil
    end
  end
  if left == 0 and not next(U.dims) then
    MINE.upd = nil
    pushNote("DONE", "Mining turtles updated to " .. tostring(c.myver), C.good)
    if sysLog then sysLog("Mining turtles updated to miner.lua " .. tostring(c.myver), "INFO") end
  elseif os.clock() - U.t0 > 3600 then
    for id in pairs(U.resume) do MINE.cmd(id, "start") end
    MINE.upd = nil
    pushNote("WARNING", "Miner update: " .. left .. " turtle(s) did not take the new program in 1 h - teams started again", C.warn)
  end
end

-- ===== A MINER GOES SILENT (comms worker): one WARNING with where it was last =====
-- (a server crash can delete a turtle - "no trace of it"; the team pauses after 20 min
-- and drops it after CONFIG.mining.autoDrop min by itself). Says where to look: the last
-- position, dimension, job and its last log line. Again only after it spoke in between.
function MINE.silentTick()
  local limit = tonumber(MINE.cfg("silentWarn", 900)) or 900          -- s
  for id, u in pairs(MINE.units) do
    if u.lastSeen and os.clock() - u.lastSeen > limit then
      if not u.silentSaid then
        u.silentSaid = true
        local p = u.pos
        local where = (type(p) == "table" and p.x) and (p.x .. " " .. p.y .. " " .. p.z) or "unknown"
        local last = u.log and u.log[1] and u.log[1].msg or "-"
        local line = (u.label or ("#" .. id)) .. " (" .. tostring(u.role) .. ", " .. tostring(u.dim) .. ") is SILENT for " ..
                     math.floor((os.clock() - u.lastSeen) / 60) .. " min - last seen at " .. where ..
                     " doing '" .. tostring(u.task or "?") .. "'; last note: " .. tostring(last)
        MINE.log(u, line)
        if sysLog then sysLog("Mining: " .. line, "WARNING") end
        pushNote("WARNING", line, C.warn)
      end
    elseif u.silentSaid and u.lastSeen and os.clock() - u.lastSeen < 60 then
      u.silentSaid = nil
      MINE.log(u, "It reports again")
    end
  end
end
