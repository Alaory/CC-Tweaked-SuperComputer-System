# CC:Tweaked Base Control

**One computer and one big monitor that run your whole Minecraft base:** your
inventory, players, backpacks, curios, an AE2 network, drone rides, a team of
mapping turtles and a map of the world.

> Made for **CC:Tweaked 1.120.2** on **Minecraft 1.21.1 (NeoForge)** with
> **Advanced Peripherals** · optional: **PneumaticCraft**, **AE2 / Refined Storage**, **Curios**

---

## Contents

- [What it does](#what-it-does)
- [What you need](#what-you-need)
- [Installation](#installation)
- [Updating](#updating)
- [Configuration](#configuration)
- [Turtles](#turtles)
- [Drones](#drones)
- [ME / Curios](#me--curios)
- [While you are away](#while-you-are-away)
- [Turtle factory](#turtle-factory)
- [Pocket remote](#pocket-remote)
- [Schematics (builder turtles)](#schematics-builder-turtles)
- [Mining dimension teams](#mining-dimension-teams)
- [The map](#the-map)
- [Chat commands](#chat-commands)
- [Console commands](#console-commands)
- [Themes & the message log](#themes--the-message-log)
- [Tips & troubleshooting](#tips--troubleshooting)
- [Files](#files)

---

## What it does

The monitor starts on **HOME**: a status line, every page as a big button with a line saying
what it is for, and **quick actions** (stop all turtles, all home, update turtles, find lost
turtles, a drone ride to the base, save the map - each needs two taps).

The top row has the tab groups; a group with several pages shows them as small tabs under it.

| Tab | Pages | What you get |
|---|---|---|
| **HOME** | | Everything at a glance, every page one tap away, quick actions. |
| **YOU** | Inventory · Backpacks · Curios | Your inventory, armour and item list · what is inside your backpacks and tanks · your curios: store in ME, put on from ME, **auto-equip** (keep one on). |
| **AE2** (or **RS**) | | Network status, item / fluid browser, take and store items, fill fluid containers, craft. |
| **PLAYERS** | Players · Chat & rides | A card per online player (dimension, health, position) · who may use the `$drone` chat commands, ride requests, the base's messages in your chat. |
| **DRONES** | | PneumaticCraft drones: air, mission steps, log. Pick a passenger and a destination, then fly, pick up, drop or ferry. |
| **TURTLES** | Turtles · Drive · Map · Mining | Every turtle with status, fuel, gear, log and a control pad; the **FLEET** card when none is selected · **steer one turtle by hand** and see the blocks around it · the terrain map: zoom 1-512 blocks per cell, surveys, **AUTO-MAP** · the mining teams. |
| **SYSTEM** | Status · Messages · Settings | How the base is doing, a **system log**, the times it was off, UPGRADE PROGRAM · every message (kept after restarts) · **settings** you change by tapping (saved in `settings.dat`; your `base_config.lua` stays as it is). |

A tab only shows up when the block it needs is connected.

**Messages:** warnings and errors pop up as small boxes in the bottom-right corner; everything
else goes to SYSTEM > Messages (and `events.log`). What you just tapped always gets a box.
If you want, messages are also sent to you privately in chat.

---

## What you need

### Required

- A **Computer** (CC:Tweaked)
- A big **Advanced (gold) Monitor**. If it is too small, the screen tells you.
- An **Inventory Manager** (Advanced Peripherals) with a **Memory Card** bound to you

### Optional: each one adds features

| Block | Adds |
|---|---|
| Player Detector | PLAYERS tab, finding players for drone rides |
| Environment Detector | which dimension the base is in |
| ME Bridge / RS Bridge + a buffer chest | ME / RS tab |
| Drone Interface (one per drone) + Charging Station | DRONES tab |
| Chat Box | `$drone` chat commands, CHAT tab, messages in chat |
| Ender Modem (or Wireless Modem) on the computer | TURTLES and MAP tabs |
| Disk Drive + floppy | turtle install floppy, extra room for the map |

> **Connecting the blocks:** blocks can touch the computer, or sit anywhere on a
> **wired network**. For that, put a Wired Modem on each block and on the computer,
> connect them with Networking Cable, and right-click every modem so it turns on.

---

## Installation

### 1. The base computer

On the computer, make a folder and get the updater and a settings file (http must be on):

```
mkdir controller
cd controller
wget https://raw.githubusercontent.com/Alaory/CC-Tweaked-SuperComputer-System/main/upgrade.lua upgrade.lua
wget https://raw.githubusercontent.com/Alaory/CC-Tweaked-SuperComputer-System/main/base_config.lua base_config.lua
upgrade
```

`upgrade` downloads every program file, checks each one and restarts the computer.
(No internet on the server? Copy `inventory.lua`, every `base_*.lua`, `node.lua`, `store.lua`
and `startup.lua` by hand instead - drag the files onto the computer's screen.)

1. Open `base_config.lua` and set at least:
   - `turtles.key`: a secret word of your own (not `"change-me"`). Turtles
     installed from the install floppy or updated by the base get it
     automatically; if you copy `node.lua` onto a turtle by hand, put the same
     key in it.
   - `drone.home`: your "Base" - where drone riders are dropped off, where turtles meet,
     and the middle of the **no-digging zone**
   - `drone.charger`: the drone Charging Station
2. Start it:
   ```
   controller/inventory
   ```
   If a file is missing, it lists the missing files.
3. **Autostart (recommended):** `startup.lua` belongs at the **top level** of the
   computer, not in the folder (`upgrade` puts it there). The program then starts by
   itself and comes back after a crash. Ctrl+T stops it.

### 2. Turtles

1. Equip each turtle with a **Chunky upgrade** and an **Ender Modem**. A Wireless
   Modem only reaches about 64 blocks.
2. Put the **install floppy** in the Disk Drive *under* the computer: the base
   writes the installer onto it at once. Put a new turtle next to a Disk Drive
   with that floppy and turn it on. That's it.
   *Or* copy `node.lua` onto the turtle as `startup.lua`.
3. Name it: `label set Scout1`.
4. Without GPS, tell it once where it is (on the base computer):
   `turtle <id> setpos <x> <y> <z> <north|south|east|west>`
5. For mapping, put a **Geo Scanner** (as an item) in its inventory.

A new turtle refuels by itself and gets a home by itself (see [Turtles](#turtles)).

### Extra storage: helper computers (optional)

Each extra computer gives the map **1 MB** more (about 8 floppies):

1. Put a computer near the base, **in the same chunk if you can** (it must stay
   loaded), with a **Wired Modem** connected to the base's cable. Right-click
   the modem so it turns on.
2. Copy `store.lua` onto it and run `store` once. It then starts by itself.
3. On the base computer, type `store find`. The map uses the helpers when the
   data floppies are full.

A helper belongs to the first base that uses it (`store reset` on the helper
changes that) and only listens on wired modems.

**Updating helpers:** nothing to do - after the base was upgraded, every helper gets the
new `store.lua` by itself within a few minutes and restarts (`store update` on the base
computer does it at once).

### 3. ME network

Put **one** item in the buffer chest and type `mesetup` on the computer. It finds
the chest by itself and remembers it.

### 4. Drones

Program a PneumaticCraft drone with a ComputerCraft puzzle piece whose area
contains the Drone Interface, and launch it. The DRONES tab shows it as
connected. After each mission it parks on its Charging Station.

---

## Updating

| What | How |
|---|---|
| The base | Type `upgrade` on the base computer (or SYSTEM > Status > **UPGRADE PROGRAM**). Only changed files are downloaded; each is checked (size, checksum, it compiles) before anything is written. Your `base_config.lua` and data files are never touched. `upgrade check` only shows what would change. |
| Turtles | They get the new `node.lua` from the base by themselves - while you are **offline** (an update restarts them), or at once with **UPDATE TURTLES**. A busy turtle installs it after its job. A full disk never breaks a turtle: the update is then refused and the old program keeps running. |
| Pocket | Type `upgrade` on the pocket computer. |
| Storage helpers | By themselves, a few minutes after the base was upgraded (`store update` does it at once). |
| Mining turtles | Copy `miner.lua` onto them by hand **once** (m21 or newer). After that: `mine update` on the base computer (or **UPDATE MINERS** on TURTLES > MINING). The base downloads `miner.lua`, keeps it on a data floppy (not on the computer's 1 MB), pauses each running team, sends the program to every loader and miner, and starts the team again once all of them run it. Each turtle installs it only while paused and keeps its team, field, job and unload station. |

The files you get have their comments removed (about 30% smaller - a computer has only 1 MB);
the commented ones stay on GitHub. `upgrade full` gets the commented files, `upgrade slim`
goes back. `upgrade branch <name>` follows another branch.

---

## Configuration

All settings are in **`base_config.lua`**, and most can also be changed by tapping on
**SYSTEM > Settings** (those are saved in `settings.dat`; `base_config.lua` is never changed
by the program or by `upgrade`).

The settings you will most likely touch:

| Setting | What it does |
|---|---|
| `turtles.key` | The shared secret between the base and the turtles. **Change it.** |
| `turtles.fuelChest = { x=…, y=…, z=… }` | A chest with fuel that every turtle may use (see below) |
| `turtles.lowFuel` | Below this much fuel a turtle goes refuelling (default 2000) |
| `turtles.idleHome` | Seconds idle before a turtle goes home (default 120, `0` = off) |
| `turtles.rescueAfter` | Seconds silent before the rescuer goes to wake a turtle up (default 180) |
| `turtles.noDigBase` | Nothing is ever dug this close to the base (default 96 blocks, x and z) |
| `turtles.atBaseRange` | Turtles that went silent this close to the base count as picked up, not lost (default 1024, 0 = off) |
| `turtles.avoidRange` / `turtles.avoidWho` | Keep away from players this close (default 100, 0 = off) / `"strangers"` (not you, not the allow list) or `"everyone"` |
| `drone.home` / `drone.charger` | Base drop-off point / Charging Station |
| `drone.travel` | `"teleport"` (best for underground bases) or `"fly"` |
| `me.curiosChest` | An **empty** barrel used only for curios moves (see below) |
| `map.up` | Which way is up on the map (`"north"`, `"east"`, `"south"`, `"west"`) |
| `map.computerKB` | How much of the computer's disk the map may use (default 200) |
| `chat.command` | The chat command word (`$drone …`) |
| `theme` | Fix the monitor's colours, e.g. `theme = "bedrock"` (default: a random one on every start) |
| `names.*` | Pick one block by its network name when you have several of a kind |

> Many settings can also be changed while the program runs: `charger`, `theme`,
> `turtle <id> setting <name> <value>` (a turtle's own settings).

---

## Turtles

Turtles fly to places, scan the terrain for the map, find their way around
obstacles, and share what they learn (walls, dead ends, the exit route out of the
base) through the base.

### Homes

- **SET HOME** on one turtle. Every turtle without a home is then offered one
  **next to it** (one block over on X or Z). The turtle checks the spot the first
  time it goes there. If the block is not free, it gives it back without digging
  and gets the next one.
- A turtle **with nothing to do for 2 minutes goes home**, so it does not keep a
  far-away chunk loaded for nothing. A turtle you stopped, the anchor and stuck
  turtles stay where they are.

### Fuel

| How | What happens |
|---|---|
| New turtle | It fills up to 1000 by itself on its first start, moves out of the way, and tops up the rest wherever it waits. |
| Reusable fuel | A fuel item that is never used up (some mods have one) is recognised and kept. The turtle tops up from it whenever it is idle. |
| **Shared fuel chest** | Set `turtles.fuelChest`. A turtle low on fuel parks **on top of the chest**, takes only fuel (coal, charcoal, coal blocks, blaze rods, lava, or reusable fuel), and flies home. **One turtle at a time**; the others wait. |
| Chest at home | A chest under, above or in front of a turtle's home works the same way. |
| Energy cells | A turtle with an Advanced Peripherals automata core turns the energy in a charged item it carries into fuel, before anything else. |

> Keep the block **on top of** the fuel chest free. Put one reusable fuel item
> per turtle in it: each turtle keeps one, and never runs dry while it can idle.

### Rescue, anchor and stop

- ** ANCHOR:** one turtle parked in the base computer's chunk keeps the base
  running while you are offline.
- ** RESCUER:** a permanent rescue turtle. It flies to a turtle that has gone
  silent (for example an unloaded chunk: arriving wakes it up), that is stuck, or
  that has no fuel. It goes home afterwards.
- ** SEARCH PARTY** (FIND LOST on HOME, the FLEET card or the pocket): all free turtles
  meet at the base, fly over the sky highway to each lost turtle in turn, drop down to just
  above the ground and scan. A turtle they find is fetched by the rescuer (one at a time); one
  that wakes up when they arrive counts as found; one that is gone is marked **MISSING**.
  Their scans also go onto the map.
- **Lost near the base:** a turtle that went silent within 1024 blocks of the base was most
  likely picked up or broken - no rescue goes there. **FORGET THEM** on the FLEET card
  (or `forget base`) clears them.
- ** STOP** really stops a turtle, also after its chunk was unloaded and loaded
  again. A stopped turtle shows **STOPPED** and is left alone by automatic jobs.
  Any button (for example PING) makes it normal again.
- ** Your commands go first:** a button, pocket or console command to a busy turtle pauses
  its trip or survey, runs yours at once, and the turtle goes back to its job 2 minutes after
  your last command. A build, a craft or a rescue is never cut halfway - it finishes first.
- **Keeping away from players:** a surveying turtle with another player within
  100 blocks (Player Detector) stops and goes home; survey spots near that player
  wait until they leave. You and your allow list are ignored (SETTINGS > TURTLES).
  Visitors at your base don't stop turtles leaving or coming home.
- **Copies after a server crash:** a crash can leave several turtles with one ID. The base
  notices, keeps the real one and gives each copy its own name (`Name [c1]`) and number, so
  they work as turtles of their own (SETTINGS > TURTLES can park them instead).

### Digging

Turtles only dig with a pickaxe they carry, only **natural** blocks (stone, dirt, sand,
leaves, ores ... never bricks, planks or polished blocks), and only when "Turtles dig through
natural blocks" is on (SETTINGS > TURTLES) or on a rescue. **Nothing is ever dug within 96
blocks of the base** ("No digging around the base") or near a turtle's own home - no job
overrides that. Only DIG ANYWAY on the DRIVE page digs there, by your hand.

### Driving a turtle by hand

**TURTLES > Drive:** pick a turtle and see the blocks above it, at its level and below it.
Tap a block next to it to go (and dig) there, or use the buttons: turn, forward, up, down,
scan around, go home, mine up to the surface. `drive <id>` on the computer and DRIVE IT on
the pocket do the same with the keyboard (W A S D, SPACE, SHIFT).

### When a turtle misbehaves

| Command | Shows |
|---|---|
| `turtle <id> log 15` | its last 15 log lines in full |
| `turtle <id> diag` | disk space, file sizes, saved job, how often it restarted, gear |
| `turtles` | all turtles with fuel, position and gear |

A turtle's answers appear in **its log**, on the TURTLES tab or with `turtle <id> log`.
If a turtle restarts, its log says why: "started by the game (chunk loaded
again …)", "after an update" or "after an ERROR: …".

---

## Drones

- They **teleport** (or fly) to players and places. They pick a player up, carry
  them, and drop them at the destination.
- **Overworld only**, for players and places alike.
- Every teleport costs air, so missions check the air first. Long trips go in hops
  (shorter hops where the area ahead is not loaded).
- **Who is on board is asked from the drone itself** - after the pickup, before every move
  and after letting go. It comes in above your head (not beside you, where it pushed you).
- **A moving target is followed:** on the way to a player or a turtle the drone goes to
  where they are *now*, also when they moved on while it was flying.
- If **you get off during a ride**, the drone notices and goes straight home.
- If it cannot let you off at the destination, it **stays there with you** (press DROP again,
  or sneak to get off) - it never flies home with someone still on board.
- If the flight itself fails with a passenger on board, the drone brings them back to Base.

---

## ME / Curios

- **Exact amounts only:** the program only moves exactly what you asked for, plus
  what it put into a buffer itself. The one exception is the BUFFER → ME button.
- **Curios:** some Advanced Peripherals versions can only take off **all** items
  of a slot type at once, and put on **any** fitting item. For rings, charms and
  other slot types with several items, set an **empty barrel used only for curios**:
  ```lua
  me = {
    curiosChest = "minecraft:barrel_2",   -- its network name
  },
  ```
  `curios probe` shows what your version wants. Every curios move is listed on
  SYSTEM > Messages.
- **Auto-equip:** on the CURIOS tab, **AUTO** next to an item (or **KEEP ONE ON** on one you
  wear) makes the base put a new one on from AE2 whenever it is gone - a used totem, for
  example. `curios auto` lists the rules. An empty slot lists what fits; SHOW ALL lists
  everything in AE2.
- **Keep a storage stocked (`supply`):** put a **wired modem** on any chest, barrel, drawer or
  tank, right-click the modem (it turns red), then on the base computer:
  - `supply` lists the storages on the cable (with numbers) and what is kept stocked.
  - `supply 1 coal 128` keeps 128 coal in storage 1. `supply 2 fluid water 16` keeps 16 buckets of water.
  - `supply stop <n|all>` stops a rule. `supply now` checks at once.
  - Not listed? `supply` also shows **other blocks** on the cable; `supply check <n>` lists what one
    offers. Not there at all: the wired modem on it is off (right-click it, it turns red).

  Every 10 s the base counts what is in it and sends the difference from AE2. It only ever puts
  things **in**, never takes anything out, and never sends your own enchanted, renamed or used
  items. If AE2 runs out, you get one warning. The base's own buffers can't be used.
  Fluids for your own tanks pass through ONE fluid storage (the fluid buffer, normally your
  storage controller). With several fluid storages on the cable, `fluidbuffer` shows which one;
  `fluidbuffer <n>` picks it.
  A wireless or ender modem can't do this: it only carries messages, so the storage has to
  be on the cable.

---

## While you are away

5 minutes after you leave the server (Player Detector), the base uses the time:
- turtle program **updates** (they wait while you play - at most 2 h; UPDATE TURTLES forces them)
- turtles **top up their fuel** early, so they are full when you are back
- the monitor shows the **map**, zoomed out by itself, following the turtles; **auto-map** runs even if you switched it off (off again when you are back)
- the map is saved every 30 minutes

When you come back: a **WELCOME BACK** box, a private chat message, your pocket remote and the SYSTEM tab tell you
how long you were away, what was mined and mapped, what the factory built, which turtles were
found again or marked MISSING, what went wrong and what needs you now.
Type `away` on the computer to see it again. Settings: SETTINGS > AWAY.

## Turtle factory

The base keeps your fleet at the size you choose (**SETTINGS > FACTORY**, "Keep this many
turtles"; 0 = off). Turtles that went **MISSING** (deleted by a server crash) are replaced.
- It checks AE2 for an Advanced Turtle, Ender Modem, Geo Scanner, Chunky upgrade, diamond
  pickaxe and fuel (16 coal blocks, or what you choose with `factory fuel <item> [count]`);
  what is missing is **crafted by AE2** (if you have a pattern - `factory` lists what has
  none). It never takes your own enchanted / renamed / used items.
- **No pattern? Teach it:** a turtle with a crafting table (the *crafter*, home next to the
  factory chest) learns a recipe when you lay it out in its inventory and tap "Teach a
  recipe" (`factory learn`). The factory then crafts that part with it.
- The parts go into the **factory chest** (an empty chest or barrel on the cable, next to
  the builder); the **builder** (your rescuer, or the turtle you choose) places the new
  turtle, gives it the parts and starts it from the install floppy.
- The new turtle moves off the build spot by itself; the next build waits until it has. The
  build spot needs a free way out (turtles do not dig there) - if it cannot leave, the base
  tells you why.
- The builder and the crafter stay at the factory: no survey work, no search party.

## Pocket remote

Copy `pocket.lua` onto an **Advanced Pocket Computer with a modem** (an **Ender** modem
reaches the base from anywhere) and run `pocket`. The monitor shows a 6-digit code; type it
on the pocket - paired. Then, by tapping:
**HOME** (turtles, mining, factory, survey) · **RIDE** (a drone takes you to the base, a place,
or back where you died) · **BOTS** (STOP / HOME / GPS / FORGET / DRIVE IT; STOP ALL, ALL HOME, FIND LOST TURTLES) ·
**MINE** (START / PAUSE / UNLOAD / DROP) · **MSG** (the base's warnings, live) ·
**+** (work-area corners where you stand, survey around you, factory).
`pocket` on the base lists paired pockets, `pocket unpair <id>` locks one out.
`upgrade` on the pocket gets the newest `pocket.lua`.

## Schematics (builder turtles)

Save a build with Create's **Schematic and Quill**, then drag the `.nbt` file (from
`.minecraft/schematics` on your PC) onto the base computer's screen. `schem` lists them,
`schem <name>` shows the size and the materials. (Building them with turtles comes next.)

## Mining dimension teams

One **loader** and up to **5 miners** per mining dimension (e.g. *Just Another Mining
Dimension*), all running `miner.lua`. They show up on **TURTLES > MINING**, never on the map.

| Turtle | Equipped | Carries |
|---|---|---|
| **LOADER** (team leader) | Chunky upgrade + Ender Modem | fuel |
| **MINER** (1-5) | End Automata Core (stays on) + pickaxe | Ender Modem, Geo Scanner, shulker box, fuel |

 **Fuel:** any fuel works. Miners also burn the coal they mine. If your pack has an **endless
fuel item** (one that is not used up, e.g. the Mining Dim Core), give one to each turtle: they
notice it is endless by themselves, keep it and never unload it. The loader can't refuel
itself otherwise, so give it plenty of coal blocks if there is no endless item.

- Works with the normal Chunky upgrade (only its own chunk loaded) - no server config.
- Each chunk: every miner gets its own shaft; the loader hands out the layers one at a time
  (deepest first). In a layer the Geo Scanner shows the ores; the miner plans its way through
  caves and around lava, stops **next to** the ores and digs the whole vein from there.
- **Ores:** vanilla and **modded** (by their ore tags and names). Extra / unwanted ores:
  `mining.ores` / `mining.skipOres` in `base_config.lua`.
- Then all miners line up at the chunk edge, step over together, and the loader follows.
- Full -> the shulker. Every few minutes (SETTINGS > MINING) a miner teleports to the
  unload station, empties itself and the shulker, and comes back - **one miner at a time**.
- Your own items in a miner when you press START are never unloaded.

**Setup**
1. The unload station's chunk must stay loaded (a chunk loader there). The station: a block
   facing **either** an empty block with air above it and an **AE2 Import Bus** touching it,
   **or** an ME Interface / linked chest (then keep 2 blocks of air above the station).
2. **Each miner once:** put it on the station facing the storage, copy `miner.lua` onto it, run
   `miner`, answer the questions (**y** = standing on the unload station). Pick it up.
3. Put the **loader on the surface** where mining starts, facing the way to mine (away from your
   base). Copy `miner.lua`, run `miner` (role **l**).
4. Put the **miners on the surface next to the loader, in the same chunk** and run `miner here`
   on each (with GPS in the dimension just press Enter).
5. They join the loader by themselves. Press **START TEAM** on TURTLES > MINING.
6. **One more miner later, while the team is working:** do step 2 with it, then put it next to the
   loader (within 40 blocks of the middle of the chunk the team works in) and run `miner here`.
   The loader takes it into the running team as the last miner; the others keep their shafts and
   lanes, and the team waits for it before the next crossing. Too far away, or during a crossing:
   the loader says so in the team's LOG and it joins as soon as it can. (Loader and the new miner
   need miner.lua m19 or newer.)
7. **New version of miner.lua:** `mine update` on the base computer (or **UPDATE MINERS**, two
   taps). The team is paused first, every turtle gets the new program and restarts, then the team
   goes on where it was. Turtles with m20 or older need one hand copy first; the base says which.

Optional lines in `base_config.lua`:
```lua
mining = {
  want = { "minecraft:tuff" },                 -- stone types to go and dig too
  keep = { "minecraft:deepslate" },            -- keep these when dug (normally thrown away)
  ores = { "somemod:strange_rock" },           -- more blocks that count as ores
  skipOres = { "create:zinc_ore" },            -- ores you do not want
},
```

## The map

- **Two layers:** *detail* (every block column, newest chunks) and *overview* (one
  colour and height per chunk, never dropped). You see the overview when zoomed
  out to 16 blocks per cell or more.
- Saved in small files on **data floppies** first. Empty floppies become data
  disks by themselves, and you are told when to add another one.
- **SURVEY: ALL TURTLES** maps the area on screen. Big areas are handed out in
  batches of 64 spots per turtle. `survey` on the computer shows the progress, and
  what each turtle is waiting for.
- **Work area** (SETTINGS > MAP, two corners - or SET CORNER on the pocket): turtles survey
  only inside it (auto-map too); its edge is drawn on the map with `+`. Tap "Work area" for
  the whole world again.
- Turtles survey as a **pack** (side by side), so after a server crash one visit wakes them all.
- The letters on the map: **B** base · **@** you · **D** drone · **T** turtle.

---

## Chat commands

These start with `$`, which hides the message from other players. The replies are
private.

| Command | What it does |
|---|---|
| `$drone help` | list the commands |
| `$drone home` | ride to Base |
| `$drone to <place>` / `$drone to @<player>` | ride to a saved place / to a player |
| `$drone back` | back to where you were before a big jump, or where you died |
| `$drone places` · `$drone status` · `$drone stop` | saved places · what the drones do · stop your ride |
| (owner) `$drone allow / deny <name>` · `$drone allowed` | who may ride |
| (owner) `$drone yes / no <name>` | approve or decline a ride request |
| (owner) `$drone notify on / all / off` | the base's messages in your chat (`on` = warnings and errors) |

(owner) = owner only. Players not on the allow list need the owner's OK for each ride.

---

## Console commands

Type these on the base computer. `help` lists them all.

| Area | Commands |
|---|---|
| Program | `upgrade [check\|full\|slim\|branch <name>]` · `store [find\|update]` · `away` |
| Turtles | `turtles` · `turtle <id> <cmd>` (`log`, `diag`, `goto x y z`, `home`, `stop`, `forget`, `setting …`) · `drive <id>` · `update` · `rescue <id>` · `findlost` · `party [stop]` · `forget base` · `exit [clear]` |
| Map | `map [clear]` · `survey [auto on\|off]` · `disks [data\|move]` · work area: SETTINGS > MAP corners |
| Factory | `factory [chest <name>\|builder <id>\|crafter <id>\|build\|stop\|fuel <item> [count]\|fuel reset\|learn\|recipes\|forget <item>\|items]` (or SETTINGS > FACTORY) |
| Mining | `mine [drop\|forget] <id>` · `mine update [stop]` |
| Pocket | `pocket [unpair <id>]` |
| Schematics | `schem [<name>\|delete <name>]` |
| Drones | `drones` · `drone <n>` · `dest …` · `save <name>` · `list` · `fly` · `pickup` · `drop` · `ferry` · `home` · `stop` · `charger [x y z]` |
| Chat | `allow <name>` · `deny <name>` · `allowed` |
| ME | `mesetup` · `me check` · `me add <id>` · `tanks` · `fluidbuffer [<n>\|auto]` · `supply [<storage> <item> <count>\|<storage> fluid <fluid> <buckets>\|stop <n>\|now]` · `curios check` · `curios probe` · `curios auto [clear]` |
| Screen | `theme [name\|random]` · `events [n] [errors]` |
| Checks | `report` (every block and its functions, uploaded to pastebin) · `uptime` (when the base was off, and why) |

---

## Themes & the message log

- **7 themes named after Minecraft:** bedrock, stone, deepslate, oak, nether, ender, ocean.
  By default a **different one is picked on every start**. `theme bedrock` keeps one, and
  `theme random` goes back to random (also on SYSTEM > Settings). A theme only changes the
  frame; the map and status colours mean the same in every theme.
- **Message log:** every message is also saved in `events.log` (about 32 KB at
  most). The EVENTS tab keeps its list after a restart; CLEAR LIST only empties
  the list on screen. `events 30 errors` shows the last 30 errors.

---

## Tips & troubleshooting

| Problem | Try |
|---|---|
| A tab is missing | The block is not found. Check the modems (right-click to turn them on) and the cable. The ME tab lists what the computer sees. |
| ME shows a "partial view" | An item in the network breaks Advanced Peripherals' full list. `me check` helps find it; known culprit: `hazennstuff:pendant_of_harmony`. |
| A turtle ignores commands | `turtle <id> log 10`. Is it online? Is it STOPPED (press PING)? |
| A turtle keeps restarting | `turtle <id> diag` and its log ("started by the game" = its chunk was unloaded). |
| Turtles run out of fuel | Set `turtles.fuelChest` and keep fuel in it. |
| A survey does nothing | Type `survey`: it lists every turtle and why it gets no batch. |
| Turtles dig where they should not | SETTINGS > TURTLES: switch "Turtles dig through natural blocks" off and make "No digging around the base" big enough for your base. |
| A turtle says "busy" to your command | It is building, crafting or rescuing - that is never cut halfway. It takes your command right after. |
| The rescuer keeps going to turtles you picked up | They went silent near the base: FORGET THEM on the FLEET card, or `forget base`. |
| A drone will not let you off | It stays where it is: press DROP again, or sneak to get off. |
| `upgrade` says it cannot read the file list | The branch it follows is gone or renamed: `upgrade branch main`, then `upgrade`. |
| You want the messages in chat | `$drone notify on`, or the buttons on the CHAT tab. |
| The computer's disk is full | `disks data` puts the map on floppies; the footer warns before anything is lost. |

> **Server tips:** the base and the turtles only work while their chunks are
> loaded. Use the ANCHOR turtle for the base and the Chunky upgrade on every
> turtle. Server owners can give disks more room with CC:Tweaked's
> `computer_space_limit` / `floppy_space_limit`.

---

## Files

| File | Purpose |
|---|---|
| `inventory.lua` | Starts the program: checks the files, loads them in order, runs the workers |
| `startup.lua` | Autostart (goes in the computer's top level) |
| `upgrade.lua` | Gets the newest program files from GitHub (base and pocket) |
| `manifest.txt` · `dist/` | the file list `upgrade` reads · the comment-free copies it downloads (made by `tools/make_manifest.py`) |
| `base_config.lua` | **All settings** |
| `base_devices.lua` · `base_state.lua` · `base_theme.lua` | finding blocks · shared state · colours, themes, safe saving, floppies |
| `base_storage.lua` · `base_players.lua` | backpacks, curios · players, dimensions, `$drone back` |
| `base_me.lua` | ME / RS network, transfers, fluids, crafting, messages and their log |
| `base_drones.lua` | drone missions, charging, parking |
| `base_store.lua` | talking to the storage helper computers |
| `base_supply.lua` | `supply`: storages on the cable kept stocked from AE2 |
| `base_turtles.lua` · `base_map.lua` | turtle communication, homes, fuel, rescue, updates · map data and surveys |
| `base_console.lua` · `base_chat.lua` · `base_input.lua` · `base_workers.lua` | keyboard commands · chat commands · monitor touches · background workers |
| `base_ui_*.lua` | one file per page (`base_ui_core.lua` = header and shared drawing, `base_ui_home.lua` = HOME, `base_ui_drive.lua` = Drive, `base_ui_system.lua` = Status, `base_ui_settings.lua` = Settings) |
| `base_away.lua` · `base_factory.lua` · `base_curios.lua` · `base_schem.lua` | away mode and its report · the turtle factory · curios that fit and auto-equip · schematics |
| `base_pocket.lua` · `pocket.lua` | the pocket remote: the base side · the program on the pocket computer |
| `node.lua` | the turtle program |
| `miner.lua` | the mining dimension team program (miner + loader) |
| `base_mining.lua` / `base_ui_mining.lua` | the mining teams on the base / the MINING tab |
| `store.lua` | the storage helper program (for extra computers) |

**Data files the program creates** (keep them; delete one only to reset that part):
`waypoints.dat`, `drone_logs.dat`, `drone_charger.dat`, `chat_access.dat`,
`chat_notify.dat`, `back_spots.dat`, `player_dims.dat`, `turtles.dat`,
`turtle_versions.dat`, `terrain.dat`, `exit_route.dat`, `map/`, `map_view.dat`,
`me_setup.dat`, `me_names.dat`, `me_owed.dat`, `curios_last.dat`, `ui_page.dat`,
`theme.dat`, `settings.dat`, `auto_survey.dat`, `survey_queue.dat`, `base_alive.dat`, `away.dat`,
`factory.dat`, `recipes.dat`, `mining.dat`, `pockets.dat`, `curios_fits.dat`, `curios_auto.dat`,
`store_helpers.dat`, `upgrade.dat`, `schematics/`, `events.log` + `events.old.log`, `system.log` + `system.old.log`.
With a data floppy in a drive, the logs and the bigger data files live there.

A computer has only **1 MB** of disk. The big files (map, turtle knowledge) can
live on data floppies (`disks data` / `disks move`).

### For developers

`tools/` is **not** game code; don't copy it into the game.

- `tools/preview/`: draws the monitor outside the game (Lua 5.3 + Pillow)
- `tools/navsim/`: runs the turtle program in a test world (navigation, STOP, restarts)
- `tools/check_locals.py node.lua`: checks the game's 200-local limit
- `python3 tools/run_tests.py` (`--quick`, `-k <word>`): syntax, undefined globals, every
  base test, every page drawn, the turtle tests and the mining simulator. Run it after every change.
- `python3 tools/make_manifest.py`: rebuilds `manifest.txt` and `dist/` - run it after every
  change too (`upgrade` downloads what it lists; the tests fail when it is stale).
