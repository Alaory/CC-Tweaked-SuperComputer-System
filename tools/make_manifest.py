#!/usr/bin/env python3
"""manifest.txt: the files `upgrade` downloads, with size + checksum.
   group path size checksum   (group = base or pocket)
Run after changing program files (run_tests.py checks it is up to date):
   python3 tools/make_manifest.py
base_config.lua is NOT in it (the owner's settings are never replaced)."""
import glob, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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

def build():
    lines = []
    for g, f in files():
        data = open(os.path.join(ROOT, f), "rb").read()
        lines.append("%s %s %d %s" % (g, f, len(data), h(data)))
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    text = build()
    path = os.path.join(ROOT, "manifest.txt")
    if "--check" in sys.argv:
        cur = open(path).read() if os.path.exists(path) else ""
        if cur != text:
            print("manifest.txt is out of date: run  python3 tools/make_manifest.py")
            sys.exit(1)
        print("manifest.txt up to date (%d files)" % (len(text.splitlines())))
    else:
        open(path, "w").write(text)
        print("manifest.txt written (%d files)" % len(text.splitlines()))
