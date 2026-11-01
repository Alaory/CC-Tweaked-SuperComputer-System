#!/usr/bin/env python3
"""Local-variable budget of a Lua file, the way the game's Lua (Cobalt) counts it.

Cobalt adds the file-level locals that are in scope to every function's own
locals and refuses more than 200 ("function at line N has more than 200 local
variables"). Standard luac does not, so `luac -p` passes such files.

usage: python3 tools/check_locals.py node.lua   (needs luac5.3)
"""
import re, subprocess, sys

path = sys.argv[1] if len(sys.argv) > 1 else "node.lua"
listing = subprocess.run(["luac5.3", "-l", "-l", "-p", path], capture_output=True, text=True).stdout
funcs = []
for block in re.split(r"\n(?=(?:main|function) <)", listing):
    m = re.match(r"(main|function) <[^:]*:(\d+),(\d+)>", block)
    if not m or "locals (" not in block:
        continue
    part = block.split("locals (")[1]
    ranges = [(int(a), int(b)) for a, b in re.findall(r"^\s+\d+\s+\S+\s+(\d+)\s+(\d+)\s*$", part, re.M)]
    events = sorted([(s, 1) for s, _ in ranges] + [(e, -1) for _, e in ranges], key=lambda x: (x[0], x[1]))
    cur = most = 0
    for _, d in events:
        cur += d
        most = max(most, cur)
    funcs.append((m.group(1), int(m.group(2)), most))
main = next(f[2] for f in funcs if f[0] == "main")
worst = max((f for f in funcs if f[0] != "main"), key=lambda f: f[2])
total = main + worst[2]
print(f"{path}: file level {main} locals + biggest function (line {worst[1]}) {worst[2]} = {total} of 200")
sys.exit(1 if total > 180 else 0)
