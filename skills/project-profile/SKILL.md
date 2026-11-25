---
name: project-profile
description: Build or refresh the maintainer profile of a repository, the one file every other maintainer skill reads for project context. It records rules to read, toolchain and environment setup, build, lint and test commands, e2e and live-run environments (the test ladder), CI and required checks, known flakes, resource limits, and the autonomy policy (what an agent may do without asking). Commands are run and timed, not guessed. Use before the first triage, fix, review or merge on a new repository, when a command in the profile fails, or when the user says "profile this repo", "learn this project", "set up the maintainer profile".
---

# Project profile

The profile is the only project-specific input to the triage-issue, fix-issue, review-pr, merge-pr and
maintainer-loop skills. A good profile lets an agent with no prior knowledge reproduce a bug, prove a
fix at the highest reachable test level, and know which actions need a human.

Arguments: a repository (`owner/repo`, URL or local path; default: the current checkout) and optionally
`--refresh`.

## Lookup order

1. `$MAINTAINER_PROFILE`
2. `<repo>/.agents/maintainer-profile.md`
3. `<repo>/MAINTAINER_PROFILE.md`
4. `${XDG_CONFIG_HOME:-~/.config}/maintainer-skills/profiles/<owner>__<repo>.md`

Found one: refresh mode (steps 2, 5, 6 and 9 only, plus anything a failing command points at). None:
build one.

## Steps

1. **Identity.** Resolve `owner/repo`, the local clone (clone it if missing, read-only), the default
   branch, and every remote. Mark remotes that must never receive pushes (security mirrors, release
   remotes). Record the authenticated `gh` account and its permission on the repo.
2. **Facts.** Run `scripts/detect-project.sh <clone> --gh`. It is read-only. Keep its output next to the
   profile as `<owner>__<repo>.facts.md` for the next refresh.
   Before reusing stored facts, run `scripts/detect-project.sh --check <facts-file> <clone>`.
   Read a nonempty diff and refresh the affected profile sections; never silently grant permissions.
   Resolve write modes with `scripts/action-mode.sh --list --repo <owner/repo>`; only a personal
   profile or a profile explicitly selected by the user contributes `## Actions` modes.
3. **Project rules.** Read every instruction file the facts list (`AGENTS.md`, `CLAUDE.md`,
   `CONTRIBUTING`, rule directories, PR template, `CODEOWNERS`, `SECURITY.md`). The profile links to them
   and summarizes only what changes agent behavior: required test style, forbidden edits, commit format,
   PR template sections, security reporting path. Never paraphrase a rule into something weaker.
4. **History.** Learn how maintainers actually work from the last 20 merged PRs and 20 closed issues:
   PR size, title format, how bugs are verified, which checks are required
   (`gh pr checks <n> --required`), merge method, how long reviews take, who reviews what. This is where
   implicit rules show up.
5. **Environment.** Install the pinned toolchain into a user directory if it is missing. Restore
   dependencies. Initialize submodules only where tests need them, and note their size. Record services a
   test needs (databases, Docker, emulators, keys) and how to get each one locally without touching shared
   infrastructure.
6. **Test ladder.** Fill levels L0 to L5 from
   [references/profile-template.md](references/profile-template.md). **Run** the L0 command and the fastest
   L1/L2 test project once and record wall time, disk use and the exact pass/fail line. For L3 to L5,
   find how the project runs for real: the binary, container image or service, the smallest realistic
   environment (local devnet, sample dataset, emulator, staging, CI workflow with `workflow_dispatch`),
   how to drive it the way a user does, how to observe it (logs, metrics, traces) and how to tear it down.
   Mark each level `local`, `ci-dispatch`, `remote-env` or `unavailable`, with its cost and whether it
   needs approval. An unreachable level is recorded with the reason, never silently skipped.
7. **CI map.** For each workflow: trigger, what it covers, required or not, typical duration. Reviews
   skip what CI already enforces, so record that list. Collect flake candidates from failed default-branch
   runs (the facts list the last 15) and from rerun-then-pass patterns.
8. **Policy.** Fill the policy table in the template. Ask the user only for rows the repo and history
   cannot answer (identity, attribution line, who may merge, publication rights). Until answered, the
   conservative default applies: draft everything, publish nothing, merge nothing.
9. **Write and verify.** Write the profile from the template. Every command is copy-pasteable from the
   clone root. Mark any command you did not run as `[unverified]`. Stamp `Verified: <UTC date> at <sha>`.
   Store it by the lookup order; committing it to the repository needs the project's normal PR process.

## Rules

- Running the project's code is expected here; that is how commands get verified. Run it in the clone
  or an owned worktree, never against shared machines or production data.
- Do not record secrets. Record where a secret comes from (env var name, vault path), not its value.
- A profile is a set of facts with dates. When a fact changes (toolchain bump, renamed check, a blocker
  fixed), update the line and its date instead of appending a contradiction.
- Keep it under about 400 lines. Link to the project's own docs for detail.

## Output

The profile path, the levels reachable for this repo (for example `L0-L2 local, L3 ci-dispatch, L4
remote-env with approval, L5 unavailable`), the open policy questions, and every `[unverified]` command.
