#!/usr/bin/env bash
# Append-only ledger of maintainer actions for one repository (JSON lines, flock-guarded).
# Usage:
#   ledger.sh OWNER/REPO append JSON     add ts (UTC) to the object and append it; prints the line
#   ledger.sh OWNER/REPO show N          every event for issue or PR number N (also events whose pr is N)
#   ledger.sh OWNER/REPO status          counts by latest terminal state and by event
#   ledger.sh OWNER/REPO skiplist        numbers whose latest terminal state is still in force
#   ledger.sh OWNER/REPO next-round      max(round) + 1
#   ledger.sh OWNER/REPO dispatch-usage [--round N] [--since ISO8601]
#                                        workflow dispatches: runs, CI and VM runs, estimated minutes
#   ledger.sh OWNER/REPO path            the ledger file path
# File: ${MAINTAINER_STATE:-${XDG_STATE_HOME:-~/.local/state}/maintainer-skills}/OWNER/REPO/ledger.jsonl
# Events carry at least {event, number} and usually {kind: "issue"|"pr", round}. A terminal event is
# {event:"terminal", state:"...", retry_after?: ISO8601}; a later {event:"reopen"} lifts it.
# Older ledgers: "issue" is read as "number" when "number" is absent; an event whose "repo" names another
# repository is not about this repository's numbers; "<x>_dispatch" and "<x>_dispatched" count as dispatch.
set -euo pipefail

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
slug="$1"; cmd="${2:-status}"; shift 2 || true
[[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "OWNER/REPO expected" >&2; exit 2; }
dir="${MAINTAINER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/maintainer-skills}/$slug"
file="$dir/ledger.jsonl"; lock="$dir/.ledger.lock"
input="$file"; [ -e "$file" ] || input=/dev/null
# The number an event is about, or null. Shared by every reader below.
defs='def num: if (.repo // $slug) != $slug then null else (.number // .issue) end;'

case "$cmd" in
  append)
    obj="${1:?JSON object}"
    line="$(jq -ce --arg ts "$(date -u +%FT%TZ)" 'if type=="object" and (.event|type)=="string" then {ts:$ts} + . else error("need an object with a string event") end' <<<"$obj")"
    mkdir -p "$dir"
    ( flock 9; printf '%s\n' "$line" >> "$file" ) 9>"$lock"
    echo "$line"
    ;;
  show)
    n="${1:?number}"
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "number expected" >&2; exit 2; }
    jq -c --arg slug "$slug" --argjson n "$n" "$defs"' select((.repo // $slug) == $slug and (num==$n or .pr==$n))' "$input"
    ;;
  status)
    jq -s --arg slug "$slug" "$defs"'
      ([.[] | select(num != null and (.event=="terminal" or .event=="reopen"))] | group_by(num) | map(last)
        | map(select(.event=="terminal")) | group_by(.state) | map({(.[0].state // "unknown"): length}) | add // {}) as $t
      | {numbers_seen: ([.[] | num | select(. != null)] | unique | length),
         terminal: $t,
         events: ([.[] | .event // "none"] | group_by(.) | map({(.[0]): length}) | add // {})}' "$input"
    ;;
  skiplist)
    jq -rs --arg slug "$slug" --arg now "$(date -u +%FT%TZ)" "$defs"'
      [.[] | select(num != null and (.event=="terminal" or .event=="reopen"))]
      | group_by(num) | map(last)
      | map(select(.event=="terminal" and ((.retry_after // "9999") > $now))) | .[] | num' "$input" | sort -n
    ;;
  next-round)
    jq -s '([.[] | .round // 0] | max // 0) + 1' "$input"
    ;;
  dispatch-usage)
    round=null; since=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --round) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "--round needs a number" >&2; exit 2; }; round="$2"; shift ;;
        --since) [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || { echo "--since needs an ISO 8601 date" >&2; exit 2; }; since="$2"; shift ;;
        *) echo "unknown argument $1" >&2; exit 2 ;;
      esac
      shift
    done
    # A dispatch without cost_class counts as ci; one without est_minutes is reported, not guessed.
    jq -s --arg slug "$slug" --argjson round "$round" --arg since "$since" '
      [.[] | select((.repo // $slug) == $slug)
           | select((.event // "") | test("^(dispatch|.+_dispatch|.+_dispatched)$"))
           | select($round == null or .round == $round)
           | select($since == "" or (.ts // "") >= $since)
           | .cost_class //= "ci"] as $d
      | def runs(c): [$d[] | select(.cost_class == c)] | length;
        def mins(c): [$d[] | select(.cost_class == c) | .est_minutes // 0] | add // 0;
      {scope: ({round: $round, since: (if $since == "" then null else $since end)} | with_entries(select(.value != null))),
       runs: ($d | length),
       ci_runs: runs("ci"), vm_runs: runs("vm"),
       ci_minutes: mins("ci"), vm_minutes: mins("vm"),
       runs_without_estimate: ([$d[] | select(.est_minutes == null)] | length),
       by_class: ($d | group_by(.cost_class) | map({(.[0].cost_class): length}) | add // {}),
       by_workflow: ($d | group_by(.workflow // "unknown") | map({(.[0].workflow // "unknown"): length}) | add // {})}' "$input"
    ;;
  path) echo "$file" ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
