# 🖥️ CC:Tweaked Base Control

**One computer and one big monitor that run your whole Minecraft base:** your
inventory, players, backpacks, curios, an AE2 network, drone rides, a team of
mapping turtles and a map of the world.

> Made for **CC:Tweaked 1.120.2** on **Minecraft 1.21.1 (NeoForge)** with
> **Advanced Peripherals** · optional: **PneumaticCraft**, **AE2 / Refined Storage**, **Curios**

---

## 📑 Contents

- [✨ What it does](#-what-it-does)
- [🧰 What you need](#-what-you-need)
- [🚀 Installation](#-installation)
- [⚙️ Configuration](#️-configuration)
- [🐢 Turtles](#-turtles)
- [🚁 Drones](#-drones)
- [📦 ME / Curios](#-me--curios)
- [🗺️ The map](#️-the-map)
- [⛏️ Mining dimension teams](#️-mining-dimension-teams)
- [💬 Chat commands](#-chat-commands)
- [⌨️ Console commands](#️-console-commands)
- [🎨 Themes & the message log](#-themes--the-message-log)
- [💡 Tips & troubleshooting](#-tips--troubleshooting)
- [📁 Files](#-files)

---

## ✨ What it does

The top row has **6 tabs**; tabs with more than one page show their pages as small
tabs right under it.

| Tab | Pages | What you get |
|---|---|---|
| 🎒 **YOU** | Inventory · Storage · Curios | Your inventory grid, armour and item list (tap an item to highlight it) · what is inside your backpacks and tanks · your curios: store in ME, move to your inventory, put on from ME. |
| 👥 **PLAYERS** | Players · Chat | A card per online player (dimension, health, position) · who may use the `$drone` chat commands, ride requests, the base's messages in your chat. |
| 📦 **ME** (or **RS**) | | Network status, item / fluid browser, take and store items, fill fluid containers, craft. |
| 🚁 **DRONES** | | PneumaticCraft drones: air, mission steps, log. Pick a passenger and a destination, then fly, pick up, drop or ferry. |
| 🐢 **TURTLES** | Turtles · Map | Every turtle with status, fuel, gear, log and a control pad · the terrain map: zoom 1–512 blocks per cell, surveys, **AUTO-MAP**. |
| ⚙️ **SYSTEM** | Status · Events · Settings | How the base is doing, a **system log** and the times it was off · every message (kept after restarts) · **settings** you change by tapping (−/+, choices, "use my position"; saved in `settings.dat`, your `base_config.lua` stays as it is). |

A tab only shows up when the block it needs is connected.

**Messages** pop up as small boxes in the top-right corner and close by themselves
after 3 seconds; tap one to close it sooner. They are also listed on the EVENTS
tab and saved in `events.log`. If you want, they can be sent to you privately in
chat as well.

---

## 🧰 What you need

### Required

- 💻 A **Computer** (CC:Tweaked)
- 🖥️ A big **Advanced (gold) Monitor**. If it is too small, the screen tells you.
- 🎒 An **Inventory Manager** (Advanced Peripherals) with a **Memory Card** bound to you

### Optional: each one adds features

| Block | Adds |
|---|---|
| 👁️ Player Detector | PLAYERS tab, finding players for drone rides |
| 🌍 Environment Detector | which dimension the base is in |
| 📦 ME Bridge / RS Bridge + a buffer chest | ME / RS tab |
| 🚁 Drone Interface (one per drone) + Charging Station | DRONES tab |
| 💬 Chat Box | `$drone` chat commands, CHAT tab, messages in chat |
| 📡 Ender Modem (or Wireless Modem) on the computer | TURTLES and MAP tabs |
| 💾 Disk Drive + floppy | turtle install floppy, extra room for the map |

> 🔌 **Connecting the blocks:** blocks can touch the computer, or sit anywhere on a
> **wired network**. For that, put a Wired Modem on each block and on the computer,
> connect them with Networking Cable, and right-click every modem so it turns on.

---

## 🚀 Installation

### 1️⃣ The base computer

1. Make a folder on the computer, for example `controller`, and copy **all**
   program files into it: `inventory.lua`, every `base_*.lua` and `node.lua`.
2. Open `base_config.lua` and set at least:
   - `turtles.key`: a secret word of your own (not `"change-me"`). Turtles
     installed from the install floppy or updated by the base get it
     automatically; if you copy `node.lua` onto a turtle by hand, put the same
     key in it.
   - `drone.home`: your "Base", where drone riders are dropped off
   - `drone.charger`: the drone Charging Station
3. Start it:
   ```
   controller/inventory
   ```
   If a file is missing, it lists the missing files.
4. **Autostart (recommended):** copy `startup.lua` to the **top level** of the
   computer, not into the folder. The program then starts by itself and comes
   back after a crash. Ctrl+T stops it.

### 2️⃣ Turtles

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

A new turtle refuels by itself and gets a home by itself (see [🐢 Turtles](#-turtles)).

### 💽 Extra storage: helper computers (optional)

Each extra computer gives the map **1 MB** more (about 8 floppies):

1. Put a computer near the base, **in the same chunk if you can** (it must stay
   loaded), with a **Wired Modem** connected to the base's cable. Right-click
   the modem so it turns on.
2. Copy `store.lua` onto it and run `store` once. It then starts by itself.
3. On the base computer, type `store find`. The map uses the helpers when the
   data floppies are full.

A helper belongs to the first base that uses it (`store reset` on the helper
changes that) and only listens on wired modems.

**Updating helpers:** put the new `store.lua` next to the base's `inventory.lua`.
Every helper gets it by itself within a few minutes and restarts
(`store update` on the base computer does it at once).

### 3️⃣ ME network

Put **one** item in the buffer chest and type `mesetup` on the computer. It finds
the chest by itself and remembers it.

### 4️⃣ Drones

Program a PneumaticCraft drone with a ComputerCraft puzzle piece whose area
contains the Drone Interface, and launch it. The DRONES tab shows it as
connected. After each mission it parks on its Charging Station.

---

## ⚙️ Configuration

All settings are in **`base_config.lua`**. Keep your own copy of it: when you
update the program, copy the new files **except** `base_config.lua`, and add new
lines by hand when an update needs them.

The settings you will most likely touch:

| Setting | What it does |
|---|---|
| `turtles.key` | The shared secret between the base and the turtles. **Change it.** |
| `turtles.fuelChest = { x=…, y=…, z=… }` | A chest with fuel that every turtle may use (see below) |
| `turtles.lowFuel` | Below this much fuel a turtle goes refuelling (default 2000) |
| `turtles.idleHome` | Seconds idle before a turtle goes home (default 120, `0` = off) |
| `turtles.rescueAfter` | Seconds silent before the rescuer goes to wake a turtle up (default 180) |
| `turtles.avoidRange` / `turtles.avoidWho` | Keep away from players this close (default 100, 0 = off) / `"strangers"` (not you, not the allow list) or `"everyone"` |
| `drone.home` / `drone.charger` | Base drop-off point / Charging Station |
| `drone.travel` | `"teleport"` (best for underground bases) or `"fly"` |
| `me.curiosChest` | An **empty** barrel used only for curios moves (see below) |
| `map.up` | Which way is up on the map (`"north"`, `"east"`, `"south"`, `"west"`) |
| `map.computerKB` | How much of the computer's disk the map may use (default 200) |
| `chat.command` | The chat command word (`$drone …`) |
| `theme` | Fix the monitor's colours, e.g. `theme = "nord"` (default: a random one on every start) |
| `names.*` | Pick one block by its network name when you have several of a kind |

> 💡 Many settings can also be changed while the program runs: `charger`, `theme`,
> `turtle <id> setting <name> <value>` (a turtle's own settings).

---

## 🐢 Turtles

Turtles fly to places, scan the terrain for the map, find their way around
obstacles, and share what they learn (walls, dead ends, the exit route out of the
base) through the base.

### 🏠 Homes

- **SET HOME** on one turtle. Every turtle without a home is then offered one
  **next to it** (one block over on X or Z). The turtle checks the spot the first
  time it goes there. If the block is not free, it gives it back without digging
  and gets the next one.
- A turtle **with nothing to do for 2 minutes goes home**, so it does not keep a
  far-away chunk loaded for nothing. A turtle you stopped, the anchor and stuck
  turtles stay where they are.

### ⛽ Fuel

| How | What happens |
|---|---|
| 🆕 New turtle | It runs REFUEL by itself on its first start. |
| ♻️ Reusable fuel | A fuel item that is never used up (some mods have one) is recognised and kept. The turtle tops up from it whenever it is idle. |
| 🧰 **Shared fuel chest** | Set `turtles.fuelChest`. A turtle low on fuel parks **on top of the chest**, takes only fuel (coal, charcoal, coal blocks, blaze rods, lava, or reusable fuel), and flies home. **One turtle at a time**; the others wait. |
| 🏠 Chest at home | A chest under, above or in front of a turtle's home works the same way. |

> 💡 Keep the block **on top of** the fuel chest free. Put one reusable fuel item
> per turtle in it: each turtle keeps one, and never runs dry while it can idle.

### 🛟 Rescue, anchor and stop

- **⚓ ANCHOR:** one turtle parked in the base computer's chunk keeps the base
  running while you are offline.
- **🛟 RESCUER:** a permanent rescue turtle. It flies to a turtle that has gone
  silent (for example an unloaded chunk: arriving wakes it up), that is stuck, or
  that has no fuel. It goes home afterwards.
- **🛑 STOP** really stops a turtle, also after its chunk was unloaded and loaded
  again. A stopped turtle shows **STOPPED** and is left alone by automatic jobs.
  Any button (for example PING) makes it normal again.
- 🔄 **Updates:** copy a new `node.lua` into the program folder. The base updates
  the turtles one at a time; a busy turtle installs it after its job. Type
  `update` to see the versions.
- 🙈 **Keeping away from players:** a surveying turtle with another player within
  100 blocks (Player Detector) stops and goes home; survey spots near that player
  wait until they leave. You and your allow list are ignored (SETTINGS > TURTLES).
  Visitors at your base don't stop turtles leaving or coming home.

### 🩺 When a turtle misbehaves

| Command | Shows |
|---|---|
| `turtle <id> log 15` | its last 15 log lines in full |
| `turtle <id> diag` | disk space, file sizes, saved job, how often it restarted, gear |
| `turtles` | all turtles with fuel, position and gear |

A turtle's answers appear in **its log**, on the TURTLES tab or with `turtle <id> log`.
If a turtle restarts, its log says why: "started by the game (chunk loaded
again …)", "after an update" or "after an ERROR: …".

---

## 🚁 Drones

- They **teleport** (or fly) to players and places. They pick a player up, carry
  them, and drop them at the destination.
- **Overworld only**, for players and places alike.
- Every teleport costs air, so missions check the air first. Long trips go in hops
  (shorter hops where the area ahead is not loaded).
- If **you get off during a ride**, the drone notices and goes straight home.
- If something fails with a passenger on board, the drone brings them back to Base.

---

## 📦 ME / Curios

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
  `curios probe` shows what your version wants. Every curios move is listed on the
  EVENTS tab.

---

## 🌙 While you are away

5 minutes after you leave the server (Player Detector), the base uses the time:
- 🔄 turtle program **updates** (they wait while you play - at most 2 h; UPDATE TURTLES forces them)
- ⛽ turtles **top up their fuel** early, so they are full when you are back
- 🗺️ the monitor shows the **map**, zoomed out by itself, following the turtles; **auto-map** runs even if you switched it off (off again when you are back)
- 💾 the map is saved every 30 minutes

When you come back: a **WELCOME BACK** box, a private chat message and the SYSTEM tab tell you
how long you were away, what was mined and mapped, what went wrong and what needs you now.
Type `away` on the computer to see it again. Settings: SETTINGS > AWAY.

## ⛏️ Mining dimension teams

One **loader** and up to **5 miners** per mining dimension (e.g. *Just Another Mining
Dimension*), all running `miner.lua`. They show up on **TURTLES > MINING**, never on the map.

| Turtle | Equipped | Carries |
|---|---|---|
| 📦 **LOADER** (team leader) | Chunky upgrade + Ender Modem | fuel |
| ⛏️ **MINER** (1-5) | End Automata Core (stays on) + pickaxe | Ender Modem, Geo Scanner, shulker box, fuel |

⛽ **Fuel:** any fuel works. Miners also burn the coal they mine. If your pack has an **endless
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

Optional lines in `base_config.lua`:
```lua
mining = {
  want = { "minecraft:tuff" },                 -- stone types to go and dig too
  keep = { "minecraft:deepslate" },            -- keep these when dug (normally thrown away)
  ores = { "somemod:strange_rock" },           -- more blocks that count as ores
  skipOres = { "create:zinc_ore" },            -- ores you do not want
},
```

## 🗺️ The map

- **Two layers:** *detail* (every block column, newest chunks) and *overview* (one
  colour and height per chunk, never dropped). You see the overview when zoomed
  out to 16 blocks per cell or more.
- Saved in small files on **data floppies** first. Empty floppies become data
  disks by themselves, and you are told when to add another one.
- **SURVEY: ALL TURTLES** maps the area on screen. Big areas are handed out in
  batches of 64 spots per turtle. `survey` on the computer shows the progress, and
  what each turtle is waiting for.
- The letters on the map: **B** base · **@** you · **D** drone · **T** turtle.

---

## 💬 Chat commands

These start with `$`, which hides the message from other players. The replies are
private.

| Command | What it does |
|---|---|
| `$drone help` | list the commands |
| `$drone home` | ride to Base |
| `$drone to <place>` / `$drone to @<player>` | ride to a saved place / to a player |
| `$drone back` | back to where you were before a big jump, or where you died |
| `$drone places` · `$drone status` · `$drone stop` | saved places · what the drones do · stop your ride |
| 👑 `$drone allow / deny <name>` · `$drone allowed` | who may ride |
| 👑 `$drone yes / no <name>` | approve or decline a ride request |
| 👑 `$drone notify on / all / off` | the base's messages in your chat (`on` = warnings and errors) |

👑 = owner only. Players not on the allow list need the owner's OK for each ride.

---

## ⌨️ Console commands

Type these on the base computer. `help` lists them all.

| Area | Commands |
|---|---|
| 🐢 Turtles | `turtles` · `turtle <id> <cmd>` (`log`, `diag`, `goto x y z`, `home`, `stop`, `setting …`) · `update` · `rescue <id>` · `findlost` · `exit [clear]` |
| 🗺️ Map | `map [clear]` · `survey` · `disks [data\|move]` |
| 🚁 Drones | `drones` · `drone <n>` · `dest …` · `save <name>` · `list` · `fly` · `pickup` · `drop` · `ferry` · `home` · `stop` · `charger [x y z]` |
| 💬 Chat | `allow <name>` · `deny <name>` · `allowed` |
| 📦 ME | `mesetup` · `me check` · `me add <id>` · `tanks` · `curios check` · `curios probe` |
| 🎨 Screen | `theme [name\|random]` · `events [n] [errors]` |
| 🩺 Checks | `report` (every block and its functions, uploaded to pastebin) · `uptime` (when the base was off, and why) |

---

## 🎨 Themes & the message log

- **6 dark themes:** midnight, nord, dracula, forest, ember, ocean. By default a
  **different one is picked on every start**. `theme nord` keeps one, and
  `theme random` goes back to random. The map colours mean the same in every theme.
- **Message log:** every message is also saved in `events.log` (about 32 KB at
  most). The EVENTS tab keeps its list after a restart; CLEAR LIST only empties
  the list on screen. `events 30 errors` shows the last 30 errors.

---

## 💡 Tips & troubleshooting

| Problem | Try |
|---|---|
| A tab is missing | The block is not found. Check the modems (right-click to turn them on) and the cable. The ME tab lists what the computer sees. |
| ME shows a "partial view" | An item in the network breaks Advanced Peripherals' full list. `me check` helps find it; known culprit: `hazennstuff:pendant_of_harmony`. |
| A turtle ignores commands | `turtle <id> log 10`. Is it online? Is it STOPPED (press PING)? |
| A turtle keeps restarting | `turtle <id> diag` and its log ("started by the game" = its chunk was unloaded). |
| Turtles run out of fuel | Set `turtles.fuelChest` and keep fuel in it. |
| A survey does nothing | Type `survey`: it lists every turtle and why it gets no batch. |
| You want the messages in chat | `$drone notify on`, or the buttons on the CHAT tab. |
| The computer's disk is full | `disks data` puts the map on floppies; the footer warns before anything is lost. |

> ⚠️ **Server tips:** the base and the turtles only work while their chunks are
> loaded. Use the ANCHOR turtle for the base and the Chunky upgrade on every
> turtle. Server owners can give disks more room with CC:Tweaked's
> `computer_space_limit` / `floppy_space_limit`.

---

## 📁 Files

| File | Purpose |
|---|---|
| `inventory.lua` | Starts the program: checks the files, loads them in order, runs the workers |
| `startup.lua` | Autostart (goes in the computer's top level) |
| `base_config.lua` | ⚙️ **All settings** |
| `base_devices.lua` · `base_state.lua` · `base_theme.lua` | finding blocks · shared state · colours, themes, safe saving, floppies |
| `base_storage.lua` · `base_players.lua` | backpacks, curios · players, dimensions, `$drone back` |
| `base_me.lua` | ME / RS network, transfers, fluids, crafting, messages and their log |
| `base_drones.lua` | drone missions, charging, parking |
| `base_store.lua` | talking to the storage helper computers |
| `base_turtles.lua` · `base_map.lua` | turtle communication, homes, fuel, rescue, updates · map data and surveys |
| `base_console.lua` · `base_chat.lua` · `base_input.lua` · `base_workers.lua` | keyboard commands · chat commands · monitor touches · background workers |
| `base_ui_*.lua` | one file per page (`base_ui_core.lua` = header and shared drawing, `base_ui_system.lua` = Status, `base_ui_settings.lua` = Settings) |
| `node.lua` | 🐢 the turtle program |
| `miner.lua` | ⛏️ the mining dimension team program (miner + loader) |
| `base_mining.lua` / `base_ui_mining.lua` | the mining teams on the base / the MINING tab |
| `store.lua` | 💽 the storage helper program (for extra computers) |

**Data files the program creates** (keep them; delete one only to reset that part):
`waypoints.dat`, `drone_logs.dat`, `drone_charger.dat`, `chat_access.dat`,
`chat_notify.dat`, `back_spots.dat`, `player_dims.dat`, `turtles.dat`,
`turtle_versions.dat`, `terrain.dat`, `exit_route.dat`, `map/`, `map_view.dat`,
`me_setup.dat`, `me_names.dat`, `me_owed.dat`, `curios_last.dat`, `ui_page.dat`,
`theme.dat`, `settings.dat`, `auto_survey.dat`, `base_alive.dat`, `events.log` + `events.old.log`, `system.log` + `system.old.log`.

A computer has only **1 MB** of disk. The big files (map, turtle knowledge) can
live on data floppies (`disks data` / `disks move`).

### 🔧 For developers

`tools/` is **not** game code; don't copy it into the game.

- `tools/preview/`: draws the monitor outside the game (Lua 5.3 + Pillow)
- `tools/navsim/`: runs the turtle program in a test world (navigation, STOP, restarts)
- `tools/check_locals.py node.lua`: checks the game's 200-local limit
