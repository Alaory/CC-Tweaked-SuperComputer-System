#!/usr/bin/env python3
"""Undefined global names (a typo, or a function that does not exist): every
global READ in the given files must be SET somewhere in them, or be a
ComputerCraft / Lua built-in. Needs luac5.3.
   python3 tools/check_globals.py inventory.lua base_*.lua"""
import subprocess, re, sys
BUILTIN = set("""_G _ENV _HOST os fs term peripheral rednet turtle textutils colors colours shell parallel window
gps http keys vector paintutils settings multishell disk redstone rs read write print printError sleep error
pcall xpcall ipairs pairs tostring tonumber type select table string math next setmetatable getmetatable
rawget rawset rawequal rawlen assert load loadstring loadfile unpack dofile require coroutine bit32 utf8 io
debug package""".split())
def accesses(f):
    """(kind GET/SET, in main chunk?, line, name) for every global access. Big
    files (> 255 constants) load the name into a register first (LOADK) - the
    access line then has no name: it is taken from that LOADK."""
    out = subprocess.run(["luac5.3", "-l", "-l", "-p", f], capture_output=True, text=True).stdout
    res, main, regs = [], True, {}
    for line in out.splitlines():
        m = re.match(r'^(main|function) <', line)
        if m:
            main, regs = (m.group(1) == "main"), {}
            continue
        m = re.search(r'\[(\d+)\]\s+(\w+)\s+(-?\d+)\s+(-?\d+)(?:\s+(-?\d+))?\s*(?:;\s*(.*))?$', line)
        if not m: continue
        ln, op, a, b, c, note = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4)), m.group(5), m.group(6) or ""
        if op == "LOADK":
            k = re.match(r'"([^"]*)"', note)
            regs[a] = k.group(1) if k else None
            continue
        if op in ("GETTABUP", "SETTABUP") and "_ENV" in note:
            k = re.search(r'_ENV "([^"]+)"', note)
            name = k.group(1) if k else None
            if not name:
                key = int(c) if op == "GETTABUP" else b          # GETTABUP A B C: key RK(C); SETTABUP A B C: key RK(B)
                if key >= 0: name = regs.get(key)
            if name: res.append(("GET" if op == "GETTABUP" else "SET", main, ln, name))
        elif a in regs:
            regs.pop(a, None)                                # register overwritten
    return res
def scan(f):
    gets, sets = set(), set()
    for kind, main, ln, name in accesses(f):
        (gets if kind == "GET" else sets).add(name)
    return gets, sets
# globals the base files set INSIDE functions on purpose (shared state); any
# other one is probably a missing `local` (--leaks)
SHARED = set("""USER_ACTION bridge bridgeKind chatBox det envDet inv ownChargers sharedTop sortMode MESETUP
NOTE_LASTBOX NOTE_LOGGED NOTE_LOGGED_N NOTE_SEEN OWED selName H PALETTE THEME_NAME W shownRows win CODE
EXITROUTE hits THEME_MODE""".split())
leaks = "--leaks" in sys.argv
upper_ok = "--upper-ok" in sys.argv          # miner.lua / node.lua style: UPPER_CASE names are flags on purpose
files = [a for a in sys.argv[1:] if not a.startswith("--")]
data = {f: scan(f) for f in files}
allsets = set().union(*(s for _, s in data.values())) if data else set()
bad = 0
for f, (g, _) in data.items():
    miss = sorted(g - allsets - BUILTIN)
    if miss:
        bad += 1
        print(f"{f}: used but never defined: {', '.join(miss)}")
if leaks:
    # a name set inside a function, never at file level in any of the files and
    # not known shared state: most likely a missing `local`
    def sets(f):
        return [(main, ln, name) for kind, main, ln, name in accesses(f) if kind == "SET"]
    allsets_by_file = {f: sets(f) for f in files}
    top = {name for f in files for (main, _, name) in allsets_by_file[f] if main}
    for f in files:
        for main, line, name in allsets_by_file[f]:
            if not main and name not in top and name not in SHARED and not (upper_ok and re.fullmatch(r"[A-Z0-9_]+", name)):
                bad += 1
                print(f"{f}:{line}: '{name}' is set inside a function and nowhere else - a missing local?")
sys.exit(1 if bad else 0)
