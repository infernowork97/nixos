#!/usr/bin/env bash
set -euo pipefail
ip=$1
case "$ip" in
  *[!0-9.]* | "")
    echo "ERROR: expected an IPv4 address, got '$ip'" >&2
    exit 1
    ;;
  *) ;;
esac

# Secure Boot locks the kernel down, and a locked-down kernel refuses to
# kexec the unsigned installer - midway, after the age key was pasted.
lockdown=$(ssh -o ConnectTimeout=10 "root@$ip" 'cat /sys/kernel/security/lockdown 2>/dev/null || echo "[none]"')
case "$lockdown" in
  *"[none]"*) ;;
  *)
    echo "ERROR: the box's kernel is locked down ($lockdown): turn Secure Boot off in its BIOS (F10)." >&2
    exit 1
    ;;
esac

extra=$(mktemp -d)
trap 'rm -rf "$extra"' EXIT
install -d -m 700 "$extra/var/lib/sops-age"

echo "Paste 'software-factory-age-key' from Bitwarden, then press Ctrl-D on a new line:"
(
  umask 077
  cat >"$extra/var/lib/sops-age/keys.txt"
)
grep -q '^AGE-SECRET-KEY-1' "$extra/var/lib/sops-age/keys.txt" || {
  echo "ERROR: does not look like an age private key." >&2
  exit 1
}

# From the factory-install shell when inside it, and otherwise the same
# flake.lock-pinned build.
if command -v nixos-anywhere >/dev/null 2>&1; then
  anywhere=(nixos-anywhere)
else
  anywhere=(nix run --inputs-from . nixpkgs#nixos-anywhere --)
fi

"${anywhere[@]}" \
  --flake .#software-factory \
  --build-on local \
  --extra-files "$extra" \
  --target-host "root@$ip"

# The installed system has a new host key on the same address.
ssh-keygen -R "$ip" >/dev/null 2>&1 || true
echo "Installed. Once software-factory shows in the tailnet, unplug the ethernet"
echo "cable and check it rejoins over Wi-Fi."
