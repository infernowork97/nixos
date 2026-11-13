#!/usr/bin/env bats
# shellcheck disable=SC2016 # a stub's body expands when the stub runs
# The checks that stand between a wrong box or a wrong key and a wiped disk.
# The install itself is nixos-anywhere's, so its stub only records the call.

load ../../programs/shell-check/test_helper

setup() {
  export WORK="$BATS_TEST_TMPDIR"
  export LOCKDOWN="[none] integrity confidentiality"
  stub ssh 'echo "$LOCKDOWN"'
  stub ssh-keygen ':'
  stub nixos-anywhere 'echo "$*" >"$WORK/install-args"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --extra-files) cp "$2/var/lib/sops-age/keys.txt" "$WORK/installed-key" ;;
        *) ;;
      esac
      shift
    done'
}

# Pastes $2 as the age key.
install_box() { printf '%s\n' "$2" | bash "$BATS_TEST_DIRNAME/factory-install.sh" "$1"; }

# It failed saying $1, and nothing was installed.
refused() {
  [ "$status" -eq 1 ]
  [[ "$output" == *"$1"* ]]
  [ ! -e "$WORK/install-args" ]
}

@test "an IPv4 address and an age key install the box with that key" {
  run install_box 10.0.0.2 AGE-SECRET-KEY-1ABC

  [ "$status" -eq 0 ]
  grep -qF -- '--target-host root@10.0.0.2' "$WORK/install-args"
  grep -qxF AGE-SECRET-KEY-1ABC "$WORK/installed-key"
}

@test "a host name is refused" {
  run install_box software-factory AGE-SECRET-KEY-1ABC

  refused "expected an IPv4 address, got 'software-factory'"
}

@test "an empty address is refused" {
  run install_box "" AGE-SECRET-KEY-1ABC

  refused "expected an IPv4 address"
}

@test "a locked-down kernel is refused before the key is asked for" {
  export LOCKDOWN="none [integrity] confidentiality"

  run install_box 10.0.0.2 AGE-SECRET-KEY-1ABC

  refused "kernel is locked down (none [integrity] confidentiality)"
  [[ "$output" != *"Paste"* ]]
}

@test "a paste that is not an age key is refused" {
  run install_box 10.0.0.2 ssh-ed25519-AAAA

  refused "does not look like an age private key"
}

@test "an empty paste is refused" {
  run install_box 10.0.0.2 ""

  refused "does not look like an age private key"
}
