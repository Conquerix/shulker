# Development tools and Git hooks shared with the flake's validation checks.
{
  pkgs ?
    # Non-flake callers use the same nixpkgs revision recorded in flake.lock.
    let
      lock = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
      nixpkgs = fetchTarball {
        url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
        sha256 = lock.narHash;
      };
    in
    import nixpkgs { overlays = [ ]; },
  checks,
  ...
}:
{
  default = pkgs.mkShell {
    NIX_CONFIG = "extra-experimental-features = nix-command flakes";

    # Entering the shell installs hooks; their executables are also available directly.
    inherit (checks.pre-commit-check) shellHook;
    buildInputs = checks.pre-commit-check.enabledPackages;

    nativeBuildInputs = builtins.attrValues {
      inherit (pkgs)

        nix
        home-manager
        nh
        git
        ;
    };
  };
}
