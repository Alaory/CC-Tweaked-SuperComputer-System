-- COMMANDS.md lists EVERY command (the owner: "a readme with every command and usage explained"): a command added to
-- the code but not to COMMANDS.md fails here. Words are looked for as `word ... inside backticks.
local function read(f) local h = io.open(SRC_DIR .. "/" .. f) local t = h and h:read("a") or "" if h then h:close() end return t end
local doc = read("COMMANDS.md")
CHECK(#doc > 5000, "COMMANDS.md is there")
local function inDoc(prefix, w)
  -- `prefix w` anywhere in a code span (prefix "" = the word starts a span)
  local pat = "`" .. (prefix ~= "" and (prefix .. " ") or "") .. w
  return doc:find(pat, 1, true) ~= nil or doc:find(" " .. w .. "`", 1, true) ~= nil and prefix ~= "" and doc:find("`" .. prefix, 1, true) ~= nil
end
local missing = {}
local function need(prefix, w, where) if not inDoc(prefix, w) then missing[#missing + 1] = (prefix ~= "" and prefix .. " " or "") .. w .. " (" .. where .. ")" end end
-- 1) console commands
local ALIAS = { dronework = true, schematics = true, storages = true }       -- (other names for dw / schem / chests)
for w in read("base_console.lua"):gmatch('cmd == "([%a@]+)"') do if not ALIAS[w] then need("", w, "base_console") end end
-- 2) their sub-words that the console checks (words[2] == "...")
for c, w in read("base_console.lua"):gmatch('cmd == "(%a+)" and words%[2%] == "(%a+)"') do need(c, w, "base_console") end
-- 3) voice sub-commands
local va = read("voice_addon.lua")
local s0 = va:find("function VOICE.command", 1, true) or 1
for w in va:sub(s0):gmatch('a == "(%a+)"') do need("voice", w, "voice_addon") end
for f in ("voice_convo voice_crowd voice_profile voice_spawn voice_staff voice_talk2"):gmatch("%S+") do
  for w in read(f .. ".lua"):gmatch('V%.commands%.(%a+) =') do need("voice", w, f) end
end
-- 4) voice spawn sub-commands
local vs = read("voice_spawn.lua")
local s1 = vs:find("V.commands.spawn =", 1, true) or 1
local e1 = vs:find("\nend", s1, true) or #vs
for w in vs:sub(s1, e1):gmatch('a == "(%a+)"') do need("voice spawn", w, "voice_spawn") end
-- 5) $drone chat sub-commands
for w in read("base_chat.lua"):gmatch('sub == "(%a+)"') do need("$drone", w, "base_chat") end
-- 6) the turtle program's commands a person may send (not the base's own protocol words)
local INTERNAL = { ack = 1, becomecopy = 1, build = 1, craft = 1, drive = 1, dupfree = 1, dupstop = 1, exitrec = 1, exitsave = 1,
  findturtles = 1, fuelup = 1, homeoffer = 1, know = 1, learnrecipe = 1, rescue = 1, surveypts = 1, upd = 1 }
for w in read("node.lua"):gmatch('cmd == "(%a+)"') do if not INTERNAL[w] then need("turtle <id>", w, "node.lua") end end
local uniq, list = {}, {}
for _, m in ipairs(missing) do if not uniq[m] then uniq[m] = true list[#list + 1] = m end end
CHECK(#list == 0, "every command is in COMMANDS.md - missing: " .. table.concat(list, ", "))
-- the README points to it
CHECK(read("README.md"):find("COMMANDS.md", 1, true), "README.md links to COMMANDS.md")
