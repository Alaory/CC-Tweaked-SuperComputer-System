-- voice_talk3.lua - TALK PACK 3 for the talking base (after voice_addon.lua, voice_talk.lua, voice_talk2.lua).
-- OPTIONAL, on a DATA FLOPPY (`voice install` / `voice update`). Chat only, answers only. What it adds:
--   STREAKS     visiting days in a row (3 / 7 / 14 / 30): badges, and a gift at 7 and 30.
--   MAIL        players leave messages for EACH OTHER: "tell Steve that the farm is ready" - said to Steve
--               the next time he comes to the base. ("my mail" reads it at once.)
--   GLOSSARY    "what is a shulker box", "explain redstone" - 60 Minecraft words for new players.
--   RECIPES     "how do I make a hopper", "recipe for a beacon" - 70 crafting recipes in words.
--   JOKES ON    "tell me a joke about creepers".
--   FUN         spirit mob (always the same for a name), "ship me and Steve" compatibility,
--               "last time you won at hangman - rematch?" when a player comes back.
--   MILESTONES  the base's own achievements (chunks mapped, turtles, visitors, gifts) said once each.
--   THANKS      a thank you right after a gift gets a special answer.
--   TAXI        free drone rides for friends of the base: from the base to their bed, from their bed to the
--               base ("base, take me to the base" - far away, only that is answered). Offered once a visit.
--   OTHERS      who visits the most, how long it has been running, more would-you-rather / this-or-that.
if not (VOICE and VOICE.addIntents and VOICE.badge and VOICE.addBadge and VOICE.giftOnce) then return end
local V = VOICE
local pick, fill = V.pick, V.fill
V.packs["voice_talk3.lua"] = { version = 1 }

local function add(list, more) for _, x in ipairs(more) do list[#list + 1] = x end end
local function nowS() return math.floor(os.epoch("utc") / 1000) end
local function today() return os.date("!%Y-%m-%d", nowS()) end
local function rec(who)
  local m = V.mem()
  local k = tostring(who):lower()
  if type(m[k]) ~= "table" then m[k] = {} end
  return m[k], k
end
local function tell(who, text) if chatTell then chatTell(who, text) end end
local function isNear(who)
  for _, p in ipairs(V.nearPlayers()) do if p.name:lower() == tostring(who):lower() then return true end end
  return false
end
local function cap(s) s = tostring(s) return s:sub(1, 1):upper() .. s:sub(2) end
local function hashOf(s)
  local h = 7
  for c in tostring(s):lower():gmatch(".") do h = (h * 131 + c:byte()) % 2147483647 end
  return h
end

-- ===== 1. visit streaks =====
V.addBadge("streak3", "Three in a Row", "visit me 3 days in a row")
V.addBadge("streak7", "Weekly Visitor", "visit me 7 days in a row")
V.addBadge("streak30", "Loyal Friend", "visit me 30 days in a row")
V.GIFT_DEFAULT.streak7 = { { "minecraft:diamond", 24 }, { "minecraft:golden_apple", 8 } }
V.GIFT_DEFAULT.streak30 = { { "minecraft:netherite_ingot", 4 }, { "minecraft:totem_of_undying", 2 }, { "minecraft:diamond_block", 8 } }
V.GIFT_WHY.streak7 = "for visiting 7 days in a row"
V.GIFT_WHY.streak30 = "for visiting 30 days in a row"
add(V.GIFT_ORDER, { "streak7", "streak30" })
local function yesterday() return os.date("!%Y-%m-%d", nowS() - 86400) end
function V.visitDay(name)
  local r = rec(name)
  local d = today()
  if r.vday == d then return r.streak or 1 end
  if r.vday == yesterday() then r.streak = (r.streak or 1) + 1 else r.streak = 1 end
  r.vday = d
  r.best = math.max(r.best or 0, r.streak)
  V.saveMem()
  local s = r.streak
  if s >= 3 then V.badge(name, "streak3") end
  if s >= 7 then V.badge(name, "streak7") if not V.isOwner(name) then V.giftOnce(name, "streak7", "streak7") end end
  if s >= 30 then V.badge(name, "streak30") if not V.isOwner(name) then V.giftOnce(name, "streak30", "streak30") end end
  if s == 3 or s == 7 or s == 14 or s == 30 or s == 100 then
    V.say(name .. ", that is " .. s .. " days in a row! Amazing.", "minecraft:entity.player.levelup")
  elseif s > 1 and math.random() < 0.3 then
    V.say("Day " .. s .. " in a row, " .. name .. ". Keep it up!")
  end
  return s
end

-- ===== 2. mail between players =====
local function mailbox()
  local b = V.base()
  b.mail = type(b.mail) == "table" and b.mail or {}
  return b.mail
end
local function knownPlayer(name)
  local k = tostring(name):lower()
  if type(V.mem()[k]) == "table" then return true end
  if state.online and state.online[k] then return true end
  for _, e in ipairs(state.players or {}) do if tostring(e.name):lower() == k then return true end end
  return false
end
local NOT_NAMES = { me = true, you = true, him = true, her = true, them = true, everyone = true, the = true, a = true, my = true, your = true,
  it = true, us = true, all = true }
local function realName(name)
  local k = tostring(name):lower()
  for _, e in ipairs(state.players or {}) do if tostring(e.name):lower() == k then return e.name end end
  local r = V.mem()[k]
  return (type(r) == "table" and r.name) or name
end
function V.sendMail(from, to, text)
  local k = tostring(to):lower()
  local box = mailbox()
  box[k] = type(box[k]) == "table" and box[k] or {}
  if #box[k] >= 5 then return false, realName(to) .. "'s mailbox is full (5 messages). Try again later." end
  local mine = 0
  for _, list in pairs(box) do for _, m in ipairs(list) do if tostring(m.from):lower() == tostring(from):lower() then mine = mine + 1 end end end
  if mine >= 3 then return false, "You already have 3 messages waiting to be delivered." end
  box[k][#box[k] + 1] = { from = tostring(from), text = tostring(text):sub(1, 160), at = nowS() }
  V.saveMem()
  return true
end
local function ago(at)
  local d = nowS() - (tonumber(at) or nowS())
  if d < 3600 then return "just now" elseif d < 86400 then return math.floor(d / 3600) .. " hours ago" end
  return math.floor(d / 86400) .. " days ago"
end
function V.deliverMail(name, spoken)
  local box = mailbox()
  local k = tostring(name):lower()
  local list = box[k]
  if type(list) ~= "table" or #list == 0 then return 0 end
  for _, m in ipairs(list) do tell(name, "Mail from " .. m.from .. " (" .. ago(m.at) .. "): " .. m.text) end
  if spoken then V.say(name .. ", you have " .. V.plural(#list, "message", "messages") .. " from " .. list[1].from .. (#list > 1 and " and others" or "") .. ". I put them in your chat.") end
  box[k] = nil
  V.saveMem()
  return #list
end

-- ===== 3. the glossary =====
local GLOSS = {
  creeper = "a green mob that sneaks up and explodes. Cats scare it away.",
  enderman = "a tall black mob from the End. Do not look it in the eyes, and it hates water.",
  redstone = "Minecraft's electricity. Dust, torches, repeaters and comparators make machines.",
  nether = "a hot dimension full of lava, piglins and ghasts. Build a portal of obsidian to get there.",
  ["the end"] = "the dimension of the ender dragon. Find a stronghold and fill the portal with eyes of ender.",
  elytra = "wings from the ships in end cities. Jump, glide, and use fireworks to fly.",
  netherite = "the strongest material. Ancient debris from the Nether, smelted into scraps, plus gold.",
  beacon = "a block that gives you powers like speed or haste. It needs a nether star and a pyramid of mineral blocks.",
  enchanting = "giving tools magic powers with lapis and levels at an enchanting table.",
  villager = "a mob that lives in villages and trades items for emeralds. They say hmm.",
  ["iron golem"] = "a big metal guard that protects villages. Made from four iron blocks and a pumpkin.",
  spawner = "a cage block in dungeons that keeps making mobs. Great for xp farms.",
  ["slime chunk"] = "a chunk where slimes spawn underground. Ask me: slime chunk.",
  chunk = "a 16 by 16 piece of the world that loads together. My turtles keep their chunks loaded.",
  biome = "an area with its own plants, weather and mobs, like desert, jungle or snowy plains.",
  totem = "the totem of undying. Hold it and it saves you from death once. Evokers drop it.",
  ["totem of undying"] = "hold it and it saves you from death once. Evokers drop it.",
  ["shulker box"] = "a box that keeps its items when you break it. Made from shulker shells from the End.",
  ["ender chest"] = "a chest that is the same everywhere - your own private storage.",
  hopper = "a funnel block that moves items into chests and machines.",
  observer = "a block that sends a redstone signal when the block in front of it changes.",
  piston = "a block that pushes blocks. A sticky piston pulls them back too.",
  comparator = "a redstone part that reads how full a chest is, or compares signals.",
  repeater = "a redstone part that makes a signal stronger and can delay it.",
  mending = "an enchantment that repairs your tool with experience orbs.",
  ["silk touch"] = "an enchantment that mines blocks as they are, like glass or ores.",
  fortune = "an enchantment that gives more drops from ores.",
  looting = "an enchantment that makes mobs drop more.",
  ae2 = "Applied Energistics 2: the digital storage. Everything goes into drives and one terminal finds it.",
  ["me system"] = "the AE2 storage network. It stores and crafts everything automatically.",
  turtle = "a little robot from ComputerCraft. Mine fly out, map the world and come home.",
  drone = "a flying robot from PneumaticCraft. Mine carry players and bring gifts.",
  computercraft = "a mod that adds computers and turtles you program in Lua. I am one of them!",
  pneumaticcraft = "a mod with machines that run on compressed air. My drones come from it.",
  ["advanced peripherals"] = "a mod that lets computers talk to players, chat and AE2. It gives me my ears.",
  warden = "a huge blind mob in the deep dark. It hears everything. Sneak and do not wake it.",
  ["ancient city"] = "a big ruin deep in the deep dark, with loot and a Warden.",
  stronghold = "an underground fortress with the End portal. Eyes of ender lead you there.",
  ["end city"] = "towers on the outer End islands, with shulkers, loot and elytras.",
  ["trial chamber"] = "an underground building full of trial spawners and breezes, with vaults of loot.",
  breeze = "a windy mob in trial chambers that jumps around and shoots wind.",
  armadillo = "a shy mob in savannas. Its scutes make armour for wolves.",
  mace = "a heavy weapon from a breeze rod and a heavy core. The higher you fall, the harder it hits.",
  bundle = "a small bag that holds a stack of different items in one slot.",
  sculk = "creepy blue blocks of the deep dark. Sculk sensors hear sounds, shriekers call the Warden.",
  axolotl = "a cute water mob in lush caves. It helps you fight under water.",
  allay = "a small blue flying mob that collects items like the one you give it.",
  amethyst = "purple crystals from geodes. Used for spyglasses and tinted glass.",
  copper = "an orange metal that turns green over time. Wax it to keep the colour.",
  trident = "a weapon dropped by drowned. Enchant it to fly through rain or call lightning.",
  phantom = "a flying mob that comes when you have not slept for three nights.",
  piglin = "a Nether mob that loves gold. Wear gold armour and they leave you alone.",
  ghast = "a big floating jellyfish in the Nether that shoots fireballs. Hit them back!",
  blaze = "a fire mob in Nether fortresses. Its rods make brewing stands and eyes of ender.",
  wither = "a three-headed boss you build from soul sand and wither skulls. It drops a nether star.",
  ["ender dragon"] = "the boss of the End. Beat it to open the way to the end cities.",
  xp = "experience points. You get them from mobs, mining and smelting, and spend them on enchanting.",
  lapis = "blue gems for enchanting.",
  obsidian = "a very hard block made when water hits still lava. Needed for nether portals.",
  bedrock = "the unbreakable floor of the world.",
}
local GLOSS_ALIAS = { ["the nether"] = "nether", ["end"] = "the end", ["shulker"] = "shulker box", ["golem"] = "iron golem",
  ["applied energistics"] = "ae2", ["applied energistics 2"] = "ae2", ["me"] = "me system", ["cc"] = "computercraft",
  ["cc tweaked"] = "computercraft", ["dragon"] = "ender dragon", ["experience"] = "xp", ["lapis lazuli"] = "lapis",
  ["enchantment"] = "enchanting", ["enchant"] = "enchanting", ["deep dark"] = "sculk" }
-- recipes in words
local RECIPE = {
  ["crafting table"] = "four planks in a 2 by 2 square.", furnace = "eight cobblestone around an empty middle.",
  chest = "eight planks around an empty middle.", torch = "a stick with coal or charcoal on top.",
  bed = "three wool on top of three planks.", bucket = "three iron ingots in a V shape.",
  shield = "six planks in a Y shape with one iron ingot at the top middle.", bow = "three sticks and three string.",
  arrow = "flint on top, a stick in the middle, a feather at the bottom.", ladder = "seven sticks in an H shape.",
  boat = "five planks in a U shape.", minecart = "five iron ingots in a U shape.", rail = "six iron ingots and one stick - makes 16.",
  ["powered rail"] = "six gold ingots, a stick and redstone.", hopper = "five iron ingots in a V with a chest in the middle.",
  piston = "three planks on top, cobblestone, iron in the middle, redstone below.", ["sticky piston"] = "a piston with a slimeball.",
  observer = "cobblestone, redstone and one nether quartz.", dispenser = "cobblestone around a bow with redstone below.",
  dropper = "cobblestone around an empty middle with redstone below.", anvil = "three iron blocks on top, four iron ingots below.",
  ["enchanting table"] = "a book on top, diamonds on the sides, obsidian below.", bookshelf = "six planks and three books.",
  beacon = "five glass, a nether star in the middle, three obsidian below.", ["brewing stand"] = "a blaze rod on three cobblestone.",
  cake = "three milk buckets, two sugar, an egg and three wheat.", bread = "three wheat in a row.",
  ["golden apple"] = "an apple with eight gold ingots around it.", ["golden carrot"] = "a carrot with eight gold nuggets around it.",
  compass = "four iron ingots around redstone.", clock = "four gold ingots around redstone.", map = "eight paper around a compass.",
  ["fishing rod"] = "three sticks in a diagonal with two string.", shears = "two iron ingots, diagonally.",
  ["flint and steel"] = "an iron ingot and a flint.", lead = "four string and a slimeball.",
  lantern = "a torch surrounded by iron nuggets.", campfire = "sticks around coal, logs at the bottom.",
  barrel = "six planks and two slabs.", smoker = "a furnace with four logs around it.",
  ["blast furnace"] = "a furnace, five iron ingots and three smooth stone.", stonecutter = "an iron ingot on three stone.",
  loom = "two string on two planks.", scaffolding = "six bamboo and a string.", jukebox = "planks around a diamond.",
  ["note block"] = "planks around redstone.", tnt = "five gunpowder and four sand in a checker pattern.",
  pickaxe = "three of the material on top and two sticks down the middle.", sword = "two of the material on top of a stick.",
  axe = "three of the material in an L and two sticks.", shovel = "one of the material on top of two sticks.",
  hoe = "two of the material on top and two sticks.", helmet = "five of the material in a cap shape.",
  chestplate = "eight of the material, the top middle empty.", leggings = "seven of the material, the middle and bottom middle empty.",
  boots = "four of the material in two little columns.", crossbow = "three sticks, two string, an iron ingot and a tripwire hook.",
  spyglass = "two copper ingots below an amethyst shard.", lodestone = "eight chiseled stone bricks around a netherite ingot.",
  ["respawn anchor"] = "six crying obsidian and three glowstone.", ["shulker box"] = "two shulker shells with a chest between.",
  ["ender chest"] = "eight obsidian around an eye of ender.", ["end crystal"] = "seven glass, an eye of ender and a ghast tear.",
  painting = "eight sticks around wool.", ["item frame"] = "eight sticks around leather.", ["armor stand"] = "six sticks and a smooth stone slab.",
  ["eye of ender"] = "an ender pearl and blaze powder.", ["blaze powder"] = "one blaze rod makes two.",
  ["nether portal"] = "not crafted: build a frame of ten obsidian, four wide and five high, and light it.",
  ["iron golem"] = "not crafted: four iron blocks in a T and a carved pumpkin on top.",
  ["snow golem"] = "not crafted: two snow blocks with a carved pumpkin on top.",
  beehive = "six planks and three honeycomb.", candle = "a string on top of a honeycomb.", bundle = "rabbit hide and string.",
  ["slime block"] = "nine slimeballs.", glass = "not crafted: smelt sand in a furnace.", ["glass pane"] = "six glass - makes 16.",
  paper = "three sugar cane in a row.", book = "three paper and a leather.", stick = "two planks on top of each other.",
  planks = "one log makes four.", ["crafting"] = "open a crafting table and place the items in the right shape.",
}
local RECIPE_ALIAS = { table = "crafting table", ["work bench"] = "crafting table", workbench = "crafting table",
  ["enchantment table"] = "enchanting table", pick = "pickaxe", ["golden apples"] = "golden apple", armour = "chestplate",
  armor = "chestplate", ["armour stand"] = "armor stand", portal = "nether portal", golem = "iron golem", ["ender eye"] = "eye of ender" }
-- find a term: exact, without a/an/the, singular, an alias, else one typo
local function lookup(tbl, alias, term)
  local t = tostring(term or ""):lower():gsub("[%p]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  t = t:gsub("^an? ", ""):gsub("^the ", ""):gsub("^some ", "")
  local tries = { t, (t:gsub("es$", "")), (t:gsub("s$", "")), "the " .. t }
  for _, x in ipairs(tries) do
    if tbl[x] then return x, tbl[x] end
    if alias[x] and tbl[alias[x]] then return alias[x], tbl[alias[x]] end
  end
  if #t >= 5 then
    for k, v in pairs(tbl) do
      local max = #k >= 8 and 2 or 1
      if math.abs(#k - #t) <= max and k:sub(1, 1) == t:sub(1, 1) and V.dist(t, k, max) <= max then return k, v end
    end
  end
  return nil
end
V.lookupGloss = function(term) return lookup(GLOSS, GLOSS_ALIAS, term) end
V.lookupRecipe = function(term) return lookup(RECIPE, RECIPE_ALIAS, term) end

-- ===== 4. fun =====
local SPIRIT = { "axolotl", "fox", "panda", "wolf", "cat", "parrot", "dolphin", "bee", "turtle", "llama", "goat", "frog", "allay", "sniffer",
  "camel", "armadillo", "ocelot", "polar bear", "horse", "rabbit", "creeper (sorry)", "enderman", "iron golem", "villager", "glow squid" }
local SPIRIT_WHY = { "You are curious and brave.", "You are calm but strong.", "You like your friends close.", "You are a little bit chaotic.",
  "You find treasure everywhere.", "You never give up.", "You are cute, do not deny it.", "You are wiser than you look." }
local function spirit(name)
  local h = hashOf(name)
  return SPIRIT[(h % #SPIRIT) + 1], SPIRIT_WHY[(math.floor(h / 7) % #SPIRIT_WHY) + 1]
end
local function ship(a, b)
  local x, y = tostring(a):lower(), tostring(b):lower()
  if x > y then x, y = y, x end
  local p = hashOf(x .. "+" .. y) % 101
  local verdict = (p >= 90 and "Best friends forever!") or (p >= 70 and "A great team.") or (p >= 50 and "Could work. Build something together.")
                  or (p >= 25 and "Hmm. Maybe start with a small house.") or "Like a creeper and a cat. Keep your distance."
  return p, verdict
end

-- ===== 5. exact shapes =====
add(V.patterns, {
  -- mail: "tell Steve that ...", "tell Steve i said ...", "message for Steve: ...", "send Steve a message ..."
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local to, text = t:match("^tell (%w+) that (.+)$")
    if not to then to, text = t:match("^tell (%w+) i said (.+)$") end
    if not to then to, text = t:match("^message for (%w+) (.+)$") end
    if not to then to, text = t:match("^send (%w+) a message (.+)$") end
    if not to then to, text = t:match("^leave (%w+) a message (.+)$") end
    if not to or NOT_NAMES[to] or V.isOwner(to) then return nil end            -- (the owner: the old "leave a message")
    if to == tostring(who):lower() then return "You want to send yourself a message? I will just remember it then: " .. text end
    if not knownPlayer(to) then return "I do not know anyone called " .. to .. ". They have to visit me first." end
    local ok, why = V.sendMail(who, to, text)
    if not ok then return why end
    return "Got it. I will tell " .. realName(to) .. " when they come to the base."
  end,
  -- crafting recipes
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local term = t:match("how do i make (.+)$") or t:match("how do i craft (.+)$") or t:match("how to make (.+)$") or t:match("how to craft (.+)$")
                 or t:match("how do you make (.+)$") or t:match("how do you craft (.+)$") or t:match("recipe for (.+)$") or t:match("^recipe (.+)$")
                 or t:match("^craft (.+)$") or t:match("how can i make (.+)$")
    if not term then return nil end
    local k, v = V.lookupRecipe(term)
    if not k then return nil end                  -- (the guides / other answers may know it)
    return cap(k) .. ": " .. v
  end,
  -- the glossary
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local term = t:match("^what is (.+)$") or t:match("^what are (.+)$") or t:match("^what does (.+) do$") or t:match("^explain (.+)$")
                 or t:match("^tell me about (.+)$") or t:match("^define (.+)$") or t:match("^what is the (.+) for$") or t:match("^who is (.+)$")
    if not term then return nil end
    local k, v = V.lookupGloss(term)
    if not k then return nil end
    return cap(k) .. ": " .. v
  end,
  -- a joke about something
  function(who, raw, ws)
    local topic = table.concat(ws, " "):match("jokes? about (.+)$")
    if not topic then return nil end
    topic = topic:gsub("^an? ", ""):gsub("^the ", "")
    local hits = {}
    for _, j in ipairs(V.JOKES) do
      local jl = j:lower()
      for w in topic:gmatch("%a+") do
        if #w >= 3 and (jl:find(w, 1, true) or jl:find((w:gsub("s$", "")), 1, true)) then hits[#hits + 1] = j break end
      end
    end
    if #hits > 0 then return pick(hits) end
    return "I do not know a joke about " .. topic .. ". Here is another one: " .. pick(V.JOKES)
  end,
  -- ship two players
  function(who, raw, ws)
    local t = table.concat(ws, " ")
    local a, b = t:match("^ship (%w+) and (%w+)$")
    if not a then a, b = t:match("how compatible are (%w+) and (%w+)") end
    if not a then a, b = t:match("^love test (%w+) and (%w+)$") end
    if not a then a, b = t:match("^(%w+) and (%w+) compatibility$") end
    if not a then return nil end
    if a == "me" or a == "i" then a = who end
    if b == "me" or b == "i" then b = who end
    if tostring(a):lower() == tostring(b):lower() then return "You and yourself? 100 percent. Self love is important." end
    local p, verdict = ship(a, b)
    return cap(a) .. " and " .. cap(b) .. ": " .. p .. " percent. " .. verdict
  end,
})

-- ===== 6. intents =====
local function L(id, keys, reply) return { id = id, keys = keys, reply = reply } end
V.addIntents({
  L("streak", { "my streak", "days in a row", "visit streak", "how many days" }, function(w)
      local r = rec(w)
      local s = (r.vday == today() or r.vday == yesterday()) and (r.streak or 1) or 0
      return "Your visit streak: " .. V.plural(s, "day", "days") .. " in a row (best " .. (r.best or s) .. "). Come back tomorrow to keep it going!"
    end),
  L("mymail", { "my mail", "any mail", "mail for me", "messages for me", "did anyone write", "my letters" }, function(w)
      local n = V.deliverMail(w, false)
      return n == 0 and "No mail for you. Want to send some? Say: tell <name> that <message>." or ("That was all your mail (" .. n .. ").")
    end),
  L("mailhelp", { "send a message to", "message a player", "how do i send a message", "leave a message for a friend", "send mail" },
    { "Just say: tell Steve that the farm is ready. I give it to Steve when he comes to the base." }),
  L("spirit", { "spirit mob", "spirit animal", "what mob am i", "my spirit mob", "which mob am i" }, function(w)
      local m, why = spirit(w)
      return w .. ", your spirit mob is the " .. m .. ". " .. why
    end),
  L("shiphelp", { "ship me", "love test", "compatibility", "how compatible" },
    { "Say: ship me and Steve. Or: how compatible are Kevin and Steve." }),
  L("regulars", { "who visits the most", "most visits", "regulars", "best visitors", "top visitors" }, function()
      local list = {}
      for k, r in pairs(V.mem()) do
        if k:sub(1, 1) ~= "#" and type(r) == "table" and tonumber(r.visits) and not V.isOwner(k) then
          list[#list + 1] = { n = r.nick or k, v = r.visits }
        end
      end
      table.sort(list, function(a, b) return a.v > b.v end)
      if #list == 0 then return "Nobody has visited yet. You could be the first regular!" end
      local out = {}
      for i = 1, math.min(5, #list) do out[#out + 1] = list[i].n .. " (" .. list[i].v .. ")" end
      return "My most loyal visitors: " .. table.concat(out, ", ") .. "."
    end),
  L("uptime", { "how long have you been running", "uptime", "how long have you been on", "when did you start" }, function()
      local s = math.floor(os.clock())
      return "I have been running for " .. (fmtSpan and fmtSpan(s) or (s .. " seconds")) .. " since my last restart. Before that, I was asleep."
    end),
  L("glosshelp", { "what words do you know", "glossary", "dictionary", "minecraft words" }, function()
      local keys = {}
      for k in pairs(GLOSS) do keys[#keys + 1] = k end
      table.sort(keys)
      return "Ask me what is ... for: " .. table.concat(keys, ", ", 1, math.min(25, #keys)) .. " and more."
    end),
  L("recipehelp", { "recipes", "what can you craft", "crafting help", "recipe list" }, function()
      return "Ask me: how do I make a hopper. I know " .. (function() local n = 0 for _ in pairs(RECIPE) do n = n + 1 end return n end)() .. " recipes."
    end),
})
add(V.MORE, { { "a Minecraft word explained", "what words do you know" }, { "a crafting recipe", "recipes" },
  { "send a message to a player", "send mail" }, { "my spirit mob", "spirit mob" } })
add(V.TIPS, { "Tip: ask me what is a shulker box, or any other Minecraft word.", "Tip: ask me how do I make a hopper. I know lots of recipes.",
  "Tip: say tell, a name, that, and a message. I deliver it when they come by.", "Tip: visit every day. Streaks get rewards.",
  "Tip: ask me for a joke about creepers. Or about anything." })

-- ===== 7. coming back: streak, mail, last time =====
local GAME_NAMES = { guess = "guess my number", quiz = "the quiz", rps = "rock paper scissors", tf = "true or false", mob = "guess the mob",
  chain = "word chain", hl = "higher or lower", madlib = "mad libs", count = "counting", hang = "hangman", adv = "the adventure" }
local GAME_START = { guess = "guess my number", quiz = "quiz", rps = "rock paper scissors", tf = "true or false", mob = "guess the mob",
  chain = "word chain", hl = "higher or lower", madlib = "mad libs", count = "count with me", hang = "hangman", adv = "#adv:start" }
add(V.eventHooks, {
  function(who, kind, what)
    if not GAME_NAMES[what] then return end
    local r = rec(who)
    r.lastGame = { what = what, won = kind == "win", at = nowS() }
  end,
})
add(V.greetExtra, {
  function(name)
    if name == "someone" then return end
    V.visitDay(name)
    if V.deliverMail(name, true) > 0 then return end
    local r = V.mem()[tostring(name):lower()]
    local lg = type(r) == "table" and r.lastGame
    if type(lg) == "table" and GAME_NAMES[lg.what] and nowS() - (lg.at or 0) < 30 * 86400 and math.random() < 0.4 then
      r.lastGame = nil
      V.pend[tostring(name):lower()] = { kind = "yesno", yes = GAME_START[lg.what], till = os.clock() + 120 }
      V.openConvo(name)
      V.say(name .. ", last time you " .. (lg.won and "won at " or "played ") .. GAME_NAMES[lg.what] .. ". Rematch? Type yes.")
    end
  end,
})

-- ===== 8. milestones of the base (said once each, when someone is there to hear it) =====
local MILES = {
  { "chunks", { 1000, 2500, 5000, 10000, 25000, 50000, 100000 }, function() return MAP and tonumber(MAP.ovN) end, "My turtles have mapped %d chunks!" },
  { "turtles", { 5, 10, 20, 50, 100 }, function() local n = 0 for _ in pairs(state.turtles or {}) do n = n + 1 end return n end, "I command %d turtles now!" },
  { "visitors", { 10, 25, 50, 100, 250 }, function() local n = 0 for k, r in pairs(V.mem()) do if k:sub(1, 1) ~= "#" and type(r) == "table" and r.visits then n = n + 1 end end return n end,
    "I have met %d different players!" },
  { "gifts", { 10, 50, 100, 500 }, function() local b = V.base() return type(b.giftLog) == "table" and (b.giftsTotal or #b.giftLog) or 0 end, "I have given out %d gifts!" },
}
V.mileNext = 0
add(V.tickHooks, {
  function(now, nearNow)
    if now < (V.mileNext or 0) then return end
    V.mileNext = now + 60
    if not next(nearNow or {}) then return end
    local b = V.base()
    b.ms = type(b.ms) == "table" and b.ms or {}
    for _, m in ipairs(MILES) do
      local okV, v = pcall(m[3])
      v = okV and tonumber(v)
      if v then
        local top
        for _, at in ipairs(m[2]) do if v >= at and not b.ms[m[1] .. at] then top = at end end
        if top then
          for _, at in ipairs(m[2]) do if at <= top then b.ms[m[1] .. at] = true end end   -- (only the biggest new one is said)
          V.saveMem()
          V.say("Milestone! " .. string.format(m[4], top), "minecraft:entity.player.levelup")
          return
        end
      end
    end
  end,
})

-- ===== 9. thanks after a gift; counting gifts =====
V.giftThanks = V.giftThanks or {}
add(V.chatHooks, {
  function(who, text, near, answered)
    local b = V.base()
    -- (gifts counted for the milestones: the log keeps only the newest 60)
    if type(b.giftLog) == "table" and #b.giftLog > 0 then
      local last = b.giftLog[#b.giftLog]
      if last.at ~= b.giftCountedAt then
        b.giftsTotal = (b.giftsTotal or 0) + 1
        b.giftCountedAt = last.at
        V.giftThanks[tostring(last.who):lower()] = os.clock()
      end
    end
    local t = V.giftThanks[who:lower()]
    if t and os.clock() - t < 300 then
      local low = " " .. table.concat(V.norm(text), " ") .. " "
      if low:find(" thanks ", 1, true) or low:find(" thank ", 1, true) or low:find(" love ", 1, true) then
        V.giftThanks[who:lower()] = nil
        local line = fill(pick({ "You are very welcome, {name}! Enjoy your gift.", "Aww, {name}. You earned it!", "My pleasure, {name}. Friends deserve nice things." }), who)
        tell(who, line)
        if near then V.say(line) end
        V.addRep(who, 1, "kind")
      end
    end
  end,
})

-- ===== 9b. TAXI (the owner: "we know players' bed positions (overworld only) - offer them a free drone trip
-- from the base to their home or the other way") =====
-- Who: the owner, players on the allowed list, and friends of the base from voice.taxiTitle ("regular") up.
-- From the base (they are AT it) to their bed, or from near their bed (within 64 blocks) to the base - never
-- anywhere else. Their bed = the Player Detector's respawnPosition, overworld only; never told to anyone.
-- At most voice.taxiDaily (6) rides a day, 5 min apart, voice.taxiMax (5000) blocks (the owner: no limits).
-- Offered ONCE per visit to a friend who has stood at the base 4 min and lives far away. The ride itself is the
-- normal chat ride (startRide, base_chat.lua): the best free drone with air picks them up.
local RANK = { stranger = 0, visitor = 1, regular = 2, friend = 3, ["good friend"] = 4, ["best friend"] = 5, boss = 9 }
local function taxiOn() return V.cfg("taxi", true) ~= false end
local function homeXZ() local h = CONFIG.drone and CONFIG.drone.home return h and h.x and h end
function V.bedOf(name)
  if not det then return nil, "I have no Player Detector, so I cannot find your bed" end
  local fn = det.getPlayer or det.getPlayerPos
  if not fn then return nil, "my Player Detector cannot see beds" end
  local ok, p = pcall(fn, name)
  if not ok or type(p) ~= "table" then return nil, "I cannot see you right now" end
  local b = p.respawnPosition
  if type(b) ~= "table" or not tonumber(b.x) then return nil, "you have no bed set - sleep in one first", p end
  local d = p.respawnDimension
  if d and tostring(d) ~= (DRONE_DIM or "minecraft:overworld") then return nil, "your bed is not in the overworld - drones only fly there", p end
  return { x = math.floor(b.x), y = math.floor(b.y), z = math.floor(b.z) }, p
end
local function taxiAllowed(who)
  if V.isOwner(who) then return true end
  if not taxiOn() then return false, "The free drone taxi is closed right now." end
  if V.isFriend(who) then return true end
  local need = tostring(V.cfg("taxiTitle", "regular"))
  if (RANK[V.titleOf(who)] or 0) >= (RANK[need] or 2) then return true end
  return false, "The free drone taxi is for friends of the base (from " .. need .. " up). You are my " .. V.titleOf(who) ..
                ". Visit, play games, be kind - say friendship level to see how far you are."
end
local function flat(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.z - b.z)) end
local function baseDest()
  local w = findWaypoint and findWaypoint("Base")
  if w then return { kind = "waypoint", name = "the base", x = w.x, y = w.y, z = w.z } end
  local h = homeXZ()
  if h then return { kind = "waypoint", name = "the base", x = h.x, y = h.y, z = h.z } end
end
-- where = "bed" | "base" | nil (which way: at the base -> bed, near the bed -> base)
function V.taxi(who, where)
  local ok, why = taxiAllowed(who)
  if not ok then return why end
  if not startRide then return "The drone taxi needs a newer base program (upgrade)." end
  local bed, p = V.bedOf(who)
  if not bed then return "No taxi: " .. tostring(p) .. "." end
  local h = homeXZ()
  if not h then return "I do not know where the base is (CONFIG.drone.home)." end
  local at = { x = tonumber(p.x) or bed.x, z = tonumber(p.z) or bed.z }
  local atBase = isNear(who) or flat(at, h) <= 64
  local atBed = flat(at, bed) <= 64
  if flat(bed, h) <= 48 then return "Your bed is right here at the base. No taxi needed!" end
  if not where then where = atBase and "bed" or (atBed and "base") or "bed" end
  if where == "bed" and not atBase then
    return atBed and "You are at home already. Want to come to the base? Say: base, take me to the base."
           or "I fly from the base to your bed, or from your bed to the base. Come to the base first."
  end
  if where == "base" and not atBed then
    return atBase and "You are at the base already!" or "I only pick you up near your bed. Go home first, then say: base, take me to the base."
  end
  local r = rec(who)
  local owner = V.isOwner(who)
  if not owner then
    local max = tonumber(V.cfg("taxiMax", 5000)) or 5000
    if flat(bed, h) > max then return "Your bed is " .. flat(bed, h) .. " blocks away - the taxi goes " .. max .. " blocks at most." end
    r.taxi = (type(r.taxi) == "table" and r.taxi.d == today()) and r.taxi or { d = today(), n = 0 }
    local daily = tonumber(V.cfg("taxiDaily", 6)) or 6
    if r.taxi.n >= daily then return "That was your " .. daily .. " free rides for today. More tomorrow!" end
    if r.taxi.at and os.clock() - r.taxi.at < 300 then return "The taxi needs a short break - try again in " .. math.ceil((300 - (os.clock() - r.taxi.at)) / 60) .. " min." end
  end
  local dest = (where == "bed") and { kind = "coords", name = "your bed", x = bed.x, y = bed.y + 1, z = bed.z } or baseDest()
  if not dest then return "I do not know where the base is." end
  state.lastRide = state.lastRide or {}
  local before = state.lastRide[tostring(who):lower()]
  startRide(who, dest, true)
  if state.lastRide[tostring(who):lower()] == before then return nil end    -- (startRide said why in chat)
  if not owner then
    r.taxi.n, r.taxi.at = r.taxi.n + 1, os.clock()
    V.saveMem()
  end
  if where == "bed" then
    return fill(pick({ "Free ride home, on the house! Hold on tight, {name}.", "The base taxi takes you home, {name}. Enjoy the view!" }), who) ..
           " (To come back from home, say: base, take me to the base.)"
  end
  return fill(pick({ "Hop on, {name}! Next stop: the base.", "Taxi to the base is on its way, {name}." }), who)
end
V.hash.taxi = function(who, arg) return V.taxi(who, arg ~= "" and arg or nil) end
V.addIntents({
  L("taxihome", { "take me home", "fly me home", "ride home", "drone home", "take me to my bed", "fly me to my bed", "ride to my bed",
      "take me to my house", "fly me to my house", "taxi home", "free ride home" }, function(w) return V.taxi(w, "bed") end),
  L("taxibase", { "take me back", "bring me back", "fly me back", "pick me up", "come get me", "take me to the base",
      "fly me to the base" }, function(w) return V.taxi(w, "base") end),
  L("taxi", { "taxi", "free ride", "drone ride", "drone taxi", "can i get a ride", "give me a ride" }, function(w) return V.taxi(w, nil) end),
})
-- far from the base (at home): only the taxi is answered
add(V.farHooks, {
  function(who, text)
    -- (the whole message: the base's own name is "base" by default, and "take me to the base" needs that word)
    local t = " " .. table.concat(V.fix(V.norm(text)), " ") .. " "
    for _, ph in ipairs({ " to the base ", " to base ", " take me back ", " bring me back ", " fly me back ", " pick me up ",
                          " come get me ", " taxi ", " ride ", " take me home ", " fly me home " }) do
      if t:find(ph, 1, true) then return V.taxi(who, "base") or "OK." end
    end
    return nil
  end,
})
-- the offer: once per visit, a friend who has been at the base 4 min and lives far away
V.taxiOffered = V.taxiOffered or {}
V.taxiNext = 0
add(V.tickHooks, {
  function(now, nearNow)
    if not taxiOn() or now < (V.taxiNext or 0) then return end
    V.taxiNext = now + 10
    local h = homeXZ()
    if not h then return end
    for name in pairs(nearNow or {}) do
      local k = tostring(name):lower()
      local visit = V.since and V.since[name]
      if name ~= "someone" and not V.isOwner(name) and visit and now - visit >= 240 and V.taxiOffered[k] ~= visit
         and not V.pend[k] and not V.games[k] and taxiAllowed(name) then
        V.taxiOffered[k] = visit
        local bed = V.bedOf(name)
        if bed and flat(bed, h) > 150 and flat(bed, h) <= (tonumber(V.cfg("taxiMax", 5000)) or 5000) then
          V.pend[k] = { kind = "yesno", yes = "#taxi:bed", till = os.clock() + 120 }
          V.openConvo(name)
          tell(name, "Friends ride free: want a drone ride to your bed (" .. flat(bed, h) .. " blocks)? Type yes. From home, type: base, take me to the base.")
          V.say(name .. ", want a free drone ride home? Type yes.")
          return
        end
      end
    end
  end,
})
add(V.TIPS, { "Tip: friends of the base ride free. Say: take me home. From home, say: base, take me to the base." })
add(V.MORE, { { "a free drone ride home (friends)", "#taxi:bed" } })

-- ===== 10. more choices for the games of pack 1 + idle =====
add(V.MUSINGS, { "Somebody asked me what a shulker box is. I explained. I love explaining.",
  "I keep the mail for players who are not here yet. Like a tiny post office.", "Streaks are nice. I have been here every single day.",
  "Fun fact about me: I know more than sixty Minecraft words. Ask me one." })
add(V.idleExtra, {
  function(nearNow, who)   -- a word from the glossary
    local keys = {}
    for k in pairs(GLOSS) do keys[#keys + 1] = k end
    local k = pick(keys)
    return V.say("Word of the moment: " .. k .. ". It is " .. GLOSS[k])
  end,
  function(nearNow, who)   -- a recipe
    local keys = {}
    for k in pairs(RECIPE) do keys[#keys + 1] = k end
    local k = pick(keys)
    return V.say("Crafting tip: " .. k .. " is " .. RECIPE[k])
  end,
  function(nearNow, who)   -- their spirit mob
    if not who then return nil end
    local m = spirit(who)
    return V.say(who .. ", did you know your spirit mob is the " .. m .. "? Ask me why.")
  end,
  function(nearNow, who)   -- their streak
    if not who then return nil end
    local r = V.mem()[tostring(who):lower()]
    if type(r) ~= "table" or (r.streak or 0) < 2 then return nil end
    return V.say(who .. ", you have visited " .. r.streak .. " days in a row. Do not break the streak!")
  end,
})
