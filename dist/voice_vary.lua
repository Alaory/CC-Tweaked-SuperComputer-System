









local V = VOICE
if not V then return end
V.packs = V.packs or {}
V.packs["voice_vary.lua"] = { version = 1 }


local DATA = { "status", "turtles", "mining", "survey", "time", "weather", "online", "whereami", "mobs", "realtime", "whereturtle",
"biome", "moon", "slime", "light", "realdate", "score", "notes", "readmsg", "heard", "visitors", "whohere", "seeme", "knowme",
"friendship", "badges", "allbadges", "top", "gifts", "mygifts", "aboutme", "diary", "yesterday", "streak", "mymail", "regulars",
"uptime", "howmanyturtles2", "lore_lag", "lore_dronesslow", "news", "gossip", "mood", "owner", "lonely", "age", "luck" }
local INFO = { "who", "stay", "treasure", "glosshelp", "recipehelp", "mailhelp", "shiphelp", "mods", "code", "lag", "server", "version",
"turtlewhat", "dronewhat", "aewhat", "screenwhat", "respawn", "spawn", "portal", "directions", "cando", "languages", "whyname",
"advice", "wisdom", "motivate", "think", "sky", "stars", "hotcold", "creeper", "ender", "dragon", "wither", "warden", "villager",
"nether", "theend", "netherite", "redstone", "enchant", "potion", "farm", "fishing", "trade", "bestweapon", "whatdoing", "purpose" }
local NO = { "rules", "grief", "password", "hack", "shutdown", "openup", "freestuff", "teleport", "keepsecret", "secret2" }

local SKIP = { "menu", "games", "joke", "story", "fact", "roast", "compliment", "eight", "riddle", "unscramble", "hangman", "maths",
"wyr", "knockjoke", "adventure", "thisthat", "askme", "dare", "fortune", "quiz", "guess", "rps", "coin", "dice", "number", "sing",
"tour", "message", "bye", "remind", "remember", "say", "quiet", "talk", "clearmsg", "forgetheard", "tf", "mobgame", "chain", "hl",
"madlibs", "countgame", "hackgame", "pirate", "robotmode", "cowboy", "knight", "normal", "taxi", "taxihome", "taxibase",
"lore_modtip", "poem", "wotd", "qotd", "realfact", "secretword", "random", "petname", "basename", "teamname",
"heroname", "buildidea", "whattodo", "motto", "randommob", "randomitem", "love", "alive", "spirit", "tellsomeone", "sign",
"book", "rate", "wish2", "favnumber", "joketoo", "talktome", "diss" }
local KIND = {}
for _, id in ipairs(DATA) do KIND[id] = "data" end
for _, id in ipairs(INFO) do KIND[id] = "info" end
for _, id in ipairs(NO) do KIND[id] = "no" end
for _, id in ipairs(SKIP) do KIND[id] = "skip" end
V.VARY_KIND = KIND


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

ask = { "", " Tell me in chat.", " I am curious.", " Be honest.", " No wrong answers.", " Take your time.", " I will wait." },
}
V.varyN = V.varyN or {}


function V.vary(id, c, sp, who, started)
if type(c) ~= "string" or c == "" or started or not id then return c, sp end
local kind = KIND[id] or (id:find("^guide_") and "info") or (id:find("^lore_") and "info") or "chat"
if kind == "skip" then return c, sp end
if c:find("Type a number", 1, true) or c:find("Type yes", 1, true) or c:find("type yes", 1, true) then return c, sp end
local set = V.VARY[kind]
local n = V.varyN[id]
if not n then n = math.random(0, 69) end
V.varyN[id] = n + 1
local open = set.open[(n % #set.open) + 1]
local asks = c:match("%?%s*$") ~= nil
local closeList = asks and V.VARY.ask or set.close
local close = closeList[(n % #closeList) + 1]
local function wrap(t)
if type(t) ~= "string" or t == "" then return t end
local body = t

return open .. body .. close
end
return wrap(c), sp and wrap(sp) or nil
end






local REAL = {}
for w in ([[a about above across act add after again against age ago agree air all almost alone along already also always am
among an and angry animal another answer any anyone anything anyway apple are area arm army around art as ask asked at ate away
awesome baby back bad bag bake ball band bank bar base bat bath be bear beat beautiful became because become bed bee been before
began begin behind being believe bell below belt bench best better between big bike bird bit bite black blade blind block blood
blow blue board boat body boil bold bone book boot born boss both bottle bottom bought bow bowl box boy brain brave bread break
breath brick bridge bright bring broke brother brought brown brush bucket build built burn burnt bus busy but butter buy by cake
call came camp can cant car card care carpet carry case cast castle cat catch cause cave cell chain chair chance change charge
chat cheap check cheese chest chicken child chill choice choose chose church city class clean clear climb clock close cloth cloud
club coal coast coat code coffee coin cold color colour come cook cool copper copy corn corner cost cotton could count country
course cover cow crack craft crash crazy cream creek crew crop cross crowd crown cry cube cup cure cut cute dad daily damage dance
danger dark data date daughter day dead deal dear death decide deep deer desk did die diet dig dinner dirt dirty dish dive do
doctor does dog doing done door double doubt down drag draw dream dress drew drink drive drop drove drown dry duck dug during dust
duty each ear early earn earth east easy eat edge egg eight either else empty end enemy enough enter equal even evening ever every
exact eye eyes face fact fail fair fall false family famous far farm fast fat father fault fear feed feel feet fell felt fence few
field fight fill final find fine finger finish fire firm first fish fit five fix flag flat flew floor flow flower fly fog fold
follow food fool foot for force forest forget fork form fort forty forward found four fox free fresh friend from front fruit full
fun funny fur future gain game garden gas gate gave get ghost gift girl give glad glass glow go goat goes going gold golden gone
good got grab grass grave gray great green grew grey ground group grow guard guess guest gun guy had hair half hall hammer hand
hang happen happy hard harm hat hate have he head heal hear heard heart heat heavy held hell hello help her here hero hide high
hill him his hit hold hole holy home honest honey hope horn horse hot hour house how huge human hunt hurry hurt i ice idea if ill
in inch inside into iron is island it item its jail job join joke jump just keep kept key kick kid kill kind king kiss kit
kitchen knee knew knife knock know lady laid lake lamp land lane large last late laugh law lay lazy lead leaf learn least leave
led left leg less let letter level lie life lift light like lime line lion list listen little live load lock long look loose lord
lose loss lost lot loud love low luck lunch made mail main make male man many map mark market mass master match mate math may maybe
me meal mean meat meet melt men metal middle might mile milk mind mine minute miss mix mode moment money month moon more morning
most mother mouse mouth move much mud must my nail name near neck need nest net never new news next nice night nine no none noon
nor north nose not note nothing now number nurse oak ocean of off offer often oil old on once one only open or order other our out
over own pack page paid pain paint pair pan paper park part party pass past path pay peace pen people pet pick picture pie piece
pig pile pink pipe place plan plane plant plate play plenty plus pocket point pole pool poor pop pot pound power press pretty
price print prize pull pump punch push put queen quick quiet quit race rail rain raise ran rare rat rate raw reach read ready real
red rent rest rich ride right ring rise river road rock rod role roll roof room root rope rose round row rule run rush sad safe
said sail salt same sand sat save saw say scared school sea seat second see seed seem seen self sell send sent set seven shake
shall shape share sharp she sheep shelf shell shine ship shirt shoe shoot shop short shot should show shut sick side sign silk
silver sing sink sir sister sit six size skin sky sleep slide slip slow small smart smell smile smoke snake snow so soap soft
soil sold some son song soon sorry sort soul sound soup south space speak speed spell spend spent spider spin spot spring square
stand star start state stay steal steel step stick still stone stop store storm story strange street strong stuck stuff such
sugar suit summer sun sure swap sweet swim table tail take tale talk tall tank tap task taste tea teach team tear tell ten tent
test than thank that the their them then there these they thick thin thing think third this those though thought three threw
through throw tie till time tin tiny tired to today toe together told tomorrow tonight too took tool top torch total touch tough
tower town toy track trade train trap tree trick trip true trust truth try turn twice two type uncle under until up upon us use
used very view village visit voice wait wake walk wall want war warm was wash watch water wave way we weak wear week weird well
went were west wet what wheat wheel when where which while white who whole whose why wide wife wild will win wind window wing
winter wire wise wish with wolf woman won wood wool word wore work world worm worry would wrong wrote yard year yes yet you young
your zero zone ok okay chest beds sword pickaxe shovel axe hoe armor armour diamond emerald netherite redstone portal nether spawn
villager creeper zombie skeleton enderman slime witch golem pillager ravager blaze ghast piglin dragon wither warden server mods
modpack]]):gmatch("%S+") do REAL[w] = true end
V.REAL = REAL
function V.isReal(w)
w = tostring(w or "")
if #w < 3 or REAL[w] then return REAL[w] or false end
local function r(s) return REAL[s] end
if w:sub(-1) == "s" and (r(w:sub(1, -2)) or (w:sub(-2) == "es" and r(w:sub(1, -3))) or (w:sub(-3) == "ies" and r(w:sub(1, -4) .. "y"))) then return true end
if w:sub(-3) == "ing" then
local s = w:sub(1, -4)
if r(s) or r(s .. "e") or (#s > 2 and s:sub(-1) == s:sub(-2, -2) and r(s:sub(1, -2))) then return true end
end
if w:sub(-2) == "ed" then
local s = w:sub(1, -3)
if r(s) or r(w:sub(1, -2)) or (w:sub(-3) == "ied" and r(w:sub(1, -4) .. "y")) or (#s > 2 and s:sub(-1) == s:sub(-2, -2) and r(s:sub(1, -2))) then return true end
end
if w:sub(-2) == "er" and (r(w:sub(1, -3)) or r(w:sub(1, -2))) then return true end
if w:sub(-2) == "ly" and r(w:sub(1, -3)) then return true end
return false
end
V.resetVocab()


local ASK_Q = { "Sure, ask away - I am listening.", "Of course. What is it?", "Go ahead, {name}. Ask me anything.",
"Ask! I will do my best.", "Yes? I am all ears. Well, all speakers.", "Fire away, {name}." }
local BACK = { "Welcome back, {name}!", "There you are again, {name}.", "Oh, you are back! I missed you. A bit.",
"Welcome back. I kept an eye on things.", "Back already? Good. It was quiet without you." }
local HEAR = { "Ooh, tell me! I am listening.", "A story? Go on, {name}.", "I love stories. Type away.", "Tell me everything, {name}." }
local PLACE = { "Thank you, {name}! I like it here too.", "Aw, thanks. I will tell the turtles.", "Glad you like it, {name}. Make yourself at home.",
"Thank you! A lot of work went into this place.", "That is nice to hear. Thank you, {name}." }
table.insert(V.patterns, 1, function(who, raw, ws)
local t = " " .. table.concat(ws, " ") .. " "

local rest = t:gsub(" can i ask you ", " "):gsub(" may i ask you ", " "):gsub(" i have ", " "):gsub(" i got ", " ")
:gsub(" got ", " "):gsub(" quick ", " "):gsub(" a ", " "):gsub(" one ", " "):gsub(" another ", " ")
:gsub(" question ", " "):gsub(" something ", " "):gsub(" for you ", " "):gsub(" please ", " "):gsub(" hey ", " ")
if (t:find(" question ", 1, true) or t:find(" ask you something ", 1, true)) and rest:match("^%s*$") then
V.openConvo(who)
return V.fill(V.pick(ASK_Q), who)
end
if t:find(" i have a story ", 1, true) or t:find(" i got a story ", 1, true) or t:find(" let me tell you a story ", 1, true) then
V.openConvo(who)
return V.fill(V.pick(HEAR), who)
end
if t == " i am back " or t == " im back " or t == " back again " or t == " i am back again " or t == " i am home " then
return V.fill(V.pick(BACK), who)
end

local r0 = " " .. tostring(raw or ""):lower():gsub("[^%w ]", " "):gsub("%s+", " ") .. " "
local nm = " " .. tostring(V.cfg("name", "base")):lower() .. " "
if r0:sub(1, #nm) == nm then r0 = r0:sub(#nm) end
local GOOD = { "this place", "it here", "your base", "the base", "this base", "your place", "your house", "the place" }
for _, lead in ipairs({ " i love ", " i like ", " i really like ", " i really love ", " love ", " we love " }) do
for _, g in ipairs(GOOD) do if r0 == lead .. g .. " " then return V.fill(V.pick(PLACE), who) end end
end
for _, g in ipairs({ " nice base ", " cool base ", " awesome base ", " great base ", " nice place ", " cool place ", " beautiful base ",
" this place is cool ", " this place is nice ", " this place is awesome ", " this place is amazing " }) do
if r0 == g then return V.fill(V.pick(PLACE), who) end
end
end)
