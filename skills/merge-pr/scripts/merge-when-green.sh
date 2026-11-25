#!/usr/bin/env bash
# Merge a pull request only when every gate passes, at an exact head. Reports only, unless --merge.
# Usage: merge-when-green.sh OWNER/REPO PR HEAD_SHA [options]
#   --merge              actually merge (default: evaluate the gate and report)
#   --watch              keep polling until merged or a terminal failure (default: evaluate once)
#   --interval SEC       poll interval for --watch (default 180)
#   --method M           squash (default), merge or rebase
#   --min-required N     at least N required checks must have reported (default 1)
#   --block-check NAME   a check that must be absent, passing or skipped even if not required
#                        (repeatable; matches the check name or "workflow/name")
#   --no-approval        accept an empty review decision (repo requires no approval); still refuses
#                        REVIEW_REQUIRED and CHANGES_REQUESTED
# Gates: OPEN at HEAD_SHA (a newer head is followed only when it is a plain merge of the base branch into
# the pinned head); not draft; review APPROVED; >= N required checks, all passing; merge state CLEAN,
# UNSTABLE or HAS_HOOKS; 0 unresolved review threads and 0 changes requested, re-read right before merging;
# every --block-check passing. Merges with --match-head-commit so a late push cannot slip in.
# Exit: 0 merged, or (without --merge) every gate passes; 3 not ready yet; 1 terminal (closed, head moved,
# required or blocking check failed, merge refused); 2 usage.
set -uo pipefail

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
[ $# -ge 3 ] || { usage >&2; exit 2; }
slug="$1"; pr="$2"; pin="$3"; shift 3
merge=0; watch=0; interval=180; method=squash; min_req=1; no_approval=0; blocks=()
while [ $# -gt 0 ]; do
  case "$1" in
    --merge) merge=1 ;;
    --watch) watch=1 ;;
    --interval) interval="${2:?}"; shift ;;
    --method) method="${2:?}"; shift ;;
    --min-required) min_req="${2:?}"; shift ;;
    --block-check) blocks+=("${2:?}"); shift ;;
    --no-approval) no_approval=1 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[[ "$pin" =~ ^[0-9a-f]{40}$ ]] || { echo "HEAD_SHA must be the full 40-hex sha" >&2; exit 2; }
case "$method" in squash|merge|rebase) ;; *) echo "bad --method $method" >&2; exit 2 ;; esac
owner="${slug%%/*}"; repo="${slug#*/}"
state_dir="${MAINTAINER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/maintainer-skills}/$owner/$repo"
ts() { date -u +%FT%TZ; }

ledger() {  # json object
  mkdir -p "$state_dir"
  local line; line="$(jq -c --arg ts "$(ts)" '{ts:$ts} + .' <<<"$1")"
  ( flock 9; printf '%s\n' "$line" >> "$state_dir/ledger.jsonl" ) 9>"$state_dir/.ledger.lock"
}

# A new head is acceptable only if it is a merge commit whose first parent is the pinned head and whose
# second parent is already contained in the base branch.
follows_base_merge() {  # new_head base_branch
  local parents p1 p2 st
  parents="$(gh api "repos/$slug/commits/$1" --jq '[.parents[].sha] | join(" ")' 2>/dev/null)" || return 1
  read -r p1 p2 _ <<<"$parents"
  [ -n "${p2:-}" ] && [ "$p1" = "$pin" ] || return 1
  st="$(gh api "repos/$slug/compare/$2...$p2" --jq .status 2>/dev/null)" || return 1
  [ "$st" = behind ] || [ "$st" = identical ]
}

last=""
evaluate() {  # sets verdict: ready | wait | terminal, and reason
  local s
  s="$("$here/pr-state.sh" "$slug" "$pr" --json 2>/dev/null)" || { verdict=wait; reason="GitHub read failed"; return; }
  local st head draft rd ms reqn reqp unres chg failing_req
  st="$(jq -r .state <<<"$s")"; head="$(jq -r .head <<<"$s")"; draft="$(jq -r .draft <<<"$s")"
  rd="$(jq -r '.review_decision // ""' <<<"$s")"; ms="$(jq -r .merge_state <<<"$s")"
  reqn="$(jq -r .checks.required <<<"$s")"; reqp="$(jq -r .checks.required_pass <<<"$s")"
  unres="$(jq -r '.threads.unresolved | length' <<<"$s")"; chg="$(jq -r '.changes_requested | length' <<<"$s")"
  failing_req="$(jq -r '[.checks.failing[] | select(.required) | .workflow + "/" + .name] | join(", ")' <<<"$s")"
  [ "$(jq -r .threads.complete <<<"$s")" = true ] || unres="100+"

  if [ "$st" != OPEN ]; then
    verdict=terminal; reason="state $st"; [ "$st" = MERGED ] && verdict=merged; return
  fi
  if [ "$head" != "$pin" ]; then
    if follows_base_merge "$head" "$(jq -r .base <<<"$s")"; then
      echo "$(ts) #$pr head ${pin:0:10} -> ${head:0:10} is a plain base merge; following"
      pin="$head"; last=""; verdict=wait; reason="head followed"; return
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
      fail) verdict=wait; reason="blocking check '$b' is failing (needs its owner's action)"; return ;;
      pending) verdict=wait; reason="blocking check '$b' is pending"; return ;;
    esac
  done
  [ "$draft" = false ] || { verdict=wait; reason="draft"; return; }
  if [ $no_approval = 1 ]; then
    { [ -z "$rd" ] || [ "$rd" = APPROVED ]; } || { verdict=wait; reason="review decision $rd"; return; }
  else
    [ "$rd" = APPROVED ] || { verdict=wait; reason="review decision ${rd:-none}"; return; }
  fi
  [ "$reqn" -ge "$min_req" ] && [ "$reqp" = "$reqn" ] || { verdict=wait; reason="required checks $reqp/$reqn (min $min_req)"; return; }
  [ "$unres" = 0 ] || { verdict=wait; reason="$unres unresolved review thread(s)"; return; }
  [ "$chg" = 0 ] || { verdict=wait; reason="changes requested"; return; }
  case "$ms" in CLEAN|UNSTABLE|HAS_HOOKS) ;; *) verdict=wait; reason="merge state $ms"; return ;; esac
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
        out="$(gh pr merge "$pr" -R "$slug" "--$method" --match-head-commit "$pin" 2>&1)"; rc=$?
        sleep 10
        res="$(gh pr view "$pr" -R "$slug" --json state,mergeCommit --jq '"\(.state) \(.mergeCommit.oid // "")"' 2>/dev/null)"
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
