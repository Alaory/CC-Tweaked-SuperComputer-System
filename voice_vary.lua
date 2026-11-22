-- voice_vary.lua  -  VARIETY PACK for the talking base (an add-on file, loaded LAST; see VOICE_FILES in base_theme.lua).
--
-- The owner: "add at least 50 variants for each interaction, each" (300 things it understands; many had one to three
-- answers). The lists that are asked for again and again (jokes, roasts, facts, stories ...) have 100+ lines of their
-- own (voice_lines / voice_idle). For EVERY other answer this pack adds the way it is said: an opener and a closer that
-- fit the KIND of answer - data (status, time, turtles: the numbers stay exactly as they are), information (guides,
-- lore), a "no" (rules, hacking), or small talk. They go in turn, not at random: openers 10 and closers 7 (no common
-- factor) = all 70 pairs once before any comes back, for every answer line it already had.
-- Never touched: answers that START something (a game, a menu, a yes / no question - their words matter), the big
-- lists above, generators (names, ideas), and answers to nothing in particular.
local V = VOICE
if not V then return end
V.packs = V.packs or {}
V.packs["voice_vary.lua"] = { version = 1 }

-- the kind of answer per intent (everything else = small talk)
local DATA = { "status", "turtles", "mining", "survey", "time", "weather", "online", "whereami", "mobs", "realtime", "whereturtle",
  "biome", "moon", "slime", "light", "realdate", "score", "notes", "readmsg", "heard", "visitors", "whohere", "seeme", "knowme",
  "friendship", "badges", "allbadges", "top", "gifts", "mygifts", "aboutme", "diary", "yesterday", "streak", "mymail", "regulars",
  "uptime", "howmanyturtles2", "lore_lag", "lore_dronesslow", "news", "gossip", "mood", "owner", "lonely", "age", "luck" }
local INFO = { "who", "stay", "treasure", "glosshelp", "recipehelp", "mailhelp", "shiphelp", "mods", "code", "lag", "server", "version",
  "turtlewhat", "dronewhat", "aewhat", "screenwhat", "respawn", "spawn", "portal", "directions", "cando", "languages", "whyname",
  "advice", "wisdom", "motivate", "think", "sky", "stars", "hotcold", "creeper", "ender", "dragon", "wither", "warden", "villager",
  "nether", "theend", "netherite", "redstone", "enchant", "potion", "farm", "fishing", "trade", "bestweapon", "whatdoing", "purpose" }
local NO = { "rules", "grief", "password", "hack", "shutdown", "openup", "freestuff", "teleport", "keepsecret", "secret2" }
-- left alone: lists of their own / games / menus / generators / things that change something
local SKIP = { "menu", "games", "joke", "story", "fact", "roast", "compliment", "eight", "riddle", "unscramble", "hangman", "maths",
  "wyr", "knockjoke", "adventure", "thisthat", "askme", "dare", "fortune", "quiz", "guess", "rps", "coin", "dice", "number", "sing",
  "tour", "message", "bye", "remind", "remember", "say", "quiet", "talk", "clearmsg", "forgetheard", "tf", "mobgame", "chain", "hl",
  "madlibs", "countgame", "hackgame", "pirate", "robotmode", "cowboy", "knight", "normal", "taxi", "taxihome", "taxibase",
  "lore_modtip", "poem", "wotd", "qotd", "dailyfortune", "realfact", "secretword", "random", "petname", "basename", "teamname",
  "heroname", "buildidea", "whattodo", "motto", "randommob", "randomitem", "love", "alive", "spirit", "tellsomeone", "sign",
  "book", "rate", "wish2", "favnumber", "joketoo", "talktome", "diss" }
local KIND = {}
for _, id in ipairs(DATA) do KIND[id] = "data" end
for _, id in ipairs(INFO) do KIND[id] = "info" end
for _, id in ipairs(NO) do KIND[id] = "no" end
for _, id in ipairs(SKIP) do KIND[id] = "skip" end
V.VARY_KIND = KIND

-- 10 openers and 7 closers per kind (the first of each = nothing)
V.VARY = {
  data = {
    open = { "", "Here you go. ", "Let me check. ", "One moment. ", "Right now: ", "Latest news: ", "Fresh from my sensors: ",
             "Checking. ", "Here is the latest. ", "Status report: " },
    close = { "", " Anything else?", " That is the latest.", " Ask me again any time.", " I keep an eye on it.",
              " Numbers do not lie.", " Updated just now." } },
  info = {
    open = { "", "Good question. ", "Here is what I know. ", "Glad you asked. ", "Let me explain. ", "Sure. ", "Easy one. ",
             "Listen to this. ", "Short answer: ", "From my notes: " },
    close = { "", " Hope that helps.", " Ask me more any time.", " Any other questions?", " That is how it works.",
              " Pretty neat, right?", " Now you know." } },
  no = {
    open = { "", "Sorry. ", "Nope. ", "Nice try. ", "Hmm, no. ", "Not a chance. ", "I do not think so. ", "Afraid not. ",
             "Let me be clear. ", "Ha! " },
    close = { "", " Rules are rules.", " Nothing personal.", " The turtles agree.", " Ask me something else.",
              " Still friends?", " Good try though." } },
  chat = {
    open = { "", "Hmm. ", "Oh! ", "Let me think. ", "Ha. ", "Good question. ", "Honestly? ", "You know what? ", "Ooh. ", "Okay. " },
    close = { "", " What about you?", " Just so you know.", " Fun, right?", " Thanks for asking.", " The turtles agree.",
              " Ask me more." } },
  -- (an answer that ends in a question: closers that still fit after it)
  ask = { "", " Tell me in chat.", " I am curious.", " Be honest.", " No wrong answers.", " Take your time.", " I will wait." },
}
V.varyN = V.varyN or {}

-- (chat text, spoken text) -> the same answer said one of 70 ways
function V.vary(id, c, sp, who, started)
  if type(c) ~= "string" or c == "" or started or not id then return c, sp end
  local kind = KIND[id] or (id:find("^guide_") and "info") or (id:find("^lore_") and "info") or "chat"
  if kind == "skip" then return c, sp end
  if c:find("Type a number", 1, true) or c:find("Type yes", 1, true) or c:find("type yes", 1, true) then return c, sp end
  local set = V.VARY[kind]
  local n = V.varyN[id]
  if not n then n = math.random(0, 69) end                    -- (each starts somewhere else)
  V.varyN[id] = n + 1
  local open = set.open[(n % #set.open) + 1]
  local asks = c:match("%?%s*$") ~= nil
  local closeList = asks and V.VARY.ask or set.close
  local close = closeList[(n % #closeList) + 1]
  local function wrap(t)
    if type(t) ~= "string" or t == "" then return t end
    local body = t
    -- (an opener ending in ": " or ". " - the answer keeps its own capital; "Hmm. hello" never happens: answers start with one)
    return open .. body .. close
  end
  return wrap(c), sp and wrap(sp) or nil
end
