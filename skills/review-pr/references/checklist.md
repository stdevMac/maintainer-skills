# Review checklist

Apply the project's own rules and domain checklists first; this list is the generic floor. Skip what CI
already enforces (the profile lists it): formatting, build errors, the test suites CI runs, dependency
scanning. Report problems, not preferences.

## Correctness

- Does the change do what the PR claims, on every entry point (API, CLI, background job, sync/async
  path, retry path, startup and shutdown)?
- Boundaries: empty, one, maximum, off-by-one, overflow and truncation, negative, null or missing,
  duplicate, out of order, unicode and encoding.
- Errors: swallowed exceptions, partial failure leaving state half-written, error paths that skip
  cleanup, wrong error code or message contract.
- Concurrency: shared mutable state, check-then-act races, lock ordering, work that can outlive its
  owner (a straggler writing after a reset or dispose), cancellation honored and propagated.
- Resources: every handle, stream, buffer, subscription, timer, pooled object and process released on
  every path, including exceptions and cancellation.
- State and persistence: restart in the middle, crash consistency, migrations both ways, data written by
  the previous version still readable.
- Retries and idempotency: what happens when the same request, message or block arrives twice?
- Time: clocks, time zones, timeouts that are too short under load, tests depending on wall time.
- Does the change remove or bypass an existing guard? Find out why the guard was there (blame, PR).

## Security

- Input from outside the process (network, files, CLI, env, other services) validated and bounded:
  sizes, counts, depth, rates.
- Injection (SQL, shell, path traversal, template, log), unsafe deserialization, SSRF.
- Authentication and authorization on new endpoints and handlers.
- Secrets in code, logs, errors, test fixtures or telemetry.
- New dependencies: maintained, licence compatible, not duplicating an existing one, pinned.
- A security-sensitive finding is reported privately (profile), never in a public review comment.

## Compatibility

- Public API, wire format, storage format, config keys, CLI flags, environment variables, metric names
  and log formats: anything renamed, removed or retyped breaks someone. Is it versioned, defaulted,
  documented, release-noted?
- New required parameters without a backward-compatible default.
- Interfaces extended without default implementations (breaks implementers).
- Behavior change hidden behind an unchanged signature.

## Performance

- Allocations, copies, LINQ/stream chains or reflection in per-request or per-item paths.
- Blocking calls in async code; sync-over-async.
- Queries or I/O in loops (N+1), missing batching, unbounded caches or queues.
- Algorithmic change on a hot path without a benchmark.

## Tests

- A bug fix has a regression test, and it fails without the fix (verify when you can).
- The test exercises the changed path, not a neighbor that happens to pass.
- Boundary cases from the correctness list are covered where they matter.
- Deterministic: no sleeps, no wall clock, no order dependence, no fixed ports shared with other tests.
- Duplicated test bodies that differ only in inputs should be one parameterized test (if the project
  says so).

## Clarity and scope

- Changes outside the PR's purpose (drive-by refactors, reformatting, unrelated renames).
- Comments that contradict the code, or narrate it without adding the why.
- Leftover debug code, commented-out code, TODOs without an issue.
- The PR description matches the diff (claims of "no behavior change", "no new API", test counts).

## Writing a finding

One to three sentences: the problem with file:line, the trigger and impact, and a concrete fix.

> `Cache.Get` returns the pooled buffer after `Return` puts it back (Cache.cs:88), so a concurrent `Get`
> can read a buffer another caller is overwriting. Copy before returning, or return the lease and release
> it in the caller.
