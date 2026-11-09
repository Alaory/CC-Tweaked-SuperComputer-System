#!/usr/bin/env python3
"""Slim copies of the program files for the in-game computers (1 MB disk):
comments (whole-line, end-of-line, --[[ ]] blocks), indentation and trailing
spaces removed - text INSIDE strings (also [[ ]] long strings) is never touched,
and every line stays where it was (error line numbers still match).

    slim(text) -> text
    python3 tools/slim.py <file.lua>       prints the slim version

tools/make_manifest.py writes them to dist/ (the `upgrade` command downloads
those) and run_tests checks each one compiles to EXACTLY the same code as the
full file (luac -s, byte for byte)."""
import re, sys

LONG_OPEN = re.compile(r"\[(=*)\[")


def slim(text):
    out = []
    mode = None          # None, ("str", closer) = inside a long string, ("com", closer) = long comment
    for line in text.split("\n"):
        if mode and mode[0] == "str":
            # inside a [[ long string ]]: keep the line exactly (spaces matter)
            end = line.find(mode[1])
            if end < 0:
                out.append(line)
                continue
            head, rest = line[:end + len(mode[1])], line[end + len(mode[1]):]
            mode = None
            body, mode = scan(rest)
            out.append((head + body).rstrip())
            continue
        if mode and mode[0] == "com":
            end = line.find(mode[1])
            if end < 0:
                out.append("")
                continue
            rest = line[end + len(mode[1]):]
            mode = None
            body, mode = scan(rest.lstrip())
            out.append(body.rstrip())
            continue
        body, mode = scan(line.lstrip())
        out.append(body if (mode and mode[0] == "str") else body.rstrip())
    return "\n".join(out)


def scan(s):
    """One line outside any long string/comment: drop comments, keep strings.
    Returns (kept text, mode at the end of the line)."""
    res, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            j = i + 1
            while j < n and s[j] != c:
                j += 2 if s[j] == "\\" else 1
            res.append(s[i:j + 1])
            i = j + 1
            continue
        if c == "[":
            m = LONG_OPEN.match(s, i)
            if m:
                closer = "]" + m.group(1) + "]"
                end = s.find(closer, m.end())
                if end < 0:
                    res.append(s[i:])
                    return "".join(res), ("str", closer)
                res.append(s[i:end + len(closer)])
                i = end + len(closer)
                continue
        if s.startswith("--", i):
            m = LONG_OPEN.match(s, i + 2)
            if m:
                closer = "]" + m.group(1) + "]"
                end = s.find(closer, m.end())
                if end < 0:
                    return "".join(res), ("com", closer)
                i = end + len(closer)
                res.append(" ")                     # (a block comment between tokens)
                continue
            return "".join(res), None               # rest of the line is a comment
        res.append(c)
        i += 1
    return "".join(res), None


if __name__ == "__main__":
    sys.stdout.write(slim(open(sys.argv[1], encoding="latin-1").read()))
