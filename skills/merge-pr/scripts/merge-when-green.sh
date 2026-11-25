#!/usr/bin/env bash
# Merge a pull request only when every gate passes, at an exact head. Reports only, unless --merge.
# Usage: merge-when-green.sh OWNER/REPO PR HEAD_SHA [options]
#   --merge              actually merge (requires auto or exact approval in ask mode)
#   --approve TOKEN      approval from the READY preview with the same target and options
#   --watch              keep polling until merged or a terminal failure (default: evaluate once)
#   --interval SEC       poll interval for --watch (default 180)
#   --method M           squash (default), merge or rebase
#   --min-required N     at least N required checks must have reported (default 1)
#   --require-success    require SUCCESS (not SKIPPED or NEUTRAL) on required checks
#   --block-check NAME   a check that must be absent, passing or skipped even if not required
#                        (repeatable; matches the check name or "workflow/name")
#   --no-approval        accept an empty review decision (repo requires no approval); still refuses
#                        REVIEW_REQUIRED and CHANGES_REQUESTED
# Gates: OPEN at HEAD_SHA; not draft; review APPROVED with approval at HEAD_SHA; >= N required
# checks, all passing; mergeable, merge state CLEAN or UNSTABLE; no unresolved review threads or
# changes requested; every --block-check passing. Rechecks before using --match-head-commit.
# Exit: 0 merged, or (without --merge) every gate passes; 3 not ready yet (a failing --block-check waits
# for its owner); 1 terminal (closed, head moved, required check failed, merge refused); 2 usage.
set -euo pipefail

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
[ $# -ge 3 ] || { usage >&2; exit 2; }
slug="$1"; pr="$2"; pin="$3"; shift 3
merge=0; watch=0; interval=180; method=squash; min_req=1; no_approval=0; strict=0; blocks=()
approval=""
while [ $# -gt 0 ]; do
  case "$1" in
    --merge) merge=1 ;;
    --approve) approval="${2:?--approve needs a token}"; shift ;;
    --watch) watch=1 ;;
    --interval) interval="${2:?}"; shift ;;
    --method) method="${2:?}"; shift ;;
    --min-required) min_req="${2:?}"; shift ;;
    --require-success) strict=1 ;;
    --block-check) blocks+=("${2:?}"); shift ;;
    --no-approval) no_approval=1 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[[ "$pin" =~ ^[0-9a-f]{40}$ ]] || { echo "HEAD_SHA must be the full 40-hex sha" >&2; exit 2; }
case "$method" in squash|merge|rebase) ;; *) echo "bad --method $method" >&2; exit 2 ;; esac
[[ "$slug" =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$ && "${slug#*/}" != . && "${slug#*/}" != .. && "$pr" =~ ^[1-9][0-9]*$ ]] ||
  { echo "OWNER/REPO and a positive PR number required" >&2; exit 2; }
[[ "$min_req" =~ ^[1-9][0-9]*$ ]] || { echo "--min-required must be positive" >&2; exit 2; }
approval_token() {
  printf '%s\0' pr_merge "$slug" "$pr" "$pin" "$method" "$min_req" "$strict" "$no_approval" "${blocks[@]+"${blocks[@]}"}" |
    git -C "$here" hash-object --stdin
}
authorize() {
  local mode
  mode="$("$here/../../project-profile/scripts/action-mode.sh" pr_merge --repo "$slug")" || return
  if [ -n "$approval" ] && [ "$approval" != "$(approval_token)" ]; then
    echo "pr_merge: approval does not match this preview" >&2; return 2
  fi
  case "${mode%% *}" in
    auto) ;;
    ask) if [ "$watch" = 0 ] && [ -n "$approval" ]; then return 0; fi
         echo "pr_merge=ask: approve the exact merge preview; --watch is auto only" >&2
         return 2 ;;
    *) echo "No merge: pr_merge=${mode%% *}" >&2; return 2 ;;
  esac
}
if [ "$merge" = 1 ]; then
  authorize || exit $?
elif [ -n "$approval" ]; then
  echo "--approve requires --merge" >&2; exit 2
fi
owner="${slug%%/*}"; repo="${slug#*/}"
state_dir="${MAINTAINER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/maintainer-skills}/$owner/$repo"
ts() { date -u +%FT%TZ; }

ledger() {  # json object
  mkdir -p "$state_dir"
  local line; line="$(jq -c --arg ts "$(ts)" '{ts:$ts} + .' <<<"$1")"
  ( flock 9; printf '%s\n' "$line" >> "$state_dir/ledger.jsonl" ) 9>"$state_dir/.ledger.lock"
}

last=""
defer() { verdict='wait'; reason=$1; }
evaluate() {  # sets verdict: ready | wait | terminal, and reason
  local s
  s="$("$here/pr-state.sh" "$slug" "$pr" --json 2>/dev/null)" || { defer "GitHub read failed"; return; }
  local st head draft rd ms mg reqn reqp unres chg failing_req appr
  st="$(jq -r .state <<<"$s")"; head="$(jq -r .head <<<"$s")"; draft="$(jq -r .draft <<<"$s")"
  rd="$(jq -r '.review_decision // ""' <<<"$s")"; ms="$(jq -r .merge_state <<<"$s")"; mg="$(jq -r .mergeable <<<"$s")"
  appr="$(jq -r --arg h "$pin" '[.approvals[]? | select(.commit == $h) | .login] | join(",")' <<<"$s")"
  reqn="$(jq -r .checks.required <<<"$s")"; reqp="$(jq -r .checks.required_pass <<<"$s")"
  if [ "$strict" = 1 ]; then reqp="$(jq -r .checks.required_success <<<"$s")"; fi
  unres="$(jq -r '.threads.unresolved | length' <<<"$s")"; chg="$(jq -r '.changes_requested | length' <<<"$s")"
  failing_req="$(jq -r '[.checks.failing[] | select(.required) | .workflow + "/" + .name] | join(", ")' <<<"$s")"
  [ "$(jq -r .threads.complete <<<"$s")" = true ] || unres="100+"

  if [ "$st" != OPEN ]; then
    verdict=terminal; reason="state $st"; [ "$st" = MERGED ] && verdict=merged; return 0
  fi
  if [ "$head" != "$pin" ]; then
    verdict=terminal; reason="head moved to $head"; return
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
  case "$rd" in
    APPROVED) [ -n "$appr" ] || { defer "no approval on head ${pin:0:12} (approvals on older commits do not count)"; return; } ;;
    "") [ "$no_approval" = 1 ] || { defer "review decision none"; return; } ;;
    *) defer "review decision $rd"; return ;;
  esac
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
      if [ "$merge" = 0 ]; then
        echo "$(ts) #$pr READY at ${pin:0:12}: $reason (dry run; pass --merge)"
        printf 'Merge %s#%s at %s using %s (min_required=%s require_success=%s no_approval=%s)\n' \
          "$slug" "$pr" "$pin" "$method" "$min_req" "$strict" "$no_approval"
        for b in "${blocks[@]+"${blocks[@]}"}"; do printf 'Extra blocking check: %s\n' "$b"; done
        echo "Approval token: $(approval_token)"
        exit 0
      fi
      # Re-read once more right before merging, so a comment posted during the poll still blocks.
      evaluate
      case "$verdict" in
        merged) echo "$(ts) #$pr already merged"; exit 0 ;;
        terminal) echo "$(ts) #$pr STOP: $reason"; exit 1 ;;
        wait) if [ "$watch" = 0 ]; then echo "$(ts) #$pr NOT READY: $reason"; exit 3; fi ;;
      esac
      if [ "$verdict" = ready ]; then
        authorize || exit $?
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
