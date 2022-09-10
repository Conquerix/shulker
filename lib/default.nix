{ inputs, ... }:

with inputs.nixpkgs.lib;
let
  strToPath = x: path:
    if builtins.typeOf x == "string"
    then builtins.toPath ("${toString path}/${x}")
    else x;
  strToFile = x: path:
    if builtins.typeOf x == "string"
    then builtins.toPath ("${toString path}/${x}.nix")
    else x;
in
rec {
  firstOrDefault = first: default: if !isNull first then first else default;

  existsOrDefault = x: set: default: if hasAttr x set then getAttr x set else default;

  # Derivation agnostic settings for all types of top level derivations (nixos, home-manager && darwin).
  mkUserHome = { config, system ? "x86_64-linux" }:
    { ... }: {
      imports = [
        (import ../home/modules)
        (import ../home/profiles)
        (import config)
      ];

      # For compatibility with nix-shell, nix-build, etc.
      home.file.".nixpkgs".source = inputs.nixpkgs;
      home.sessionVariables."NIX_PATH" =
        "nixpkgs=$HOME/.nixpkgs\${NIX_PATH:+:}$NIX_PATH";

      # Use the same Nix configuration for the user
      xdg.configFile."nixpkgs/config.nix".source = ../nix/config.nix;

      # Re-expose self and nixpkgs as flakes.
      xdg.configFile."nix/registry.json".text = builtins.toJSON {
        version = 2;
        flakes =
          let
            toInput = input:
              {
                type = "path";
                path = input.outPath;
              } // (
                filterAttrs
                  (n: _: n == "lastModified" || n == "rev" || n == "revCount" || n == "narHash")
                  input
              );
          in
          [
            {
              from = { id = "nyx"; type = "indirect"; };
              to = toInput inputs.self;
            }
            {
              from = { id = "nixpkgs"; type = "indirect"; };
              to = toInput inputs.nixpkgs;
            }
          ];
      };

      # Needs reviewing/understanding.
      home.sessionPath = [ "$HOME/.local/nyx/bin" "$XDG_BIN_HOME" ];

      home.stateVersion = "22.05";
    };

  mkSystem = name: { config ? name, user ? "nixos", system ? "x86_64-linux" }:
    nameValuePair name (
      let
        pkgs = inputs.self.pkgsBySystem."${system}";
        userConf = import (strToFile user ../user);
      in
      nixosSystem {
        inherit system;
        modules = [
          (
            { name, ... }: {
              networking.hostName = name;
            }
          )
          (
            { inputs, ... }: {
              # Use the nixpkgs from the flake.
              nixpkgs = { inherit pkgs; };

              # For compatibility with nix-shell, nix-build, etc.
              environment.etc.nixpkgs.source = inputs.nixpkgs;
              nix.nixPath = [ "nixpkgs=/etc/nixpkgs" ];
            }
          )
          (
            { pkgs, ... }: {
              # Don't rely on the configuration to enable a flake-compatible version of Nix.
              nix = {
                package = pkgs.nixFlakes;
                extraOptions = "experimental-features = nix-command flakes";
              };
            }
          )
          (
            { inputs, ... }: {
              # Re-expose self and nixpkgs as flakes.
              nix.registry = {
                self.flake = inputs.self;
                nixpkgs = {
                  from = { id = "nixpkgs"; type = "indirect"; };
                  flake = inputs.nixpkgs;
                };
              };
            }
          )
          (
            { ... }: {
              system.stateVersion = "22.05";
            }
          )
          (inputs.home-manager.nixosModules.home-manager)
          (
            {
              home-manager = {
                # useUserPackages = true;
                useGlobalPkgs = true;
                extraSpecialArgs =
                  let
                    self = inputs.self;
                    user = userConf;
                  in
                  # NOTE: Cannot pass name to home-manager as it passes `name` in to set the `hmModule`
                  { inherit inputs self system user; };
              };
            }
          )
          (import ../system/common/modules)
          (import ../system/common/profiles)
          (import ../system/nixos/modules)
          (import ../system/nixos/profiles)
          (import (strToPath config ../system/nixos/hosts))
        ];
        specialArgs =
          let
            self = inputs.self;
            user = userConf;
          in
          { inherit inputs name self system user; };
      }
    );
}
