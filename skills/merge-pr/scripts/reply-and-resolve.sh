#!/usr/bin/env bash
# Preview review-thread replies for one PR at an exact head.
# Usage: reply-and-resolve.sh OWNER/REPO PR HEAD_SHA DRAFT_DIR [--resolve] [--post [--approve TOKEN]]
# Drafts: reply-*.md, with a unique "Thread: PRRT_..." header, optional
# "Resolve after posting: yes|no" (default no), then "---" and a nonempty body.
# --post writes only if thread_reply permits it. --resolve also requests resolution
# for drafts marked yes, subject to thread_resolve. Preview with the same --resolve
# setting and use its approval token with --post in ask mode.
# Validates the whole batch before writing; skips resolved threads and duplicate replies.
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "reply-and-resolve.sh: $*" >&2; exit 2; }
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
[ "$#" -ge 4 ] || die "expected OWNER/REPO PR HEAD_SHA DRAFT_DIR"
slug=$1; pr=$2; pin=$3; dir=$4; shift 4
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
post=0; resolve_requested=0; approval=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --post) post=1 ;;
    --resolve) resolve_requested=1 ;;
    --approve) approval="${2:?--approve needs a token}"; shift ;;
    *) die "unknown argument $1" ;;
  esac
  shift
done
[[ "$slug" =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$ && "${slug#*/}" != . && "${slug#*/}" != .. && "$pr" =~ ^[1-9][0-9]*$ ]] ||
  die "OWNER/REPO and a positive PR number required"
[[ "$pin" =~ ^[0-9a-f]{40}$ ]] || die "HEAD_SHA must be the full 40-hex sha"
[ "$post" = 1 ] || [ -z "$approval" ] || die "--approve requires --post"
[ -d "$dir" ] || die "not a directory: $dir"
shopt -s nullglob
drafts=("$dir"/reply-*.md)
[ ${#drafts[@]} -gt 0 ] || { echo "no reply-*.md drafts in $dir"; exit 0; }

# header FILE KEY: value of "KEY:" before the first "---", trimmed
header() { awk -v k="$2" '/^---\r?$/ {exit} index($0, k ":") == 1 {sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit}' "$1"; }
body_of() { awk 'found {print} /^---\r?$/ && !found {found=1}' "$1" | sed '/./,$!d'; }

declare -A seen=()
threads=(); resolutions=(); bodies=()
any_resolution=0
for f in "${drafts[@]}"; do
  # Snapshot once: the preview/token and mutation must use the same parsed bytes.
  text="$(cat -- "$f")"
  grep -qE '^---'$'\r''?$' <<<"$text" || die "$f: missing '---' separator"
  thread="$(header /dev/stdin Thread <<<"$text")"
  [[ "$thread" =~ ^PRRT_[A-Za-z0-9_-]+$ ]] || die "$f: invalid Thread header"
  [ -z "${seen[$thread]:-}" ] || die "$f: duplicate draft for $thread"
  seen[$thread]=1
  want_resolve="$(header /dev/stdin 'Resolve after posting' <<<"$text")"
  [[ "$want_resolve" =~ ^(yes|no|)$ ]] || die "$f: 'Resolve after posting' must be yes or no"
  body="$(body_of /dev/stdin <<<"$text")"
  [ -n "$(tr -d '[:space:]' <<<"$body")" ] || die "$f: empty body"
  will_resolve=no
  if [ "$resolve_requested" = 1 ] && [ "$want_resolve" = yes ]; then
    will_resolve=yes; any_resolution=1
  fi
  threads+=("$thread"); resolutions+=("$will_resolve"); bodies+=("$body")
done

token="$(
  {
    printf '%s\0' thread_reply "$slug" "$pr" "$pin"
    for i in "${!threads[@]}"; do
      printf '%s\0' "${threads[$i]}" "${resolutions[$i]}" "${bodies[$i]}"
    done
  } | git -C "$here" hash-object --stdin
)"
authorize() {
  local mode
  mode="$("$here/../../project-profile/scripts/action-mode.sh" "$1" --repo "$slug")" || return
  [ -z "$approval" ] || [ "$approval" = "$token" ] || die "$1: approval does not match this preview"
  case "${mode%% *}" in
    auto) ;;
    ask) [ "$approval" = "$token" ] || die "$1=ask: approve the exact preview before posting" ;;
    *) die "no writes: $1=${mode%% *}" ;;
  esac
}
if [ "$post" = 1 ]; then
  authorize thread_reply
  if [ "$any_resolution" = 1 ]; then authorize thread_resolve; fi
fi

resolve() {
  gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
    -f t="$1" --jq '"resolved=\(.data.resolveReviewThread.thread.isResolved)"'
}

status=()
for i in "${!threads[@]}"; do
  thread="${threads[$i]}"
  st="$(gh api graphql -f query='query($t:ID!){node(id:$t){... on PullRequestReviewThread{
    isResolved pullRequest{number headRefOid state repository{nameWithOwner}}
    comments(first:100){pageInfo{hasNextPage} nodes{body}}}}}' \
        -f t="$thread" --jq '.data.node')" || die "cannot read $thread"
  jq -e --arg slug "$slug" --arg head "$pin" --argjson pr "$pr" '
    .pullRequest | (.repository.nameWithOwner | ascii_downcase) == ($slug | ascii_downcase)
      and .number == $pr and .headRefOid == $head and .state == "OPEN"
  ' <<<"$st" >/dev/null || die "$thread is not on open $slug#$pr at $pin"
  if [ "$(jq -r .isResolved <<<"$st")" = true ]; then
    status+=(resolved)
  elif jq -e --arg b "${bodies[$i]}" 'any(.comments.nodes[]; (.body | rtrimstr("\n")) == $b)' <<<"$st" >/dev/null; then
    status+=(posted)
  elif [ "$(jq -r .comments.pageInfo.hasNextPage <<<"$st")" = false ]; then
    status+=(pending)
  else
    die "$thread comment list is incomplete; cannot verify whether the reply already exists"
  fi
done

if [ "$post" = 0 ]; then
  printf 'Review thread draft for %s#%s at %s\n' "$slug" "$pr" "$pin"
  for i in "${!threads[@]}"; do
    printf '== %s (%s) resolve=%s\n%s\n\n' "${threads[$i]}" "${status[$i]}" "${resolutions[$i]}" "${bodies[$i]}"
  done
  echo "Approval token: $token"
  exit 0
fi

for i in "${!threads[@]}"; do
  thread="${threads[$i]}"
  case "${status[$i]}" in
    resolved) echo "skip $thread: already resolved"; continue ;;
    posted) echo "skip $thread: reply already posted" ;;
    pending)
      gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}' \
        -f t="$thread" -f b="${bodies[$i]}" --jq '.data.addPullRequestReviewThreadReply.comment.url'
      ;;
  esac
  if [ "${resolutions[$i]}" = yes ]; then resolve "$thread"; fi
done
