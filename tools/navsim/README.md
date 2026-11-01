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
