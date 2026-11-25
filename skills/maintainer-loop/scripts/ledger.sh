#!/usr/bin/env bash
# Append-only ledger of maintainer actions for one repository (JSON lines, flock-guarded).
# Usage:
#   ledger.sh OWNER/REPO append JSON     add ts (UTC) to the object and append it; prints the line
#   ledger.sh OWNER/REPO show N          every event for issue or PR number N
#   ledger.sh OWNER/REPO status          counts by latest terminal state and by event
#   ledger.sh OWNER/REPO skiplist        numbers whose latest terminal state is still in force
#   ledger.sh OWNER/REPO next-round      max(round) + 1
#   ledger.sh OWNER/REPO path            the ledger file path
# File: ${MAINTAINER_STATE:-${XDG_STATE_HOME:-~/.local/state}/maintainer-skills}/OWNER/REPO/ledger.jsonl
# Events carry at least {event, number} and usually {kind: "issue"|"pr", round}. A terminal event is
# {event:"terminal", state:"...", retry_after?: ISO8601}; a later {event:"reopen"} lifts it.
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
slug="$1"; cmd="${2:-status}"; shift 2 || true
[[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "OWNER/REPO expected" >&2; exit 2; }
dir="${MAINTAINER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/maintainer-skills}/$slug"
file="$dir/ledger.jsonl"; lock="$dir/.ledger.lock"
mkdir -p "$dir"; touch "$file"

case "$cmd" in
  append)
    obj="${1:?JSON object}"
    line="$(jq -ce --arg ts "$(date -u +%FT%TZ)" 'if type=="object" and has("event") then {ts:$ts} + . else error("need an object with event") end' <<<"$obj")"
    ( flock 9; printf '%s\n' "$line" >> "$file" ) 9>"$lock"
    echo "$line"
    ;;
  show)
    n="${1:?number}"
    jq -c --argjson n "$n" 'select(.number==$n)' "$file"
    ;;
  status)
    jq -s '
      ([.[] | select(.number != null and (.event=="terminal" or .event=="reopen"))] | group_by(.number) | map(last)
        | map(select(.event=="terminal")) | group_by(.state) | map({(.[0].state // "unknown"): length}) | add // {}) as $t
      | {numbers_seen: ([.[] | select(.number != null) | .number] | unique | length),
         terminal: $t,
         events: ([.[] | .event] | group_by(.) | map({(.[0]): length}) | add // {})}' "$file"
    ;;
  skiplist)
    jq -rs --arg now "$(date -u +%FT%TZ)" '
      [.[] | select(.number != null and (.event=="terminal" or .event=="reopen"))]
      | group_by(.number) | map(last)
      | map(select(.event=="terminal" and ((.retry_after // "9999") > $now))) | .[].number' "$file" | sort -n
    ;;
  next-round)
    jq -s '([.[] | .round // 0] | max // 0) + 1' "$file"
    ;;
  path) echo "$file" ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
