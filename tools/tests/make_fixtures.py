#!/usr/bin/env python3
"""Writes test schematics (Create / vanilla structure format, gzip NBT) into
tools/tests/fixtures/. Run again only when the fixtures should change."""
import gzip, io, json, os, random, struct, zlib

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

# --- a tiny NBT writer
def tag_string(s):
    b = s.encode("utf-8")
    return struct.pack(">H", len(b)) + b
def payload(t, v):
    if t == "int": return struct.pack(">i", v)
    if t == "string": return tag_string(v)
    if t == "compound":
        out = b""
        for name, (tt, vv) in v.items():
            out += bytes([TAG[tt]]) + tag_string(name) + payload(tt, vv)
        return out + b"\0"
    if t == "list":
        et, items = v
        out = bytes([TAG[et] if items else 0]) + struct.pack(">i", len(items))
        for it in items: out += payload(et, it)
        return out
    raise ValueError(t)
TAG = {"int": 3, "string": 8, "list": 9, "compound": 10}
def nbt_root(compound):
    return bytes([10]) + tag_string("") + payload("compound", compound)

def structure(size, palette, blocks):
    pal = [{"Name": ("string", n), **({"Properties": ("compound", {k: ("string", v) for k, v in p.items()})} if p else {})}
           for n, p in palette]
    bl = [{"pos": ("list", ("int", list(pos))), "state": ("int", st)} for pos, st in blocks]
    return nbt_root({
        "DataVersion": ("int", 3955),
        "size": ("list", ("int", list(size))),
        "palette": ("list", ("compound", pal)),
        "blocks": ("list", ("compound", bl)),
        "entities": ("list", ("compound", [])),
    })

def gz(raw, level=9, strategy=None):
    if strategy is None:
        return gzip.compress(raw, compresslevel=level, mtime=0)
    c = zlib.compressobj(level, zlib.DEFLATED, -15, 9, strategy)
    body = c.compress(raw) + c.flush()
    head = b"\x1f\x8b\x08\x00" + b"\0\0\0\0" + b"\x00\xff"
    return head + body + struct.pack("<II", zlib.crc32(raw) & 0xffffffff, len(raw) & 0xffffffff)

# --- the house: 5 x 4 x 5
palette = [
    ("minecraft:oak_planks", {}),                                               # 0 floor
    ("minecraft:stone_bricks", {}),                                             # 1 walls
    ("minecraft:air", {}),                                                      # 2 inside
    ("minecraft:oak_door", {"facing": "south", "half": "lower", "hinge": "left", "open": "false", "powered": "false"}),  # 3
    ("minecraft:oak_door", {"facing": "south", "half": "upper", "hinge": "left", "open": "false", "powered": "false"}),  # 4
    ("minecraft:glass", {}),                                                    # 5
    ("minecraft:wall_torch", {"facing": "south"}),                              # 6
    ("minecraft:oak_slab", {"type": "bottom", "waterlogged": "false"}),         # 7 roof
    ("minecraft:oak_slab", {"type": "double", "waterlogged": "false"}),         # 8 one double slab
]
blocks = []
for x in range(5):
    for z in range(5):
        blocks.append(((x, 0, z), 0))
        edge = x in (0, 4) or z in (0, 4)
        for y in (1, 2):
            if (x, y, z) == (2, 1, 0): blocks.append(((x, y, z), 3))
            elif (x, y, z) == (2, 2, 0): blocks.append(((x, y, z), 4))
            elif (x, y, z) == (0, 2, 2): blocks.append(((x, y, z), 5))
            elif (x, y, z) == (2, 2, 3): blocks.append(((x, y, z), 6))
            elif edge: blocks.append(((x, y, z), 1))
            else: blocks.append(((x, y, z), 2))
        if (x, z) == (4, 4): continue                     # structure void: not in the file
        blocks.append(((x, 3, z), 8 if (x, z) == (0, 0) else 7))
raw = structure((5, 4, 5), palette, blocks)
open(os.path.join(HERE, "house.raw"), "wb").write(raw)
open(os.path.join(HERE, "house.nbt"), "wb").write(gz(raw, 9))                           # dynamic Huffman
open(os.path.join(HERE, "house_stored.nbt"), "wb").write(gz(raw, 0))                    # stored blocks
open(os.path.join(HERE, "house_fixed.nbt"), "wb").write(gz(raw, 9, zlib.Z_FIXED))       # fixed Huffman

# --- a bigger one with many kinds of block (inflate + NBT on more data)
random.seed(7)
kinds = ["minecraft:stone", "minecraft:dirt", "minecraft:air", "minecraft:oak_log", "minecraft:glass",
         "minecraft:cobblestone", "minecraft:oak_planks", "minecraft:bricks", "minecraft:sand", "minecraft:gravel"]
pal2 = [(k, {"axis": "y"} if "log" in k else {}) for k in kinds]
bl2, counts = [], {}
for x in range(32):
    for y in range(16):
        for z in range(32):
            st = random.randrange(len(kinds)) if random.random() < 0.7 else (x + y + z) % len(kinds)
            if random.random() < 0.05: continue           # structure void
            bl2.append(((x, y, z), st))
            counts[kinds[st]] = counts.get(kinds[st], 0) + 1
raw2 = structure((32, 16, 32), pal2, bl2)
open(os.path.join(HERE, "big.nbt"), "wb").write(gz(raw2, 6))
json.dump({"blocks": len(bl2), "counts": counts, "rawSize": len(raw2)}, open(os.path.join(HERE, "big.json"), "w"))
print("fixtures written:", len(blocks), "house blocks,", len(bl2), "big blocks,", len(raw2), "bytes raw")
