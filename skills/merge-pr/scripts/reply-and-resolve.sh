#!/usr/bin/env bash
# Post review-thread reply drafts and resolve the threads they answer. Dry run unless --post.
# Usage: reply-and-resolve.sh DRAFT_DIR [--post]
# Each DRAFT_DIR/reply-*.md has header lines, a line "---", then the reply body:
#   Thread: PRRT_...                 (GraphQL id of the review thread; required)
#   Resolve after posting: yes|no    (default no)
# Every draft is checked before anything is posted; one malformed draft (no "---", no or bad Thread
# header, a Resolve value other than yes/no, empty body) rejects the whole run with exit 2.
# Idempotent: skips a thread that is already resolved, and does not post a body that the thread already
# contains (it only resolves it, if asked). Prints what it did per draft.
set -euo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
dir="$1"; post=0
case "${2:-}" in "") ;; --post) post=1 ;; *) echo "unknown argument $2" >&2; exit 2 ;; esac
[ $# -le 2 ] || { echo "too many arguments" >&2; exit 2; }
[ -d "$dir" ] || { echo "not a directory: $dir" >&2; exit 2; }
shopt -s nullglob
drafts=("$dir"/reply-*.md)
[ ${#drafts[@]} -gt 0 ] || { echo "no reply-*.md drafts in $dir"; exit 0; }

# header FILE KEY: value of "KEY:" before the first "---", trimmed
header() { awk -v k="$2" '/^---\r?$/ {exit} index($0, k ":") == 1 {sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit}' "$1"; }
body_of() { awk 'found {print} /^---\r?$/ && !found {found=1}' "$1" | sed '/./,$!d'; }

bad=0
for f in "${drafts[@]}"; do
  why=""
  if ! grep -qE '^---'$'\r''?$' "$f"; then why="no '---' line between the headers and the body"
  elif ! [[ "$(header "$f" Thread)" =~ ^PRRT_[A-Za-z0-9_-]+$ ]]; then why="no valid 'Thread: PRRT_...' header"
  elif ! [[ "$(header "$f" "Resolve after posting")" =~ ^(yes|no|)$ ]]; then why="'Resolve after posting' must be yes or no"
  elif [ -z "$(body_of "$f" | tr -d '[:space:]')" ]; then why="empty body"
  fi
  [ -z "$why" ] || { echo "reject $f: $why" >&2; bad=1; }
done
[ $bad = 0 ] || { echo "nothing posted: fix the drafts above" >&2; exit 2; }

resolve() {
  gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
    -f t="$1" --jq '"resolved=\(.data.resolveReviewThread.thread.isResolved)"'
}

for f in "${drafts[@]}"; do
  thread="$(header "$f" Thread)"
  want_resolve="$(header "$f" "Resolve after posting")"; want_resolve="${want_resolve:-no}"
  body="$(body_of "$f")"
  st="$(gh api graphql -f query='query($t:ID!){node(id:$t){... on PullRequestReviewThread{isResolved comments(first:100){nodes{body}}}}}' \
        -f t="$thread" --jq '.data.node')" || { echo "skip $f: cannot read $thread"; continue; }
  if [ "$(jq -r .isResolved <<<"$st")" = true ]; then echo "skip $f: already resolved"; continue; fi
  if jq -e --arg b "$body" 'any(.comments.nodes[]; (.body | rtrimstr("\n")) == ($b | rtrimstr("\n")))' <<<"$st" >/dev/null; then
    echo "skip $f: reply already posted"
    if [ $post = 1 ] && [ "$want_resolve" = yes ]; then resolve "$thread"; fi
    continue
  fi
  if [ $post = 0 ]; then
    printf '== %s (%s) resolve=%s\n%s\n\n' "$thread" "$(basename "$f")" "$want_resolve" "$body"
    continue
  fi
  gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}' \
    -f t="$thread" -f b="$body" --jq '.data.addPullRequestReviewThreadReply.comment.url'
  if [ "$want_resolve" = yes ]; then resolve "$thread"; fi
done
