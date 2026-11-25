#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
script="$REPO_ROOT/skills/merge-pr/scripts/reply-and-resolve.sh"
setup_draft() {
  mkdir -p "$T/drafts"
  printf 'Thread: PRRT_example\nResolve after posting: %s\n---\nVerified against the current head.\n' "$1" > "$T/drafts/reply-a.md"
  gh_route 'query\(' '{"data":{"node":{"isResolved":false,"comments":{"nodes":[]}}}}'
  gh_route 'mutation.*addPullRequestReviewThreadReply' '{"data":{"addPullRequestReviewThreadReply":{"comment":{"url":"https://example.test/reply"}}}}'
  gh_route 'mutation.*resolveReviewThread' '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}'
}
test_preview_does_not_write() {
  setup_draft yes
  run "$script" "$T/drafts"
  assert_rc 0
  assert_contains "$OUT" 'Verified against the current head.'
  assert_no_gh_writes
}
test_post_then_resolve() {
  setup_draft yes
  run "$script" "$T/drafts" --post
  assert_rc 0
  assert_contains "$OUT" $'https://example.test/reply\nresolved=true'
  assert_eq 2 "$(gh_writes | wc -l)"
}
test_malformed_draft_blocks_all_writes() {
  setup_draft yes
  printf 'Thread: invalid\n---\ntext\n' > "$T/drafts/reply-b.md"
  run "$script" "$T/drafts" --post
  assert_rc 2
  assert_no_gh_writes
}
run_tests "$@"
