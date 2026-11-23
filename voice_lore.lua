-- voice_lore.lua  -  LORE PACK for the talking base (an add-on file on a data floppy, loaded after the other
-- voice files; see VOICE_FILES in base_theme.lua).
--
-- The owner: "add other questions and answers like why the drones, why not /tp etc. Read a bit about the modpack
-- Craftoria or other modpacks and add some things you think are great." So:
--   * WHY questions about the base itself: why drones and not /tp, why turtles, how the map works, why turtles get
--     lost, chunk loading, why drones are slow, lag and the server's speed (measured), floppies, how it talks ...
--   * MODPACK questions: getting started, power, AE2, Mekanism, Create, magic, storage, farms, travel, bosses,
--     dimensions, the end game - kitchen-sink NeoForge 1.21.1 packs like Craftoria or All the Mods share most of
--     these mods (AE2, Mekanism, Create, Ars Nouveau, Occultism, Waystones, Sophisticated Backpacks ...)
--   * 70 mod words for the glossary ("what is ae2", "explain the digital miner")
--   * 100+ MODPACK TIPS ("give me a mod tip"; also now and then as idle talk)
-- Every answer has several ways to say it (picked by the shuffle bag).
local V = VOICE
if not V then return end
V.packs = V.packs or {}
V.packs["voice_lore.lua"] = { version = 1 }
local L = V.L or {}
local pick = V.pick or function(t) return t[math.random(1, #t)] end
local function I(id, keys, reply) return { id = id, keys = keys, reply = reply } end

-- ===== MODPACK TIPS =====
V.MODTIPS = {
  "Mod tip: in a big modpack, follow the quest book. It is a map of the whole pack.", "Mod tip: press R on an item in JEI or EMI to see how it is made, U to see what it is used for.",
  "Mod tip: get a backpack early. Sophisticated Backpacks can be upgraded to feed you and pick up items.", "Mod tip: find Waystones. They save hours of walking.",
  "Mod tip: AE2 starts with meteorites. Find one with a meteorite compass and get the presses inside.", "Mod tip: in AE2, the four presses make the processors you need for everything.",
  "Mod tip: in AE2, every cable carries eight channels. Dense cables carry thirty two.", "Mod tip: in AE2, a storage cell with few item types holds the most items.",
  "Mod tip: AE2 crafting needs patterns, molecular assemblers and a crafting CPU.", "Mod tip: more co-processors in an AE2 crafting CPU means more crafts at once.",
  "Mod tip: AE2 storage buses can turn any chest or drawer into part of your network.", "Mod tip: in AE2, an interface can keep a stock of items in a machine.",
  "Mod tip: in Mekanism, an enrichment chamber doubles your ores. That is the easy first step.", "Mod tip: Mekanism's purification chamber with oxygen triples ores.",
  "Mod tip: Mekanism's chemical injection chamber gets you four ingots per ore.", "Mod tip: Mekanism's full ore chain gives five ingots per ore. Worth it.",
  "Mod tip: Mekanism machines get faster with speed upgrades, and use less power with energy upgrades.", "Mod tip: the Mekanism digital miner mines a whole area while you sleep.",
  "Mod tip: Mekanism's universal cables move power, and logistical transporters move items.", "Mod tip: a Mekanism atomic disassembler is an amazing all-in-one tool.",
  "Mod tip: in Create, everything runs on rotation. Water wheels and windmills are free power.", "Mod tip: in Create, watch the stress units. Too much load and everything stops.",
  "Mod tip: Create's mechanical press and mixer make brass and much more.", "Mod tip: Create trains can carry huge loads across the world.",
  "Mod tip: in Create, a deployer can use items like a player does.", "Mod tip: Create's crushing wheels give extra ore bits from raw ore.",
  "Mod tip: Ars Nouveau spells are made from glyphs. Start with projectile and break for a mining spell.", "Mod tip: Ars Nouveau's source comes from sourcelinks near a source jar.",
  "Mod tip: in Ars Nouveau, a starbuncle can move items between chests for you. Adorable and useful.", "Mod tip: Occultism needs you to see spirits first. Eat a demon's dream fruit. Carefully.",
  "Mod tip: in Occultism, a spirit can work as a miner, a crusher or a trader.", "Mod tip: Botania starts with a petal apothecary and the Lexica Botania guide.",
  "Mod tip: in Botania, mana pools fill from generating flowers. The endoflame burns fuel for mana.", "Mod tip: Mystical Agriculture grows ores as crops. Start with inferium essence.",
  "Mod tip: in Mystical Agriculture, better farmland makes your seeds grow faster.", "Mod tip: Productive Bees can make combs of almost any ore.",
  "Mod tip: Apotheosis makes enchantments go far beyond vanilla. Bookshelves matter a lot.", "Mod tip: Apotheosis gems add bonus stats to your gear.",
  "Mod tip: Functional Storage drawers hold huge stacks of one item. A storage controller links them.", "Mod tip: use a framed drawer to make your storage wall look nice.",
  "Mod tip: Farmer's Delight meals give long lasting effects. A cooking pot is worth building.", "Mod tip: the comfort effect from Farmer's Delight heals you slowly.",
  "Mod tip: Iron's Spells needs a scroll forge and an inscription table to make spell books.", "Mod tip: the Twilight Forest has bosses in a set order. Start with the naga.",
  "Mod tip: in the Twilight Forest, the bosses unlock the next area. Do not skip ahead.", "Mod tip: Industrial Foregoing's laser drill can mine ores out of thin air.",
  "Mod tip: Industrial Foregoing's mob crusher and slaughter factory make mob farms easy.", "Mod tip: Powah's energizing orb makes crystals for better generators.",
  "Mod tip: Powah's reactors make lots of power, but need cooling.", "Mod tip: Modern Industrialization builds big multiblock machines. Plan the space first.",
  "Mod tip: Pipez moves items, fluids, energy and gas through one kind of pipe.", "Mod tip: Laser IO links machines without cables. Nice and tidy.",
  "Mod tip: XNet connects many machines through one controller.", "Mod tip: in most packs, the first big goal is steady power. Solar is easy, generators are faster.",
  "Mod tip: chunk loaders keep your machines running when you are far away. Use them wisely, they cost server time.", "Mod tip: lots of item entities on the ground make servers lag. Pick them up or use a vacuum.",
  "Mod tip: fluid tanks, drawers and AE2 cells are better than many chests for lag.", "Mod tip: in Craftoria and similar packs, recipes can be changed. Always check JEI.",
  "Mod tip: big packs often have a final item, like the ATM Star in All the Mods. It takes a whole base to make.", "Mod tip: All the Modium, Vibranium and Unobtainium are the special ores of the All the Mods packs.",
  "Mod tip: most kitchen sink packs mix tech and magic. You can play only tech or only magic, but both together are stronger.",
  "Mod tip: Curios gives you extra slots for rings, belts and charms.", "Mod tip: a good early magnet saves your back. Many mods have one.",
  "Mod tip: use a mining gadget or a hammer tool to mine three by three in modded packs.", "Mod tip: Nature's Compass finds biomes, Explorer's Compass finds structures.",
  "Mod tip: Just Dire Things has handy items like the ferricore tools. Check the quests.", "Mod tip: if a machine stops, check power, input space and output space. It is always one of those.",
  "Mod tip: automate the boring stuff first: smelting, ore processing and food.", "Mod tip: name your AE2 patterns by placing them in order. Future you will thank you.",
  "Mod tip: in AE2, a level emitter can turn machines on only when stock is low.", "Mod tip: in AE2, a ME drive holds ten storage cells.",
  "Mod tip: AE2 wireless terminals let you reach your storage anywhere in range.", "Mod tip: in PneumaticCraft, pressure tubes explode if the pressure is too high. Watch the gauge.",
  "Mod tip: PneumaticCraft drones can be programmed to mine, farm and carry items.", "Mod tip: a PneumaticCraft charging station fills drones with air.",
  "Mod tip: volume upgrades let PneumaticCraft drones carry more air. More air means more teleports.", "Mod tip: speed upgrades make PneumaticCraft drones fly faster.",
  "Mod tip: in ComputerCraft, turtles need fuel. Coal works, lava buckets work better.", "Mod tip: a ComputerCraft wireless modem lets turtles talk to the base.",
  "Mod tip: Advanced Peripherals adds the ME Bridge, so a computer can read AE2.", "Mod tip: a Geo Scanner lets a turtle see the blocks around it.",
  "Mod tip: a Chunky turtle keeps its own chunk loaded. Great for long trips.", "Mod tip: a GPS host needs four computers with wireless modems high in the sky.",
  "Mod tip: Mining dimension mods give you a fresh world just for mining, so the overworld stays pretty.", "Mod tip: in many packs, quests give rewards. Claim them, they add up.",
  "Mod tip: back up your base before you try a new mod's explosive machines.", "Mod tip: the Ender IO conduits can carry many things in one block.",
  "Mod tip: Thermal's dynamos turn fuel into power. A good early choice.", "Mod tip: Immersive Engineering's machines are big multiblocks that look amazing.",
  "Mod tip: Draconic Evolution is late game. Its armour and tools are some of the strongest.", "Mod tip: Blood Magic needs an altar and, well, your blood. Use a sacrificial dagger carefully.",
  "Mod tip: Refined Storage is like AE2 but simpler, with no channels.", "Mod tip: KubeJS lets pack makers change recipes. That is why recipes differ between packs.",
  "Mod tip: FTB Quests is the quest book in most packs. Pin the chapter you are working on.", "Mod tip: a Mekanism teleporter needs a frame of teleporter blocks, power, and a second teleporter to link to.",
  "Mod tip: in big packs, write down your coordinates often. A death far away is painful.", "Mod tip: Create's andesite alloy is the start of almost everything in Create.",
  "Mod tip: in Mekanism, a fission or fusion reactor is end game power. Read the guide first.", "Mod tip: Mekanism's QIO is a storage system like AE2, with drives and terminals.",
  "Mod tip: Applied Flux lets AE2 store power. Applied Mekanistics lets it store chemicals.", "Mod tip: Extended AE adds bigger crafting CPUs and better buses.",
  "Mod tip: Ars Nouveau's imbuement chamber turns gems into magic items with source.", "Mod tip: Occultism's dimensional storage holds a huge amount with spirits as helpers.",
  "Mod tip: mob grinding utilities make experience farms easy.", "Mod tip: a void miner in some packs mines ores from nothing. Very late game.",
}
if V.TIPS then for i = 1, 20 do V.TIPS[#V.TIPS + 1] = V.MODTIPS[i * 5] end end

-- ===== the base's WHY questions and the modpack questions =====
local function tpsLine()
  local t = V.tps and V.tps()
  if not t then return "I am still measuring the server's speed - ask me again in a minute." end
  return "Right now the server makes about " .. math.floor(t + 0.5) .. " ticks a second" ..
         (t >= 19 and " - that is full speed." or (t >= 15 and " - a little slow." or " - that is slow, so everything takes longer, my drones too."))
end
V.addIntents({
  I("lore_dronesslow", { "why drones slow", "why are drones slow", "drones slow", "why is the drone slow", "drone takes long", "why does the ride take so long" }, function()
    return "A drone waits 120 game ticks before every teleport, and it can only jump into loaded chunks - so long trips go in hops. " .. tpsLine()
  end),
  I("lore_whydrones", { "why drones", "why not tp", "why not teleport", "why no tp", "why use drones", "drones instead", "why not just tp",
    "why cant you tp me", "why fly", "tp me", "teleport me", "why not tpa" }, {
    "Why drones and not /tp? This is survival. There is no /tp for players here, so the base does it the in-game way: a PneumaticCraft drone picks you up and teleports with compressed air.",
    "No /tp on this server - that would be cheating, and {owner} likes it fair. My drones fly you instead. Each teleport costs air, so they hop in steps.",
    "A /tp command is for admins. I am just a computer with drones. They can only teleport into loaded chunks, so far trips go in hops.",
    "Drones are the honest way. They carry you, they cost air, and they need the chunks to be loaded. It is more fun than a command, I promise.",
    "Why not teleport you straight away? A drone waits six seconds before every teleport and only lands where the world is loaded. That is the rules of PneumaticCraft.",
    "Because a command is boring and a flying drone is not. Ask me for a taxi if you are my friend.",
  }),
  I("lore_lag", { "server lag", "is the server lagging", "why lag", "tps", "ticks per second", "server speed", "how fast is the server" }, function()
    return tpsLine() .. " Machines, mobs and items on the ground all cost ticks."
  end),
  I("lore_whyturtles", { "why turtles", "why use turtles", "what do turtles do", "what are the turtles for", "why so many turtles" }, {
    "The turtles map the world for me. Each one has a Geo Scanner, flies out in rings around the base and sends back what it sees.",
    "Turtles are my hands and eyes. They map, they rescue each other, they build new turtles and they mine in the mining dimension.",
    "Why turtles? They work while everyone sleeps. Fuel, a scanner and a Chunky upgrade, and off they go.",
    "Every turtle owns a ring of the map. Together they draw the whole world, one chunk at a time.",
  }),
  I("lore_howmap", { "how does the map work", "how do you map", "how is the map made", "how big is the map", "how do turtles map" }, {
    "Turtles scan the ground with Geo Scanners and send me heights and blocks. I keep the newest chunks in detail and one value for every chunk ever seen.",
    "The map is made of turtle scans. They go round the base in rings, 17 blocks apart, and I save it on floppies and helper computers.",
    "Look at the MAP tab on my big screen - green T's are turtles mapping, purple x's are turtles that went quiet.",
  }),
  I("lore_lost", { "why are turtles offline", "lost turtles", "why do turtles get lost", "offline turtles", "missing turtles" }, {
    "A turtle goes offline when its chunk stops running. A server restart, an empty fuel tank, or a copy that shares its Chunky can do that.",
    "Server crashes can make copies of a turtle. Copies share one Chunky, so when one moves the other freezes. I test which one loads its own chunk.",
    "Lost turtles are found by the search party: other turtles fly there, look down and call the rescuer.",
  }),
  I("lore_chunks", { "chunk loading", "what is chunk loading", "loaded chunks", "simulation distance", "why chunks" }, {
    "The world only runs near players and chunk loaders. A Chunky turtle carries its own little loaded area with it.",
    "Simulation distance is how far around a player the world actually runs. My drones keep their hops inside it, or they freeze.",
    "A chunk is sixteen by sixteen blocks. If nobody loads it, nothing in it moves. Not even my turtles.",
  }),
  I("lore_floppies", { "why floppies", "floppy disks", "where do you keep the map", "where is the map saved", "your memory" }, {
    "This computer has only one megabyte. The map lives on floppy disks and on helper computers on the cable.",
    "Floppies and storage helpers. Even my voice lives on a floppy. I am a very organised computer.",
  }),
  I("lore_howtalk", { "how do you talk", "how can you speak", "how do you have a voice", "why can you talk", "your voice" }, {
    "I send my words to a text to speech service, decode the sound and play it on every speaker of the base.",
    "Speakers! CC:Tweaked speakers can play sound, and I make my sentences into sound. Slowly, but clearly.",
  }),
  I("lore_whoami", { "what mods do you use", "what are you made of", "what runs the base", "how does the base work", "what is this computer" }, {
    "I am a CC:Tweaked computer with Advanced Peripherals. I read AE2 through an ME Bridge, fly PneumaticCraft drones and talk to turtles over a wireless modem.",
    "The base is CC:Tweaked plus Advanced Peripherals, AE2, PneumaticCraft drones and a fleet of turtles. And me, the voice.",
  }),
  I("lore_modpack", { "what modpack is this", "which modpack", "what modpack", "is this craftoria", "what mods are here", "modpack" }, {
    "This is a big modded NeoForge server. Packs like this, Craftoria or All the Mods, mix tech like AE2, Mekanism and Create with magic like Ars Nouveau and Occultism.",
    "A kitchen sink pack - tech, magic, exploration, all of it. Ask me for a mod tip, or what is AE2, or how to start.",
  }),
  I("lore_start", { "how do i start", "where do i start", "beginner tips", "new to the modpack", "what should i do first", "first steps", "just started" }, {
    "Start with the quest book. Then: a backpack, a few Waystones, simple ore doubling, then power and AE2.",
    "New here? Wood, stone, iron as usual - then follow the quests. Get Sophisticated Backpacks and a magnet early.",
    "First steps: a safe base with lights, a food farm, a backpack. Then pick one tech mod, like Create or Mekanism, and grow from there.",
    "Read the quest book, press R on items in JEI to see recipes, and do not dig straight down. Classic.",
  }),
  I("lore_power", { "how do i make power", "best power", "power generation", "energy", "rf", "fe", "generator" }, {
    "Early power: solar panels or a coal generator. Middle: Powah reactors or Mekanism wind and gas. Late: big reactors and fusion.",
    "Create runs on rotation, not power - water wheels are free. For FE, Powah and Mekanism are the usual picks.",
    "Steady power first, machines second. Every factory starts with a good generator.",
  }),
  I("lore_ae2", { "how do i start ae2", "ae2 tips", "me system tips", "how to make an me system", "applied energistics tips", "ae2 help" }, {
    "AE2: find a meteorite, get the four presses, make processors, then an ME controller, a drive and some cells. Channels: eight per cable.",
    "Start AE2 with a controller, a drive and a terminal. Add a pattern provider and a crafting CPU for autocrafting.",
    "In AE2 fewer item types per cell means more items per cell. Keep a cell for the big stacks.",
  }),
  I("lore_mek", { "mekanism tips", "ore processing", "how to double ores", "how to triple ores", "mekanism help" }, {
    "Mekanism ores: enrichment chamber doubles, purification chamber triples, injection gives four, the full chain gives five.",
    "Mekanism machines love upgrades. Speed for faster, energy for cheaper. And watch your chemical tanks.",
  }),
  I("lore_create", { "create tips", "how does create work", "create mod help", "stress units" }, {
    "Create runs on rotation. Water wheels and windmills give stress units, machines use them. Too much load and it all stops.",
    "In Create, andesite alloy makes the basics, brass makes the clever parts. Trains are the big reward.",
  }),
  I("lore_magic", { "magic mods", "ars nouveau tips", "magic tips", "how do i get magic", "occultism tips", "botania tips" }, {
    "Ars Nouveau: start with the worn notebook and a novice spell book. Glyphs make spells.",
    "Botania: a petal apothecary, generating flowers and mana pools. The Lexica Botania explains it all.",
    "Occultism: see spirits first with demon's dream, then bind them to work for you. Spooky but very useful.",
  }),
  I("lore_storage", { "storage tips", "how to store items", "best storage", "too many chests", "drawers" }, {
    "Storage: drawers for big stacks, AE2 or Refined Storage for everything else, backpacks for the road.",
    "Too many chests? An AE2 storage bus can turn them into one searchable network.",
  }),
  I("lore_farms", { "farm tips", "best farm", "mob farm", "xp farm", "food farm", "how to farm" }, {
    "Farms: Mystical Agriculture for resources, Productive Bees for ores, Industrial Foregoing or a mob grinder for experience.",
    "Start with an automatic food farm, then an iron farm, then mob drops. Automation saves your evenings.",
  }),
  I("lore_travel", { "fast travel", "how to travel", "waystones", "how do i get around", "travel tips" }, {
    "Travel: Waystones, an elytra, Create trains, or a ride with my drones. Friends get a free taxi.",
    "Find a Waystone and activate it - you can come back any time. Or ask me for a drone ride.",
  }),
  I("lore_bosses", { "what bosses", "hardest boss", "boss tips", "which boss first", "bosses" }, {
    "Bosses: the ender dragon, the wither, the warden, and in packs the Twilight Forest bosses - naga, lich, hydra and more.",
    "Before a boss: full armour, golden apples, potions and a totem. And tell me where you are, just in case.",
  }),
  I("lore_dims", { "best dimension", "dimensions", "twilight forest", "other dimensions", "where to explore" }, {
    "The Twilight Forest is great fun - bosses, mazes and loot. Mining dimensions keep the overworld pretty.",
    "Explore the Nether for quartz and debris, the End for elytra, and modded dimensions for their own treasures.",
  }),
  I("lore_endgame", { "end game", "endgame", "what is the goal", "atm star", "final item", "how do i win" }, {
    "Big packs have a final goal, like the ATM Star in All the Mods. It needs almost every mod, so it takes a whole base.",
    "The end game is usually a giant craft or a creative item. Automate everything and the end comes to you.",
  }),
  I("lore_modtip", { "mod tip", "modpack tip", "give me a mod tip", "tip about mods", "modded tip", "pack tip" }, function()
    return pick(V.MODTIPS)
  end),
})

-- ===== GLOSSARY: mod words ("what is ...", "explain ...") =====
local G = L.GLOSS
if G then
  local W = {
    ae2 = "Applied Energistics 2, a mod that stores items as data in an ME network and crafts things automatically.",
    ["me system"] = "AE2's storage network: a controller, drives with cells, cables and terminals.",
    ["crafting cpu"] = "an AE2 multiblock that runs crafting jobs. Co-processors let it do more at once.",
    pattern = "an AE2 recipe card. Put it in a pattern provider and the network can craft that item.",
    ["storage cell"] = "an AE2 disk that holds items. Bigger cells hold more bytes.",
    channel = "AE2's limit on devices per cable: eight on normal cables, thirty two on dense ones.",
    ["me bridge"] = "an Advanced Peripherals block that lets a computer like me read and move AE2 items.",
    mekanism = "a big tech mod: ore processing, machines, chemicals, jetpacks and the meka-suit.",
    ["digital miner"] = "a Mekanism machine that mines an area by itself, block by block, without breaking the surface.",
    ["meka suit"] = "Mekanism's power armour, upgraded with modules.",
    create = "a mod of rotation and contraptions: gears, belts, presses, trains and moving machines.",
    ["stress units"] = "Create's measure of rotational power. Too much load and the machines stop.",
    ["andesite alloy"] = "Create's first key material, made from andesite and iron or zinc.",
    pneumaticcraft = "a mod of compressed air: pressure tubes, machines and programmable drones.",
    pressure = "in PneumaticCraft, how much air is packed in. Drones use it to fly and teleport.",
    computercraft = "CC:Tweaked, the mod that gives us computers and turtles, programmed in Lua.",
    ["cc tweaked"] = "the mod that runs me and the turtles. Computers you program in Lua.",
    lua = "the programming language I am written in. Small and fast.",
    ["advanced peripherals"] = "a mod that gives computers extra blocks: player detectors, ME bridges, geo scanners, chat boxes and more.",
    ["player detector"] = "an Advanced Peripherals block that tells a computer where players are.",
    ["geo scanner"] = "an Advanced Peripherals scanner that shows the blocks around it. My turtles map with it.",
    chunky = "an Advanced Peripherals turtle upgrade that keeps the turtle's chunk loaded.",
    ["chunk loader"] = "a block or upgrade that keeps a part of the world running while nobody is there.",
    ["simulation distance"] = "how far around a player the world is actually running. Further out, things freeze.",
    ["ars nouveau"] = "a magic mod where you build spells from glyphs and power them with source.",
    source = "Ars Nouveau's magic energy, made by sourcelinks.",
    glyph = "an Ars Nouveau spell part, like projectile, break or harm.",
    occultism = "a dark magic mod: you summon spirits and make them work for you.",
    botania = "a nature magic mod: flowers make mana, and mana makes magic.",
    mana = "Botania's magic power, made by flowers and stored in mana pools.",
    waystone = "a stone you can teleport to after you find it. Great for travel.",
    waystones = "a mod with teleport stones. Find one, use it, come back any time.",
    ["sophisticated backpacks"] = "a mod of upgradable backpacks: magnets, feeding, crafting and more.",
    ["functional storage"] = "a mod of storage drawers that hold huge amounts of one item.",
    apotheosis = "a mod that makes enchanting, gear and dungeons much stronger and more varied.",
    ["productive bees"] = "a mod of bees that make combs of ores and other resources.",
    ["mystical agriculture"] = "a mod where you grow resources like iron and diamonds as crops.",
    inferium = "the first essence of Mystical Agriculture, used to make seeds and tools.",
    ["twilight forest"] = "a magical dimension with bosses, mazes and a big quest line.",
    ["industrial foregoing"] = "a tech mod with farms, mob crushers, laser drills and more.",
    powah = "a power mod: generators, reactors and the energizing orb.",
    ["modern industrialization"] = "a tech mod of large multiblock factories.",
    ["farmers delight"] = "a cooking mod: knives, cooking pots, stoves and many meals.",
    ["irons spells"] = "a magic mod with spell books, scrolls and many spells.",
    jei = "Just Enough Items: shows every recipe. R for how to make, U for what it makes.",
    emi = "a recipe viewer like JEI. Press R or U on an item.",
    ["ftb quests"] = "the quest book in most modpacks. It guides you and gives rewards.",
    ["quest book"] = "the guide of a modpack. Follow it and you will not get lost.",
    kubejs = "a tool pack makers use to change recipes. That is why every pack is a bit different.",
    craftoria = "a big NeoForge 1.21.1 modpack that mixes tech and magic, with Mekanism, AE2, Ars Nouveau, Occultism and hundreds more.",
    ["all the mods"] = "a famous series of kitchen sink modpacks with a giant final craft, the ATM Star.",
    ["atm star"] = "the final item of All the Mods packs. It needs almost every mod.",
    allthemodium = "a special ore from the All the Mods packs, found in the deep and in its own dimensions.",
    vibranium = "an All the Mods ore, stronger than allthemodium.",
    unobtainium = "the strongest All the Mods ore. Not actually unobtainable.",
    curios = "a mod that adds slots for rings, belts, necklaces and charms.",
    ["refined storage"] = "a storage network mod like AE2, simpler, with no channels.",
    thermal = "the Thermal series: machines, dynamos and ore processing.",
    ["immersive engineering"] = "a tech mod with big, good-looking multiblock machines.",
    ["ender io"] = "a tech mod known for its conduits that carry many things in one block.",
    ["draconic evolution"] = "a late game mod of draconic tools, armour and huge energy storage.",
    ["blood magic"] = "a magic mod powered by life essence from an altar.",
    ["mining dimension"] = "a separate world just for mining, so the overworld stays pretty.",
    qio = "Mekanism's storage network, like AE2 with drives and terminals.",
    pipez = "a mod of simple pipes for items, fluids, energy and gas.",
    ["laser io"] = "a mod that links machines with lasers instead of cables.",
    xnet = "a mod that connects many machines through one network controller.",
  }
  for k, v in pairs(W) do if G[k] == nil then G[k] = v end end
  local A = L.GLOSS_ALIAS
  if A then
    for k, v in pairs({ ["applied energistics"] = "ae2", ["applied energistics 2"] = "ae2", ["me network"] = "me system", ["me"] = "me system",
      ["cpu"] = "crafting cpu", ["patterns"] = "pattern", ["cell"] = "storage cell", ["cells"] = "storage cell", ["channels"] = "channel",
      ["meka"] = "mekanism", ["digital mine"] = "digital miner", ["stress"] = "stress units", ["pneumatic craft"] = "pneumaticcraft",
      ["cc"] = "cc tweaked", ["computer craft"] = "computercraft", ["scanner"] = "geo scanner", ["chunky turtle"] = "chunky",
      ["ars"] = "ars nouveau", ["spirits"] = "occultism", ["backpacks"] = "sophisticated backpacks", ["drawer"] = "functional storage",
      ["drawers"] = "functional storage", ["bees"] = "productive bees", ["mystical"] = "mystical agriculture", ["twilight"] = "twilight forest",
      ["farmer's delight"] = "farmers delight", ["iron's spells"] = "irons spells", ["quests"] = "ftb quests", ["atm"] = "all the mods",
      ["atm10"] = "all the mods", ["ender i o"] = "ender io", ["draconic"] = "draconic evolution" }) do
      if A[k] == nil then A[k] = v end
    end
  end
end

-- ===== more things to choose in the menus, and idle mod tips =====
if V.MORE then
  V.MORE[#V.MORE + 1] = { "a modpack tip", "give me a mod tip" }
  V.MORE[#V.MORE + 1] = { "why drones and not /tp", "why drones" }
end
if V.idleExtra then
  V.idleExtra[#V.idleExtra + 1] = function() return V.say(pick(V.MODTIPS)) end
end
