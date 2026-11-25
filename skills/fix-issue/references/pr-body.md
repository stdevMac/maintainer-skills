# PR body

Use the project's PR template when it has one (the profile names it); fill every section it has, in
its order. Without a template, use this shape:

```markdown
Fixes #<n>

## Changes

- <what the code now does, one bullet per behavior change, user-visible effect first>

## Testing

- Regression test `<name>` in `<file>`: fails on the base (<one-line excerpt of the failure>), passes with the fix.
- <project/package>: <executed> passed, <failed> failed, <skipped> skipped (<command>).
- Live: <environment>, <scenario>; baseline shows <bug signal>, fix shows <expected signal> (<run ID or log>).
- Not verified: <levels not reached and why>.

## Remarks

<root cause in two or three sentences; anything a reviewer should look at first; compatibility or
release-note notes; related issues and PRs>

<attribution line from the profile, if any>
```

## Before opening or editing

- Every number and claim matches a saved log under `<state>/evidence/<n>/`. Agents invent numbers
  ("took about 20 minutes", "1,000 runs"); delete anything without a log behind it.
- Claims like "no new public API" or "no behavior change for X": check the diff for new public members
  and for every caller of changed code.
- A user-visible or breaking change says so in one sentence and gets a release-note line (and a `!` in a
  conventional-commit title when the project uses them).
- No chronology ("first I tried..."), no first person, no CI status claims (CI shows itself), no
  @-mentions unless the project expects them, no marketing words.
- Security-sensitive context never appears in a public PR. If the fix touches code with an unfixed
  private issue, hold the PR and ask.
- Body edits after review: keep the template, update counts and changes so the body stays true for the
  current head.
