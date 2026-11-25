#!/usr/bin/env bash
# merge-when-green.sh (and pr-state.sh underneath it) against a fake gh: every refusal, the pinned merge.
. "$(dirname "$0")/lib.sh"

S="$REPO_ROOT/skills/merge-pr/scripts/merge-when-green.sh"
PIN="$(printf 'a%.0s' {1..40})"
NEW="$(printf 'b%.0s' {1..40})"
OLD="$(printf 'c%.0s' {1..40})"
BASEC="$(printf 'd%.0s' {1..40})"

# meta [key=value ...]: the pull request metadata GraphQL answer. Keys: state head draft mergeable ms rd
# approved_on (commit of bob's approval; empty for none) unresolved (count) total (thread count) cr
meta() {
  local state=OPEN head=$PIN draft=false mergeable=MERGEABLE ms=CLEAN rd=APPROVED approved_on=$PIN
  local unresolved=0 total="" cr=false kv
  for kv in "$@"; do local "${kv%%=*}=${kv#*=}"; done
  jq -n --arg state "$state" --arg head "$head" --argjson draft "$draft" --arg mg "$mergeable" --arg ms "$ms" \
        --arg rd "$rd" --arg ap "$approved_on" --argjson unres "$unresolved" --arg total "$total" --argjson cr "$cr" '
    ([range($unres) | {id: "PRRT_t\(.)", isResolved: false, isOutdated: false, path: "src/a.c", line: 3,
        comments: {nodes: [{author: {login: "carol"}, createdAt: "2026-01-01T00:00:00Z", body: "why?", url: "u"}]}}]
     + [{id: "PRRT_done", isResolved: true, isOutdated: false, path: "src/a.c", line: 1,
        comments: {nodes: [{author: {login: "bob"}, createdAt: "2026-01-01T00:00:00Z", body: "ok", url: "u"}]}}]) as $threads
    | {data: {repository: {pullRequest: {
        number: 42, title: "Fix it", url: "https://example.invalid/pr/42", state: $state, isDraft: $draft,
        mergeable: $mg, mergeStateStatus: $ms, reviewDecision: (if $rd == "" then null else $rd end),
        headRefOid: $head, headRefName: "fix", baseRefName: "main", author: {login: "alice"},
        headRepository: {nameWithOwner: "o/r"}, commits: {nodes: [{commit: {committedDate: "2026-01-01T00:00:00Z"}}]},
        latestReviews: {nodes: (
            (if $ap == "" then [] else [{author: {login: "bob"}, state: "APPROVED", commit: {oid: $ap}, submittedAt: "2026-01-02T00:00:00Z"}] end)
          + (if $cr then [{author: {login: "carol"}, state: "CHANGES_REQUESTED", commit: {oid: $head}, submittedAt: "2026-01-02T00:00:00Z"}] else [] end))},
        reviewThreads: {totalCount: (if $total == "" then ($threads | length) else ($total | tonumber) end), nodes: $threads}}}}}'
}

# checks_page HAS_NEXT < lines "workflow|name|required|status|conclusion|startedAt" (workflow "status" =
# a commit status context, conclusion = its state)
checks_page() {
  jq -Rn --argjson next "${1:-false}" '
    [inputs | select(length > 0) | split("|") | {wf: .[0], name: .[1], req: (.[2] == "true"), status: .[3], concl: .[4], at: .[5]}
     | if .wf == "status" then {__typename: "StatusContext", context: .name, state: .concl, createdAt: .at, isRequired: .req}
       else {__typename: "CheckRun", name, conclusion: (if .concl == "" then null else .concl end), status,
             startedAt: (if .at == "" then null else .at end), isRequired: .req,
             checkSuite: {workflowRun: {workflow: {name: .wf}}}} end] as $nodes
    | {data: {repository: {pullRequest: {commits: {nodes: [{commit: {statusCheckRollup: {contexts: {
        pageInfo: {hasNextPage: $next, endCursor: (if $next then "CUR" else null end)}, nodes: $nodes}}}}]}}}}}'
}

GREEN_CHECKS='CI|build|true|COMPLETED|SUCCESS|2026-01-01T01:00:00Z
CI|test|true|COMPLETED|SUCCESS|2026-01-01T01:00:00Z
Lint|lint|false|COMPLETED|SUCCESS|2026-01-01T01:00:00Z'

# Default scenario: everything green; merging works and lands.
green() {
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"; chmod +x "$T/bin/sleep"
  gh_route 'statusCheckRollup' "$(checks_page false <<<"${CHECKS:-$GREEN_CHECKS}")"
  gh_route '^pr merge ' ''
  gh_route '^pr view 42 -R o/r --json state,mergeCommit' '{"state":"MERGED","mergeCommit":{"oid":"eeee"}}'
}
with_meta() { gh_route 'reviewThreads' "$(meta "$@")"; }
gate() { MAINTAINER_ACTIONS="${MAINTAINER_ACTIONS-pr_merge=auto}" run "$S" o/r 42 "$PIN" "$@"; }
refused() {  # expected_rc reason_substring
  assert_rc "$1"; assert_contains "$OUT" "$2"
  assert_no_gh_writes; assert_gh_not_called '^pr merge'
}

test_dry_run_all_green_reports_ready_and_never_writes() {
  green; with_meta
  gate
  assert_rc 0; assert_contains "$OUT" "READY at ${PIN:0:12}"; assert_contains "$OUT" "dry run"
  assert_no_gh_writes; assert_no_unrouted
  assert_no_file "$MAINTAINER_STATE/o/r/ledger.jsonl"
}

test_merge_all_green_squashes_at_pinned_head() {
  green; with_meta
  gate --merge
  assert_rc 0; assert_contains "$OUT" "MERGED eeee"
  assert_gh_called "^pr merge 42 -R o/r --squash --match-head-commit $PIN\$"
  assert_eq 1 "$(gh_writes | wc -l | tr -d ' ')" "exactly one write call"
  assert_eq "merged $PIN eeee squash" "$(jq -r '"\(.event) \(.head) \(.merge_commit) \(.method)"' "$MAINTAINER_STATE/o/r/ledger.jsonl")"
}

test_merge_method_rebase_is_passed_through() {
  green; with_meta
  gate --merge --method rebase
  assert_rc 0; assert_gh_called "^pr merge 42 -R o/r --rebase --match-head-commit $PIN\$"
}

test_refuses_when_head_sha_moved() {
  green; with_meta head="$NEW"
  gate --merge
  refused 1 "head moved to $NEW"
}

test_watcher_refuses_even_a_plain_base_merge_on_apply() {
  green; with_meta head="$NEW"
  gh_route "^api repos/o/r/commits/$NEW" "{\"parents\":[{\"sha\":\"$PIN\"},{\"sha\":\"$BASEC\"}]}"
  gh_route "^api repos/o/r/compare/main\\.\\.\\.$BASEC" '{"status":"behind"}'
  MAINTAINER_ACTIONS=pr_merge=auto run timeout 20 "$S" o/r 42 "$PIN" --merge --watch --interval 0
  refused 1 "head moved to $NEW"
  assert_gh_not_called '^api repos/o/r/commits/'
}

test_default_and_off_block_direct_merge() {
  green; with_meta
  MAINTAINER_ACTIONS='' gate --merge
  refused 2 "pr_merge=draft"
  MAINTAINER_ACTIONS=pr_merge=off gate --merge
  refused 2 "pr_merge=off"
}

test_ask_requires_and_binds_exact_merge_approval() {
  green; with_meta
  local token
  MAINTAINER_ACTIONS=pr_merge=ask gate --merge
  refused 2 "pr_merge=ask"
  MAINTAINER_ACTIONS=pr_merge=ask gate
  assert_rc 0; assert_no_gh_writes
  token="$(sed -n 's/^Approval token: //p' <<<"$OUT")"
  assert_match "$token" '^[a-f0-9]{40,64}$'
  MAINTAINER_ACTIONS=pr_merge=ask gate --merge --watch --approve "$token"
  refused 2 "auto only"
  MAINTAINER_ACTIONS=pr_merge=ask gate --merge --method rebase --approve "$token"
  refused 2 "approval does not match"
  MAINTAINER_ACTIONS=pr_merge=ask run "$S" o/r 42 "$NEW" --merge --approve "$token"
  refused 2 "approval does not match"
  MAINTAINER_ACTIONS=pr_merge=ask gate --merge --approve "$token"
  assert_rc 0; assert_contains "$OUT" "MERGED eeee"
  assert_eq 1 "$(gh_writes | wc -l | tr -d ' ')"
}

test_ask_approval_refuses_head_change_after_preview() {
  green
  gh_route_once 'reviewThreads' "$(meta)"
  with_meta head="$NEW"
  MAINTAINER_ACTIONS=pr_merge=ask gate
  assert_rc 0
  MAINTAINER_ACTIONS=pr_merge=ask gate --merge --approve "$(sed -n 's/^Approval token: //p' <<<"$OUT")"
  refused 1 "head moved to $NEW"
}

test_refuses_when_unresolved_review_thread() {
  green; with_meta unresolved=1
  gate --merge
  refused 3 "1 unresolved review thread(s)"
}

test_refuses_when_review_threads_exceed_one_page() {
  green; with_meta total=101
  gate --merge
  refused 3 "100+ unresolved review thread(s)"
}

test_refuses_when_no_approval_on_current_head() {
  green; with_meta approved_on="$OLD"
  gate --merge
  refused 3 "no approval on head ${PIN:0:12}"
}

test_refuses_when_review_decision_is_not_approved() {
  green; with_meta rd=REVIEW_REQUIRED approved_on=""
  gate --merge
  refused 3 "review decision REVIEW_REQUIRED"
}

test_no_approval_flag_still_refuses_review_required() {
  green; with_meta rd=REVIEW_REQUIRED approved_on=""
  gate --merge --no-approval
  refused 3 "review decision REVIEW_REQUIRED"
}

test_no_approval_flag_does_not_accept_stale_approval() {
  green; with_meta approved_on="$OLD"
  gate --merge --no-approval
  refused 3 "no approval on head"
}

test_no_approval_flag_accepts_empty_review_decision() {
  green; with_meta rd="" approved_on=""
  gate --no-approval
  assert_rc 0; assert_contains "$OUT" "READY"
}

test_preview_rejects_approval_behind_a_plain_base_merge() {
  green; with_meta approved_on="$OLD"
  gate
  refused 3 "no approval on head ${PIN:0:12}"
  assert_gh_not_called '^api repos/o/r/commits/'
}

test_refuses_when_required_check_failing() {
  CHECKS="$GREEN_CHECKS
CI|test|true|COMPLETED|FAILURE|2026-01-01T02:00:00Z" green; with_meta
  gate --merge
  refused 1 "required check failed: CI/test"
}

test_refuses_when_required_check_pending() {
  CHECKS="$GREEN_CHECKS
CI|test|true|IN_PROGRESS||2026-01-01T02:00:00Z" green; with_meta
  gate --merge
  refused 3 "required checks 1/2"
}

test_refuses_when_required_check_is_rerunning_after_a_pass() {
  CHECKS="$GREEN_CHECKS
CI|test|true|QUEUED|||" green; with_meta
  gate --merge
  refused 3 "required checks 1/2"
}

test_refuses_when_fewer_required_checks_than_min_required() {
  green; with_meta
  gate --merge --min-required 3
  refused 3 "required checks 2/2 (min 3)"
}

test_refuses_when_block_check_failing_even_if_not_required() {
  CHECKS="$GREEN_CHECKS
Guard|ci-change-guard|false|COMPLETED|FAILURE|2026-01-01T01:00:00Z" green; with_meta
  gate --merge --block-check Guard/ci-change-guard
  refused 3 "blocking check 'Guard/ci-change-guard' is failing"
  : > "$FAKE_GH_LOG"
  gate --merge --block-check ci-change-guard
  refused 3 "blocking check 'ci-change-guard' is failing"
  gate
  assert_rc 0 "a failing non-required check that is not a --block-check does not block"
}

test_refuses_when_block_check_pending() {
  CHECKS="$GREEN_CHECKS
Guard|ci-change-guard|false|IN_PROGRESS||2026-01-01T01:00:00Z" green; with_meta
  gate --merge --block-check ci-change-guard
  refused 3 "blocking check 'ci-change-guard' is pending"
}

test_refuses_when_not_mergeable() {
  green; with_meta mergeable=CONFLICTING ms=DIRTY
  gate --merge
  refused 3 "mergeable CONFLICTING"
}

test_refuses_when_merge_state_blocked() {
  green; with_meta ms=BLOCKED
  gate --merge
  refused 3 "merge state BLOCKED"
}

test_refuses_when_closed() {
  green; with_meta state=CLOSED
  gate --merge
  refused 1 "state CLOSED"
}

test_already_merged_exits_zero_without_writing() {
  green; with_meta state=MERGED
  gate --merge
  assert_rc 0; assert_contains "$OUT" "already merged"; assert_no_gh_writes
}

test_refuses_when_draft() {
  green; with_meta draft=true
  gate --merge
  refused 3 "draft"
}

test_refuses_when_changes_requested() {
  green; with_meta cr=true
  gate --merge
  refused 3 "changes requested"
}

test_rereads_right_before_merging_and_refuses_a_new_thread() {
  green
  gh_route_once 'reviewThreads' "$(meta)"
  with_meta unresolved=1
  gate --merge
  refused 3 "1 unresolved review thread(s)"
}

test_merge_that_does_not_land_exits_1_without_ledger() {
  green; with_meta
  gh_route_first '^pr merge ' 'Head branch was modified' 1
  gh_route_first '^pr view 42 -R o/r --json state,mergeCommit' '{"state":"OPEN","mergeCommit":null}'
  gate --merge
  assert_rc 1; assert_contains "$OUT" "merge did not land"
  assert_no_file "$MAINTAINER_STATE/o/r/ledger.jsonl"
}

test_github_read_failure_waits() {
  green; gh_route 'reviewThreads' 'HTTP 502' 1
  gate --merge
  refused 3 "GitHub read failed"
}

test_rejects_a_short_head_sha() {
  run "$S" o/r 42 abc123 --merge
  assert_rc 2; assert_contains "$OUT" "full 40-hex sha"
  assert_eq "" "$(gh_calls)" "no gh call on a usage error"
}

test_strict_required_refuses_skipped_and_keeps_nonrequired_guard_skippable() {
  CHECKS="${GREEN_CHECKS/SUCCESS/SKIPPED}" green; with_meta
  gate --merge --require-success
  refused 3 "required checks 1/2"
}

test_preview_also_refuses_head_movement() {
  green; with_meta head="$NEW"
  gate
  refused 1 "head moved"
  assert_gh_not_called '^api repos/o/r/commits/'
}

run_tests "$@"
