





















local REPO = "Alaory/CC-Tweaked-SuperComputer-System"
local DEFAULT_BRANCH = "main"

local FALLBACK_BRANCH = "claude/computercraft-base-review-ihjtqw"
local SAVE = "upgrade.dat"


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


local function get(url, headers)
local ok, h, err = pcall(http.get, { url = url, headers = headers, binary = true })
if not ok then ok, h, err = pcall(http.get, url, headers, true) end
if not ok or not h then return nil, tostring(err or h or "no answer") end
local body = h.readAll() or ""
h.close()
return body
end


local function whichGroup()
if pocket then return "pocket" end
return "base"
end



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
if args[1] == "full" or args[1] == "slim" then
saved.full = (args[1] == "full") or nil
writeBin(SAVE, textutils.serialize(saved))
log(saved.full and "From now on the FULL files (with comments) - getting them now."
or "From now on the SLIM files (no comments, ~30% smaller) - getting them now.")
end
local checkOnly = args[1] == "check"


local tryBranches = saved.branch and { saved.branch } or { DEFAULT_BRANCH, FALLBACK_BRANCH }
local branch, sha, base, man, err
for _, b in ipairs(tryBranches) do
branch = b

log("Asking GitHub for the newest version of " .. branch .. " ...")
sha = get("https://api.github.com/repos/" .. REPO .. "/commits/" .. textutils.urlEncode(branch),
{ Accept = "application/vnd.github.sha", ["User-Agent"] = "cc-base-upgrade" })
if sha then sha = sha:match("^%s*(%x+)%s*$") end
local ref = sha or branch
base = "https://raw.githubusercontent.com/" .. REPO .. "/" .. ref .. "/"

man, err = get(base .. "manifest.txt")
if man then break end
end
if not man then log("Could not read the file list: " .. tostring(err)) return false end
local group = whichGroup()
local list = {}

local want = saved.full and group or ("slim:" .. group)
for pass = 1, 2 do
for line in man:gmatch("[^\n]+") do
local g, path, size, sum, src = line:match("^(%S+)%s+(%S+)%s+(%d+)%s+(%x+)%s*(%S*)")
if g == want then list[#list + 1] = { path = path, size = tonumber(size), sum = sum, src = (src ~= "" and src) or nil } end
end
if #list > 0 then break end
want = group
end
if #list == 0 then log("The file list has no files for this computer (" .. group .. ").") return false end


local dir = o.dir or ""
local changed, grow = {}, 0
for _, f in ipairs(list) do
f.target = (f.path == "startup.lua") and "startup.lua" or fs.combine(dir, f.path)
local cur = readBin(f.target)
f.oldSize = cur and #cur or 0
if not cur or #cur ~= f.size or upgradeHash(cur, yield) ~= f.sum then
changed[#changed + 1] = f
grow = grow + f.size - f.oldSize
end
end
local ver = (sha and sha:sub(1, 7)) or branch
if #changed == 0 then
log("Everything is up to date (version " .. ver .. ").")
saved.sha = sha or saved.sha
writeBin(SAVE, textutils.serialize(saved))
return false
end
log(#changed .. " file(s) changed (version " .. ver .. "):")
local names = {}
for _, f in ipairs(changed) do names[#names + 1] = f.path .. (f.oldSize == 0 and " (new)" or "") end
log("  " .. table.concat(names, ", "))
if checkOnly then log("Nothing written (check only). Type  upgrade  to get them.") return false end

local free = fs.getFreeSpace(dir == "" and "/" or dir)
if grow > free - 8192 then
log(("Not enough room: the new files need %d KB more, %d KB free. Type  disks  to see what takes the space.")
:format(math.ceil(grow / 1024), math.floor(free / 1024)))
return false
end


for i, f in ipairs(changed) do
log(("  getting %s (%d/%d)"):format(f.path, i, #changed))
local body, e = get(base .. (f.src or f.path))
if not body then log("Download failed: " .. f.path .. " - " .. tostring(e) .. ". Nothing was changed.") return false end
if #body ~= f.size or upgradeHash(body, yield) ~= f.sum then
log("Download of " .. f.path .. " is not complete / not the right version. Nothing was changed - try again in a minute.")
return false
end
if f.path:match("%.lua$") then
local fn, ce = load(body, "=" .. f.path, "t", {})
if not fn then log("New " .. f.path .. " does not compile: " .. tostring(ce) .. ". Nothing was changed.") return false end
end
f.body = body
yield()
end



for _, f in ipairs(changed) do
local okW, e
if fs.getFreeSpace(dir == "" and "/" or dir) > f.size + 4096 then
local tmp = f.target .. ".new"
okW, e = writeBin(tmp, f.body)
if okW then
if fs.exists(f.target) then fs.delete(f.target) end
fs.move(tmp, f.target)
else
pcall(fs.delete, tmp)
end
else
local old = readBin(f.target)
if fs.exists(f.target) then fs.delete(f.target) end
okW, e = writeBin(f.target, f.body)
if not okW and old then writeBin(f.target, old) end
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
if type(first) == "table" then return run(first) end


local here = (shell and shell.getRunningProgram) and fs.getDir(shell.getRunningProgram()) or ""
local done = run({ args = { ... }, dir = here })
if done then
print("Restarting in 3 s ...")
sleep(3)
os.reboot()
end
