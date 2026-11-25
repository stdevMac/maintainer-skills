#!/usr/bin/env bash
# Run the test suite: every tests/test-*.sh, each as its own bash process. No dependencies beyond bash 4+,
# git, jq and coreutils; GitHub is never contacted (tests put a fake gh first on PATH).
# Usage: tests/run.sh [test-file-name ...]     e.g. tests/run.sh test-merge-when-green.sh
#
# Convention for a test file tests/test-<thing>.sh:
#   - standalone: `bash tests/test-<thing>.sh [test_name ...]` works on its own;
#   - exits non-zero when any case fails and prints the failing case names;
#   - usually: `. "$(dirname "$0")/lib.sh"`, one function per case named test_<what_it_checks>, and
#     `run_tests "$@"` at the end. lib.sh gives each case a temp dir ($T), isolated HOME, git config and
#     MAINTAINER_STATE, a fake gh with call log (gh_route, assert_no_gh_writes, assert_gh_called), and
#     assertions (assert_eq, assert_rc after run, assert_contains, assert_match, ...).
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
cd "$(dirname "${BASH_SOURCE[0]}")"

files=()
if [ $# -gt 0 ]; then files=("$@"); else for f in test-*.sh; do [ -f "$f" ] && files+=("$f"); done; fi
[ ${#files[@]} -gt 0 ] || { echo "no test files" >&2; exit 2; }

failed=()
summary=()
for f in "${files[@]}"; do
  f="$(basename "$f")"
  echo "== $f"
  start=$SECONDS
  if bash "$f"; then summary+=("PASS  $f ($((SECONDS - start))s)")
  else summary+=("FAIL  $f ($((SECONDS - start))s)"); failed+=("$f"); fi
done

echo
echo "Summary:"
printf '  %s\n' "${summary[@]}"
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all ${#files[@]} test files passed"
