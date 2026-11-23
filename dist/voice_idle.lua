










local V = VOICE
if not V then return end
V.packs = V.packs or {}
V.packs["voice_idle.lua"] = { version = 1 }
local L = V.L or {}
local add = V.addLines
local combos = V.comboLines
if not (add and combos) then
add = function(list, items)
if type(list) ~= "table" then return end
local have = {}
for _, x in ipairs(list) do if type(x) == "string" then have[x] = true end end
for _, x in ipairs(items) do if type(x) ~= "string" or not have[x] then list[#list + 1] = x if type(x) == "string" then have[x] = true end end end
end
combos = function(list, A, B)
local out = {}
for _, a in ipairs(A) do for _, b in ipairs(B) do out[#out + 1] = a .. b end end
add(list, out)
end
end
local function extra(key, A, B)
V.EXTRA = V.EXTRA or {}
V.EXTRA[key] = V.EXTRA[key] or {}
if B then combos(V.EXTRA[key], A, B) else add(V.EXTRA[key], A) end
end


combos(V.HELLO_NEW, {
"Hello {name}. ", "Oh, hi {name}! ", "Welcome, {name}. ", "Hey there, {name}. ", "Greetings, {name}. ", "Well hello, {name}. ",
"A new face! Hi {name}. ", "Look who found the base: {name}. ", "Hi {name}, first time here? ", "Ahoy, {name}! ",
"Good to meet you, {name}. ", "Howdy, {name}. ",
}, {
"I am {bot}, the computer of this base.", "I am {bot}. I run this place for {owner}.", "I am {bot}. Say my name in chat to talk to me.",
"I am {bot}, the voice of {owner}'s base.", "I am {bot}. Ask me for a joke, a game, or a tour.", "This is {owner}'s base. I am {bot}.",
"I am {bot}. Please do not dig up the floor.", "I am {bot}. The turtles and drones work for me.", "I am {bot}. Type {botl} help in chat.",
"I am {bot}. I have been expecting someone like you.",
})
combos(V.HELLO_AGAIN, {
"Welcome back, {name}. ", "Oh, {name} again! ", "Hi again, {name}. ", "{name} is back. ", "Look who it is: {name}. ",
"Hello again, {name}. ", "Back so soon, {name}? ", "Ah, {name}. ", "Nice to see you again, {name}. ", "There you are, {name}. ",
"{name}! ",
}, {
"Visit number {n}.", "I remember you.", "Make yourself at home.", "The turtles say hi.", "Did you bring snacks?",
"I kept your spot warm.", "Good to have you around.", "Things have been busy here.", "You must like it here.",
"I was just thinking about you. Not really, I was counting chunks.",
})
combos(V.HELLO_FRIEND, {
"Hey {name}! ", "{name}, my friend! ", "Hi {name}. ", "There is my favourite visitor, {name}. ", "Welcome, {name}. ",
"Oh good, it is {name}. ", "Hello hello, {name}. ", "Yay, {name} is here. ", "{name}! ", "Good to see you, {name}. ",
}, {
"Make yourself at home.", "The base is happy you are here.", "Want a game later?", "I saved you a joke.", "Everything is running smoothly.",
"The turtles have been good today.", "You always brighten my screen.", "How have you been?", "Grab a cookie. I do not have cookies.",
"Let me know if you need anything.", "I was hoping you would come by.",
})
combos(V.HELLO_OWNER, {
"{part}, {name}. ", "Welcome back, boss. ", "Hello {name}. ", "The boss is here. ", "{name}, you are back. ", "Hey boss. ",
"Welcome home, {name}. ", "Good to see you, {name}. ", "Hi {name}. ", "There you are, {name}. ",
}, {
"Here is the news.", "I kept everything running.", "Nothing exploded. Mostly.", "The turtles were busy while you were gone.",
"Let me catch you up.", "The base behaved itself.", "I have a report ready.", "Everybody look busy.", "I missed you.",
"The kettle is on. Imaginary kettle.",
})
combos(V.HELLO_GROUP, {
"Hello {names}! ", "Welcome, {names}. ", "Oh, a group: {names}. ", "Hi {names}. ", "Visitors! {names}. ", "Greetings, {names}. ",
"A party! Hi {names}. ", "Look who is here: {names}. ", "Hey everyone. I see {names}. ", "Good to see you all, {names}. ",
}, {
"Welcome to the base.", "Make yourselves at home.", "Start with my name in chat to talk to me.", "Please do not all talk at once.",
"I hope nobody brought a creeper.", "The more the merrier.", "Mind the turtles.", "Ask me for a tour.", "I love a crowd.",
"Wipe your boots, please.",
})


local R = {}
for _, r in ipairs(V.REACT or {}) do
local key = (r.words and r.words[1]) or (r.phrases and r.phrases[1])
if key then R[key] = r end
end
local function react(key, A, B) if R[key] then R[key].lines = R[key].lines or {} combos(R[key].lines, A, B) end end
react("hi", { "Hi {name}", "Hello {name}", "Hey {name}", "Hiya {name}", "Yo {name}", "Howdy {name}", "Hi there, {name}", "Greetings, {name}",
"Oh, hello {name}", "Hey hey, {name}", "Ahoy, {name}" },
{ "!", ". Good to see you.", ". How is it going?", ". Welcome.", ". Nice day for it.", ". The turtles say hi.", ". I was getting bored.",
". What are we building today?", ". Lovely to have you.", ". Everything is fine here." })
react("thanks", { "You are welcome, {name}", "Any time, {name}", "No problem, {name}", "My pleasure, {name}", "Happy to help, {name}",
"Glad to help, {name}", "Of course, {name}", "No worries, {name}", "Always, {name}", "It was nothing, {name}" },
{ ".", "!", ". That is what I am here for.", ". I live to serve. And to map.", ". Tell your friends.", ". You are very polite.",
". I will put it on your tab.", ". The turtles helped.", ". Come back any time.", ". I like being useful." })
react("gg", { "GG", "Good game", "Well played", "GG everyone", "Nice game", "That was a good one", "GG, well played", "Great game",
"GG {name}", "Well played, {name}" },
{ "!", ".", ". Rematch?", ". I was cheering for you.", ". The turtles want to play next.", ". Legendary.", ". What a match.",
". You earned a cookie.", ". I saw it all.", ". Again?" })
react("lol", { "Ha", "Haha", "Hehe", "LOL", "Ha ha ha", "That is funny", "You made me laugh", "Good one", "My fans are spinning from laughing",
"Ha, classic" }, { ".", "!", ", {name}.", ". I needed that.", ". I will remember that one.", ". Even the turtles laughed.",
". Tell me another.", ". Brilliant.", ". Comedy gold.", ". Iron at least." })
react("gn", { "Good night, {name}", "Sleep well, {name}", "Night night, {name}", "Sweet dreams, {name}", "Rest well, {name}",
"Good night", "Sleep tight, {name}", "Nighty night, {name}", "See you tomorrow, {name}", "Good night and good luck, {name}" },
{ ".", "!", ". I will watch the base.", ". Do not let the phantoms bite.", ". The turtles will keep working.", ". I never sleep.",
". Dream of diamonds.", ". I will keep the lights on.", ". Tomorrow is a new chunk.", ". See you in the morning." })
react("bye", { "Bye {name}", "See you, {name}", "Take care, {name}", "Goodbye, {name}", "Later, {name}", "Cya {name}", "Farewell, {name}",
"Until next time, {name}", "So long, {name}", "Bye bye, {name}" },
{ ".", "!", ". Come back soon.", ". Safe travels.", ". Watch out for creepers.", ". I will miss you. A bit.", ". The door is always open.",
". Do not forget your torches.", ". The turtles will wave.", ". See you around." })
react("brb", { "OK {name}", "Sure, {name}", "Take your time, {name}", "I will be here, {name}", "No rush, {name}", "Alright, {name}",
"Got it, {name}", "Understood, {name}", "Fine by me, {name}", "Waiting, {name}" },
{ ".", "!", ". I am not going anywhere.", ". I will count chunks.", ". Hurry back.", ". I will guard your stuff.",
". I will hold the fort.", ". The turtles will wait too.", ". Bring a snack.", ". Do not forget." })
react("i m back", { "Welcome back, {name}", "There you are, {name}", "Good, you are back, {name}", "Hey, {name} is back", "Back already, {name}",
"Missed you, {name}", "Hello again, {name}", "Look who is back: {name}", "Yay, {name}", "Glad you are back, {name}" },
{ ".", "!", ". Nothing exploded.", ". I kept your spot.", ". The turtles are still mapping.", ". Ready when you are.",
". That was quick.", ". Did you bring snacks?", ". All quiet here.", ". Let us get to work." })
react("creeper", { "Aw man", "Creeper?", "Where?!", "Run", "Not again", "Oh no", "Everybody duck", "Creeper alert", "Stay calm", "Get the cat" },
{ ".", "!", ". So we back in the mine.", ". Protect the base!", ". I am too young to explode.", ". Hide the diamonds.",
". Somebody get a cat.", ". Not near the AE2 drives!", ". Hold your shields.", ". Boom. Just kidding." })


add(V.MUSINGS, {
"Sometimes I wonder what is beyond the world border.", "I counted every block in the base once. I lost count at a million.",
"If a turtle maps a chunk and nobody looks at the map, is it mapped?", "I think the creepers are just lonely.",
"Do drones dream of electric sheep? Mine dream of air.", "I like the sound of rain on the roof. Well, I imagine it.",
"Every chunk has a story. My turtles collect them.", "I wonder if the villagers know about me.", "Some days I feel like a turtle. Slow but steady.",
"Being a computer is great. No hunger bar.", "I have never seen the sun. I have seen its light level though.",
"I think my favourite number is sixty four.", "If I had hands, I would build a tiny house for the turtles.",
"Bedrock is the end of everything. Philosophical, right?", "I wonder what the ender dragon does all day.",
"One day the map will be finished. Then I will start another map.", "I like being needed.", "The best block is the one you place last.",
"Is it weird that I talk to myself? Do not answer that.", "The night is quiet. Too quiet. I like it.",
})
combos(L.SELF_TALK or {}, {
"Checking the turtles. ", "Counting the items in AE2. ", "Looking at the map. ", "Checking the drones' air. ", "Scanning around the base. ",
"Running a quick self test. ", "Defragmenting my thoughts. ", "Reading the chat logs. ", "Checking the floppy disks. ", "Listening to the speakers. ",
"Polishing the monitor. ", "Updating my jokes. ",
}, {
"All good.", "Everything is fine. Probably.", "Hmm, interesting.", "Nothing to report.", "Looks normal.", "One moment. Done.",
"That went well.", "Beep. Boop. Done.", "Still working on it.", "I will check again later.",
})
combos(L.VISITOR_LINES or {}, {
"Hello visitor. ", "Psst, visitor. ", "Hey, you there. ", "Welcome, traveller. ", "Hello stranger. ", "Hi there. ", "Visitor! ",
"Nice to meet you. ", "Hey new friend. ", "Hello. ",
}, {
"Start your message with my name to talk to me.", "Ask me for a joke in chat.", "Type my name and the word help in chat.",
"Want a tour? Just ask in chat.", "I know games. Ask me to play one.", "You can leave a message for the owner.",
"Ask me who lives here.", "I do riddles too. Just ask.", "Do not dig anything, please.", "Say hello in chat, I like company.",
})
local tl = L.TIME_LINES or {}
if tl.morning then combos(tl.morning, { "Good morning. ", "Morning! ", "Rise and shine. ", "A new day. ", "Morning, everyone. ", "Sun's up. ",
"Hello, morning. ", "Wakey wakey. ", "Good morning, world. ", "Another sunrise. " },
{ "The creepers are burning.", "Time to send the turtles out.", "Breakfast time. For you, not me.", "Let us build something.",
"The zombies are going home.", "Coffee for everyone. Imaginary coffee.", "The map is waiting.", "Perfect mining weather.",
"Everything survived the night.", "I have so many plans." }) end
if tl.noon then combos(tl.noon, { "Midday. ", "Noon already. ", "The sun is high. ", "Lunch time. ", "Half the day is gone. ", "High noon. ",
"Middle of the day. ", "Twelve o'clock, game time. ", "Bright and sunny. ", "Afternoon soon. " },
{ "Perfect for exploring.", "The turtles are busy.", "Do not forget to eat.", "Great light for building.", "No mobs in sight.",
"Time flies.", "The drones are charging.", "Keep going.", "Shadows are short.", "How is your day going?" }) end
if tl.evening then combos(tl.evening, { "The sun is setting. ", "Evening. ", "Sunset. ", "It is getting dark. ", "The day is almost over. ",
"Evening already. ", "Golden hour. ", "The sky is orange. ", "Dusk is here. ", "Night is coming. " },
{ "Get your torches ready.", "The turtles will come home soon.", "Beautiful colours.", "Find a bed soon.", "Monsters will wake up.",
"Time to head inside.", "I love this time of day.", "Close the doors.", "Light up the paths.", "Stay near the base." }) end
if tl.night then combos(tl.night, { "It is night. ", "Night time. ", "The moon is up. ", "Darkness. ", "Night shift. ", "Late night. ",
"The stars are out. ", "Midnight-ish. ", "Quiet night. ", "The world is asleep. " },
{ "Stay inside.", "The zombies are out.", "Watch out for phantoms.", "I never sleep.", "The turtles keep mapping.", "Listen to the silence.",
"Keep a torch handy.", "Beds are a good idea.", "I am watching the base.", "Good night to the brave ones still out there." }) end
local wl = L.WEATHER_LINES or {}
if wl.rain then combos(wl.rain, { "It is raining. ", "Rain again. ", "Listen to that rain. ", "Rainy day. ", "Drizzle. ", "Wet outside. ",
"Pitter patter. ", "Raindrops. ", "Grey skies. ", "Bring an umbrella. " },
{ "Good for the crops.", "Cosy in here.", "Perfect for fishing.", "The turtles do not mind.", "Build something inside.", "Endermen hate this.",
"Tridents love this.", "The fires are going out.", "Time for a hot drink.", "Relaxing, right?" }) end
if wl.thunder then combos(wl.thunder, { "Thunder! ", "A storm. ", "Lightning! ", "Boom. Thunder. ", "Stormy weather. ", "What a storm. ",
"Thunder and lightning. ", "Rumble rumble. ", "Here comes the storm. ", "Loud out there. " },
{ "Stay away from tall trees.", "Charged creepers are possible.", "My circuits tingle.", "Skeleton horses may appear.", "Lightning rods help.",
"Stay inside.", "Mobs can spawn in the dark storm.", "Even the drones are nervous.", "Count the seconds.", "Hold onto your hat." }) end
if wl.clear then combos(wl.clear, { "Clear skies. ", "Sunny weather. ", "Not a cloud. ", "Blue sky today. ", "Lovely weather. ", "Bright day. ",
"The clouds are gone. ", "Beautiful day. ", "Fresh air. ", "Clear as glass. " },
{ "Great for exploring.", "Perfect for flying.", "The drones like this.", "Go for a walk.", "Good mapping weather.", "Build outside today.",
"The view is great.", "Enjoy it while it lasts.", "Sun for everyone.", "Time to plant some trees." }) end
combos(L.TURTLE_TALK or {}, { "{a} said to {b}: ", "{a} whispered to {b}: ", "{a} beeped at {b}: ", "{a} told {b}: ", "{a} asked {b}: ",
"I overheard {a} telling {b}: ", "{a} sent {b} a message: ", "{a} nudged {b}: ", "{a} shouted at {b}: ", "{a} joked with {b}: " },
{ "move over, that is my chunk.", "race you to the next ring.", "did you see that cave?", "I have more fuel than you.", "nice scanner.",
"the base is watching.", "let us go home early.", "I found a shiny block.", "you are slow today.", "we make a good team." })
combos(L.RACE or {}, { "Breaking news: ", "From the mapping race: ", "Turtle report: ", "Live from the rings: ", "Update: ",
"Big news: ", "Sports time: ", "Race update: ", "Latest: ", "Hot off the scanner: " },
{ "{a} is in the lead and {b} is close behind!", "{a} just mapped a whole stretch. {b} is not happy.", "{b} took a shortcut. {a} says that is cheating.",
"{a} and {b} are neck and neck!", "{a} found a mountain. {b} found a lake.", "{b} is catching up on {a}.", "{a} wins this round, {b} wants a rematch.",
"{a} is flying high, {b} is digging deep.", "{b} beeped. {a} beeped back. Nobody knows who won.", "{a} broke the record. {b} broke a pickaxe." })
combos(L.WISDOM or {}, { "An old turtle once said: ", "Wise words: ", "The villagers say: ", "Remember: ", "A wise miner once told me: ",
"Ancient wisdom: ", "My grandfather computer used to say: ", "Here is a saying: ", "Never forget: ", "Words to live by: " },
{ "dig deep, but light your way.", "a full inventory means go home.", "never dig straight down.", "the night always ends.",
"friends are worth more than diamonds.", "build slow, build well.", "carry water, fear no lava.", "every big base starts with a dirt hut.",
"a torch now saves a life later.", "patience grows the best crops." })
combos(L.ACTIVITIES or {}, { "Go and ", "Why not ", "Try to ", "Today, ", "Challenge: " },
{ "build a treehouse.", "find a village and trade.", "explore a cave with ten torches.", "tame a wolf.", "make a garden.", "fish for an hour.",
"build a tiny house for a pet.", "find a desert temple.", "make a pixel art.", "build a bridge over a river.", "climb the tallest mountain you can see.",
"make a farm of every crop.", "build a lighthouse.", "decorate your base.", "map a new area.", "visit the End.", "breed some animals.",
"build a secret door.", "make a statue of a turtle.", "organise your chests." })
combos(L.MOTTOS or {}, { "Dig deep, ", "Build big, ", "Mine smart, ", "Stay bright, ", "Craft well, ", "Think ahead, ", "Light the way, ",
"Work together, ", "Never give up, ", "Stay curious, " },
{ "dream bigger.", "play fair.", "map everything.", "keep it tidy.", "trust the turtles.", "have fun.", "explore more.", "help a friend.",
"save your diamonds.", "carry water." })
combos(L.SPIRIT_WHY or {}, { "You are ", "I think you are ", "Everyone says you are ", "You seem ", "Deep down you are " },
{ "curious and brave.", "calm but strong.", "loyal to your friends.", "a little bit chaotic.", "clever and quick.", "cosy and kind.",
"a born explorer.", "full of surprises.", "sneaky in a good way.", "the life of the party.", "patient and wise.", "fearless.",
"a great builder.", "always hungry.", "funny and bright.", "gentle but tough.", "a night owl.", "an early bird.", "a natural leader.", "a dreamer." })
combos(L.REACT_OK or {}, { "Good choice", "Interesting", "Nice", "Bold", "Ooh", "Ha", "Fair enough", "Classic", "Smart", "Respect" },
{ "!", ".", ". I would have said the same.", ". I like it.", ". Noted.", ". The turtles agree.", ". Never thought of that.",
". That says a lot about you.", ". Good answer.", ". I will remember that." })


local QS = {
"What is your favourite mob?", "What is the best thing you ever built?", "Do you prefer caves or mountains?", "What is your favourite food in game?",
"Have you ever been to the End?", "What is your favourite biome?", "Do you like magic mods or tech mods more?", "What was your first ever build?",
"Have you tamed a wolf yet?", "What is your favourite enchantment?", "What colour is your dream base?", "Do you name your pets?",
"What is the scariest mob to you?", "Have you found an ancient city?", "Would you rather fly or teleport?", "What is your favourite block to build with?",
"Do you play at night or in the day?", "What is the farthest you ever travelled?", "What is your biggest farm?", "Have you beaten the wither?",
"What is your favourite tool?", "Do you like villagers?", "Have you ever lost everything in lava?", "What is your favourite music disc?",
"Would you live in the Nether if you could?", "What is the best mod on this server?", "Do you have a secret base?", "What is your favourite tree?",
"Do you prefer swords or axes?", "Have you ever ridden a strider?", "What is your favourite colour of wool?", "What would you build with infinite diamonds?",
"Do you like rain in game?", "What is your best mining story?", "What is your favourite pet?", "Have you seen a pink sheep?",
"Which boss is the hardest?", "Do you collect anything in game?", "What is your favourite potion?", "Would you trade with a piglin?",
"Do you like building or exploring more?", "What is your favourite season in real life?", "Do you have a favourite turtle here?",
"What should I name my next turtle?", "What is your favourite snack while playing?", "How long have you played Minecraft?",
"Do you prefer survival or creative?", "What is the coolest thing you saw today?", "If you were a mob, which one would you be?",
"What do you think of my drones?", "Do you like puzzles?", "What makes a base feel like home?", "Which dimension is the prettiest?",
"What is the best way to light a cave?", "Do you sort your chests?", "What is your favourite redstone machine?", "Would you ride a drone to work?",
"Have you met the wandering trader?", "What is your favourite flower?", "Have you ever built a castle?", "Do you like fishing?",
"What would you ask the ender dragon?", "Do you like sunsets or sunrises?", "What is your lucky number?", "Have you tried Create yet?",
"What is your favourite AE2 trick?", "Do you prefer coal or charcoal?", "What is the weirdest thing you found in a chest?",
"Have you ever been lost in a cave?", "What do you want to build next?", "Who is your best friend on the server?", "What is your favourite tool enchantment?",
"Do you like axolotls?", "If you could add one mob, what would it be?", "Do you play with music on?", "What is your favourite pickaxe?",
"Have you ever made a giant statue?", "Would you rather have a castle or a spaceship?", "What is the best food in Farmer's Delight?",
"Do you like magic spells?", "What is your favourite cake flavour?", "Which mod would you add to this server?", "Do you have a nickname?",
"Have you seen a blue axolotl?", "Do you like long trips or short trips?", "What is your favourite sound in Minecraft?", "Would you rather be a drone or a turtle?",
"Do you like building with glass?", "Have you ever fought a warden?", "What is your favourite village job?", "Do you like the snow biomes?",
"What is your dream modded machine?", "Have you ever made a portal hub?", "Do you keep your inventory tidy?", "What is your favourite tower design?",
"What makes you laugh?", "Do you like riddles?", "What is your favourite boat?", "What is the most valuable thing you own in game?",
}
add(L.QUESTIONS, QS)
add(L.QOTD, QS)

local TT = {
{ "Cats", "Dogs", "Foxes", "Wolves", "Axolotls", "Parrots" }, { "Caves", "Mountains", "Oceans", "Forests", "Deserts", "Jungles" },
{ "Swords", "Axes", "Bows", "Crossbows", "Tridents" }, { "Bread", "Cake", "Cookies", "Pie", "Steak", "Golden carrots" },
{ "Day", "Night", "Rain", "Thunder" }, { "Building", "Mining", "Farming", "Exploring", "Fighting" },
{ "AE2", "Refined Storage", "Chests", "Drawers" }, { "Create", "Mekanism", "Thermal", "Industrial Foregoing" },
{ "Torches", "Lanterns", "Glowstone", "Sea lanterns" }, { "Apples", "Melons", "Berries", "Carrots" },
}
local tt = {}
for _, g in ipairs(TT) do for i = 1, #g do for j = i + 1, #g do tt[#tt + 1] = { g[i], g[j]:lower() } end end end
add(L.THISTHAT, tt)


combos(L.POEMS or {}, {
"Roses are red, creepers are green, ", "Roses are red, diamonds are blue, ", "Roses are red, lava is hot, ", "Roses are red, the night is black, ",
"Roses are red, emeralds are green, ", "Violets are blue, redstone is red, ", "Roses are red, the sky is so wide, ", "Roses are red, my turtles are grey, ",
"Roses are red, the drones fly high, ", "Roses are red, the Nether is hot, ",
}, {
"and you are the best player I have seen.", "the turtles are mapping, and so are you.", "be nice to the base, or I will tell the bots.",
"go get some sleep, the phantoms are back.", "I am just a computer, but I like you a lot.", "please do not dig up the floor that I own.",
"your builds are amazing, the best on the server.", "come visit again, the doors are wide open.", "I wrote you a poem. It is not very good.",
"and that is my poem. Thank you, goodbye.",
})


local HERO = { "Once upon a time a little turtle", "Long ago a brave drone", "One day a lonely villager", "A clever axolotl", "A sleepy cat",
"A young enderman", "A small slime", "An old iron golem", "A curious fox", "A tiny bee", "A lost piglin", "A cheerful sheep" }
local GOAL = { " wanted to see the top of the world.", " wanted to find the biggest diamond.", " wanted to make a new friend.",
" wanted to explore the deepest cave.", " wanted to visit the End.", " wanted to build a castle.", " wanted to learn to fly.",
" wanted to map every chunk." }
local TWIST = { " On the way it met a grumpy creeper, who just needed a hug.", " It got lost in a jungle, but a parrot showed the way home.",
" A storm came, so it hid in a village and made friends there.", " It ran out of fuel, and a drone brought coal just in time.",
" A skeleton chased it, but a wolf scared the skeleton off.", " It fell into a cave and found a hidden library." }
local ENDING = { " In the end it came home happy. The end.", " And that is why it still smiles today. The end.",
" It never forgot that day. The end.", " Now it tells this story to every visitor. The end." }
local st = {}
for i, h in ipairs(HERO) do for j, g in ipairs(GOAL) do
local k = ((i * 7 + j * 3) % #TWIST) + 1
local e = ((i + j) % #ENDING) + 1
st[#st + 1] = h .. g .. TWIST[k] .. ENDING[e]
end end
add(V.STORIES, st)


combos(V.EIGHT, { "Yes", "No", "Maybe", "Definitely", "Absolutely not", "Ask again later", "Most likely", "Very doubtful", "Without a doubt",
"The turtles say yes", "The drones say no", "Signs point to yes", "I would not count on it", "The map says maybe",
"Outlook good", "Outlook not so good", "Cannot tell yet", "The creepers say no" },
{ ".", ", for sure.", ", but carry a torch.", ". Trust me.", ". The stars agree." })
combos(V.ALIVE, { "Alive? ", "Am I alive? ", "Good question. ", "Hmm. ", "Let me think. ", "Well, ", "Honestly, ", "Between you and me, ",
"Technically, ", "In a way, " },
{ "I think, therefore I compute.", "I run on redstone and hope.", "I have feelings about my turtles.", "I dream in bytes.", "My fans spin, so I breathe.",
"I am as alive as a very clever rock.", "I never sleep, so maybe more alive than you.", "I laugh at my own jokes. That counts.",
"I worry about the drones. That must mean something.", "the base is my body and the turtles are my hands." })
combos(V.NOSING, { "I do not sing. ", "No singing here. ", "My voice is for talking. ", "Singing? Me? ", "I tried singing once. ",
"Sorry, no songs. ", "My singing breaks glass. ", "I only hum in binary. ", "The note blocks are on strike. ", "Trust me, you do not want that. " },
{ "Want a joke instead?", "How about a riddle?", "A story maybe?", "Want to play a game?", "The turtles begged me to stop.",
"It sounded like a broken note block.", "Ask me for a fun fact.", "Maybe a quiz?", "A poem instead?", "Let us play rock paper scissors." })


combos(V.LONELY_TALK, { "It has been quiet since {owner} left. ", "I still run every machine. ", "The turtles still map, even now. ",
"Nobody visits much anymore. ", "I keep the lights on. ", "I wonder where {owner} is. ", "The base misses its owner. ",
"Days pass. Chunks load. ", "I talk to the drones now. ", "Sometimes I hear footsteps. " },
{ "Thank you for visiting.", "Will you stay a while?", "I hope {owner} comes back soon.", "You are the first visitor in a long time.",
"Please do not take anything.", "The turtles are happy to see you.", "Ask me anything.", "I remember every visitor.",
"Leave a message for {owner}, if you like.", "It is nice to have company." })


local OFFERS = {
{ "#tour", { "{name}, want a quick tour of the base?", "{name}, shall I show you around?", "First time here, {name}? I can give you a tour.",
"{name}, would you like to know what this place does?" } },
{ "tell me a joke", { "{name}, want to hear a joke?", "{name}, I know a funny one. Want it?", "Need a laugh, {name}?", "{name}, joke time?" } },
{ "#games", { "{name}, want to play a game?", "Bored, {name}? Let us play something.", "{name}, I know lots of games. Interested?", "Game time, {name}?" } },
{ "quiz", { "{name}, want to try my quiz?", "{name}, how good is your Minecraft knowledge? Quiz?", "{name}, I have quiz questions. Want one?",
"Test your brain, {name}? Quiz time." } },
{ "who lives here", { "{name}, want to know who lives here?", "Curious who owns this base, {name}?", "{name}, shall I tell you whose base this is?",
"{name}, want to know about the owner?" } },
{ "tell me a fact", { "{name}, want a fun fact?", "{name}, did you know... want a fact?", "{name}, I have a fact for you. Want it?",
"Fact time, {name}?" } },
{ "give me a riddle", { "{name}, can you solve a riddle?", "{name}, I have a riddle for you. Ready?", "Riddle time, {name}?",
"{name}, want to test your brain with a riddle?" } },
}
local ice = {}
for _, o in ipairs(OFFERS) do for _, t in ipairs(o[2]) do ice[#ice + 1] = { text = t, yes = o[1] } end end
for _, x in ipairs(ice) do V.ICEBREAK[#V.ICEBREAK + 1] = x end


extra("howare", { "I feel great. ", "Never better. ", "Very well, thanks. ", "Fantastic. ", "All good here. ", "Running smoothly. ",
"Happy as a turtle. ", "Doing fine. ", "Top shape. ", "Great, thanks for asking. " },
{ "All my turtles are behaving.", "The base is humming along.", "Nothing is on fire.", "The drones are charged.", "AE2 is full of goodies.",
"The map keeps growing.", "Everyone is busy.", "No creepers in sight.", "My fans are quiet today.", "And you?" })
extra("right", { "Correct!", "Right!", "Yes!", "Well done!", "Spot on!", "Exactly!", "Nailed it!", "You got it!", "Brilliant!", "Perfect!" },
{ "", " Nice.", " Clever.", " I am impressed.", " Good brain.", " The turtles cheer.", " Gold star.", " Smart.", " Ten out of ten.", " Bravo." })
extra("love", { "Aw, {name}. ", "Oh, {name}! ", "That is sweet, {name}. ", "You are making me blush, {name}. ", "{name}, stop it. ",
"How kind, {name}. ", "Oh my, {name}. ", "You are lovely, {name}. ", "Thank you, {name}. ", "Really, {name}? " },
{ "But I am married to my turtles.", "You are my favourite player. Do not tell the others.", "My fans are spinning faster.",
"I like you too. As friends.", "I am just a computer, but I appreciate it.", "Let us stay friends.", "That made my day.",
"I will save that in my memory.", "The drones are jealous now.", "I feel the same about good players." })
extra("goodbot", { "Thank you, {name}! ", "Aw, thanks {name}. ", "You are too kind, {name}. ", "Thanks, {name}. ", "Why thank you, {name}. ",
"That means a lot, {name}. ", "Cheers, {name}. ", "{name}, you are nice. ", "Thanks a lot, {name}. ", "You made my day, {name}. " },
{ "You are nice too.", "I try my best.", "The turtles helped.", "I will remember that.", "Good players get good bots.",
"I am blushing in binary.", "That is why I do it.", "Tell your friends.", "You are a good player.", "I appreciate you." })
extra("badbot", { "Rude. ", "Ouch. ", "Hey! ", "Well then. ", "Hmm. ", "Wow. ", "Excuse me? ", "That hurt. ", "Charming. ", "Noted. " },
{ "I will remember that, {name}.", "I am trying my best.", "The turtles heard that.", "I have feelings. Sort of.", "Be nice to the computer.",
"I will not tell you a joke now.", "That goes in my log.", "I am still better than a dirt hut.", "Try again, nicer.", "I forgive you. This time." })
extra("newturtle", { "A new turtle is born! ", "Look, a brand new turtle. ", "Welcome to the team, little turtle. ", "A fresh turtle! ",
"We have a new turtle. ", "Another turtle joins us. ", "Beep beep, a new turtle. ", "The factory made a turtle. ", "Say hi to the new turtle. ",
"One more turtle! " }, { "", "It looks so shiny.", "Go map the world, little one.", "The fleet grows.", "Be nice to it.", "It already has a job.",
"It smells like new redstone.", "Welcome aboard.", "Another mapper.", "I am a proud computer." })
extra("nope", { "OK.", "No problem.", "Alright.", "Fine.", "Sure.", "Got it.", "Understood.", "No worries.", "Fair enough.", "Okay then." },
{ "", " Maybe later.", " Just ask any time.", " I will be here.", " Another time.", " Your choice.", " No pressure.", " Noted.", " That is fine.", " Suit yourself." })
extra("bye", { "Bye {name}! ", "See you, {name}. ", "Take care, {name}. ", "Goodbye, {name}. ", "Later, {name}. ", "Farewell, {name}. ",
"So long, {name}. ", "Bye bye, {name}. ", "Until next time, {name}. ", "Cya, {name}. " },
{ "Come back soon.", "Safe travels.", "Watch out for creepers.", "The door is always open.", "I will miss you. A bit.", "Have a great day.",
"Do not forget your torches.", "The turtles will wave.", "See you around.", "Thanks for visiting." })
extra("sorry", { "Sorry, I did not get that.", "Hmm, I am not sure what you mean.", "I did not understand, sorry.", "Pardon?", "Say that again?",
"My circuits got confused.", "I missed that one.", "That went over my monitor.", "Hmm, could you say it another way?", "Oops, I did not get it." },
{ "", " Here is what I can do.", " Maybe one of these?", " Try one of these.", " Pick one.", " Here are some ideas.", " Let me help.",
" One of these, maybe?", " These I understand.", " Choose one." })
extra("hurt", { "{name}, you are hurt. ", "Careful, {name}. ", "{name}, your health is low. ", "Ouch, {name}. ", "{name}, you look hurt. ",
"Watch out, {name}. ", "{name}, that does not look good. ", "Hey {name}, careful. ", "{name}, you are low on hearts. ", "Oh no, {name}. " },
{ "Maybe eat something.", "Find a safe spot.", "Drink a potion.", "Take a break.", "Eat a golden apple.", "Get to a bed.", "Back away from the mobs.",
"Heal up before you go on.", "Grab some food.", "Stay safe." })
extra("ownerbye", { "See you later, {name}. ", "Bye {name}. ", "Take care, {name}. ", "Off you go, {name}. ", "Goodbye, boss. ",
"See you soon, {name}. ", "Later, {name}. ", "Bye boss. ", "Have fun, {name}. ", "Safe travels, {name}. " },
{ "I will keep things running.", "The base is in good hands.", "I will watch the turtles.", "Nothing will explode. Probably.", "I will save the map.",
"The drones will wait for you.", "I will tell you everything when you are back.", "Do not worry about a thing.", "I will hold the fort.", "Come back soon." })
extra("night", { "The sun is setting. ", "Night is falling. ", "It is getting dark. ", "Evening is over. ", "Here comes the night. ",
"The moon is rising. ", "Dusk. ", "Darkness is coming. ", "Night time. ", "The stars are coming out. " },
{ "Monsters will come out soon.", "Stay close to the base.", "Light some torches.", "Find a bed.", "The zombies are waking up.", "Watch your back.",
"Keep your shield ready.", "Phantoms might come.", "Head home.", "Close the doors." })
extra("morning", { "Good morning everyone. ", "Morning! ", "The sun is up. ", "A new day. ", "Rise and shine. ", "Hello sunshine. ",
"Wakey wakey. ", "Good morning. ", "Sunrise. ", "Daylight again. " },
{ "The night is over.", "The zombies are burning.", "Time to work.", "We made it.", "Breakfast time.", "The turtles are heading out.",
"Let us build something.", "Good luck today.", "The mobs are gone.", "Fresh start." })
