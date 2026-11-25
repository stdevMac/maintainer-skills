# Ledger

One JSON object per line in `<state>/ledger.jsonl`, appended through `scripts/ledger.sh <owner/repo>
append '<json>'` (adds `ts`, serializes writers with `flock`). Never edit or delete lines; a correction
is a new event.

One repository has one ledger. Every tool that works on the repository (this loop, the merge gate, older
project-specific scripts) appends to the same file, because two ledgers mean two skip lists and two
sessions working the same issue. A project with an older state directory keeps it by making
`<state root>/<owner>/<repo>` a symlink to it: the file and its `.ledger.lock` are then shared.

## Fields

| Field | Meaning |
|---|---|
| `ts` | UTC ISO 8601, added by the script |
| `event` | One of the events below (a string; `append` refuses an object without one) |
| `number` | Issue or PR number. Older ledgers use `issue`; the script reads `issue` when `number` is absent |
| `kind` | `issue` or `pr` (older ledgers may hold other text here; the script does not read it) |
| `round` | Round number from `next-round` |
| `repo` | Only on events about another repository (an issue filed upstream); they are left out of per-number views |
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
| `dispatch_intent` → `dispatch` | `workflow`, `run_id` (result only), `ref`, `est_minutes`, `cost_class` (`ci` or `vm`) |
| `drafted` | `action` (action name), `mode` (`draft`, `ask`, `off`), `path` (the draft under `<state>/drafts/`) |
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

## Dispatch budget

A dispatch is any workflow run you start on purpose (`workflow_dispatch`, a manual test environment, a
paid run); a rerun of an existing run is a `rerun`, capped separately. `ledger.sh <owner/repo>
dispatch-usage [--round N] [--since ISO8601]` sums the `dispatch` events in scope:

```json
{"scope":{"round":12},"runs":3,"ci_runs":3,"vm_runs":0,"ci_minutes":95,"vm_minutes":0,
 "runs_without_estimate":1,"by_class":{"ci":3},"by_workflow":{"hive-tests":2,"unknown":1}}
```

- `cost_class` is `ci` (runner minutes) or `vm` (the run creates machines or other billed resources). A
  dispatch without `cost_class` counts as `ci`, so every VM run must say `vm`.
- `est_minutes` is your estimate before the run (the profile's typical time for that workflow). Runs
  without one are counted in `runs_without_estimate`, not guessed.
- Older ledgers name dispatches `<something>_dispatch` or `<something>_dispatched` (for example
  `retest_dispatch`); they count as dispatches. `<something>_dispatch_intent` and `_pending` do not.

Before every dispatch, compare the usage for the current round plus the planned run with the profile's
Dispatch budget (maintainer-loop SKILL.md, Caps).

## Rules

- Write the intent event **before** any external action and the result event right after, so a crash
  between them is visible and the next session reconciles by reading GitHub, not by retrying blindly.
- An action whose mode is not `auto` (and `ask` without approval) gets a `drafted` event instead of the
  intent/result pair.
- Copy verdicts and key numbers from remote runs into the ledger immediately; CI artifacts expire.
- The round report is generated from the ledger, not from memory.
