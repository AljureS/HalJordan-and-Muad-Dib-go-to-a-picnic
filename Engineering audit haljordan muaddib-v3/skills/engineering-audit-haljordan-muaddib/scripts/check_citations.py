#!/usr/bin/env python3
"""Verify that every path:line citation in a Markdown report resolves.

Usage: check_citations.py REPORT.md [--root REPO_ROOT] [--context 3] [--lenient-symbols]

What counts as a citation
  * anything in backticks shaped like `path:line` or `path:start-end` — paths may
    contain spaces and need no extension (`Dockerfile:12`, `docs/my file.md:3-9`);
  * outside backticks, tokens with a slash or an extension (src/app.ts:12), and
    bare names only when that file exists at the root (Dockerfile:12).
  URLs, IP:port and times are ignored.
Checks
  * the file exists under the root; start ≥ 1; end ≥ start; both within the file;
  * when a citation is followed by (`symbol` …), the symbol text must appear within
    --context lines of the cited range — a line that exists but does not contain the
    claimed symbol is reported (as a problem, or a warning with --lenient-symbols);
  * backticked spans that look like citations but do not parse are listed as WARN UNPARSED.
Exit codes: 0 every citation resolves · 1 problems · 2 no citation found at all.
"""
import argparse
import os
import re
import sys

BACKTICK = re.compile(r"`([^`\n]+)`")
CITE = re.compile(r"^(?P<path>.+?):(?P<start>\d+)(?:-(?P<end>\d+))?$")
URL = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://[^\s)>\]]+")
BARE = re.compile(r"(?<![\w`/:.@-])((?:[\w.@-]+/)+[\w.@-]+|[\w@-]+\.[A-Za-z0-9]+):(\d+)(?:-(\d+))?(?![\w:])")
BARE_NOEXT = re.compile(r"(?<![\w`/:.@-])([A-Za-z][\w-]*):(\d+)(?:-(\d+))?(?![\w:])")
SYMBOL_AFTER = re.compile(r"^\s*\((?:`([^`]+)`|\"([^\"]+)\")")


def line_count(path):
    with open(path, "rb") as f:
        data = f.read()
    return len(data.splitlines())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("report")
    ap.add_argument("--root", default=".")
    ap.add_argument("--context", type=int, default=3)
    ap.add_argument("--lenient-symbols", action="store_true")
    args = ap.parse_args()
    try:
        text = open(args.report, encoding="utf-8").read()
    except OSError as e:
        print(f"report not found: {e}")
        return 1

    citations = {}   # (path, start, end) -> list of symbols claimed next to it
    unparsed = []
    # 1. backticked spans
    for m in BACKTICK.finditer(text):
        span = m.group(1).strip()
        c = CITE.match(span)
        if c:
            key = (c.group("path").strip().lstrip("./"), int(c.group("start")), int(c.group("end") or c.group("start")))
            citations.setdefault(key, [])
            after = SYMBOL_AFTER.match(text[m.end():m.end() + 300])
            if after:
                citations[key].append((after.group(1) or after.group(2)).strip())
        elif re.search(r":\s*\d", span) and not URL.search(span) and re.search(r"[A-Za-z]", span.split(":")[0]):
            unparsed.append(span)
    # 2. bare tokens outside backticks and URLs
    stripped = URL.sub(" ", BACKTICK.sub(" ", text))
    for m in BARE.finditer(stripped):
        key = (m.group(1).lstrip("./"), int(m.group(2)), int(m.group(3) or m.group(2)))
        citations.setdefault(key, [])
    for m in BARE_NOEXT.finditer(stripped):
        if os.path.isfile(os.path.join(args.root, m.group(1))):
            key = (m.group(1), int(m.group(2)), int(m.group(3) or m.group(2)))
            citations.setdefault(key, [])

    problems = 0
    warnings = 0
    for (path, start, end), symbols in sorted(citations.items()):
        label = f"{path}:{start}" + (f"-{end}" if end != start else "")
        full = os.path.join(args.root, path)
        if not os.path.isfile(full):
            print(f"MISSING FILE     {label}")
            problems += 1
            continue
        n = line_count(full)
        if start < 1 or start > n:
            print(f"BAD LINE         {label} (file has {n} lines)")
            problems += 1
            continue
        if end < start or end > n:
            print(f"BAD RANGE        {label} (file has {n} lines)")
            problems += 1
            continue
        if symbols:
            with open(full, encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
            lo, hi = max(0, start - 1 - args.context), min(n, end + args.context)
            window = "\n".join(lines[lo:hi])
            for sym in symbols:
                if sym not in window:
                    tag = "WARN SYMBOL      " if args.lenient_symbols else "SYMBOL NOT NEAR  "
                    print(f"{tag}{label} claims `{sym}` within ±{args.context} lines, not found")
                    if args.lenient_symbols:
                        warnings += 1
                    else:
                        problems += 1
    for span in unparsed:
        print(f"WARN UNPARSED    `{span}` looks like a citation but is not path:line")
        warnings += 1

    print(f"checked {len(citations)} citations, {problems} problems, {warnings} warnings")
    if not citations:
        print("no citations found: a report without path:line evidence is not verified")
        return 2
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
