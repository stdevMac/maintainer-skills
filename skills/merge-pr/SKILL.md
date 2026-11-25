---
name: merge-pr
description: Drive a pull request from open to merged without cutting corners. Snapshots readiness, closes every review thread by fixing the point or answering it with evidence, triages CI failures from their logs (fix real ones, one justified rerun for flakes or infra), resolves conflicts by merging the base, marks ready, asks humans only for what only they can give, and merges through a hard gate - exact head, approved, required checks green, zero unresolved threads, zero changes requested. Use when the user says "merge PR N", "get this merged", "what is blocking this PR", "answer the review comments", "sweep my open PRs".
---

# Merge a pull request

Arguments: one or more PR numbers, or `--author <login>` for all open PRs of an author; optional
`--post` (publish replies), `--merge` (allow merging), `--watch`.

Every pass ends with each PR either merged or carrying a named blocker that only a human can clear (an
approval, a code-owner review, a design decision). A PR never merges with an open review thread.

Load the project profile. Its Policy says whether you may push, post replies, resolve threads, rerun CI
and merge; the arguments can only narrow it. Its CI section names extra merge blockers and known flakes.

## Steps

1. **Snapshot.** `scripts/pr-state.sh <owner/repo> <n>` for each PR (read-only): head, mergeability,
   review decision, approvals on the current head, required and failing checks, unresolved threads with
   their last author. Save `--json` output under `<state>/prs/<n>/`.
2. **Ownership.** Whose branch is it? If another person or agent session pushed in the profile's quiet
   window (default 2 hours), do not push to it; draft replies and report. Before any push, check
   `git ls-remote origin refs/heads/<branch>` equals the head you started from, and again after pushing.
3. **Review threads** ([references/threads.md](references/threads.md)). Every unresolved thread, including
   bot and "nit" or "optional" ones, gets one of: a fix (commit, then a reply naming it), or a reply that
   answers with evidence (code at file:line, a test, a reference implementation). Verify the reviewer's
   claim with a test before deciding; claims that pin down concrete behavior are often right. Drafts go
   to `<state>/prs/<n>/reply-<file>-<line>-<reviewer>.md`; `scripts/reply-and-resolve.sh <dir>` previews
   them and posts them with `--post` when allowed. Many threads across PRs: one subagent per PR, using
   the fixer role and the fix-issue skill's verification steps.
4. **CI** ([references/ci-triage.md](references/ci-triage.md)). Read the failing job's log before
   anything else. Ours: fix it. Known flake or infrastructure, with evidence: one rerun of the failed jobs,
   logged. Never bypass a guard check; ask its owner.
5. **Conflicts.** Merge the base into the branch (no rebase or force-push on a pushed branch unless the
   profile says the project rebases and the branch is yours). Resolve preserving the PR's intent. For a
   semantic conflict (both sides changed the same invariant or data structure), list every path that
   depends on it and run the full affected test projects. If the base already made the PR redundant
   (empty diff), report it as superseded instead of pushing.
6. **Verification for every push.** Same bar as the fix-issue skill: affected test projects in full, new
   tests proven with a mutant or fail-before, static checks clean, PR body updated so its claims match
   the new head.
7. **Readiness.** Draft PRs become ready when CI is green and policy allows. PRs that need human approval
   go into a short request message (the ask first, full URLs, the code owner for guarded areas).
8. **Merge gate.** `scripts/merge-when-green.sh <owner/repo> <n> <full head sha>` evaluates every gate
   and reports. With policy and `--merge`: add `--merge`, plus `--block-check` for each extra blocker in
   the profile. For unattended waiting add `--watch` and run it detached
   (`setsid nohup ... >> <state>/prs/<n>/watch.log 2>&1 < /dev/null &`). Never merge by hand around the
   gate. After you push again, stop the old watcher and start one on the new head.
9. **After the merge.** Confirm the merge commit, that linked issues closed (or close them per policy with
   the merge reference), and that post-merge CI on the base branch is not newly red because of it. Delete
   the branch if the project does. Remove worktrees. Record the merge in the ledger.

## Output

Conclusion first: what merged (short SHAs). Then a table `PR | state | blocker | next action`, one line
per thread handled (fixed / declined / answered, and why), CI reruns with their evidence, drafts not yet
posted with the exact command to post them, and the decisions the user must make.
