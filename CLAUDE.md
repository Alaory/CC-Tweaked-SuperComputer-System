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
  pageWorker, actionWorker, droneWorker, terminalWorker, chatWorker, commsWorker, mapWorker.
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
  `MAP.get` / `MAP.getOverview(x, z)` return height, block (getOverview also
  `partial`: a chunk only touched at its EDGE by a neighbouring scan - a 17-wide
  scan reaches 1 column into the next chunk; stored as the top bit of the
  height, "!" before the cell in the files). Surveys only skip chunks that are
  MAP.scanned (overview and not partial). The MAP draws 2x2 chunks per cell
  from zoom 32. No ores (owner
  does not want them). An old `map.dat` is converted once on start-up.
  World border is -20000..20000 (CONFIG.map.border); zoom goes to 512 so the
  whole world fits. Big surveys (> 400x400 blocks) go through a queue
  (MAP.queueSurvey / feedSurvey, 64 spots per idle turtle). Every batch
  handed out is kept (q.out[id]); when the turtle answers with a failure, or
  is idle 30 s while it still has one, its UNSCANNED spots go to q.redo and are
  handed out first (MAP.reclaim). SURVEY: ALL for small areas also goes through
  the queue (MAP.addSurvey); SURVEY: THIS ONE is a direct order. A spot is
  done when MAP.spotDone (its own column in detail, or its chunk fully in the
  overview) - NOT MAP.scanned alone (17-block spots vs 16-block chunks).
  AUTO-MAP (MAP.auto, auto_survey.dat, default on; CONFIG.map.autoSurvey =
  false to start off; MAP tab ON/OFF, `survey auto on|off`): MAP.autoTick
  (comms worker) starts a queue {auto, spiral} around CONFIG.drone.home when
  none runs - spiral(n) from the base outward to the border; a manual survey
  goes first (auto cursor saved, unfinished spots carried over); paused while
  MAP.full (floppies full, set in checkSpace); STOP on it turns auto off. When the data
  floppies run low, empty floppies are made data disks automatically (one is
  kept for the turtle installer) and the owner is warned (popup, chat,
  footer) - MAP.checkSpace.
- Turtle updates: every new node.lua gets a number (v1, v2 ... in
  turtle_versions.dat). TT.updateTick (comms worker) updates up to 3 turtles at a
  time (TT.sending; t.updState sending/ready/retry + t.updNote for the screen;
  runs when autoUpdate is on, or 10 min after UPDATE TURTLES = TT.updateForce); a busy turtle keeps the update (UPD_READY) and installs it after its
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
  base also compiles node.lua before sending it (TT.codeLoad), and sends /
  writes a SHRUNK copy (TT.shrinkCode: whole-line comments, --[[ ]] blocks and
  indentation removed, every line kept in place so error line numbers match;
  ~97 KB vs 128 KB - a floppy holds 125 KB). Falls back to the full text if
  the small one does not compile. CODE.ver is the hash of what is sent.
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
- Digging (node.lua tryDig): only with a pickaxe the turtle carries (swapped in on
  the modem side for the dig), only NATURAL blocks (CONFIG.digOk, exact names after
  the colon, "*x" = ends in x - never bricks/smooth/polished/cobblestone/planks),
  never within digNearHome (24) of its home, never into a home being probed.
  Allowed when the turtle's setting dig is on (base: SETTINGS > TURTLES "Turtles
  dig ..." -> TT.setDig, sent to all and on every hello) or always during rescue /
  sweep jobs (DIG_JOB).
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
  Reusable fuel (S.reuse, e.g. a modded item that is never used up) in the
  chest is recognised (refuel(0) = is fuel; one refuel(1) that leaves the count
  = reusable), KEPT in the turtle and topped up from; skipped if it already
  carries one. Shared fuel chest: CONFIG.turtles.fuelChest {x,y,z} -> the base
  sends ONE low-fuel idle turtle at a time ("fuelup", TT.fuelTrip; others wait
  instead of going home); the turtle parks on top (else beside, facing it),
  takes fuel from THAT chest only (fuelStation(side)), then goes home.
- Avoid players (TT.avoidTick, comms worker; TT.threats / TT.nearThreat): the
  Player Detector's positions (refreshed every 10 s on every page while turtles
  exist and avoidRange > 0) vs turtle positions. A turtle doing MAP work (task
  "survey..." / "scanning...") with a player within CONFIG.turtles.avoidRange
  (100, 0 = off) gets STOP with again=true (no hold), t.avoidHome -> "home" once
  idle; its batch is reclaimed as usual. nextBatch puts spots near a player into
  q.redo (later). avoidWho "strangers" (default: not owner, not allow list) or
  "everyone" (not owner). Only players whose dimension is KNOWN to be the
  overworld (unknown dim = not avoided: a mining dimension uses the same x z).
  nextBatch keeps q.lastWhy {near, who, done, redo} -> TT.idleWhy says why a
  survey hands out nothing. A player within avoidRange
  of the turtle's own home (a visitor at the base) is not avoided by that turtle
  (no stop -> home -> leave -> stop loop). No owner known yet -> nobody avoided.
- Turtle status (TT.status(t) -> key, LABEL, colour, why; base_turtles.lua):
  OFFLINE / NO FUEL (<20) / STUCK (t.stuck while idle and not moved > 3 blocks
  from t.stuckPos) / STOPPED (held) / FINDING A WAY (task backing up, retracing,
  planning/following a route) / NOT MOVING (busy, no move and no task change
  for 90 s; t.movedAt / t.taskAt from TT.receive; not for waiting/refuel/gps/
  install tasks) / WORKING (ANCHOR, RESCUER) / IDLE + TT.idleWhy (fuel below
  surveyMinFuel, not chosen / excluded, floppies full, auto-map off/done, got
  nothing for 60 s ...). Used by the TURTLES page and `turtles`. TT.stallTick
  (comms worker): NOT MOVING 3 min -> STOP (no hold, once per 10 min) +
  sysLog; the turtle is free again, and if it cannot move the next trip fails
  -> STUCK -> rescuer. No turtle selected -> drawFleet (FLEET card: status
  counts, fuel total + lowest, program, survey progress, mining teams, NEEDS A
  LOOK list - tap = select); tapping the selected turtle again deselects. List
  fuel colours by amount (<1000 red, <5000 yellow), not by share of the tank.
- Route planner (node.lua astar): a sideways direction change costs 0.4 (a
  turn), opposite 0.8 (HD[k] = last sideways direction); h weighted 1.001
  (tie-break). tools/navsim/world.lua: turns cost time and are counted; maze /
  maze2 (TX=44) and "astar" (planner alone on 6 random mazes) scenarios.
- Mining teams (miner.lua, base_mining.lua MINE, base_ui_mining.lua; TURTLES >
  MINING): two turtles per mining dimension (S.dim overworld/nether/end), same
  signed protocol with m.mine = true -> TT.receive hands them to MINE.receive
  (never in state.turtles: no map/survey/home/rescue). LOADER = Chunky + Ender
  Modem, never digs, follows the miner's corridor (team proto "basemine":
  loaderhere/paired pairing by dim, follow {ref, pts} / arrived). MINER = End
  Automata Core fixed + pickaxe; modem / Geo Scanner swapped in on the free side
  (report every CONFIG.checkIn 30 s, base commands queue in u.queue until
  m.lastCmd shows them). Works with the DEFAULT chunkyTurtleRadius 0 (owner
  cannot change server configs): the loader parks in X1up (above the first
  tunnel block of the miner's chunk) for the whole chunk. Crossing (crossTo):
  at the edge E the miner digs X1 + X1up, sends follow (trail + Eup + X1up),
  waits for "got", then steps into X1 FIRST (the game may pause / shut it
  down there - it restarts and continues from the saved plan); the loader comes
  through E and Eup into X1up. waitLoader before the next crossing. The start
  chunk (ci 0) is only left; loader + miner must start in the same chunk.
  calibrate() before a new plan: Geo Scanner scan r 1 finds the loader behind
  -> the miner's facing is corrected; the loader gets "setpos" (its real
  position + facing = towards the miner, it turns until inspect sees a turtle)
  and answers "posok". START resets the unload timer; an unload trip with
  nothing to unload is skipped. MYVER shown on the turtle and the MINING tab.
  GPS (the owner has a GPS system in the mining dimension): gpsCheck at start,
  at every miner report (modem on anyway) and every 30 s on an idle loader -
  the tracked position is corrected; setup / miner here offer the GPS spot.
  geoScan(r): the Geo Scanner's scan function is looked up by name (it is NOT
  "scan" on the owner's version; the error lists the methods). Items in the
  miner at START (not tools / coal) are the owner's (S.own): never unloaded;
  more than 4 such slots -> START refused; full of only those -> HALT.
  Ctrl+T (Terminated) is passed on, not saved as an error. Endless fuel
  (CONFIG.fuelItems "*mining_dim_core*", or learned S.reuse): burnCoal uses
  it first (refuel(1) keeps the item), both roles (loader before every step);
  counts as a tool (never unloaded). Loader following: before each walk
  gpsCheck + gpsFacing (one step forward/back, GPS delta = real facing),
  GPS check after every leg (5 misses -> STUCK); the miner waits for
  "arrived" at the START of each new chunk ("go") and before crossing, max
  5 min, then stops with "the loader did not follow". Works with 1-chunk AND
  3x3 Chunky loading (minesim default = 1 chunk, scenario r1 = 3x3). MINING tab: per
  team unitBox (status, why wrapped, fuel bar from m.fuelMax, position),
  FIELD map (one cell per chunk index, rowLength per row), layer bar, ores/hour
  (u.runT0/u.ores0 on the base), unload countdown, item lists with totals,
  START/PAUSE, UNLOAD NOW, NEW FIELD (actButton kind "minecmd", two taps),
  TO DO hint, wrapped LOG. Plan:
  rows of rowLength chunks forward from the start facing, next row to the right;
  per chunk: tunnel to the centre at the start Y, layers every 17 down to minY
  (Geo Scanner r 8, ores + CONFIG.mining.want inside the chunk), exit to the
  chunk edge, handoff. Junk thrown away; full -> shulker in front with air
  above (stash). Every dumpEvery s (or full shulker): savePoint "work", warp
  "station", unload (empty block in front = shulker there for an Import Bus;
  inventory in front = drop + shulker ABOVE and suckUp), warp back. noMine /
  noDig around the station. Base sends cfg (dumpEvery, rowLength, noMine,
  want, keep) when it changes. tools/navsim/minesim.lua runs the real
  miner.lua x2 + base_mining.lua in a voxel world (plain/reboot/want/full/direct).
- AWAY MODE (base_away.lua AWAY, comms tick AWAY.tick): owner offline (Player
  Detector; players refreshed every 30 s on any page) for CONFIG.away.after
  (300 s) -> AWAY.start: snapshot (MINE got/ores/ci per dim, MAP.ovN, turtles
  up to date), monitor shows the MAP following the turtles (AWAY.followMap:
  zoom to fit home + online turtles + q.out spots; previous page restored),
  auto-map ON if you had it off (AWAY.autoOn, off again after), turtles top up
  fuel at 3x lowFuel (homeTick), map saved every 30 min. Turtle updates wait
  while the owner is online (CONFIG.turtles.updateWhenAway, max 2 h,
  TT.updWaiting; UPDATE TURTLES forces). Back -> AWAY.report() (time away,
  map growth, mining per dim with top items, updates, base off times, system
  warnings since "away mode on", "Needs you" list) -> box (USER_ACTION), chat
  to the owner (up to 6 lines), SYSTEM tab card WHILE YOU WERE AWAY, sysLog,
  `away` console command. away.dat keeps it over restarts. SETTINGS > AWAY.
  Unknown owner state (no detector / old data) -> nothing changes.
  NOTE cfg helpers (MINE.cfg / AWAY.cfg): `type(t)=="table" and t[k]` gives
  false, not nil - use an if (fixed; the mining cfg was never sent before).
- Permanent rescuer: t.rescuerRole (RESCUER button, saved in turtles.dat;
  base only). TT.patrolTick (comms worker) sends it to: no fuel (<20 for
  60 s), stuck (60 s idle), lost (silent CONFIG.turtles.rescueAfter, default
  180 s; no reinstall gear needed - arriving loads the area and wakes it). Never in the first 5 min after the base starts, never when half
  or more turtles are offline (server trouble); called off when the turtle
  is fine again; max 3 tries, 30 min apart (tries reset once the turtle is fine again). Rescuer goes home after each
  rescue, gets no big-survey batches.
- Themes (base_theme.lua): THEMES = 6 dark palettes, same JOB per colour slot.
  The 11 slots the MAP uses (MAP_SLOTS: green lime blue yellow orange white
  brown red cyan purple pink) always keep the midnight colours; a theme only
  changes the frame (bg, cards, lines, buttons, titles). Chosen at start: theme.dat {mode, last} or
  CONFIG.theme, default "random" (never the same as last time). `theme
  [name|random]` switches live (setTheme) and saves. Keep new themes dark.
- Message boxes (pushNote, base_me.lua): a BOX only for CONFIG.notes.show
  ("important" = warnings + errors, default; "errors", "all", "none") - INFO/DONE
  go to EVENTS only; USER_ACTION (set around handleTouch and runAction in
  base_workers.lua) = always a box; max one new box per 4 s (errors excepted),
  same box again within 60 s: no; same message within 30 s: not logged again.
  Boxes at the bottom-right (CONFIG.notes.where = "top" for the old place), max 3.
- Message log: pushNote -> noteLogAdd (base_me.lua) also appends to
  events.log (computer, 16 KB, then events.old.log); the EVENTS list is read
  back on start (after the last CLEAR marker). `events [n] [errors]` shows it.
- Header: pages are GROUPED (GROUPS in base_ui_core.lua: YOU = inventory/storage/
  curios, PLAYERS = players/access, ME, DRONES, TURTLES = turtles/map, SYSTEM =
  system/events/settings); a group with several pages shows small sub-tabs on
  row 5 (hit "page"); the top tab is hit "group" -> openGroup (last page used).
  pageTabs() lists the pages that exist; headerTabs() the groups.
- SETTINGS page (base_ui_settings.lua, SETTING_GROUPS): click-only - num (-/+ by
  step, min/max), cycle, bool, pos ("USE MY POSITION" / "BLOCK UNDER ME" from
  the Player Detector, tap twice), custom (theme, chat messages, auto-map).
  setSetting / resetSetting (base_devices.lua; CONFIG_ORIGINAL keeps the
  base_config.lua value for RESET). Only settings that are read live belong here.
- SYSTEM tab (base_ui_system.lua): STATUS (state.sys from sysRefresh in the comms
  worker - disk/floppy calls never in drawing), SYSTEM LOG (sysLog -> system.log,
  16 KB + system.old.log, newest 100 in SYSLOG; only system things: base off /
  crash, new turtle program, floppies, auto-map, turtle crashes), times the base
  was off, ACTIONS (save map, update turtles, restart base). settings.dat is
  applied over CONFIG at the top of base_devices.lua - base_config.lua never changed.
- `$drone notify on|all|off` (owner, also buttons on the CHAT tab): pushNote -> notifyChat (base_chat.lua)
  sends the monitor's messages privately in chat; max 6/min, rest summed up;
  saved in chat_notify.dat.
- Base off-time (base_workers.lua): base_alive.dat gets the real time every 30 s;
  baseStartCheck (inventory.lua, after buildWindow) reports a gap > 90 s as
  "BASE WAS OFF from .. to .. - why" (crash text / you stopped it / unloaded or
  server restart); baseExit marks crash or Ctrl+T. `uptime` lists the last 10.
- Storage helpers (base_store.lua + store.lua): other computers on the WIRED
  network run store.lua (rednet protocol "basestore", wired modems only; a helper
  belongs to the first base that uses it - `store reset` on it to change). The map
  saves to them after the data floppies, before this computer (places(): rank
  floppy > helper > computer; path "store:<id>/map/<key>.dat"; MAP.rsize = sizes).
  Calls wait for answers, so map saving runs in its own mapWorker (also finds new
  helpers ~20 s after start, then every 5 min); at start only helpers seen before
  are asked (store_helpers.dat, no 2-s lookup). Helper gone -> files go to the
  computer. `store [find|update]` on the base computer. Updates: a store.lua next to
  inventory.lua (STORE.code, must compile) goes to every helper whose version
  (hello -> ver = checksum of its startup.lua) differs (op "upd": checksum +
  compile check, then startup.lua + reboot) - STORE.updateAll in the mapWorker.
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
| base_ui_*.lua | one file per page (base_ui_system.lua = STATUS, base_ui_settings.lua = SETTINGS) + base_ui_core.lua (header groups, cards, buttons, bars, footer) |
| node.lua | the turtle program |
| miner.lua | mining-dimension team program (MINER + LOADER roles; installed by hand, not OTA) |
| base_mining.lua / base_ui_mining.lua | mining teams on the base (MINE) / MINING tab |
| base_away.lua | away mode: uses the time you are offline, WHILE YOU WERE AWAY report |

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
before flying into an area that is not loaded. A refused (blocked/tight)
target with OPEN SKY above it (MAP.get column top <= y-1; skyOpenAbove) ->
one teleport into the air above + fly down (skyApproach) instead of trying
the nearby spots; under a roof / unknown column / pickups (noFly): as before. A FAR
target refused at once is not hopped to straight away: one teleport into the
air above it (map top + 8, or hopY when unknown) tells loaded (spot was just
blocked -> carry on from there) from not loaded (-> hops). Everything refused
and the spot is UNDER GROUND (map top > y): the drone lands on the surface
right above it. Teleports only into loaded chunks (players and the
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
