# Disposition and publication

## Disposition

| Verified state | Action |
|---|---|
| Source reviewed, no surviving finding, no unmet owner condition | `APPROVE` pinned to the reviewed `commit_id` (body per profile; empty is fine) |
| New confirmed substantive finding | One `COMMENT` review: inline comments at exact lines plus a short summary. `REQUEST_CHANGES` only if the profile allows it |
| An existing public comment or unresolved thread already covers your concern, or an owner's stated condition is unmet | Private `hold`, link it; do not duplicate it publicly |
| Only cosmetic notes, draft status, or CI-only failures | Not a reason to hold; decide on the source. CI failures are the author's to read; mention them only with a source-level cause |
| Material part not covered (access, size, identity uncertain) | Private `incomplete` with the exact gap; never approve |
| Merged or closed during the review | Record the verdict; post nothing |

Your own PR: never approve it. Someone else's PR with a session or agent actively pushing (last push
within the profile's quiet window): review is fine, pushing to it is not.

## Before posting

1. Refresh the PR: still open, head SHA equals the reviewed SHA, no new comments or threads that change
   the decision. If the head moved, the review is for the old head: keep it, review the new head's
   delta and any unchanged code it affects, then decide again.
2. Deduplicate: list your account's reviews on this PR; no second identical review on the same head.
3. Check the profile allows this event type (for example no `REQUEST_CHANGES`) and wants an attribution
   line.
4. Check the action mode for `pr_review` (`scripts/action-mode.sh pr_review` in the project-profile
   skill). `off` or `draft`: save the draft below and stop. `ask`: post only after explicit approval.

## Draft and posting

In every mode, build the payload as a file (never interpolate prose into shell) and save the draft
`<state>/drafts/pr_review/<n>-<head sha>.md` with the target PR, the head SHA, the payload and the exact
command below:

```json
{
  "commit_id": "<full reviewed head sha>",
  "event": "COMMENT",
  "body": "<one or two sentence summary, or empty>",
  "comments": [
    {"path": "src/cache.ts", "line": 88, "side": "RIGHT", "body": "<problem, trigger and impact, fix>"}
  ]
}
```

```bash
gh api -X POST repos/<owner>/<repo>/pulls/<n>/reviews --input payload.json > receipt.json
jq '{id, state, commit_id, html_url}' receipt.json
```

Inline `line` must be a line present in the diff on that side; otherwise put the comment in the body
with `path:line`. After posting, save `payload.json` and `receipt.json` under `<state>/reviews/<n>/<head>/`.

If the POST outcome is uncertain (timeout, network error), read the PR's reviews before retrying.
