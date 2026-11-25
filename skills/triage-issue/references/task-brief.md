# Task Brief

The Task Brief is the contract between triage and fix. The fix-issue skill, or a subagent with no
other context, must be able to execute it. Save it as `<state>/briefs/<issue>.md`
(`<state>` is defined in the maintainer-loop skill) and log its path in the ledger.

Fill every section. Write `none` or `unknown` instead of deleting a section, so the reader knows it was
considered.

```markdown
# Task Brief: <owner/repo>#<n> <title>

Base: `<branch>` at `<full sha>` (fetched <UTC time>). Issue: <url>. Triage verdict: needs_fix.

## Context
<Two to five sentences: what the software does in this area, who hits the bug, why it matters.>
Project rules to read before editing: <paths from the profile, plus any area-specific rule>.

## Problem
Observed: <exact behavior, with an output or log excerpt>.
Expected: <exact behavior, with the source of truth: spec, docs, reference implementation file:line at a tag, previous version>.

## Verified facts
- <fact> (<how verified: command, SHA, link>)
Unverified or wrong claims in the report:
- <claim> (<why it does not hold or could not be checked>)

## Reproduction
Level: <L1 test / script / L3 / L4>. Ran on: <sha, environment>.
Steps:
    <exact commands, copy-pasteable from the clone root>
Result: <excerpt showing the bug>.
Evidence: <path to saved log>.

## Root cause
<file:line at the base sha, what is wrong and why>. Confidence: <high / medium / low>.
Introduced by: <commit / PR, or unknown>. Intent of that change: <what it was trying to do>.
Alternative explanations ruled out: <list with the evidence that ruled each out>.

## Fix direction
Preferred: <approach>, because <reason>.
Alternatives: <approach: trade-off>.
Constraints: <minimal diff, no new public API, plugin-style change, compatibility, performance budget>.
Do not touch: <files, behaviors, other open PRs' areas>.

## Test plan
Regression test: <file to add it to, case(s), what it asserts>. It must fail on the base sha for the
reason in Root cause; capture that output.
L2 suites to run in full: <projects/packages>.
L3/L4 (live) plan: <environment from the profile, setup steps, how to drive the scenario, the success
signal, what to observe in logs/metrics, teardown>. If unreachable: <why, and what evidence replaces it>.
Edge cases to cover: <boundaries, concurrency, restart, empty and maximum inputs, error paths>.

## Environment
<toolchain, submodules, services, data, ports, approximate disk and time>.

## Risk
Area: <critical area per the profile, or none>. Blast radius: <callers, users, config, persisted data>.
Compatibility: <API, config, storage format, wire format>.

## Done when
- <observable criteria, e.g. regression test fails before and passes after; suites X, Y green; live
  scenario Z shows <signal>; PR open with template filled>

## Publication
Closing keyword: `Fixes #<n>` (or `Refs #<n>` when it only partly fixes it).
Related issues/PRs: <list>. Notes for the PR body or release notes: <user-visible change?>.

## Budget
<iterations or hours before escalating, e.g. 3 fix attempts or 2 hours>.
```
