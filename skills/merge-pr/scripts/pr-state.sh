#!/usr/bin/env bash
# One pull request's merge readiness, read-only: state, head, mergeability, review decision, approvals on
# the current head, required and failing checks (all pages; latest run per workflow + check name), and
# unresolved review threads.
# Usage: pr-state.sh OWNER/REPO PR [--json]
#   default output: a short human summary; --json: the full summary object
set -euo pipefail

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
slug="$1"; n="${2:?PR number}"; mode="${3:-}"
owner="${slug%%/*}"; name="${slug#*/}"
[ "$owner" != "$slug" ] || { echo "OWNER/REPO expected" >&2; exit 2; }

meta_q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  number title url state isDraft mergeable mergeStateStatus reviewDecision
  headRefOid headRefName baseRefName author{login} headRepository{nameWithOwner}
  commits(last:1){nodes{commit{committedDate}}}
  latestReviews(first:100){nodes{author{login} state commit{oid} submittedAt}}
  reviewThreads(first:100){totalCount nodes{id isResolved isOutdated path line
    comments(first:50){nodes{author{login} createdAt body url}}}}}}}'
checks_q='query($o:String!,$r:String!,$n:Int!,$endCursor:String){repository(owner:$o,name:$r){pullRequest(number:$n){
  commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100,after:$endCursor){
    pageInfo{hasNextPage endCursor}
    nodes{__typename
      ... on CheckRun{name conclusion status startedAt isRequired(pullRequestNumber:$n)
                      checkSuite{workflowRun{workflow{name}}}}
      ... on StatusContext{context state createdAt isRequired(pullRequestNumber:$n)}}}}}}}}}}'

meta="$(gh api graphql -F o="$owner" -F r="$name" -F n="$n" -f query="$meta_q")"
checks="$(gh api graphql --paginate -F o="$owner" -F r="$name" -F n="$n" -f query="$checks_q" \
  | jq -s '[.[].data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // [] | .[]]')"

# A queued or waiting check run has no startedAt yet; it is the newest run of its workflow + name (a rerun
# in progress), so it sorts last and its pending state wins over the attempt it replaces.
summary="$(jq --slurpfile ctx <(printf '%s' "$checks") '.data.repository.pullRequest as $p
  | [$ctx[0][]
      | if .__typename == "CheckRun" then
          {name, workflow: (.checkSuite.workflowRun.workflow.name // ""), required: .isRequired, at: (.startedAt // "9999"),
           success: (.status == "COMPLETED" and .conclusion == "SUCCESS"),
           bucket: (if .status != "COMPLETED" then "pending"
                    elif (.conclusion | IN("SUCCESS","NEUTRAL","SKIPPED")) then "pass" else "fail" end)}
        else
          {name: .context, workflow: "status", required: .isRequired, at: (.createdAt // ""),
           success: (.state == "SUCCESS"),
           bucket: (if .state == "SUCCESS" then "pass" elif (.state | IN("PENDING","EXPECTED")) then "pending" else "fail" end)}
        end]
  | group_by([.workflow, .name]) | map(max_by(.at)) as $checks
  | {pr: $p.number, title: $p.title, url: $p.url, state: $p.state, draft: $p.isDraft,
     author: $p.author.login, head_repo: $p.headRepository.nameWithOwner,
     base: $p.baseRefName, branch: $p.headRefName, head: $p.headRefOid,
     last_push: $p.commits.nodes[0].commit.committedDate,
     mergeable: $p.mergeable, merge_state: $p.mergeStateStatus, review_decision: $p.reviewDecision,
     approvals_current: [$p.latestReviews.nodes[] | select(.state=="APPROVED" and .commit.oid==$p.headRefOid) | .author.login],
     approvals_old: [$p.latestReviews.nodes[] | select(.state=="APPROVED" and .commit.oid!=$p.headRefOid) | .author.login],
     approvals: [$p.latestReviews.nodes[] | select(.state=="APPROVED") | {login: .author.login, commit: .commit.oid}],
     changes_requested: [$p.latestReviews.nodes[] | select(.state=="CHANGES_REQUESTED") | .author.login],
     checks: {total: ($checks|length),
              required: ([$checks[] | select(.required)] | length),
              required_pass: ([$checks[] | select(.required and .bucket=="pass")] | length),
              required_success: ([$checks[] | select(.required and .success)] | length),
              failing: [$checks[] | select(.bucket=="fail") | {name, workflow, required}],
              pending: [$checks[] | select(.bucket=="pending") | {name, workflow, required}]},
     threads: {total: $p.reviewThreads.totalCount, complete: ($p.reviewThreads.totalCount <= 100),
               unresolved: [$p.reviewThreads.nodes[] | select(.isResolved|not)
                 | {id, path, line, outdated: .isOutdated,
                    last_author: .comments.nodes[-1].author.login, last_at: .comments.nodes[-1].createdAt,
                    url: .comments.nodes[0].url,
                    first: (.comments.nodes[0].body | gsub("[\r\n\t]+"; " ") | .[0:200])}]}}' <<<"$meta")"

if [ "$mode" = "--json" ]; then echo "$summary"; exit 0; fi
jq -r '
  "#\(.pr) \(.title)\n  \(.state) draft=\(.draft) base=\(.base) head=\(.head[0:12]) pushed=\(.last_push) by \(.author)",
  "  mergeable=\(.mergeable) state=\(.merge_state) review=\(.review_decision // "none") approvals(current)=\(.approvals_current|join(",")) approvals(old)=\(.approvals_old|join(",")) changes_requested=\(.changes_requested|join(","))",
  "  checks: \(.checks.total) total, required \(.checks.required_pass)/\(.checks.required) pass; failing=\([.checks.failing[] | .workflow + "/" + .name + (if .required then "*" else "" end)] | join(", ")); pending=\(.checks.pending|length)",
  "  threads: \(.threads.unresolved|length) unresolved of \(.threads.total)\(if .threads.complete then "" else " (more than 100: incomplete)" end)",
  (.threads.unresolved[] | "    \(.id) \(.path // "-"):\(.line // "-")\(if .outdated then " (outdated)" else "" end) last=\(.last_author)@\(.last_at[0:16]) :: \(.first[0:120])")
' <<<"$summary"
