#!/usr/bin/env python3
"""Undefined global names (a typo, or a function that does not exist): every
global READ in the given files must be SET somewhere in them, or be a
ComputerCraft / Lua built-in. Needs luac5.3. Not for node.lua (too many
constants for the listing this reads).
   python3 tools/check_globals.py inventory.lua base_*.lua"""
import subprocess, re, sys
BUILTIN = set("""_G _ENV _HOST os fs term peripheral rednet turtle textutils colors colours shell parallel window
gps http keys vector paintutils settings multishell disk redstone read write print printError sleep error
pcall xpcall ipairs pairs tostring tonumber type select table string math next setmetatable getmetatable
rawget rawset rawequal rawlen assert load loadstring loadfile unpack dofile require coroutine bit32 utf8 io
debug package""".split())
def scan(f):
    out = subprocess.run(["luac5.3", "-l", "-l", "-p", f], capture_output=True, text=True).stdout
    gets, sets = set(), set()
    for line in out.splitlines():
        m = re.search(r'(GETTABUP|SETTABUP)\s.*_ENV "([^"]+)"', line)
        if m: (gets if m.group(1) == "GETTABUP" else sets).add(m.group(2))
    return gets, sets
files = sys.argv[1:]
data = {f: scan(f) for f in files}
allsets = set().union(*(s for _, s in data.values())) if data else set()
bad = 0
for f, (g, _) in data.items():
    miss = sorted(g - allsets - BUILTIN)
    if miss:
        bad += 1
        print(f"{f}: used but never defined: {', '.join(miss)}")
sys.exit(1 if bad else 0)
