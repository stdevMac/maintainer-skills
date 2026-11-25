# Verdicts, evidence bar and refuter lenses

## Verdicts

| Verdict | Meaning | Evidence required | Public action (when policy allows) |
|---|---|---|---|
| `close_fixed` | The reported behavior no longer happens on the default branch | One of: a merged PR whose merge commit is an ancestor of the default branch **and** touches the exact code path in the report; a test targeting the reported behavior that fails on the reported version and passes on head; a recorded live run | Comment naming the fix and how it was verified, close as completed |
| `close_obsolete` | The feature, platform or code path is gone, and the report's ask no longer applies | The removal commit or PR, plus a check that the user's actual need is not still unmet elsewhere | Comment, close as not planned |
| `close_duplicate` | Same root cause as another issue | Both reports traced to the same code path, not just similar symptoms | Comment linking the canonical issue, close as duplicate |
| `needs_fix` | Reproduced, or the defect is proven in code with a failing test | A failing test or a recorded repro on head | Task Brief; optional comment with the narrowed root cause |
| `needs_env` | Reproduction needs an environment you could not reach | What is missing, and the plan to reach it | None, or a comment asking for specific data |
| `needs_info` | The report lacks something only the reporter has | The exact questions; what you already ruled out | One comment with specific questions |
| `review_open_pr` | An open PR already addresses it | The PR number and that it targets this behavior | Hand to the review-pr skill |
| `keep_open` | Valid feature, epic or design question not ready for a fix | Why it is valid and what would unblock it | Optional comment with a concrete proposal |
| `cannot_repro` | Tried and failed to reproduce | Every attempt with versions and commands | Comment only if it carries new evidence |
| `security_private` | Security-sensitive | Step 3 screen | **None.** Private route only |

Code reading alone supports a comment, never a close. A close also needs: no open PR that references the
issue (the merge closes it), and the issue re-read right before closing in case the reporter replied.

## Lessons that recur across projects

- "A merged PR touched this area" is not "fixed". Check that the PR changed the exact path in the report.
  One path can be fixed while a sibling path (sync vs live, CLI vs API) is not.
- "The environment from the report no longer exists" is not "fixed". The behavior may live on.
- A feature request is delivered only when the exact ask is delivered, not something adjacent.
- Before adding a guard, look for an existing one in other callers. A duplicate guard can be harmful.
- A claim like "now it logs X" must hold at the default log level.
- Reports contain fabricated or mistaken SHAs, versions, stack frames and PR numbers. Verify first.
- A green test that passes for the wrong reason is not evidence. Ask which code path the test exercises.
- Shallow clones make `git merge-base --is-ancestor` answer "no" for old commits. Use the compare API.

## Refuter lenses

Run them against your own verdict before acting, or brief a refuter subagent with them.

For closes:
- Is it really fixed or obsolete on head, or only on the path you tested?
- Did the cited PR change exactly the behavior reported, in every entry point?
- Did the reporter or anyone else reply with a newer reproduction?

For fixes and fix plans:
- Is the root cause right, or is the fix treating a symptom?
- Does the change remove the purpose of an existing guard?
- Can a concurrent caller, retry, restart or partial failure still reach the bad state?
- Does every caller of the changed code still get what it expects?
- Does the regression test fail without the fix, for the reason the bug exists?
- Is there a cheaper fix that removes code instead of adding it?
