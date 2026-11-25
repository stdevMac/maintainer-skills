#!/usr/bin/env bash
# Shared helpers for tests/test-*.sh. Source it, define test_* functions, then call run_tests.
# Each test_* runs in its own subshell with `set -euo pipefail`, inside a fresh temp directory ($T), with
# a fake `gh` first on PATH, an isolated git config, and MAINTAINER_STATE under $T. The first failing
# assertion ends that test; run_tests prints "ok NAME" or "FAIL NAME" plus the test's output, and exits 1
# if any test failed. Pass test names as arguments to run only those.
#
# Fake gh: every call is logged as one JSON array of its arguments to $FAKE_GH_LOG. Answers come from
# routes, tried in the order they were added; the first route whose extended regex matches the arguments
# joined by single spaces wins. A route registered with gh_route_once is used for one call only. A call
# with no route fails (exit 97) and is logged with "unrouted" so tests can assert on it. When the call
# carries --jq/-q EXPR, the fake applies `jq -r EXPR` to the fixture, like gh does.
# shellcheck disable=SC2034  # variables here are read by the sourcing test files

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

fail() { echo "  assertion failed: $*" >&2; return 1; }

assert_eq() {  # expected actual [message]
  [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$1] got [$2]"
}
assert_rc() {  # expected_rc [message]; checks $RC from run
  [ "$RC" = "$1" ] || { printf '%s\n' "$OUT" >&2; fail "${2:-exit code}: expected $1 got $RC"; }
}
assert_contains() {  # haystack needle [message]
  case "$1" in *"$2"*) ;; *) printf '%s\n' "$1" >&2; fail "${3:-output} does not contain [$2]" ;; esac
}
assert_not_contains() {  # haystack needle [message]
  case "$1" in *"$2"*) printf '%s\n' "$1" >&2; fail "${3:-output} contains [$2]" ;; *) ;; esac
}
assert_match() {  # haystack ERE [message]
  grep -qE -- "$2" <<<"$1" || { printf '%s\n' "$1" >&2; fail "${3:-output} does not match /$2/"; }
}
assert_file() { [ -e "$1" ] || fail "missing file $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "unexpected file $1"; }

# run CMD...: sets RC and OUT (stdout and stderr together) without tripping set -e.
run() { OUT="$("$@" 2>&1)" && RC=0 || RC=$?; }

# Snapshot of a directory tree: path, mode and sha256 of every file except .git internals.
tree_digest() {
  (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print0 | sort -z \
    | xargs -0 -r stat -c '%n %a' | while read -r p m; do printf '%s %s %s\n' "$p" "$m" "$(sha256sum < "$p" | cut -c1-64)"; done)
}

# ---- fake gh ----------------------------------------------------------------------------------------
fake_gh_setup() {
  mkdir -p "$T/bin" "$T/gh"
  ln -sf "$TESTS_DIR/fakes/gh" "$T/bin/gh"
  export FAKE_GH_ROUTES="$T/gh/routes.tsv" FAKE_GH_LOG="$T/gh/calls.jsonl"
  : > "$FAKE_GH_ROUTES"; : > "$FAKE_GH_LOG"
  export PATH="$T/bin:$PATH"
}
_gh_fixture() {  # body -> fixture path
  local f; f="$(mktemp "$T/gh/fixture.XXXXXX")"; printf '%s\n' "$1" > "$f"; echo "$f"
}
gh_route()      { printf 'always\t%s\t%s\t%s\n' "$1" "$(_gh_fixture "$2")" "${3:-0}" >> "$FAKE_GH_ROUTES"; }
gh_route_once() { printf 'once\t%s\t%s\t%s\n' "$1" "$(_gh_fixture "$2")" "${3:-0}" >> "$FAKE_GH_ROUTES"; }
gh_route_file() { printf 'always\t%s\t%s\t%s\n' "$1" "$2" "${3:-0}" >> "$FAKE_GH_ROUTES"; }
# Routes added later are tried later; gh_route_first puts a route ahead of all others.
gh_route_first() {
  local t; t="$(mktemp "$T/gh/routes.XXXXXX")"
  { printf '%s\t%s\t%s\t%s\n' "${4:-always}" "$1" "$(_gh_fixture "$2")" "${3:-0}"; cat "$FAKE_GH_ROUTES"; } > "$t"
  mv "$t" "$FAKE_GH_ROUTES"
}

# Calls that change something on GitHub, one JSON array per line.
GH_WRITE_FILTER='
  def sub1: .[1] // "";
  def method: (index("-X") // index("--method")) as $i | if $i then .[$i+1] | ascii_upcase else null end;
  def has_fields: any(.[]; IN("-f","-F","--field","--raw-field","--input") or startswith("--field=") or startswith("--raw-field="));
  select(
    (.[0] == "api" and (
        any(.[]; test("\\bmutation\\b"))
        or ((method // "GET") != "GET")
        or (method == null and (any(.[]; . == "graphql") | not) and has_fields)))
    or (.[0] == "pr" and (sub1 | IN("merge","comment","review","close","reopen","edit","create","ready","lock","unlock")))
    or (.[0] == "issue" and (sub1 | IN("comment","close","reopen","edit","create","delete","lock","unlock","transfer","pin","unpin","develop")))
    or (.[0] == "run" and (sub1 | IN("rerun","cancel","delete")))
    or (.[0] == "workflow" and (sub1 | IN("run","enable","disable")))
    or (.[0] == "release" and (sub1 | IN("create","edit","delete","upload","delete-asset")))
    or (.[0] == "label" and (sub1 | IN("create","edit","delete","clone")))
    or (.[0] == "repo" and (sub1 | IN("create","edit","delete","fork","sync","rename","archive","unarchive")))
    or ((.[0] | IN("secret","variable","cache")) and (sub1 | IN("set","delete")))
  ) | tostring'
gh_calls()  { jq -c 'del(.[] | select(. == "unrouted"))' "$FAKE_GH_LOG"; }
gh_writes() { jq -r "$GH_WRITE_FILTER" "$FAKE_GH_LOG"; }
assert_no_gh_writes() {
  local w; w="$(gh_writes)"
  [ -z "$w" ] || fail "unexpected GitHub write call(s): $w"
}
assert_no_unrouted() {
  local u; u="$(jq -c 'select(any(.[]; . == "unrouted"))' "$FAKE_GH_LOG")"
  [ -z "$u" ] || fail "gh called without a route: $u"
}
# assert_gh_called ERE: some call, arguments joined by spaces, matches.
assert_gh_called() {
  jq -r 'join(" ")' "$FAKE_GH_LOG" | grep -qE -- "$1" || { gh_calls >&2; fail "no gh call matches /$1/"; }
}
assert_gh_not_called() {
  ! jq -r 'join(" ")' "$FAKE_GH_LOG" | grep -qE -- "$1" || { gh_calls >&2; fail "a gh call matches /$1/"; }
}

# ---- git --------------------------------------------------------------------------------------------
git_isolate() {
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
  printf '[user]\n\tname = Test\n\temail = test@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$GIT_CONFIG_GLOBAL"
}

# ---- runner -----------------------------------------------------------------------------------------
run_tests() {
  local names=() t rc out failed=0 passed=0 tmp_root
  if [ $# -gt 0 ]; then names=("$@"); else mapfile -t names < <(declare -F | awk '$3 ~ /^test_/ {print $3}'); fi
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/maintainer-tests.XXXXXX")"
  for t in "${names[@]}"; do
    out="$tmp_root/$t.out"
    (
      set -euo pipefail
      T="$tmp_root/$t"; mkdir -p "$T"; cd "$T"
      export MAINTAINER_STATE="$T/state" HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state"
      unset MAINTAINER_PROFILE MAINTAINER_ACTIONS MAINTAINER_WORKTREES CODEX_HOME
      mkdir -p "$HOME"
      git_isolate
      fake_gh_setup
      "$t"
    ) > "$out" 2>&1
    rc=$?
    if [ $rc = 0 ]; then echo "ok   $t"; passed=$((passed + 1))
    else echo "FAIL $t"; sed 's/^/     /' "$out"; failed=$((failed + 1)); fi
  done
  rm -rf "$tmp_root"
  echo "$(basename "$0"): $passed passed, $failed failed"
  [ $failed = 0 ]
}
