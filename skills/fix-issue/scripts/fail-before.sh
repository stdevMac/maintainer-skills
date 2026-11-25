#!/usr/bin/env bash
# Prove a regression test catches the bug: put the production files changed since BASE back to their BASE
# versions, run the test command, expect it to fail, then restore the fix exactly.
# Usage: fail-before.sh [--base REF] [--prod "PATH ..."] [--test-pattern REGEX] [--log FILE] -- TEST_COMMAND...
#   --base          default: merge-base of HEAD and origin's default branch
#   --prod          production files to revert (default: changed files not matching --test-pattern)
#   --test-pattern  extended regex for test files; default covers test/spec/fixture dirs and
#                   *_test.*, *.test.*, *.spec.*, test_*.py, *Test(s).<ext>, *.Test(s)/ projects
# Needs a clean worktree (commit the fix first) so the restore is exact.
# Exit: 0 test failed on base (good: read the log to confirm it failed on the bug, not on compilation)
#       1 test passed on base (the test does not catch the bug)
#       2 usage or state error
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
base=""; prod=""; log=""
pattern='(^|/)(tests?|__tests__|specs?|e2e|fixtures?|testdata|test-data)(/|$)|(^|/)test_[^/]*$|_test\.[^/]+$|\.(test|spec)\.[^/]+$|Tests?\.[A-Za-z]+$|\.Tests?(/|$)'
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:?}"; shift ;;
    --prod) prod="${2:?}"; shift ;;
    --test-pattern) pattern="${2:?}"; shift ;;
    --log) log="${2:?}"; shift ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ $# -gt 0 ] || { echo "missing TEST_COMMAND after --" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "not in a git worktree" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)"
[ -z "$(git status --porcelain)" ] || { echo "worktree is dirty; commit the fix first" >&2; exit 2; }

if [ -z "$base" ]; then
  def="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
  base="$def"
fi
base_sha="$(git merge-base HEAD "$base")" || { echo "no merge base with $base" >&2; exit 2; }

if [ -n "$prod" ]; then
  read -r -a files <<<"$prod"
else
  mapfile -t files < <(git diff --no-renames --name-only "$base_sha" HEAD | grep -Ev "$pattern" || true)
fi
[ ${#files[@]} -gt 0 ] || { echo "no production files changed since ${base_sha:0:12}; pass --prod" >&2; exit 2; }

log="${log:-$(mktemp "${TMPDIR:-/tmp}/fail-before.XXXXXX.log")}"
restore() {
  git restore --source=HEAD --worktree -- "${files[@]}" 2>/dev/null || true
  if [ -n "$(git status --porcelain)" ]; then
    echo "WARNING: worktree not clean after restore; inspect with git status" >&2
  fi
}
trap restore EXIT

echo "base ${base_sha:0:12}; reverting ${#files[@]} production file(s):" >&2
printf '  %s\n' "${files[@]}" >&2
git restore --source="$base_sha" --worktree -- "${files[@]}"

set +e
"$@" > "$log" 2>&1
rc=$?
set -e
restore
trap - EXIT

echo "--- last lines of $log" >&2
tail -n 25 "$log" >&2
if [ $rc -ne 0 ]; then
  echo "RESULT: test FAILED on base (exit $rc). Confirm in the log that it failed on the bug's assertion." >&2
  exit 0
fi
echo "RESULT: test PASSED on base. It does not catch the bug (or --prod missed a file)." >&2
exit 1
