-- EVERY CONSOLE COMMAND AND EVERY $drone CHAT COMMAND (the owner: "go over every feature and check them"):
-- each command with every sub-word its own code checks for, then odd extra arguments (none, numbers, a
-- negative, a word, "me", coordinates, a very long word). The owner and a stranger. An error - thrown, or
-- printed back as "attempt to ..." - is a bug (in the game the terminal / chat worker swallows it).
local errors, seen, runs = {}, {}, 0
local function note(where, err)
  local k = where:gsub("%d+", "#") .. " | " .. tostring(err):gsub("%d+", "#")
  if not seen[k] then seen[k] = true errors[#errors + 1] = where .. ": " .. tostring(err) end
end
os.reboot, os.shutdown = function() end, function() end
local function guarded(f, ...)
  local args = table.pack(...)
  debug.sethook(function() error("RUNS TOO LONG (endless loop?)") end, "", 5e7)
  local ok, r = pcall(f, table.unpack(args, 1, args.n))
  debug.sethook()
  return ok, r
end
local BAD = { "attempt to ", "bad argument", "stack traceback", "invalid key to", "table index is nil" }
local function badText(lines)
  for _, l in ipairs(type(lines) == "table" and lines or {}) do
    for _, b in ipairs(BAD) do if tostring(l):find(b, 1, true) then return tostring(l) end end
  end
end
local ODD = { "", "1", "999999", "-3", "x", "me", "0 64 0", string.rep("w", 300), "all", "on", "off" }

-- the console: commands + the sub-words each one's own block checks for
local src = io.open(SRC_DIR .. "/base_console.lua"):read("a")
local cmds, order = {}, {}
local pos = 1
while true do
  local a, b, name = src:find('cmd == "([%w?]+)"', pos)
  if not a then break end
  local nextA = src:find('elseif cmd == "', b) or #src
  local block = src:sub(b, nextA)
  if not cmds[name] then cmds[name] = {} order[#order + 1] = name end
  for w in block:gmatch('== "([%w_%-]+)"') do cmds[name][w] = true end
  pos = b + 1
end
local SKIP = { exit = false }
local said = {}
local function consoleRound(tag)
said = {}
for _, c in ipairs(order) do
  if SKIP[c] == nil then
    local subs = { "" }
    for w in pairs(cmds[c]) do subs[#subs + 1] = w end
    table.sort(subs)
    for _, s in ipairs(subs) do
      for _, extra in ipairs(ODD) do
        local line = c .. (s ~= "" and (" " .. s) or "") .. (extra ~= "" and (" " .. extra) or "")
        if not said[line] then
          said[line] = true
          runs = runs + 1
          local ok, out = guarded(handleCommand, line)
          if not ok then note("console '" .. line .. "'", out)
          else
            local bad = badText(out)
            if bad then note("console '" .. line .. "' printed", bad) end
          end
          state.actionQueue, state.busy, state.pending = {}, false, nil
        end
      end
    end
  end
end
end
-- without an ME Bridge (the owner's can drop off the cable) and with one
bridge = nil
consoleRound("no bridge")
dofile(SRC_DIR .. "/tools/tests/lib/fake_ae2.lua")
consoleRound("with AE2")

-- chat: $drone <sub> as the owner and as a stranger
local csrc = io.open(SRC_DIR .. "/base_chat.lua"):read("a")
local subs, sorder = {}, {}
pos = 1
while true do
  local a, b, name = csrc:find('sub == "(%w+)"', pos)
  if not a then break end
  local nextA = csrc:find('elseif sub == "', b) or #csrc
  local block = csrc:sub(b, nextA)
  if not subs[name] then subs[name] = {} sorder[#sorder + 1] = name end
  for w in block:gmatch('== "([%w_%-]+)"') do subs[name][w] = true end
  pos = b + 1
end
local told = {}
local tell0 = chatTell
chatTell = function(n, t) told[#told + 1] = tostring(t) end
local owner = (knownOwner and knownOwner()) or state.owner or "Alaory"
local c = CONFIG.chat and CONFIG.chat.command or "drone"
for _, who in ipairs({ { name = owner, uuid = state.ownerUuid }, { name = "Griefer", uuid = "u-griefer" } }) do
  for _, s in ipairs(sorder) do
    local ws = { "" }
    for w in pairs(subs[s]) do ws[#ws + 1] = w end
    table.sort(ws)
    for _, w in ipairs(ws) do
      for _, extra in ipairs(ODD) do
        local msg = "$" .. c .. " " .. s .. (w ~= "" and (" " .. w) or "") .. (extra ~= "" and (" " .. extra) or "")
        told = {}
        runs = runs + 1
        local ok, err = guarded(handleChat, { name = who.name, uuid = who.uuid, msg = msg })
        if not ok then note("chat " .. who.name .. " '" .. msg .. "'", err)
        else
          local bad = badText(told)
          if bad then note("chat " .. who.name .. " '" .. msg .. "' replied", bad) end
        end
        state.chatOut = {}
      end
    end
  end
  -- not even a sub-command, and nonsense
  for _, msg in ipairs({ "$" .. c, "$" .. c .. " ", "$" .. c .. " zzz", "$" .. c .. "x", "$", "hello" }) do
    local ok, err = guarded(handleChat, { name = who.name, uuid = who.uuid, msg = msg })
    if not ok then note("chat '" .. msg .. "'", err) end
  end
end
chatTell = tell0

CHECK(#errors == 0, #errors .. " error(s) in " .. runs .. " commands:\n  " .. table.concat(errors, "\n  ", 1, math.min(#errors, 60)))
CHECK(#order > 50 and #sorder > 12 and runs > 3000, "commands tried: " .. #order .. " console, " .. #sorder .. " chat, " .. runs .. " runs")
