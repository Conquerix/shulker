{
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
{
  config = {
    nixpkgs.config.allowUnfree = true;

    # For compatibility with nix-shell, nix-build, etc.
    environment.etc.nixpkgs.source = inputs.nixpkgs;

    home-manager = {
      useGlobalPkgs = true;
      extraSpecialArgs = { inherit inputs; };
      sharedModules = [ (import ../../../../home) ];
    };

    nix = {
      # Don't rely on the configuration to enable a flake-compatible version of Nix.
      extraOptions = "experimental-features = nix-command flakes";
      nixPath = [ "nixpkgs=/etc/nixpkgs" ];
      registry = {
        self.flake = inputs.self;
        nixpkgs = {
          from = {
            id = "nixpkgs";
            type = "indirect";
          };
          flake = inputs.nixpkgs;
        };
      };

      settings = {
        trusted-users = [ "conquerix" ];
        allowed-users = [ "root" ];
      };

      optimise.automatic = true;
    };

    time.timeZone = "Europe/Paris";

    # List of bare minimal requirements for a system to have to bootstrap from
    environment.systemPackages = with pkgs; [
      curl
      git
      git-lfs
      micro
      openssl
      zip
      bat
      htop
      gping # better ping
      eza # better ls
    ];

    environment.shellAliases = {
      ping = "gping";
      l = "eza -oluag --git";
      ls = "eza";
      ll = "eza -olug --git";
      ".." = "cd ..";
    };

    programs.direnv.enable = true;
  };
}
