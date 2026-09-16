# Usage contract

A normalization of what each provider reports. It is not either provider's native format; every value is kept as reported, and every gap stays visible.

## Record (one per provider bucket)

```yaml
provider: openai | anthropic | unknown
account_alias: owner's local label, no secrets        # who this reading belongs to
organization_or_workspace: null                        # only when the provider reports it
identity_verified: false                               # a script cannot prove which identity answered
billing_mode: subscription | api | unknown             # API key present in the environment → api
plan: plus | pro | ... | null
bucket_id: codex | codex_bengalfox | claude-subscription | manual   # provider's limit id
scope: what the bucket applies to (limitName / model slug, or "account")
windows:
  - window_role: 5h | 7d | 30d | spend_limit | unknown  # derived from duration_minutes, never from the slot name
    provider_slot: primary | secondary | five_hour | seven_day | spend_limit | manual
    duration_minutes: 300 | 10080 | null
    used_percent: number | null
    remaining_percent: number | null                    # max(0, min(100, 100 - used)) only when used is numeric
    raw_used_percent: as received
    resets_at: ISO-8601 UTC | null                      # provider's value; null = unknown reset, not "no reset"
    source: tool | script | panel | manual
    observed_at: ISO-8601 UTC
    freshness: fresh | stale | unknown                  # stale after --max-age-min, or once resets_at has passed
    availability: known | unavailable | unknown         # unavailable = provider sent null/absent; unknown = unparseable
    notes: []
rate_limit_reached: null | rate_limit_reached | ...    # provider flag
credits: { has_credits, unlimited, balance, unit }     # Codex only, informational; not a percentage, not tokens
session_tokens: { ... unit: "tokens in this session's context window; not a quota" }   # Claude statusline only
session_cost_estimate: { usd, unit: "client-side estimate; not a bill" }
notes: []
```

## Dimensions that stay separate

- **Subscription quota**: the windows above (percent used per window, reset time).
- **Session tokens**: what one conversation holds in its context window (Claude `context_window.*`).
- **Context window**: the model's capacity, not consumption.
- **API limits and money**: organization/workspace scoped, request/token rates and budgets; never expressed as subscription percent.

There is no documented conversion from a subscription percentage to a token allowance; consumption depends on model, context, reasoning effort, tools and caching. The skill therefore never turns a percentage into "tokens left".

## Decision rules

1. Numeric `used` → `remaining`; otherwise unknown. Unknown ≠ 0.
2. Role from duration; reset from the provider.
3. Separate records per provider, identity, billing mode, bucket, window. Shared accounts do not multiply.
4. No sums, averages or cross-provider comparisons of percentages.
5. All applicable windows must clear the reserve; weekly exhaustion blocks regardless of the 5-hour window; another model's bucket does not apply.
6. Source, time, freshness on every reading; re-read on account change, window reset, before big delegations.
7. Measurements ≠ estimates; deltas include other sessions and devices.

## Worked example (real reading, 2026-09-16 ≈ 13:16 Bogotá, account id omitted)

Raw `account/rateLimits/read` result (legacy view; `rateLimitsByLimitId` absent):

```json
{"rateLimits": {"limitId": "codex",
  "primary": {"usedPercent": 18, "windowDurationMins": 10080, "resetsAt": 1790122652},
  "secondary": null, "planType": "plus", "rateLimitReachedType": null}}
```

Normalized (`usage_normalize.py --provider openai --account-alias rayo-codex`):

| Field | Value |
|---|---|
| plan / bucket | plus / codex |
| window 1 | role **7d** (from 10080 min, although the slot is `primary`), used 18 %, remaining **82 %**, resets 2026-09-23T00:17:32Z |
| window 2 | slot `secondary` = null → availability **unavailable**, remaining **unknown** |
| tokens left | not derivable |
| verdict (`usage_decide.py --reserve 15`) | `ok_with_unknown`: eligible, with one window not reported |

Claude's account in the same moment: not read → `unknown`. Two eligible accounts are then chosen between by task fit, not by 82 % versus anything.

## Acceptance checks (covered by `tests/run_tests.sh`)

- Reader works through the app-server handshake, sends only the three allowed methods, exits 2 without a binary and 3 on timeout.
- Null, absent and non-numeric percentages stay unknown; zero is a different value.
- The real example yields 7d / 82 % / secondary unknown → `ok_with_unknown`.
- A weekly window at 100 % blocks even with the 5-hour window at 40 %.
- Another account's records (ledger) never feed a decision for this account.
- A stale reading (older than the max age, or past its reset) yields `unknown`.
- Both providers eligible → no ranking by percentage.
- Session tokens and cost are recorded as separate dimensions with their own unit.
