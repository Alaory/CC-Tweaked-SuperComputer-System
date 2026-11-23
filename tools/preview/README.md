# Screen preview (not game code)

Draws the monitor with the real `base_*.lua` files outside Minecraft, using a
small stand-in for ComputerCraft (`cc_stub.lua`) and fake blocks with sample
data (`world.lua`). Do **not** copy this folder into the game.

Needs Lua 5.3 and Python 3 with Pillow.

```bash
cd tools/preview
lua5.3 run.lua ../.. out/drone.txt drone notes.lua   # page, optional scenario file
python3 render.py out/drone.txt out/drone.png
```

Pages: inventory players storage curios me drone access turtles map.
Monitor size: `MONW=121 MONH=50 lua5.3 run.lua ...` (default 164 x 81).
The font is not the in-game one, so letters look a bit wider.

**README pictures:** `showcase.lua` is an example base (made-up coordinates, an AE2 network, a fleet of turtles,
mapped land, messages, a schematic) - render a page with it:
`lua5.3 run.lua ../.. out/home.txt home showcase.lua && python3 render.py out/home.txt ../../docs/images/home.png`.
Never use your own `base_config.lua` coordinates or saved places in pictures you publish.
