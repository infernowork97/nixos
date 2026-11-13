{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # The nixpkgs default, 3.13, which the /self-improve analyzer needs.
    python3
    ruff
    basedpyright
  ];

  # Nix pins interpreters, through a project's flake or python3 above, so uv
  # never downloads one of its own.
  programs.uv = {
    enable = true;
    settings = {
      python-downloads = "never";
      python-preference = "only-system";
    };
  };
}
