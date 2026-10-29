{ lib, ... }:
{
  imports = [ ./disk-config.nix ];

  networking.hostName = "software-factory";

  myConfig = {
    # The agent account commits as infernowork97, a secondary account kept for
    # the factory. main is guarded by a ruleset (pull request required, no force
    # pushes, no deletion) and agents are barred from `gh pr merge`.
    user = {
      name = "factory";
      fullName = "infernowork97";
      email = "263571817+infernowork97@users.noreply.github.com";
    };

    # The operator machine's key.
    admin.authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKhYu/b/3+boevsZiit1clWpwborD4noSkkbOQvBTBg1 operator"
    ];

    factory = {
      # HP Omen 15-ax005 (4 cores / 8 threads, 12 GB).
      size = "medium";

      # Deploys are pulled from this repository (modules/nixos/server/ops.nix).
      deploy.repo = "infernowork97/nixos";

      # Public repositories only - private ones are added on the box with
      # `factory-ctl start` and never named here.
      repos = {
        nixos = "git@github.com:infernowork97/nixos.git";
      };
    };

    secrets = {
      gh-token = { };

      # modules/secrets.nix declares this probe as global on every host. This
      # host's age key is not a recipient of secrets/common.yaml, so the probe
      # reads the same key from the host's own file instead.
      example-global.scope = lib.mkForce "host";
    };
  };

  system.stateVersion = "26.05";
}
