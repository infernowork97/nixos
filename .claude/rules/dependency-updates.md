---
paths:
  - "flake.nix"
  - "flake.lock"
  - "modules/nix.nix"
  - ".github/dependabot.yml"
  - ".github/workflows/**"
---

## Dependency Updates

**`nixpkgs` tracks `nixos-26.05`**, the branch Hydra advances only once its Linux binaries are in `cache.nixos.org`. The only host is x86_64-linux.

Dependabot splits nix inputs into `nixpkgs-core`, `ai` (agent tooling and skill sources) and `ungrouped` (a catch-all matching everything else), so a nixpkgs rev that breaks the build does not also hold back llm-agents and the skills, and an input nobody classified still gets updates instead of silently freezing. `ungrouped` restates the other two memberships in `exclude-patterns` because dependabot has no group-reference syntax; keep them in step.
