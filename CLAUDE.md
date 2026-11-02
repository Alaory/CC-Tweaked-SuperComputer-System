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
- The MAP has two layers (base_map.lua): DETAIL (every column, newest
  `maxChunks` chunks) and OVERVIEW (1 value per chunk, never dropped; used at
  zoom >= 16 and where detail is gone). Files in `map/`: detail `<rx>_<rz>.dat`
  (4x4 chunks), overview `o<ox>_<oz>.dat` (32x32 chunks), compact text, on data
  floppies first (owner has at most 10), computer at most `computerKB`. Saved
  at most once a minute (MAP.autoSave in commsWorker) and on exit. In memory
  layers are TEXT, 4 bytes per cell (numbers in tables are costly in Cobalt).
  `MAP.get` / `MAP.getOverview(x, z)` return height, block. No ores (owner
  does not want them). An old `map.dat` is converted once on start-up.
  World border is -20000..20000 (CONFIG.map.border); zoom goes to 512 so the
  whole world fits. Big surveys (> 400x400 blocks) go through a queue
  (MAP.queueSurvey / feedSurvey, 64 spots per idle turtle). When the data
  floppies run low, empty floppies are made data disks automatically (one is
  kept for the turtle installer) and the owner is warned (popup, chat,
  footer) - MAP.checkSpace.
- Turtle updates: every new node.lua gets a number (v1, v2 ... in
  turtle_versions.dat). TT.updateTick (comms worker) updates ONE turtle at a
  time; a busy turtle keeps the update (UPD_READY) and installs it after its
  job; missing pieces are asked for ("updmiss"). Toasts on each update.
- Install drive: the Disk Drive under the computer ("bottom", not wired;
  CONFIG.turtles.installDrive). A floppy put in gets the installer + current
  node.lua at once (TT.prepareInstallFloppy on the "disk" event, comms
  worker) - only if empty or already an installer. Never used for the map.
- node.lua: the game's Lua (Cobalt) counts FILE-LEVEL locals into every
  function's 200-local limit (standard luac does not). Keep file-level
  helpers as plain `function f()` (the turtle program has its own
  environment), not `local function`. Check with
  `python3 tools/check_locals.py node.lua` (must stay well under 200). The
  base also compiles node.lua before sending it (TT.codeLoad).
- STOP (node.lua): clears the saved job at once (no resume after a reload);
  a job that ignores it for 2 s is cut off (FORCE_STOP: no new move/turn;
  stopWatch kills it when not STEPPING / modem on / no slot lock, then
  afterForcedStop). Base: t.held (saved) after STOP - STOP is sent again if
  the turtle reports a task after a reload; no patrol/survey batches; any
  non-quiet command, or a survey you start
  (MAP.queueSurvey), releases it; TT.available still lists held turtles. A resumed job waits 6 s first.
- node.lua never just ends: the main parallel.waitForAny is in a pcall; an
  error is written to `node_crash`, the turtle reboots (5 s, longer when it
  keeps crashing) and tells the base ("restarted after an ERROR: ..." in the
  turtle's log). Each command (immediate) is pcall'd too.
- `turtle <id> diag`: disk free, file sizes (program, backup, state, outbox,
  trail), saved job, starts, gear, last save error. writeFile never crashes on a
  full disk. On start, old outbox scans lose their ores (old versions); disk
  < 100 KB free -> outbox trimmed to 10, startup.old deleted ("clean" result).
- Chunky upgrade never comes off: every equip goes through equipOn (node.lua),
  which refuses the Chunky side and puts it straight back if the item that
  came off is a Chunky ("chunk" in the name). chunkyFix re-equips a loose one
  (only where turtle.getEquippedLeft/Right exist).
- Homes (TT.homeTick, comms worker): a turtle without a home is offered one
  ("homeoffer"): next to another turtle's home, +-1 in X or Z, not a home /
  offer / spot it reported bad. The turtle checks it the first time it goes
  home (HOMEPROBE: no digging, no retries - isFinal); blocked -> "homebad"
  -> next offer. Idle for CONFIG.turtles.idleHome s (default 120, 0 = off)
  away from home -> sent home (not held / anchor / stuck / needed by a big
  survey; at most every 10 min). A turtle that never refuelled and has < 1000
  fuel runs REFUEL once by itself (doRefuel; S.refuelDone).
- Fuel chest at home (node.lua fuelStation): idle AT home with fuel < lowFuel
  (2000) -> sucks from an inventory below/above/in front (never a turtle),
  burns ONLY fuel items up to stationFuel (20000), non-fuel and empty buckets
  go back; once a minute. Base sends low-fuel idle turtles home after 10 s.
- Permanent rescuer: t.rescuerRole (RESCUER button, saved in turtles.dat;
  base only). TT.patrolTick (comms worker) sends it to: no fuel (<20 for
  60 s), stuck (60 s idle), lost (silent CONFIG.turtles.rescueAfter, default
  180 s; no reinstall gear needed - arriving loads the area and wakes it). Never in the first 5 min after the base starts, never when half
  or more turtles are offline (server trouble); called off when the turtle
  is fine again; max 3 tries, 30 min apart (tries reset once the turtle is fine again). Rescuer goes home after each
  rescue, gets no big-survey batches.
- Themes (base_theme.lua): THEMES = 6 dark palettes, same JOB per colour slot
  (C.* / map colours unchanged). Chosen at start: theme.dat {mode, last} or
  CONFIG.theme, default "random" (never the same as last time). `theme
  [name|random]` switches live (setTheme) and saves. Keep new themes dark.
- Message log: pushNote -> noteLogAdd (base_me.lua) also appends to
  events.log (computer, 16 KB, then events.old.log); the EVENTS list is read
  back on start (after the last CLEAR marker). `events [n] [errors]` shows it.
- `$drone notify on|all|off` (owner, also buttons on the CHAT tab): pushNote -> notifyChat (base_chat.lua)
  sends the monitor's messages privately in chat; max 6/min, rest summed up;
  saved in chat_notify.dat.
- Autostart: `startup.lua` (top level of the computer) finds inventory.lua
  in any folder and restarts it after a crash (inventory.lua raises an error
  on a crash, returns normally on Ctrl+T). inventory.lua turns off
  `shell.allow_disk_startup` (the install floppy's startup.lua would run
  instead); the installer also starts the base program if run on a computer.
- `tools/preview/` draws the monitor outside the game (Lua 5.3 + Pillow); use
  it to check screen changes. It is not game code.

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
- **Curios moves (seen in game):** `exportCuriosItem(slotType, chest)` takes
  off ALL items of that slot type (as many as the chest takes);
  `importCuriosItem(slotType, chest)` puts on ANY fitting item from the chest.
  No way to choose the item. The item buffer is the owner's storage
  controller (holds their own items) -> never "any"/"all" there. Taking ONE
  of several / putting on goes through `CONFIG.me.curiosChest` (an EMPTY
  barrel only for curios). base_me.lua learns the arguments at runtime
  (curioSignature), logs every call in EVENTS, checks with listCurios.
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
fails; flying costs no air. Passenger watch: dr.rider (set after pickup) is checked every
2 s while moving (riderLeft); off = > 12 blocks apart twice -> "passenger got
off" -> the drone goes straight home. Long trips hop 160 -> 80 -> 48 blocks
before flying into an area that is not loaded. Teleports only into loaded chunks (players and the
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
rescue, findlost, map [clear], exit [clear], survey, theme, events.
