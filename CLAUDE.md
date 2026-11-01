# Base Control Program (CC:Tweaked + Advanced Peripherals)

A ComputerCraft program for a Minecraft base: a big monitor UI with tabs
(INVENTORY, PLAYERS, STORAGE, CURIOS, ME, DRONES, CHAT, TURTLES, MAP), a
command console on the computer terminal, chat commands ($drone ...),
PneumaticCraft drone rides, turtle mapping/surveys, and an AE2 ME network view.

## Where it runs
- In-game computer, **CC:Tweaked 1.120.2, Minecraft 1.21.1** (NeoForge server).
- Started with `inventory.lua` (the launcher). The turtle program is `node.lua`
  (runs on mining turtles; the base sends it to turtles as an over-the-air update).
- The owner copies files onto the in-game computer by hand (drag and drop).
  **Never assume you can run code in the game.** Check syntax with `luac -p`
  (Lua 5.3 syntax is close enough), then the owner tests in game.

## Architecture
- `inventory.lua` loads every `base_*.lua` in a fixed order into **one shared
  global namespace** (functions are globals; file-local helpers are `local`).
  Order matters: a file may only use globals defined by files loaded before it
  at load time (inside functions, anything goes).
- Workers run together via `parallel.waitForAny`: uiLoop, invWorker,
  pageWorker, actionWorker, droneWorker, terminalWorker, chatWorker, commsWorker.
- **Peripheral calls belong in workers or fetch functions, never in drawing
  code.** Drawing reads `state.*` only.
- Drawing: everything is drawn into an off-screen window `win`; `flushWindow()`
  copies only changed rows to the monitor (big performance win - keep it).
- Buttons: `actButton(x, y, w, h, label, action)`; a second tap confirms; the
  action is queued and run by `runAction(a)` (base_me.lua) in the action worker.
- Data files are written with `saveFileSafe(path, text)` (base_theme.lua):
  only if they fit, through a temp file, never half-written. Big files go
  through `dataFile(path)` so they can live on data floppies (`disks data`).
- The computer has only **1 MB of disk** - keep data files small.

## Files
| File | What |
|---|---|
| base_config.lua | ALL settings. The owner has their own values in it (coordinates, turtle key) - never replace it wholesale; tell the owner which lines to add or change. |
| base_devices.lua / base_state.lua / base_theme.lua | peripheral discovery, shared state, palette + helpers (saveFileSafe, dataFile, mountedDisks, flushWindow) |
| base_storage.lua / base_players.lua | inventory, storage items (backpacks/tanks), curios, players, `$drone back` tracking |
| base_me.lua | ME network: listing (incl. partial view), item transfers, fluids, crafting, `mesetup`, stuck-item ledger, `runAction` |
| base_drones.lua | PneumaticCraft drone missions (teleport mode, air checks, parking/charging) |
| base_turtles.lua / base_map.lua | turtle comms, shared terrain knowledge, OTA updates, map data |
| base_console.lua / base_chat.lua / base_input.lua / base_workers.lua | console commands, chat commands, touch input, workers |
| base_ui_*.lua | one file per tab + base_ui_core.lua (cards, buttons, bars, footer) |
| node.lua | the turtle program |

## The owner's setup (found out the hard way)
Peripherals (from the `report` command): `me_bridge_4`, `inventory_manager_3`,
`player_detector_1`, `chat_box_0`, `drone_interface_0` + `drone_interface_2`,
`functionalstorage:storage_controller_0`, disk drives `drive_0`/`drive_1`/bottom,
monitor on `right`, wired modem `back`, wireless modem `top`.

**Inventory Manager is a newer Advanced Peripherals API:**
- Functions: importItem, exportItem, importCuriosItem, exportCuriosItem, list,
  size, getEmptySlots, getFreeSlot, listCurios, getCuriosSizes,
  wrapStorageItem, wrapCuriosStorageItem, getItemInHand, getOwner, ...
- **No** addItemToPlayer/removeItemFromPlayer, **no** getItemsChest.
- importItem/exportItem want the container's **network name** - plain sides
  ("up") fail with "Target 'up' does not exist" (the docs suggest "@up" style).
- `listCurios()` reads all curios at once; one unreadable item breaks it.
- Opened storage items (tanks): fluid functions vary by version; the code
  tries pullFluid/importFluid/insertFluid and pushFluid/exportFluid/extractFluid,
  in Advanced Peripherals filter style AND ComputerCraft style
  `(target, amount, fluidName)`. Containers move **1 bucket per call** -> loop.

**ME Bridge:** item/fluid functions take `(filter, target)`; `transfer()` in
base_me.lua tries both argument orders and remembers what worked. Old function
names exist on this version (getMaxItemStorage etc.); code tries new and old.
- `getItems()` crashes server-side ("invalid dist DEDICATED_SERVER") if ANY item
  in the network has a client-only tooltip -> the ME tab falls back to a
  "partial view" built from tag listings + name lookups. Known culprit:
  `hazennstuff:pendant_of_harmony` (Hazen N Stuff) - kept out of the network.
- Buffers: items via `minecraft:barrel_1` (saved by `mesetup` in me_setup.dat);
  fluids via `functionalstorage:storage_controller_0` (it also holds the
  owner's own items/fluids -> always move EXACT amounts, never "everything",
  except the explicit BUFFER -> ME button).

**Drones (PneumaticCraft):** teleport costs ~10,000 mL (~0.85 bar) even when it
fails; flying costs no air. Teleports only into loaded chunks (players and the
anchor turtle keep chunks loaded). Charging station + parking in base_drones.lua.

## Rules for changes
- ComputerCraft Lua (Cobalt, Lua 5.2 based): no `goto`, no `//`, no bit ops
  operators; use math.floor. Keep everything pcall-safe around peripherals.
- Never block the UI; no sleeps in drawing code.
- Never move or delete the owner's items/fluids except exact amounts the
  program itself put somewhere.
- After changing files, run `luac -p` on them, then tell the owner exactly which
  files to copy and what to test in game. Keep explanations short and plain.
- When an in-game API is unclear, ask the owner to run `report` (uploads all
  peripherals + functions to pastebin) or `tanks` / `me check` / `curios check`.

## Useful console commands (on the base computer)
help, report, tanks, mesetup, me check, me add <id>, curios check, disks
[data|move], drones, drone <n>, charger, turtles, turtle <id> <cmd>, update,
rescue, findlost, map [clear], exit [clear].
