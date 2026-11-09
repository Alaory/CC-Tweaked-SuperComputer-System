-- the base's TT.shrinkCode (node.lua sent to turtles / floppies): writes the shrunk
-- copies to arg[1]; run_tests compiles both (luac -s) - must be the SAME bytes, same lines.
local src = io.open("base_turtles.lua"):read("a")
local a = src:find("local function shrinkScan", 1, true)
local b = src:find("-- (re)read node.lua if it is new or changed", 1, true)
TT = { workYield = function() end }
load(src:sub(a, b - 1))()
-- the tricky cases (none of them in the real files today)
local TRICKY = table.concat({
  'local a = "-- not a comment"   -- a comment',
  "local b = 'it\\'s -- still text' .. \"x\\\"--y\"",
  "local c = [[ -- inside a long string",
  "   kept as it is -- too ]] .. 'z' -- gone",
  "local d = [==[ ]] -- ]==] --[[ block",
  "comment ]] local e = 1 --[==[ x ]==] + 2",
  "    local f = 3 - -4 -- minus minus",
  "return a, b, c, d, e, f", "" }, "\n")
do
  local o = io.open(arg[1] .. "/tricky_full.lua", "w") o:write(TRICKY) o:close()
  o = io.open(arg[1] .. "/tricky.lua", "w") o:write(TT.shrinkCode(TRICKY)) o:close()
  local fa, fb = load(TRICKY), load(TT.shrinkCode(TRICKY))
  local ra, rb = { fa() }, (fb and { fb() } or {})
  for k = 1, 6 do
    if ra[k] ~= rb[k] then print("tricky value " .. k .. " differs: " .. tostring(ra[k]) .. " / " .. tostring(rb[k])) os.exit(1) end
  end
end
for _, f in ipairs({ "node.lua", "pocket.lua", "base_map.lua", "base_turtles.lua", "miner.lua" }) do
  local full = io.open(f):read("a")
  local s = TT.shrinkCode(full)
  local o = io.open(arg[1] .. "/" .. f, "w") o:write(s) o:close()
  print(f, #full, #s)
end
