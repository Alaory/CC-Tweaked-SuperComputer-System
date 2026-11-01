# Turtle navigation test world (not game code)

Runs node.lua's real navigation in a small voxel world with the turtle API
(moves, turns, detect, inspect, fuel) and prints moves / game time / result.

```bash
WHO=new TX=300 lua5.3 tools/navsim/world.lua node.lua hills     # long trip over hills
WHO=new TX=40  lua5.3 tools/navsim/world.lua node.lua pocket    # U-shaped trap
WHO=new TX=40  lua5.3 tools/navsim/world.lua node.lua wall      # long high wall
MAP=unknown WHO=new lua5.3 tools/navsim/world.lua node.lua hills  # base map has no data
```
Compare against an older node.lua (e.g. `git show HEAD~1:node.lua > /tmp/old.lua`).

## STOP test (`stoptest.lua`)

Runs the whole turtle program (listener, worker, heartbeat) with real events and
sends STOP. Moves take 0.4 s like in the game.
```bash
MODE=goto lua5.3 tools/navsim/stoptest.lua node.lua hills     # normal job, STOP at 15 s
MODE=deaf lua5.3 tools/navsim/stoptest.lua node.lua hills     # a job that ignores STOP: forced stop
# unload + reload: save the files at 10 s, start again from them
MODE=goto STOPAT=0 ENDAT=10 SAVEF=/tmp/f.lua lua5.3 tools/navsim/stoptest.lua node.lua hills
MODE=reload STOPAT=2 ENDAT=30 LOADF=/tmp/f.lua lua5.3 tools/navsim/stoptest.lua node.lua hills
```
