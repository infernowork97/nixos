# The operator machine's shell for installing and running the software-factory
# box: `nix develop .#factory-install`, then the `just factory-*` recipes in the
# order docs/SOFTWARE-FACTORY.md gives. Everything is pinned by flake.lock, so
# the install does not depend on what the operator's distribution ships.
{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    just # the factory-* recipes
    git
    gh # open and merge the pull request, check deployments
    jq # quote secrets for sops
    curl # tailscale-apply
    age # age-keygen for the operator and factory keys
    sops # write secrets/hosts/software-factory.yaml
    ssh-to-age
    mkpasswd # yescrypt hash of the admin password
    nixos-anywhere # factory-install
    openssh
    wl-clipboard # age keys to the clipboard for Bitwarden (Wayland)
    xclip # the same under X11
  ];
  shellHook = ''
    echo "software-factory install shell. The steps: docs/SOFTWARE-FACTORY.md."
    echo "Run 'just' to list the recipes."
  '';
}
