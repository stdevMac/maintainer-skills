#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
script="$REPO_ROOT/skills/merge-pr/scripts/reply-and-resolve.sh"
pin="$(printf 'a%.0s' {1..40})"
moved="$(printf 'b%.0s' {1..40})"
body='Verified against the current head.'
thread_response() {
  jq -nc --arg head "${1:-$pin}" --arg slug "${2:-o/r}" --argjson comments "${3:-[]}" '
    {data:{node:{isResolved:false,pullRequest:{number:42,headRefOid:$head,state:"OPEN",
      repository:{nameWithOwner:$slug}},comments:{pageInfo:{hasNextPage:false},nodes:$comments}}}}'
}
draft() {
  printf 'Thread: %s\nResolve after posting: %s\n---\n%s\n' "$1" "$2" "$3"
}
apply() { run "$script" o/r 42 "$pin" "$T/drafts" "$@"; }
setup_draft() {
  mkdir -p "$T/drafts"
  draft PRRT_example "$1" "$body" > "$T/drafts/reply-a.md"
  gh_route 'query\(' "$(thread_response)"
  gh_route 'mutation.*addPullRequestReviewThreadReply' '{"data":{"addPullRequestReviewThreadReply":{"comment":{"url":"https://example.test/reply"}}}}'
  gh_route 'mutation.*resolveReviewThread' '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}'
}
test_preview_does_not_write() {
  setup_draft yes
  apply --resolve
  assert_rc 0
  assert_contains "$OUT" 'Verified against the current head.'
  assert_contains "$OUT" 'resolve=yes'
  assert_contains "$OUT" "o/r#42 at $pin"
  assert_no_gh_writes
}
test_auto_reply_does_not_also_resolve() {
  setup_draft yes
  MAINTAINER_ACTIONS='thread_reply=auto,thread_resolve=off' apply --post
  assert_rc 0
  assert_contains "$OUT" 'https://example.test/reply'
  assert_eq 1 "$(gh_writes | wc -l | tr -d ' ')"
  assert_gh_not_called 'mutation.*resolveReviewThread'
}
test_auto_reply_and_resolve() {
  setup_draft yes
  MAINTAINER_ACTIONS='thread_reply=auto,thread_resolve=auto' apply --post --resolve
  assert_rc 0
  assert_contains "$OUT" $'https://example.test/reply\nresolved=true'
  assert_eq 2 "$(gh_writes | wc -l | tr -d ' ')"
}
test_malformed_draft_blocks_all_writes() {
  setup_draft yes
  printf 'Thread: invalid\n---\ntext\n' > "$T/drafts/reply-b.md"
  MAINTAINER_ACTIONS='*=auto' apply --post
  assert_rc 2
  assert_no_gh_writes
}
test_default_and_off_prevent_direct_writes() {
  setup_draft yes
  apply --post
  assert_rc 2; assert_contains "$OUT" 'thread_reply=draft'; assert_no_gh_writes
  MAINTAINER_ACTIONS=thread_reply=off apply --post
  assert_rc 2; assert_contains "$OUT" 'thread_reply=off'; assert_no_gh_writes
  MAINTAINER_ACTIONS='thread_reply=auto,thread_resolve=off' apply --post --resolve
  assert_rc 2; assert_contains "$OUT" 'thread_resolve=off'; assert_no_gh_writes
}
test_ask_approval_binds_exact_body_and_operation() {
  setup_draft yes
  export MAINTAINER_ACTIONS='thread_reply=ask,thread_resolve=ask'
  apply --resolve
  assert_rc 0; assert_no_gh_writes
  local token
  token="$(sed -n 's/^Approval token: //p' <<<"$OUT")"
  assert_match "$token" '^[a-f0-9]{40,64}$'
  apply --post --resolve
  assert_rc 2; assert_contains "$OUT" 'thread_reply=ask'; assert_no_gh_writes
  apply --post --approve "$token"
  assert_rc 2; assert_contains "$OUT" 'approval does not match'; assert_no_gh_writes
  draft PRRT_example yes 'Changed after approval.' > "$T/drafts/reply-a.md"
  apply --post --resolve --approve "$token"
  assert_rc 2; assert_contains "$OUT" 'approval does not match'; assert_no_gh_writes
  draft PRRT_example yes "$body" > "$T/drafts/reply-a.md"
  apply --post --resolve --approve "$token"
  assert_rc 0; assert_contains "$OUT" $'https://example.test/reply\nresolved=true'
  assert_eq 2 "$(gh_writes | wc -l | tr -d ' ')"
}
test_apply_rejects_head_change_and_foreign_thread_before_any_writes() {
  setup_draft yes
  gh_route_first 'query\(.*t=PRRT_example' "$(thread_response "$moved")"
  MAINTAINER_ACTIONS='*=auto' apply --post
  assert_rc 2; assert_contains "$OUT" 'is not on open o/r#42'; assert_no_gh_writes
  : > "$FAKE_GH_ROUTES"
  gh_route 'query\(.*t=PRRT_foreign' "$(thread_response "$pin" other/repo)"
  gh_route 'query\(' "$(thread_response)"
  draft PRRT_foreign no 'Other reply.' > "$T/drafts/reply-b.md"
  MAINTAINER_ACTIONS='*=auto' apply --post
  assert_rc 2; assert_contains "$OUT" 'PRRT_foreign is not on open'; assert_no_gh_writes
}
test_already_posted_body_is_not_sent_twice() {
  setup_draft yes
  gh_route_first 'query\(' "$(thread_response "$pin" o/r "$(jq -nc --arg body "$body" '[{body:$body}]')")"
  MAINTAINER_ACTIONS='*=auto' apply --post --resolve
  assert_rc 0; assert_contains "$OUT" 'reply already posted'
  assert_gh_not_called 'mutation.*addPullRequestReviewThreadReply'
  assert_gh_called 'mutation.*resolveReviewThread'
}
run_tests "$@"
