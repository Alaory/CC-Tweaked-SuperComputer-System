# Changelog

Release numbers are `major.minor.patch`. The base shows its own number on SYSTEM > Status
("Program") and with the console command `version`. Turtles (`node.lua`) get a short version
code from the base, mining turtles show `m<N>` (`miner.lua`).

## 1.0.0 - 2026-11-22

The first release. Everything below works together on one CC:Tweaked computer with Advanced
Peripherals (tested on CC:Tweaked 1.120.2, Minecraft 1.21.1, NeoForge).

### The base computer
- A big touch monitor in a "control room" look: HOME (live numbers, NEEDS YOU, quick actions),
  YOU (inventory, backpacks, curios), AE2 (storage + AE2 SYSTEM), PLAYERS (players, world, chat
  and rides, gifts), DRONES (drones, drone work), TURTLES (turtles, drive, map, mining) and
  SYSTEM (status, messages, settings). Six colour themes; nothing is ever drawn out of bounds.
- A keyboard console (`help`) and chat commands (`$drone ...`) for the owner.
- `upgrade`: the newest files from GitHub in one command - only changed files, each checked
  (size, checksum, compiles) before anything is written; `base_config.lua` is never touched.
- Safe saving everywhere (a full disk or a stop mid-save never wipes a file), data floppies and
  storage helper computers for the map and the big data files (a computer has only 1 MB).
- Autostart and crash restart (`startup.lua`); the base notes when and why it was off. An error in one
  part (a page, a button, a background job) no longer stops the base: that part starts again and the
  error goes to the SYSTEM log.
- A miner that ends up in the chunk next to its job chunk (after an unload trip) walks back in instead of stopping.
- PING is sent again until the turtle answers (survey turtles have their modem off while scanning) and says why not.
- Drones on far trips jump into the sky above a player near the target first, then hop on from there.
- Item wishes work at the base too, not only at spawn. The miner program is kept on a storage helper.
- Hardcore-ready auto-equip: KEEP ONE ON (CURIOS tab) checks every tick and puts a new totem on at once, even while
  other buttons are busy.
- Schematics: files with Create machines in them can be read (8-byte numbers in the file stopped the reader); crops,
  vines and filled cauldrons ask AE2 for the right item; fluids are left out of the list; an item AE2 has none of no
  longer stops a drone build (the rest is built, it looks again every 5 min); a build without CLEAR goes on after a
  restart; a big schematic is read in the background, not on the screen; a newer file of the same name stays the one.
- The talking base understands ordinary chat better: real words are no longer taken as typos of other words ("I have a
  story for you" was read as "I hate you"), "can I ask you a question" no longer starts a quiz, "are you ok", "thanks for
  the help", "I am back" and "I love this place" get the right answer.
- Every voice line was read: a dozen wrong Minecraft / mod facts in the quiz, riddles, tips and mod tips are corrected.
- A schematic dropped on the screen is stored on a storage helper first (the computer and the floppies are often full).
- Taking armour / the off hand off from the INVENTORY tab tries the slot numbering your Inventory Manager uses (100-103).
- README pictures of the main screens.
- Files can be dropped onto the computer's screen while the base runs: program files are saved next to inventory.lua (it says
  when a restart is needed), schematics are read - no need to stop the base first.
- INVENTORY tab: armour and the offhand can be picked (they were un-picked at once) and taken off into your inventory or
  sent to AE2.
- Asked = answered: "roll a d20" / "roll 2 dice" / "flip 3 coins" / "pick a number from 1 to 10" / "be quiet for 2
  hours" now do what they say; "forget my notes" forgets them (it showed them); "take me to the base" at the base no
  longer tells a story; the lonely base's wall / memories say when they work; `env`, `me jobs` and `me cpus` answer in the
  console's output; `findlost` / `rescue` say when they cut the radius.
- Reminders: "base, remind me mekanism needs fixing" keeps the text and asks when; "tomorrow" (typos too), "in 2 hours",
  "next time" all work; reminders survive restarts and wait until you are online. A message that starts with the
  beginning of another player's name ("Al, what time is it") is for that player - the base stays out.
- Schematic builds are easier: stand where it should go, look the way it should go and type `$drone build <name>`;
  turn it with `turn left / right / around` or `facing east`, then `$drone build yes`. The DRONE WORK page shows the
  build seen from above (turned, with you on it), TURN LEFT / TURN RIGHT and where it goes. Torches, signs, doors ...
  are placed after the blocks they hang on.
- Mining teams survive a server crash right after moving to the next chunk: miners put back into the old chunk
  walk over again (the loader goes back for them when they do not answer), a loader put back walks over itself.
- Drones never fly out of the loaded area (they were lost), an arrival spot for underground bases, where each
  drone was last seen.
- Parts broken while the base is off: it starts even without its monitor (and uses a new one when you place it),
  lists every block / data floppy it saw before and does not see now (`parts`, HOME, SYSTEM, the away report, one
  warning), notices a replacement by itself, and never uses an Inventory Manager holding another player's card.
- Loading again after a server restart, a chunk reload or a reboot: the base waits up to a minute for the
  blocks and data floppies it saw last time (their chunks may load later), finds missing ones every 20 s,
  never saves a data file elsewhere while its floppy is not loaded, and restarts once when it comes.
- Away mode: while you are offline the turtles keep mapping, and you get a WHILE YOU WERE
  AWAY report when you come back.

### AE2 and storage
- AE2 items and fluids: take, give, craft; works around the bridge's `getItems` crash with a
  partial view. Fluid ALL moves everything (also infinite cells).
- AE2 SYSTEM page: crafting CPUs, running jobs (cancel), your craft requests followed,
  drives and cells, patterns you can browse and craft from.
- `supply`: storages on the cable kept stocked from AE2 (items and fluids, modded tanks too).
- Curios: what fits each slot, put on / take off, auto-equip (a used totem is replaced).
- `chests`: every chest, barrel and tank on the cable and what it is used for.

### Drones (PneumaticCraft)
- Rides for players (to the base, a place, a player, back where you were), with checks that
  the right player is on board and a safe way home after any failure.
- Measured for slow servers: no teleports that cannot work, hops that stay inside the
  simulation distance, flying when it is quicker.
- Drone work: a work chest, fuel runs to turtles out of fuel, schematic builds (Create .nbt)
  with a turtle keeping the site loaded, gifts delivered to players.

### Turtles
- One turtle program (`node.lua`), sent to every turtle over the air.
- The MAP: turtles survey the world in rings around the base, at their own pace; detail +
  overview layers up to the world border; markers show what each turtle is doing.
- Homes, fuel chests and endless fuel items, fuel for the way home, drones bringing fuel far
  out, junk thrown away, lost tools reported.
- Rescuer, search party for lost turtles, duplicate (copy) turtles after a server crash found
  and put to use, a chunk test for copies.
- STOP that always works, your own commands first, a DRIVE page to steer a turtle by hand,
  a no-digging zone around the base.
- Schematic builds get their missing blocks crafted by AE2 automatically (items with a pattern; `schem craft
  on|off|now`, SETTINGS > DRONES). `schem status` names the blocks AE2 has no pattern for.
- A block a drone could not break (out of reach, a claimed chunk, nothing dropped) is tried once more and then
  reported as a WARNING - it was reported as done.
- Drones TAKE THINGS DOWN too: `schem unbuild` takes a build down again (its blocks go back into AE2; `schem built`
  lists your builds), `dw dig <corner> <corner>` (or `$drone dig here` at two corners) digs out an area, and
  `dw break <x y z>` / `$drone break x y z` breaks one block. The work chest, the charger and the drones' home are
  never dug.
- Drones no longer get in each other's way on a build: two drones always work at least 3 blocks apart (each trip
  is one 8 x 8 square), and a spot that refused its block once (a drone, a mob or a player in the way) is tried
  again with just the blocks that came back. On a tiny build (a few blocks) the drones now take turns.
- A CHAIN of schematics (a road in parts): `schem chain road_start,road*6,road_end` (or `$drone chain ...` in chat)
  builds the pieces one after another, each right after the one before. Builds wait in a queue (`schem queue`,
  `schem skip`).
- Drones can EMPTY A BOX OF WATER / LAVA for building (`dw clear <corner> <corner>`, or `$drone clear here` at two
  corners): walls round it, the inside filled with cobblestone and dug out again.
- A build site that is not loaded gets one turtle PER CHUNK (a turtle loads only its own chunk); a turtle whose
  chunk is done moves to the next one or goes home.
- Drone builds use more drones on small builds: blocks go into any layer at once (falling blocks like sand and
  gravel still wait for the layer below, torches and doors for the walls), no extra chest visit before each trip,
  and `schem status` shows where a trip's time goes (chest wait, AE2 into the chest, the drone taking it, flying,
  placing).
- Faster drone builds: a drone stays at the work chest between trips (no flight home to the charger each time,
  as long as it has air), and a drone low on air charges instead of failing a trip that paused the whole build.
- Every drone works at once: builds, gifts and fuel runs use all free drones side by side (they take turns at the
  one work chest, a few seconds each). Each drone still carries one kind of item per trip.
- Survey turtles no longer keep what they dig (ores, gems, logs, saplings, sticks, modded drops ...): away from the
  base a turtle keeps only its gear, its fuel and its endless fuel item - the rest is thrown away right after the
  dig. Turtles already full clean themselves out when idle.
- The program takes a third of the space: `upgrade` keeps the base files PACKED (`base_*.luz`, ~280 KB instead
  of ~917 KB of the computer's 1 MB) and the base unpacks them in memory when it starts. A plain file you drag in
  is still used first. `upgrade slim` / `upgrade full` for plain files. The voice add-on is packed too (`voice
  update`: 823 KB -> 271 KB on the floppies / storage helpers).
- Survey far out: given-back spots (from a lost or failed turtle) only go to a turtle near them, and a turtle that
  takes over a ring starts at its nearest point - no more trips across the whole map between hand-outs (measured:
  ~10 % more spots an hour, trips over 1,000 blocks 44 -> 2-4). A turtle that just took a job no longer says "idle"
  (it refused the next order "busy: idle").
- The turtle factory: keeps the fleet at a size you choose, from AE2 parts; taught recipes.
- Mining teams (`miner.lua`, m25): one loader + up to 5 miners per mining dimension, updated
  from the base (`mine update`).

### Players and the world
- PLAYERS page: every player ever seen is remembered (also after a year): where they are,
  health, visits, time on the server.
- WORLD page (Environment Detector): game time, weather, moon, light, mobs around the base.
- Pocket remote (`pocket.lua`): paired and signed, status, rides, turtle orders, messages.

### The voice add-on (optional, on a data floppy: `voice install`)
- The base talks through Speakers: greetings, warnings, chat answers; slower, clearer speech,
  ready-made voices; answers come first.
- Hundreds of interactions: games, quizzes, jokes (100+ ways to say each thing), long
  conversations, what each player likes and how they play, server staff roles, friendship,
  badges and drone gifts from AE2.
- The spawn speaker (`spawn_speaker.lua` on a relay computer): its own voice and call word,
  item wishes delivered by drone, help for players who have never seen it, and a crowd mode
  (fights, duels, group quiz, roast battles) when many players are at spawn.
- The lonely base: when you are away a week or more it changes how it talks (stages that fit a
  6-month world), writes you letters, keeps a wall for visitors, lets caretakers you name help
  (permissions, all logged), can fly AFK players to the base by drone (only those who said yes),
  counts down to the next world reset (`voice reset <date>`) and gives you one report when you
  are back.
- Humble: call it a god or a lord and it says it is just a bot; call the owner one and they are
  just a regular player who had time to waste. No fortune telling.

### Upgrading from a version before 1.0.0
- Type `upgrade` on the base computer. If the voice add-on is installed, type `voice update`
  about 30 s after the restart.
- Mining turtles older than m21 need `miner.lua` copied by hand once; after that `mine update`.
