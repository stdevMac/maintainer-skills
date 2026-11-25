---
name: maintainer-loop
description: Orchestrate the whole maintenance loop over many issues and PRs - triage, fix, review, merge - in rounds, with parallel subagents, a durable ledger, resource caps, independent verification of every agent claim, and the orchestrator as the only identity that writes publicly. Resumable from the ledger in a new session. Use when the user says "work through the issues", "run the maintainer loop", "sweep issues and PRs", "keep going", "resume the sweep", or gives a batch of issues or PRs to handle end to end.
---

# Maintainer loop

Arguments: `--issues "<gh search>"` (default `is:open is:issue` oldest first), `--prs "<gh search>"`,
`--mode triage|fix|review|merge|all` (default `all`), `--batch N` (default 8), `--max-agents N`
(default from the profile, else 4), `--dry-run` (no public writes, no pushes), `--resume`.

This skill composes project-profile, triage-issue, fix-issue, review-pr and merge-pr. Read
[references/safety.md](references/safety.md) before the first action of every session; it applies to
you and is pasted into every subagent brief.

## Roles

- **Orchestrator (you):** selects work, writes briefs, launches subagents, verifies their reports, keeps
  the ledger, and makes **every** public write (issues, comments, closes, PRs, reviews, merges).
- **Subagents** (role prompts in this repo's `agents/`; templates in
  [references/briefs.md](references/briefs.md)): triager, fixer, refuter, pr-reviewer. They may build,
  test and run approved owned environments, but never push, dispatch remotely or post on GitHub.
  They start blank: give them the full rules text and the brief, not file names to look up.

## State

`<state>` = `${MAINTAINER_STATE:-${XDG_STATE_HOME:-~/.local/state}/maintainer-skills}/<owner>/<repo>/`:
`ledger.jsonl` (source of truth, via `scripts/ledger.sh`), `briefs/`, `evidence/<n>/`, `prs/<n>/`,
`reviews/<n>/`, `drafts/`, `rounds/round-NNN.md`, `private/` (security items; never shared). Schema and
events: [references/ledger.md](references/ledger.md). Chat memory is not state.

## Session start

1. `gh auth status`; confirm the account and git identity match the profile. Fetch the clone.
2. Load the profile (project-profile skill lookup). Missing, or a command in it fails: run the
   project-profile skill first.
   Resolve modes with the project-profile skill's `scripts/action-mode.sh --list --repo <repo>`.
   Include applicable modes and notes in each brief. An invalid configuration stops public actions.
3. `scripts/ledger.sh <repo> status`; read the last round report and its retrospective.
4. Inventory what you own: `worktree.sh list` (fix-issue skill), environments and cloud resources by
   your run label, open PRs by your account. Clean up only what is provably yours and idle.
5. Check resources against the profile (disk, parallel builds, singletons).

## Round

1. **Select.** `round=$(scripts/ledger.sh <repo> next-round)`. Pick `--batch` issues from the query,
   skipping `scripts/ledger.sh <repo> skiplist`, issues with an open PR (they go to review), and
   anything security-sensitive (private route). Ledger `selected` for each.
2. **Triage** in parallel (triager subagents, up to `--max-agents`): each returns a verdict, evidence
   and, for `needs_fix`, a Task Brief file (triage-issue skill).
3. **Refute the plan** for each `needs_fix` before spending builds: one refuter with the brief. A
   refuted plan goes back to triage with the refutation.
4. **Fix** (fixer subagents, capped by the profile's build and disk limits): each follows the fix-issue
   skill and returns branch, head SHA, ladder levels with evidence paths, and a PR body file.
5. **Refute the fix:** 2 or 3 refuters for critical areas or diffs over about 150 lines, 1 otherwise.
6. **Verify every report yourself** before acting on it:
   - the branch head equals the reported SHA, and signatures verify if the profile requires them;
   - every number in the report appears in an evidence log (`grep` the log, do not trust the summary);
   - read the production diff and the callers of changed behavior;
   - the PR body's claims match the diff ("no new public API", counts, "fails without the fix").
   Agents misreport. An unverified claim is not published.
7. **Publish** only per the resolved mode for each action and within policy and caps. `off`: report
   the skipped action; `draft`: save the exact payload locally; `ask`: get approval for that payload;
   `auto`: proceed after gates. Each write: ledger intent, write, ledger result with the URL.
   `--dry-run` suppresses all writes outside the sandbox, including pushes and dispatches.
8. **PR maintenance:** run the merge-pr skill over open PRs (yours and the round's), and the review-pr
   skill over PRs that the round routed to review.
9. **Close the round:** clean up worktrees and environments (verify teardown), write
   `rounds/round-NNN.md` (counts by verdict, PRs, closes, reviews, merges, needs_user, time per item),
   then a short retrospective: which verdicts were overturned and why, wasted steps, caps that blocked or
   were too loose, what review caught that local gates missed. Add durable lessons to the profile's
   Gotchas and flake table.
10. Report to the user in about ten lines, then start the next round unless a stop condition holds.

## Caps (defaults; the profile overrides)

| Resource | Default |
|---|---|
| Parallel subagents | 4 |
| Parallel heavy builds/tests | per profile lock |
| Built worktrees | per profile disk limits |
| Fix attempts per issue | 3, or 2 hours |
| Public writes | 15 per hour; one comment per issue per 30 days unless new evidence |
| Re-review requests per PR | 3 |
| CI reruns | 1 per run, with evidence |
| Paid or VM-creating runs | 0 without approval |
| CI dispatches | 0 unless the profile sets a budget |

Before dispatch, check `ci_dispatch`, then `ledger.sh <repo> dispatch-usage --round <n>`. Reject runs
without a credible estimate or whose projected totals exceed any cap. Serialize dispatch decisions for
the repo (hold a separate lock from budget check through receipt append). Write the `dispatch` event
with its run ID and estimated minutes; reconcile uncertain outcomes before dispatching again.

## Stop and ask the user

Security-sensitive findings and their routing; closing an issue authored by a maintainer or with a
recent maintainer comment; superseding someone else's PR; any force-push; deleting anything not provably
yours; spending money or creating shared resources beyond policy; a design decision with several valid
answers; a rule or cap change. Everything else: decide, log the decision and the reason in the ledger,
keep going.

## Stop condition

Every selected item is terminal in the ledger (`done`, `in_review`, `needs_user`, `needs_env`,
`cannot_repro`, `keep_open`, `security_private`, `owned_elsewhere`) or the queue is empty. Write
`FINAL.md` in `<state>` with what changed, links, and open decisions.
