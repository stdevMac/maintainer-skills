#!/usr/bin/env bash
# Merge a pull request only when every gate passes, at an exact head. Reports only, unless --merge.
# Usage: merge-when-green.sh OWNER/REPO PR HEAD_SHA [options]
#   --merge              actually merge (default: evaluate the gate and report)
#   --watch              keep polling until merged or a terminal failure (default: evaluate once)
#   --interval SEC       poll interval for --watch (default 180)
#   --method M           squash (default), merge or rebase
#   --min-required N     at least N required checks must have reported (default 1)
#   --require-success    require SUCCESS (not SKIPPED or NEUTRAL) on required checks
#   --exact-head         stop on head movement; accept approval only on the pinned commit
#   --block-check NAME   a check that must be absent, passing or skipped even if not required
#                        (repeatable; matches the check name or "workflow/name")
#   --no-approval        accept an empty review decision (repo requires no approval); still refuses
#                        REVIEW_REQUIRED and CHANGES_REQUESTED
# Gates: OPEN at HEAD_SHA (a newer head is followed only when it is a plain merge of the base branch into
# the pinned head); not draft; review APPROVED with at least one approval given on HEAD_SHA, on a head
# followed from it, or on a commit reached from it through up to 5 plain base merges (a repository that
# keeps stale approvals reports APPROVED for code nobody approved); >= N required checks, all passing;
# mergeable, merge state CLEAN or UNSTABLE;
# 0 unresolved review threads and 0 changes requested, re-read right before merging; every --block-check
# passing. Merges with --match-head-commit so a late push cannot slip in.
# Exit: 0 merged, or (without --merge) every gate passes; 3 not ready yet (a failing --block-check waits
# for its owner); 1 terminal (closed, head moved, required check failed, merge refused); 2 usage.
set -euo pipefail

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
[ $# -ge 3 ] || { usage >&2; exit 2; }
slug="$1"; pr="$2"; pin="$3"; shift 3
merge=0; watch=0; interval=180; method=squash; min_req=1; no_approval=0; strict=0; exact=0; blocks=()
while [ $# -gt 0 ]; do
  case "$1" in
    --merge) merge=1 ;;
    --watch) watch=1 ;;
    --interval) interval="${2:?}"; shift ;;
    --method) method="${2:?}"; shift ;;
    --min-required) min_req="${2:?}"; shift ;;
    --require-success) strict=1 ;;
    --exact-head) exact=1 ;;
    --block-check) blocks+=("${2:?}"); shift ;;
    --no-approval) no_approval=1 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[[ "$pin" =~ ^[0-9a-f]{40}$ ]] || { echo "HEAD_SHA must be the full 40-hex sha" >&2; exit 2; }
case "$method" in squash|merge|rebase) ;; *) echo "bad --method $method" >&2; exit 2 ;; esac
owner="${slug%%/*}"; repo="${slug#*/}"
approved_heads=" $pin "   # heads an approval may point at: the pin and the plain base merges followed from it
state_dir="${MAINTAINER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/maintainer-skills}/$owner/$repo"
ts() { date -u +%FT%TZ; }

ledger() {  # json object
  mkdir -p "$state_dir"
  local line; line="$(jq -c --arg ts "$(ts)" '{ts:$ts} + .' <<<"$1")"
  ( flock 9; printf '%s\n' "$line" >> "$state_dir/ledger.jsonl" ) 9>"$state_dir/.ledger.lock"
}

# base_merge_parent COMMIT BASE_BRANCH: print COMMIT's first parent when COMMIT is a merge whose second
# parent is already contained in the base branch (a plain "merge the base in"); fail otherwise.
base_merge_parent() {
  local parents p1 p2 extra st
  parents="$(gh api "repos/$slug/commits/$1" --jq '[.parents[].sha] | join(" ")' 2>/dev/null)" || return 1
  read -r p1 p2 extra <<<"$parents"
  [ -n "${p2:-}" ] && [ -z "$extra" ] || return 1
  st="$(gh api "repos/$slug/compare/$2...$p2" --jq .status 2>/dev/null)" || return 1
  { [ "$st" = behind ] || [ "$st" = identical ]; } && echo "$p1"
}
# A new head is acceptable only if it is a plain base merge whose first parent is the pinned head.
follows_base_merge() {  # new_head base_branch
  [ "$(base_merge_parent "$1" "$2")" = "$pin" ]
}
# Approvals survive a plain base merge in many repositories but sit on the merge's first parent. When the
# pin itself carries no approval, walk first parents back through plain base merges (at most 5) and accept
# approvals on the commits reached, so a watcher re-armed after "merge the base in" can still merge.
walked=""
walk_base_merges() {  # base_branch
  [ "$walked" != "$pin" ] || return 0
  walked="$pin"
  local c="$pin" p _
  for _ in 1 2 3 4 5; do
    p="$(base_merge_parent "$c" "$1")" || break
    approved_heads="$approved_heads$p "; c="$p"
  done
}

last=""
defer() { verdict='wait'; reason=$1; }
evaluate() {  # sets verdict: ready | wait | terminal, and reason
  local s
  s="$("$here/pr-state.sh" "$slug" "$pr" --json 2>/dev/null)" || { defer "GitHub read failed"; return; }
  local st head draft rd ms mg reqn reqp unres chg failing_req appr
  st="$(jq -r .state <<<"$s")"; head="$(jq -r .head <<<"$s")"; draft="$(jq -r .draft <<<"$s")"
  rd="$(jq -r '.review_decision // ""' <<<"$s")"; ms="$(jq -r .merge_state <<<"$s")"; mg="$(jq -r .mergeable <<<"$s")"
  appr="$(jq -r --arg h "$approved_heads" '[.approvals[]? | .commit as $c | select($c != null and ($h | contains(" " + $c + " "))) | .login] | join(",")' <<<"$s")"
  if [ "$exact" = 0 ] && [ -z "$appr" ] && [ "$rd" = APPROVED ] && [ "$st" = OPEN ] && [ "$head" = "$pin" ]; then
    walk_base_merges "$(jq -r .base <<<"$s")"
    appr="$(jq -r --arg h "$approved_heads" '[.approvals[]? | .commit as $c | select($c != null and ($h | contains(" " + $c + " "))) | .login] | join(",")' <<<"$s")"
  fi
  reqn="$(jq -r .checks.required <<<"$s")"; reqp="$(jq -r .checks.required_pass <<<"$s")"
  if [ "$strict" = 1 ]; then reqp="$(jq -r .checks.required_success <<<"$s")"; fi
  unres="$(jq -r '.threads.unresolved | length' <<<"$s")"; chg="$(jq -r '.changes_requested | length' <<<"$s")"
  failing_req="$(jq -r '[.checks.failing[] | select(.required) | .workflow + "/" + .name] | join(", ")' <<<"$s")"
  [ "$(jq -r .threads.complete <<<"$s")" = true ] || unres="100+"

  if [ "$st" != OPEN ]; then
    verdict=terminal; reason="state $st"; [ "$st" = MERGED ] && verdict=merged; return 0
  fi
  if [ "$head" != "$pin" ]; then
    if [ "$exact" = 0 ] && follows_base_merge "$head" "$(jq -r .base <<<"$s")"; then
      echo "$(ts) #$pr head ${pin:0:10} -> ${head:0:10} is a plain base merge; following"
      pin="$head"; approved_heads="$approved_heads$head "; last=""; defer "head followed"; return
    fi
    verdict=terminal; reason="head moved to $head and it is not a plain base merge"; return
  fi
  local cur="review=${rd:-none} merge=$ms required=$reqp/$reqn unresolved=$unres changes_requested=$chg draft=$draft"
  [ "$cur" != "$last" ] && { echo "$(ts) #$pr $cur"; last="$cur"; }
  [ -z "$failing_req" ] || { verdict=terminal; reason="required check failed: $failing_req"; return; }
  local b bstate
  for b in "${blocks[@]+"${blocks[@]}"}"; do
    bstate="$(jq -r --arg b "$b" '[(.checks.failing[] | select(.name==$b or (.workflow + "/" + .name)==$b) | "fail"),
                                   (.checks.pending[] | select(.name==$b or (.workflow + "/" + .name)==$b) | "pending")] | first // "ok"' <<<"$s")"
    case "$bstate" in
      fail) defer "blocking check '$b' is failing (needs its owner's action)"; return ;;
      pending) defer "blocking check '$b' is pending"; return ;;
    esac
  done
  [ "$draft" = false ] || { defer "draft"; return; }
  if [ $no_approval = 1 ]; then
    { [ -z "$rd" ] || [ "$rd" = APPROVED ]; } || { defer "review decision $rd"; return; }
  else
    [ "$rd" = APPROVED ] || { defer "review decision ${rd:-none}"; return; }
    [ -n "$appr" ] || { defer "no approval on head ${pin:0:12} (approvals on older commits do not count)"; return; }
  fi
  [ "$reqn" -ge "$min_req" ] && [ "$reqp" = "$reqn" ] || { defer "required checks $reqp/$reqn (min $min_req)"; return; }
  [ "$unres" = 0 ] || { defer "$unres unresolved review thread(s)"; return; }
  [ "$chg" = 0 ] || { defer "changes requested"; return; }
  [ "$mg" = MERGEABLE ] || { defer "mergeable $mg"; return; }
  case "$ms" in CLEAN|UNSTABLE) ;; *) defer "merge state $ms"; return ;; esac
  verdict=ready; reason="all gates pass"
}

while :; do
  evaluate
  case "$verdict" in
    merged) echo "$(ts) #$pr already merged"; exit 0 ;;
    terminal) echo "$(ts) #$pr STOP: $reason"; exit 1 ;;
    ready)
      if [ $merge = 0 ]; then echo "$(ts) #$pr READY at ${pin:0:12}: $reason (dry run; pass --merge)"; exit 0; fi
      # Re-read once more right before merging, so a comment posted during the poll still blocks.
      evaluate
      if [ "$verdict" = ready ]; then
        rc=0
        out="$(gh pr merge "$pr" -R "$slug" "--$method" --match-head-commit "$pin" 2>&1)" || rc=$?
        sleep 10
        res="$(gh pr view "$pr" -R "$slug" --json state,mergeCommit --jq '"\(.state) \(.mergeCommit.oid // "")"' 2>/dev/null)" || res=""
        if [ "${res%% *}" = MERGED ]; then
          echo "$(ts) #$pr MERGED ${res#* }"
          ledger "$(jq -nc --argjson pr "$pr" --arg head "$pin" --arg mc "${res#* }" --arg m "$method" \
            '{event:"merged", kind:"pr", number:$pr, head:$head, merge_commit:$mc, method:$m}')"
          exit 0
        fi
        echo "$(ts) #$pr merge did not land (rc=$rc): $out"
        [ $watch = 1 ] || exit 1
      fi
      ;;
    wait)
      [ $watch = 1 ] || { echo "$(ts) #$pr NOT READY: $reason"; exit 3; }
      [ "$reason" = "${last_reason:-}" ] || { echo "$(ts) #$pr waiting: $reason"; last_reason="$reason"; }
      ;;
  esac
  sleep "$interval"
done
