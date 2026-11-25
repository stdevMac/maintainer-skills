#!/usr/bin/env bash
# List PRs linked to an issue: closing references, timeline cross-references and connected events,
# a text search for "#N", and an optional title keyword search. Read-only.
# Usage: linked-prs.sh OWNER/REPO ISSUE [keyword ...]
# Prints one JSON object per PR: {pr, state, draft, base, author, title, merge, updated, via}
set -euo pipefail

usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help|"") usage; [ -n "${1:-}" ]; exit $? ;; esac
slug="$1"; n="${2:?issue number}"; shift 2
owner="${slug%%/*}"; name="${slug#*/}"
[ "$owner" != "$slug" ] && [ -n "$name" ] || { echo "OWNER/REPO expected, got $slug" >&2; exit 2; }

q='query($owner:String!,$name:String!,$num:Int!){
  repository(owner:$owner,name:$name){
    issue(number:$num){
      closedByPullRequestsReferences(first:25, includeClosedPrs:true){ nodes{ number repository{nameWithOwner} } }
      timelineItems(first:100, itemTypes:[CROSS_REFERENCED_EVENT, CONNECTED_EVENT]){
        nodes{
          __typename
          ... on CrossReferencedEvent{ source{ __typename ... on PullRequest{ number repository{nameWithOwner} } } }
          ... on ConnectedEvent{ subject{ __typename ... on PullRequest{ number repository{nameWithOwner} } } }
        }
      }
    }
  }
}'
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT

gh api graphql -F owner="$owner" -F name="$name" -F num="$n" -f query="$q" \
  | jq -r --arg slug "$slug" '.data.repository.issue as $i
      | ($i.closedByPullRequestsReferences.nodes[] | select(.repository.nameWithOwner==$slug) | "\(.number) closes"),
        ($i.timelineItems.nodes[] | (.source // .subject)
          | select(.__typename=="PullRequest" and .repository.nameWithOwner==$slug) | "\(.number) xref")' >> "$tmp"

gh api -X GET search/issues -f q="repo:$slug is:pr \"#$n\"" --jq '.items[].number' 2>/dev/null \
  | sed 's/$/ text/' >> "$tmp" || true

if [ $# -gt 0 ]; then
  gh pr list -R "$slug" --state all --search "$* in:title" --limit 10 --json number --jq '.[].number' 2>/dev/null \
    | sed 's/$/ keyword/' >> "$tmp" || true
fi

sort -u "$tmp" | awk '{ if ($1 in v) v[$1] = v[$1] "," $2; else v[$1] = $2 } END {for (k in v) print k, v[k]}' | sort -n \
| while read -r pr via; do
    gh pr view "$pr" -R "$slug" --json number,state,isDraft,baseRefName,author,title,mergeCommit,updatedAt 2>/dev/null \
      | jq -c --arg via "$via" '{pr:.number, state, draft:.isDraft, base:.baseRefName, author:.author.login,
          title, merge:(.mergeCommit.oid // null), updated:.updatedAt, via:$via}' || true
  done
