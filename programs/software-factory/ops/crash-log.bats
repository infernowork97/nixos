#!/usr/bin/env bats
# shellcheck disable=SC2154,SC2312 # test_helper and check.nix set the variables, and a masked failure fails the assertion around it

load ../test_helper

# check.nix builds factory-crash-log with $work/ops as its state directory and
# $work/pstore as systemd-pstore's archive.

# A dump $1 with part $2, its dmesg.txt 100 numbered lines dated $3.
add_dump() {
  mkdir -p "$work/pstore/$1/$2"
  seq -f "$1 line %g" 100 >"$work/pstore/$1/$2/dmesg.txt"
  touch -d "$3" "$work/pstore/$1/$2/dmesg.txt"
}

@test "factory-crash-log: an empty pstore copies nothing" {
  factory-crash-log

  [ -z "$(ls "$work/ops/crash")" ] || fail "copied $(ls "$work/ops/crash")"
}

# Two dumps with the same part number, and a part that is not a merged dmesg.
given_three_dumps() {
  add_dump 1700000000 001 '3 days ago'
  add_dump 1700000000 002 '2 days ago'
  add_dump 1800000000 001 '1 hour ago'
  touch "$work/pstore/1800000000/001/dmesg-efi_pstore-1"
}

copied_exactly_the_three_dumps() {
  [ "$(ls "$work/ops/crash")" = "$(printf '%s\n' 1700000000-001.txt 1700000000-002.txt 1800000000-001.txt)" ] ||
    fail "copied $(ls "$work/ops/crash")"
}

@test "factory-crash-log: copies every part of every dump as is" {
  given_three_dumps

  factory-crash-log

  copied_exactly_the_three_dumps
  cmp -s "$work/pstore/1800000000/001/dmesg.txt" "$work/ops/crash/1800000000-001.txt" || fail "a dump was not copied as is"
}

@test "factory-crash-log: the copies are readable by all" {
  given_three_dumps

  factory-crash-log

  [ "$(stat -c %a "$work/ops/crash" "$work/ops/crash/1700000000-002.txt" | paste -sd ' ')" = "755 644" ] ||
    fail "the copies are not readable by the agent account"
}

@test "factory-crash-log: rerunning is a no-op" {
  given_three_dumps
  factory-crash-log

  factory-crash-log

  copied_exactly_the_three_dumps
}
