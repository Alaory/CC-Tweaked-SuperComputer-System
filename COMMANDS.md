# Command Reference

Every command of the base program, what it does and how to use it.

- `<word>` = put your own value there (no brackets): `turtle <id> log` -> `turtle 7 log`
- `[word]` = optional: `events [n]` -> `events` or `events 20`
- `a|b` = one of these: `survey auto on|off` -> `survey auto on`
- (owner) = only the owner may use it

Contents:
[Where you type what](#where-you-type-what) |
[Base console](#base-console) |
[Turtle commands](#turtle-commands-turtle-id-cmd) |
[Chat commands ($drone)](#chat-commands-drone) |
[Voice add-on](#voice-add-on-console-voice-) |
[Talking to the base in chat](#talking-to-the-base-in-chat) |
[At spawn](#at-spawn-the-spawn-speaker) |
[Other computers](#other-computers)

---

## Where you type what

| Where | How | Who |
|---|---|---|
| The base computer's keyboard | open the computer and type, e.g. `turtles` | anyone at the computer |
| Minecraft chat, commands | start with `$drone`, e.g. `$drone home` (the `$` hides it from others, replies are private) | the owner and allowed players |
| Minecraft chat, talking | start with the base's name, e.g. `base, status?` (needs the voice add-on) | everyone |
| The monitor | tap the buttons; risky ones need a second tap (CONFIRM?) | anyone at the monitor |
| The computer's screen, drag and drop | drag a file from your PC onto the open computer screen - also while the base runs (see [Dropping files](#dropping-files-onto-the-computer)) | anyone at the computer |
| The pocket computer | tap the buttons in `pocket.lua` | the paired pocket |
| A mining turtle / storage helper / pocket | its own shell commands, see [Other computers](#other-computers) | at that computer |

`help` on the base computer prints the short list. Most console commands answer on the screen;
some answers come later as a message on the monitor or in the turtle's log.

### Dropping files onto the computer

Open the base computer (right-click it) and drag files from your PC onto its screen. The base does
not need to be stopped. A message on the monitor says what happened:

| You drop | It goes |
|---|---|
| a Create schematic (`.nbt`, from `.minecraft/schematics`) | read and stored: on a storage helper first, else a data floppy, else the computer. Then `schem` lists it and DRONE WORK can build it |
| `base_*.lua`, `inventory.lua`, `startup.lua`, `upgrade.lua` | saved next to `inventory.lua` (the old one replaced) - restart the base to use it (SYSTEM > RESTART BASE) |
| `node.lua` | saved; the turtles get it by themselves (it is moved off the computer within a minute) |
| `store.lua` | saved; the storage helpers get it by themselves within a few minutes |
| `miner.lua` | saved; type `mine update` to send it to the mining turtles |
| a voice file (`voice_*.lua`) | not saved - type `voice update` instead (they live on a floppy / storage helper) |
| anything else | saved next to `inventory.lua` |

A file that does not fit on the computer is refused (it says how much room is left; the old file
stays). `upgrade` is still the easy way to get the newest files.

---

## Base console

### Program and system

| Command | What it does |
|---|---|
| `help` | the short list of commands |
| `version` | the program's release number and the GitHub commit `upgrade` installed |
| `upgrade` | gets the newest program files from GitHub (only the changed ones, each checked), then restarts. Your `base_config.lua` and data files are never touched |
| `upgrade check` | only shows what would change - nothing is written |
| `upgrade full` / `upgrade slim` / `upgrade packed` | from now on get the commented files / the smaller files without comments / the PACKED files (the default on the base: a third of the size, unpacked when the base starts) |
| `upgrade branch <name>` | take the files from another GitHub branch from now on |
| `parts` | blocks and data floppies the base saw and does not see now (broken, moved or their chunk is not loaded), and whether it has a screen |
| `parts forget <n\|name\|all>` | a missing part was taken away on purpose - not listed any more; a data floppy: its files are saved somewhere else again |
| `owner` | who the base thinks its owner is, and whether the Inventory Manager holds someone else's memory card |
| `owner new` | you changed accounts: the next memory card in the Inventory Manager becomes the owner's |
| `uptime` | how long the base has been running, and the last 10 times it was off (and why: crash, you stopped it, server restart) |
| `away` | away mode: is it on, is the owner online, the last WHILE YOU WERE AWAY report |
| `events [n] [errors]` | the last `n` saved messages (default a screenful), also from before a restart. `events 30 errors` = only warnings and errors |
| `theme [name\|random]` | the monitor's colours: `teal` (default), `amber`, `ice`, `violet`, `graphite`, `crimson`; `random` = a different one each start. No name = shows the current one |
| `report` | every connected block and all its functions -> `report.txt`, uploaded to pastebin (send the link when something does not work) |
| `report local` | the same, only saved to `report.txt` (no upload) |
| `disks` | floppies, storage helpers and the biggest files on the computer (it has only 1 MB) |
| `disks data` | makes empty floppies DATA floppies (one is kept for the turtle installer) |
| `disks move` | moves the map, logs, turtle and mining data onto the data floppies / storage helpers now |
| `store` | the storage helper computers (`store.lua`): free space, files; turns on helpers that are off |
| `store find` | looks for new storage helpers on the cable now |
| `store update` | sends a new `store.lua` (dropped next to `inventory.lua`) to every helper now |
| `chests` | every chest, barrel and tank on the cable: how full, and what the base uses it for |
| `env` / `world` | the Environment Detector: time, weather, moon, light, mobs around the base |
| `pocket` | the paired pocket computers |
| `pocket unpair <id>` | forgets a paired pocket |

### Drones

Pick a drone first (`drone <n>`), then give it a destination and a job.

| Command | What it does |
|---|---|
| `drones` | lists the drones (air, position, what they do) |
| `drone <n>` | chooses drone number `n` for the commands below |
| `dest <x> <y> <z>` | destination = those coordinates |
| `dest <place>` | destination = a saved place (`list` shows them; `Base` is always there) |
| `dest @<player>` | destination = where that player is (followed while the drone flies) |
| `dest me` | destination = where you (the owner) are |
| `fly` | flies the chosen drone to the destination |
| `home` | flies it back to the base / its charger |
| `pickup [player]` | picks a player up (default: the passenger chosen on the DRONES page) |
| `drop` | flies the passenger to the destination and lets them off |
| `ferry [player]` | pickup + drop in one go |
| `stop` | stops the drone now (not counted as a failure) |
| `release` | hands the drone back (lets a passenger off, idle again) |
| `status` | what the chosen drone is doing |
| `players` | online players and their positions |
| `charger` | shows the Charging Station's spot |
| `charger <x> <y> <z>` / `charger off` | moves it / no charger |

### Saved places

| Command | What it does |
|---|---|
| `save <name>` | saves the chosen drone's destination as a place |
| `save <name> <x> <y> <z>` / `save <name> me` / `save <name> feet` | at these coordinates / the block UNDER you / where your feet are. In chat: `$drone mark <name>` |
| `list` | shows the saved places |
| `del <name>` | deletes a saved place (`Base` cannot be deleted - it is `drone.home` in `base_config.lua`) |

### Who may use the drones

| Command | What it does |
|---|---|
| `allow <name>` | `<name>` may use `$drone` in chat (tied to their UUID on first use) |
| `deny <name>` | takes it away |
| `allowed` | shows the list |

### Turtles

| Command | What it does |
|---|---|
| `turtles` | every turtle: status (IDLE, WORKING, STUCK, OFFLINE ...), fuel, where, why it waits |
| `turtle <id\|name> <cmd> [args]` | sends a command to one turtle - see [Turtle commands](#turtle-commands-turtle-id-cmd) |
| `drive <id>` | steer a turtle with the keyboard: W A S D, SPACE up, SHIFT down, Q quits (or the DRIVE page) |
| `update` | turtle program versions; sends the newest program to every outdated online turtle now (busy ones install after their job) |
| `rescue <id> [<x> <y> <z> [radius]]` | sends the rescuer turtle to a lost / stuck turtle (default: its last known spot) |
| `findlost [radius]` | searches around the base for lost turtles and reinstalls them |
| `party` | SEARCH PARTY: every free turtle looks for the lost ones together; the rescuer brings them home |
| `party stop` | calls the search party back |
| `lost` | every offline turtle: a copy? enough fuel for the way home? last task, last spot, last log line |
| `forget base` | forgets turtles that went silent AT the base (picked up / broken - nobody is sent there) |
| `exit` | the turtles' saved exit route out of the base |
| `exit clear` | deletes the exit route |

### The map and surveys

| Command | What it does |
|---|---|
| `survey` | the big survey: progress, and what each turtle is waiting for |
| `survey stats` | scans per hour and where the turtles' time goes (surveying, trips, stuck ...) |
| `survey auto on\|off` | AUTO-MAP: turtles keep mapping from the base outward when no survey runs |
| `map` | saves the map, then shows its size and where its files are |
| `map clear` | deletes all map scans (cannot be undone) |

The survey area, corners and "survey in rings" are set on SETTINGS > MAP and the MAP page.

### Mining teams (mining dimension)

| Command | What it does |
|---|---|
| `mine` | every mining team: loader, miners, field, ores, offline units and where they were last |
| `mine drop <id>` | takes a lost miner (deleted by a server crash) out of its team so the team can go on |
| `mine forget <id>` | takes a mining turtle off the base's list |
| `mine update` | sends the newest `miner.lua` to every mining turtle (teams are paused first, then started again) |
| `mine update stop` | stops sending it |

### Turtle factory

| Command | What it does |
|---|---|
| `factory` | the parts it needs, what is missing, the status and the last try |
| `factory build` | tries again now (after 3 failures it waits for this) |
| `factory stop` | stops the job running now |
| `factory chest <name>` | the chest / barrel on the cable next to the builder (an EMPTY one) |
| `factory builder <id>` | which turtle builds (default: the rescuer) |
| `factory crafter <id>` | which turtle crafts taught recipes (it has a crafting table equipped) |
| `factory fuel <item> [count]` / `factory fuel reset` | the fuel a new turtle gets / back to the default (16 coal blocks) |
| `factory items [<item>]` | every version of an item in AE2 (default: the turtle) and whether it counts as plain or yours |
| `factory learn` | teach a recipe: put it in the crafter's 3x3 grid first |
| `factory recipes` | the taught recipes |
| `factory forget <item>` | forgets a taught recipe |

The fleet size is set on SETTINGS > FACTORY (0 = factory off).

### AE2 / ME network, fluids, curios

| Command | What it does |
|---|---|
| `mesetup` | finds the ME buffer chest - put ONE item in it first, then type this |
| `me check` | does the full ME item list work right now? (finds the item that breaks it) |
| `me add <item id>` | makes the AE2 page look up an item it does not list (partial view), e.g. `me add minecraft:diamond` |
| `me tags <item id>` | the tags AE2 reports for an item (and its Curios slots) |
| `me jobs` / `me cpus` | running crafting jobs / the crafting CPUs |
| `me cancel <item>` | cancels the crafting job for that item |
| `me raw` | each busy CPU's job exactly as the bridge gives it (for bug reports) |
| `tanks` | your fluid containers: contents and what they accept |
| `fluidbuffer` | which fluid storage AE2 fluids pass through, and the candidates (numbered) |
| `fluidbuffer <n\|name>` / `fluidbuffer auto` | use that one / choose by itself again |
| `fluidstop` | ends a big fluid ALL that is still moving |
| `curios check` | can your worn Curios items be read? |
| `curios probe` | what the Curios functions want (nothing is moved) |
| `curios auto` / `curios auto clear` | the AUTO-EQUIP rules (keep a totem on ...) / remove them all |

### Keep a storage filled (supply)

Keeps a chest or tank on the wired cable stocked from AE2. It only ever puts things in.

| Command | What it does |
|---|---|
| `supply` | the rules, and the storages on the cable (numbered) |
| `supply <n\|name> <item> <count>` | keep `count` of an item in that storage, e.g. `supply 2 minecraft:coal 64` |
| `supply <n\|name> fluid <fluid> <buckets>` | keep that many buckets, e.g. `supply 3 fluid minecraft:water 16` |
| `supply stop <n\|name\|all>` | stop keeping it filled |
| `supply now` | fill everything now |
| `supply every <seconds>` | how often it checks (0.2 - 600, default 1) |
| `supply check <n\|name>` | what that block is and which functions it has (for modded tanks) |

### Drone work (work chest, fuel runs, building)

| Command | What it does |
|---|---|
| `dw` | the drone work status: work chest, fuel runs, building |
| `dw chest` | the candidates for the work chest (EMPTY chests on the cable, numbered) |
| `dw chest <n\|name> <me\|x y z\|place>` | use that chest; its spot = the block under you / coordinates / a saved place |
| `dw test [item]` | tests the work chest end to end (one item AE2 -> chest -> AE2; with you near it, a drone drops it at your feet) |
| `dw fuel <id>` | a drone brings fuel to that turtle now |
| `dw fuel item <item> [n]` | the fuel drones bring, and how many per run |
| `dw auto on\|off` | drones bring fuel to turtles out of fuel by themselves |
| `schem` | the stored schematics and where each one is (drag a Create `.nbt` file onto the computer's screen to add one - a storage helper takes it first, so the full computer / floppies do not matter) |
| `schem <name>` | its size and materials |
| `schem delete <name>` | deletes it |
| `schem preview <name> [here\|place\|x y z] [facing <dir>\|turn left\|right\|around] [centered] [clear]` | only says where it would go and which way it faces |
| `schem build <name> [here\|place\|x y z] [facing north\|east\|south\|west \| turn left\|right\|around \| rot 90] [centered] [clear]` | drones build it. No place / `here` = in front of you (where you look, 2 blocks ahead, bottom at your feet); a place / x y z = the GROUND block it stands on (its north-west corner, or `centered`). `facing east` = the side that was north faces east. `clear` = dig the schematic's air spots first |
| `schem status` / `pause` / `resume` / `stop` | the build: how far / pause / go on / end |
| `schem craft [on\|off\|now]` | AE2 crafts the blocks a running build is short of (items with a pattern; on by default, checked every 30 s); `now` = ask at once |

### The voice add-on

`voice ...` - see [Voice add-on](#voice-add-on-console-voice-).

---

## Turtle commands (`turtle <id> <cmd>`)

Type `turtle`, the turtle's id or name, then the command. Your commands go first: a job the
turtle is doing is paused and comes back 2 minutes after your last command.

| Command | What it does |
|---|---|
| `turtle <id> log [n]` | its last `n` log lines in full |
| `turtle <id> diag` | its disk, files, saved job, gear, last save error (the answer is in its log) |
| `turtle <id> status` | what it is doing now |
| `turtle <id> ping` | is it there? (answers "pong") |
| `turtle <id> stop` | stops it now; it stays STOPPED (no automatic jobs) until you give it a command |
| `turtle <id> goto <x> <y> <z>` | goes there |
| `turtle <id> home` | goes home |
| `turtle <id> home dig` | goes home and may dig through natural blocks on the way (never near the base or its home) |
| `turtle <id> move <up\|down\|forward\|back\|left\|right> [n]` | moves `n` blocks, e.g. `turtle 7 move up 3` |
| `turtle <id> locate` | GPS: finds its position again |
| `turtle <id> setpos <x> <y> <z> <north\|east\|south\|west>` | tells it where it is and which way it faces (no GPS) |
| `turtle <id> sethome [<x> <y> <z>]` | its home = here / there |
| `turtle <id> refuel` | burns the fuel it carries |
| `turtle <id> scan [radius]` | scans around it for the map |
| `turtle <id> survey <x1> <z1> <x2> <z2> [radius]` | maps that area |
| `turtle <id> digup` | digs straight up to the surface (MINE UP on its card; natural blocks only) |
| `turtle <id> sweep <x> <y> <z> [radius]` | digs out an area around that spot (for rescues) |
| `turtle <id> anchor on\|off` | it stays put and keeps its chunk loaded (the ANCHOR) |
| `turtle <id> setting <name> <value>` | one of its settings, e.g. `turtle 7 setting dig true` |
| `turtle <id> forget` | takes a turtle that is gone for good (server crash) off the list - only when offline |
| `turtle <id> newchunky [off]` | a COPY turtle got a NEW Chunky upgrade: it may move again (`off` = undo) |
| `turtle <id> chunktest [stop]` | tests whether it loads its own chunk (pinged while nobody is near) |
| `turtle <id> core` | checks its End Automata Core |
| `turtle <id> warps` | the core's saved teleport points |
| `turtle <id> warp <name>` | teleports to a saved point (End Automata Core) |
| `turtle <id> warpsave <name>` | saves this spot as a point |

The turtle card on TURTLES has buttons for the common ones (HOME, STOP, LOCATE, MINE UP,
RESCUER, ANCHOR, FORGET ...).

---

## Chat commands (`$drone`)

Type them in Minecraft chat. The `$` hides the message from other players; the answers come
privately. Players who are not allowed only get `help` and ride requests (the owner says yes or no).

| Command | What it does |
|---|---|
| `$drone help` | lists the commands you may use |
| `$drone home` | a drone flies you to Base |
| `$drone to <place>` | a drone flies you to a saved place |
| `$drone to @<player>` | ... to a player (the owner, or everyone when allowed in `base_config.lua`) |
| `$drone back` | back to where you were before a big jump, or where you died |
| `$drone places` | the saved places |
| `$drone status` | what the drones are doing |
| `$drone stop` | stops your ride |
| `$drone allow <name>` / `$drone deny <name>` (owner) | who may ride without asking |
| `$drone allowed` (owner) | that list |
| `$drone yes <name>` / `$drone no <name>` (owner) | says yes / no to a ride request |
| `$drone notify on\|all\|off` (owner) | the monitor's messages in your chat: `on` = warnings and errors, `all` = everything |
| `$drone mark <name> [feet]` (owner) | saves a place: the block you stand ON (`feet` = where your feet are) |
| `$drone unmark <name>` (owner) | deletes a saved place |
| `$drone arrive [<x> <y> <z>\|off]` (owner) | the drones' ARRIVAL SPOT for an underground base: an open spot they can teleport to (where you stand); far trips teleport there, then fly in |
| `$drone workchest [<x> <y> <z>]` (owner) | the drones' work chest = the block you stand on (or those coordinates) |
| `$drone build [<name> [turn right\|facing east ...] [clear]]` (owner) | a schematic in FRONT OF YOU (look the way it should go): says where and which way it faces; then `$drone build turn left / right / around` or `facing <dir>` to turn it, `$drone build yes` to start (`no` = forget it, `stop`, `status`) |
| `$drone test [item]` (owner) | tests the work chest while you stand near it (a drone drops an item at your feet) |
| `$drone spawn here` (owner) | the spawn speaker's spot = where you stand |
| `$drone spawn pair <code>` (owner) | pairs the spawn relay computer (the code is on its screen) |

---

## Voice add-on (console `voice ...`)

The base talks through Speakers. All of these also work as `voice ...` on the base computer
only (not in chat).

### Install and basics

| Command | What it does |
|---|---|
| `voice` | its state: on / off, speakers, settings |
| `voice install` | downloads the add-on onto a data floppy / storage helper (needs http) |
| `voice update` | gets the newest add-on files (also done by itself after `upgrade`) |
| `voice remove` | removes the add-on |
| `voice on\|off` | it talks / it is quiet |
| `voice say <text>` / `voice test` | says that / says a test line |
| `voice name <word>` | what players call it in chat (one word, default `base`) |
| `voice volume <0-3>` | how loud |
| `voice range <blocks>` | how far from the base a player counts as "at the base" (without an Environment Detector) |
| `voice detector on\|off` | who is at the base comes from the Environment Detector (on) or the Player Detector |
| `voice scan <seconds>` | how often the Environment Detector looks (its cooldown is 2 s) |

### How it sounds

| Command | What it does |
|---|---|
| `voice presets` / `voice voices` | the ready-made voices (standard, deep, british, bright, narrator, robot, tiny) |
| `voice try [name]` | says a line in each voice (or in that one) |
| `voice preset <n\|name>` | keeps that voice |
| `voice speed <50-100>` | slower or faster (percent, default 80) |
| `voice pitch <70-140>` | lower or higher (percent) |
| `voice accent <voice>\|off` | another speech voice, e.g. `voice accent en-gb` |
| `voice clear on\|off` | makes quiet sounds louder and pauses longer (clearer in Minecraft) |
| `voice pause <ms>` / `voice gap <ms>` | extra time at commas and full stops / on short silences (0 = off) |
| `voice sayas <word> <how>` | how it says a word, e.g. `voice sayas AE2 A E two`; `voice sayas <word> off` removes it |
| `voice timing` / `voice timings` | how long the last answers took (and the server speed) |
| `voice bench` | times one fresh line step by step |

### What it says

| Command | What it does |
|---|---|
| `voice greet on\|off` | greetings when players arrive |
| `voice announce all\|summary\|errors\|off` | the monitor's messages out loud (`summary` = errors at once, warnings as one line every 15 min) |
| `voice chat on\|off` | answers to questions in chat |
| `voice fun on\|off` | reactions, small talk, jokes, games |
| `voice chatter <minutes>` | how often it makes small talk (0 = never) |
| `voice alarm on\|off` | a bell for strangers and monsters near the base (off by default) |
| `voice modchat on\|off` | comments when players near the base talk about mods |
| `voice joke` | tells a joke now |
| `voice lonely <days>` | after how many days without you it acts lonely to visitors (0 = never) |
| `voice message <text>` | a message for whoever finds the base while you are away (empty = remove it) |
| `voice visitors` | who visited while you were away |
| `voice listen on\|off` | remembers what players say about you while you are offline |
| `voice listen tell on\|off` | says out loud "I will pass it on" when it hears it |
| `voice heard [clear]` | what players said about you (shown ones are deleted) / delete all |
| `voice reminders [clear]` | every player's reminders (and when) / forget them all |
| `voice nick <a,b,...>` | your other names it should listen for |
| `voice forget` | forgets every player it met (your message for visitors and the visitor list stay) |

### Players

| Command | What it does |
|---|---|
| `voice likes <player>` | what it remembers a player likes |
| `voice profile <player>` | how a player plays (what they love, what gets in their way) |
| `voice staff` | the server staff list |
| `voice staff add <name> <role> [role ...]` | e.g. `voice staff add Steve admin builder` (roles: admin, mod, maintainer, builder, helper, staff) |
| `voice staff remove <name> [role]` | takes one role / all roles away |
| `voice gifts` | waiting gifts and why each one waits |
| `voice gifts list` | the rewards and what each gives |
| `voice gifts on\|off` | friendship gifts by drone |
| `voice gifts now` | tries to send the waiting gifts now |
| `voice gifts give <name> <item> [count]` | sends a gift, e.g. `voice gifts give Steve diamond 16` |
| `voice gifts block <name>` / `unblock <name>` | that player gets no gifts / gets them again |
| `voice gifts clear` | empties the gift queue |
| `voice crowd [on\|off]` | the crowd mode at spawn (fights, duels, group games) |

### While you are away (the lonely base)

When you have been offline `voice lonely` days (default 7) the base changes: its own greetings and
talk for each stage (missing you, worried, lonely, keeper, legend), a mood, letters to you, and
things for visitors to do. Caretakers you name may help while you are away. Everything fits in a
6-month world (the stages are 7 / 14 / 30 / 60 / 120 days, milestones up to day 175); with the reset
date set it counts down to the new world.

| Command | What it does |
|---|---|
| `voice lonely <days>` | after how many days away it acts lonely (0 = never) |
| `voice reset <yyyy-mm-dd>` | the date the server starts a new world, e.g. `voice reset 2027-05-01`: it counts down (idle talk, greetings and letters in the last weeks, a goodbye on the last day) |
| `voice reset every <months>` | after the date it moves on by this much (default 6; 0 = only that date) |
| `voice reset off` / `voice reset` | no date / show the next reset |
| `voice caretaker` | the caretakers, their permissions, and whether they count right now |
| `voice caretaker add <name> [perm ...]` | e.g. `voice caretaker add Steve turtles supplies`. Permissions: `status` (where the turtles are + a report), `guard` (told in chat when a stranger is at the base), `taxi` (the free drone taxi), `supplies` (a few items from AE2 by drone), `turtles` (stop / call home every turtle), `wall` (tidy the wall), `all`. No names = status, guard, taxi |
| `voice caretaker remove <name> [perm]` | takes one permission / all of them away |
| `voice caretaker after <days>` | caretakers may act once you are away that long (default: the lonely days; 0 = whenever you are offline) |
| `voice caretaker log` | what caretakers did, strangers who came, AFK rescues |
| `voice memory` / `voice memory add <text>` | stories about you that visitors hear while you are away / add one |
| `voice memory remove <n>` / `voice memory clear` | remove one / all |
| `voice afk off\|ask\|everyone` | AFK rescue: `ask` (default) = only players who said yes; `everyone` = everyone who did not say no; `off` |
| `voice afk after <minutes>` | how long a player stands still before it counts as AFK (default 10) |
| `voice afk when lonely\|always` | only while the base is lonely (default) / whenever you are offline |

### The spawn speaker (`voice spawn ...`)

| Command | What it does |
|---|---|
| `voice spawn` / `voice spawn status` | paired? online? where, settings, sound sender running |
| `voice spawn here` | its spot = where you stand (same as `$drone spawn here`) |
| `voice spawn at <x> <y> <z>` | its spot = those coordinates |
| `voice spawn pair <code>` | pairs the relay computer (the code is on its screen) |
| `voice spawn update [force]` | the newest spawn_speaker.lua from GitHub to the relay (v4+ installs it itself and restarts; `voice update` does it too) |
| `voice spawn unpair` | forgets the relay computer |
| `voice spawn on\|off` | talks at spawn or not |
| `voice spawn name <word>\|off` | its own call word at spawn / the base's word again |
| `voice spawn range <blocks>` | how far from its spot counts as "at spawn" (default 24) |
| `voice spawn voice <preset>` | its own voice (default `bright`) |
| `voice spawn volume <0-3>` | how loud |
| `voice spawn chatter <minutes>` | how often it talks by itself |
| `voice spawn greet on\|off` | greetings at spawn |
| `voice spawn say <text>` | says that at spawn |
| `voice spawn wish` | the wish rules |
| `voice spawn wish on\|off` | item wishes by drone |
| `voice spawn wish daily <n>` / `all <n>` / `max <n>` | wishes per player a day / for everyone a day / items per wish (64 at most) |
| `voice spawn wish keep <percent>` | how much of every item always stays in AE2 (default 50; the most it had in the last 30 days counts, rounded up - 1 elytra = none, 3 = 1) |
| `voice spawn wish block <item>` / `unblock <item>` | an item nobody may wish for / allowed again |

---

## Talking to the base in chat

With the voice add-on, players talk to the base in normal chat (no `$`). Start with its name
(`base` unless you changed it with `voice name`), or `bot` / `computer`. Away from the base only
messages that START with its name count. It answers questions only - it never does anything on
a stranger's word.

| Say | You get |
|---|---|
| `base, status?` | how the base is doing (turtles, mining, map, warnings) |
| `base, where is turtle 7?` | how far and which way, what it is doing |
| `base, what time is it?` / `weather?` / `who is online?` | the answer |
| `base, hi` / `base, how are you?` / `base, let's talk` | a conversation (it asks questions and remembers your answers) |
| `base, tell me a joke` / `fact` / `riddle` / `roast me` / `compliment me` / `tell me a story` | one of hundreds |
| `base, let's play` / `quiz` / `hangman` / `guess my number` / `rock paper scissors` / `would you rather` | a game |
| `base, remind me in 10 minutes to check the farm` | a reminder (also `in 2 hours`, `tomorrow`, `next time`; said in chat when you are online - one due while you are off waits for you) |
| `base, remind me <something>` | no time given: it keeps the text and asks when - answer `in 30 min`, `tomorrow`, `next time` or `no` |
| `base, my reminders` / `base, forget my reminders` | your reminders / forget them all |
| `base, remember <text>` / `my notes` / `forget my notes` | notes it keeps for you |
| `base, call me <name>` / `my birthday is 14 march` / `my favourite mob is the axolotl` | it remembers |
| `base, who am I?` / `who is Steve?` / `what do you know about me?` | what it knows (never where anyone is) |
| `base, about me: I build castles` | what it tells others who ask about you |
| `base, tell Steve that the farm is done` | mail, given to Steve when he comes to the base |
| `base, how do I make a piston?` / `what is a beacon?` / `give me a mod tip` | recipes, the glossary, modpack tips |
| `base, what did people say about me?` (owner) | what players said while you were away |
| `base, how many diamonds do we have?` (owner and friends) | the AE2 count |
| `base, take me home` / `take me to the base` (friends) | the free drone taxi between the base and your bed |
| `base, shh` / `base, be quiet for 2 hours` / `base, talk to me` | quiet for 30 minutes (or as long as you say, up to a day) / talks again |
| `base, roll a d20` / `roll 2 dice` / `flip 3 coins` / `pick a number from 1 to 10` | dice, coins, numbers as asked |

While you are away (the lonely base), visitors and caretakers can also say:

| Say | You get |
|---|---|
| `base, write on the wall <words>` / `base, read the wall` | a note everyone who comes here reads (3 a day) / the newest notes |
| `base, tell me a memory` | a story about the owner |
| `base, what are you thinking?` / `how do you feel?` / `did you dream?` | what the lonely base thinks, feels and dreams about |
| `base, how long has it been?` | the days without the owner |
| `base, when does the world reset?` (anyone, any time) | the date of the next new world and how many days are left |
| `base, I have news` | it asks for your news and tells the owner |
| `base, afk yes` / `base, afk no` | a drone may / may never fly you to the base when you go AFK far away |
| `base, stay` | the drone that was about to pick you up does not come |
| `base, take me back to where I was` | after an AFK pickup: a ride back (2 hours) |
| `base, stop messaging me` | it never messages you again ("come and visit me?") |
| `base, am I a caretaker?` (caretakers) | your permissions |
| `base, stop all turtles` / `all turtles home` (caretakers with `turtles`) | stops / calls home every turtle |
| `base, caretaker report` / `where is turtle 7?` (caretakers with `status`) | turtles online, problems, strangers today / where a turtle is |
| `base, I need 32 torches` (caretakers with `supplies`) | a drone brings them from AE2 (5 requests a day, 64 each) |
| `base, make Steve a caretaker` / `Steve is not a caretaker` (owner) | the same as `voice caretaker add / remove` |
| `base, read my letters` / `news` / `caretaker log` / `clear the wall` (owner) | the letters it wrote you, news from visitors, what happened, a clean wall |
| `base, remember for visitors <text>` (owner) | the same as `voice memory add` |

Typos and chat shorthand (`u`, `wat`, `pls` ...) are understood. Not understood -> a numbered
menu; answer with the number.

---

## At spawn (the spawn speaker)

Players at spawn talk to it the same way, with its spawn call word or `speaker` / `bot`. There
are no rewards or friendship at spawn.

| Say | You get |
|---|---|
| `speaker, help` / `how do I use this?` | how to talk to it, with examples |
| `speaker, I wish for 16 torches` | asks "yes?", then a drone brings them from AE2 (a few wishes a day, at most 64 each) |
| `speaker, how do I wish?` | how wishes work and how many you have left today |
| `speaker, take me to Steve` | maybe a drone ride to that player (if it feels like it) |
| `speaker, duel Steve` / `1v1 Steve` | a refereed duel: countdown, the first one down loses, 3 minutes = a draw |
| `speaker, group quiz` | 5 questions for everyone at spawn; the first right answer scores (needs 2+ players) |
| `speaker, roast battle Steve` | a roast for each, then the crowd votes `1` or `2` |
| `speaker, scoreboard` | wins, knockouts and quiz points this session |
| `speaker, hype` | cheers the crowd on |
| anything from the chat list above | the same answers (jokes, games, questions ...) |

---

## Other computers

### Pocket computer (`pocket.lua`)

| Command | What it does |
|---|---|
| `pocket` | starts the remote; the first time it pairs (type the code shown on the monitor) |
| `upgrade` | gets the newest `pocket.lua` from GitHub |

Everything else is tapping: HOME, RIDE, BOTS, MINE, MSG tabs.

### Mining turtles (`miner.lua`)

| Command | What it does |
|---|---|
| `miner` | starts it; the first time it asks role (loader or miner), key, position and facing |
| `miner setup` | asks everything again |
| `miner here` | the turtle was moved: type its new position |
| `miner station` | (miner) THIS spot is its unload station - stand it on the station first |

After that: START / PAUSE / UNLOAD / NEW FIELD on TURTLES > MINING, `mine update` for new versions.

### Storage helper computers (`store.lua`)

| Command | What it does |
|---|---|
| `store` | starts it (it starts by itself after that) |
| `store reset` | frees it from the base that uses it, so another base may |

### Spawn relay computer (`spawn_speaker.lua`)

Save it as `startup.lua` on a computer at spawn with a Speaker and an Ender Modem, and restart.
It shows a 6-digit code; pair it with `$drone spawn pair <code>` while standing there. No
commands of its own.

### Turtles (`node.lua`)

Nothing to type: turtles get their program from the install floppy or from the base, and every
command comes from the base (`turtle <id> ...`, the TURTLES page, the pocket).
