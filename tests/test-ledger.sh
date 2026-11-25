#!/usr/bin/env bash
# Tests for skills/maintainer-loop/scripts/ledger.sh: append, skip list, legacy field aliases, dispatch
# usage, and concurrent appends through two paths to one ledger.
# Usage: bash tests/test-ledger.sh [test_name ...]
# shellcheck disable=SC2329  # test_* functions are called by run_tests
. "$(dirname "$0")/lib.sh"

L="$REPO_ROOT/skills/maintainer-loop/scripts/ledger.sh"
S=acme/widget

seed() {  # lines... : write them as the ledger
  mkdir -p "$MAINTAINER_STATE/$S"
  printf '%s\n' "$@" > "$MAINTAINER_STATE/$S/ledger.jsonl"
}

test_usage_and_bad_arguments() {
  run "$L" -h; assert_rc 0; assert_contains "$OUT" "dispatch-usage"
  run "$L" not-a-slug status; assert_rc 2
  run "$L" "$S" frobnicate; assert_rc 2
  run "$L" "$S" dispatch-usage --round x; assert_rc 2
  run "$L" "$S" dispatch-usage --since yesterday; assert_rc 2
  run "$L" "$S" show abc; assert_rc 2
}

test_append_adds_ts_and_requires_a_string_event() {
  run "$L" "$S" append '{"event":"selected","number":7,"round":1}'; assert_rc 0
  assert_match "$OUT" '^\{"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z","event":"selected","number":7,"round":1\}$'
  local bad
  for bad in '{"number":7}' '{"event":null,"number":7}' '[1]' 'not json'; do
    run "$L" "$S" append "$bad"
    [ "$RC" -ne 0 ] || fail "append accepted $bad"
  done
  assert_eq 1 "$(wc -l < "$MAINTAINER_STATE/$S/ledger.jsonl")"
}

test_skiplist_terminal_reopen_and_retry_after() {
  seed '{"event":"terminal","number":1,"state":"done"}' \
       '{"event":"terminal","number":2,"state":"done"}' \
       '{"event":"reopen","number":2,"why":"regressed"}' \
       '{"event":"terminal","number":3,"state":"cannot_repro","retry_after":"2000-01-01T00:00:00Z"}' \
       '{"event":"terminal","number":4,"state":"needs_env","retry_after":"2999-01-01T00:00:00Z"}' \
       '{"event":"triaged","number":5,"verdict":"needs_fix"}'
  assert_eq "$(printf '1\n4')" "$("$L" "$S" skiplist)"
}

test_legacy_issue_field_is_read_as_number() {
  seed '{"event":"terminal","issue":10,"state":"done"}' \
       '{"event":"terminal","issue":11,"state":"done"}' \
       '{"event":"reopen","issue":11}' \
       '{"event":"terminal","number":12,"issue":99,"state":"in_review"}' \
       '{"stage":"refute","issue":10,"refuted":false}'
  assert_eq "$(printf '10\n12')" "$("$L" "$S" skiplist)"
  run "$L" "$S" status; assert_rc 0
  assert_eq 3 "$(jq .numbers_seen <<<"$OUT")" "numbers_seen"
  assert_eq '{"done":1,"in_review":1}' "$(jq -c .terminal <<<"$OUT")"
  assert_eq 1 "$(jq .events.none <<<"$OUT")" "an event without a name is counted as none"
  assert_eq 2 "$("$L" "$S" show 10 | wc -l)"
}

test_events_about_another_repository_are_ignored() {
  seed '{"event":"filed","issue":null,"repo":"other/thing","number":12}' \
       '{"event":"terminal","repo":"other/thing","number":13,"state":"done"}' \
       '{"event":"filed","issue":null,"repo":"acme/widget","number":14}'
  assert_eq "" "$("$L" "$S" skiplist)"
  assert_eq 1 "$("$L" "$S" status | jq .numbers_seen)"
  assert_eq "" "$("$L" "$S" show 12)"
  assert_eq 1 "$("$L" "$S" show 14 | wc -l)"
}

test_show_includes_events_whose_pr_is_the_number() {
  seed '{"event":"pr_opened","issue":20,"pr":30}' \
       '{"event":"review_requested","issue":null,"pr":30}' \
       '{"event":"merged","kind":"pr","number":30}' \
       '{"event":"selected","number":31}'
  assert_eq 3 "$("$L" "$S" show 30 | wc -l)"
  assert_eq 1 "$("$L" "$S" show 20 | wc -l)"
}

test_next_round() {
  run "$L" "$S" next-round; assert_eq 1 "$OUT" "empty ledger"
  seed '{"event":"selected","number":1,"round":3}' '{"event":"note"}' '{"event":"selected","number":2,"round":7}'
  assert_eq 8 "$("$L" "$S" next-round)"
}

test_dispatch_usage_counts_dispatch_and_legacy_events() {
  seed '{"ts":"2026-01-01T00:00:00Z","event":"dispatch_intent","number":1,"round":1,"workflow":"hive"}' \
       '{"ts":"2026-01-01T00:01:00Z","event":"dispatch","number":1,"round":1,"workflow":"hive","run_id":11,"ref":"fix/1","est_minutes":45,"cost_class":"ci"}' \
       '{"ts":"2026-01-01T00:02:00Z","event":"dispatch","number":2,"round":1,"workflow":"node","run_id":12,"ref":"fix/2","est_minutes":180,"cost_class":"vm"}' \
       '{"ts":"2026-01-02T00:00:00Z","event":"retest_dispatch","issue":3,"round":2,"workflow":"scenario","run_id":13}' \
       '{"ts":"2026-01-02T00:01:00Z","event":"retest_dispatch_intent","issue":4,"round":2}' \
       '{"ts":"2026-01-02T00:02:00Z","event":"retest_dispatch_pending","issue":4,"round":2}' \
       '{"ts":"2026-01-02T00:03:00Z","event":"retest_dispatched","issue":5,"round":2,"run_id":14}' \
       '{"ts":"2026-01-03T00:00:00Z","event":"rerun","number":6,"round":3,"run_id":15}'
  run "$L" "$S" dispatch-usage; assert_rc 0
  assert_eq '{"scope":{},"runs":4,"ci_runs":3,"vm_runs":1,"ci_minutes":45,"vm_minutes":180,"runs_without_estimate":2,"by_class":{"ci":3,"vm":1},"by_workflow":{"hive":1,"node":1,"scenario":1,"unknown":1}}' "$(jq -c . <<<"$OUT")"
  assert_eq '2 1 1' "$("$L" "$S" dispatch-usage --round 1 | jq -r '"\(.runs) \(.ci_runs) \(.vm_runs)"')"
  assert_eq 2 "$("$L" "$S" dispatch-usage --round 2 | jq .runs)"
  assert_eq 2 "$("$L" "$S" dispatch-usage --since 2026-01-02 | jq .runs)"
  assert_eq 1 "$("$L" "$S" dispatch-usage --round 2 --since 2026-01-02T00:02:30Z | jq .runs)"
  assert_eq 0 "$("$L" "$S" dispatch-usage --round 3 | jq .runs)" "a CI rerun is not a dispatch"
}

test_concurrent_appends_through_a_symlinked_state_dir_land_in_one_file() {
  # Two entry points to one ledger: the state dir and a second state root whose OWNER/REPO directory is
  # a symlink to it (how a project keeps an older state directory). Both take the same .ledger.lock, so
  # no line is lost or interleaved.
  local real="$MAINTAINER_STATE/$S" pad i
  mkdir -p "$real" "$T/other/acme"
  ln -s "$real" "$T/other/acme/widget"
  pad="$(printf 'x%.0s' $(seq 1 3000))"
  for i in $(seq 1 40); do
    "$L" "$S" append "{\"event\":\"note\",\"number\":$i,\"pad\":\"$pad\"}" >/dev/null &
    MAINTAINER_STATE="$T/other" "$L" "$S" append "{\"event\":\"note\",\"number\":$((i + 100)),\"pad\":\"$pad\"}" >/dev/null &
  done
  wait
  assert_eq "$(realpath "$real/ledger.jsonl")" "$(realpath "$(MAINTAINER_STATE="$T/other" "$L" "$S" path)")"
  assert_eq 80 "$(wc -l < "$real/ledger.jsonl")"
  assert_eq 80 "$(jq -c . "$real/ledger.jsonl" | wc -l)" "every line is valid JSON"
  assert_eq 80 "$(jq -r .number "$real/ledger.jsonl" | sort -u | wc -l)"
  assert_eq "" "$(MAINTAINER_STATE="$T/other" "$L" "$S" skiplist)"
}

run_tests "$@"
