#!/usr/bin/env python3
"""Read Codex subscription rate limits through `codex app-server` (JSON-RPC over stdio).

This script sends exactly three messages: `initialize`, the `initialized`
notification, and `account/rateLimits/read`. It never starts a thread, never
runs a command, and never calls `account/rateLimitResetCredit/consume` or any
other method that could spend, buy, or reset anything.

Usage:
  codex_usage_read.py [--timeout 20] [--settle 0.5] [--codex-bin "codex"]

Output: the raw JSON `result` of account/rateLimits/read on stdout.
Exit codes: 0 ok · 2 codex binary not found · 3 timeout, protocol error, or
            the server answered with an error (details on stderr).
Requires: Codex CLI installed and logged in (`codex login status`), and network
access from this shell — the limits are fetched live from the account.
"""
import argparse
import json
import shlex
import shutil
import subprocess
import sys
import threading
import time
from queue import Empty, Queue

ALLOWED_METHODS = ("initialize", "initialized", "account/rateLimits/read")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--timeout", type=float, default=20.0, help="seconds to wait for the answer")
    ap.add_argument("--settle", type=float, default=0.5, help="pause after the handshake before asking")
    ap.add_argument("--codex-bin", default="codex", help="command used to start the app server")
    args = ap.parse_args()

    cmd = shlex.split(args.codex_bin)
    if shutil.which(cmd[0]) is None and not cmd[0].startswith(("/", ".")):
        print(f"codex binary not found: {cmd[0]!r} (install Codex CLI and run `codex login`)", file=sys.stderr)
        return 2
    if cmd == ["codex"]:
        cmd = ["codex", "app-server"]

    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    except FileNotFoundError:
        print(f"could not start {cmd!r}", file=sys.stderr)
        return 2

    lines: "Queue[str]" = Queue()

    def pump() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            lines.put(line)
        lines.put("")  # EOF marker

    threading.Thread(target=pump, daemon=True).start()

    def send(msg: dict) -> None:
        assert msg["method"] in ALLOWED_METHODS, msg["method"]
        assert proc.stdin is not None
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()

    def wait_for(msg_id: int, deadline: float):
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            try:
                line = lines.get(timeout=remaining)
            except Empty:
                return None
            if line == "":
                return None  # server exited
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue  # non-JSON noise on stdout
            if msg.get("id") == msg_id:
                return msg

    deadline = time.monotonic() + args.timeout
    rc = 3
    try:
        send({"method": "initialize", "id": 1, "params": {"clientInfo": {"name": "collab_codex_claude", "title": "collab-haljordan-muaddib usage reader", "version": "1.0.0"}}})
        if wait_for(1, deadline) is None:
            print("timeout or server exit during initialize", file=sys.stderr)
            return 3
        send({"method": "initialized", "params": {}})
        time.sleep(args.settle)  # collectors report empty data when asking too early
        send({"method": "account/rateLimits/read", "id": 2, "params": {}})
        answer = wait_for(2, deadline)
        if answer is None:
            print("timeout waiting for account/rateLimits/read", file=sys.stderr)
            return 3
        if "error" in answer:
            print(json.dumps(answer["error"]), file=sys.stderr)
            return 3
        json.dump(answer.get("result", {}), sys.stdout)
        sys.stdout.write("\n")
        rc = 0
    finally:
        try:
            proc.kill()
        except Exception:
            pass
    return rc


if __name__ == "__main__":
    sys.exit(main())
