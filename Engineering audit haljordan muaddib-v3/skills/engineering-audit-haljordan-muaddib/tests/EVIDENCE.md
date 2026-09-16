# Test evidence — 2026-09-16T18:39Z, Linux container, python3 3.12.3, bash 

```
PASS  range end beyond file (short.js:2-999) is rejected
PASS  inverted range (short.js:3-1) is rejected
PASS  valid range (short.js:1-3) passes
PASS  extensionless file, bad line (Dockerfile:999) rejected
PASS  extensionless bare token (Dockerfile:999) also caught
PASS  extensionless file, good line (Dockerfile:2) passes
PASS  path with spaces resolves (docs/has spaces.md:1)
PASS  missing file reported
PASS  URLs, IP:port, localhost and clock times are ignored
PASS  zero citations -> exit 2 and explicit message
PASS  symbol near the cited line passes
PASS  symbol NOT near the cited line is a problem
PASS  --lenient-symbols downgrades symbol mismatch to warning
PASS  malformed backticked citation is reported as unparsed
PASS  same citation twice is checked once
PASS  inventory default: script names only, no command values
PASS  inventory default: token never printed
PASS  inventory --commands: command shown with secret redacted
PASS  inventory lists env file names only
----
passed 19, failed 0
```
