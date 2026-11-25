# Maintainer profile: `<owner>/<repo>`

Verified: `<UTC date>` at `<default-branch sha>` by `<agent / model>`.
Facts file: `<owner>__<repo>.facts.md` (output of `detect-project.sh --gh`).

Replace every `<...>`. Delete a row only when it cannot apply to this project; write `none` when the
answer is "nothing". Mark commands you did not run as `[unverified]`.

## 1. Identity

| Item | Value |
|---|---|
| Repository | `<owner>/<repo>`, default branch `<main>` |
| Local clone | `<path>` (read-only for agents; work happens in worktrees) |
| Remotes | `origin` = `<url>`; never push to: `<remote names or none>` |
| Account | `<gh login>`, permission `<read / triage / write / maintain / admin>` |
| Clone quirks | `<shallow? submodules? LFS? sparse?>` |

## 2. Read first

The project's own rules win over these skills. Read, in this order:

- `<AGENTS.md / CONTRIBUTING / rule dirs>`: `<one line on what each governs>`
- PR template: `<path>`; required sections: `<list>`
- Security policy: `<SECURITY.md>`; private reporting path: `<advisory / email / private repo>`

Behavior-changing rules, summarized: `<test placement, forbidden directories, commit format, minimal-diff
rules, comment style, platform assumptions>`.

## 3. Environment setup

```bash
<toolchain install into a user dir, e.g. dotnet-install.sh --version X --install-dir ~/.dotnet>
<dependency restore>
<submodules needed only by: ...>
```

| Need | How to get it locally | Notes |
|---|---|---|
| Toolchain `<name version>` | `<cmd>` | pinned in `<file>` |
| Service `<db / docker / emulator>` | `<cmd or none>` | `<allowed on the workstation?>` |
| Secrets for tests | `<env var names, where they come from>` | never commit |
| Test data / fixtures | `<submodule / download / generate>` | `<size>` |

Fresh worktree recipe: `<git worktree add ... ; restore ; anything else a new tree needs>`.

## 4. L0: build and static checks

| Check | Command | Time | Disk | CI equivalent |
|---|---|---|---|---|
| Build | `<cmd>` | `<min>` | `<GB>` | `<workflow>` |
| Lint / analyzers | `<cmd>` | | | |
| Format | `<cmd that fails on diff>` | | | |
| Type check / docs / spelling | `<cmd>` | | | |

A clean result looks like: `<exact line, e.g. "0 Warning(s) 0 Error(s)">`.

## 5. L1-L3: tests

| Level | Scope | Command | Time | Where |
|---|---|---|---|---|
| L1 | One test by name | `<cmd with filter>` | | local |
| L2 | One project / package in full | `<cmd>` | | local |
| L2 | Everything affected by a change in `<dir>` | `<cmd or rule>` | | local |
| L3 | Integration / e2e | `<cmd>` | | `<local / ci-dispatch>` |

Test framework traps: `<filters that select zero tests and look green, port conflicts, parallel runs that
collide, tests needing env vars>`. A run counts only when the output shows a non-zero executed count.

## 6. L4-L5: live verification

How the software runs for real: `<binary / image / service / CLI / library consumer>`.

| Level | Environment | How to start | How to drive it | How to observe | Teardown | Cost | Approval |
|---|---|---|---|---|---|---|---|
| L4 | `<local devnet / docker compose / emulator / sample app>` | `<cmd>` | `<requests, CLI script, browser flow>` | `<logs, metrics>` | `<cmd>` | | `<no / yes>` |
| L4 | `<CI workflow_dispatch on a branch>` | `gh workflow run <file> --ref <branch> -f ...` | | run logs, artifacts | n/a | `<runner minutes>` | |
| L5 | `<soak / staging / differential vs reference>` | | | | | | |

Gaps: `<levels that are unavailable and why; tracked issue>`.

## 7. CI

| Workflow | Trigger | Covers | Required | Typical time |
|---|---|---|---|---|
| `<file>` | `<pull_request>` | `<build / unit / e2e / lint>` | `<yes/no>` | |

Required checks on `<default branch>`: `<count and names>`. Extra merge blockers that are not required
checks: `<e.g. a guard workflow, a label>`. Reviews skip what CI enforces: `<list>`.

## 8. Known flakes and false positives

| Symptom | Where | Cause | Action |
|---|---|---|---|
| `<test or job>` | `<workflow / shard>` | `<timing, shared port, infra>` | `<rerun once alone / ignore / fix tracked in #n>` |

## 9. Resources and concurrency

| Resource | Limit | Why |
|---|---|---|
| Disk per built worktree | `<GB>`; stop below `<GB>` free | |
| Parallel builds/tests | `<n>`; lock: `<flock path or none>` | |
| Ports / singletons | `<fixed ports, global caches>` | |
| Cleanup | `<how to remove worktrees, containers, VMs>` | |

Dispatch budget per round: `<maximum CI runs, estimated CI minutes, VM runs>`. No dispatch without a
configured budget; paid or VM runs also require explicit approval unless a stricter policy forbids them.

## 10. Policy

| Action | Allowed without asking | Notes |
|---|---|---|
| Build, test, run anything in an owned worktree or owned env | yes | |
| Create cloud resources / VMs / paid CI runs | `<no>` | caps: `<n per day>` |
| Push a branch to `<remote>` | `<yes / no>` | never force-push a shared branch |
| Open a draft PR | `<yes / no>` | |
| Comment on issues / PRs | `<yes / no>` | |
| Submit reviews | `<APPROVE+COMMENT / COMMENT only / no>` | never REQUEST_CHANGES unless allowed |
| Close issues | `<no / with evidence>` | |
| Merge | `<no / via gate only>` | method `<squash>` |
| Rerun CI | `<once per run, with evidence>` | |
| Labels, reviewers, titles | `<no>` | |

Identity: `<git user, signing key / method, how to verify signed commits>`.
Attribution line for public text: `<exact line or none>`.
Security-sensitive findings go to: `<private path>`; never to public issues, PRs or comments.
Never touch: `<machines, branches, directories, other people's PRs>`.

## 11. Writing conventions

Commit format: `<conventional commits?>`. PR title: `<format>`. Body: `<template>`. Tone:
`<plain, no emoji, no @-mentions, ...>`. Issue references: `<Fixes #n closes on merge>`.

## 12. Gotchas

Dated, one line each, with the incident that taught it:

- `<YYYY-MM-DD>`: `<what happened> -> <what to do>`

## Actions

Public writes are optional. `off` skips the action; `draft` saves the payload locally (default);
`ask` requires explicit approval of that payload; `auto` runs only when every applicable project and
skill gate passes. `MAINTAINER_ACTIONS` overrides this table for one session. Notes only narrow a mode.

| Action | Mode | Notes |
|---|---|---|
| push_branch | draft | |
| pr_open | draft | Includes PR body edits |
| pr_ready | draft | |
| issue_comment | draft | |
| issue_close | draft | |
| issue_create | draft | |
| labels | draft | Includes titles, assignees and reviewers |
| pr_review | draft | |
| thread_reply | draft | Post a review-thread reply |
| thread_resolve | draft | Resolve a review thread; independent of permission to reply |
| pr_merge | draft | Never bypass the merge gate |
| ci_dispatch | draft | Budget and resource approvals still apply |
| ci_rerun | draft | |
