#!/usr/bin/env python3
"""Stand-in for `codex app-server` used by the tests. Answers initialize and
account/rateLimits/read from a fixture (FAKE_FIXTURE env var) and exits with
status 9 if the client sends any method outside the allowed set."""
import json, os, sys
allowed = {"initialize", "initialized", "account/rateLimits/read"}
fixture = json.load(open(os.environ["FAKE_FIXTURE"]))
print(json.dumps({"method": "noise/notification", "params": {}}), flush=True)  # unrelated notification
for line in sys.stdin:
    if not line.strip():
        continue
    msg = json.loads(line)
    m = msg.get("method")
    if m not in allowed:
        sys.stderr.write(f"forbidden method {m}\n"); sys.exit(9)
    if m == "initialize":
        print(json.dumps({"id": msg["id"], "result": {"userAgent": "fake", "platformFamily": "unix"}}), flush=True)
    elif m == "account/rateLimits/read":
        print(json.dumps({"id": msg["id"], "result": fixture}), flush=True)
