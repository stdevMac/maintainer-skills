#!/usr/bin/env bash
# Post review-thread reply drafts and resolve the threads they answer. Dry run unless --post.
# Usage: reply-and-resolve.sh DRAFT_DIR [--post]
# Each DRAFT_DIR/reply-*.md has header lines, a line "---", then the reply body:
#   Thread: PRRT_...                 (GraphQL id of the review thread; required)
#   Resolve after posting: yes|no    (default no)
# Idempotent: skips a thread that is already resolved, and does not post a body that the thread already
# contains (it only resolves it, if asked). Prints what it did per draft.
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
dir="$1"; post=0; [ "${2:-}" = "--post" ] && post=1
shopt -s nullglob
drafts=("$dir"/reply-*.md)
[ ${#drafts[@]} -gt 0 ] || { echo "no reply-*.md drafts in $dir"; exit 0; }

resolve() {
  gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
    -f t="$1" --jq '"resolved=\(.data.resolveReviewThread.thread.isResolved)"'
}

for f in "${drafts[@]}"; do
  thread="$(sed -n 's/^Thread: *//p' "$f" | head -1)"
  [[ "$thread" == PRRT_* ]] || { echo "skip $f: no 'Thread: PRRT_...' header"; continue; }
  want_resolve="$(sed -n 's/^Resolve after posting: *//p' "$f" | head -1)"
  body="$(awk 'found {print} /^---$/ && !found {found=1}' "$f" | sed '/./,$!d')"
  [ -n "$body" ] || { echo "skip $f: empty body"; continue; }
  st="$(gh api graphql -f query='query($t:ID!){node(id:$t){... on PullRequestReviewThread{isResolved comments(first:100){nodes{body}}}}}' \
        -f t="$thread" --jq '.data.node')" || { echo "skip $f: cannot read $thread"; continue; }
  if [ "$(jq -r .isResolved <<<"$st")" = true ]; then echo "skip $f: already resolved"; continue; fi
  if jq -e --arg b "$body" 'any(.comments.nodes[]; (.body | rtrimstr("\n")) == ($b | rtrimstr("\n")))' <<<"$st" >/dev/null; then
    echo "skip $f: reply already posted"
    [ $post = 1 ] && [ "$want_resolve" = yes ] && resolve "$thread"
    continue
  fi
  if [ $post = 0 ]; then
    printf '== %s (%s) resolve=%s\n%s\n\n' "$thread" "$(basename "$f")" "${want_resolve:-no}" "$body"
    continue
  fi
  gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}' \
    -f t="$thread" -f b="$body" --jq '.data.addPullRequestReviewThreadReply.comment.url'
  [ "$want_resolve" = yes ] && resolve "$thread"
done
