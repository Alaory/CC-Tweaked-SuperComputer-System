# CC:Tweaked Base Control

A ComputerCraft program for a Minecraft base. One computer with a large
Advanced Monitor shows your inventory, the online players, your backpacks and
curios, an AE2 / Refined Storage network, PneumaticCraft drones, remote
turtles and a terrain map. It also has a keyboard console and `$drone` chat
commands, so players can call a drone ride from anywhere.

Made for **CC:Tweaked 1.120.2 on Minecraft 1.21.1 (NeoForge)** with
**Advanced Peripherals**.

## Features

| Tab | What it shows / does |
|---|---|
| **INVENTORY** | Your inventory grid, armour and offhand, how full it is, and a sortable item list (by count, name or slot). Tap an item to highlight every slot that holds it. |
| **PLAYERS** | One box per online player: name, dimension, health, air, position, facing. Tap a box to see the Player Detector's raw data. |
| **STORAGE** | What is inside the backpacks and tanks you carry. |
| **CURIOS** | Your worn Curios slots. |
| **ME** (or **RS**) | Network status, an item / fluid browser, and buttons to take items, store them, fill your fluid containers and craft. Every button needs a second tap to confirm. |
| **DRONE(S)** | PneumaticCraft drones: air, mission steps and log. Pick a passenger and a destination (player, saved place or coordinates), then fly, pick up, drop or ferry. |
| **CHAT** | Who may use the `$drone` chat commands (the allow list). |
| **TURTLES** | Remote-controlled turtles: status, fuel, position, and a control pad. Also rescue and "find lost turtles". |
| **MAP** | Terrain and ores from the turtles' Geo Scanner scans: zoom, rotate, and send turtles to survey an area. |

A tab only appears when the block it needs is connected.

**Messages** (a transfer is done, a drone cannot start, an error ...) appear as
boxes in the top-right corner. Tap a box to close it. Normal messages close by
themselves after a few seconds, errors stay until you close them. The
**EVENTS** button in the header lists the last 40 messages, with the number of
new ones on it.

**Drones** (PneumaticCraft):
- They teleport (or fly) to players and places, pick a player up with Entity Import, and drop them at the destination. If something fails with a passenger on board, the drone brings them back to Base.
- They only go to players and places **in the overworld**.
- After each mission a drone parks on its Charging Station. Every teleport costs air, so missions check the air first.

**Turtles** (`node.lua`): they find their way around obstacles, use a "sky highway" for long trips and share what they learn (walls, dead ends, the exit route) through the base. They also scan terrain for the map. The base sends them program updates by itself.

## What you need

**Required**
- A computer (CC:Tweaked)
- An **Advanced (gold) Monitor**. It needs to be big: the screen asks for a bigger one if it is too small.
- An **Inventory Manager** (Advanced Peripherals) with a Memory Card bound to you

**Optional**: each one adds features.

| Block | Adds |
|---|---|
| Player Detector | PLAYERS tab, your status, drones finding players |
| Environment Detector | tells the program which dimension the base is in |
| ME Bridge / RS Bridge + a buffer chest | ME / RS tab |
| Drone Interface (one per drone) + Charging Station | DRONE tab |
| Chat Box | `$drone` chat commands, CHAT tab |
| Wireless or Ender Modem on the computer | TURTLES and MAP tabs |
| Disk Drive + floppy | turtle install disk, and extra space for data files |

**Connecting the blocks:** they can touch the computer or sit anywhere on a **wired network**: a Wired Modem on each block and on the computer, connected with Networking Cable. Right-click every modem so it turns on.

## Installation

1. Copy **all** files into the same folder on the computer: `inventory.lua`,
   every `base_*.lua` and `node.lua`.
2. Open `base_config.lua` and set at least:
   - `drone.home`: the "Base" position where riders are dropped off
   - `drone.charger`: the drone Charging Station
   - `turtles.key`: a shared secret. Change it from `"change-me"`. The same key goes in `node.lua`.
3. Run it:
   ```
   inventory
   ```
   If a file is missing, the program lists the missing files.
4. For the ME tab, put **one** item in the buffer chest and type `mesetup` on
   the computer. It finds the chest by itself and saves the result.

### Turtles

1. Give the turtle a **Chunky upgrade** and an **Ender Modem** (a Wireless Modem
   reaches only about 64 blocks), plus fuel.
2. Copy `node.lua` onto it as `startup.lua`. `protocol`, `baseName` and `key`
   must match `CONFIG.turtles` in `base_config.lua`. Instead of copying it by
   hand, you can put a NEW turtle next to the Disk Drive with the install
   floppy and turn it on. The base keeps that floppy up to date.
3. Give it a name: `label set Scout1`.
4. Without GPS, tell it where it is once, on the base computer:
   `turtle <id> setpos <x> <y> <z> <north|south|east|west>`.
5. For the map, put a **Geo Scanner** (as an item) in its inventory.

## Chat commands

These start with `$` (`$drone ...`), which hides the message from other players.
The replies are private.

| Command | What it does |
|---|---|
| `$drone help` | list the commands |
| `$drone home` | ride to Base |
| `$drone to <place>` | ride to a saved place |
| `$drone to @<player>` | ride to a player (if allowed) |
| `$drone back` | back to where you were before a big jump, or where you died (overworld only) |
| `$drone places` | the saved places |
| `$drone status` | what the drones are doing |
| `$drone stop` | stop your ride |
| `$drone allow / deny <name>` | owner: who may ride |
| `$drone allowed` | owner: show the allow list |
| `$drone yes / no <name>` | owner: approve or decline a ride request |

Players who are not on the allow list need the owner's OK for each ride.

## Console commands

Type these on the base computer. `help` shows the full list.

| Area | Commands |
|---|---|
| Drones | `drones`, `drone <n>`, `dest <x y z \| place \| @player>`, `save <name> [x y z]`, `del <name>`, `list`, `players`, `fly`, `home`, `pickup [player]`, `drop`, `ferry [player]`, `stop`, `release`, `status`, `charger [x y z\|off]` |
| Chat access | `allow <name>`, `deny <name>`, `allowed` |
| Turtles | `turtles`, `turtle <id\|name> <cmd>`, `update`, `rescue <id> [x y z [radius]]`, `findlost [radius]`, `exit [clear]` |
| Map | `map clear` |
| ME | `mesetup`, `me add <item id>`, `me check`, `tanks` |
| Checks | `curios check`, `report` (every peripheral and its functions, uploaded to pastebin), `disks [data\|move]` |

## Files

| File | Purpose |
|---|---|
| `inventory.lua` | Launcher: checks that every file is there, loads them in order, starts the workers |
| `base_config.lua` | **All settings** |
| `base_devices.lua` | Finds the blocks (sides or wired network) |
| `base_theme.lua` | Colours, the off-screen window, safe file saving, floppies, helpers |
| `base_state.lua` | The shared `state` table, reading the inventory |
| `base_storage.lua` | Backpacks / tanks and Curios data |
| `base_me.lua` | ME / RS network: reading it, transfers, fluids, crafting, `mesetup` |
| `base_players.lua` | Player Detector data, dimensions, `$drone back` tracking |
| `base_drones.lua` | Drones: travel, pickup / drop, charging, missions |
| `base_turtles.lua` | Turtle communication, shared knowledge, updates, rescue |
| `base_map.lua` | Map data from turtle scans |
| `base_console.lua` | Keyboard commands |
| `base_chat.lua` | `$drone` chat commands |
| `base_input.lua` | Monitor touches |
| `base_workers.lua` | Background workers and the screen loop |
| `base_ui_core.lua` | Shared drawing: header, tabs, boxes, buttons, footer, popup |
| `base_ui_*.lua` | One file per tab |
| `node.lua` | The turtle program |

All `base_*.lua` files share one global namespace and are loaded in a fixed
order by `inventory.lua`. All game calls happen in background workers. The
screen only draws data those workers have already read, so it never waits on
the game.

### Data files the program creates

`waypoints.dat`, `drone_logs.dat`, `drone_charger.dat`, `chat_access.dat`,
`back_spots.dat`, `player_dims.dat`, `turtles.dat`, `terrain.dat`,
`exit_route.dat`, `map.dat`, `map_view.dat`, `me_setup.dat`, `me_names.dat`,
`me_owed.dat`, `curios_last.dat`.

A computer has only **1 MB** of disk. The biggest files (map, turtle
knowledge, logs) can be moved to data floppies with `disks data` / `disks move`.
When the disk is full, the footer shows a warning instead of writing half a file.

## Screen preview

`tools/preview/` draws the monitor outside the game (for checking screen changes).
See `tools/preview/README.md`. It is not part of the program; do not copy it into the game.

## Known limits

- **Drones** only fly to players and places in the overworld. A player the Player Detector cannot find in its own dimension counts as being in another dimension.
- **Broken ME list:** Advanced Peripherals' `getItems()` crashes on a server if any item in the network uses client-only tooltip code. The ME tab then shows a "partial view", and `me check` helps find the item. Known culprit: `hazennstuff:pendant_of_harmony`.
- **Broken Curios list:** one unreadable worn item breaks the whole Curios listing. The CURIOS tab then shows the last reading that worked.
- **Exact amounts only:** the program only moves exact amounts of your items and fluids, plus whatever it put into a buffer itself. The one exception is the explicit BUFFER -> ME button.
