# ─── Software factory ────────────────────────────────────────────────────────
# Recipes for the software-factory box, run on the operator machine (Linux)
# inside `nix develop .#factory-install`. The order of a first install is in
# docs/SOFTWARE-FACTORY.md.
#
# Hosts are reached by their MagicDNS name, so these need Tailscale up on the
# operator machine (`tailscale up`), except factory-install, which talks to the
# box's Ubuntu over the home LAN.
#
# Parameters are declared as `$name`: just passes them as environment variables
# instead of splicing them into the script text, so a hostile argument is inert.
# Secrets are read with `read -s` and travel on stdin, never in argv, where any
# local process could read them from the process list.

# ─── Secrets ─────────────────────────────────────────────────────────────────

# Copies stdin to the clipboard, Wayland or X11; with no input, clears it.
[private]
_clip := 'clip() { if [ -n "${WAYLAND_DISPLAY:-}" ]; then wl-copy; else xclip -selection clipboard; fi; }'

# The operator's own age key: the one that can edit every secrets file. It lives
# root-only at /var/lib/sops-age/keys.txt, where every secrets recipe reads it
# through sudo, and a copy goes to Bitwarden through the clipboard. Only the
# public half is committed, in .sops.yaml.
#
# Generate the operator machine's age key (root-only) and copy it for Bitwarden
operator-age-key:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ _clip }}
    marker='# operator-age-key: not generated yet'
    key_file=/var/lib/sops-age/keys.txt
    grep -qF "$marker" .sops.yaml || {
        echo "ERROR: .sops.yaml already lists an operator key." >&2
        exit 1
    }

    sudo -v
    if sudo -n test -e "$key_file"; then
        echo "Reusing the existing key at $key_file."
    else
        key=$(age-keygen 2>/dev/null)
        printf '%s\n' "$key" | sudo install -D -m 600 -o root -g root /dev/stdin "$key_file"
        printf '%s\n' "$key" | clip
        unset key
        echo "The private key is on the clipboard. Save it in Bitwarden as"
        echo "'operator-age-key' (the whole text)."
        read -rsp "Press Enter once saved - the clipboard is cleared in 120s either way. " -t 120 || true
        echo
        clip </dev/null
        echo "Clipboard cleared."
    fi

    public=$(sudo -n cat "$key_file" | age-keygen -y)
    sed -i "s|$marker|- $public # operator|" .sops.yaml
    echo "Added $public to .sops.yaml."
    echo "Next: just factory-generate-age-key"

# Nothing is written to disk: age-keygen prints the key to a shell variable,
# which goes to the clipboard for Bitwarden and is then cleared. Only the public
# half is kept, in .sops.yaml. To install the key on a new server,
# factory-install asks for it back from Bitwarden.
#
# Generate the software-factory age key into the clipboard (for Bitwarden)
factory-generate-age-key:
    @bash "{{ justfile_directory() }}/just/scripts/factory-generate-age-key.sh"

# Fills secrets/hosts/software-factory.yaml with everything the host declares:
# the admin password (reusing set-password-hash), the Tailscale auth key, the
# agents' GitHub token, the Wi-Fi credentials, and the probe modules/secrets.nix
# requires.
#
# Write every secret software-factory needs into its sops file
factory-secrets:
    @bash "{{ justfile_directory() }}/just/scripts/factory-secrets.sh"

# The server pulls deploys from this repository's GitHub deployments and posts
# the result back, with a fine-grained token of the repository owner: this
# repository only, Deployments read and write, nothing else. It is root-only on
# the server, unlike the agents' token. Steps in docs/SOFTWARE-FACTORY.md.
#
# Write or renew software-factory's deploy token in its sops file
factory-deploy-token:
    #!/usr/bin/env bash
    set -euo pipefail
    file=secrets/hosts/software-factory.yaml

    sudo -v
    export SOPS_AGE_KEY_CMD="sudo -n cat /var/lib/sops-age/keys.txt"

    echo "infernowork97 > Settings > Developer settings > Fine-grained tokens:"
    echo "only this nixos repository, permission Deployments: Read and write."
    read -rsp "Deploy token: " value; echo
    case "$value" in
        github_pat_*) ;;
        *) echo "ERROR: expected a fine-grained token (github_pat_...)." >&2; exit 1 ;;
    esac
    printf '%s' "$value" | jq -R . | sops set --value-stdin "$file" '["factory-deploy-token"]'
    echo "Wrote factory-deploy-token. Commit $file, then deploy."

# The key is pasted from Bitwarden into a shell variable and goes to the server
# on stdin. It sits briefly in admin's home (mode 600) because sudo needs the
# terminal for its password, so the same connection cannot also carry the key.
#
# Restore the software-factory age key from Bitwarden onto the running server
factory-restore-age-key:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Paste 'software-factory-age-key' from Bitwarden, then press Ctrl-D on a new line:"
    key=$(cat)
    printf '%s\n' "$key" | grep -q '^AGE-SECRET-KEY-1' || {
        echo "ERROR: does not look like an age private key." >&2
        exit 1
    }
    printf '%s\n' "$key" | ssh -p 2222 admin@software-factory 'umask 077; cat > ~/.age-key.tmp'
    unset key
    ssh -t -p 2222 admin@software-factory \
        'sudo install -D -m 600 -o root -g root ~/.age-key.tmp /var/lib/sops-age/keys.txt; rm -f ~/.age-key.tmp'
    echo "Key restored. Deploy again (just factory-deploy) to decrypt with it."

# ─── Install and deploy ──────────────────────────────────────────────────────

# The install link: the box cabled straight to this machine's ethernet adapter.
# NetworkManager's "shared" mode makes this machine 10.42.0.1 on that cable,
# hands the box an address by DHCP and NATs it to the internet through this
# machine's own connection. The kexec installer finds it again by DHCP too.
#
# Share this machine's network with the box over the cable on <interface>
factory-link-up $iface:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$iface" in
        "" | *[!a-zA-Z0-9_-]*) echo "ERROR: invalid interface name '$iface' (see: ip -br link)" >&2; exit 1 ;;
        *) ;;
    esac
    nmcli connection delete factory-install-link >/dev/null 2>&1 || true
    nmcli connection add type ethernet ifname "$iface" con-name factory-install-link \
        ipv4.method shared ipv6.method link-local connection.autoconnect yes >/dev/null
    nmcli connection up factory-install-link >/dev/null
    echo "This machine is 10.42.0.1 on $iface. Leases handed to the box:"
    echo "  just factory-link-leases"

# Show the addresses the box got over the install link
factory-link-leases:
    #!/usr/bin/env bash
    set -euo pipefail
    neighbours=$(ip -4 neigh show)
    grep '^10\.42\.0\.' <<<"$neighbours" || echo "No box seen on 10.42.0.0/24 yet."

# Remove the install link once the box is on Wi-Fi
factory-link-down:
    nmcli connection delete factory-install-link

# Replaces the Ubuntu Server on the box with NixOS, using nixos-anywhere over
# root SSH on the install link (factory-link-up). The box must be on ethernet:
# nixos-anywhere kexecs into an installer that restores wired networking only,
# never Wi-Fi. The age key is
# pasted from Bitwarden into a private temp directory that nixos-anywhere copies
# to the new root, and the directory is removed on exit. The system is built
# here, where the caches are warm, and copied over.
#
# Install NixOS on the box over its install-link address (wipes its disk)
[positional-arguments]
factory-install $ip:
    @bash "{{ justfile_directory() }}/just/scripts/factory-install.sh" "$@"

# Deploys the working tree as it is, committed or not. The flake and its inputs
# are copied to the server's store - content-addressed paths, which need no
# trusted user - and the server builds and switches to it. sudo asks for the
# admin password on the terminal.
#
# Build and switch software-factory to this working tree
factory-deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    export NIX_SSHOPTS="-p 2222"
    source=$(nix flake metadata --json | nix run --inputs-from . nixpkgs#jq -- -r .path)
    nix flake archive --to ssh-ng://admin@software-factory
    ssh -t -p 2222 admin@software-factory \
        sudo nixos-rebuild switch --flake "$source#software-factory"

# Read-only. Runs as the agent account over Tailscale SSH, so it needs no
# key and cannot read the system journal; everything it shows is
# visible to that account. The script travels on stdin, so nothing on the
# server has to be deployed for it to change.
#
# Show software-factory's RAM, disk and Remote Control sessions (`detailed` adds branches, errors, top processes)
[positional-arguments]
factory-status $mode="concise":
    @bash "{{ justfile_directory() }}/just/scripts/factory-status.sh" "$@"

# ─── GitHub and Tailscale ────────────────────────────────────────────────────

# Generates the agents' SSH key on the server, as the agent account, so the
# private half never exists anywhere else. Idempotent: an existing key is kept.
#
# Create the agents' SSH key on software-factory and print its public half
factory-gh-key:
    ssh factory@software-factory \
        'test -e ~/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -C software-factory -f ~/.ssh/id_ed25519; cat ~/.ssh/id_ed25519.pub'
    @echo ""
    @echo "Add this key to infernowork97 TWICE: as an Authentication key and as a"
    @echo "Signing key (GitHub > Settings > SSH and GPG keys)."

# REPLACES the tailnet policy with tailscale/policy.hujson, after the API has
# validated it. The API key is pasted (read -s) and reaches curl on stdin, never
# in argv. Use a short-lived key and revoke it afterwards.
#
# Validate and apply tailscale/policy.hujson to the tailnet
tailscale-apply:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rsp "Tailscale API access token: " token; echo
    [ -n "$token" ] || { echo "ERROR: empty token." >&2; exit 1; }

    api() {
        printf 'user = "%s:"\n' "$token" | curl --fail-with-body -sS -K - \
            -H "Content-Type: application/hujson" \
            --data-binary @tailscale/policy.hujson \
            "https://api.tailscale.com/api/v2/tailnet/-/acl$1"
    }

    echo "Validating..."
    result=$(api /validate)
    if [ -n "$result" ] && [ "$result" != "{}" ]; then
        echo "ERROR: the policy did not validate:" >&2
        echo "$result" >&2
        exit 1
    fi
    api "" >/dev/null
    echo "Applied tailscale/policy.hujson."
