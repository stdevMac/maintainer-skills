# CI triage

## Read before acting

```bash
gh pr checks <n> -R <owner/repo>                                # all checks with links
gh run view <run-id> -R <owner/repo> --log-failed | tail -200   # failing step output
gh api repos/<owner/repo>/check-runs/<job-id>/annotations       # compiler and test annotations
gh run view <run-id> -R <owner/repo> --json attempt,conclusion,jobs
```

Find the first real error, not the last line. Note the job, attempt number and the head SHA it ran on.

## Classify

| Class | Evidence | Action |
|---|---|---|
| Ours | Build, lint or test failure in code or tests the PR touches, or in their consumers | Fix it locally, prove it with the same command, push |
| Known flake | Listed in the profile's flake table, or the same test fails on the base branch too | One `gh run rerun <run-id> --failed` on attempt 1, logged with the evidence |
| Infrastructure | Runner lost, network or registry errors, disk full on the runner, a timeout while sibling shards finished fast | One rerun, logged |
| Cancelled | Superseded by a newer push or a concurrency group | Nothing; look at the newer run |
| Guard or policy | A check that needs a person (code-owner approval, label, CLA) | Never bypass; ask the owner in the request message |
| Unknown | None of the above | Reproduce locally on the PR head; if it does not reproduce, treat as a flake candidate and add it to the profile once confirmed |

Rules:

- One rerun per run, on attempt 1, and only with evidence that the failure is unrelated to the diff. A
  second failure is real until proven otherwise.
- A new flake you confirm (fails on base too, passes alone) goes into the profile's flake table with the
  date and run IDs, and gets an issue if the project tracks flakes.
- "All green" means every required check passed on the current head. A rollup status can be stale after
  reruns; trust per-check states from `scripts/pr-state.sh`.
- Non-required checks still matter when they cover the changed area (for example an e2e suite); read them.
