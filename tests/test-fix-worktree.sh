#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scripts="$root/skills/fix-issue/scripts"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export MAINTAINER_WORKTREES="$tmp/worktrees" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.test GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.test
origin="$tmp/origin"; clone="$tmp/clone"
git init -qb main "$origin"
printf 'wrong\n' > "$origin/value"
git -C "$origin" add value
git -C "$origin" -c commit.gpgsign=false commit -qm base
git clone -q "$origin" "$clone"
wt=$("$scripts/worktree.sh" new "$clone" regression --base origin/main --min-free-gb 0)
cd "$wt"
printf 'right\n' > value
mkdir tests
printf '%s\n' 'grep -Fxq right value || { echo wrong-value; exit 1; }' > tests/value.sh
git add value tests/value.sh
git -c commit.gpgsign=false commit -qm fix
bash tests/value.sh
"$scripts/fail-before.sh" --base origin/main --log "$tmp/before.log" -- bash tests/value.sh
grep -Fxq wrong-value "$tmp/before.log"
bash tests/value.sh
if "$scripts/fail-before.sh" --base origin/main --log "$tmp/weak.log" -- true; then
  echo 'weak regression test was accepted' >&2; exit 1
fi
[[ -z $(git status --porcelain) ]]
printf 'dirty\n' >> value
cd "$tmp"
if "$scripts/worktree.sh" remove "$wt"; then exit 1; fi
[[ -f "$wt/value" ]]
git -C "$wt" restore value
if "$scripts/worktree.sh" remove "$wt"; then exit 1; fi
"$scripts/worktree.sh" remove "$wt" --discard-unpushed
bundles=("$MAINTAINER_WORKTREES"/backups/*.bundle)
git -C "$clone" bundle verify "${bundles[0]}"
[[ ! -e "$wt" ]]
