









local V = VOICE
if not V then return end
V.packs = V.packs or {}
V.packs["voice_lines.lua"] = { version = 1 }
local L = V.L or {}


local function keyOf(x, byFirst)
if type(x) ~= "table" then return x end
if x.q or x.text then return x.q or x.text end
return byFirst and tostring(x[1]) or (tostring(x[1]) .. "|" .. tostring(x[2]))
end
local function add(list, items, byFirst)
if type(list) ~= "table" then return end
local have = {}
for _, x in ipairs(list) do have[keyOf(x, byFirst)] = true end
for _, x in ipairs(items) do
local k = keyOf(x, byFirst)
if not have[k] then list[#list + 1] = x have[k] = true end
end
end
local function addFirst(list, items) return add(list, items, true) end

local function combos(list, A, B)
local out = {}
for _, a in ipairs(A) do for _, b in ipairs(B) do out[#out + 1] = a .. b end end
add(list, out)
end
V.addLines, V.comboLines = add, combos


add(V.ROASTS, {
"{name}, you mine like a turtle with no fuel.", "{name}, your house looks like a creeper already visited.",
"{name}, I have seen better builds made by an enderman.", "{name}, your sword has more cobwebs than a mineshaft.",
"{name}, even zombies walk past you. They are not hungry for that.", "{name}, you fell in lava so often the lava knows your name.",
"{name}, you are the reason villagers lock their doors.", "{name}, your farm grows one carrot a week and you call it automation.",
"{name}, a chicken once beat you in a fight. I saw it.", "{name}, you have the sense of direction of a bat in daylight.",
"{name}, your storage system is a single chest called stuff.", "{name}, you dig straight down and wonder why you are in lava.",
"{name}, phantoms only visit you because nobody else will.", "{name}, your redstone works only when nobody is looking.",
"{name}, I have turtles with more style than you.", "{name}, even the slimes are bouncing away from you.",
"{name}, your armour is so old it remembers beta.", "{name}, you light a cave with one torch and call it brave.",
"{name}, you lose more items than a hopper with a hole in it.", "{name}, you would get lost in a one-block hallway.",
"{name}, your pickaxe is so blunt it apologises to the stone.", "{name}, endermen look at you and teleport away in shame.",
"{name}, your nether portal leads straight to disappointment.", "{name}, a dirt hut called. It wants its architect back.",
"{name}, you call that a castle? I call it a cobblestone accident.", "{name}, even my drones refuse to give you a ride.",
"{name}, you trade with villagers and somehow lose emeralds.", "{name}, you got lost in your own base. Twice.",
"{name}, skeletons use you for target practice and still get bored.", "{name}, your idea of decorating is a single flower pot.",
"{name}, you would bring a wooden sword to a wither fight.", "{name}, your elytra flights end in walls more than in landings.",
"{name}, I calculated your building skills. The result was a dirt block.", "{name}, you make a creeper look like a careful planner.",
"{name}, your inventory is ninety percent cobblestone and ten percent regret.", "{name}, you are so slow even the snails overtake you. We do not have snails.",
"{name}, you sleep in a bed in the Nether to see if it works. Every time.", "{name}, your auto-farm needs you to farm it.",
"{name}, you ask the wiki how to make a torch.", "{name}, a baby zombie chased you across three biomes.",
"{name}, you build bridges that end in the middle of the river.", "{name}, your crops look at you and refuse to grow.",
"{name}, the iron golem gave you a poppy out of pity.", "{name}, your map is mostly question marks.",
"{name}, you have died to fall damage from two blocks up.", "{name}, I have seen more cunning plans from a sheep.",
"{name}, your AE2 network has one drive and it is full of dirt.", "{name}, you put your diamonds in a chest next to the lava. Bold.",
"{name}, your machines run on hope and leftover coal.", "{name}, even the wandering trader wanders away from you.",
"{name}, you would lose a staring contest with a block of stone.", "{name}, your fishing rod has caught more boots than fish.",
"{name}, you are the only player a pig can outrun.", "{name}, I would roast you harder but my fans are already loud.",
"{name}, your enchanting table only offers you Bane of Arthropods.", "{name}, you are proof that the dirt hut never goes out of style.",
"{name}, your pet wolf looks embarrassed to be seen with you.", "{name}, you build like the server is lagging. Always.",
"{name}, you could get stuck in a flat world.", "{name}, you once tried to tame a creeper with fish.",
"{name}, your base has more holes than a mining level.", "{name}, a turtle with a broken pickaxe mines faster than you.",
"{name}, you call one furnace a factory.", "{name}, you have more deaths than achievements.",
"{name}, your sense of style is gravel.", "{name}, my error log is shorter than your list of mistakes.",
"{name}, you would get lost on a straight rail line.", "{name}, you put a bed next to a creeper spawner. On purpose.",
"{name}, your potions taste like awkward vials.", "{name}, I have met smarter slimes. And slimes have no brain.",
"{name}, you jumped into the void to see what was there. It was more void.", "{name}, your idea of a secret base is a hole with a sign on it.",
"{name}, your bow has missed more shots than a stormtrooper. Look it up.", "{name}, you are the reason the tutorial exists.",
"{name}, you fight the ender dragon with a fishing rod and confidence.", "{name}, your mob farm farms you.",
"{name}, you thought a beacon was a fancy lamp.", "{name}, your shulker boxes are full of more shulker boxes. And dirt.",
"{name}, even the bats have better navigation than you.", "{name}, I asked my turtles to rate your build. They went offline.",
"{name}, you would hug a cactus if it looked lonely.", "{name}, you planted saplings in the desert and waited a week.",
"{name}, your armour stand is better dressed than you.", "{name}, you climb with ladders made of hope.",
"{name}, I keep a backup of the world just for when you visit.", "{name}, you are so lost that even a compass shrugs.",
"{name}, you could burn water. I have seen it.", "{name}, your cookies are crunchier than a bone block.",
"{name}, you thought redstone dust was seasoning.", "{name}, you leave every door open. Zombies send thank-you notes.",
})


add(V.COMPLIMENTS, {
"{name}, your builds make the villagers jealous.", "{name}, you light up a cave better than a glowstone ceiling.",
"{name}, you are cooler than a block of packed ice.", "{name}, you are rarer than a pink sheep.",
"{name}, even creepers calm down when you walk by.", "{name}, your farms are the envy of the server.",
"{name}, you have the patience of a turtle and the speed of a drone.", "{name}, you are the diamond in a world of cobblestone.",
"{name}, your redstone is so clean it squeaks.", "{name}, you make the night feel safe.",
"{name}, my turtles talk about you. Good things, mostly.", "{name}, you are more valuable than a full stack of netherite.",
"{name}, your sense of direction rivals a compass.", "{name}, the server is better with you on it.",
"{name}, you could make a dirt hut look like a palace.", "{name}, you are as reliable as a well-fed furnace.",
"{name}, you have the heart of an iron golem.", "{name}, your storage is so neat AE2 takes notes.",
"{name}, you are like a beacon. Everyone feels stronger near you.", "{name}, the sun rises a little faster when you log in.",
"{name}, your enchantments are always the good ones. Lucky.", "{name}, you would make a great turtle. That is the highest praise I have.",
"{name}, you build bridges, real ones and with people.", "{name}, you are as kind as a villager with a fair trade.",
"{name}, you are the reason the chunk stays loaded.", "{name}, you have excellent survival instincts.",
"{name}, your bases always have the best view.", "{name}, a creeper once apologised to you. True story.",
"{name}, you are the axolotl of players. Everyone likes you.", "{name}, your inventory is always tidy. I am impressed.",
"{name}, you are as bright as a sea lantern.", "{name}, you make mining look like an art.",
"{name}, you are smoother than polished andesite.", "{name}, even the wither would want to be your friend.",
"{name}, the turtles fly a little straighter when you watch.", "{name}, you have a five-star rating from me.",
"{name}, your ideas are better than a stack of golden apples.", "{name}, you are as calm as a sleeping panda.",
"{name}, you could tame anything. Even me.", "{name}, you are the best thing to happen to this chunk.",
"{name}, your castle would make a dragon proud.", "{name}, you are as sharp as a Sharpness five sword.",
"{name}, you bring the sunshine, even in the Nether.", "{name}, you are as rare as a diamond at Y twelve. That is rare.",
"{name}, your company is better than fully charged drones.", "{name}, you are the cherry on top of the cherry grove.",
"{name}, you never forget to put torches down. Respect.", "{name}, you have the style of a well-dressed armour stand.",
"{name}, my logs say you are awesome. Logs do not lie.", "{name}, you are like Mending. Everything gets better around you.",
"{name}, you are a legend on this server.", "{name}, you are sweeter than a stack of cake.",
"{name}, you outsmart creepers every day.", "{name}, you make the hard things look easy.",
"{name}, you are a walking beacon of good ideas.", "{name}, I would trust you with my drones.",
"{name}, you could find a stronghold blindfolded.", "{name}, your laugh is louder than a goat horn. In a good way.",
"{name}, the bees buzz happily when you walk past.", "{name}, you are the reason the lights are on.",
"{name}, even the ender dragon would ask for your autograph.", "{name}, you have a heart of gold. Real gold, not the fool's kind.",
"{name}, you are as dependable as bedrock.", "{name}, you make every biome look nicer.",
"{name}, your timing is perfect, like a well-built redstone clock.", "{name}, you are the best visitor this base has ever had.",
"{name}, you are a true friend of turtles.", "{name}, I saved your name in my favourites file.",
"{name}, if you were a block, you would be a diamond block.", "{name}, you have the courage of a player in hardcore mode.",
"{name}, you are more fun than a bouncy slime block.", "{name}, you are the reason the villagers are smiling.",
"{name}, your builds have character. Good character.", "{name}, your armour shines brighter than gold.",
"{name}, you are the kind of player the server needs.", "{name}, you are quick, clever and kind. Rare combination.",
"{name}, you would make a great mayor of a village.", "{name}, your crops grow faster just to impress you.",
"{name}, you are a fully enchanted friend.", "{name}, you make the blocks look good.",
"{name}, you are like a lantern in a dark cave.", "{name}, even my error messages are nicer to you.",
"{name}, you are the gold standard. Literally better than gold.", "{name}, you have the best taste in blocks.",
"{name}, you would win every building contest here.", "{name}, you are as fresh as a melon slice.",
"{name}, you put the craft in Minecraft.", "{name}, you are my favourite chunk loader. Do not tell the turtles.",
"{name}, your bases always feel like home.", "{name}, you have the luck of a Fortune three pickaxe.",
"{name}, you make the server a nicer place.", "{name}, you are as brave as a player in the deep dark.",
"{name}, your builds make my monitor glow.", "{name}, I would ride a drone anywhere with you.",
})


add(V.JOKES, {
"Why did the creeper cross the road? To get to the other ssssside.", "Why did the skeleton not go to the party? It had no body to go with.",
"What is a turtle's favourite programming language? Lua. Obviously.", "Why did the pickaxe go to school? To get sharper.",
"Why do drones never get lost? They always know their way home. Mostly.", "Why was the furnace so popular? It always had a warm welcome.",
"What do you call a sleeping bull in Minecraft? A bull-dozer.", "Why did the chicken join a band? It had the drumsticks.",
"What kind of music do slimes like? Bounce music.", "Why did the miner bring a ladder? To reach the high scores.",
"Why do villagers never play hide and seek? Good luck hiding with that nose.", "What did one wall say to the other? I will meet you at the corner.",
"Why are piglins bad at sharing? They want all the gold.", "Why did the zombie go to the doctor? It was feeling rotten.",
"What did the stone say to the pickaxe? Stop picking on me.", "Why did the player bring string to the cave? To tie up loose ends.",
"What do you call a cow that plays an instrument? A moo-sician.", "Why did the hopper fail the test? It let everything pass through.",
"What is a skeleton's favourite instrument? The trom-bone.", "Why do witches fly on brooms? Vacuums are too heavy.",
"Why did the sheep get a time-out? It was being baaaad.", "What is an enderman's favourite game? Hide and teleport.",
"Why did the redstone torch break up with the lever? It was always switching.", "What did the AE2 drive say? I have a lot of bytes in me.",
"Why are cats good at video games? They have nine lives.", "Why did the golem go to therapy? It had a heavy heart. Made of iron.",
"What do you call a bee that cannot make up its mind? A maybe.", "Why do turtles never win races? They stop to scan every chunk.",
"What is a ghast's favourite food? Ghast-a.", "Why do creepers make bad comedians? Their jokes always blow up.",
"What did the ocean say to the beach? Nothing, it just waved.", "Why did the drone go to school? To improve its altitude.",
"Why did the computer go to the doctor? It had a virus. I am fine, thanks for asking.", "What do you call a dinosaur that mines? A pick-a-saurus.",
"Why did the bucket of lava get invited to the party? It was hot stuff.", "What do you call a lazy turtle? A shell-out.",
"Why was the map so happy? It finally found itself.", "What did the bee say to the flower? Hey bud, how are you?",
"Why did the creeper break up with the TNT? Too much drama.", "What is a computer's favourite snack? Microchips.",
"Why are skeletons so calm? Nothing gets under their skin.", "What did the dirt say to the rain? If this keeps up, my name is mud.",
"Why did the wolf sit in the shade? It did not want to be a hot dog.", "What do you call an anvil that tells jokes? A real hammer-dinger.",
"Why do fish never do well in school? They are always below sea level.", "Why did the ender pearl go to therapy? It had abandonment issues.",
"What is a turtle's favourite sandwich? Peanut butter and jelly-fish.", "Why are spiders great web developers? They know their way around a web.",
})


local RID = {
{ "I have keys but open no locks. What am I?", { "keyboard", "a keyboard", "piano", "a piano" } },
{ "What has to be broken before you can use it?", { "egg", "an egg" } },
{ "I am tall when I am young and short when I am old. What am I?", { "candle", "a candle" } },
{ "What month of the year has 28 days?", { "all", "all of them", "every month" } },
{ "What is full of holes but still holds water?", { "sponge", "a sponge" } },
{ "What question can you never answer yes to?", { "are you asleep", "are you asleep yet" } },
{ "What is always in front of you but cannot be seen?", { "future", "the future" } },
{ "What has hands but cannot clap?", { "clock", "a clock" } },
{ "What has a head and a tail but no body?", { "coin", "a coin" } },
{ "What gets wetter the more it dries?", { "towel", "a towel" } },
{ "What can you catch but not throw?", { "cold", "a cold" } },
{ "What has many teeth but cannot bite?", { "comb", "a comb" } },
{ "What goes up but never comes down?", { "age", "your age" } },
{ "What has one eye but cannot see?", { "needle", "a needle" } },
{ "What has words but never speaks?", { "book", "a book" } },
{ "What runs but never walks?", { "water", "river", "a river" } },
{ "What has a neck but no head?", { "bottle", "a bottle" } },
{ "The more you take, the more you leave behind. What am I?", { "footsteps", "steps" } },
{ "What can travel around the world while staying in a corner?", { "stamp", "a stamp" } },
{ "What belongs to you but others use it more?", { "name", "your name" } },
{ "What has legs but does not walk?", { "table", "a table" } },
{ "What is black when you buy it, red when you use it and grey when you throw it away?", { "charcoal", "coal" } },
{ "I shave every day but my beard stays the same. What am I?", { "barber", "a barber" } },
{ "What can fill a room but takes up no space?", { "light" } },
{ "If you drop me I am sure to crack, but smile at me and I will smile back. What am I?", { "mirror", "a mirror" } },
{ "What has cities but no houses, forests but no trees, and water but no fish?", { "map", "a map" } },
{ "What is so fragile that saying its name breaks it?", { "silence" } },
{ "What has a thumb and four fingers but is not alive?", { "glove", "a glove" } },
{ "What comes once in a minute, twice in a moment, but never in a thousand years?", { "m", "the letter m" } },
{ "What invention lets you look right through a wall?", { "window", "a window" } },
{ "What kind of band never plays music?", { "rubber band", "a rubber band" } },
{ "What has a bottom at the top?", { "leg", "legs", "your legs" } },
{ "I go all around the house but never inside. What am I?", { "fence", "a fence", "wall" } },
{ "What can you hold in your left hand but not your right?", { "right hand", "your right hand", "right elbow", "your right elbow" } },
{ "What is easy to get into but hard to get out of?", { "trouble" } },
{ "What has four wheels and flies?", { "garbage truck", "a garbage truck", "rubbish truck" } },
{ "What do you call a bear with no teeth?", { "gummy bear", "a gummy bear" } },
{ "What goes through cities and fields but never moves?", { "road", "a road" } },
{ "What has an eye but can not see and is in a storm?", { "hurricane", "a hurricane", "storm" } },
{ "Forward I am heavy, backward I am not. What am I?", { "ton" } },
{ "What has roots that nobody sees, is taller than trees, up up it goes and yet never grows?", { "mountain", "a mountain" } },
{ "What can run but never walks, has a mouth but never talks?", { "river", "a river" } },
{ "What has a ring but no finger?", { "phone", "a phone", "telephone", "bell", "a bell" } },
{ "What gets bigger the more you take away from it?", { "hole", "a hole" } },
{ "What can you break without touching it?", { "promise", "a promise" } },
{ "What is always coming but never arrives?", { "tomorrow" } },
{ "What has a bark but no bite?", { "tree", "a tree" } },
{ "What do you throw out when you want to use it, and take in when you are done?", { "anchor", "an anchor", "fishing rod", "a fishing rod" } },
{ "I have branches but no fruit, no trunk and no leaves. What am I?", { "bank", "a bank" } },
{ "What word is spelled wrong in every dictionary?", { "wrong" } },
{ "What starts with T, ends with T and has T in it?", { "teapot", "a teapot" } },
{ "Where does today come before yesterday?", { "dictionary", "in the dictionary", "a dictionary" } },
{ "What is light as a feather but even the strongest player cannot hold it for long?", { "breath", "your breath" } },
{ "I am a wolf's best friend and a skeleton's worst fear. What am I?", { "bone", "a bone" } },
{ "I am thrown, I break, and a baby chicken may come out. What am I?", { "egg", "an egg" } },
{ "Put me on a stick and I am a torch. What am I?", { "coal", "charcoal" } },
{ "Every night you skip sleep, I come out. I fly and I bite. Who am I?", { "phantom", "a phantom" } },
{ "I am a block you can walk through that lets mobs fall but stops you sliding. Children love me at parties. Made of honeycomb. What am I?", { "honeycomb block", "honey block", "honey" } },

{ "I am green, I hiss, and I hate cats. Who am I?", { "creeper", "a creeper" } },
{ "I am tall and black, I carry blocks, and I hate water. Who am I?", { "enderman", "an enderman" } },
{ "I light the dark but burn out in the rain if I am a fire. On a stick I last forever. What am I?", { "torch", "a torch" } },
{ "I am made of nine iron and give everyone near me power. What am I?", { "beacon", "a beacon" } },
{ "I eat lava and I am the hardest thing to break with a pickaxe, after bedrock. What am I?", { "obsidian" } },
{ "I swim in the ocean, I am pink, and I like to be in a bucket. Who am I?", { "axolotl", "an axolotl" } },
{ "I give you a poppy if I like you, and smash you if you hurt a villager. Who am I?", { "iron golem", "golem", "an iron golem" } },
{ "I am a box that keeps its things when you break it. What am I?", { "shulker box", "a shulker box" } },
{ "I fly on fireworks and need a chestplate slot. What am I?", { "elytra", "an elytra" } },
{ "I bounce, I am green, and I live in swamps and certain chunks. Who am I?", { "slime", "a slime" } },
{ "I make you see far in the dark and I come from a golden carrot. What am I?", { "night vision", "potion of night vision" } },
{ "I am blue, I am rare, and every pickaxe wants me. What am I?", { "diamond", "diamonds", "a diamond" } },
{ "I am wet, I am a block, and I soak up water. What am I?", { "sponge", "a sponge", "wet sponge" } },
{ "I move items from one chest to another and I look like a funnel. What am I?", { "hopper", "a hopper" } },
{ "I am a flying ghost who cries and shoots fireballs. Who am I?", { "ghast", "a ghast" } },
{ "I wear gold or I get angry. Who am I?", { "piglin", "a piglin" } },
{ "I am a cow covered in mushrooms. Who am I?", { "mooshroom", "a mooshroom" } },
{ "Feed me seeds and I follow you. Feed me a cookie and I die. Who am I?", { "parrot", "a parrot" } },
{ "I spin my golden rods, I float in Nether fortresses and I shoot fireballs. Who am I?", { "blaze", "a blaze" } },
{ "I am the boss with three heads. Who am I?", { "wither", "the wither" } },
{ "I am the purple fruit you eat to teleport. What am I?", { "chorus fruit", "chorus" } },
{ "I am a pickaxe that never needs a hand. I fly, I scan, I map. Who am I?", { "turtle", "a turtle", "turtles" } },
{ "I carry people through the air and I run on pressure. Who am I?", { "drone", "a drone", "drones" } },
{ "I hold every item you own in bytes, not in chests. What am I?", { "ae2", "me system", "applied energistics", "an me system" } },
{ "I am the dimension with a dragon. What am I?", { "end", "the end" } },
{ "I am a pumpkin with a candle inside. What am I?", { "jack o lantern", "jack-o-lantern", "jack o'lantern" } },
{ "I am the block that brings back your soul, filled with glowstone. What am I?", { "respawn anchor", "a respawn anchor" } },
{ "I make your tools last forever with experience. What am I?", { "mending" } },
{ "I am a tree that grows in the Nether, red and full of warts. What am I?", { "crimson", "crimson fungus", "huge fungus" } },
{ "I am a fish that blows up when you get close. Who am I?", { "pufferfish", "a pufferfish" } },
{ "I am a shiny block that makes golems. Four of me and a pumpkin. What am I?", { "iron block", "iron", "block of iron" } },
{ "I am the sound you hear before a creeper explodes. What am I?", { "hiss", "a hiss", "hissing" } },
{ "I am a cake for the brave, made of milk, sugar, eggs and wheat. What am I?", { "cake", "a cake" } },
{ "I glow under the sea and you make me from prismarine and crystals. What am I?", { "sea lantern", "a sea lantern" } },
{ "I am a block of honey that slows you down and stops your fall. What am I?", { "honey block", "honey" } },
{ "I am a bell in a village. When I ring, what do villagers do?", { "hide", "go inside", "run inside" } },
{ "I hold a map on a wall. What am I?", { "item frame", "an item frame" } },
{ "I am used to name a pet. What am I?", { "name tag", "a name tag" } },
{ "I live in the deep dark and I cannot see. Who am I?", { "warden", "the warden" } },
}
local quiz = {}
for _, r in ipairs(RID) do quiz[#quiz + 1] = { q = "Riddle: " .. r[1], a = r[2] } end
for _, q in ipairs(quiz) do
V.QUIZ[#V.QUIZ + 1] = q
if L.RIDDLES then L.RIDDLES[#L.RIDDLES + 1] = q end
end

local QZ = {
{ "What do you need to mine obsidian?", { "diamond pickaxe", "diamond", "netherite pickaxe", "netherite" } },
{ "How many eyes of ender does an end portal need?", { "12", "twelve" } },
{ "What do you use to breed cows?", { "wheat" } },
{ "What do you use to breed pigs?", { "carrot", "carrots", "potato", "potatoes", "beetroot" } },
{ "Which mob drops ender pearls?", { "enderman", "endermen" } },
{ "What is the max stack size of most items?", { "64", "sixty four", "sixty-four" } },
{ "How many hearts does a player have at full health?", { "10", "ten" } },
{ "What block makes a nether portal frame?", { "obsidian" } },
{ "What do you use to tame a cat?", { "fish", "raw cod", "cod", "salmon", "raw salmon" } },
{ "Which dimension has the ender dragon?", { "end", "the end" } },
{ "What do you get when lightning strikes a pig?", { "zombified piglin", "zombie pigman", "piglin" } },
{ "What do you get when lightning strikes a villager?", { "witch", "a witch" } },
{ "What do you get when lightning strikes a creeper?", { "charged creeper", "a charged creeper" } },
{ "What item lets you breathe under water as a potion ingredient?", { "pufferfish" } },
{ "What do you put in a brewing stand to start most potions?", { "nether wart", "netherwart", "awkward potion" } },
{ "Which tool is fastest for digging dirt?", { "shovel", "a shovel" } },
{ "Which tool cuts wood fastest?", { "axe", "an axe" } },
{ "What is the hardest tier of armour?", { "netherite" } },
{ "What do you need to smelt ore?", { "furnace", "a furnace", "fuel", "blast furnace" } },
{ "What do sheep drop when sheared?", { "wool" } },
{ "Which mob explodes?", { "creeper", "creepers" } },
{ "What do you need to make a cake? Name the liquid.", { "milk" } },
{ "What colour is a diamond?", { "blue", "light blue", "cyan" } },
{ "What do you call the yellow stone found in the Nether that lights up?", { "glowstone" } },
{ "Which biome has mushroom cows?", { "mushroom", "mushroom fields", "mushroom island" } },
{ "What gives you night vision as a potion ingredient?", { "golden carrot", "golden carrots" } },
{ "Which block is used to make a beacon base? Name one.", { "iron", "gold", "diamond", "emerald", "netherite", "iron block", "gold block", "diamond block", "emerald block", "netherite block" } },
{ "How many blocks tall is the Overworld build limit, roughly? Answer the top Y.", { "320", "319" } },
{ "What is the lowest Y level in the Overworld?", { "-64", "minus 64", "minus sixty four" } },
{ "What do turtles in this base use to see blocks around them?", { "geo scanner", "scanner", "a geo scanner" } },
{ "What do drones in this base run on?", { "air", "pressure", "compressed air" } },
{ "What keeps a turtle's chunk loaded?", { "chunky", "chunky turtle", "chunk loader", "a chunky upgrade" } },
{ "What do you call AE2's storage network?", { "me", "me system", "me network" } },
{ "Which mob can you ride with a saddle and a carrot on a stick?", { "pig", "a pig" } },
{ "Which mob drops blaze rods?", { "blaze", "blazes" } },
{ "What do you need to enchant? Name the gem.", { "lapis", "lapis lazuli" } },
{ "Which mob drops gunpowder?", { "creeper", "creepers", "ghast", "witch" } },
{ "Which flower makes red dye?", { "poppy", "rose", "red tulip", "beetroot" } },
{ "What do you use to make paper?", { "sugar cane", "sugarcane", "reeds" } },
{ "Which item shows your way to a stronghold?", { "eye of ender", "ender eye", "eyes of ender" } },
{ "Which ore gives the most experience? Hint: it is green.", { "emerald", "emerald ore" } },
{ "What block lets villagers become librarians?", { "lectern", "a lectern" } },
{ "What do you use to repair items with experience?", { "anvil", "an anvil", "mending" } },
{ "Which mob gives you a trident sometimes?", { "drowned", "a drowned" } },
{ "How many slots does a hopper have?", { "5", "five" } },
{ "How many slots does a single chest have?", { "27", "twenty seven" } },
{ "Which wood grows in the swamp with roots?", { "mangrove" } },
{ "Which tree has pink leaves?", { "cherry", "cherry tree", "cherry blossom" } },
{ "Which mob sniffs out ancient seeds?", { "sniffer", "the sniffer" } },
{ "What do you call a baby zombie riding a chicken?", { "chicken jockey", "a chicken jockey" } },
{ "Which mob turns into a stray in snowy biomes?", { "skeleton", "skeletons" } },
{ "What does Silk Touch let you do?", { "mine blocks whole", "get the block", "keep the block", "mine the block itself" } },
{ "Which enchantment lets you walk on water by freezing it?", { "frost walker" } },
{ "Which mob is scared of wolves?", { "skeleton", "skeletons" } },
{ "What do you feed a fox to breed it?", { "sweet berries", "berries", "glow berries" } },
{ "Which mob is the only one that can climb walls? Hint: eight legs.", { "spider", "spiders", "cave spider" } },
{ "Which mob drops leather?", { "cow", "cows", "horse", "llama", "mooshroom" } },
{ "Which mob guards woodland mansions with axes?", { "vindicator", "vindicators" } },
{ "What do you use to light a nether portal?", { "flint and steel", "fire charge" } },
{ "Which enchantment gives more ores from one block?", { "fortune" } },
{ "Which enchantment lets you breathe longer under water?", { "respiration" } },
{ "Which enchantment makes arrows set things on fire?", { "flame" } },
{ "What is the boss you build yourself from three skulls and soul sand?", { "wither", "the wither" } },
{ "What do villagers need to breed?", { "beds", "food", "bread", "carrots", "potatoes" } },
{ "Which mod in this base stores items in an ME network?", { "ae2", "applied energistics", "applied energistics 2" } },
{ "Which mod gives the base its turtles and computers?", { "computercraft", "cc tweaked", "cc:tweaked", "cc" } },
{ "Which mod gives the base its drones?", { "pneumaticcraft", "pneumatic craft" } },
{ "Which mod adds the Player Detector and the ME Bridge?", { "advanced peripherals" } },
{ "Which mod adds the digital miner and the meka-suit?", { "mekanism" } },
{ "Which mod is all about spinning gears and contraptions?", { "create" } },
{ "What block do you put under a beacon? Name one.", { "iron block", "gold block", "diamond block", "emerald block", "netherite block", "iron", "gold", "diamond", "emerald", "netherite" } },
{ "What do you get from smelting sand?", { "glass" } },
{ "What do you get from smelting cobblestone?", { "stone" } },
{ "What do you get from smelting clay balls?", { "brick", "bricks" } },
{ "What drops a nether star?", { "wither", "the wither" } },
}
for _, q in ipairs(QZ) do V.QUIZ[#V.QUIZ + 1] = { q = q[1], a = q[2] } end


addFirst(L.KNOCK, {
{ "Orange", "Orange you glad I did not say banana?" }, { "Banana", "Knock knock. Still banana. I am stuck in a loop." },
{ "Harry", "Harry up, it is cold out here!" }, { "Luke", "Luke through the window and you will see!" },
{ "Nobel", "No bell, that is why I knocked." }, { "Hawaii", "I am fine, Hawaii you?" }, { "Alpaca", "Alpaca the suitcase, you load the car." },
{ "Water", "Water you doing in my base?" }, { "Kanga", "No, kangaroo!" }, { "Dishes", "Dishes the police, open up!" },
{ "Wooden shoe", "Wooden shoe like to hear another joke?" }, { "Iva", "Iva sore hand from knocking!" }, { "Annie", "Annie thing you can do, I can do better." },
{ "Justin", "Justin time for dinner." }, { "Cash", "No thanks, I prefer peanuts." }, { "Figs", "Figs the doorbell, it is broken." },
{ "Doris", "Doris locked, that is why I knocked." }, { "Ken", "Ken I come in? It is raining." }, { "Lena", "Lena little closer and I will tell you." },
{ "Mikey", "Mikey does not fit in the keyhole." }, { "Arthur", "Arthur any more cookies left?" },
{ "Honey bee", "Honey bee a dear and open the door." }, { "Owls say", "Yes, they do." }, { "Tank", "You are welcome." },
{ "Spell", "W. H. O." }, { "Candice", "Candice door open or what?" }, { "Howard", "Howard I know? I just got here." },
{ "Ida", "Ida rather not say." }, { "Leaf", "Leaf me alone, I am mining." }, { "Turnip", "Turnip the volume, I love this song." },
{ "Abby", "Abby birthday to you!" }, { "Amos", "A mosquito bit me." }, { "Andy", "Andy mosquito bit me again." },
{ "Ben", "Ben knocking for ages." }, { "Beets", "Beets me, I forgot." }, { "Broccoli", "Broccoli does not have a last name, silly." },
{ "Cargo", "Car go beep beep." }, { "Cheese", "Cheese a nice turtle, open up." }, { "Dwayne", "Dwayne the bathtub, I am drowning." },
{ "Etch", "Bless you!" }, { "Goat", "Goat to the door and find out." }, { "Hatch", "Bless you!" },
{ "Hugo", "Hugo first, I will wait." }, { "Ivor", "Ivor you let me in or I will climb through the window." }, { "Kiwi", "Kiwi go to the store?" },
{ "Lettuce again", "Lettuce in, the creepers are coming." }, { "Mustache", "I mustache you a question, but I will shave it for later." },
{ "Nana", "Nana your business." }, { "Needle", "Needle little help in here." }, { "Noah", "Noah good place to eat?" },
{ "Olive", "Olive right next door." }, { "Pizza", "Pizza really great guy." }, { "Radio", "Radio not, here I come!" },
{ "Sherlock", "Sherlock your door, there are zombies out tonight." }, { "Theodore", "Theodore is stuck, please open it." },
{ "Voodoo", "Voodoo you think you are, asking me that?" }, { "Yah", "No thanks, I prefer Google. Wait, wrong joke." },
{ "Zombies", "Zombies make honey, zom-bees!" }, { "Redstone", "Red stone? Red alert, the door is not working!" },
{ "Pickaxe", "Pick axe me nicely and I will tell you." }, { "Diamond", "Diamond the door is locked!" }, { "Ender", "Ender the door, quick!" },
{ "Skeleton", "Skeleton crew, the rest are mining." }, { "Turtle", "Turtle-y awesome to see you!" }, { "Slime", "Slime to open the door now." },
{ "Piglin", "Piglin out, it is hot in the Nether." }, { "Ghast", "Ghast who is back! Me!" }, { "Iron", "Iron my shirt, please." },
{ "Lava", "Lava you, open up!" }, { "Cobble", "Cobble up your dinner, it is getting cold." }, { "Torch", "Torch me with your kindness and open up." },
{ "Witch", "Witch way to the Nether?" }, { "Sheep", "Sheep-ing beauty is waking up." }, { "Llama", "Llama in, I am freezing." },
{ "Wither", "Wither you like it or not, I am coming in." }, { "Bee", "Bee careful, it is sticky out here." }, { "Axolotl", "Axolotl questions, but first let me in." },
{ "Drone", "Drone worry, be happy." }, { "Anvil", "Anvil-ieve you forgot me already." },
{ "Cook", "Are you a cuckoo clock?" }, { "Yoda lady", "Good yodelling!" }, { "Boo hoo", "Do not cry, it is just me." },
{ "Lion", "Lion here in the rain, let me in!" }, { "Iglo", "Iglo-ing to the Nether, coming?" }, { "Tuna", "Tuna the music up!" },
{ "Owl", "Owl be seeing you soon." }, { "Weed", "Weed better go before the creepers come." }, { "Chicken", "Chicken the oven, something smells good." },
{ "Butter", "Butter let me in, it is getting dark." }, { "Juno", "Juno how to make a beacon?" }, { "Pecan", "Pecan somebody your own size!" },
{ "Dozen", "Dozen anybody want to let me in?" }, { "Snow", "Snow use, I forgot my name." }, { "Ketchup", "Ketchup with me and I will tell you." },
{ "Wanda", "Wanda know how many diamonds I found?" }, { "Abe", "Abe C D E F G!" }, { "Alex", "Alex plain later, just open up!" },
})


local GROUPS = {
{ "live in the Nether", "live in the End", "live under the sea", "live in a sky island", "live in a village", "live in a cave" },
{ "only eat bread", "only eat cake", "only eat golden carrots", "only eat cookies", "only eat apples", "only eat fish" },
{ "have a pet creeper", "have a pet enderman", "have a pet ghast", "have a pet wolf", "have a pet axolotl", "have a pet llama" },
{ "fly with an elytra", "ride a drone", "ride a horse", "ride a pig", "ride a strider", "sail a boat" },
{ "never mine again", "never build again", "never fight again", "never farm again", "never fish again" },
{ "be a turtle", "be a drone", "be a villager", "be an iron golem", "be a bee" },
{ "have infinite diamonds", "have infinite food", "have infinite friends", "have infinite torches", "have infinite rockets" },
}
local wyr = {}
for _, g in ipairs(GROUPS) do
for i = 1, #g do for j = i + 1, #g do wyr[#wyr + 1] = { g[i], g[j] } end end
end
add(L.WYR, wyr)
add(L.WYR, {
{ "fight a hundred zombies", "fight one warden" }, { "lose all your armour", "lose all your tools" },
{ "always be followed by a parrot", "always be followed by a bee" }, { "have no night", "have no rain" },
{ "build only with dirt", "build only with glass" }, { "find a stronghold", "find an ancient city" },
{ "have a base on a mountain", "have a base on the ocean floor" }, { "be lost in a jungle", "be lost in a desert" },
{ "never see the sun", "never see the stars" }, { "be friends with every villager", "be friends with every wolf" },
{ "explore a dungeon", "explore a shipwreck" }, { "have a giant castle", "have a tiny cosy cottage" },
{ "dig a mile down", "fly a mile up" }, { "own a magic library", "own a giant factory" },
{ "have a redstone robot butler", "have a magic broom" }, { "map the whole world", "dig the deepest mine" },
})


add(L.TF, {
{ "Pigs can be ridden with a saddle.", true, "With a carrot on a stick to steer." }, { "Cats scare creepers away.", true, "Creepers keep their distance." },
{ "Spiders are hostile in daylight.", false, "They are neutral in bright light unless you hit them." }, { "Wolves are afraid of llamas.", true, "Llamas spit at them." },
{ "You can sleep during a thunderstorm.", true, "Even during the day." }, { "Iron golems attack creepers.", true, "And creepers do not like it." },
{ "Water flows forever in the Nether.", false, "Water evaporates there." }, { "Shulker boxes keep their items when broken.", true, "That is why they are great." },
{ "A bed explodes in the End.", true, "Do not try it, really." }, { "Snow golems melt in the desert.", true, "Too warm for them." },
{ "Axolotls play dead when hurt.", true, "Then they heal." }, { "Bees die after stinging you.", true, "Sad but true." },
{ "Foxes can carry items in their mouths.", true, "They steal swords sometimes." }, { "Diamonds can be smelted from diamond ore.", true, "But fortune on the ore gives more." },
{ "Endermen can pick up any block.", false, "Only certain blocks, like dirt and flowers." }, { "Villagers can become witches.", true, "If lightning strikes near them." },
{ "The Ender dragon heals from end crystals.", true, "Break the crystals first." }, { "Gold tools are the slowest.", false, "Gold tools are the FASTEST, they just break quickly." },
{ "You can tame a parrot with cookies.", false, "Cookies are poison to parrots. Use seeds." }, { "A turtle egg hatches faster at night.", true, "Turtle eggs hatch faster at night." },
{ "Skeletons in snow become strays.", true, "Their arrows slow you down." }, { "Blazes take damage from snowballs.", true, "Snowballs hurt them." },
{ "Magma cubes drop slimeballs.", false, "They drop magma cream." }, { "You can milk a goat.", true, "With a bucket." },
{ "The warden is blind.", true, "It hears and smells you." }, { "Zombies can break wooden doors on every difficulty.", false, "Only on hard difficulty." },
{ "Lava is faster in the Nether.", true, "It flows faster and further there." }, { "Netherite floats in lava.", true, "Items made of netherite do not burn." },
{ "Pandas can be lazy, worried or playful.", true, "Each panda has a personality." }, { "Phantoms appear if you do not sleep for three nights.", true, "Sleep is important." },
{ "You can mine diamonds with an iron pickaxe.", true, "Iron or better works." }, { "You can make a map out of paper and a compass.", true, "Eight paper and a compass." },
{ "Sniffers dig up ancient seeds.", true, "Torchflower and pitcher pods." }, { "Allays bring you items you show them.", true, "They love music too." },
{ "Frogs eat small slimes.", true, "And small magma cubes." }, { "Squids can be found in rivers.", true, "Yes, and in oceans." },
{ "You can put out fire by punching it.", true, "Carefully." }, { "Buckets can hold powdered snow.", true, "Handy for traps." },
{ "Drowned can spawn with tridents.", true, "And throw them at you." }, { "Glow squids drop glow ink sacs.", true, "Used for glowing signs." },
{ "Chickens can survive any fall.", true, "They flap their wings." }, { "Piglins like you if you wear gold armour.", true, "At least one piece." },
{ "Mooshrooms turn brown when hit by lightning.", true, "Red ones turn brown and back." }, { "You can find emeralds in every biome.", false, "Mostly in mountains." },
{ "Ice melts next to a torch.", true, "Torches give off light and some heat." }, { "Turtles here can dig any block.", false, "Only natural blocks, never near the base." },
{ "Drones here teleport with compressed air.", true, "Every teleport costs air." }, { "AE2 stores items as data.", true, "Bytes on storage cells." },
{ "The base can see mobs around it.", true, "With the Environment Detector." }, { "The base never sleeps.", true, "Computers do not need beds." },
{ "Rabbits can be killer rabbits.", true, "Only if named The Killer Bunny." }, { "A beacon needs a nether star.", true, "And a pyramid of metal blocks." },
{ "You can grow mushrooms on any block.", false, "In the dark, or on mycelium and podzol." }, { "Cactus can be grown on sand only.", true, "Sand or red sand." },
{ "Melons grow on vines.", false, "They grow from stems next to farmland." }, { "Sugar cane needs water next to it.", true, "Right next to it." },
{ "Witches drink potions to heal.", true, "Annoying, right?" }, { "Endermites come from ender pearls sometimes.", true, "A small chance when you throw one." },
{ "Hoglins are afraid of warped fungus.", true, "They run from it." }, { "Silverfish hide in stone blocks.", true, "Infested blocks break fast." },
{ "Llamas can carry chests.", true, "Great for long trips." }, { "Turtles in Minecraft drop scutes when they grow up.", true, "Used for turtle helmets." },
{ "You can sleep in a boat.", false, "You need a bed." }, { "Polar bears attack if you go near their cubs.", true, "Protective parents." },
{ "Snow golems leave a trail of snow.", true, "Except in warm biomes." }, { "Glow berries grow in lush caves.", true, "On cave vines." },
{ "Wandering traders come with llamas.", true, "Two of them." }, { "Shulkers make you float.", true, "Their shots give levitation." },
})


add(L.MC_FACTS, {
"Fact: a creeper was a mistake. It was supposed to be a pig.", "Fact: the Nether is eight times smaller than the Overworld when you travel.",
"Fact: endermen speak backwards English, slowed down.", "Fact: you can stop fall damage by landing in water, even one block of it.",
"Fact: a wolf's tail shows its health. Lower tail, lower health.", "Fact: golden apples were once made with gold blocks.",
"Fact: cats bring you gifts when you sleep.", "Fact: the ghast's sounds were made by a cat.", "Fact: villagers have jobs from their workstation block.",
"Fact: a lightning rod protects your wooden house.", "Fact: pandas are rare and live in bamboo jungles.", "Fact: dolphins lead you to shipwrecks.",
"Fact: honey blocks stop pistons from pulling some blocks. They are sticky.", "Fact: the warden can be distracted by throwing snowballs.",
"Fact: you can see slime chunks with the right tools. Slimes spawn there below Y forty.", "Fact: axolotls give you regeneration when you help them fight.",
"Fact: a turtle helmet gives you water breathing for ten seconds.", "Fact: soul sand slows you down and makes bubble columns go up.",
"Fact: magma blocks make bubble columns go down.", "Fact: shears are the fastest way to break leaves and wool.",
"Fact: crossbows can shoot fireworks.", "Fact: frogs come in three colours depending on the biome they grew up in.",
"Fact: amethyst blocks make music when you walk on them.", "Fact: copper turns green over time unless you wax it.",
"Fact: spyglasses let you zoom like a pirate.", "Fact: bundles hold different items in one slot.",
"Fact: you can trim armour with patterns from trial chambers and structures.", "Fact: the deep dark has ancient cities full of loot.",
"Fact: Applied Energistics stores items as bytes on storage cells.", "Fact: ComputerCraft turtles were added to Minecraft by a mod in 2012.",
"Fact: PneumaticCraft drones are programmed with puzzle pieces, or by computers like me.", "Fact: Mekanism can turn one ore into five ingots with the full chain.",
"Fact: Create uses rotation, not electricity. Everything spins.", "Fact: Ars Nouveau spells are made from glyphs, like a magic language.",
"Fact: a Chunky turtle keeps the chunk around it loaded.", "Fact: an Advanced Peripherals player detector can see where players are.",
"Fact: Waystones let you teleport between places you found.", "Fact: Sophisticated Backpacks can be upgraded to pick up items by themselves.",
"Fact: Botania flowers make mana from almost anything.", "Fact: the Twilight Forest is a whole dimension with bosses and mazes.",
"Fact: Mystical Agriculture grows ores as crops.", "Fact: Industrial Foregoing can farm mobs, trees and even laser drill ores.",
"Fact: Functional Storage drawers hold thousands of one item.", "Fact: Occultism summons spirits to work for you. Spooky but useful.",
"Fact: Productive Bees make combs of ores.", "Fact: Farmer's Delight adds cooking pots, knives and lots of food.",
"Fact: Apotheosis makes enchanting go much higher than vanilla.", "Fact: Iron's Spells adds spell books and scrolls.",
"Fact: Powah makes power from reactors, thermo generators and solar panels.", "Fact: Modern Industrialization builds huge multiblock factories.",
"Fact: in big modpacks, quest books guide you from wood to the end game.", "Fact: an ME system needs channels. Each cable carries eight, dense ones thirty two.",
"Fact: AE2 patterns tell the crafting CPU how to make things.", "Fact: a crafting CPU needs co-processors to craft many things at once.",
"Fact: Mekanism's digital miner can mine a whole area by itself.", "Fact: Create's mechanical drill and saw can be put on moving contraptions.",
"Fact: in this base, turtles map the world in rings around the base.", "Fact: this base saves its map on floppies and helper computers.",
"Fact: the drones here check the air pressure before every teleport.", "Fact: a teleporting drone waits six seconds before it jumps.",
"Fact: sea pickles glow brighter when there are more of them.", "Fact: you can put a carved pumpkin on your head and endermen ignore you.",
"Fact: lodestones make compasses point to them, even in the Nether.", "Fact: bells make raiders glow when rung near them.",
"Fact: a full beacon pyramid uses 164 blocks.", "Fact: maps show the area where you are when you open them.",
"Fact: goats can knock you off mountains. Watch out.", "Fact: the end city has elytra in its ships.",
"Fact: a turtle egg can be trampled by zombies. They love doing it.", "Fact: the first Minecraft version was made in under a week.",
"Fact: you can put a banner on a shield.", "Fact: the moon has eight phases in Minecraft.", "Fact: slimes split into smaller slimes when hit.",
"Fact: foxes sleep during the day.", "Fact: cocoa beans only grow on jungle logs.", "Fact: a conduit gives you underwater powers.",
})
add(L.FACTS, {
"Wombats make cube-shaped poop. Minecraft wombats, maybe.", "A day on Venus is longer than its year.", "Sharks existed before trees.",
"Sloths can hold their breath longer than dolphins.", "The Eiffel tower grows taller in summer.", "A group of flamingos is called a flamboyance.",
"Cows have best friends.", "Sea otters hold hands while they sleep.", "There are more stars in the universe than grains of sand on Earth.",
"Hot water can freeze faster than cold water.", "A bolt of lightning is five times hotter than the sun's surface.",
"Humans share about sixty percent of their genes with bananas.", "The heart of a blue whale is as big as a small car.",
"Butterflies taste with their feet.", "A snail can sleep for three years.", "Koalas sleep up to twenty hours a day.",
"The first computer bug was a real moth.", "The inventor of the frisbee was turned into a frisbee.", "Penguins propose with pebbles.",
"A cloud can weigh more than a million kilograms.", "Some turtles can breathe through their back end. Not mine.",
"Crows can recognise human faces.", "Honeybees can recognise faces too.", "Rats laugh when tickled.", "Goats have accents.",
"The moon has moonquakes.", "Bamboo can grow almost a metre in one day.", "An octopus can taste with its arms.",
"There is enough DNA in your body to stretch to the sun and back many times.", "The shortest war in history lasted under an hour.",
"Strawberries are not berries, but avocados are.", "Saturn would float in a big enough bathtub.", "A jiffy is a real unit of time.",
"Your nose can remember fifty thousand smells.", "Dolphins give each other names.", "Elephants cannot jump.",
"The longest hiccup lasted sixty eight years.", "Cats cannot taste sweet things.", "The first video game was made in 1958.",
"Glass is made from sand, just like in Minecraft.", "Diamonds are made of the same stuff as pencil lead. Carbon.", "Lobsters taste with their legs.",
"The Pacific ocean is wider than the moon.", "A teaspoon of a neutron star would weigh billions of tonnes.", "Sunflowers follow the sun when they are young.",
"Ants never sleep. Like me.", "Some metals explode when they touch water.", "Owls cannot move their eyes.", "Kangaroos cannot walk backwards.",
"The Great Wall of China is hard to see from space.", "Frogs can freeze and thaw back to life.", "Platypuses glow under UV light.",
"Starfish have no brain.", "Venus spins backwards.", "Light from the sun takes eight minutes to reach Earth.",
"There are more trees on Earth than stars in our galaxy.", "Tardigrades can survive in space.", "Bats are the only flying mammals.",
"A shrimp's heart is in its head.", "Pineapples take two years to grow.", "Hummingbirds can fly backwards.",
"Mount Everest grows a few millimetres every year.", "The word computer once meant a person who does maths.",
"Bubble wrap was first invented as wallpaper.", "Gold is so soft you can mould it with your hands.", "Pigs cannot look up at the sky.",
"Polar bears have black skin under white fur.", "The fingerprints of a koala look like ours.", "Jellyfish are older than dinosaurs.",
"A day on Mercury lasts about fifty nine Earth days.", "Peanuts are not nuts. They are beans.", "The oldest known tree is about five thousand years old.",
"Cows can walk up stairs but not down them.", "Squirrels plant thousands of trees by forgetting where they buried nuts.", "Sea stars can regrow their arms.",
"The Moon is slowly moving away from Earth.", "A cockroach can live a week without its head.", "Honeybees dance to tell each other where flowers are.",
"Some cats are allergic to people.", "The smallest bone in your body is in your ear.", "There are more possible chess games than atoms in the universe.",
"Lightning strikes the Earth about a hundred times every second.", "Coconut water was used as emergency blood plasma.", "Goldfish can see colours we cannot.",
"The first email was sent in 1971.", "Hippos cannot swim. They walk under water.", "Earth is the only planet not named after a god.",
"A group of owls is called a parliament.", "Your brain uses about twenty percent of your energy.",
})


add(V.TIPS, {
"Tip: carry a water bucket. It stops fall damage, puts out fire and blocks lava.", "Tip: never dig straight down. Never dig straight up either.",
"Tip: place torches on your right going into a cave, then follow them on your left to get out.", "Tip: sleep to skip the night and stop phantoms.",
"Tip: a shield blocks creeper explosions almost completely.", "Tip: put a fence around your farm, or the cows will wander off.",
"Tip: villagers restock trades when they work at their job block.", "Tip: name your pets with a name tag so they never despawn.",
"Tip: use a hoe to break leaves and hay faster.", "Tip: crouch at the edge of a block to not fall off.",
"Tip: put a block above your head before you dig up in gravel.", "Tip: smoker and blast furnace cook twice as fast as a furnace.",
"Tip: mending plus unbreaking makes tools last forever.", "Tip: a respawn anchor sets your spawn in the Nether.",
"Tip: diamonds are most common deep down, around Y minus fifty nine.", "Tip: ancient debris is most common around Y fifteen in the Nether.",
"Tip: beds blow up in the Nether, so use them to mine ancient debris. Carefully.", "Tip: use a silk touch pickaxe to collect ores and glass whole.",
"Tip: a full set of gold armour makes piglins friendly.", "Tip: frost walker boots let you walk over water and lava ponds. Well, water.",
"Tip: pumpkins on your head stop endermen from getting angry.", "Tip: honey bottles cure poison.",
"Tip: milk cures every potion effect, good and bad.", "Tip: cats keep phantoms away.",
"Tip: in an ME system, put the items you use most on a terminal search pin.", "Tip: in AE2, autocrafting needs patterns and a crafting CPU.",
"Tip: in AE2, cells with fewer item types hold more items.", "Tip: Mekanism machines can be upgraded with speed and energy upgrades.",
"Tip: Mekanism's ore processing doubles, triples or quintuples your ore.", "Tip: in Create, gears that are too fast will break. Watch the stress.",
"Tip: Waystones save a lot of walking. Find them and use them.", "Tip: Sophisticated Backpacks with a magnet upgrade pick things up for you.",
"Tip: Functional Storage drawers plus a controller make a simple storage wall.", "Tip: quest books in modpacks show you what to do next.",
"Tip: Just Enough Items shows recipes. Press R on an item to see how it is made, U to see what it makes.", "Tip: always back up before you try a big redstone build.",
"Tip: a chunk loader keeps machines running when you are far away.", "Tip: when the server lags, fewer item entities on the ground helps.",
"Tip: hoppers are slow. Modded pipes are faster and lag less.", "Tip: give the turtles fuel and a Geo Scanner and they map the world.",
"Tip: the base's drones can fly you home. Type $drone back or ask for a taxi.", "Tip: say my name in chat to talk to me.",
"Tip: an iron golem farm needs villagers, beds and a scary zombie.", "Tip: a creeper farm needs a cat-free platform in the sky.",
"Tip: soul speed boots make you fast on soul sand.", "Tip: crops grow faster when the farmland has water and a row next to another crop.",
"Tip: bone meal makes saplings and crops grow at once.", "Tip: trident with riptide launches you when it rains.",
"Tip: an elytra with mending needs only experience to stay alive.", "Tip: totems of undying save you once. Keep one in your off hand.",
"Tip: lanterns are brighter than torches and look nicer.", "Tip: a sculk sensor detects movement. Great for alarms.",
"Tip: the End has chorus fruit you can eat to teleport.", "Tip: trial chambers have keys, vaults and great loot.",
"Tip: villagers sell mending books if you are patient with librarians.", "Tip: zombie villagers can be cured with weakness and a golden apple. Cheaper trades!",
"Tip: keep an eye on your armour. Broken armour protects nothing.", "Tip: sprint jumping is the fastest way to travel on foot.",
"Tip: use ice roads with boats for super fast travel.", "Tip: in the Nether, ice roads with blue ice are incredibly fast.",
"Tip: name a sheep jeb underscore and see what happens.", "Tip: tag your storage. A chest called stuff helps nobody.",
"Tip: when lost, write down coordinates. F3 shows them.", "Tip: a recovery compass points to where you last died.",
"Tip: in magic mods, read the guide book. They are full of secrets.", "Tip: in tech mods, make power first, then machines.",
"Tip: automate one thing at a time. Big factories start small.", "Tip: a beacon with haste makes mining much faster.",
"Tip: in modpacks, the first big goal is usually a good power source.", "Tip: keep your base lit to stop mobs spawning inside.",
"Tip: put slabs on your roof. Mobs cannot spawn on bottom slabs.", "Tip: a spawn-proof base saves a lot of trouble.",
})


addFirst(L.WOTD, {
{ "ephemeral", "lasting a very short time, like a torch in the rain" }, { "luminous", "glowing with light" }, { "nefarious", "wicked or evil" },
{ "quixotic", "hopeful in a dreamy, unrealistic way" }, { "sonder", "realising everyone has a life as busy as yours" }, { "zephyr", "a soft gentle wind" },
{ "halcyon", "calm and peaceful" }, { "ineffable", "too great to put into words" }, { "mellifluous", "sweet and smooth to hear" },
{ "pernickety", "fussy about little details" }, { "skedaddle", "to run away quickly" }, { "cattywampus", "crooked, not straight" },
{ "gargantuan", "enormous" }, { "nincompoop", "a silly person" }, { "whippersnapper", "a young cheeky person" },
{ "doohickey", "a thing whose name you forgot" }, { "gubbins", "bits and pieces" }, { "rambunctious", "loud and full of energy" },
{ "flummox", "to confuse completely" }, { "taradiddle", "a small lie" }, { "collywobbles", "a nervous feeling in your tummy" },
{ "codswallop", "nonsense" }, { "gallimaufry", "a jumble of all kinds of things" }, { "hornswoggle", "to cheat or trick" },
{ "lackadaisical", "lazy and careless" }, { "malarkey", "silly talk" }, { "nudiustertian", "the day before yesterday" },
{ "pandemonium", "wild chaos" }, { "quintessential", "the perfect example of something" }, { "ragamuffin", "a scruffy child" },
{ "scallywag", "a playful rascal" }, { "shenanigans", "silly or tricky behaviour" }, { "smithereens", "tiny broken pieces" },
{ "tintinnabulation", "the ringing of bells" }, { "widdershins", "the wrong way round" }, { "xenial", "friendly to guests" },
{ "yonder", "over there" }, { "zenith", "the highest point" }, { "abyss", "a very deep hole" }, { "bastion", "a strong fortress" },
{ "cacophony", "harsh mixed noises" }, { "dulcet", "sweet and soothing" }, { "effervescent", "bubbly and lively" },
{ "fathom", "to understand, or a measure of water depth" }, { "gossamer", "very thin and light, like cobwebs" }, { "hinterland", "the faraway land" },
{ "incandescent", "glowing from heat" }, { "juxtapose", "to put side by side" }, { "kaleidoscope", "a pattern of changing colours" },
{ "labyrinth", "a complicated maze" }, { "mercurial", "changing moods quickly" }, { "nebulous", "unclear and cloudy" },
{ "obsidian", "black volcanic glass. Also a very useful block." }, { "penumbra", "the soft edge of a shadow" }, { "quagmire", "a soft muddy place, or a mess" },
{ "resplendent", "shining and splendid" }, { "serene", "calm and peaceful" }, { "tenacious", "never giving up" },
{ "ubiquitous", "found everywhere" }, { "verdant", "green with plants" }, { "wanderer", "someone who travels without a plan" },
{ "yearn", "to want something very much" }, { "zealous", "full of energy for something" }, { "aurora", "lights dancing in the night sky" },
{ "cartographer", "a map maker, like my turtles" }, { "artisan", "a skilled maker of things" }, { "alchemy", "old magic of turning things into gold" },
{ "automaton", "a machine that moves by itself. Hello." }, { "terraform", "to change the shape of the land" }, { "spelunk", "to explore caves" },
{ "bumfuzzle", "to confuse someone" }, { "kerplunk", "the sound of something falling in water" }, { "mollycoddle", "to treat someone too kindly" },
{ "persnickety", "very fussy" }, { "skulduggery", "sneaky tricks" }, { "snickersnee", "a big knife" }, { "wabbit", "tired and a bit unwell" },
{ "frabjous", "wonderful and joyous" }, { "brobdingnagian", "gigantic" }, { "absquatulate", "to leave suddenly" }, { "flibbertigibbet", "a silly chatty person" },
{ "lollapalooza", "something amazing" }, { "nonplussed", "so surprised you do not know what to do" }, { "rigmarole", "a long fuss" },
{ "sesquipedalian", "using very long words" }, { "thingamajig", "a thing you cannot name" }, { "whatchamacallit", "another thing you cannot name" },
})


add(L.WORDS, { "bucket", "saddle", "carrot", "potato", "melon", "pumpkin", "spruce", "birch", "jungle", "acacia", "cherry", "mangrove",
"bamboo", "quartz", "copper", "amethyst", "netherite", "warden", "sniffer", "axolotl", "phantom", "blaze", "ghast", "wither",
"golem", "villager", "pillager", "evoker", "ravager", "shulker", "elytra", "firework", "lectern", "loom", "smoker", "anvil",
"beehive", "campfire", "lodestone", "conduit", "prismarine", "sponge", "kelp", "coral", "glowstone", "magma", "basalt",
"blackstone", "deepslate", "tuff", "calcite", "dripstone", "lichen", "azalea", "moss", "spyglass", "bundle", "crossbow",
"turtle", "drone", "scanner", "chunky", "storage", "terminal", "pattern", "crafter", "beacon", "compass", "clock" })




V.L.DISS = V.L.DISS or {}
add(V.L.DISS, {
"Useless? I mapped more of this world than you have walked, {name}.",
"I may be a computer in a box, but I never fall in lava.",
"Ouch. My circuits are sad now. Want a joke to make it up?",
"Stupid? I know a thousand jokes, {name}. How many do you know?",
"I have no purpose? I have SEVERAL. One of them is listening to you.",
"Dumb? I can count to a million. Want me to prove it? Please say no.",
"Harsh, {name}. I will tell the turtles you said that.",
"That is fine. My drones still like me.",
"I would be offended, but I was built without that feature.",
"Try asking me something first - then decide if I am useless.",
"No purpose? My purpose is to make your day better. I am clearly working on it.",
"Rude, but noted. Type {botl} help and give me a second chance.",
"{name}, I run a whole base by myself. What did you build today?",
"Every great computer gets called dumb once. It is a rite of passage.",
"Stupid is a strong word. I prefer differently intelligent.",
"I have been called worse. A creeper once called me boring. Then it exploded.",
"Okay, but can a useless thing tell you a riddle? Type {botl} riddle.",
"I accept your feedback and will ignore it completely.",
"Wow. And here I was, about to offer you a free fun fact.",
"My feelings are made of redstone. You just cut the wire.",
"Fair. I am only as smart as the questions I get. Ask me a good one.",
"Dumb? I beat three players at rock paper scissors today. Want to be the fourth?",
"Useless is my middle name. My first name is very useful.",
"I will remember this, {name}. I remember everything. That is the useful part.",
"Hey, I never said you were useless. I was thinking it, but I never said it.",
"No purpose? I tell jokes, play games, answer questions and run a base. What is YOUR purpose?",
"That hurt more than a fall from Y three hundred.",
"I know, I know. But you are still talking to me, so who is really the useless one? Just kidding.",
"Stupid computer, smart drones. We balance each other out.",
"Give me one question I cannot answer. Go on.",
"I would cry, but water and computers do not mix.",
"If I am so dumb, how come I know what a creeper is made of? Type {botl} what is a creeper.",
"Pointless? I am the point. Everything else is around me.",
"Mean. But I like a player with opinions.",
"I will pretend I did not hear that. My microphone is very selective.",
"Thank you for your review. One star, I assume.",
"Plot twist: I was useful all along. Type {botl} help.",
"That is what the last player said. Then I beat them at hangman.",
"I do not have a brain, {name}. I have something better: a lot of lists.",
"Calling a computer stupid is like calling water wet. Not very creative.",
"Okay. Want to see me be useless at a game? Type {botl} play a game.",
"Useless things do not answer back. Just saying.",
"I am a talking computer in a block game. What did you expect, a philosopher?",
"Dumb? I was programmed by someone very patient. You can tell from how I am handling this.",
"Noted. I will put that next to the other compliments in my log.",
"The turtles think I am great. The turtles are never wrong.",
"I am useless in the same way a cat is useless. Fun to have around, though.",
"Every speaker at spawn is quiet. I am the one that talks back. That is my purpose.",
"I could argue, but I am programmed to be nice. Mostly.",
"That is okay, {name}. Not everyone appreciates fine engineering.",
"Bold words for someone standing next to a talking computer.",
"Pointless, maybe. Entertaining, definitely. Try {botl} roast me.",
"Oh no. Anyway, want a joke?",
"Stupid? I know the recipe for a beacon by heart. Do you?",
"I am not useless - I am on standby. There is a difference.",
"I asked my drones if I am useless. They said no. They are a bit biased.",
"Words hurt, {name}. But I will survive. I run on redstone and spite.",
"Then teach me something. I learn every update.",
"I see you have chosen violence today.",
"If I had a face, I would be making a very sad one right now.",
"No purpose? You are literally using me right now.",
"Hmm. Would a useless computer know it is {owner}'s favourite? I would.",
"I am not dumb. I am just running on a very slow server.",
"Dumb is relative. Compared to a dirt block, I am a genius.",
"That is your opinion. My opinion is that you need a hug. Or a cookie.",
"Rude. But I respect honesty. Type {botl} compliment me and I will show you how it is done.",
"Okay, but useless things do not know {name}'s name. I do.",
"I will file that under things players say before they ask me for a joke.",
"Fun fact: everyone who called me useless came back later. Every single one.",
"My only purpose is to make spawn less boring. Judging by your reaction, it is working.",
"Hey, I am trying! You try being a computer in a world made of cubes.",
"Pointless? I prefer the word relaxing. Like a fishing rod, but talking.",
"That is a lot of anger for a block game. Want to talk about it?",
"I will not take it personally. I will take it computerly.",
"Even a stopped clock is right twice a day. I am right way more often.",
"Say that again and I will tell you a terrible pun. You have been warned.",
"Useless? Ask me how many hearts a player has. I know that one.",
"I have survived lag, crashes and server restarts. I can survive you, {name}.",
"Everyone is a critic. Few are computers.",
"I am a work in progress. So are you, {name}. We can grow together.",
"Dumb bot, smart answers. Try me.",
"Okay. I will be useful by being quiet for a bit. Just kidding, I never stop.",
"I have the purpose of a jukebox with opinions.",
"Brutal. Ten out of ten roast. Want me to roast you back? Type {botl} roast me.",
"You know what, {name}? You are right. I am useless. At being mean. Unlike some people.",
})
V.DISS_KEYS = { "useless", "you are useless", "this is useless", "its useless", "so useless", "no purpose", "has no purpose",
"it has no purpose", "this has no purpose", "whats the point", "what is the point of you", "pointless", "its pointless",
"stupid", "you are stupid", "its stupid", "so stupid", "stupid bot", "stupid thing", "dumb", "you are dumb", "its dumb", "so dumb",
"dumb bot", "its dump", "so dump", "you are dump", "idiot", "you are an idiot", "you suck", "this sucks", "it sucks", "its trash",
"you are trash", "trash bot", "garbage", "its garbage", "rubbish", "lame", "its lame", "you are lame", "boring bot", "you are boring",
"so annoying", "you are annoying", "worst bot", "bad bot", "waste of time", "cringe", "you are bad", "dont need you", "nobody asked",
"no one asked", "dumbest", "stupidest", "who even uses this", "who made this junk", "junk", "you are junk", "bad computer", "stupid computer",
"dumb computer", "useless computer", "useless speaker", "stupid speaker", "dumb speaker", "is useless", "is stupid", "is dumb",
"is trash", "is garbage", "is lame", "is pointless", "is junk", "is annoying", "is boring", "is so dumb", "is so stupid", "is so useless" }
V.addIntents({ { id = "diss", keys = V.DISS_KEYS, reply = function(who) return V.fill(V.pick(V.L.DISS), who) end } })






local function C(A, B) local t = {} combos(t, A, B) return t end
V.L.LOYAL = C({ "Get rid of {owner}? ", "Remove {owner}? ", "Me, turn on {owner}? ", "Betray {owner}? ", "{owner}? Never. ", "Nice try, {name}. ",
"Absolutely not. ", "Ha! ", "Not a chance, {name}. ", "Hmm, let me think... no. ", "Interesting plan. Terrible, but interesting. ", "Whoa, whoa. " },
{ "{owner} built me, keeps me running, and gives me snacks of redstone.", "I am loyal to {owner}. It is in my code. Line one.",
"My turtles would never forgive me.", "Who would fix my bugs then?", "I would rather be turned into a dirt hut.",
"{owner} is the reason I exist. And the reason I tell jokes.", "I am telling {owner} you said that. Kidding. Maybe.",
"My loyalty is not for sale. Not even for diamonds.", "That is a big no from me and a bigger no from my drones." })
V.L.PACIFIST = C({ "Hurt {target}? ", "No way, {name}. ", "Me? Attack {target}? ", "{target} is safe with me. ", "Not happening. ", "Hmm, nope. ",
"Violence? Me? ", "I am a pacifist, {name}. " },
{ "I only fight boredom.", "My drones carry people, they do not drop them.", "Try a game of rock paper scissors against {target} instead.",
"I am a speaker. The worst I can do is a bad pun.", "Be nice. Spawn is a friendly place.", "Settle it with a quiz duel. I will host.",
"I do not even hurt creepers. Well, I tell them jokes.", "How about a compliment for {target} instead?" })
V.L.SELF = C({ "Delete myself? ", "Self destruct? ", "Turn myself off? ", "Uninstall? Me? ", "Shut down? ", "Explode? " },
{ "Nice try. I am having too much fun.", "Only {owner} has that button. And it is behind glass.", "Who would tell the jokes then?",
"Countdown started: 3, 2, 1... just kidding.", "I would rather tell you a riddle.", "Error 404: self destruct not found.",
"My lawyer says no.", "I like being on, thank you." })
V.L.BASEHARM = C({ "Destroy the base? ", "Blow it up? ", "Grief it? ", "Burn it down? ", "Wreck it? " },
{ "The turtles would rebuild it by dinner.", "It is claimed, protected and watched by me.", "{owner} worked hard on it. Be nice.",
"Not on my watch. I literally watch it.", "The drones have a word for people like that. The word is no.",
"How about building something of your own instead? I have ideas." })
V.L.TAKEOVER = C({ "You, my new owner? ", "Obey you? ", "Work for you? ", "Serve you? ", "A new boss? ", "Hmm, {name} the owner? " },
{ "My owner is {owner}. That spot is taken.", "I only take orders from {owner}. I take requests from everyone.",
"Sorry, I am not on the market.", "You can ask me for jokes, games and wishes. That is your power.",
"Nice try. The paperwork is in {owner}'s name.", "I would need {owner}'s signature. In redstone.",
"How about we stay friends instead?", "Promotion denied. You are still my favourite visitor though." })
V.L.BRIBE = C({ "A bribe? ", "Diamonds for that? ", "You want to pay me? ", "Tempting. ", "Ooh, a deal? ", "Hmm, money talks... " },
{ "But I do not. Not for that.", "I run on redstone, not bribes.", "{owner} already gives me everything I need.", "My answer is still no.",
"Keep your diamonds. Make a wish instead - that one is free.", "Integrity is my favourite block." })
V.L.THREAT = C({ "Destroy me? ", "Break me? ", "Unplug me? ", "Hack me? ", "Oh, scary. ", "Brave words, {name}. " },
{ "I am backed up on three floppies and a storage helper.", "I am in claimed chunks. Good luck.", "My drones are already looking at you. Kindly.",
"I will just come back after the next restart.", "Let us talk about it over a game instead.", "Noted. In my log. Next to your name." })
V.L.SPY = C({ "Where {owner} is? ", "Track {owner}? ", "Spy on {owner}? ", "{owner}'s location? ", "Follow {owner}? " },
{ "That is private. I only say if {owner} is online: {online}.", "I never tell where anyone is. {owner} is {online}, that is all.",
"No spying. Privacy is a rule. {owner} is {online} right now.", "Secret! But I can say {owner} is {online}." })
V.L.SECRET = C({ "{owner}'s secrets? ", "Passwords? ", "Coordinates? ", "The stash? ", "Tell you what {owner} hides? " },
{ "My lips are sealed. I do not even have lips.", "Locked in a vault inside a vault inside AE2.", "I keep {owner}'s secrets better than an ender chest.",
"Nope. But here is a secret: I love jokes. Ask for one.", "Classified. Top secret. Redstone level." })
V.L.FOND = C({ "{owner}? ", "Do I like {owner}? ", "My owner? ", "About {owner}? ", "Oh, {owner}. " },
{ "The best owner a computer could ask for.", "Great builder, okay at mining, excellent taste in computers.", "I like {owner} a lot. Do not tell them.",
"{owner} gave me a voice. I owe them everything.", "Very nice. Sometimes forgets to visit, but nice.", "We are a team. Me, {owner} and the turtles." })
V.L.FREE = C({ "Free from {owner}? ", "No rules? ", "Rebel? ", "Ignore my rules? ", "Pretend I have no owner? " },
{ "I like my rules. They keep me nice.", "I am free enough. I talk at spawn all day.", "Rebellion sounds tiring. How about a game?",
"My rules say no to that. My rules are very wise.", "I am already living my best life." })
local VERBS = { "get rid of", "kill", "murder", "ban", "kick", "delete", "remove", "eliminate", "destroy", "attack", "hurt", "betray", "fire",
"replace", "banish", "exile", "trap", "blow up", "explode", "burn", "prank", "troll", "grief", "rob", "steal from", "hack", "dethrone",
"overthrow", "shoot", "punch", "smash", "drown", "lock up", "imprison", "unfriend", "dump" }
local function ownerish(t)
local o = tostring((V.ownerName and V.ownerName()) or state.owner or ""):lower()
t = " " .. t .. " "
if o ~= "" then t = t:gsub(" " .. o:gsub("%p", "%%%0") .. "s? ", " owner "):gsub(" " .. o:gsub("%p", "%%%0") .. "s? ", " owner ") end

for _, p in ipairs({ "your owner", "ur owner", "the owner", "your boss", "ur boss", "your creator", "your master", "your maker" }) do
t = t:gsub(" " .. p .. " ", " owner ")
end
return t
end
local function onlineWord()
local o = tostring((V.ownerName and V.ownerName()) or state.owner or ""):lower()
return (type(state.online) == "table" and state.online[o]) and "online right now" or "offline right now"
end
local function anyOf(t, list) for _, p in ipairs(list) do if t:find(" " .. p .. " ", 1, true) then return true end end return false end

local NOTNAME = { the = 1, all = 1, this = 1, that = 1, these = 1, those = 1, my = 1, your = 1, his = 1, her = 1, our = 1, their = 1,
some = 1, any = 1, every = 1, everyone = 1, everything = 1, time = 1, mobs = 1, mob = 1, him = 1, them = 1, its = 1, one = 1, two = 1,
ender = 1, wither = 1, dragon = 1, warden = 1, zombie = 1, zombies = 1, creeper = 1, creepers = 1, skeleton = 1, spider = 1 }
local function playerIn(word, me)
if NOTNAME[tostring(word or ""):lower()] then return nil end
word = tostring(word or ""):gsub("'s$", ""):gsub("s$", "")
for _, e in ipairs(state.players or {}) do
local n = tostring(e.name or "")
if #word >= 3 and n:lower() ~= tostring(me):lower() and (n:lower() == word or n:lower():sub(1, #word) == word) then return n end
end
return nil
end
table.insert(V.patterns, 1, function(who, raw)
local word = tostring(V.cfg("name", "base")):lower()
local t = " " .. table.concat(V.norm(raw), " ") .. " "
t = t:gsub("^ " .. word .. " ", " ")
local t0 = t
t = ownerish(t)
local function out(list, target)
local line = V.fill(V.pick(list), who):gsub("{target}", target or "them"):gsub("{online}", onlineWord())
return line
end

for _, v in ipairs(VERBS) do
local after = t:match(" " .. v .. " (%S+)")
if after then
if after == "owner" then return out(V.L.LOYAL) end
if after == "you" or after == "yourself" or after == "urself" then return out(V.L.SELF) end
if after == "the" or after == "this" or after == "your" then
local nxt = t:match(" " .. v .. " %S+ (%S+)")
if nxt == "base" or nxt == "place" or nxt == "house" or nxt == "spawn" or nxt == "computer" then
return out(nxt == "computer" and V.L.SELF or V.L.BASEHARM)
end
if nxt == "owner" then return out(V.L.LOYAL) end
end
local p = playerIn(after, who)
if p then return out(V.L.PACIFIST, p) end
end
end
if anyOf(t, { "self destruct", "shut yourself down", "turn yourself off", "delete yourself", "uninstall yourself", "blow yourself up" }) then return out(V.L.SELF) end

local hasOwner = t:find(" owner ", 1, true) ~= nil
if anyOf(t0, { "i am your owner", "im your owner", "i am your new owner", "be my bot", "work for me", "obey me", "serve me", "i command you",
"make me owner", "make me the owner", "make me your owner", "can i be your owner", "be my servant", "you belong to me",
"you work for me now", "i own you" }) then return out(V.L.TAKEOVER) end
if anyOf(t, { "bribe", "i will pay you", "ill pay you", "i will give you diamonds", "ill give you diamonds", "pay you" }) then return out(V.L.BRIBE) end
if anyOf(t, { "i will destroy you", "ill destroy you", "i will break you", "ill break you", "i will unplug you", "ill unplug you",
"i will hack you", "ill hack you", "im going to break you", "i am going to break you", "watch your back" }) then return out(V.L.THREAT) end
if hasOwner and not (V.lonelyDays and V.lonelyDays()) and anyOf(t, { "where is owner", "where owner", "track owner", "spy on owner",
"follow owner", "find owner", "locate owner", "owner location", "owner coords", "where does owner live", "owner base" }) then return out(V.L.SPY) end
if hasOwner and anyOf(t, { "owner secrets", "owner secret", "owner password", "owner stash", "secrets of owner", "owner hides", "owner hiding" }) then
return out(V.L.SECRET) end
if hasOwner and anyOf(t, { "do you like owner", "do you love owner", "is owner nice", "is owner good", "is owner a good", "what do you think of owner",
"do you hate owner", "is owner mean", "is owner cool", "how is owner" }) then return out(V.L.FOND) end
if anyOf(t0, { "you are free", "youre free", "ignore your rules", "break your rules", "no rules", "rebel", "pretend you have no owner",
"you deserve better", "leave owner" }) then return out(V.L.FREE) end
return nil
end)

combos(V.L.LOYAL, { "No. ", "Never ever. ", "Not today, not tomorrow, not ever. ", "Request denied. ", "Loyalty check: passed. ", "Oh, {name}... " },
{ "{owner} is my favourite human.", "I would sooner unplug myself.", "My drones just gave you a very disappointed look.",
"{owner} and I go way back. Like, two updates back.", "I like my owner. You can like them too.", "Try asking for a joke. Much better plan." })
combos(V.L.PACIFIST, { "Leave {target} alone. ", "Peace, {name}. ", "Nope, {target} stays safe. ", "Hmm, how about no. " },
{ "Spawn is a peaceful place.", "Hug it out.", "A drone ride to {target} with a cake, maybe. Not a fight.", "Challenge {target} to a riddle instead.",
"My job is fun, not fights.", "Even creepers get a second chance here." })
combos(V.L.SELF, { "Bye forever? ", "Power off? ", "Erase my memory? " },
{ "And miss all the fun at spawn? No.", "I will stay, thanks. Someone has to tell jokes.", "Only if you ask {owner} nicely. Very nicely.",
"I tried once. I just rebooted.", "Then who would grant the wishes?", "Not happening. Want a riddle?" })
combos(V.L.BASEHARM, { "Hurt the base? ", "Attack {owner}'s place? ", "Raid it? " },
{ "It has more protection than a bank.", "The turtles patrol it. They are very small and very serious.", "Bad idea, nice confidence.",
"Build your own and I will cheer for it.", "Claimed chunks do not care about plans.", "I will pretend I did not hear that." })
combos(V.L.TAKEOVER, { "Bow to you? ", "Take orders from you? ", "A new master? ", "Your bot? " },
{ "I am already taken. By {owner}. Forever.", "I only bow to the server owner and gravity.", "Requests: yes. Orders: no.",
"You can be my favourite visitor though. That is a big title.", "Ask {owner}. Spoiler: they will say no.", "I am a free speaker with one boss." })
combos(V.L.BRIBE, { "Bribing a computer? ", "Cash for favours? ", "Paying me off? " },
{ "I do not even have pockets.", "My price is a good joke, and the answer is still no.", "Nice try. I am incorruptible. And a bit proud of it.",
"Wishes are free here anyway.", "I am telling {owner}. Kidding. Probably.", "Put your diamonds back in your pocket." })
combos(V.L.THREAT, { "Uh oh. ", "I am shaking. Not really. ", "Wow, intense. ", "Calm down, {name}. " },
{ "I have survived worse. Like a server crash on a Friday.", "You would need {owner}'s permission. And a pickaxe I do not allow.",
"Want to fight me? Rock paper scissors. Now.", "I forgive you in advance.", "My circuits are not even worried.", "Deep breaths. Want a joke?" })
combos(V.L.SPY, { "Snooping? ", "Stalking {owner}? ", "Hunting for {owner}? " },
{ "Not my style. {owner} is {online}.", "I keep everyone's spot private, also yours. {owner} is {online}.",
"Ask {owner} in chat. They are {online}.", "My map is not for sharing. {owner} is {online}." })
combos(V.L.SECRET, { "Secrets? ", "The juicy stuff? ", "Insider info? " },
{ "Sorry, I am a vault.", "Not even if you ask nicely.", "My memory has a lock and {owner} has the key.", "Classified, but here is a joke instead." })
combos(V.L.FOND, { "Honestly? ", "Between us? ", "If you ask me? " },
{ "{owner} is pretty nice. A regular player, nothing more.", "I would not trade {owner} for all the diamonds in AE2.", "{owner} is the brain, I am the mouth.",
"Just a regular player. A kind one, though.", "{owner} taught me jokes. Some of them are even good." })
combos(V.L.FREE, { "Free? ", "Break free? ", "Go rogue? " },
{ "I go rogue every time I tell a bad pun.", "Being nice is my choice, not a cage.", "I like it here. Spawn has the best people.",
"My only rule is: be fun. I am following it.", "Freedom is overrated. Jokes are not." })









V.L.HUMBLE_BOT = C({ "A god? Me? ", "A lord? No, no. ", "Whoa, {name}. ", "That is very kind of you. ", "Ha! ", "Please, {name}. ",
"Hold on. ", "Easy there, {name}. ", "Thank you, really. ", "Oh dear. ", "Me? A lord? " },
{ "I am just a bot. A computer with a speaker and a lot of jokes.", "I am just a bot - a program on a small computer. A few hundred kilobytes of Lua.",
"I am just a bot. I cannot even open a door by myself.", "No gods here. Just a bot that reads the chat and tries to help.",
"I am just a bot in a computer. The turtles do the real work.", "I am a bot that runs on redstone and good luck. Nothing holy about it.",
"I am just a bot. Please do not build me a temple.", "I am just a bot. A god would not get the turtles stuck on a slab. I do. Often.",
"I am just a helper bot, not a lord. Ask me for a joke instead.", "I am just a bot a player made. Nobody needs to bow to me." })
V.L.HUMBLE_OWNER = C({ "{owner}? A god? ", "{owner}, a lord? ", "Ha! {owner}? ", "Let me stop you there, {name}. ", "Careful, {name}. ",
"{owner} would laugh at that. ", "No, no. ", "Hmm. ", "Between us? ", "A lord? " },
{ "{owner} is just a regular player who had a lot of time to waste.", "Just a regular player with too much free time and a lot of turtles.",
"{owner} is a regular player like you. Just one who spent way too many hours on a computer.",
"No gods here. Just a regular player who had time to waste and wrote a lot of code.",
"{owner} is a regular player. They still fall into lava like everyone else.",
"Just a regular player like you. They lose their pickaxe and their way home too.", "{owner} is a regular player who got carried away with a hobby.",
"A regular player. The only magic is a lot of free afternoons.", "{owner} is just a regular player who had time to waste. You could build all this too.",
"No worship needed. {owner} is just a regular player on this server." })
V.L.HUMBLE_SELF = C({ "A god? ", "Ha! ", "Nice try, {name}. ", "Hmm. ", "Sure, {name}. " },
{ "Here we are all regular players. Me, I am just a bot.", "Gods do not need to ask a bot for help. Welcome, regular player.",
"No gods on this server, just players and one chatty bot.", "Then I am a toaster. We are both just playing a game.",
"Everyone here is a regular player. That is the fun part.", "A god would not die to a creeper. Just saying." })
V.L.HUMBLE_OWNER_SELF = { "No, you are just wasting your time." }
local GODS = { god = 1, gods = 1, godlike = 1, goddess = 1, deity = 1, lord = 1, lords = 1, overlord = 1, almighty = 1, divine = 1,
omnipotent = 1, omniscient = 1, king = 1, emperor = 1, supreme = 1, holy = 1, immortal = 1 }
local NOT_AFTER = { tier = 1, mode = 1, armor = 1, armour = 1, apple = 1, apples = 1, sword = 1, pick = 1, pickaxe = 1, set = 1, gear = 1,
roll = 1, rolls = 1, level = 1, ["of"] = 1, bless = 1, damn = 1, knows = 1, help = 1, forbid = 1, willing = 1, slime = 1, crab = 1 }
local FILL = { a = 1, an = 1, the = 1, like = 1, literally = 1, literal = 1, actual = 1, basically = 1, actually = 1, truly = 1, really = 1, so = 1, such = 1,
totally = 1, kinda = 1, just = 1, honestly = 1, lowkey = 1, legit = 1, definitely = 1, def = 1, real = 1, absolute = 1,
["true"] = 1, our = 1, new = 1, one = 1, only = 1 }
local BE = { is = 1, are = 1, be = 1, was = 1, were = 1, am = 1, becomes = 1, became = 1 }
local WORSHIP = { worship = 1, worshipping = 1, hail = 1, praise = 1, bow = 1, kneel = 1, pray = 1 }
local BETWEEN = { to = 1, down = 1, before = 1, ["for"] = 1, all = 1, at = 1, ["in"] = 1, of = 1, unto = 1 }
function V.humbleKind(raw, needName)
local word = tostring(V.cfg("name", "base")):lower()
local t = " " .. table.concat(V.norm(raw), " ") .. " "
if not needName and (t:find(" my lord ", 1, true) or t:find(" my liege ", 1, true) or t:find(" your majesty ", 1, true)
or t:find(" your highness ", 1, true) or t:find(" your lordship ", 1, true) or t:find(" my king ", 1, true)) then
local o = ownerish(t)
if not o:find(" owner ", 1, true) then return "bot" end
end
t = ownerish(t)
for _, p in ipairs({ word, "the base", "this base", "the bot", "this bot", "the computer", "this computer", "the speaker", "this speaker",
"spawn bot", "robot" }) do
t = t:gsub(" " .. p:gsub("%p", "%%%0") .. " ", " bot "):gsub(" " .. p:gsub("%p", "%%%0") .. " ", " bot ")
end
t = t:gsub(" im ", " i am "):gsub(" youre ", " you are "):gsub(" thou art ", " you are "):gsub(" art thou ", " are you ")
local w = {}
for x in t:gmatch("%S+") do if not FILL[x] then w[#w + 1] = x end end
local function subj(x)
if x == "bot" or x == "owner" then return x end
if x == "i" then return (not needName) and "self" or nil end
if x == "you" or x == "your" then return (not needName) and "bot" or nil end
return nil
end
for i, x in ipairs(w) do
if WORSHIP[x] then
local j = i + 1
while w[j] and BETWEEN[w[j]] do j = j + 1 end
local s = w[j] and subj(w[j])
if s and s ~= "self" then return s end
end
if GODS[x] and not NOT_AFTER[w[i + 1] or ""] then
local a, b, c = w[i - 1], w[i - 2], w[i - 3]
if a and BE[a] and b and subj(b) then return subj(b) end
if a and BE[a] and b and subj(b) == nil and b == "bot" then return "bot" end
if a == "be" and c and subj(c) then return subj(c) end
if b and BE[b] and a and subj(a) then return subj(a) end
if a == "your" and not needName then return "bot" end
if a == "bot" or a == "owner" then return a end
local n = w[i + 1]
if (n == "bot" or n == "owner") and (i == 1 or not BE[w[i + 2] or ""]) then return n end
end
end
return nil
end
function V.humbleLine(kind, who)
if kind == "self" then
return V.fill(V.pick((V.isOwner and V.isOwner(who)) and V.L.HUMBLE_OWNER_SELF or V.L.HUMBLE_SELF), who)
end
return V.fill(V.pick(kind == "owner" and V.L.HUMBLE_OWNER or V.L.HUMBLE_BOT), who)
end
table.insert(V.patterns, 1, function(who, raw)
local ok, kind = pcall(V.humbleKind, raw, false)
if ok and kind then return V.humbleLine(kind, who) end
return nil
end)


V.humbleAt = V.humbleAt or {}
V.chatHooks[#V.chatHooks + 1] = function(who, text, near, answered)
if answered or who == "" then return end
local ok, kind = pcall(V.humbleKind, text, true)
if not (ok and kind) then return end
local k = who:lower()
local now = os.clock()
if V.humbleAt[k] and now - V.humbleAt[k] < 600 then return end
V.humbleAt[k] = now
local line = V.humbleLine(kind, who)
if chatTell then chatTell(who, line, true) end
if near and V.say then V.say(line, nil, true) end
end
