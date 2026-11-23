#!/usr/bin/env python3
"""manifest.txt: the files `upgrade` downloads, with size + checksum.
   group path size checksum   (group = base, pocket or miner)
Run after changing program files (run_tests.py checks it is up to date):
   python3 tools/make_manifest.py
base_config.lua is NOT in it (the owner's settings are never replaced)."""
import glob, os, sys, zlib
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from slim import slim
# SLIM copies (no comments / indentation, same lines) in dist/: listed as group
# "slim:<group>" with their source path - `upgrade` takes those (the in-game
# computer has 1 MB); `upgrade full` and older upgrade.lua take the full files.
# PACKED copies of the base_*.lua files (dist/z/<name>.luz = raw deflate of the SLIM text, about a
# third): group "z:base" - `upgrade` takes those, inventory.lua unpacks them with unzip.lua when the
# base starts (the slim files alone were ~900 KB of the 1 MB computer).

def h(data):                       # same as upgradeHash in upgrade.lua
    x = 0
    for b in data:
        x = (x * 31 + b) % 4294967296
    return "%08x" % x

def files():
    base = sorted(os.path.basename(f) for f in glob.glob(os.path.join(ROOT, "base_*.lua")))
    base = [f for f in base if f != "base_config.lua"]
    out = [("base", f) for f in ["inventory.lua", "startup.lua", "store.lua", "upgrade.lua"] + base]
    # (the unpacker for the PACKED base files: its own group - an older upgrade.lua must not install it: at 13 KB
    #  free the step to the new upgrade.lua would not fit; the new upgrade.lua gets it when it packs)
    out += [("unzip", "unzip.lua")]
    out += [("node", "node.lua")]  # (the turtle program: NOT on the base computer - `upgrade` stores it on a storage helper / data floppy)
    out += [("pocket", "pocket.lua"), ("pocket", "upgrade.lua")]
    out += [("miner", "miner.lua")]
    out += [("voice", "voice_addon.lua"), ("voice", "voice_talk.lua"), ("voice", "voice_talk2.lua"), ("voice", "voice_talk3.lua"), ("voice", "voice_lines.lua"), ("voice", "voice_idle.lua"), ("voice", "voice_lore.lua"), ("voice", "voice_convo.lua"), ("voice", "voice_staff.lua"), ("voice", "voice_profile.lua"), ("voice", "voice_vary.lua"), ("voice", "voice_spawn.lua"), ("voice", "voice_crowd.lua"), ("voice", "voice_lonely.lua")]
    out += [("spawn", "spawn_speaker.lua")]  # (the SPAWN SPEAKER computer: copied there by hand as startup.lua - never on the base)  # (an optional add-on: `voice install` puts it on a data floppy)      # (NOT installed on the base: `mine update` fetches it for the mining turtles)
    return out

def slimmed(f):
    text = open(os.path.join(ROOT, f), "rb").read().decode("latin-1")
    return slim(text).encode("latin-1")

def packed(data):                  # raw deflate (no zlib header), the same bytes every run
    c = zlib.compressobj(9, zlib.DEFLATED, -15, 9)
    return c.compress(data) + c.flush()

def build():
    lines, dist = [], {}
    for g, f in files():
        data = open(os.path.join(ROOT, f), "rb").read()
        lines.append("%s %s %d %s" % (g, f, len(data), h(data)))
    for g, f in files():
        data = dist.get(f) or slimmed(f)
        dist[f] = data
        lines.append("slim:%s %s %d %s dist/%s" % (g, f, len(data), h(data), f))
    for g, f in files():
        if (g == "base" and f.startswith("base_")) or g == "voice":
            z = packed(dist[f])
            name = f[:-4] + ".luz"
            dist["z/" + name] = z
            lines.append("z:%s %s %d %s dist/z/%s" % (g, name, len(z), h(z), name))
    return "\n".join(lines) + "\n", dist

if __name__ == "__main__":
    text, dist = build()
    path = os.path.join(ROOT, "manifest.txt")
    if "--check" in sys.argv:
        cur = open(path).read() if os.path.exists(path) else ""
        stale = [f for f, d in dist.items()
                 if not os.path.exists(os.path.join(ROOT, "dist", f)) or open(os.path.join(ROOT, "dist", f), "rb").read() != d]
        if cur != text or stale:
            print("manifest.txt / dist/ out of date: run  python3 tools/make_manifest.py  " + " ".join(stale))
            sys.exit(1)
        print("manifest.txt + dist/ up to date (%d lines)" % (len(text.splitlines())))
    else:
        os.makedirs(os.path.join(ROOT, "dist", "z"), exist_ok=True)
        for f, d in dist.items():
            open(os.path.join(ROOT, "dist", f), "wb").write(d)
        open(path, "w").write(text)
        print("manifest.txt + dist/ written (%d lines)" % len(text.splitlines()))
