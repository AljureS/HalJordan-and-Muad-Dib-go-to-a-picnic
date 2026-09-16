#!/usr/bin/env python3
"""Decide whether each provider account may take a task, from normalized usage records.

Usage:
  usage_decide.py [--records FILE ...] [--ledger PATH] [--reserve 15] [--max-age-min 30]
                  [--provider openai|anthropic|all] [--account-alias ALIAS] [--bucket ID] [--now ISO8601]

Rules applied (see references/usage-contract.md):
  * every applicable window must clear the reserve; a weekly limit that is exhausted
    blocks the account even when the 5-hour window has room;
  * unknown, unavailable, or stale windows never count as room; they make the verdict
    "unknown" (re-read or ask the owner) unless another window already blocks;
  * only the latest record per (provider, account, billing mode, bucket) is used, and
    records for other accounts are ignored — switching accounts never reuses a balance;
  * verdicts are per account. Percentages are never compared across providers; the
    executor is chosen by task fit among the eligible accounts, not by "who has more".

Exit: 0 (verdicts printed as JSON, human summary on stderr).
"""
import argparse
import json
import sys
from datetime import datetime, timedelta, timezone


def parse_iso(s):
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def load_records(args):
    recs = []
    for path in args.records or []:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        recs.extend(data.get("records", data if isinstance(data, list) else [data]))
    if args.ledger:
        with open(args.ledger, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    recs.append(json.loads(line))
    return recs


def latest_per_key(recs):
    best = {}
    for r in recs:
        obs = max((parse_iso(w.get("observed_at")) or datetime.min.replace(tzinfo=timezone.utc)) for w in r.get("windows", [])) if r.get("windows") else datetime.min.replace(tzinfo=timezone.utc)
        key = (r.get("provider"), r.get("account_alias"), r.get("billing_mode"), r.get("bucket_id"))
        if key not in best or obs >= best[key][0]:
            best[key] = (obs, r)
    return [r for _, r in best.values()]


def judge_window(w, reserve, now, max_age):
    if w.get("availability") != "known":
        return "unknown", f"{w.get('window_role')}: not reported ({w.get('availability')})"
    obs = parse_iso(w.get("observed_at"))
    if obs is None or now - obs > timedelta(minutes=max_age) or w.get("freshness") == "stale":
        return "unknown", f"{w.get('window_role')}: reading is stale — re-read before deciding"
    rem = w.get("remaining_percent")
    if rem is None:
        return "unknown", f"{w.get('window_role')}: remaining unknown"
    if w.get("window_role") == "spend_limit":
        if rem <= 0:
            return "blocked", "spend_limit: exceeded"
        return "ok", f"spend_limit: {rem:.0f}% of the spend limit left (money, not a rate window)"
    if rem <= reserve:
        return "blocked", f"{w.get('window_role')}: {rem:.0f}% left ≤ reserve {reserve:.0f}% (resets {w.get('resets_at') or 'unknown'})"
    return "ok", f"{w.get('window_role')}: {rem:.0f}% left (resets {w.get('resets_at') or 'unknown'})"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--records", nargs="*")
    ap.add_argument("--ledger")
    ap.add_argument("--reserve", type=float, default=15.0, help="percent to keep untouched in every window (owner's policy)")
    ap.add_argument("--max-age-min", type=float, default=30.0)
    ap.add_argument("--provider", default="all")
    ap.add_argument("--account-alias")
    ap.add_argument("--bucket", help="bucket/limit id the task will consume; other buckets are reported but not decisive")
    ap.add_argument("--now")
    args = ap.parse_args()
    now = parse_iso(args.now) or datetime.now(timezone.utc)

    recs = latest_per_key(load_records(args))
    verdicts = []
    for r in recs:
        if args.provider != "all" and r.get("provider") != args.provider:
            continue
        if args.account_alias and r.get("account_alias") != args.account_alias:
            continue
        applicable = (args.bucket is None) or (r.get("bucket_id") == args.bucket)
        results = [judge_window(w, args.reserve, now, args.max_age_min) for w in r.get("windows", [])]
        states = [s for s, _ in results]
        if r.get("rate_limit_reached"):
            states.append("blocked")
            results.append(("blocked", f"provider reports rate_limit_reached={r['rate_limit_reached']}"))
        if "blocked" in states:
            verdict = "blocked"
        elif "ok" not in states:
            verdict = "unknown"
        elif "unknown" in states:
            verdict = "ok_with_unknown"
        else:
            verdict = "ok"
        verdicts.append({
            "provider": r.get("provider"), "account_alias": r.get("account_alias"), "billing_mode": r.get("billing_mode"),
            "bucket_id": r.get("bucket_id"), "applicable_to_task": applicable, "verdict": verdict,
            "eligible": applicable and verdict in ("ok", "ok_with_unknown"),
            "reasons": [msg for _, msg in results],
            "identity_verified": r.get("identity_verified", False),
        })

    eligible = sorted({(v["provider"], v["account_alias"]) for v in verdicts if v["eligible"]})
    blocked = sorted({(v["provider"], v["account_alias"]) for v in verdicts if v["applicable_to_task"] and v["verdict"] == "blocked"})
    eligible = [e for e in eligible if e not in blocked]  # one blocked applicable bucket blocks the account
    out = {
        "now": now.isoformat().replace("+00:00", "Z"),
        "reserve_percent": args.reserve,
        "verdicts": verdicts,
        "eligible_accounts": [f"{p}:{a}" for p, a in eligible],
        "choose_by": "task fit, tool availability, context continuity and coordination cost among eligible accounts — never by comparing percentages across providers",
    }
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")
    for v in verdicts:
        print(f"[{v['verdict']:^15}] {v['provider']}:{v['account_alias']} bucket={v['bucket_id']} " + "; ".join(v["reasons"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
