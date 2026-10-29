# Software factory runbook

How to stand up, use and recover the `software-factory` box, step by step.
The design and its accepted risks are in `docs/adr/0007-software-factory.md`.

The box is an **HP Omen 15-ax005** (i7-6700HQ, 4 cores / 8 threads, 12 GB,
1 TB SSD) at home on Wi-Fi, lid closed and plugged in. It is installed from
the **operator machine**, an Ubuntu laptop, with nixos-anywhere over an
Ubuntu Server that is wiped by the install. Agents work as the GitHub account
**infernowork97** and are driven from an Android phone through Claude Code
Remote Control.

Every step is labelled with **where** it runs:

| Label | Where |
|---|---|
| **[operator]** | A terminal on the operator machine, in this repository, inside `nix develop .#factory-install` |
| **[browser]** | Any browser, signed in to the named website |
| **[phone]** | The Android phone |
| **[box]** | The Omen's own keyboard and screen, lid open |
| **[factory]** | A shell on the box as `factory` (`ssh factory@software-factory`) |
| **[admin]** | A shell on the box as `admin` (`ssh -p 2222 admin@software-factory`) |

`just` recipes always run **[operator]**. Follow the steps in order: each one
only needs what the steps before it created.

---

## Part 0 - The operator machine (once)

### 1. Nix and the install shell **[operator]**

1. Install Nix with the Determinate installer. It enables flakes by default:
   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install
   ```
   Open a new terminal afterwards so `nix` is on PATH.
2. Enter the install shell from this repository. Every later **[operator]**
   step runs inside it:
   ```sh
   cd ~/repo/nixos
   nix develop .#factory-install
   ```
   It brings just, gh, sops, age, mkpasswd, nixos-anywhere and the clipboard
   tools, all pinned by `flake.lock`.
3. Tailscale is already installed on this machine. `tailscale up` connects it,
   `tailscale status` shows the tailnet.

---

## Part 1 - Accounts, keys and secrets (no box needed)

### 2. Apply the tailnet policy **[browser]** then **[operator]**

`tailscale/policy.hujson` becomes your **entire** tailnet policy. It keeps
your own devices (this machine, the phone) able to reach each other and adds
the factory rules.

1. **[browser]** login.tailscale.com > **Access controls**: check the current
   policy is still the default allow-all. If you customised it, merge your
   rules into `tailscale/policy.hujson` first.
2. **[browser]** **Settings** > **Keys** > **Generate access token**:
   description `policy-apply`, expiry **1 day**. Copy it (`tskey-api-...`).
3. **[operator]** Apply the policy and paste the token when asked. It
   validates first and changes nothing if validation fails.
   ```sh
   just tailscale-apply
   ```
4. **[browser]** Revoke the access token.

### 3. Tailscale auth key for the box **[browser]**

This must come after step 2: the key needs `tag:factory`, which the policy
defines.

login.tailscale.com > **Settings** > **Keys** > **Generate auth key**:

- Reusable **off**, Ephemeral **off**, Pre-approved **on**;
- Expiration **90 days**: it is used once, at the box's first boot, so the
  install (step 12) must happen before it expires. If it does expire, repeat
  this step and step 8;
- Tags **on**, `tag:factory`.

Copy the key (`tskey-auth-...`) somewhere temporary for step 8.

### 4. GitHub **[browser]**, signed in as infernowork97

Agents push as infernowork97 itself (there is no separate bot account). That
account can merge its own pull requests, so main is guarded by a ruleset that
requires a pull request. Agents merge with `gh pr merge` only when you ask
them to. Merging deploys nothing: only `/deploy` or the workflow does.

1. **Enable Actions and Dependabot** on `infernowork97/nixos`: **Actions** tab
   > enable workflows; **Settings** > **Code security** > Dependabot version
   updates on.
2. **Protect `main`** in every repository the factory works on, this one
   first: **Settings** > **Rules** > **Rulesets** > **New branch ruleset**:
   - target: the default branch; enforcement **Active**; bypass list **empty**;
   - **Restrict deletions**, **Block force pushes**;
   - **Require a pull request before merging**, required approvals **0**
     (GitHub never lets you approve your own pull request).
3. **The agents' token**: **Settings** > **Developer settings** > **Personal
   access tokens** > **Tokens (classic)** > **Generate new token (classic)**:
   - note `software-factory`, expiration of your choice (step 8 again when it
     expires);
   - scopes **`repo`**, **`workflow`**, **`read:org`**;
   - copy it (`ghp_...`) somewhere temporary for step 8.
4. **The deploy token**: **Settings** > **Developer settings** > **Fine-grained
   tokens** > **Generate new token**:
   - name `software-factory-deploy`, expiration up to a year (`factory-ctl
     status` warns 30 days before it ends);
   - Repository access: **Only select repositories** > `nixos`;
   - Permissions: **Deployments: Read and write**, nothing else;
   - copy it (`github_pat_...`) for step 8.

The box's SSH key does not exist yet. It is created on the box in step 15.

### 5. Claude account settings **[browser]**

claude.ai > **Settings**, signed in with the Max account:

- **Usage** > **Extra usage**: **off**. Reaching the plan limit pauses the
  agents instead of billing more.
- **Account** > **Trusted devices** > **Require trusted devices**: **on**.
  The box enrols itself when it logs in, in step 16.
- **Connectors** > **GitHub**: connect infernowork97, and install the Claude
  GitHub App on that account. This is how a session attaches its repository
  (`add_repo`) and gets woken by CI results and reviews
  (`subscribe_pr_activity`).

### 6. The operator's age key **[operator]**

```sh
just operator-age-key
```

1. It asks for your sudo password, then writes a new age key to
   `/var/lib/sops-age/keys.txt` (root-only) on this machine.
2. The private key is copied to the clipboard. In Bitwarden create a **Secure
   note** named `operator-age-key` and paste it.
3. Press Enter. The clipboard is cleared (after 120 s even without Enter).

This key can edit every secrets file. Its public half goes into `.sops.yaml`.

### 7. The box's age key **[operator]**

```sh
just factory-generate-age-key
```

The same flow: save the clipboard in Bitwarden as `software-factory-age-key`
(two comment lines, then the `AGE-SECRET-KEY-1...` line), press Enter. Only
its public half is written, into `.sops.yaml`; the install (step 12) asks for
the private half back.

### 8. The box's secrets **[operator]**

```sh
just factory-secrets
```

It asks, in order, for:

1. **Your sudo password**, to read the operator key from step 6.
2. **A new admin password**, typed twice. Save it in Bitwarden as
   `software-factory-admin-password`. You need it for every break-glass deploy
   (sudo) and at the box's own keyboard if the tailnet is ever down.
3. **The Tailscale auth key** from step 3.
4. **The agents' token** from step 4.3.
5. **The Wi-Fi SSID and password**. Both are secret: the repository is public
   and an SSID locates the house.
6. **The deploy token** from step 4.4. `just factory-deploy-token` renews this
   one secret on its own later.

Then commit to the pull request's branch, so the flake can see the files.
Until `secrets/hosts/software-factory.yaml` exists, evaluating the host fails
on purpose:

```sh
git add .sops.yaml secrets/hosts/software-factory.yaml
git commit -m "[software-factory] Add the box's secrets"
git push
```

Delete the temporary copies of the tokens.

---

## Part 2 - Prepare and install the box (about 1 hour, once)

### 9. Firmware settings **[box]**

Power on and press **F10** for the BIOS setup:

- **Secure Boot: off** (System Configuration > Boot Options), legacy support
  off, so it boots UEFI only. Secure Boot locks the kernel down, and a
  locked-down kernel refuses the `kexec` nixos-anywhere relies on; NixOS's
  systemd-boot is unsigned too. `just factory-install` checks this first and
  stops if it is still on.
- If offered, enable **power on after AC loss**, so the box comes back by
  itself after a power cut drains the battery.

Ubuntu still boots afterwards.

### 10. Ubuntu Server and the install link **[box]** then **[operator]**

Ubuntu is only the vehicle for nixos-anywhere: the install wipes it. The box
is cabled **straight to the operator machine** (its USB ethernet adapter), and
the operator machine shares its own internet over that cable.

1. **[box]** Install **Ubuntu Server 26.04** from a USB stick, with **Install
   OpenSSH server** ticked. Any user name will do (here `merlin7559`).
2. Cable the box's ethernet port to the operator machine's ethernet adapter.
3. **[operator]** Share this machine's network over that cable. Find the
   adapter's name with `ip -br link` (here `enx6c1ff708f396`):
   ```sh
   just factory-link-up enx6c1ff708f396
   ```
   This machine becomes `10.42.0.1` on the cable and hands out `10.42.0.x`.
4. **[box]** Ubuntu installed without a network writes no DHCP for the wired
   port, so turn it on, logged in on the box's own keyboard:
   ```sh
   printf 'network:\n  version: 2\n  ethernets:\n    eno1:\n      dhcp4: true\n' \
     | sudo tee /etc/netplan/50-install-link.yaml
   sudo chmod 600 /etc/netplan/50-install-link.yaml
   sudo netplan apply
   ip -4 -br addr show eno1      # 10.42.0.x: that is <box-ip> from here on
   ```
   `sudo` wants the Ubuntu user's password. Root has no password on Ubuntu,
   so `su` never works; that is normal.
5. **[operator]** Copy your key to the Ubuntu user. Use a real terminal, not
   Claude's `!` prefix, which has no terminal to ask the password on, and
   never `sudo` (local root has no key):
   ```sh
   ssh-copy-id -i ~/.ssh/id_ed25519.pub merlin7559@<box-ip>
   ```
6. **[box]** Give root the same key, since nixos-anywhere logs in as root:
   ```sh
   sudo install -d -m 700 /root/.ssh
   sudo cp /home/merlin7559/.ssh/authorized_keys /root/.ssh/
   ```
7. **[operator]** Check: `ssh root@<box-ip> true` must succeed with no
   password.

### 11. Pin the disk, then merge **[operator]** then **[browser]**

1. The disk is pinned already, as
   `/dev/disk/by-id/nvme-NVMe_CA5-8D1024_00210650002E` in
   `hosts/software-factory/disk-config.nix`. After a disk swap, read the new
   one's id and change it there:
   ```sh
   ssh root@<box-ip> 'lsblk -d -o NAME,SIZE,MODEL,TRAN; ls -l /dev/disk/by-id/ | grep -v part'
   ```
   Pick the `nvme-...` (or `ata-...`) entry without `eui.`/`wwn-`.
2. **[browser]** With the secrets from step 8 pushed, wait for the pull
   request's `check` to go green, then merge it, and pull `main` here:
   `git switch main && git pull`.

### 12. Install NixOS **[operator]**

From `main`, with the cable still plugged in:

```sh
just factory-install <box-ip>
```

1. Paste the `software-factory-age-key` note from Bitwarden, then press
   **Ctrl-D** on an empty line.
2. Wait. Lines saying `/etc/ssh/ssh_config line 52: Unsupported option
   "gssapiauthentication"` are harmless: nixos-anywhere brings its own ssh,
   built without GSSAPI, and it reads Ubuntu's ssh config. nixos-anywhere
   kexecs the box into an in-memory NixOS installer,
   wipes the disk, builds the system **here** and copies it over, installs it
   and reboots. 20-40 minutes, mostly downloads. The installed system
   takes `10.42.0.x` on the cable again.
3. About a minute after the reboot, the box joins the tailnet by itself with
   the auth key. Check login.tailscale.com > **Machines**: `software-factory`,
   tagged `tag:factory`.

### 13. Move it to Wi-Fi **[box]**

1. **Unplug the ethernet cable.** NetworkManager joins the Wi-Fi from the
   `wifi-env` secret; within a minute the box is reachable over the tailnet
   again (`tailscale ping software-factory` from the operator machine).
   Then, **[operator]**, `just factory-link-down` removes the shared profile.
2. Close the lid and put it somewhere ventilated, plugged in. Lid close and
   sleep are disabled, so it keeps running.

If it does not come back, see [Troubleshooting](#troubleshooting).

### 14. Check both ways in **[operator]**

```sh
tailscale up
ssh -p 2222 admin@software-factory   # your ~/.ssh/id_ed25519; you get a shell, then exit
ssh factory@software-factory         # Tailscale SSH: no key, no password; then exit
```

Accept each host key with `yes` the first time.

### 15. Give the box its GitHub key **[operator]** then **[browser]**

```sh
just factory-gh-key
```

This creates the key on the box and prints its public half
(`ssh-ed25519 ... software-factory`). Signed in as **infernowork97**:

1. github.com > **Settings** > **SSH and GPG keys** > **New SSH key**: title
   `software-factory`, key type **Authentication Key**, paste.
2. **New SSH key** again with the same key, key type **Signing Key**, so the
   agents' commits show as Verified.

### 16. Log in to Claude on the box **[factory]**

```sh
ssh factory@software-factory
claude-factory
```

1. Choose **Claude account with subscription**, not an API key: the box
   refuses API keys anyway.
2. Open the URL it prints in a browser on the operator machine, approve, and
   paste the code back.
3. If it asks whether to trust the home directory, answer yes.
4. `/status` shows your claude.ai Max account. `/exit`.

Then start every repository's Remote Control server:

```sh
systemctl --user restart factory-repos
systemctl --user list-units 'claude-rc@*'   # one running unit per repository
exit
```

The declared repository (`nixos`) is cloned into `~/repos` with the key from
step 15.

### 17. Connect the phone **[phone]**

1. Tailscale is already on the phone and signed in to the same tailnet.
   Android Settings > Apps > Tailscale > Battery: **Unrestricted**.
2. Open the **Claude** app, sign in, go to **Code**. Enrol the phone if
   Trusted Devices asks.
3. Android Settings > Apps > Claude > Battery: **Unrestricted**, so
   notifications arrive. Two kinds reach the phone:
   - **needs your input**: an agent asks a question or waits on a permission
     prompt;
   - **agent-sent**: agents call `PushNotification` when they open a pull
     request, when CI is green, when blocked, or on a failure they cannot fix.

   These are the **Push when actions required** and **Push when Claude
   decides** toggles in `/config` of any interactive `claude` signed in to the
   same account. If agent-sent pushes never arrive, check the second one.
4. You should see an `admin` server and a `nixos` server.
5. For SSH from the phone (Part 5): install **Termux** from F-Droid, then
   `pkg install openssh` and `ssh factory@software-factory`. Tailscale SSH
   authenticates the phone's tailnet identity, so no key is needed.

### 18. First end-to-end test **[phone]**

Open the `nixos` server, start a session, and ask for something small: "add
a sentence to docs/SOFTWARE-FACTORY.md and open a PR". You should get:

- a branch pushed and a pull request opened by infernowork97, with Verified
  commits;
- a notification with the link when the pull request opens, and another
  when CI is green.

Merge it in the browser, or ask the agent to merge it. It never merges on its
own.

---

## Part 3 - Daily use

- **Start work [phone]:** Claude app > Code > the repository's server > new
  session, e.g. `/grill-me`. Each session works in its own git worktree. Up
  to 3 sessions per repository.
- **Run the box [phone]:** open the `admin` server and start a session:

  | Skill | Does |
  |---|---|
  | `/start-repo <name or URL>` | clone if needed, start, and start at boot |
  | `/stop-repo <name>` | stop, and stay stopped across reboots |
  | `/restart-repo <name>` | restart a wedged server, or apply a deploy to it |
  | `/terminate-sessions [name]` | end live sessions; servers keep running |
  | `/status` | servers, sessions, local work, last deploy |
  | `/stats` | RAM, disk, CPU, the agents' memory cap |
  | `/free-disk` | plan, confirm, then prune pushed worktrees, caches and garbage |
  | `/deploy [rollback]` | Part 4 |
  | `/reboot`, `/gc` | root operations through fixed units |

  The skills drive `factory-ctl`, which works the same in a shell
  **[factory]** (`factory-ctl help`).
- **Add a repository [phone]:** `/start-repo <name>` in the admin server. Add
  the `main` ruleset from step 4.2 to it first. **Private repositories are
  only ever added this way, never in Nix**: this repository is public.
- **Preview an app:** agents bind dev servers to ports 3000-3099 and say
  which. Open `http://software-factory:<port>` on the phone or the operator
  machine, with Tailscale up.
- **Status [operator]:** `just factory-status`, or `just factory-status
  detailed` for recent branches, the last hour's errors and the top memory
  users.
- **Logs [factory]:** `journalctl --user -u claude-rc@<repo> -e` for one
  repository's server; `journalctl -u factory-deploy -e` for deploys.
- **Remove a repository for good [factory]:** `/stop-repo` it, then
  `rm -rf ~/repos/<repo>`.

### Sizing

`myConfig.factory.size = "medium"` is tuned for the Omen
(`modules/nixos/server/resources.nix`): the agents' slice is capped at 9 GB
(soft) / 9.5 GB (hard), Nix builds at 5 / 6 GB on 6 of the 8 threads, one at a
time, so a deploy leaves the agents two threads. zram and an 8 GiB swapfile
absorb the overlap. The store collects garbage when free disk drops below
20 GiB.

## Part 4 - Changing the box (deploy)

Change the configuration with a pull request, merge it, then deploy `main`:

- **[phone]** `/deploy` in the admin server, or
- **[browser]** Actions > **Deploy software-factory** > Run workflow, on `main`.

What happens:

1. The workflow refuses unless `check` passed on main's tip, then creates a
   GitHub deployment for that commit. GitHub holds no credential to the box.
2. Within a minute the box sees it, checks the commit is still the tip of
   `main`, and builds it itself.
3. It activates the new system and checks it can still be reached: Tailscale
   up, sshd running, GitHub answering. If not, it switches straight back.
   Only a healthy system becomes the boot default.
4. The result is posted to the deployment (the repository's Environments page)
   and shown by `/status`.

- **Live sessions keep running.** `/restart-repo` applies a new agent setup to
  a repository; a reboot applies it everywhere.
- **Roll back:** `/deploy rollback` returns to the previous generation. Only two
  are kept, and the boot menu offers the same two.
- **Nothing deploys on merge.** Only the workflow or `/deploy` does.

### Break glass **[operator]**

When GitHub or the deploy path itself is broken, deploy the working tree
directly, committed or not, any branch:

```sh
tailscale up
just factory-deploy        # then the admin password for sudo
```

## Part 5 - Recovery

- **Tailnet unreachable:**
  - [box] open the lid, log in as `admin` with
    `software-factory-admin-password`;
  - `nmcli device status` and `journalctl -u NetworkManager -e` for Wi-Fi;
    `sudo systemctl status tailscaled`, and `sudo tailscale up` if it is
    logged out;
  - cabling it to the operator machine again with `just factory-link-up
    <iface>` always gives a working link (`ssh -p 2222 admin@<box-ip>` over
    the cable works only once Tailscale is up, so use the keyboard first).
- **Wi-Fi password changed:** cable it to the operator machine
  (`just factory-link-up <iface>`), run
  `just factory-secrets` (it overwrites everything, so have the other values at
  hand) or `just edit-secrets software-factory` to change `wifi-env` alone,
  commit, merge, and deploy.
- **Box reinstalled from scratch:**
  - repeat step 3 (new auth key) and step 8;
  - commit, and repeat steps 10 and 12 to 16.
  - The age keys stay the same: they are in Bitwarden.
- **Age key missing on a running box [operator]:**
  `just factory-restore-age-key`, then `just factory-deploy`.
- **Operator machine lost:** on the new one, do Part 0, then put the
  `operator-age-key` note from Bitwarden at `/var/lib/sops-age/keys.txt`
  (root, mode 600) and add a new admin key to
  `hosts/software-factory/configuration.nix`, deployed from the phone.
- **Agents' token expired:** create a new one (step 4.3), run
  `just factory-secrets`, commit, merge, and `/deploy`.
- **Deploy token expired or expiring:** create a new one (step 4.4), run
  `just factory-deploy-token`, commit, and `just factory-deploy` - the old
  token cannot report the deploy that replaces it.
- **Admin server not answering [factory]:**
  `systemctl --user restart claude-rc-admin`.
- **Suspected compromise:** do all of these, then reinstall from scratch with
  new age keys, auth key and tokens:
  - [browser, as infernowork97] delete the `software-factory` SSH keys and
    both tokens;
  - [browser] claude.ai > Settings > Account: remove the box from Trusted
    devices and sign out of all sessions;
  - [browser] login.tailscale.com > Machines: remove `software-factory`.

## Troubleshooting

- **"the box's kernel is locked down":** Secure Boot is still on (step 9).
- **nixos-anywhere hangs after "kexec":** the box lost its network. It must
  be on the cable with `just factory-link-up` active (step 10). Power-cycle
  it back into Ubuntu, check `just factory-link-leases`, and retry.
- **The box has no 10.42.0.x address [box]:** the netplan file from step 10.4
  is missing, or the cable is in a different adapter than the one given to
  `factory-link-up`.
- **No Wi-Fi after unplugging ethernet [box]:** `nmcli connection show
  home-wifi` must exist; if not, `journalctl -u NetworkManager-ensure-profiles
  -e`. A wrong SSID or password means rewriting `wifi-env` (Part 5). The card
  is an Intel one and its firmware ships with
  `hardware.enableRedistributableFirmware`.
- **`ssh factory@software-factory` asks for a password or is refused:** check
  that the policy from step 2 is applied and the box shows `tag:factory` in
  Machines.
- **`ssh -p 2222 admin@...` times out:** port 2222 is reachable only over the
  tailnet. Run `tailscale up` first.
- **`systemctl --user` says "Failed to connect to bus" [factory]:** run
  `export XDG_RUNTIME_DIR=/run/user/$(id -u)` and retry.
- **A repository's server keeps restarting [factory]:** read
  `journalctl --user -u claude-rc@<repo> -e`. Usually: **not logged in**
  (repeat step 16), or **"Workspace not trusted"** (restart the unit).
- **Agents say `add_repo` or `subscribe_pr_activity` was refused:** redo the
  GitHub connector in step 5, and check the Claude GitHub App is granted that
  repository.
- **Clones fail [factory]:** `ssh -T git@github.com` should greet
  infernowork97; if not, redo step 15.
- **The box gets hot or loud:** builds use 6 threads at most. Keep the vents
  clear; a laptop stand helps more than any setting.
