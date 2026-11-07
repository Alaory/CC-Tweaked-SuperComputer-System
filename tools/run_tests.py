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
                     ("node.lua", ["node.lua"])]:
    @check("globals", label)
    def _(files=files):
        rc, out = run(["python3", "tools/check_globals.py"] + files)
        return rc == 0, out.strip()

@check("globals", "missing locals (base)")
def _():
    files = ["inventory.lua"] + sorted(os.path.basename(f) for f in glob.glob(os.path.join(ROOT, "base_*.lua")))
    rc, out = run(["python3", "tools/check_globals.py", "--leaks"] + files)
    return rc == 0, out.strip()
for f in ["miner.lua", "store.lua", "startup.lua", "node.lua"]:
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

# ---- base tests (CHECKs inside) and every page
for t in sorted(glob.glob(os.path.join(ROOT, "tools", "tests", "test_*.lua"))):
    name = os.path.basename(t)
    @check("base", name)
    def _(t=t):
        rc, out = run(["lua5.3", "run.lua", "../..", "/tmp/run_tests_%d.txt" % os.getpid(), "system", t],
                      cwd=PREVIEW, env={"TESTMODE": "1"})
        tail = "\n".join(l for l in out.splitlines() if l.startswith(("FAIL", "PASS", "lua5.3:")) or "ERROR" in l)
        return rc == 0 and "PASS" in out, tail or out[-800:]

PAGES = ["inventory", "players", "storage", "curios", "me", "drone", "access", "turtles", "map", "mining",
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
          "newfield", "team2newfield", "team3crosspause", "team3drop", "team5drop", "team3dropalive"]
if QUICK:
    MINING = ["plain", "team3", "reboot", "newfield", "team3crosspause", "team3drop", "team3dropalive", "wrongface"]
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
