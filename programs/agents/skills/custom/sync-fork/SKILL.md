---
name: sync-fork
description: Syncs this fork with its upstream, ILIYANGERMANOV/nixos - triages the new commits, merges upstream with a real merge commit that keeps the protected surface intact, verifies it and opens a PR. Never merges the PR.
disable-model-invocation: true
---

# Sync fork

Upstream's history enters the fork through merge commits, so each sync starts
where the last one ended. Every step leaves `upstream/main` an ancestor of the
branch.

## 1. Fetch

```sh
git fetch origin main
git fetch https://github.com/ILIYANGERMANOV/nixos.git +main:refs/remotes/upstream/main
git log --oneline origin/main..upstream/main
```

Fetch by URL: the repository's remotes stay as they are. An empty log means
nothing is new: tell the user and stop.

## 2. Triage

Group the new commits by theme and give every theme a verdict: **take**,
**adapt** or **skip**. A theme is done when it answers each of these:

- Value: what it gives this fork, a single x86_64-linux box.
- Conflicts: `git merge-tree --write-tree --name-only origin/main upstream/main`.
- Identity: the upstream owner, its bot and its deploy repository, in new text.
- Flake: new inputs, and anything that would change `flake.lock`.
- Secrets: anything touching `.sops.yaml`, `secrets/` or a secret's declaration.
- Deleted paths: changes under a path in the protected surface's deleted list.

## 3. Ask

Use `AskUserQuestion` for a real conflict with the fork, or a change whose fit
is unclear. Recommend the fork's side on a conflict. Settle the rest from the
protected surface yourself.

## 4. Merge

```sh
git switch -c sync-upstream-<yyyy-mm> origin/main
git merge --no-ff --no-commit upstream/main
```

Resolve conflicts. A protected path keeps the fork's side, and a path the fork
deleted stays deleted, even with upstream's edits on it. Revert each skipped
change here, with `git checkout origin/main -- <path>` or by hand, so it is part
of the merge. A cherry-pick or a squash would fork the history from upstream.

Adapt merged text to the fork in a follow-up commit: paths, hosts and identity
it names.

## 5. Verify

Complete when every check below passes on the final commit:

1. `git merge-base --is-ancestor upstream/main HEAD`.
2. Each entry of the protected surface: read
   `git diff origin/main HEAD -- <path>`, and read
   `git diff --diff-filter=A --name-only origin/main HEAD` for deleted paths
   that came back. Each difference is a change the user or triage accepted.
3. `git grep -n -i -e iliyangermanov -e ivybot -e ivywallet` lists only
   intended references.
4. The host evaluation from `CLAUDE.md`'s Checks.
5. `nix develop .#default -c just check` once, in the background.

## 6. Open the PR

Use `pr-description`. The body lists the themes with their verdicts and states:
**merge with a merge commit, never squash or rebase, or the next sync replays
these commits.** Wait for green CI and report the PR. The user merges it.

## Protected surface

The fork's side wins here unless the user says otherwise.

- `hosts/software-factory/`, including the infernowork97 identity and
  `deploy.repo`.
- `modules/nixos/server/omen.nix` and `resources.nix`.
- `.sops.yaml` and `secrets/`: the server has its own age key.
- `flake.nix`: `nixpkgs` on `nixos-26.05`, and no `nix-darwin`, `lanzaboote` or
  `herdr` input.
- `.github/workflows/check.yml`: no `cache-guard` job, since the fork has no
  darwin host.
- `.github/workflows/deploy-factory.yml` and `.github/dependabot.yml`.
- Deleted, and staying so: darwin, desktop and old-host paths (`hosts/macos-*`,
  `hosts/lenovo-old`, `modules/macos/`, `modules/nixos/desktop.nix`,
  `just/nix-darwin/`, `shells/darwin-install.nix`, `shells/nixos-install.nix`,
  their `secrets/hosts/*.yaml`) and the `modules/home/` removals (`default.nix`,
  `terminal.nix`, `git.nix`, `ssh.nix`, `direnv.nix`, `herdr.nix`,
  `claude-code.nix`).
- Fork docs: the Omen amendment in `docs/adr/0007-software-factory.md`,
  `docs/SOFTWARE-FACTORY.md`, and the software factory section of `CLAUDE.md`.
- Agents push as infernowork97, never a bot.
