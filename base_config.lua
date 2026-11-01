--[[
  INVENTORY DISPLAY
  CC:Tweaked + Advanced Peripherals (Inventory Manager)

  Setup:
    * Advanced (gold) Monitor next to the computer
    * Inventory Manager, with a Memory Card bound to your player
    * OPTIONAL: a Player Detector -> player status card and PLAYERS page
    * OPTIONAL: an Environment Detector -> helps work out the dimension
    * OPTIONAL: an ME Bridge (or RS Bridge) -> ME page: network status,
      item browser, crafting, and moving items between you and the network

  DRONE (PneumaticCraft): connect a Drone Interface. Program a drone with a
  ComputerCraft puzzle piece whose area contains the interface and launch it;
  once it reaches the piece the DRONE tab shows it as connected. From the tab
  (or the computer's keyboard: type "help") you can fly it to a player or to
  coordinates, pick a player up with Entity Import and carry them somewhere.

  CHAT BOX (optional): players can call a drone from anywhere in chat, e.g.
  "$drone home" (the $ hides the message from everyone else). Only the owner
  (the player on the memory card, checked by UUID) and players the owner
  allows may use it; anyone else's request is sent to the owner to approve.
  A player can only ever move THEMSELVES, and only to saved places.
  When you are far away the base must stay loaded (chunk loader), or the
  computer stops running.

  WIRED NETWORK (recommended): put a Wired Modem on the computer, a Wired
  Modem on each block (manager, detector, bridge, buffer chest ...) and
  connect them with Networking Cable. Right-click every modem until it
  shows a number/turns on. Nothing has to touch anything else.
    - Blocks can be anywhere on the network, even far from the computer.
      Network names are preferred over "touching" ones, so you can move a
      block away later; the script re-connects by itself.
    - If a device is missing, the screen shows what each modem can see and
      what to check (wireless vs wired modem, right-click, cables).
    - If you have SEVERAL of one kind (e.g. two Inventory Managers), choose
      one by its network name in CONFIG.names. List the names with the
      command   peripherals   on the computer.
    - ME transfers need a BUFFER CHEST on the network: set CONFIG.me.buffer
      to its network name (e.g. "minecraft:chest_0"). Both the bridge and
      the manager use that name, so the chest does not have to touch them.
      Use a dedicated, EMPTY chest: it is only a hand-over point, and items
      of the same kind left in it get moved back to the network/you.

  WITHOUT a wired network the blocks must touch the computer, and the buffer
  chest must touch both the bridge and the manager (see CONFIG.me
  bufferFromBridge / bufferFromManager).

  Speed: all game calls (the slow part) run in background workers and are
  cached, so the screen always responds instantly. Pages show their last
  data right away and refresh quietly. Tune the refresh times in CONFIG.ttl.

  Touch controls:
    * Touch any item (grid or list) to highlight every slot holding it
    * Touch the SORT button to cycle: count / name / slot
    * Touch the tabs in the header to switch pages:
        INVENTORY / PLAYERS / STORAGE (backpack contents) / CURIOS
    * On the PLAYERS page touch a card to see that player's raw data
]]

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
CONFIG = {
  refresh   = 1,      -- seconds between updates
  textScale = 0.5,    -- 0.5 gives the most detail on a big monitor
  title     = "INVENTORY",
  -- look of the screen: "flat" = clean solid blocks (like the original
  -- design), "rounded" = rounded corners and thin bars made of pixel characters
  style = "flat",
  -- nil = auto-detect (list() is 1-based, getItems() is 0-based).
  -- Only set this (0 or 1) if your hotbar shows up in the wrong place.
  slotBase  = nil,
  -- Used for the dimension when the detector doesn't report one but the
  -- player is in range of it (i.e. in the same dimension as the detector).
  homeDimension = "minecraft:overworld",
  detectRange   = 100000,

  -- seconds a page's data counts as fresh before it is re-read in the background
  ttl = { players = 2, storage = 5, curios = 5 },

  -- Pin a peripheral by its network name when there is more than one of a kind
  -- (nil = use the first one found).  Example: inventoryManager = "inventory_manager_1"
  names = {
    inventoryManager    = nil,
    monitor             = nil,
    playerDetector      = nil,
    meBridge            = nil,
    environmentDetector = nil,
  },

  drone = {
    home         = { x = -5292, y = 68, z = 10839 },  -- "Base": where riders are dropped off
    -- Charging Station (needs a Dispenser Upgrade). After every mission the drone
    -- parks in the block ABOVE it and recharges there. If you move the station,
    -- type   charger <x> <y> <z>   on the computer (saved, no need to edit this).
    charger      = { x = -5293, y = 14, z = 10846 },
    chargerFile  = "drone_charger.dat",
    -- optional nicknames, by the interface's network name, e.g.
    --   names = { ["drone_interface_0"] = "Taxi", ["drone_interface_1"] = "Cargo" },
    names        = {},
    returnHome   = true,  -- fly back to base after every mission
    minPressure  = 2,     -- (bar) missions do not start below this pressure
    waypointFile = "waypoints.dat",   -- saved places (kept between restarts)
    logFile      = "drone_logs.dat",  -- drone logs (kept between restarts)
    logMax       = 100,               -- entries kept per drone (oldest are dropped)
    stepTimeout  = 180,   -- seconds one drone step (fly / pick up / drop) may take
    -- Every teleport costs air: 10,000 mL = about 0.85 bar for a drone without
    -- Volume Upgrades (also when the teleport fails). Flying costs no air.
    teleportCost = 0.85,  -- bar per teleport (first guess; measured while flying)
    airReserve   = 1.5,   -- never teleport below this much air left - fly instead
    rideMinTeleport = 4,  -- teleport mode: a ride needs at least this many bar
    hopLength    = 160,   -- far + not loaded: teleport in hops this long (the passenger
    hopY         = 200,   --   loads each next area); at this height above the terrain
    travelTimeout = 8,    -- seconds one teleport attempt may take (warm-up is 6 s; after a
                          -- failed teleport the drone starts FLYING - so keep this short)
    -- Entity Import flies to the player by itself. Only if a try fails is the
    -- drone first sent to the player's exact Y, this many blocks beside them
    -- (0, 0 = the player's own block, which may push them away).
    approachDX   = 1,
    approachDZ   = 0,
    -- "teleport": the drone teleports to every target (no pathfinding - best for
    -- underground bases). "fly": it flies when it finds a path, like before.
    travel       = "teleport",
    liftHeight   = 4,     -- blocks the drone lifts a picked-up player (shows they are on board)
    -- Teleport mode: false = no lift after the pickup; the drone checks at the
    -- destination that the passenger came along (saves a 6 s teleport).
    -- true = lift-and-check right after the pickup (always used when flying).
    liftCheck    = false,
    pickupTries  = 4,     -- attempts before giving up
    maxPressure  = 25,    -- full scale of the pressure bar
  },

  -- TURTLES: remote-controlled turtles (run node.lua on them). Needs a Wireless
  -- or (better) an Ender Modem on a side of this computer. protocol, hostname
  -- and key MUST be the same in node.lua on every turtle.
  turtles = {
    protocol     = "basectl",
    hostname     = "base",
    key          = "change-me",   -- shared secret: change it (here AND in node.lua)
    offlineAfter = 45,            -- seconds without a report = offline (scans swap the modem out briefly)
    -- what the turtles learnt (walls they bumped into, dead ends, the exit
    -- route) is kept here and shared with every turtle before a trip
    knowFile     = "terrain.dat",
    exitFile     = "exit_route.dat",
    knowMax      = 4000,          -- remembered walls at most (oldest dropped), ~35 bytes each
    -- updates: the base sends node.lua (next to inventory.lua) to every turtle
    -- that runs an older version, when it is idle
    codeFile     = "node.lua",
    listFile     = "turtles.dat",  -- every turtle ever seen, with its last position
    autoUpdate   = true,
  },

  -- MAP: built from turtle scans (node.lua with a Geo Scanner in its inventory)
  map = {
    file       = "map.dat",
    maxChunks  = 200,   -- mapped chunks kept on disk (oldest dropped), ~1 KB each
                        -- (a computer has 1 MB; files can also go on a floppy:
                        --  file = "disk/map.dat" - a floppy holds 125 KB, ~110 chunks)
    scanRadius = 8,     -- 8 = the free scan (17x17x17 blocks)
    skipKnown  = 0.8,   -- survey: skip spots that are already this much mapped (0..1)
    -- which direction is UP on the map: "north", "east", "south" or "west".
    -- Tip: use the direction you LOOK when you stand in front of the monitor
    -- (monitor facing east -> you look west -> "west"). ROTATE changes it live.
    up         = "west",
  },

  -- items known to break Advanced Peripherals' readings on a server (their
  -- tooltip uses client-only code). Named in the messages on the CURIOS tab.
  knownBroken = {
    ["hazennstuff:pendant_of_harmony"] = "Pendant of Harmony (Hazen N Stuff)",
  },

  -- "$drone back": where a player was before a big jump (teleport, /home)
  -- or where they died - the drone takes them back. Overworld only.
  back = {
    jump      = 500,    -- a jump of more than this (blocks) = remember the spot before it
    deathJump = 32,     -- badly hurt, then healed and this far away = died there
    lowHealth = 0.35,   -- "badly hurt" = at most this part of full health
    keepHours = 24,     -- how long such a spot can be used
    every     = 3,      -- seconds between position checks
    file      = "back_spots.dat",
  },

  chat = {
    command     = "drone",   -- chat commands start with this word: "$drone home"
    replyPrefix = "Drone",   -- shown as [Drone] in the private replies
    askOwner    = true,      -- requests from unknown players go to the owner to approve
    approveTime = 60,        -- seconds an approval request stays open
    cooldown    = 120,       -- seconds between rides for players other than the owner
    maxDistance = nil,       -- e.g. 5000: refuse pickups further than this from base
    notifyOwner = true,      -- tell the owner whenever someone else gets a ride
    othersToPlayers = true,  -- may other players fly TO players? (owner always can;
                             -- players not on the list still need the owner's OK)
    tellTarget  = true,      -- tell a player when someone is flown to them
    accessFile  = "chat_access.dat",  -- the allow list (kept between restarts)
  },

  me = {
    -- TAKING ITEMS needs a BUFFER CHEST: the ME Bridge puts items in it, the
    -- Inventory Manager moves them from it to the player (the owner of the
    -- Memory Card in the manager). The chest MUST TOUCH THE INVENTORY MANAGER.
    -- Directions: "up" "down" "north" "south" "east" "west" (or "left" etc.)
    -- TWO CHESTS (optional): one the manager GIVES items to the player from,
    -- one it PUTS the player's items into. If not set, the single chest above.
    giveFromManager = nil,        -- the give chest, seen from the Inventory Manager (e.g. "down")
    takeFromManager = nil,        -- the take chest, seen from the Inventory Manager (e.g. "east")
    -- How the ME Bridge reaches each chest: its network name ("minecraft:chest_3")
    -- or a direction from the bridge. nil = found automatically (put any item
    -- into each chest once - the base then recognizes them by their contents).
    -- FLUIDS: the fluid storage the ME tab moves fluids to and from (network
    -- name, e.g. "functionalstorage:storage_controller_0"). nil = found
    -- automatically when there is only one fluid storage on the network.
    fluidBuffer = nil,
    giveChest = nil,
    takeChest = nil,
    bufferFromManager = "east",   -- where the chest is, seen from the Inventory Manager
    -- The ME Bridge reaches the chest either by touching it ...
    bufferFromBridge  = "up",     -- where the chest is, seen from the ME Bridge
    -- ... or, if it does not touch it, by the chest's network name (put a wired
    -- modem on the chest, right-click it, use the name it shows, e.g. "minecraft:chest_0")
    buffer = nil,
    chunk   = 576,   -- max items per transfer step (about 9 stacks)
    refresh = 3,     -- seconds between ME network reads
  },
}

