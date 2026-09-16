#!/usr/bin/env python3
"""Normalize a provider usage payload into the shared usage contract.

Usage:
  usage_normalize.py --provider openai    [opts] [INPUT.json | -]   # account/rateLimits/read result
  usage_normalize.py --provider anthropic [opts] [INPUT.json | -]   # Claude Code statusline JSON (or capture file)
  usage_normalize.py --provider manual    [opts] [INPUT.json | -]   # windows typed by the user

Options:
  --account-alias ALIAS   local, secret-free label for the identity (default: "unknown")
  --billing-mode MODE     subscription | api | unknown (default: guessed, see notes)
  --source TEXT           where the payload came from (tool, script, panel, manual)
  --observed-at ISO8601   when the payload was read (default: now; capture files carry their own)
  --max-age-min N         readings older than N minutes are marked stale (default 30)
  --ledger PATH           append the records as JSON lines to this file
  --now ISO8601           override "now" (tests)

Output: {"records": [...]} on stdout. Every window keeps used_percent as given; a
missing or non-numeric value stays unknown (never zero). Nothing is summed across
buckets, accounts, or providers, and percentages are never converted to tokens.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone

ROLE_BY_MINUTES = {300: "5h", 10080: "7d", 43200: "30d", 1440: "24h"}


def parse_iso(s):
    if not s:
        return None
    try:
        s = s.replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z") if dt else None


def epoch_to_iso(v):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return iso(datetime.fromtimestamp(v, tz=timezone.utc))
    return None


def num_or_none(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return float(v)


def window(role, used, duration_min, resets_iso, slot, source, observed_at, now, max_age, extra=None):
    w = {
        "window_role": role,               # derived from duration, never from the slot name
        "provider_slot": slot,             # primary / secondary / five_hour / ... (traceability only)
        "duration_minutes": duration_min,
        "used_percent": None,
        "remaining_percent": None,
        "raw_used_percent": used,
        "resets_at": resets_iso,
        "source": source,
        "observed_at": iso(observed_at),
        "freshness": "unknown",
        "availability": "unknown",
        "notes": [],
    }
    if extra:
        w.update(extra)
    u = num_or_none(used)
    if used is None:
        w["availability"] = "unavailable"
        w["notes"].append("window not reported by the provider (null/absent): unknown, not zero")
    elif u is None:
        w["availability"] = "unknown"
        w["notes"].append("used_percent is not numeric; kept raw, treated as unknown")
    else:
        w["availability"] = "known"
        w["used_percent"] = u
        if u > 100:
            w["notes"].append("used_percent above 100: over the limit")
        if u < 0:
            w["notes"].append("negative used_percent: unexpected value")
        w["remaining_percent"] = max(0.0, min(100.0, 100.0 - u))
    if observed_at is not None:
        age = now - observed_at
        w["freshness"] = "fresh" if age <= timedelta(minutes=max_age) else "stale"
        r = parse_iso(resets_iso)
        if r and r <= now:
            w["freshness"] = "stale"
            w["notes"].append("reset time has passed since this reading; re-read before deciding")
    return w


def role_from_minutes(mins):
    if mins is None:
        return "unknown-duration"
    return ROLE_BY_MINUTES.get(int(mins), f"{int(mins)}m")


def base_record(provider, args, billing, plan, bucket_id, scope):
    return {
        "provider": provider,
        "account_alias": args.account_alias,
        "organization_or_workspace": None,
        "identity_verified": False,   # the reader cannot prove which identity produced the payload
        "billing_mode": billing,
        "plan": plan,
        "bucket_id": bucket_id,
        "scope": scope,
        "windows": [],
        "rate_limit_reached": None,
        "session_tokens": None,
        "session_cost_estimate": None,
        "notes": [],
    }


def normalize_openai(payload, args, now, observed_at):
    if "result" in payload and isinstance(payload["result"], dict):
        payload = payload["result"]
    by_id = payload.get("rateLimitsByLimitId")
    snapshots = []
    if isinstance(by_id, dict) and by_id:
        snapshots = list(by_id.values())          # multi-bucket view wins; legacy view is the same data
    elif isinstance(payload.get("rateLimits"), dict):
        snapshots = [payload["rateLimits"]]
    billing = args.billing_mode or ("api" if os.environ.get("CODEX_API_KEY") or os.environ.get("OPENAI_API_KEY") else "subscription")
    records = []
    seen = set()
    for snap in snapshots:
        bucket = snap.get("limitId") or "unknown-bucket"
        if bucket in seen:
            continue
        seen.add(bucket)
        scope_bits = [b for b in (snap.get("limitName"), snap.get("normalModelSlug")) if b]
        rec = base_record("openai", args, billing, snap.get("planType"), bucket, " / ".join(scope_bits) or "account")
        for slot in ("primary", "secondary"):
            w = snap.get(slot)
            if isinstance(w, dict):
                rec["windows"].append(window(role_from_minutes(w.get("windowDurationMins")), w.get("usedPercent"), w.get("windowDurationMins"),
                                             epoch_to_iso(w.get("resetsAt")), slot, args.source, observed_at, now, args.max_age_min))
                if isinstance(w, dict) and w.get("resetsAt") is None:
                    rec["windows"][-1]["notes"].append("resetsAt null: reset time unknown, not 'no reset'")
            else:
                rec["windows"].append(window("unknown", None, None, None, slot, args.source, observed_at, now, args.max_age_min))
        rec["rate_limit_reached"] = snap.get("rateLimitReachedType")
        credits = snap.get("credits")
        if isinstance(credits, dict):
            rec["credits"] = {"has_credits": credits.get("hasCredits"), "unlimited": credits.get("unlimited"), "balance": credits.get("balance"),
                              "unit": "credits (informational; not a percentage, not tokens)"}
        records.append(rec)
    if not records:
        rec = base_record("openai", args, billing, None, "unknown-bucket", "account")
        rec["windows"].append(window("unknown", None, None, None, None, args.source, observed_at, now, args.max_age_min))
        rec["notes"].append("payload had neither rateLimitsByLimitId nor rateLimits")
        records.append(rec)
    return records


def normalize_anthropic(payload, args, now, observed_at):
    if "statusline" in payload and isinstance(payload["statusline"], dict):
        cap_obs = parse_iso(payload.get("observed_at"))
        if cap_obs:
            observed_at = cap_obs
        payload = payload["statusline"]
    billing = args.billing_mode or ("api" if os.environ.get("ANTHROPIC_API_KEY") else "unknown")
    rl = payload.get("rate_limits")
    rec = base_record("anthropic", args, billing, None, "claude-subscription", "claude.ai Pro/Max subscription (shared by Claude web, Desktop and Claude Code)")
    if isinstance(rl, dict) and rl:
        if billing == "unknown":
            rec["billing_mode"] = "subscription"
            rec["notes"].append("rate_limits present, so this session is on a claude.ai subscription")
        for slot, role, mins in (("five_hour", "5h", 300), ("seven_day", "7d", 10080)):
            w = rl.get(slot)
            if isinstance(w, dict):
                rec["windows"].append(window(role, w.get("used_percentage"), mins, epoch_to_iso(w.get("resets_at")), slot, args.source, observed_at, now, args.max_age_min))
            else:
                rec["windows"].append(window(role, None, mins, None, slot, args.source, observed_at, now, args.max_age_min,
                                             {"notes": ["window absent: Claude Code drops a window once it resets, or it was never reported"]}))
        sl = rl.get("spend_limit")
        if isinstance(sl, dict):
            rec["windows"].append(window("spend_limit", sl.get("used_percentage"), None, epoch_to_iso(sl.get("resets_at")), "spend_limit", args.source, observed_at, now, args.max_age_min,
                                         {"unit": "percent of a gateway spend limit (money), not a rate-limit window"}))
    else:
        for slot, role, mins in (("five_hour", "5h", 300), ("seven_day", "7d", 10080)):
            rec["windows"].append(window(role, None, mins, None, slot, args.source, observed_at, now, args.max_age_min))
        rec["notes"].append("rate_limits absent: not a Pro/Max session, no API response yet, or statusline capture not enabled — quota unknown")
    cw = payload.get("context_window") or {}
    if isinstance(cw, dict) and (cw.get("total_input_tokens") is not None or cw.get("total_output_tokens") is not None):
        rec["session_tokens"] = {"input_incl_cache": cw.get("total_input_tokens"), "output": cw.get("total_output_tokens"),
                                 "context_window_size": cw.get("context_window_size"), "context_used_percent": cw.get("used_percentage"),
                                 "unit": "tokens in this session's context window; not a quota"}
    cost = payload.get("cost") or {}
    if isinstance(cost, dict) and cost.get("total_cost_usd") is not None:
        rec["session_cost_estimate"] = {"usd": cost.get("total_cost_usd"), "unit": "client-side list-price estimate for this session; not a bill"}
    return [rec]


def normalize_manual(payload, args, now, observed_at):
    billing = args.billing_mode or payload.get("billing_mode") or "unknown"
    rec = base_record(payload.get("provider", "unknown"), args, billing, payload.get("plan"), payload.get("bucket_id", "manual"), payload.get("scope", "as typed by the user"))
    rec["notes"].append("manual reading typed by the user; not verified against the provider")
    for w in payload.get("windows", []):
        mins = w.get("duration_minutes")
        rec["windows"].append(window(w.get("window_role") or role_from_minutes(mins), w.get("used_percent"), mins, w.get("resets_at"), "manual", args.source or "manual", observed_at, now, args.max_age_min))
    if not rec["windows"]:
        rec["windows"].append(window("unknown", None, None, None, "manual", args.source or "manual", observed_at, now, args.max_age_min))
    return [rec]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", nargs="?", default="-")
    ap.add_argument("--provider", required=True, choices=["openai", "anthropic", "manual"])
    ap.add_argument("--account-alias", default="unknown")
    ap.add_argument("--billing-mode", choices=["subscription", "api", "unknown"])
    ap.add_argument("--source", default=None)
    ap.add_argument("--observed-at")
    ap.add_argument("--max-age-min", type=float, default=30.0)
    ap.add_argument("--ledger")
    ap.add_argument("--now")
    args = ap.parse_args()
    if args.source is None:
        args.source = {"openai": "codex app-server account/rateLimits/read", "anthropic": "claude code statusline rate_limits", "manual": "manual"}[args.provider]
    now = parse_iso(args.now) or datetime.now(timezone.utc)
    observed_at = parse_iso(args.observed_at) or now
    raw = sys.stdin.read() if args.input == "-" else open(args.input, encoding="utf-8").read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"input is not JSON: {e}", file=sys.stderr)
        return 1
    fn = {"openai": normalize_openai, "anthropic": normalize_anthropic, "manual": normalize_manual}[args.provider]
    records = fn(payload, args, now, observed_at)
    if args.ledger:
        os.makedirs(os.path.dirname(os.path.abspath(args.ledger)), exist_ok=True)
        with open(args.ledger, "a", encoding="utf-8") as f:
            for r in records:
                f.write(json.dumps(r) + "\n")
    json.dump({"records": records}, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
