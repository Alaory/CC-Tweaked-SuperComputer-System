#!/usr/bin/env python3
"""Build the files for a GitHub release into release/ (not game code, not committed).

    python3 tools/make_release.py            build release/ for the version in base_state.lua
    python3 tools/make_release.py --check    only check that a release could be built

Checks first (and stops on any problem):
  - BASE_VERSION in base_state.lua is x.y.z and is the newest entry in CHANGELOG.md
  - manifest.txt and dist/ are up to date (tools/make_manifest.py --check)
  - every Lua file that goes into a zip compiles (luac5.3 -p, when luac5.3 is there)

Then writes, for servers WITHOUT internet in the game (drag the files onto the computer):
  base-control-<v>.zip    the base computer: inventory.lua, startup.lua, upgrade.lua, store.lua,
                          every base_*.lua, base_config.lua
  turtle-program-<v>.zip  node.lua - onto a floppy in one of the base's drives (the base finds it there;
                          on the 1 MB computer next to everything else it would hardly fit)
  pocket-<v>.zip          the pocket remote: pocket.lua + upgrade.lua
  miner-<v>.zip           the mining-dimension team program: miner.lua
  voice-addon-<v>.zip     the optional voice add-on: every voice_*.lua (put them on a DATA floppy)
  spawn-speaker-<v>.zip   the spawn relay computer: spawn_speaker.lua (save it as startup.lua there)
  RELEASE_NOTES.md        this version's CHANGELOG.md entry + how to install (paste into the release)
  SHA256SUMS.txt
The game files are the slim copies from dist/ (comments removed, every line kept), the same
ones `upgrade` downloads. With internet in the game nobody needs the zips: `upgrade` does it.
"""
import hashlib, os, re, shutil, subprocess, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "release")


def fail(msg):
    print("NOT READY: " + msg)
    sys.exit(1)


def version():
    src = open(os.path.join(ROOT, "base_state.lua")).read()
    m = re.search(r'^BASE_VERSION\s*=\s*"([^"]+)"', src, re.M)
    if not m:
        fail("no BASE_VERSION in base_state.lua")
    v = m.group(1)
    if not re.fullmatch(r"\d+\.\d+\.\d+", v):
        fail("BASE_VERSION %r is not x.y.z" % v)
    return v


def changelog_entry(v):
    path = os.path.join(ROOT, "CHANGELOG.md")
    if not os.path.exists(path):
        fail("no CHANGELOG.md")
    text = open(path).read()
    heads = list(re.finditer(r"^## \[?v?(\d+\.\d+\.\d+)\]?.*$", text, re.M))
    if not heads:
        fail("CHANGELOG.md has no '## x.y.z' entry")
    if heads[0].group(1) != v:
        fail("the newest CHANGELOG.md entry is %s, BASE_VERSION is %s" % (heads[0].group(1), v))
    end = heads[1].start() if len(heads) > 1 else len(text)
    return text[heads[0].start():end].strip()


def manifest_groups():
    groups = {}
    for line in open(os.path.join(ROOT, "manifest.txt")):
        p = line.split()
        if len(p) >= 2 and not p[0].startswith("slim:"):
            groups.setdefault(p[0], []).append(p[1])
    return groups


def game_file(name):
    """the slim copy when there is one (what upgrade downloads), else the file itself"""
    slim = os.path.join(ROOT, "dist", name)
    return slim if os.path.exists(slim) else os.path.join(ROOT, name)


def main():
    v = version()
    entry = changelog_entry(v)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "make_manifest.py"), "--check"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fail("manifest.txt / dist/ are stale - run python3 tools/make_manifest.py\n" + r.stdout + r.stderr)
    g = manifest_groups()
    for need in ("base", "node", "pocket", "miner", "voice", "spawn"):
        if need not in g:
            fail("manifest.txt has no group %r" % need)
    parts = [
        ("base-control", g["base"] + ["base_config.lua"]),
        ("turtle-program", g["node"]),
        ("pocket", g["pocket"]),
        ("miner", g["miner"]),
        ("voice-addon", g["voice"]),
        ("spawn-speaker", g["spawn"]),
    ]
    luac = shutil.which("luac5.3")
    for _, files in parts:
        for f in files:
            path = game_file(f)
            if not os.path.exists(path):
                fail("missing " + f)
            if luac and f.endswith(".lua"):
                c = subprocess.run([luac, "-p", path], capture_output=True, text=True)
                if c.returncode != 0:
                    fail(f + " does not compile: " + c.stderr.strip())
    if "--check" in sys.argv:
        print("ready: v%s, %d zips" % (v, len(parts)))
        return
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    made = []
    for name, files in parts:
        zname = "%s-%s.zip" % (name, v)
        with zipfile.ZipFile(os.path.join(OUT, zname), "w", zipfile.ZIP_DEFLATED) as z:
            for f in files:
                z.write(game_file(f), f)
        made.append(zname)
        size = sum(os.path.getsize(game_file(f)) for f in files)
        print("%-28s %3d files  %4d KB unpacked" % (zname, len(files), (size + 1023) // 1024))
    notes = entry + "\n\n" + INSTALL.replace("{v}", v)
    open(os.path.join(OUT, "RELEASE_NOTES.md"), "w").write(notes)
    with open(os.path.join(OUT, "SHA256SUMS.txt"), "w") as s:
        for zname in made:
            h = hashlib.sha256(open(os.path.join(OUT, zname), "rb").read()).hexdigest()
            s.write("%s  %s\n" % (h, zname))
    print("release/RELEASE_NOTES.md, release/SHA256SUMS.txt - v%s ready" % v)


INSTALL = """### Install

With http on in the game (recommended), on the base computer:

```
mkdir controller
cd controller
wget https://raw.githubusercontent.com/Alaory/CC-Tweaked-SuperComputer-System/main/upgrade.lua upgrade.lua
wget https://raw.githubusercontent.com/Alaory/CC-Tweaked-SuperComputer-System/main/base_config.lua base_config.lua
upgrade
```

Already running an older version: type `upgrade` on the base computer (your `base_config.lua`
and data files are never touched). With the voice add-on: `voice update` about 30 s after the restart.

No internet on the server: unzip `base-control-{v}.zip` and drag the files onto the base
computer's screen (into one folder; `startup.lua` goes to the top level), and put `node.lua` from
`turtle-program-{v}.zip` onto a floppy in one of the base's disk drives. The other zips are
optional: `pocket` (a pocket computer), `miner` (mining turtles, copied once), `voice-addon`
(onto a DATA floppy - `disks data`), `spawn-speaker` (the relay computer at spawn, saved there as
`startup.lua`). Set your own `turtles.key` and `drone.home` in `base_config.lua` first (see README).
"""

if __name__ == "__main__":
    main()
