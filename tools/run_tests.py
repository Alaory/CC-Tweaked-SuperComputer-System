#!/usr/bin/env python3
"""Runs EVERY check of this project outside the game and prints one summary.

    python3 tools/run_tests.py            everything (the mining simulator: 2 h each, ~3-5 min)
    python3 tools/run_tests.py --quick    the mining simulator shorter and fewer scenarios (~1 min)
    python3 tools/run_tests.py -k drone   only checks whose name contains "drone"

Needs lua5.3 + luac5.3 (and python3). Exit code 1 when anything failed.

What runs:
  syntax     luac -p on every .lua file
  globals    names used but defined nowhere (tools/check_globals.py)
  locals     node.lua / miner.lua stay far below the game's 200-local limit
  base       tools/tests/test_*.lua - the real base_*.lua files with a stand-in
             for ComputerCraft (tools/preview); each test CHECKs its results
  pages      every monitor page draws without an error
  node       tools/tests/node_build.lua (the factory builder), the turtle route
             tests (tools/navsim/world.lua) and the STOP tests (stoptest.lua)
  mining     tools/navsim/minesim.lua - the real miner.lua team in a voxel world
"""
import os, re, subprocess, sys, glob, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW = os.path.join(ROOT, "tools", "preview")
QUICK = "--quick" in sys.argv
ONLY = sys.argv[sys.argv.index("-k") + 1] if "-k" in sys.argv else None

def run(cmd, cwd=ROOT, env=None, timeout=900):
    e = dict(os.environ)
    e.update(env or {})
    try:
        p = subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return 99, "TIMEOUT after %d s" % timeout

checks = []        # (group, name, function -> (ok, detail))
def check(group, name):
    def deco(fn):
        checks.append((group, name, fn))
        return fn
    return deco

# ---- syntax, globals, locals
lua_files = sorted(glob.glob(os.path.join(ROOT, "*.lua")) + glob.glob(os.path.join(ROOT, "tools", "**", "*.lua"), recursive=True))
@check("syntax", "luac -p (%d files)" % len(lua_files))
def _():
    bad = []
    for f in lua_files:
        rc, out = run(["luac5.3", "-p", f])
        if rc != 0: bad.append(out.strip())
    return not bad, "\n".join(bad)

for label, files in [("base", ["inventory.lua"] + sorted(os.path.basename(f) for f in glob.glob(os.path.join(ROOT, "base_*.lua")))),
                     ("miner.lua", ["miner.lua"]), ("store.lua", ["store.lua"]), ("startup.lua", ["startup.lua"]),
                     ("node.lua", ["node.lua"]), ("pocket.lua", ["pocket.lua"])]:
    @check("globals", label)
    def _(files=files):
        rc, out = run(["python3", "tools/check_globals.py"] + files)
        return rc == 0, out.strip()

@check("globals", "missing locals (base)")
def _():
    files = ["inventory.lua"] + sorted(os.path.basename(f) for f in glob.glob(os.path.join(ROOT, "base_*.lua")))
    rc, out = run(["python3", "tools/check_globals.py", "--leaks"] + files)
    return rc == 0, out.strip()
for f in ["miner.lua", "store.lua", "startup.lua", "node.lua", "pocket.lua"]:
    @check("globals", "missing locals (%s)" % f)
    def _(f=f):
        rc, out = run(["python3", "tools/check_globals.py", "--leaks", "--upper-ok", f])
        return rc == 0, out.strip()

for f in ["node.lua", "miner.lua"]:
    @check("locals", f)
    def _(f=f):
        rc, out = run(["python3", "tools/check_locals.py", f])
        m = re.search(r"= (\d+) of 200", out)
        n = int(m.group(1)) if m else 999
        return n < 160, out.strip()

@check("syntax", "no automata digBlock / useOnBlock (they mine the turtle itself)")
def _():
    # Advanced Peripherals before 0.8.2a on 1.21.1: the core aims at its OWN turtle
    # (issue #840) - tested on the owner's server: lookAtBlock() = turtle_advanced.
    bad = []
    for f in sorted(glob.glob(os.path.join(ROOT, "*.lua"))):
        for i, line in enumerate(open(f, encoding="latin-1").read().split("\n"), 1):
            code = line.split("--", 1)[0]
            if re.search(r"\b(digBlock|useOnBlock)\b", code):
                bad.append("%s:%d: %s" % (os.path.basename(f), i, line.strip()))
    return not bad, "\n".join(bad)

@check("upgrade", "manifest.txt up to date")
def _():
    rc, out = run(["python3", "tools/make_manifest.py", "--check"])
    return rc == 0, out.strip()

@check("upgrade", "slim copies (dist/) = the same code, the same lines")
def _():
    bad = []
    tmp = os.path.join(ROOT, "tools", ".slimcheck")
    for f in sorted(glob.glob(os.path.join(ROOT, "dist", "*.lua"))):
        name = os.path.basename(f)
        full = os.path.join(ROOT, name)
        if not os.path.exists(full):
            bad.append(name + ": no full file"); continue
        r1, o1 = run(["luac5.3", "-s", "-o", tmp + "1", full])
        r2, o2 = run(["luac5.3", "-s", "-o", tmp + "2", f])
        if r1 or r2:
            bad.append(name + ": " + (o1 + o2).strip()); continue
        if open(tmp + "1", "rb").read() != open(tmp + "2", "rb").read():
            bad.append(name + ": compiles to DIFFERENT code")
        if open(full, "rb").read().count(b"\n") != open(f, "rb").read().count(b"\n"):
            bad.append(name + ": line count differs")
    for x in (tmp + "1", tmp + "2"):
        if os.path.exists(x): os.remove(x)
    return not bad, "\n".join(bad)

@check("upgrade", "upgrade.lua on a fake disk + GitHub")
def _():
    rc, out = run(["lua5.3", "tools/tests/upgrade_sim.lua", ROOT])
    return rc == 0, out.strip()

# ---- base tests (CHECKs inside) and every page
for t in sorted(glob.glob(os.path.join(ROOT, "tools", "tests", "test_*.lua"))):
    name = os.path.basename(t)
    @check("base", name)
    def _(t=t):
        rc, out = run(["lua5.3", "run.lua", "../..", "/tmp/run_tests_%d_%s.txt" % (os.getpid(), os.path.basename(t)), "system", t],
                      cwd=PREVIEW, env={"TESTMODE": "1"})
        tail = "\n".join(l for l in out.splitlines() if l.startswith(("FAIL", "PASS", "lua5.3:")) or "ERROR" in l)
        return rc == 0 and "PASS" in out, tail or out[-800:]

PAGES = ["home", "inventory", "players", "storage", "curios", "me", "drone", "access", "turtles", "drive", "map", "mining",
         "system", "events", "settings", "chat"]
@check("pages", "%d monitor pages draw" % len(PAGES))
def _():
    bad = []
    for p in PAGES:
        rc, out = run(["lua5.3", "run.lua", "../..", "/tmp/run_tests_page.txt", p], cwd=PREVIEW)
        if rc != 0: bad.append(p + ": " + out.strip()[-300:])
    return not bad, "\n".join(bad)

# ---- the turtle program
@check("node", "factory builder (node_build.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_build.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "DRIVE steps (node_drive.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_drive.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "energy cells (node_cell.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_cell.lua", "node.lua", "miner.lua"])
    return rc == 0, out.strip()

@check("node", "new turtle: first fuel ~1000 then go (node_firstfuel.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_firstfuel.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "your commands pause a job, back after 2 min (node_hand.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_hand.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "search party scans feed the map (node_partymap.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_partymap.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "no digging at the base, any job (node_nodig.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_nodig.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "shrunk node.lua (sent to turtles) = same code (shrink_check.lua)")
def _():
    import tempfile
    d = tempfile.mkdtemp()
    rc, out = run(["lua5.3", "tools/tests/shrink_check.lua", d])
    if rc != 0:
        return False, out.strip()
    bad = []
    for f in ["node.lua", "pocket.lua", "base_map.lua", "base_turtles.lua", "miner.lua", "tricky"]:
        a, b = os.path.join(d, "a.out"), os.path.join(d, "b.out")
        src = os.path.join(d, "tricky_full.lua") if f == "tricky" else f
        if f == "tricky":
            f = "tricky.lua"
        r1, o1 = run(["luac", "-s", "-o", a, src])
        r2, o2 = run(["luac", "-s", "-o", b, os.path.join(d, f)])
        same = r1 == 0 and r2 == 0 and open(a, "rb").read() == open(b, "rb").read()
        lines = open(os.path.join(ROOT, src), encoding="latin-1").read().count("\n") == \
                open(os.path.join(d, f), encoding="latin-1").read().count("\n")
        if not (same and lines):
            bad.append(f + (" (different code)" if not same else " (lines moved)") + o2)
    return not bad, "; ".join(bad) or out.strip().replace("\n", "; ")

@check("node", "update on a full disk never breaks the turtle (node_update_safe.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_update_safe.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "crafter: learn + craft (node_craft.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_craft.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "duplicate copies (miner_dup.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/miner_dup.lua", "miner.lua"])
    return rc == 0, out.strip()

@check("node", "miner updates from the base (miner_update.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/miner_update.lua", "miner.lua"])
    return rc == 0, out.strip()

@check("node", "duplicate copies (node_dup.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_dup.lua", "node.lua"])
    return rc == 0, out.strip()

@check("node", "MINE UP (node_digup.lua)")
def _():
    rc, out = run(["lua5.3", "tools/tests/node_digup.lua", "node.lua"])
    return rc == 0, out.strip()

for scen in ["hills", "pocket", "wall"]:
    @check("node", "route: " + scen)
    def _(scen=scen):
        rc, out = run(["lua5.3", "tools/navsim/world.lua", "node.lua", scen], env={"WHO": "new", "TX": "40"}, timeout=300)
        return "arrived true" in out, (re.findall(r".*arrived.*", out) or [out[-400:]])[0]

for mode in ["goto", "deaf", "crash", "badcmd"]:
    @check("node", "STOP: " + mode)
    def _(mode=mode):
        rc, out = run(["lua5.3", "tools/navsim/stoptest.lua", "node.lua", "hills"], env={"MODE": mode}, timeout=300)
        last = out.strip().splitlines()[-1] if out.strip() else ""
        m = re.search(r"real pos (\S+ \S+ \S+)\s+saved (\S+ \S+ \S+)", last)
        ok = bool(m) and m.group(1) == m.group(2) and (mode == "crash" or "task=idle" in last)
        return ok, last

# ---- the mining team simulator
MINING = ["plain", "team2", "team3", "team5", "caves", "reboot", "team3reboot", "team5caves", "full", "direct", "core",
          "otherfuel", "loaderdrift", "wrongface", "gpsfix", "r1", "nofuel", "ownfull", "geoname", "corein", "modemon",
          "newfield", "team2newfield", "team3crosspause", "team3drop", "team5drop", "team3dropalive",
          "nearstation", "team3nearstation", "team3crashunload", "team2warpfail", "team3silentback",
          "team2join", "team3join", "team2joincaves", "team2joinfar", "team2neighbour", "team3neighboureq", "team2update", "team3updatecaves"]
if QUICK:
    MINING = ["plain", "team3", "reboot", "newfield", "team3crosspause", "team3drop", "team3dropalive", "wrongface", "team3nearstation", "team3crashunload", "team2join", "team2neighbour", "team2update"]
HOURS = "1" if QUICK else "2"
for scen in MINING:
    @check("mining", scen)
    def _(scen=scen):
        rc, out = run(["lua5.3", "tools/navsim/minesim.lua", HOURS, scen], timeout=900)
        fails = [l for l in out.splitlines() if re.match(r"\s+\[\d+s\]", l)]
        speed = (re.findall(r"SPEED: \d+ ores/hour", out) or ["?"])[0]
        ok = out.strip().endswith("OK") and not fails
        return ok, speed if ok else ("\n".join(fails) or out[-600:])

# ---- run
todo = [c for c in checks if not ONLY or ONLY in (c[0] + " " + c[1])]
t0 = time.time()
results = []
def go(c):
    group, name, fn = c
    t = time.time()
    try:
        ok, detail = fn()
    except Exception as ex:
        ok, detail = False, "runner error: %r" % ex
    return group, name, ok, detail, time.time() - t
with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
    for r in ex.map(go, todo):
        results.append(r)
        group, name, ok, detail, dt = r
        print("%-4s %-8s %-38s %5.1fs  %s" % ("ok" if ok else "FAIL", group, name, dt,
              (detail.splitlines()[0] if ok and detail else "")[:60]), flush=True)
bad = [r for r in results if not r[2]]
print()
for group, name, ok, detail, dt in bad:
    print("=" * 70)
    print("FAILED: %s / %s" % (group, name))
    print(detail)
print("%d checks, %d failed, %.0f s" % (len(results), len(bad), time.time() - t0))
sys.exit(1 if bad else 0)
