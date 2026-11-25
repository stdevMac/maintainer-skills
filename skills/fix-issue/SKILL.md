---
name: fix-issue
description: Fix an issue from a Task Brief, proving it at the highest reachable level of the test ladder. Prepares an isolated worktree and environment, writes the regression test first and shows it failing for the right reason, makes the smallest root-cause fix, proves the test fails without the fix, runs static checks, full affected suites, integration and live runs (real binary or service, devnet, differential baseline-vs-fix), self-reviews adversarially, then commits, pushes and opens a PR with evidence-backed testing notes. Use when the user says "fix #N", "implement the fix", "make a PR for this", or when triage-issue produced a needs_fix brief.
---

# Fix an issue

Arguments: an issue number, URL or Task Brief path; optional `--no-pr`, `--draft` (default), `--ready`.

Inputs, in order: the Task Brief (`<state>/briefs/<n>.md`; no brief: run the triage-issue skill first),
the project profile, the project's own rules (the brief and profile list them; read them from disk now,
they change). Paths: `<state>` is defined in the maintainer-loop skill.

## You have room to work

Inside the sandbox, go as far as the problem needs. Build anything, run any test, write throwaway probe
harnesses, add temporary logging, run the real binary, start local services and multi-node setups the
profile allows, fuzz, bisect, compare against a reference implementation, run baseline and fixed builds
side by side. The sandbox is: your own worktree, your own processes, containers or environments you
created and labelled, and `<state>/evidence/<n>/`. The limits are only at its edge (see
[references/environment.md](references/environment.md) and the profile Policy): nothing shared,
nothing public and nothing irreversible without the policy allowing it.

## Steps

1. **Prepare the environment** ([references/environment.md](references/environment.md)).
   `scripts/worktree.sh new <clone> <n>-<slug> --base origin/<default>` on a freshly fetched base. Check
   disk against the profile limits. Install the pinned toolchain, restore dependencies, initialize only
   the submodules the tests need, start the services the brief lists. Build once (L0) before changing
   anything, so later failures are yours.
2. **Reproduce first.** Write the regression test the brief describes, in the file and style the project
   uses. Run it on the unmodified base: it must fail, and the failure must be the bug (an assertion on the
   wrong value), not a compile error or a setup problem. Save the output to
   `<state>/evidence/<n>/fail-before.log`. If the bug only shows live, write the live scenario as a script
   first and record it failing.
3. **Fix the root cause.** Smallest diff that fixes the cause in the brief. Prefer removing code, then
   adding code without new public surface, then modifying existing code. Read every caller of anything
   whose behavior changes. No drive-by edits, no reformatting, no rewording of unrelated comments. If the
   root cause turns out different from the brief, update the brief and say so.
4. **Prove it** ([references/test-ladder.md](references/test-ladder.md)). Climb as high as the profile
   allows and save every log under `<state>/evidence/<n>/`:
   - L1: the new test passes. Then `scripts/fail-before.sh --base <base> -- <test command>` restores the
     base versions of the production files, runs the test, expects failure, and puts the fix back.
   - L0: build, analyzers, formatter on the touched files: clean.
   - L2: every affected test project or package in full, not just the filter.
   - L3: integration or e2e suites for the subsystem, locally or through the CI dispatch the profile names.
   - L4/L5: the live scenario from the brief, on the baseline build and on the fixed build. The bug
     appears on baseline and is gone on the fix. Observe logs and metrics, not just exit codes.
   Record the levels you could not reach and why. A run counts only with a non-zero executed count.
5. **Attack it.** Review your own diff with the review-pr skill's checklist, or brief 2 or 3 `refuter`
   subagents with the lenses in the triage-issue skill's `references/verdicts.md`. Did the fix remove an
   existing guard's purpose? Can a retry, restart, concurrent caller or partial failure still reach the
   bad state? Does every caller still get what it expects? A refuter that wins sends you back to step 3.
6. **Commit and push.** Identity, signing and message format from the profile. Never `--no-verify`,
   never rewrite a pushed branch, never push to a remote the profile forbids. Verify the pushed head
   equals your local head and, if the profile requires signed commits, that GitHub reports them verified.
7. **Open the PR** when policy allows ([references/pr-body.md](references/pr-body.md)): project template,
   closing keyword, real commands and counts from the evidence logs, the live-run IDs, levels not reached,
   attribution line. Draft unless the user passed `--ready`. Then hand the PR to the merge-pr skill for
   CI, review threads and merge, or stop if policy forbids.
8. **Clean up.** Tear down every environment you started and check nothing labelled with your run ID is
   left. Remove the worktree with `scripts/worktree.sh remove` once the branch is pushed; keep evidence.

## Budget and escalation

Stop and report instead of pushing on when: the brief's budget is spent (default 3 fix attempts or
2 hours); the fix needs a design decision, a new public API, a breaking change or a change in a critical
area the profile marks for approval; the same reviewer finding returns twice; or an environment you need
is not reachable. Report what you tried, the evidence, and the decision needed.

## Output

Branch and head SHA, PR URL (or the drafted body path), the ladder levels reached with evidence paths,
what was not verified and why, cleanup status.
