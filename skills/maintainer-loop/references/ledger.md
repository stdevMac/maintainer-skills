# Ledger

One JSON object per line in `<state>/ledger.jsonl`, appended through `scripts/ledger.sh <owner/repo>
append '<json>'` (adds `ts`, serializes writers with `flock`). Never edit or delete lines; a correction
is a new event.

## Fields

| Field | Meaning |
|---|---|
| `ts` | UTC ISO 8601, added by the script |
| `event` | One of the events below |
| `number` | Issue or PR number |
| `kind` | `issue` or `pr` |
| `round` | Round number from `next-round` |
| `base` | Base branch SHA the event refers to, when relevant |
| `evidence` | Path(s) under `<state>/evidence/` |
| `url` | URL of a public write |
| `why` | One-line reason for a decision |

## Events

| Event | Extra fields |
|---|---|
| `selected` | `query` |
| `triaged` | `verdict`, `brief` (path, for needs_fix) |
| `repro` | `result` (`reproduced`, `fixed_on_head`, `cannot_repro`, `inconclusive`), `level` |
| `plan_refuted` / `fix_refuted` | `why` |
| `branch_pushed` | `branch`, `sha`, `verified` (signature) |
| `env_created` / `env_destroyed` | `run_id`, `where`, `verified` (inventory by label is empty) |
| `pr_intent` → `pr_opened` | `pr`, `url` |
| `comment_intent` → `commented` | `url` |
| `close_intent` → `closed` | `reason`, `url` |
| `review_intent` → `review_posted` | `pr`, `head`, `state`, `url` |
| `rerun` | `run_id`, `why` |
| `merged` | `head`, `merge_commit`, `method` (written by `merge-when-green.sh`; `number` is the PR) |
| `needs_user` | `why`, `options` |
| `abandon` | `why`, `patch` (saved work) |
| `terminal` | `state`, `retry_after` (optional) |
| `reopen` | `why` |

Terminal states: `done`, `in_review`, `needs_user`, `needs_env`, `cannot_repro`, `keep_open`,
`owned_elsewhere`, `security_private`. A terminal event with `retry_after` in the future keeps the
number on the skip list; `cannot_repro` and `needs_env` default to 30 days.

`security_private` items carry no detail in the ledger; details live in `<state>/private/`.

## Rules

- Write the intent event **before** any external action and the result event right after, so a crash
  between them is visible and the next session reconciles by reading GitHub, not by retrying blindly.
- Copy verdicts and key numbers from remote runs into the ledger immediately; CI artifacts expire.
- The round report is generated from the ledger, not from memory.
