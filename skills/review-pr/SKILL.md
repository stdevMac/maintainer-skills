---
name: review-pr
description: Adversarial review of a pull request at an exact head, in an isolated worktree. Reads the full public context, computes the true merge-base diff, reviews every changed file against the project rules and a correctness, security, compatibility, performance and test checklist, falsifies each finding before keeping it, optionally verifies by execution (build, run the PR's tests, prove they fail on the base, run the live scenario), and drafts an APPROVE or a concise COMMENT pinned to the reviewed commit, posting it only when the configured action mode allows. Use when the user says "review PR N", "check this PR", "is this PR correct", "review my changes", or as the review stage of the maintainer loop.
---

# Review a pull request

Arguments: a PR number or URL, optional `--repo`, `--verify` (run code, see step 6), `--focus "<area>"`.

Posting the review is the `pr_review` action and is opt-in: resolve its mode with the project-profile
skill's `scripts/action-mode.sh pr_review` (`off`, `draft` by default, `ask`, `auto`). A `pr-reviewer`
subagent never posts whatever the mode; it returns the draft payload.

Load the project profile and the project's own rules (read from disk; they change). If the project ships
its own review skill or rules (for example `.agents/skills/review`), apply them in addition to this one.

## Steps

1. **Snapshot.** PR state, head SHA, base branch, author, draft flag, linked issues, every comment, review
   and review thread with its resolution state (paginate everything), checks and statuses:
   `gh pr view <n> --json ...`, GraphQL `reviewThreads`, `gh pr checks <n>`. Note whether your account
   already reviewed this exact head; an unchanged head with no new context needs no second review.
   Never approve your own PR.
2. **Isolate.** Fetch the head and base into refs you own
   (`git fetch origin pull/<n>/head:refs/review/<n>/head`), compute the true base with
   `git merge-base`, and check out the head in a worktree (the fix-issue skill's `scripts/worktree.sh new
   <clone> review-<n> --base <head sha> --branch review/<n>`). Never diff against the moving tip of the
   base branch, and never touch the user's checkout.
3. **Scope.** `git diff --stat <base>...<head>` before any full diff. If the branch contains merge
   commits, separate the author's files (`git log --no-merges --name-only <base>..<head>`) from files
   that arrived through merges. List skipped files (generated, vendored, binary, lockfile-only) with the
   reason. Large files go to subagents with the rules and checklist pasted into their prompt; subagents
   do not inherit your context.
4. **Understand intent.** Read the linked issue and the PR description. Write down, in one or two
   sentences, what the PR claims to fix or add, and what would have to be true for it to be correct.
5. **Review each file** against [references/checklist.md](references/checklist.md) and the project
   rules. Read the callers of every changed function whose behavior changes, the registration or wiring
   of new components, and the tests that are supposed to cover it. Each concern becomes a hypothesis
   with a concrete trigger ("when X happens, Y returns Z").
6. **Verify by execution** when `--verify` is given or the profile allows it, in the review worktree:
   build (L0); run the PR's new and changed tests; run the fix-issue skill's `scripts/fail-before.sh
   --base <base>` with the PR's test to check it catches the bug; reproduce the reported bug on the base;
   run the live scenario from the PR's testing notes on base and head. A concern you can trigger with a
   test becomes a finding with proof; one you cannot trigger is weaker. Without `--verify`, do not claim
   anything ran; existing CI counts only for what its logs show (non-zero counts, the right head).
7. **Falsify.** For each hypothesis, name the evidence that would disprove it (a guard in a caller,
   DI order, a bound elsewhere, a test that covers it), look for it, and mark KEEP or DROP with the
   reason. Keep a domain finding only at about 80% confidence or better. A violation of an explicit
   project rule is reported even below that bar; dismissing it is the author's call.
8. **Decide** using the disposition table in [references/publish.md](references/publish.md): approve,
   comment, hold (an existing unresolved issue or unmet owner condition already covers it), or
   incomplete (you could not cover something material; say what).
9. **Publish per the action mode for `pr_review`**, following
   [references/publish.md](references/publish.md). Every mode saves the payload to
   `<state>/drafts/pr_review/<n>-<head sha>.md` (`<state>` as in the maintainer-loop skill). `off` and
   `draft`: stop there and report the path. `ask`: show it, post after approval. `auto` (or approved
   `ask`): refresh the head first, pin `commit_id`, deduplicate, post, save the receipt.
10. **Clean up.** Remove the review worktree and your private refs. Keep notes and evidence.

## Output

PR, reviewed head and true base, scope (reviewed, skipped with reasons), findings that survived (each
with file:line, trigger, impact, fix), dropped hypotheses in one line each, what was executed and its
counts, the disposition, and the review URL or draft path.
