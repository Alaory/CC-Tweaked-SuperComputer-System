-- upgrade.lua  -  gets the newest program files from GitHub: one command
-- instead of dragging every file onto the computer.
--
--   upgrade                  download what changed, check it, restart
--   upgrade check            only show what would change (nothing is written)
--   upgrade branch <name>    use another branch from now on (saved in upgrade.dat)
--   upgrade full / slim      commented files from now on / SLIM ones (no comments or
--                            indentation, ~30% smaller, the same code and line numbers)
--   upgrade packed           the default on the base: the SLIM base_*.lua files PACKED as
--                            base_*.luz (about a third: the plain ones were ~900 KB of the 1 MB
--                            computer); inventory.lua unpacks them when the base starts
--                            (unzip.lua). A plain base_x.lua dragged in by hand is used first.
--
-- Works on the BASE (also typed in the base program's console) and on the
-- POCKET computer (gets pocket.lua). Turtles get node.lua from the base, the
-- storage helpers store.lua - as before.
--
-- Safe: the file list (manifest.txt) has a size + checksum per file; every
-- download must match it and every .lua file must compile, else NOTHING is
-- written. All files come from ONE exact version (commit), never a mix.
-- base_config.lua and data files are never touched. Bytes are written as they
-- are ("wb"), exactly like dragging the file in.
-- First time (on the computer's shell, Ctrl+T stops the base program):
--   wget https://raw.githubusercontent.com/Alaory/CC-Tweaked-SuperComputer-System/main/upgrade.lua upgrade.lua

local REPO = "Alaory/CC-Tweaked-SuperComputer-System"
local DEFAULT_BRANCH = "main"
-- (until the work branch is merged, main has no file list yet: then this one is used)
local FALLBACK_BRANCH = "claude/computercraft-base-review-ihjtqw"
local SAVE = "upgrade.dat"

-- checksum (the same in tools/make_manifest.py)
local function upgradeHash(s, yield)
  local h = 0
  for i = 1, #s, 4096 do
    local stop = math.min(#s, i + 4095)
    for j = i, stop, 64 do
      local b = { string.byte(s, j, math.min(stop, j + 63)) }
      for k = 1, #b do h = (h * 31 + b[k]) % 4294967296 end
    end
    if yield and i % 65536 == 1 then yield() end
  end
  return string.format("%08x", h)
end

local function readBin(path)
  if not fs.exists(path) or fs.isDir(path) then return nil end
  local h = fs.open(path, "rb")
  if not h then return nil end
  local s = h.readAll() or ""
  h.close()
  return s
end

local function writeBin(path, s)
  local ok, err = pcall(function()
    local h = fs.open(path, "wb")
    if not h then error("cannot open " .. path) end
    h.write(s)
    h.close()
  end)
  return ok, err
end

local function loadSaved()
  local s = readBin(SAVE)
  local t = s and textutils.unserialize(s)
  return type(t) == "table" and t or {}
end

-- one download (binary: the bytes as they are)
local function get(url, headers)
  local ok, h, err = pcall(http.get, { url = url, headers = headers, binary = true })
  if not ok then ok, h, err = pcall(http.get, url, headers, true) end
  if not ok or not h then return nil, tostring(err or h or "no answer") end
  local body = h.readAll() or ""
  h.close()
  return body
end

-- the files of this computer: "base" (with inventory.lua) or "pocket"
local function whichGroup()
  if pocket then return "pocket" end
  return "base"
end

-- run it. o = { log = function(text), args = { ... }, dir = folder of the program,
--               yield = function(), restart = function() } (all optional)
--   o.fetch = "miner.lua", o.group = "miner": only DOWNLOAD that file (checked: size,
--   checksum, compiles) and return true, text, version - nothing is written (the base
--   keeps miner.lua on a data floppy and sends it to the mining turtles: mine update)
local function run(o)
  o = o or {}
  local log = o.log or print
  local args = o.args or {}
  local yield = o.yield or function() os.queueEvent("upgrade_yield") os.pullEvent("upgrade_yield") end
  if not http then
    log("This computer cannot use the internet (http is off on this server). Drag the files in instead.")
    return false
  end
  local saved = loadSaved()
  if args[1] == "branch" then
    if not args[2] then log("Branch now: " .. (saved.branch or DEFAULT_BRANCH)) return false end
    saved.branch = args[2]
    writeBin(SAVE, textutils.serialize(saved))
    log("Branch set to " .. args[2] .. ". Type  upgrade  to get its files.")
    return false
  end
  if args[1] == "full" or args[1] == "slim" or args[1] == "packed" then
    saved.full = (args[1] == "full") or nil
    saved.plain = (args[1] == "slim") or nil
    writeBin(SAVE, textutils.serialize(saved))
    log(saved.full and "From now on the FULL files (with comments) - getting them now."
        or saved.plain and "From now on the SLIM files, not packed (no comments, ~30% smaller) - getting them now."
        or "From now on the PACKED files (a third of the size, unpacked when the base starts) - getting them now.")
  end
  local checkOnly = args[1] == "check"
  -- the branch you chose (upgrade branch <name>), else main - and while main has no
  -- file list yet (before the merge), the work branch
  local tryBranches = saved.branch and { saved.branch } or { DEFAULT_BRANCH, FALLBACK_BRANCH }
  local branch, sha, base, man, err
  for _, b in ipairs(tryBranches) do
    branch = b
    -- 1. the exact version (commit) of that branch, so all files match
    log("Asking GitHub for the newest version of " .. branch .. " ...")
    sha = get("https://api.github.com/repos/" .. REPO .. "/commits/" .. textutils.urlEncode(branch),
              { Accept = "application/vnd.github.sha", ["User-Agent"] = "cc-base-upgrade" })
    if sha then sha = sha:match("^%s*(%x+)%s*$") end
    local ref = sha or branch
    base = "https://raw.githubusercontent.com/" .. REPO .. "/" .. ref .. "/"
    -- 2. the file list
    man, err = get(base .. "manifest.txt")
    if man then break end
  end
  if not man then log("Could not read the file list: " .. tostring(err)) return false end
  local group = o.group or whichGroup()
  local list = {}
  -- the SLIM copies ("slim:<group>", from dist/) unless you want the full ones
  local want = saved.full and group or ("slim:" .. group)
  for pass = 1, 2 do
    for line in man:gmatch("[^\n]+") do
      local g, path, size, sum, src = line:match("^(%S+)%s+(%S+)%s+(%d+)%s+(%x+)%s*(%S*)")
      if g == want then list[#list + 1] = { path = path, size = tonumber(size), sum = sum, src = (src ~= "" and src) or nil } end
    end
    if #list > 0 then break end
    want = group                                -- (an older file list: no slim copies)
  end
  if #list == 0 then log("The file list has no files for this computer (" .. group .. ").") return false end
  local dir = o.dir or ""
  -- PACKED (the base, the default): base_x.luz instead of base_x.lua - checked by unpacking it here
  -- (unzip.lua: the copy here if it is the right one, else downloaded and checked first)
  local unz
  if not o.fetch and not saved.full and not saved.plain then
    local zs = {}
    for line in man:gmatch("[^\n]+") do
      local path, size, sum, src = line:match("^z:" .. group:gsub("%p", "%%%0") .. "%s+(%S+)%s+(%d+)%s+(%x+)%s*(%S*)")
      if path then zs[#zs + 1] = { path = path, size = tonumber(size), sum = sum, src = (src ~= "" and src) or nil } end
    end
    if #zs > 0 then
      local uz
      for line in man:gmatch("[^\n]+") do
        local path, size, sum, src = line:match("^slim:unzip%s+(%S+)%s+(%d+)%s+(%x+)%s*(%S*)")
        if path == "unzip.lua" then uz = { path = path, size = tonumber(size), sum = sum, src = (src ~= "" and src) or nil } end
      end
      for _, f in ipairs({ uz }) do
        if f.path == "unzip.lua" then
          local body = readBin(fs.combine(dir, "unzip.lua"))
          if not body or #body ~= f.size or upgradeHash(body, yield) ~= f.sum then
            body = get(base .. (f.src or f.path))
            if body and (#body ~= f.size or upgradeHash(body, yield) ~= f.sum) then body = nil end
          end
          local fn = body and load(body, "=unzip.lua", "t", _ENV)
          local okU, r = pcall(function() return fn and fn() end)
          if okU and type(r) == "function" then unz = r end
        end
      end
      if unz then
        local byPlain = {}
        for _, z in ipairs(zs) do
          z.packed = true
          z.extra = z.path:gsub("%.luz$", ".lua")        -- (the plain copy goes once the packed one is in)
          byPlain[z.extra] = z
        end
        local nl = { uz }                                -- (unzip.lua itself: installed / updated too)
        for _, f in ipairs(list) do if not byPlain[f.path] then nl[#nl + 1] = f end end
        for _, z in ipairs(zs) do nl[#nl + 1] = z end
        list = nl
      else
        log("(unzip.lua could not be read - the files stay unpacked this time)")
      end
    end
  end
  if not unz then
    -- plain files: a PACKED copy of one left from before goes
    for _, f in ipairs(list) do
      if f.path:match("^base_.*%.lua$") then f.extra = f.path:gsub("%.lua$", ".luz") end
    end
  end
  if o.fetch then
    -- the PACKED copy when the caller can unpack it (o.inflate - the base's voice files: a third of the size):
    -- checked (size, checksum), unpacked, compiled; returns true, text, version, packed bytes
    if o.inflate then
      local zname = o.fetch:gsub("%.lua$", ".luz")
      for line in man:gmatch("[^\n]+") do
        local path, size, sum, src = line:match("^z:" .. group:gsub("%p", "%%%0") .. "%s+(%S+)%s+(%d+)%s+(%x+)%s*(%S*)")
        if path == zname then
          log("  getting " .. zname)
          local body, e = get(base .. ((src ~= "" and src) or path))
          if not body or #body ~= tonumber(size) or upgradeHash(body, yield) ~= sum then
            log("Download of " .. zname .. " is not complete / not the right version - try again in a minute. " .. tostring(e or ""))
            return false
          end
          local okU, text = pcall(o.inflate, body, yield)
          if not okU or type(text) ~= "string" then log(zname .. " does not unpack: " .. tostring(text)) return false end
          local fn, ce = load(text, "=" .. o.fetch, "t", {})
          if not fn then log("New " .. o.fetch .. " does not compile: " .. tostring(ce)) return false end
          return true, text, (sha and sha:sub(1, 7)) or branch, body
        end
      end
    end
    for _, f in ipairs(list) do
      if f.path == o.fetch then
        log("  getting " .. f.path)
        local body, e = get(base .. (f.src or f.path))
        if not body then log("Download failed: " .. f.path .. " - " .. tostring(e)) return false end
        if #body ~= f.size or upgradeHash(body, yield) ~= f.sum then
          log("Download of " .. f.path .. " is not complete / not the right version - try again in a minute.")
          return false
        end
        local fn, ce = load(body, "=" .. f.path, "t", {})
        if not fn then log("New " .. f.path .. " does not compile: " .. tostring(ce)) return false end
        return true, body, (sha and sha:sub(1, 7)) or branch
      end
    end
    log(o.fetch .. " is not in the file list (" .. group .. ").")
    return false
  end

  -- 3. what is different here
  local changed, grow = {}, 0
  for _, f in ipairs(list) do
    f.target = (f.path == "startup.lua") and "startup.lua" or fs.combine(dir, f.path)   -- (startup.lua lives at the top)
    local cur = readBin(f.target)
    f.oldSize = cur and #cur or 0
    local other = f.extra and fs.combine(dir, f.extra)
    if other and fs.exists(other) then f.extraPath = other f.oldSize = f.oldSize + fs.getSize(other) else other = nil end
    if other or not cur or #cur ~= f.size or upgradeHash(cur, yield) ~= f.sum then
      changed[#changed + 1] = f
      grow = grow + f.size - f.oldSize
    end
  end
  -- the ones that FREE room first (packing a plain file), the growing ones last
  table.sort(changed, function(a, b) return a.size - a.oldSize < b.size - b.oldSize end)
  local ver = (sha and sha:sub(1, 7)) or branch
  if #changed == 0 then
    log("Everything is up to date (version " .. ver .. ").")
    saved.sha = sha or saved.sha
    writeBin(SAVE, textutils.serialize(saved))
    return false
  end
  log(#changed .. " file(s) changed (version " .. ver .. "):")
  local names = {}
  local packing = 0
  for _, f in ipairs(changed) do
    if f.packed and f.extraPath then packing = packing + 1
    else names[#names + 1] = f.path .. (f.oldSize == 0 and " (new)" or "") end
  end
  if packing > 0 then names[#names + 1] = packing .. " program file(s) PACKED (frees " ..
                                          math.max(0, math.floor(-grow / 1024)) .. " KB)" end
  log("  " .. table.concat(names, ", "))
  if checkOnly then log("Nothing written (check only). Type  upgrade  to get them.") return false end

  local free = fs.getFreeSpace(dir == "" and "/" or dir)
  if grow > free - 8192 then
    log(("Not enough room: the new files need %d KB more, %d KB free. Type  disks  to see what takes the space.")
        :format(math.ceil(grow / 1024), math.floor(free / 1024)))
    return false
  end

  -- 4. download + check EVERYTHING first (nothing written yet)
  for i, f in ipairs(changed) do
    log(("  getting %s (%d/%d)"):format(f.path, i, #changed))
    local body, e = get(base .. (f.src or f.path))
    if not body then log("Download failed: " .. f.path .. " - " .. tostring(e) .. ". Nothing was changed.") return false end
    if #body ~= f.size or upgradeHash(body, yield) ~= f.sum then
      log("Download of " .. f.path .. " is not complete / not the right version. Nothing was changed - try again in a minute.")
      return false
    end
    local code = body
    if f.packed then
      local okU, text = pcall(unz, body, yield)
      if not okU or type(text) ~= "string" then
        log("New " .. f.path .. " does not unpack: " .. tostring(text) .. ". Nothing was changed.")
        return false
      end
      code = text
    end
    if f.path:match("%.lua$") or f.packed then
      local fn, ce = load(code, "=" .. f.path, "t", {})
      if not fn then log("New " .. f.path .. " does not compile: " .. tostring(ce) .. ". Nothing was changed.") return false end
    end
    f.body = body
    yield()
  end

  -- 5. write: through a temp file when there is room, else old out / new in
  --    (the old file is kept in memory and put back if writing fails)
  for _, f in ipairs(changed) do
    local okW, e
    if fs.getFreeSpace(dir == "" and "/" or dir) > f.size + 4096 then
      local tmp = f.target .. ".new"
      okW, e = writeBin(tmp, f.body)
      if okW then
        if fs.exists(f.target) then fs.delete(f.target) end
        fs.move(tmp, f.target)
        if f.extraPath then pcall(fs.delete, f.extraPath) end      -- (the other copy: plain / packed)
      else
        pcall(fs.delete, tmp)
      end
    else
      -- (the old file - and its other copy - kept in memory, put back if writing fails)
      local old = readBin(f.target)
      local oldX = f.extraPath and readBin(f.extraPath)
      if fs.exists(f.target) then fs.delete(f.target) end
      if oldX then fs.delete(f.extraPath) end
      okW, e = writeBin(f.target, f.body)
      if not okW then
        if fs.exists(f.target) then pcall(fs.delete, f.target) end
        if old then writeBin(f.target, old) end
        if oldX then writeBin(f.extraPath, oldX) end
      end
    end
    if not okW then
      log("Could not write " .. f.path .. ": " .. tostring(e) .. ". The files written before it are new, the rest old - type  upgrade  again.")
      return false
    end
  end
  saved.sha = sha or saved.sha
  saved.at = os.epoch and os.epoch("utc") or nil
  writeBin(SAVE, textutils.serialize(saved))
  log("Done: " .. #changed .. " file(s) updated to version " .. ver .. ". base_config.lua was not touched.")
  return true, #changed
end

local first = ...
if type(first) == "table" then return run(first) end     -- (loaded by the base console)

-- started from the shell: upgrade [check|branch <name>]
local here = (shell and shell.getRunningProgram) and fs.getDir(shell.getRunningProgram()) or ""
-- run straight from GitHub (wget run <url>) - no room needed on a full computer: the program is not a file
-- here, so the base program's folder is the one with inventory.lua (like startup.lua finds it)
if not pocket and not fs.exists(fs.combine(here, "inventory.lua")) then
  local found = {}
  for _, pattern in ipairs({ "inventory.lua", "*/inventory.lua", "*/*/inventory.lua" }) do
    for _, p in ipairs(fs.find(pattern)) do
      if not fs.getDrive or fs.getDrive(p) == "hdd" then found[#found + 1] = p end
    end
  end
  table.sort(found, function(a, b) return #a < #b end)
  if found[1] then here = fs.getDir(found[1]) print("Base program found in /" .. here) end
end
local done = run({ args = { ... }, dir = here })
if done then
  print("Restarting in 3 s ...")
  sleep(3)
  os.reboot()
end
