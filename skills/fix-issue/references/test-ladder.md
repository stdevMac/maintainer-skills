# The test ladder

| Level | What | Proves | Typical evidence |
|---|---|---|---|
| L0 | Build, analyzers, type check, format | Compiles, follows the rules CI enforces | "0 warnings 0 errors", empty format diff |
| L1 | Regression test: fails before, passes after | The bug is caught and fixed | fail-before log, pass log |
| L2 | Affected test projects or packages in full | Nothing nearby broke | executed/passed/failed/skipped counts |
| L3 | Integration or e2e suites of the subsystem | Components still work together | suite counts, CI run ID |
| L4 | Live: the real build, a realistic environment, driven the way users drive it | It works for real | scenario log, observations, run ID |
| L5 | Soak, production-like load, or differential run against a reference | It keeps working and matches the reference | duration, error counts, diff report |

Climb as high as the project allows. The profile marks each level `local`, `ci-dispatch`, `remote-env`
or `unavailable` and says which need approval. Report every level you skipped, with the reason.

## Rules that make evidence trustworthy

- **Fail before, pass after, for the right reason.** The regression test must fail on the base
  production code with an assertion about the bug. A compile error against the base (because the test
  uses a new API) proves nothing about the bug; restructure the test or say so explicitly.
  `scripts/fail-before.sh` automates the check.
- **Non-zero counts.** Some runners report success when a filter selects zero tests. Read the executed
  count every time.
- **Full projects, not just filters.** Loader, config, serialization and startup changes break tests far
  from the filter. Run the whole affected project; for shared code, every project that consumes it.
- **Mutation check for new tests.** Break the fixed line on purpose (invert a condition, drop a call);
  the new test must fail. Revert. A test that survives the mutant does not cover the fix.
- **Determinism.** No sleeps or wall-clock waits; use the project's fakes, gates, clocks and hooks. A
  flaky new test is a defect in the PR.
- **Flakes are claims too.** Before calling a failure a flake: it is in the profile's flake list or it
  fails on the base too, and a single isolated rerun passes. Record both runs.
- **Save everything.** Every command and its output go to `<state>/evidence/<n>/`. PR bodies quote
  these logs, never memory.

## Live verification (L4/L5)

The strongest live evidence is **differential**: the same scenario, same environment, run on the baseline
build and on the fixed build. The bug shows on baseline and is gone on the fix, and nothing else
changed. Prove each lane runs the build you think it does (print the version or commit from the running
process, not from the build step).

A live scenario has five parts: **setup** (environment, data, config), **drive** (the requests, commands
or UI flow a user would perform, including the failure trigger: restart, reorg, timeout, bad input,
concurrency), **observe** (responses, logs, metrics, state on disk), **assert** (the success signal from
the brief, written down before running), **teardown**.

Recipes by kind of software:

| Kind | Realistic environment | Drive it | Observe |
|---|---|---|---|
| Library / SDK | A small consumer project that depends on the built artifact, not on source | Call the public API the way the issue's user did; property-based or fuzz inputs | Return values, exceptions, allocations |
| CLI tool | The built binary in a temp dir with realistic files | The exact command lines from the issue, plus edge inputs; stdin/stdout/exit codes | Output against golden files, exit code, files written |
| Web service / API | The service plus its real dependencies (compose, testcontainers, local cloud emulators) with seeded data | HTTP/gRPC calls scripted from the issue; concurrent and retried requests | Responses, logs, metrics endpoint, DB state |
| Web frontend | Dev or preview server against a local or mocked backend | Browser automation (Playwright or similar) through the user's flow | Screenshots, console errors, network log, accessibility tree |
| Distributed system / node software (databases, blockchain clients, brokers) | Local multi-node devnet or cluster; CI-dispatched or remote environment for real networks | Workload generator, restarts, crashes, partitions, upgrades from the previous version | Logs, metrics, health and sync status, consistency against a reference node |
| Data pipeline / ML | Sample of real-shaped data, fixed seeds | Run the pipeline end to end | Output diff and metrics against the baseline run |
| Infrastructure as code | Sandbox account or local emulator only | plan/diff, validate, policy checks; apply only in the sandbox | Plan diff, drift, resources created and destroyed |
| Mobile / desktop app | Emulator or simulator, clean profile | UI automation through the flow | Screenshots, logs, crash reports |
| Performance change | Same machine, same data, quiet system | Benchmark baseline and fix alternately, several runs each | Mean, variance, allocations; report noise honestly |

When L4 is out of reach locally, look for, in order: a CI workflow with `workflow_dispatch` that runs the
software for real on a branch; a project-provided remote test environment; a recorded reproduction the
maintainers accept (logs, traces); and only then report L4 as unreachable.

## What to put in the PR

Per level: the command or run ID, the counts or observed signal, and the level's limits (for example
"L4 on a local 2-node devnet; not verified on mainnet-sized state"). No level claimed without its log.
