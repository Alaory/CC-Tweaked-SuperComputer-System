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
  LOST TIMERS: CraftOS drops events (timers too) that arrive while a coroutine waits
  for a peripheral answer. So the commsWorker 2-s jobs run by the CLOCK (nextTick; a
  new timer each tick replaces a lost one), uiLoop re-arms clockTimer / drawTimer,
  waitFor has a deadline. (Before: one lost timer stopped every 2-s job - updates
  "queued" forever, idle turtles never sent home.) test_lost_timer.lua.
- **Peripheral calls belong in workers or fetch functions, never in drawing
  code.** Drawing reads `state.*` only.
- Drawing: everything is drawn into an off-screen window `win`; `flushWindow()`
  copies only changed rows to the monitor (big performance win - keep it).
  The MAP image (state.mapImage) is rebuilt at once when the VIEW changes, but
  for new map data (MAP.version - every scan) at most every 5 s: with many
  turtles scanning, rebuilding it on every draw made the base lag. okey() is
  cached by number (text building is slow in Cobalt). AWAY.followMap moves the
  view only on a zoom change or when the middle is off by > 1/4 screen.
- Buttons: `actButton(x, y, w, h, label, action)`; a second tap confirms; the
  action is queued and run by `runAction(a)` (base_me.lua) in the action worker.
- Data files are written with `saveFileSafe(path, text)` (base_theme.lua):
  only if they fit, through a temp file, never half-written. Big files go
  through `dataFile(path)` so they can live on data floppies (`disks data`).
- The computer has only **1 MB of disk** - keep data files small. The program
  files alone are ~800 KB (miner.lua is NOT needed on the base). Small data files
  use serialSmall (compact textutils.serialize); survey_queue.dat goes through
  dataFile (floppy first). The map leaves CONFIG.map.keepFreeKB (96) free on the
  computer. turtles.dat goes through saveFileSafe. `disks` lists floppies,
  storage helpers and the biggest files on the computer.
  OFF THE COMPUTER BY DEFAULT: dataPath(name) (base_theme.lua; dataFile cached 60 s)
  puts events.log / system.log (+ .old via logPaths), mining.dat, me_names.dat and
  turtles.dat on a DATA FLOPPY when there is one (the computer's copy moves along).
  MAP.offload (mapWorker, every 10 min, every minute when the computer has < 160 KB
  free) moves map files saved on the computer earlier onto floppies / storage helpers
  (MAP.save only rewrites CHANGED files, so old ones stayed on the computer).
  test_disk_place.lua.
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
  The map is READ IN THE BACKGROUND (MAP.loadNow, first thing in mapWorker;
  loadYield after every file, only in that coroutine - TT.yieldCo): before
  MAP.loaded, scans wait in MAP.pendingScans (added after), MAP.save refuses
  (a half-read map must never overwrite the files), feedSurvey / autoTick wait,
  the MAP tab says "Loading the map". Reading it at start-up froze the base
  ~10 s. node.lua (TT.codeLoad: compile, shrink, hash) is also checked in the
  mapWorker (start + every 30 s) with TT.workYield pauses, not in the comms
  worker (the install-floppy "disk" event still loads it at once).
  World border is -20000..20000 (CONFIG.map.border); zoom goes to 512 so the
  whole world fits. Big surveys (> 400x400 blocks) go through a queue
  (MAP.queueSurvey / feedSurvey, 64 spots per idle turtle). Every batch
  handed out is kept (q.out[id]); when the turtle answers with a failure, or
  is idle 30 s while it still has one, its UNSCANNED spots go to q.redo and are
  handed out first (MAP.reclaim). Queued surveys are clamped to the
  world border and go in a SPIRAL (q.spiral + q.rect) from the area's point
  nearest to the base (CONFIG.drone.home) - never row by row from the far corner
  (that sent turtles 28,000 blocks away when zoomed out); spiral spots outside
  the area are skipped cheaply. Old saved row-by-row queues are converted once in
  feedSurvey: their old far batches / redo spots are DROPPED and the turtles that
  had one get t.recall (saved in turtles.dat) - TT.receive stops their survey job
  (also when they resume it after being offline), then sends them home. The queue file is written only when it changed (or once a minute). PACK mode
  (CONFIG.map.pack, default on; SETTINGS > MAP): the free turtles get spots in
  ROUNDS (q.wave): n*packSpots (3) consecutive spiral spots shared out in turn
  (side by side, 17 blocks apart), by measured speed (t.packRate from
  batchResult) so they finish together; the next round only when the whole
  pack is done (or after packWait 300 s). Keeps them ~20 blocks apart (sim:
  83% of free-running speed) so one wake-up (rescuer / player) reaches all.
  t.packWait -> TT.idleWhy "waiting for the rest of the pack". A turtle still holding
  a batch (q.out[id]) is never free (its batch is reclaimed after 30 s idle first -
  overwriting it lost the unscanned spots). SURVEY: ALL for small areas also goes through
  the queue (MAP.addSurvey); SURVEY: THIS ONE is a direct order. A spot is
  done when MAP.spotDone (its own column in detail, or its chunk fully in the
  overview) - NOT MAP.scanned alone (17-block spots vs 16-block chunks).
  WORK AREA (SETTINGS > MAP "Work area: corner 1/2" = CONFIG.map.areaA/B, x z;
  "Work area" tap = whole world): MAP.area / MAP.inArea (also the border) -
  queueSurvey clamps to it (returns 0 when the view is outside), nextBatch skips
  spots outside (cheap) and drops redo spots outside, surveySpots leaves them out,
  auto-map spirals inside it (q.areaKey; another area -> queue dropped, cursor 0);
  the MAP draws its edge ("+"). Turtle TRAVEL itself is not limited (goto / home).
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
  runs when autoUpdate is on, or after UPDATE TURTLES = TT.forceUpdate UNTIL every online turtle has it (max 1 h; a fixed 10 min left the last ones out); version "?" counts as outdated: button,
  console `update` (it did NOT force before), pocket "updateall"; busy turtles that
  already hold it get STOP (no hold) and install at once; list label UPDATE WAITS /
  UPDATE AFTER JOB / UPDATE QUEUED); a busy turtle keeps the update (UPD_READY) and installs it after its
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
- DUPLICATE TURTLES (a server crash while a turtle crosses into the next chunk leaves
  SEVERAL turtles with one id: same program, items AND the same disk - they all hear its
  rednet messages). node.lua: SESSION (random, memory only) in every report (m.ses);
  a cmd with m.ses for another copy is ignored; "dupstop" -> DUP (stops, takes no jobs,
  writeFile refuses - the shared disk belongs to the real one, no updates, GPS position
  reported, m.dup); "dupfree" undoes it. Base TT.dupSeen (before the lastN check): two
  sessions that each spoke after the other appeared (a restart's old session goes silent)
  = copies; t.mainSes = not already DUP, nearest its home; the others get dupstop with
  THEIR ses (every 15 s until m.dup); their reports never touch t; t.dups -> TT.dupText
  (turtle card, FLEET needs list, pocket, away report) + one WARNING / sysLog. While
  copies exist TT.send adds ses = t.mainSes (never otherwise - a restarted turtle must not
  be locked out). Gone 10 min -> forgotten. The first time copies are seen the real one is
  CHOSEN (not whichever spoke last). MINING turtles too (miner.lua m17: SESSION, DUP, save /
  sendTeam refused, dupPark freezes the copy between steps; miners hearDup() every 10 s
  between steps - only "dupstop" acted on, the rest kept in BACKLOG for the next listen;
  base MINE.receive -> TT.dupSeen opt.where: t.dupAnchor = where it was when the 2nd session
  appeared; MINE.cmd adds ses). rememberOwn on a NEW FIELD keeps the first START's record
  (mined ore is not "yours" - before: "9 slots hold your own items", STOPPED).
  USING COPIES (CONFIG.turtles.copies "use" default, SETTINGS > TURTLES; "stop" = park):
  the copy gets "becomecopy <n>" (its ses) -> name "<label> [c<n>]" (the label lives in the
  turtle BLOCK, not the shared disk, so it survives restarts) + its own files (node:
  STATE/TRAIL/OUTBOX/SWEEP/CRASH .. COPYSFX; miner: miner_state_c<n> keeping role, key,
  dim, station ...) + restart. Base: copy n of id = turtle n*100000 + id (TT.realId /
  TT.freeCopyNo / TT.copyRes); TT.receive maps m.copy -> that number, the comms sender maps
  back (rednet to the real id, msg.copy = n); node/miner ignore cmds whose copy tag is not
  theirs. The "becomecopy" ok result marks the old session promoted (no longer a copy).
  Miners in the team: MYTID = n*100000 + id, team messages carry from / to (radio to
  to % 100000; handle uses m.from as the sender). LOADER copies are always parked (one
  loader per dimension; opt.canUse). A promoted miner joins a team when no plan runs
  (the next NEW FIELD). test_dups.lua, node_dup.lua, miner_dup.lua.
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
  sweep jobs (DIG_JOB). Also a HOME trip when the turtle is STUCK (S.stuck) or "home dig":
  TT.homeTick part 3 sends a stuck idle turtle that carries a pickaxe (t.gear) "home dig"
  after 30 s, every 10 min, max 3 tries (t.digOutTries, reset once not stuck) - the
  rescuer stuck in a cave after a rescue. test_digout.lua. MINE UP (button on the turtle card
  with a pickaxe, two taps; pocket BOTS too): job "digup" [surface Y = MAP.get top + 1]
  -> digUp: straight up, tryDig (natural only, not near home), stops at that Y or after 6
  free blocks; says why it stops. tools/tests/node_digup.lua.
- DRIVE page (base_ui_drive.lua, TURTLES group "drive"): pick a turtle (dsel; picking it = "look" at
  once). The owner tried 5 layouts and chose the FIRST (three grids) improved: ABOVE IT /
  ITS LEVEL / BELOW IT, seen from above NORTH UP (like the MAP) with N/E/S/W labels,
  radius 2 (5x5), big cells with a gap row; the turtle = green arrows its way (>>>);
  interesting blocks get a 3-letter code + a "WHAT THE LETTERS MEAN" legend, plain stone /
  dirt / deepslate are just grey (PLAINS); black = air, ? = not seen. TAP: the 4 blocks
  next to it on ITS LEVEL ("GO" -> gon/goe/gos/gow: node faces that way, then minef), the
  middle of ABOVE ("UP" mineu) / BELOW ("DOWN" mined). Buttons: TURN LEFT, FORWARD, TURN
  RIGHT, UP, DOWN, SCAN AROUND, STOP, GO HOME, BACK, MINE UP TO SURFACE, DIG ANYWAY.
  Every step the turtle looks again (front/up/down + Geo Scanner radius 1 = scanR; SCAN
  AROUND radius 3; TT.lookIn only replaces the scanned cube). driveRows / driveWord (six
  rows with keys) stay for the keyboard: console `drive <id>` and the pocket DRIVE IT
  (W A S D, SPACE, SHIFT). Data: t.view.cells (WORLD positions
  "x,y,z" -> name / false = air; TT.lookIn from the turtle's "look" message: front/up/
  down every step, LOOK = Geo Scanner r 3 as "dx,dy,dz,name;..."). Buttons -> TT.drive
  (quiet "drive" {act, force}; ends a STOP hold): f b u d l r, digf/u/d, minef/u/d, look;
  STOP / GO HOME / MINE UP TO THE SURFACE. node.lua immediate "drive": refused while a
  job runs (STOP first); driveMove = one try (+ one attack), never waits long; driveDig:
  natural blocks, else / near home only with DIG ANYWAY (two taps, t.driveAnyway from
  the refusal), NEVER inventories / computers / machines (DRIVE_KEEP), even forced.
  The page says "no answer for N s" instead of hanging. test_drive.lua, node_drive.lua.
- Chunky upgrade never comes off: every equip goes through equipOn (node.lua),
  which refuses the Chunky side and puts it straight back if the item that
  came off is a Chunky ("chunk" in the name). chunkyFix re-equips a loose one
  (only where turtle.getEquippedLeft/Right exist).
- Homes (TT.homeTick, comms worker): a turtle without a home is offered one
  ("homeoffer"): next to another turtle's home, +-1 in X or Z, not a home /
  offer / spot it reported bad, never next to the factory builder's / crafter's home
  (the chest + the BUILD SPOT: a new turtle offered the build spot as its home never
  left it); none free one block away -> two blocks away. The turtle checks it the first time it goes
  home (HOMEPROBE: no digging, no retries - isFinal); blocked -> "homebad"
  -> next offer. Idle for CONFIG.turtles.idleHome s (default 120, 0 = off)
  away from home -> sent home (not held / anchor / stuck / needed by a big
  survey; at most every 10 min). A turtle that never refuelled and has < 1000
  fuel runs REFUEL once by itself (doRefuel(true); S.refuelDone) - only up to FIRST_FUEL (1000), then
  it can leave (factory build spot); idle top-up does the rest wherever it waits. A job that comes
  BEFORE that first refuel: ensureFuel (first move, fuel < 20) runs it (before: endless fuel was not
  known yet -> 0 fuel, the new turtle never left). node_firstfuel.lua.
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
- Mining teams (miner.lua m16, base_mining.lua MINE, base_ui_mining.lua; TURTLES >
  MINING): per mining dimension ONE LOADER + up to CONFIG.maxMiners (5) MINERS.
  Same signed protocol with m.mine = true -> TT.receive -> MINE.receive (never
  in state.turtles). Team proto "basemine": loaderhere / minerhere (join, by
  dim; only while no plan runs), team {team, plan} (the plan, every 30 s),
  hello (every miner report - liveness), needlayer {ci, done} / layer {ci, li},
  ready {ci} / go {ci} / stepped {ci}, unloadreq / unloadok / unloadwait /
  unloaded, unloadnow. LOADER = leader (modem always on): S.plan {id, sx, sz, f,
  yt = loader.y-1, x0, z0, ci, phase work|cross, ready, queue, assigned};
  START / PAUSE / NEW FIELD / UNLOAD go to the loader (base buttons). Every
  turtle computes the same geometry: chunkAt (rows of rowLength), chunkCols ->
  entry column, exit column (straight on to the far edge; at a row turn the
  entry is already on that edge -> exit shifted one block), dir. Miner k
  (1..n by ID): own SHAFT column (SHAFTS offsets), own LANE at the exit column,
  height yt-(k-1). Miner 1 first digs the 2-high main tunnel entry -> exit
  (TUNNEL2; the loader moves at yt+1) and at its lane also X1up. Layers come
  from the loader one at a time, DEEPEST FIRST (fillLayers / needlayer): a
  miner goes down once and works up, nobody waits for a slow one. Per layer:
  own shaft -> centre at that Y -> scan (KNOWN/KBOX) -> orderTour -> planTo /
  walkPath / mineAround (in place) -> back to own shaft. Crossing: all at
  their lanes "ready" (X1 dug) -> loader GPS-checks position + facing, goes to
  Eup, "go" -> each miner saves the NEXT job first, modem on, steps into the
  next chunk, "stepped" -> loader steps after (waits <= 15 s). CHUNK_LOCK: a
  working miner never steps out of its chunk (would = position/facing off ->
  GPS re-check, retried up to 5x). A miner silent 20 min -> the TEAM PAUSES
  (never left behind). A miner deleted by a server crash: base `mine
  drop <id>` -> loader cmd "drop" (out of S.team, its assigned layer back to the
  queue, ALL ready flags cleared, a crossing without "go" back to work); miners
  leave the ready wait when myIndex() changes; a new miner 1 digs the main
  tunnel of the current chunk first (J.tunnelDone); a dropped miner that is
  alive gets a team list without itself -> leaves (S.leader nil). minesim
  team2drop/team3drop/team5drop/team3dropalive (DROPIDX = which miner). The loader
  answers ready/needlayer/unloadreq from a non-member (isMember) with the team list,
  and sends it to a dropped miner directly - an alive dropped miner leaves. S.dropped
  keeps it from joining again until a NEW FIELD (newTeamPlan clears it). A lost LOADER: MINE.drop forgets it; miners (m15) leave a loader silent 10 min
  (LEADER_SEEN) when another one says loaderhere. MINE.drop(id) (console
  `mine drop` and a DROP button on the MINING tab for a miner gone 20+ min). Unloading: one miner at the station at a time
  (S.stationUse, 6 min max); each miner needs its own `miner station` (the
  point lives in its core). SELF-REPAIR (m16): saved times are REAL time (now(), epoch s) - os.clock restarts
  at 0 after a server crash, so S.stationUse / S.seen kept the station "busy" / a miner
  "never silent" for hours; the loader clears stationUse on start and when its holder's
  hello says dumping=false. A failed teleport TO the station = keep working, retry in
  5/10/20... min (S.dumpRetry); FROM the station = wait there and retry (~30 min);
  restart at the station -> the main loop finishes the trip first. Any teamStep error
  = retry by itself (30 s ... 10 min, GPS + facing re-check, FAILS up to 8) before
  STOPPED. Loader: a silent miner pauses the team (S.pausedFor) -> it goes on by itself
  when that miner talks again; silent 60 min (CONFIG.autoDrop) with others left -> it is
  dropped and the team goes on. minesim clock restarts per boot; scenarios
  team3crashunload (crash while the station is marked busy, holder lost), team2warpfail
  (station unreachable 40 min - keep mining), team3silentback (silent 25 min, resumes).
  Ores (isOreBlock): tags (:ores, _ores, /ores, not
  ores_in_ground), names _ore / ore_ / _ore_ (not _block), CONFIG.ores +
  mining.ores (extraOres), never mining.skipOres. Turtles start on the
  SURFACE (loader; miners next to it, same chunk). Set up NEXT TO the unload station (m14): miners send
  their station (m.st on every team message -> S.stations); planTransit on a new plan:
  the start chunk within noDig of one -> P.transit chunks straight on are crossed in
  the AIR at P.fy (tunY; no digging, no layers), the field (fieldAt) starts beyond
  them so its rows never come back; the loader comes down its entry column after.
  Base: loader reports transit, MINE.totals ci minus it / T.moving. minesim nearstation. GPS: gpsCheck at start /
  reports, gpsFacing (canDig) after a restart and on a new plan. Fuel: the
  Mining Dim Core is OPTIONAL (not in every pack). burnCoal: known endless
  items first (CONFIG.fuelItems / mining.fuelItems from the base, S.reuse),
  then coal, then - still low - any other fuel item it carries (refuel(0)):
  one that keeps name + count after refuel(1) is LEARNED as endless (S.reuse,
  kept as a tool, never unloaded); others are simply burned. Junk is also
  LEARNED (m9): digDir records what each dig dropped (learnDrops) - from an
  ore / wanted block (DIG_TARGET, isOreBlock on the inspected block) =
  S.oreDrops, from a block only dug through = S.junkDrops; isJunk = vanilla
  list or junkDrops-but-never-oreDrops (modded stones, clay ...). Facing
  (m10): MINERS never take a test step (at a chunk edge it can end in an
  unloaded chunk): scanFacing = Geo Scanner r 1 vs inspecting the 4 sides;
  only if that is ambiguous (open air) AND not on a chunk-edge block, the GPS
  test step (modem put back on first - gpsHere does that for miners). The
  loader keeps gpsFacing (its Chunky goes with it). A crossing whose "go" is
  out is always finished (P.goSent), even when PAUSE / NEW FIELD come in
  (NEWFIELD_LATER); a paused miner still steps over then (crossingDue). Miners: no plan / plan not running -> S.running false
  (the base button follows the LOADER's running only). Log entries carry e
  (epoch): the merged team log sorts by it. Owner's items in a miner at START (S.own) never unloaded (> 4 slots ->
  refused). geoScan looks the scan function up by name. MINING tab: team card
  per dim (unitRow per turtle, FIELD map from the loader's ci, MINE.totals,
  items, START/PAUSE TEAM, UNLOAD NOW, NEW FIELD two taps, TO DO, merged LOG).
  tools/navsim/minesim.lua: 1 chunk loading (r1 = 3x3), freeze + shutdown,
  ores in veins, caves; scenarios plain/teamN/caves/reboot/full/direct/core/
  loaderdrift/wrongface/gpsfix/r1/nofuel/ownfull/geoname/corein/modemon (and
  combinations like team3reboot, team5caves). 1 miner ~1,400 ores/h, 3 ~2,750,
  5 ~3,700 in the simulator. Tried and reverted: alternating tunnel heights.
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
  START needs THIS run of the base to see the owner offline for `after` (AWAY.offSince, memory
  only) - the saved lastSeen made a base that was off 10 h start away mode one tick before it
  saw the owner -> "Away 1 s". A report shorter than `after` is not sent. The "base was OFF"
  message (within 10 min of a base start) also goes to chat; an offline tick does not cancel
  it. Unknown owner state (no detector / old data) -> nothing changes. Online = the
  owner is in getOnlinePlayers (state.online from refreshPlayers(full)) - NOT just
  an entry in state.players (the owner is always added there, even offline: that
  kept away mode from ever starting). Base OFF longer than `after` right before
  the owner is seen again -> one box saying the base was off (chunk unloaded).
  NOTE cfg helpers (MINE.cfg / AWAY.cfg): `type(t)=="table" and t[k]` gives
  false, not nil - use an if (fixed; the mining cfg was never sent before).
- TURTLE FACTORY (base_factory.lua FACTORY, comms tick FACTORY.tick every 10 s,
  factory.dat): keeps the fleet (turtles not MISSING) at CONFIG.factory.target
  (SETTINGS > FACTORY, 0 = off). Steps (j.step): parts (ME getItem count /
  isItemCraftable; no stock + no pattern -> FACTORY.lastMissing, warning once
  an hour; this program cannot read recipes - AE2 patterns do) -> crafting
  (craftME, wait <= 30 min) -> export (EXACT counts into FACTORY.chest, a chest
  on the cable next to the builder; j.exported; on any failure exactly those go
  back with importItem) -> building (TT.send builder "build"; result via
  TT.receive -> FACTORY.result, "built turtle <id>"); then FACTORY.leaving: no next build
  until the new turtle is >= 2 blocks from the builder's home (home offer at once, then
  "home" every 60 s; 20 min -> warning). SPEED: FACTORY.tick every 3 s while a job or
  leaving runs (else 10 s); all parts in stock -> parts -> export -> "build" in ONE check;
  after a build waitUntil 5 s (was 2 min); FACTORY.last.msg "... in N s", sysLog "left the
  build spot after N s" (one turtle per ~10 min before). Builder = FACTORY.builder
  or the rescuer; needs Disk Drive + install floppy + pickaxe. node.lua build():
  turns until the chest holding a turtle item is in front, sucks it empty (only
  the delta vs invSnapshot goes on), places the turtle on the OPPOSITE side,
  drops the parts into it, puts its drive + floppy ABOVE the new turtle, turns
  it on (it installs node.lua, equips modem/Chunky itself, refuels), takes the
  drive back. Before the turtle is placed every failure gives the parts back to
  the chest. Parts: CONFIG.factory.turtle/modem/geo/chunky/pick/fuel(+fuelCount
  16). Never your own items: before export the ME item is looked at -
  enchanted / renamed / damaged / a used computer-turtle (nbt or components with a
  FILLED value - 1.21 lists defaults like damage 0) -> never taken. FACTORY.variants(name):
  EVERY version in AE2 (bridge.getItems{name}, else getItem) -> plain count, own count, a
  plain fingerprint (before: the FIRST version AE2 gave was "the" item - the owner's one
  used pickaxe stopped the factory). Parts count only plain ones (own only -> missing / AE2
  crafts a fresh one); exported by the plain fingerprint. `factory` prints the parts FIRST
  and status / "Last try" LAST (the reason had scrolled off the screen). The builder must be AT HOME (else sent home first); a builder whose
  inventory is too full gives everything back (parts left in the chest). 3 failures in a row -> stops until `factory build`. FACTORY TURTLES STAY HOME: TT.factoryRole(t)
  (the builder - hand-picked or the rescuer - and the crafter) -> no survey batches (TT.available,
  nextBatch), no search party, idleWhy "factory builder - stays at the factory". SETTINGS > FACTORY: fleet size,
  factory chest (tap = next EMPTY chest OR BARREL <= 54 slots on the cable, never FACTORY.reserved = the
  AE2 buffer / give / take / curios / fluid buffer), builder (tap = next
  turtle / automatic = the rescuer), status (tap = try again). Console `factory
  [chest <name>|builder <id>|build|stop|fuel <item> [count]|fuel reset]`; FLEET card line
  "Factory". `factory fuel` = setSetting factory.fuel / fuelCount (settings.dat).
- ENERGY CELLS (Advanced Peripherals automata core chargeTurtle: FE in a charged item ->
  fuel): node.lua chargeFromCell(target) at the start of topUp (any side with chargeTurtle;
  no core / empty cell = nothing; tells the base once, S.cellUsed); miner.lua (m18) tries
  it first in burnCoal. A miner keeps a cell only if it was in it at START (S.own).
  node_cell.lua. NEVER use the core's digBlock / useOnBlock: tested in game (End Automata
  on the right, deepslate emerald ore in front, pickaxe selected) - the turtle MINES ITSELF
  (it drops as an item); lookAtBlock().name = "computercraft:turtle_advanced" (f = 0.0045):
  Advanced Peripherals issue #840, fixed in 0.8.2a - the owner's server is older and the
  owner cannot update it. run_tests fails if any game file calls digBlock / useOnBlock.
  Only after the server has 0.8.2a+ (lookAtBlock names the block in front): silk touch via
  the core, and only after checking lookAtBlock().name == turtle.inspect() name each time.
  The core's peripheral type is "end_automata" (+ "automata"), not
  "endAutomata" as the docs say - find it by "automata" in the type. The server does not
  allow enchanted tools as turtle upgrades (no silk touch / fortune for turtles).
- TAUGHT RECIPES (modpacks change recipes: none written in the code). CRAFTER turtle =
  a crafting table equipped (node gear "crafter"; FACTORY.crafter or automatic = the one
  with "crafter"), home next to the factory chest. SETTINGS > FACTORY "Teach a recipe" /
  `factory learn` -> node learnRecipe: only the 3x3 grid (GRID 1-3,5-7,9-11) may hold
  items, craft(1) into slot 16, sends "recipe" {out, count, grid[9]} -> FACTORY.learned
  (recipes.dat). Factory "parts": parts neither in stock nor AE2-craftable -> FACTORY.plan
  (stock shared via avail, AE2-craftable ingredients ordered, other taught recipes first,
  depth 6, <= 64 crafts per call; plan.missing named) -> "tcwait" (ingredients in stock,
  crafter idle + at home; EXACT export to the empty chest, j.exported) -> crafter "craft"
  {grid, times} -> node craftRecipe (must be EMPTY, finds the chest by turning, sucks,
  lays out exactly, extras back, craft, ALL back into the chest; any failure -> all back)
  -> "tcraft" -> FACTORY.craftResult imports the chest into AE2 -> next craft / "parts"
  (j.rounds > 30 = wrong recipe -> fail). `factory recipes|forget <item>|crafter <id>`.
  The preview stub counts the SLIM program sizes (dist/) as the computer's used space.
  test_factory.lua (taught), node_craft.lua.
- SCHEMATICS (base_schem.lua SCHEM, stage 1 of the builder turtles): Create's
  Schematic and Quill `.nbt` (= vanilla structure format, also Minecraft's own
  structure pieces) dragged onto the base computer's screen -> uiLoop
  "file_transfer" -> SCHEM.onTransfer (only .nbt, must parse) -> SCHEM.store
  (data floppy schematics/ first, else computer schematics/ leaving 96 KB; binary
  "wb"). Own gzip/zlib inflate (stored/fixed/dynamic, arithmetic only) + NBT
  reader + structure parser: { size, palette {name, props}, blocks {x,y,z,p} };
  AIR = must be air, a position missing from the file = leave as is.
  SCHEM.materials -> items (wall torch -> torch, door/bed: one half, double
  slab = 2, air/fluids/fire skipped). Console `schem [<name>|delete <name>]`. A drop only takes the bytes (SCHEM.pending,
  event schem_in); the mapWorker reads + stores them with TT.workYield pauses.
  Plan: stage 2 builder turtles (several, strips; scan + diff: break what does
  not belong -> back into AE2, place what is missing; daily rotation per site at
  an hour), stage 3 structure "spawning" at flat spots from the map. Litematica /
  WorldEdit files are refused with a hint. tools/tests/fixtures (make_fixtures.py).
- CURIOS (base_curios.lua CURIOS; CURIOS tab, empty slot selected): FITS = items tagged
  curios:<slot> (or curios:curio) + items listed under "#curios:<slot>" in the partial view
  (meTagCache.curioOf - those answers often carry NO tags, so nothing was ever found) +
  items LEARNED to fit (worn before / put on from here: CURIOS.fits, curios_fits.dat).
  SHOW ALL lists every AE2 item (Curios refuses what does not fit). AUTO-EQUIP: AUTO next
  to an item / KEEP ONE ON on a worn one -> rule {slot, item} (curios_auto.dat);
  CURIOS.autoTick (comms worker, slots read every 2 s while rules exist - was 8 s, too slow for a used totem) queues a cequip FIRST in the action queue
  (auto=true) when the item is not worn in that slot type and a slot is free (a used
  totem); r.why = "none left in AE2" / the put-on error (shown on the tab, `curios auto`).
  Putting on needs CONFIG.me.curiosChest. test_curios.lua.
- POCKET REMOTE (pocket.lua on the owner's Advanced Pocket Computer with a
  wireless / ender modem; base_pocket.lua POCKET; rednet protocol "basepocket",
  rednet.host'ed by the comms worker; POCKET.out sent there). Pairing: pocket
  "pairreq" -> monitor box with a 6-digit code (2 min) -> pocket "pair" with
  proof = sign(code, "pair", id) -> base makes a per-pocket key (pockets.dat),
  sends it scrambled with the code (POCKET.scramble: + a hash stream mod 256).
  Then every pocket message is signed with that key + numbered (lastN: no
  replays); base answers are signed too. "req" -> POCKET.status (turtles,
  needs, mining, factory, survey, area, drones, places); "act" -> POCKET.act:
  ride base / place / back, ridestop, turtle stop|home|locate|ping, allstop,
  allhome, mine start|pause|unload, corner 1|2 (pocket GPS, else the Player
  Detector), wholeworld, surveyhere, factoryretry. pushNote WARNING / ERROR /
  DONE -> "note" to every paired pocket. Pocket tabs HOME RIDE BOTS MINE MSG +,
  tap only, risky buttons two taps. Pages SCROLL (^ v on row 2; put/button/text
  take page rows, at() = screen rows; row H = message bar); text WRAPS, never cut;
  BOTS lists problems first (RANK), natural name order; HOME sections tap to their tab. Console `pocket [unpair <id>]`.
  Also: forget (offline turtle only) and minedrop (MINE.drop) from the pocket
  (two taps); status lists gone miners (20+ min). Messages older than 60 s are
  refused (m.n is the server clock * 100) - replays also after a base restart.
  corner / surveyhere refused when the Player Detector says the owner is not in
  the overworld (the pocket's GPS there is not an overworld place). WELCOME BACK
  goes to the pocket too. tools/tests/test_pocket.lua runs the real pocket.lua
  against the base (DUMP=1 prints the screens).
- SEARCH PARTY (TT.party, base_turtles.lua; FLEET card SEARCH PARTY / CALL BACK PARTY,
  console `party [stop]`): members = online, fuel > 2000, not anchor / rescuer / held
  (t.party: no survey batches - TT.available -, no idle-home, idleWhy says so); jobs
  stopped (no hold). Targets = TT.lostList (offline, not MISSING, pos known), nearest-next
  order. Stages: meet (base, a line) -> travel (hops <= 128 toward the target, members side
  by side 24 apart across the way; next hop when all are within 6 of their goal or idle 20 s,
  max 300 s) -> ring1 (24 around the spot) -> ring2 (56) -> TT.markMissing. After EVERY stop
  each member runs node job "findturtles" (Geo Scanner r 16/8, turtle blocks, not eggs) ->
  "turtlesseen" -> TT.partySeen: a block with no online turtle on it, within 96 of a lost
  one's last spot = that turtle -> TT.rescue(id, exact x y z, 6, the permanent rescuer)
  (the rescuer checks the ID - isTurtle - before touching it). A lost one that reports
  (Chunky loaded its area) = found. End / no members -> all "home", summary note.
  Memory only (a base restart ends it). test_party.lua.
- Permanent rescuer: t.rescuerRole (RESCUER button, saved in turtles.dat;
  base only). TT.patrolTick (comms worker) sends it to: no fuel (<20 for
  60 s), stuck (60 s idle), lost (silent CONFIG.turtles.rescueAfter, default
  180 s; no reinstall gear needed - arriving loads the area and wakes it). Never in the first 5 min after the base starts; when half or
  more are offline (a server crash) only after CONFIG.turtles.rescueAfterCrash
  (600 s) of silence; lost turtles: the biggest group first (lost ones within 48
  blocks), none sent to a turtle within 48 blocks of one already being rescued; called off when the turtle
  is fine again; max 3 tries, 30 min apart (tries reset once the turtle is fine again). Rescuer goes home after each
  rescue, gets no big-survey batches. MISSING: a rescue that ends "not found
  within" while the turtle is offline -> TT.markMissing (t.missing, saved; popup
  + sysLog with last spot and gear; no more rescues; batch reclaimed; not counted
  for massOffline); any report clears it. FORGET (two taps, replaces PING while
  offline) / `turtle <id> forget` -> TT.forget. feedSurvey reclaims the batch of
  a turtle silent > CONFIG.map.reclaimOffline (600 s).
- Themes (base_theme.lua): THEMES = 6 Minecraft biomes (see UI rules), same JOB per colour slot.
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
  computer. `store [find|update]` on the base computer. Helpers left OFF by a server
  restart: STORE.wakeAll turns them on over the cable (computer peripheral isOn /
  turnOn; only known ids or label "Store <id>") - at mapWorker start (then 4 s
  before the map is read), every 5 min, and in `store`. Helpers ON but not
  answering (store.lua not running) -> STORE.kickSilent reboots them over the cable
  (known ids only, once per 10 min; one wakeAll just turned on counts as kicked -
  STORE.kicked - so a slow boot is not restarted). store.lua on start: moves a plain `startup`
  file away (CraftOS runs it INSTEAD of startup.lua), allow_startup on,
  allow_disk_startup off. Updates: a store.lua next to
  inventory.lua (STORE.code, must compile) goes to every helper whose version
  (hello -> ver = checksum of its startup.lua) differs (op "upd": checksum +
  compile check, then startup.lua + reboot) - STORE.updateAll in the mapWorker.
- UPGRADE (upgrade.lua; console `upgrade [check|branch <b>]`, SYSTEM > ACTIONS
  UPGRADE PROGRAM, or `upgrade` in a shell - also on the pocket): the newest files from
  GitHub (public repo, raw.githubusercontent.com; the exact commit from api.github.com so
  files never mix). manifest.txt = "group path size checksum" (groups base / pocket;
  base_config.lua NEVER in it) - REGENERATE IT after every change: `python3
  tools/make_manifest.py` (run_tests fails when it is stale). Only changed files; every
  download must match size + checksum (upgradeHash = make_manifest h) and compile, else
  nothing is written; temp file when there is room, else old out / new in (old kept in
  memory); binary "rb"/"wb". Then map saved + reboot. Default branch
  claude/computercraft-base-review-ihjtqw (upgrade.dat). tools/tests/upgrade_sim.lua.
  SLIM (default): make_manifest also writes dist/<file> = tools/slim.py (comments, --[[ ]]
  blocks, indentation, trailing spaces removed; strings / [[ ]] untouched; EVERY LINE KEPT
  so game error line numbers match the full file) and lists them as "slim:<group> path size
  sum dist/path"; upgrade takes those (`upgrade full` = commented files, saved; `upgrade
  slim` back; an older upgrade.lua only reads the plain groups -> full files + the new
  upgrade.lua, the next run goes slim). Base files 904 KB -> 656 KB. run_tests: every dist
  file compiles (luac -s) to the SAME bytes as the full one, same line count.
- Autostart: `startup.lua` (top level of the computer) finds inventory.lua
  in any folder and restarts it after a crash (inventory.lua raises an error
  on a crash, returns normally on Ctrl+T). inventory.lua turns off
  `shell.allow_disk_startup` (the install floppy's startup.lua would run
  instead); the installer also starts the base program if run on a computer.
- `tools/preview/` draws the monitor outside the game (Lua 5.3 + Pillow); use
  it to check screen changes. It is not game code.

## UI rules ("Block UI" - every page follows them)
1. Minecraft's look done MODERN (the owner: liked the stone-button / gold-title look,
   but not "like a 2001 game"; the flat new-1.20-menu look was NOT liked): stone-grey
   buttons, gold titles, the blue selected tab - in deeper, softer shades. THEMES are
   biomes (stone default, deepslate, oak, nether, ender, ocean; `theme` / SETTINGS); a
   theme only changes the FRAME (bg, cards, lines, buttons, text, dim, accent, titles).
   BEDROCK theme (the owner's pick, first in THEME_ORDER; `theme bedrock`): dark slate
   boxes, LIGHT grey buttons, green selected tab / main button, white titles. THEME_STYLE
   {light, accent}: C.accent = the green SLOT (the blue slot is the MAP's water - never
   recolour it); LIGHT_FG makes text() draw white / gold / grey / status text DARK on a
   light button or the green tab (test_theme.lua). Check new pages in bedrock too.
   Status + map colours are Minecraft's chat colours, softened, FIXED (base_theme.lua
   FIXED): green good, yellow attention, red problem, cyan info, orange, pink, purple.
   Never hard-code a frame colour - use C.* (C.label = gold titles, C.accent = blue
   selected / main button, C.empty = button face, C.head = lines / dark slot).
2. No thick 3D frames: round() = two THIN lines (2x3 pixel chars, 1/3 row): panels a
   soft light line on top (C.head), every box / button a soft SHADOW under it (C.bg).
   Slots: inset() = a shadow line on top (sunken). Only 3+ rows tall. CONFIG.style
   "plain" = no lines. Two-tap actions: actButton.
3. Navigation: GROUPS (base_ui_core.lua) = HOME | YOU (inventory, backpacks, curios) |
   AE2 | PLAYERS (players, chat & rides) | DRONES | TURTLES (turtles, drive, map, mining)
   | SYSTEM (status, messages, settings). Row 5 = the group's pages + what the open
   page is for (PAGE_INFO name + one line). New page -> PAGE_INFO entry + a group +
   pageTabs + draw() dispatch + PAGES in run_tests/test_ticks.
4. HOME (base_ui_home.lua, the start page): status line, every page as a big button
   (gold name, white "what it is for", live badge) grouped like the tabs, QUICK ACTIONS
   (two taps: stop all / all home / update turtles / drone to base / save map; act
   kind "quick" -> POCKET.act). Nobody has to hunt for a tab.
5. UX (test_ux.lua): every button / tab at least 2 ROWS tall (drawButton h=2 = label row +
   a 2/3 row + shadow; tabButton = thin top edge + label; 1-row list rows only with a gap
   row). snapTouch (base_input.lua): a tap 1 row / 1 column off a button counts for the
   nearest one. Text never cut mid-sentence: shorten it or wrap() it. PAGE_INFO
   descriptions <= 30 characters (HOME buttons). No boxes that only repeat something
   (INVENTORY: OVERVIEW / EQUIPMENT boxes gone - armour + offhand are a row in the
   INVENTORY box, slots ~square: ch = 0.62 * cw; DETAILS gets the room).
6. Check every screen change with tools/preview (render.py draws the 2x3 pixel
   characters, so edges show) in the stone theme.

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
| base_ui_*.lua | one file per page (base_ui_home.lua = HOME menu, base_ui_drive.lua = DRIVE) (base_ui_system.lua = STATUS, base_ui_settings.lua = SETTINGS) + base_ui_core.lua (header groups, cards, buttons, bars, footer) |
| node.lua | the turtle program |
| miner.lua | mining-dimension team program (MINER + LOADER roles; installed by hand, not OTA) |
| base_mining.lua / base_ui_mining.lua | mining teams on the base (MINE) / MINING tab |
| base_away.lua | away mode: uses the time you are offline, WHILE YOU WERE AWAY report |
| base_factory.lua | turtle factory: keeps the fleet size, AE2 parts, the builder turtle builds new ones |
| base_schem.lua | schematics: Create .nbt files dropped on the screen, unpacked + read, materials list |
| base_pocket.lua / pocket.lua | the pocket remote: base side (pairing, status, actions, messages) / the program on the pocket computer |

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
fails; flying costs no air. Passenger watch: dr.rider (set after pickup) is checked BEFORE EVERY MOVE
(riderGoneNow in droneMoveTo) and every 2 s while moving (riderLeft): logged off (not in
getOnlinePlayers, empty list = nobody) or > 12 blocks apart twice 0.5 s apart -> "passenger got
off" -> the drone goes straight home (before: 2-3 more 160-block hops into unloaded land). Long trips hop 160 -> 80 -> 48 blocks
before flying into an area that is not loaded. A refused (blocked/tight)
target with OPEN SKY above it (MAP.get column top <= y-1; skyOpenAbove) ->
one teleport into the air above + fly down (skyApproach) instead of trying
the nearby spots; under a roof / unknown column / pickups (noFly): as before. A FAR
target refused at once is not hopped to straight away: one teleport into the
air above it (map top + 8, or hopY when unknown) tells loaded (spot was just
blocked -> carry on from there) from not loaded (-> hops). Everything refused
and the spot is UNDER GROUND (map top > y): the drone lands on the surface
right above it. A mission's own destination is dr.mdest (cmd.dest, e.g. a chat ride or
the fly-to-turtle button, else the DRONES page choice dr.dest); chat rides never change
dr.dest / dr.passenger. On board? (pickupSteps) after EVERY Entity Import the drone FLIES (goto, no air) liftHeight
(min 4: a move counts as arrived within 2.5 blocks) up; on board = the player rose with the
DRONE (from right after the grab: playerUp >= droneUp - 1, >= 1; a carried player HANGS under
the drone and the climb may stop 2.5 short - the old "2 above the pickup spot" let real
passengers out and flew home without them; polled every 0.3 s for 3 s) - being next to them proves nothing (it went there
to get them; that made it teleport off without a passenger). No room to lift -> checked
on arrival (passengerHere). The liftCheck setting is gone (base_config line unused). Wrong passenger guard (pickupSteps): no Entity Import while another
player is within 4 blocks of the rider; after the import the drone must be WITH the rider,
else letGoHere (Entity Export where it is) + fail; lift mode lets go before the next try.
Teleports only into loaded chunks (players and the
anchor turtle keep chunks loaded). Charging station + parking in base_drones.lua. After ANY failure: resetDrone
(abortAction, clear filters/area), home at once (once per failure; dr.failedAt), a
passenger still on board (dr.rider) is kept through the home mission and let out at
home (releaseRider). parkCheck (every 10 s) sends idle drones away from their spot
home - the charger spot, or homePos at Base when there is no charger - at once after
a failure, else after 20 s; retried every 60 s. A rider on board ON PURPOSE
(PICKUP done, no failure: dr.rider and not dr.failedAt) is left alone - the owner DROPs. A STOP by the
owner is not a failure (no failedAt). A failed HOME trip never lets a rider out where the
drone is (it may be in the air) - parkCheck retries; letGoHere after a lift puts a wrong
rider down at the pickup spot.

## Rules for changes
- ComputerCraft Lua (Cobalt, Lua 5.2 based): no `goto`, no `//`, no bit ops
  operators; use math.floor. Keep everything pcall-safe around peripherals.
- Never block the UI; no sleeps in drawing code.
- Never move or delete the owner's items/fluids except exact amounts the
  program itself put somewhere.
- After changing files, run `python3 tools/run_tests.py` (`--quick` ~6 s, full
  ~40 s; `-k <word>` for some): syntax, undefined globals (tools/check_globals.py; --leaks = set inside a function and nowhere
  else, a missing local; LOADK-keyed names in big files are followed),
  local limits, the base tests in tools/tests/test_*.lua (real base files on the
  tools/preview stand-in; CHECK(cond, msg) in a test, TESTMODE=1 -> exit 1 on a
  failed check), every page draws, node.lua builder / route / STOP tests, the
  mining simulator. test_ticks.lua runs EVERY background job (the ones the
  workers pcall - an error there is swallowed in the game) 40 times in a messy
  world without pcall; test_settings.lua taps every setting. New feature -> add CHECKs to a test (and make sure a broken
  version FAILS it). Then tell the owner exactly which files to copy and what to
  test in game. Keep explanations short and plain.
- When an in-game API is unclear, ask the owner to run `report` (uploads all
  peripherals + functions to pastebin) or `tanks` / `me check` / `curios check`.

## Useful console commands (on the base computer)
help, report, tanks, mesetup, me check, me add <id>, curios check, disks
[data|move], drones, drone <n>, charger, turtles, turtle <id> <cmd>, update,
rescue, findlost, map [clear], exit [clear], survey, theme, events.
