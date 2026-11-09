#!/usr/bin/env python3
"""manifest.txt: the files `upgrade` downloads, with size + checksum.
   group path size checksum   (group = base or pocket)
Run after changing program files (run_tests.py checks it is up to date):
   python3 tools/make_manifest.py
base_config.lua is NOT in it (the owner's settings are never replaced)."""
import glob, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from slim import slim
# SLIM copies (no comments / indentation, same lines) in dist/: listed as group
# "slim:<group>" with their source path - `upgrade` takes those (the in-game
# computer has 1 MB); `upgrade full` and older upgrade.lua take the full files.

def h(data):                       # same as upgradeHash in upgrade.lua
    x = 0
    for b in data:
        x = (x * 31 + b) % 4294967296
    return "%08x" % x

def files():
    base = sorted(os.path.basename(f) for f in glob.glob(os.path.join(ROOT, "base_*.lua")))
    base = [f for f in base if f != "base_config.lua"]
    out = [("base", f) for f in ["inventory.lua", "startup.lua", "node.lua", "store.lua", "upgrade.lua"] + base]
    out += [("pocket", "pocket.lua"), ("pocket", "upgrade.lua")]
    return out

def slimmed(f):
    text = open(os.path.join(ROOT, f), "rb").read().decode("latin-1")
    return slim(text).encode("latin-1")

def build():
    lines, dist = [], {}
    for g, f in files():
        data = open(os.path.join(ROOT, f), "rb").read()
        lines.append("%s %s %d %s" % (g, f, len(data), h(data)))
    for g, f in files():
        data = dist.get(f) or slimmed(f)
        dist[f] = data
        lines.append("slim:%s %s %d %s dist/%s" % (g, f, len(data), h(data), f))
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
        os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
        for f, d in dist.items():
            open(os.path.join(ROOT, "dist", f), "wb").write(d)
        open(path, "w").write(text)
        print("manifest.txt + dist/ written (%d lines)" % len(text.splitlines()))
