




local function banner()
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if term.isColor() then term.setTextColor(colors.cyan) end
print("BASE REMOTE CONSOLE")
term.setTextColor(colors.white)
print("Type a base command (help, turtles, survey, away, events, mine, factory ...).")
print("'shell' = a normal shell, 'clear' = clear the screen.")
print("")
end


local function alive()
os.queueEvent("remote_alive")
end

local history, n = {}, 0
local timer = os.startTimer(5)


local function waitAnswer(req)
local deadline = os.clock() + 60
local told = false
while true do
local ev = { os.pullEventRaw() }
if ev[1] == "remote_out" and ev[2] == req then
return ev[3]
elseif ev[1] == "remote_quit" or ev[1] == "terminate" then
return nil, "quit"
elseif ev[1] == "timer" and ev[2] == timer then
alive()
timer = os.startTimer(5)
if not told and os.clock() > deadline - 50 then
told = true
print("(the base is busy - waiting for its answer ...)")
end
if os.clock() > deadline then return { "No answer from the base in 60 s (it may still be doing it)." } end
end
end
end


local function readLine()
local line, quit
parallel.waitForAny(function()
line = read(nil, history)
end, function()
while true do
local ev = { os.pullEventRaw() }
if ev[1] == "timer" and ev[2] == timer then
alive()
timer = os.startTimer(5)
elseif ev[1] == "remote_quit" then
quit = true
return
end
end
end)
return line, quit
end

banner()
alive()
while true do
if term.isColor() then term.setTextColor(colors.yellow) end
write("base> ")
term.setTextColor(colors.white)
local line, quit = readLine()
if quit or line == nil then break end
line = line:gsub("^%s+", ""):gsub("%s+$", "")
if line ~= "" then history[#history + 1] = line end
if line == "clear" or line == "cls" then
banner()
elseif line == "shell" then
print("A normal shell - type 'exit' to come back.")
shell.run("shell")
banner()
elseif line ~= "" then
n = n + 1
local req = os.getComputerID() .. ":" .. os.epoch("utc") .. ":" .. n
os.queueEvent("remote_cmd", req, line)
local out, why = waitAnswer(req)
if why == "quit" then break end
for _, l in ipairs(out or {}) do print(l) end
end
end
print("Remote console closed.")
