# My NixOS (experimental toy project)

NixOS configuration for `software-factory`, a headless HP Omen laptop at home that runs Claude Code agents driven from a phone. Installed and operated from an Ubuntu machine with Nix. Start at [docs/SOFTWARE-FACTORY.md](docs/SOFTWARE-FACTORY.md).

---

> [!WARNING]
> ## SECURITY DISCLAIMER & PERSONAL USE NOTICE
>
> **This repository is my personal, experimental NixOS and NixVim configuration. It is NOT intended for production use, public deployment, or adoption by others.**
>
> - **USE AT YOUR OWN RISK.** This configuration may contain security vulnerabilities, incomplete hardening, experimental settings, or unsafe defaults that are intentionally or unintentionally present for my own convenience during development.
> - **NO WARRANTY.** I make absolutely no guarantees about the correctness, safety, or stability of anything in this repository. Configurations may break your system, expose sensitive data, or behave in unexpected ways.
> - **NOT SECURITY-AUDITED.** SOPS secrets management, disk encryption settings, SSH configuration, and any other security-sensitive components have NOT been independently audited. Do not assume they are safe or correct.
> - **NOT MAINTAINED FOR OTHERS.** This repo evolves for my personal needs. Breaking changes, incomplete states, and half-finished experiments are normal and expected.
> - **DO NOT USE THIS ON PRODUCTION SYSTEMS.** This is a lab/experimentation environment. It is explicitly not designed to be reproducible, secure, or safe outside of my own machines.
>
> If you are looking for a well-maintained, production-safe NixOS configuration, please look elsewhere. See the [LICENSE](./LICENSE) for full liability disclaimers.

---

## Key Programs

**NixVim** — `programs/nvim/`  
Full Neovim config via NixVim. LSP client config lives in `programs/nvim/languages/`; language binaries are installed via `modules/home/languages/`. Supports Haskell, TypeScript, Elixir, Nix, D2, YAML, and MDC.

**Claude Code** — `programs/claude-code/`  
Three flavors (`claude`, `claude-ts`, `claude-web-ui`) with shared base settings, MCP server wiring, and a custom statusline binary. Each flavor wraps the `claude` CLI and writes `~/.claude/settings.json` and `~/.claude/CLAUDE.md` at launch.

**Agents** — `programs/agents/`  
Agent-agnostic configuration shared by every coding agent. `AGENTS.md` holds instructions that apply everywhere; each agent program installs it the way its tool expects (Claude Code reads only `~/.claude/CLAUDE.md`, so that is where it lands). Agent-specific code stays in that agent's own program.

**Skills** — `programs/agents/skills/`  
Agent skills pinned in the flake. Third-party sets are declared as `flake = false` inputs and installed from an explicit allowlist; custom skills are plain `SKILL.md` files under `programs/agents/skills/custom/`. Each Claude flavor relinks `~/.claude/skills` at launch from its own set. `nix flake check` validates every skill's frontmatter.

---

## Directory Structure

```
flake.nix           — outputs: devShells, nixosConfigurations, checks
hosts/
  software-factory/ — the box's identity, disk layout and size
lib/                — system builder helpers
modules/
  home/             — Home Manager modules (factory/ is the agent account)
  nixos/server/     — the server's system configuration
programs/
  nvim/             — NixVim Neovim config (core/, languages/)
  agents/           — agent-agnostic config (AGENTS.md + skill catalog)
  claude-code/      — Claude Code flavors + statusline
  software-factory/ — factory-ctl, Remote Control launchers, ops scripts
shells/             — dev shells (factory-install for the operator machine)
docs/               — setup and operations guides
just/               — Justfile recipes
```

---

## Docs

| Doc | Purpose |
|-----|---------|
| [docs/SOFTWARE-FACTORY.md](docs/SOFTWARE-FACTORY.md) | Install, use and recover the box |
| [docs/SOPS.md](docs/SOPS.md) | Secrets management with SOPS + age |

---

## Common Commands

```shell
nix develop .#factory-install   # the operator shell
just check                      # lint + architecture + format + flake check
just factory-status             # the box's RAM, disk and sessions
just factory-deploy             # break-glass deploy of the working tree
```
