# Closing review threads

## Read

All unresolved threads with every comment, plus top-level review bodies and PR comments (a review body
can carry findings without a thread). `scripts/pr-state.sh <repo> <n>` lists threads; for full text:

```bash
gh api graphql -F o=<owner> -F r=<repo> -F n=<n> -f query='query($o:String!,$r:String!,$n:Int!){
  repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{
    id isResolved isOutdated path line
    comments(first:100){nodes{author{login} createdAt body url}}}}}}}'
```

A thread whose last reply is yours is answered but still unresolved; it still blocks the gate. Resolve
it when the project lets authors resolve, otherwise ask the reviewer.

## Decide

For each thread, first check the claim:

1. Restate it as a testable statement ("calling X after Y returns stale Z").
2. Try to trigger it: a test, a probe, a read of the callers. Pin-down claims ("this breaks upgrades",
   "descendants stay behind", "null keeps the old value") turn out real more often than not.
3. Then pick one:

| Verdict | When | What to do |
|---|---|---|
| fixed | The point holds | Fix it so it is correct in all cases, not only the reviewer's example. Add or extend a test that fails without the fix. Push, then reply |
| declined | The point does not hold, or the suggested change breaks something | Reply with the evidence: file:line at the current head, a failing test of the suggestion, or the reference implementation |
| answered | A question or a design remark | Answer it; if it needs a decision you cannot make, say who decides |
| deferred | Valid but out of scope | Propose a follow-up issue (draft it); only if the reviewer or project accepts deferral |

A reviewer's suggested code can carry its own bug (a race, a missed case). Improve on it and say why.
The same finding coming back after a fix means the fix or the reply missed something: escalate.

## Reply

One draft file per thread, `reply-<file>-<line>-<reviewer>.md`:

```text
Thread: PRRT_xxxxx
Location: src/foo.cs:120
Reviewer: <login>
Verdict: fixed
Resolve after posting: yes
Lines cited are at <short sha>.
---
Fixed in <short sha>: <what changed, one sentence>. `<TestName>` covers it and fails without the change.
```

Reply style: verdict in the first sentence, then the evidence; cite the commit and file:line; no
@-mentions unless the project uses them; attribution line if the profile requires one. Post with
`scripts/reply-and-resolve.sh <dir> --post` only when policy or the user allows; it is idempotent.

## Pushing fixes to the PR

- The branch head must equal the one you started from (`git ls-remote`), right before pushing.
- A plain merge of the base is fine; no rebase, amend or force-push on a pushed branch.
- A push that changes the diff dismisses approvals in many repos. That is accepted for a valid fix;
  never push for a point you declined.
- After pushing, update the PR body if counts or changes moved, and request a re-review the way the
  project does it (bot command, re-request reviewer).
