#!/usr/bin/env bash
set -euo pipefail
file=secrets/hosts/software-factory.yaml
key_file=/var/lib/sops-age/keys.txt

if grep -qF 'age-key: not generated yet' .sops.yaml; then
  echo "ERROR: run 'just operator-age-key' and 'just factory-generate-age-key'" >&2
  echo "first, or nobody could decrypt these secrets." >&2
  exit 1
fi

just set-password-hash software-factory

sudo -v
export SOPS_AGE_KEY_CMD="sudo -n cat $key_file"

# sops wants the value as JSON; jq -Rs quotes and escapes it.
put() { jq -Rs . | sops set --value-stdin "$file" "[\"$1\"]"; }
set_secret() {
  local name="$1" prompt="$2" value
  read -rsp "$prompt: " value
  echo
  [ -n "$value" ] || {
    echo "ERROR: $name is empty." >&2
    exit 1
  }
  printf '%s' "$value" | put "$name"
  echo "Wrote $name."
}

echo "Tailscale admin console > Settings > Keys: a one-off, pre-approved auth key"
echo "tagged tag:factory. Apply tailscale/policy.hujson first (just tailscale-apply)."
set_secret tailscale-authkey "Tailscale auth key"

echo "infernowork97 > Settings > Developer settings > Tokens (classic):"
echo "scopes 'repo', 'workflow' and 'read:org'."
set_secret gh-token "GitHub token (ghp_...)"

# An environment file for NetworkManager's Wi-Fi profile (omen.nix).
# Single-quoted, so the values may hold anything but a quote or a newline.
read -rp "Wi-Fi SSID: " ssid
read -rsp "Wi-Fi password: " psk
echo
case "$ssid$psk" in
  *"'"* | *$'\n'*)
    echo "ERROR: the SSID or password contains a single quote or newline." >&2
    exit 1
    ;;
  *) ;;
esac
[ -n "$ssid" ] && [ -n "$psk" ] || {
  echo "ERROR: empty SSID or password." >&2
  exit 1
}
printf "WIFI_SSID='%s'\nWIFI_PSK='%s'\n" "$ssid" "$psk" | put wifi-env
unset psk
echo "Wrote wifi-env."

printf 'unused' | put example-global

# The global probe (modules/secrets.nix), encrypted to the operator key
# alone. The box reads its own copy from $file; this one keeps the global
# scope exercised for any host added later.
if [ ! -f secrets/common.yaml ]; then
  printf '{"example-global": "unused"}\n' | sops -e --input-type json --output-type yaml \
    --filename-override secrets/common.yaml /dev/stdin >secrets/common.yaml.tmp
  mv secrets/common.yaml.tmp secrets/common.yaml
  echo "Created secrets/common.yaml."
fi

just factory-deploy-token
echo "Done. Commit .sops.yaml, secrets/common.yaml and $file."
