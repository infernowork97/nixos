#!/usr/bin/env bats
# shellcheck disable=SC2154,SC2312 # test_helper and check.nix set the variables, and a masked failure fails the assertion around it

load ../test_helper

# factory-ctl reads the copies factory-crash-log writes to $work/ops/crash.

# A dump $1 with part $2, its dmesg.txt 100 numbered lines dated $3.
add_dump() {
  mkdir -p "$work/pstore/$1/$2"
  seq -f "$1 line %g" 100 >"$work/pstore/$1/$2/dmesg.txt"
  touch -d "$3" "$work/pstore/$1/$2/dmesg.txt"
}

@test "crash-log: no dumps, before or after the copy, is not an error" {
  factory-ctl crash-log | grep -q "No kernel crash dumps saved." || fail "crash-log did not say there are none"

  factory-crash-log

  factory-ctl crash-log | grep -q "No kernel crash dumps saved." || fail "an empty pstore left a dump"
}

@test "crash-log: lists the dumps newest first and shows the newest one's last 80 lines" {
  add_dump 1700000000 001 '3 days ago'
  add_dump 1700000000 002 '2 days ago'
  add_dump 1800000000 001 '1 hour ago'
  factory-crash-log

  factory-ctl crash-log >"$work/out"

  [ "$(sed -n 's/^  \([^ ]*\.txt\)  .*/\1/p' "$work/out" | paste -sd ' ')" = "1800000000-001.txt 1700000000-002.txt 1700000000-001.txt" ] ||
    fail_showing "$work/out" "the dumps are not listed newest first"
  { grep -qxF "1800000000 line 21" "$work/out" && grep -qxF "1800000000 line 100" "$work/out"; } ||
    fail_showing "$work/out" "the newest dump's tail is missing"
  ! grep -qxF "1800000000 line 20" "$work/out" || fail "more than 80 lines were shown"
  ! grep -q "^1700000000 line" "$work/out" || fail "an older dump's content was shown"
}
