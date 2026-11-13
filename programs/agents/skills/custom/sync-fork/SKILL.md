---
name: sync-fork
description: Syncs this fork with its upstream, ILIYANGERMANOV/nixos - triages the new commits, merges upstream with a real merge commit that keeps the protected surface intact, verifies it and opens a PR. Never merges the PR.
disable-model-invocation: true
---

# Sync fork

Upstream's history enters the fork through merge commits, so each sync starts
where the last one ended. A sync merges one upstream commit, the **cut**:
`upstream/main` itself, or an earlier commit step 2 picks. Every step after it
works against `<cut>`, and nothing upstream committed after the cut enters.

## 1. Fetch

```sh
git fetch origin main
git fetch https://github.com/ILIYANGERMANOV/nixos.git +main:refs/remotes/upstream/main
git log --oneline origin/main..upstream/main
```

Fetch by URL: the repository's remotes stay as they are. An empty log means
nothing is new: tell the user and stop.

## 2. Pick a cut

The cut is `upstream/main` unless the range is big: dozens of commits, or a
rewrite (a commit that deletes or moves files most later commits build on).
Then propose a cut just before the first commit that touches much of the
protected surface, before a rewrite that is not the range's first commit, or
before the point where triage stops fitting one PR. When the rewrite is the
first new commit, the cut is at or after it. Compare candidates by their
conflicts, each with
`git merge-tree --write-tree --name-only origin/main <candidate>`, and ask the
user with `AskUserQuestion`. The next sync starts after the cut, since the
merge makes it an ancestor of `main`.

## 3. Triage

Group the commits of `origin/main..<cut>` by theme and give every theme a
verdict: **take**, **adapt** or **skip**. A theme is done when it answers each of these:

- Value: what it gives this fork, a single x86_64-linux box.
- Conflicts: `git merge-tree --write-tree --name-only origin/main <cut>`.
- Identity: the upstream owner, its bot and its deploy repository, in new text.
- Flake: new inputs, and anything that would change `flake.lock`.
- Secrets: anything touching `.sops.yaml`, `secrets/` or a secret's declaration.
- Deleted paths: changes under a path in the protected surface's deleted list.
- Runtime settings: every change to what a session runs with (`effortLevel`,
  connectors, hooks, permissions and other settings) is listed as its own
  theme for the user to decide. A clean merge brings them in silently.

## 4. Ask

Use `AskUserQuestion` for a real conflict with the fork, or a change whose fit
is unclear. Recommend the fork's side on a conflict. Settle the rest from the
protected surface yourself.

## 5. Merge

```sh
git switch -c sync-upstream-<cut short sha> origin/main
git merge --no-ff --no-commit <cut>
```

Resolve conflicts. A protected path keeps the fork's side, and a path the fork
deleted stays deleted, even with upstream's edits on it. Where upstream
deleted, moved or renamed a file the fork edited, carry the fork's edit to the
file's new home and drop the old file. Revert each skipped
change here, so it is part of the merge: `git checkout origin/main -- <path>`
for a path `origin/main` has, `git rm -f <path>` for one upstream added, or by
hand. A cherry-pick or a squash would fork the history from upstream.

Then commit it as `Merge upstream <cut short sha> (#<pr>) into the fork`,
where `#<pr>` is upstream's PR number from the cut commit's subject.

Adapt merged text to the fork in a follow-up commit: paths, hosts and identity
it names. Fork-only code meets the lint, format and test rules upstream brings:
move it, fix it or give it its test in a follow-up commit, behaviour unchanged.
An exemption is for vendored third-party files only.

## 6. Verify

Complete when every check below passes on the final commit:

1. `git merge-base --is-ancestor <cut> HEAD`, and nothing after the cut:
   `git rev-list --count <cut>..upstream/main` equals
   `git rev-list --count HEAD..upstream/main`.
2. Each entry of the protected surface: read
   `git diff origin/main HEAD -- <path>`. Deleted paths that came back are
   the paths both in `git diff --diff-filter=A --name-only origin/main HEAD`
   and in the fork's deletions; there are none. Each difference is a change
   the user or triage accepted.
3. Each skipped theme: for every path its commits touch
   (`git show --name-only --format= <commit>`), read
   `git diff origin/main HEAD -- <path>`. Each is empty, or its difference
   belongs to a taken or adapted theme. A clean merge brings a skipped change
   in without a conflict, so this is where it shows.
4. `git grep -n -i -e iliyangermanov -e ivybot -e ivywallet` lists only
   intended references.
5. The host evaluation from `CLAUDE.md`'s Checks.
6. `nix develop .#default -c just check` once, in the background.

## 7. Open the PR

Use `pr-description`. The body lists the themes with their verdicts and states:
**merge with a merge commit, never squash or rebase, or the next sync replays
these commits.** Wait for green CI and report the PR. The user merges it.

## Protected surface

The fork's side wins here unless the user says otherwise. Protection follows
a file through a move or rename (`git log --follow`): the merge-only rule in
`factory-core.md` may live in `programs/agents/profiles/factory/agent.md`.

- `hosts/software-factory/`, including the infernowork97 identity and
  `deploy.repo`.
- `modules/nixos/server/omen.nix` and `resources.nix`.
- `.sops.yaml` and `secrets/`: the server has its own age key.
- `flake.nix`: `nixpkgs` on `nixos-26.05`, and no `nix-darwin`, `lanzaboote` or
  `herdr` input. `flake.lock` stays the fork's; an input moves only to the
  cut's pin, and only when taken code needs it.
- `.github/workflows/check.yml`: no darwin or `cache-guard` job, since the fork
  has no darwin host.
- `.github/workflows/deploy-factory.yml`: its gate names exactly jobs
  `check.yml` has, or every deploy blocks. `.github/dependabot.yml`.
- Deleted, and staying so: the fork's deletions,
  `git diff --diff-filter=D --name-only $(git merge-base origin/main <cut>) origin/main`.
- Fork docs: the Omen amendment in `docs/adr/0007-software-factory.md`,
  `docs/SOFTWARE-FACTORY.md`, and the fork facts in `CLAUDE.md` and
  `.claude/rules/software-factory.md`.
- Fork-only skills: `10x-engineer`'s chat approval (the user's message naming
  a PR, the ledger's `Approved head`), the merge-only-when-asked rule in
  `programs/claude-code/factory-core.md`, and `sync-fork` itself.
- Agents push as infernowork97, never a bot.
