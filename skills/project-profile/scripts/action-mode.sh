#!/usr/bin/env bash
# Resolve the mode of a public action: off, draft, ask or auto. Read-only.
# Usage: action-mode.sh ACTION [--profile FILE] [--repo OWNER/REPO]
#        action-mode.sh --list [--profile FILE] [--repo OWNER/REPO]
# Prints "MODE SOURCE[ NOTES]" (SOURCE: env, profile or default); --list prints "ACTION MODE SOURCE[ NOTES]"
# for every action. First match wins:
#   1. $MAINTAINER_ACTIONS, comma list of action=mode; "*=mode" covers every action not named
#   2. the profile's "## Actions" table (| Action | Mode | Notes |; a "*" row covers the rest)
#   3. draft
# Profile: --profile, else $MAINTAINER_PROFILE, else
# ${XDG_CONFIG_HOME:-~/.config}/maintainer-skills/profiles/<owner>__<repo>.md.
# OWNER/REPO defaults to the checkout's origin. A checked-in profile cannot authorize public writes.
# Exit 2 on an unknown action or an invalid mode.
set -euo pipefail

actions=(push_branch pr_open pr_ready issue_comment issue_close issue_create labels pr_review thread_reply
         pr_merge ci_dispatch ci_rerun)
usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "action-mode.sh: $1" >&2; exit 2; }
known() { local a; for a in "${actions[@]}"; do [ "$a" = "$1" ] && return 0; done; return 1; }
valid_mode() { case "$1" in off|draft|ask|auto) return 0 ;; *) return 1 ;; esac; }

action=""; list=0; profile=""; slug=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list=1 ;;
    --profile) profile="${2:?--profile needs a file}"; shift ;;
    --repo) slug="${2:?--repo needs OWNER/REPO}"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown argument $1" ;;
    *) [ -z "$action" ] || die "one ACTION only"; action="$1" ;;
  esac
  shift
done
[ $list = 1 ] || [ -n "$action" ] || { usage >&2; exit 2; }
[ $list = 1 ] || known "$action" || die "unknown action '$action' (known: ${actions[*]})"

# ---- profile lookup
origin_slug() {
  local url; url="$(git remote get-url origin 2>/dev/null)" || return 0
  url="${url%.git}"; url="${url%/}"
  [[ "$url" =~ ([^/:]+)/([^/:]+)$ ]] && echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
}
if [ -z "$profile" ]; then
  here_slug="$(origin_slug || true)"
  [ -n "$slug" ] || slug="$here_slug"
  if [ -n "${MAINTAINER_PROFILE:-}" ]; then
    profile="$MAINTAINER_PROFILE"
  elif [ -n "$slug" ]; then
    [[ "$slug" =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$ && "${slug#*/}" != . && "${slug#*/}" != .. ]] ||
      die "OWNER/REPO expected"
    f="${XDG_CONFIG_HOME:-$HOME/.config}/maintainer-skills/profiles/${slug%%/*}__${slug#*/}.md"
    [ -f "$f" ] && profile="$f"
  fi
fi
[ -z "$profile" ] || [ -f "$profile" ] || die "profile not found: $profile"

# ---- the profile's Actions table: "action<TAB>mode<TAB>notes" per row
declare -A p_mode=() p_notes=()
if [ -n "$profile" ]; then
  while IFS=$'\t' read -r a m notes; do
    valid_mode "$m" || die "$profile: Actions row '$a' has mode '$m' (want off, draft, ask or auto)"
    [ "$a" = "*" ] || known "$a" || die "$profile: unknown action '$a'"
    p_mode[$a]="$m"; p_notes[$a]="$notes"
  done < <(awk '
    function trim(s) { gsub(/`/, "", s); gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
    /^## / { h = tolower($0); sub(/^##[ \t]+/, "", h); sub(/^[0-9]+\.?[ \t]+/, "", h); sub(/[ \t\r]+$/, "", h)
             ins = (h == "actions"); next }
    !ins || !/^[ \t]*\|/ { next }
    {
      line = $0; sub(/^[ \t]*\|/, "", line); sub(/\|[ \t\r]*$/, "", line)
      n = split(line, c, "|")
      a = trim(c[1]); m = tolower(trim(c[2])); notes = ""
      for (i = 3; i <= n; i++) notes = notes (i > 3 ? "|" : "") c[i]
      gsub(/^[ \t]+|[ \t]+$/, "", notes)
      if (a == "" || tolower(a) == "action" || a ~ /^:?-+:?$/) next
      print a "\t" m "\t" notes
    }' "$profile")
fi

# ---- the environment override
declare -A e_mode=()
IFS=',' read -r -a pairs <<<"${MAINTAINER_ACTIONS:-}"
for kv in "${pairs[@]+"${pairs[@]}"}"; do
  kv="${kv//[[:space:]]/}"; [ -n "$kv" ] || continue
  [[ "$kv" == *=* ]] || die "MAINTAINER_ACTIONS: '$kv' is not action=mode"
  a="${kv%%=*}"; m="${kv#*=}"
  valid_mode "$m" || die "MAINTAINER_ACTIONS: '$kv' has mode '$m' (want off, draft, ask or auto)"
  [ "$a" = "*" ] || known "$a" || die "MAINTAINER_ACTIONS: unknown action '$a'"
  e_mode[$a]="$m"
done

resolve() {  # action -> "mode source[ notes]"
  local a="$1" k
  for k in "$a" "*"; do [ -n "${e_mode[$k]:-}" ] && { echo "${e_mode[$k]} env"; return; }; done
  for k in "$a" "*"; do
    [ -n "${p_mode[$k]:-}" ] && { echo "${p_mode[$k]} profile${p_notes[$k]:+ ${p_notes[$k]}}"; return; }
  done
  echo "draft default"
}

if [ $list = 1 ]; then
  echo "profile: ${profile:-none}" >&2
  for a in "${actions[@]}"; do echo "$a $(resolve "$a")"; done
else
  resolve "$action"
fi
