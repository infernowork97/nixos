{ inputs, root }:
let
  inherit (inputs.nixpkgs) lib;

  # A headless NixOS server. Everything it needs lives in modules/nixos/server.
  mkNixosServer =
    hostname: system:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs root; };
      modules = [
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        "${root}/modules/theme.nix"
        "${root}/modules/nix.nix"
        "${root}/modules/home-manager.nix"
        "${root}/modules/secrets.nix"
        "${root}/modules/nixos/server"
        "${root}/hosts/${hostname}/configuration.nix"
      ];
    };

  forAllSystems =
    f:
    lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
      system:
      f (
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      )
    );
in
{
  inherit
    mkNixosServer
    forAllSystems
    ;
}
