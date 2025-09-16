# FIXME(lib.custom): Add some stuff from hmajid2301/dotfiles/lib/module/default.nix, as simplifies option declaration
{ inputs, lib, ... }:
{
  # use path relative to the root of the project
  relativeToRoot = lib.path.append ../.;
  scanPaths =
    path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          path: _type:
          (_type == "directory") # include directories
          || (
            (path != "default.nix") # ignore default.nix
            && (lib.strings.hasSuffix ".nix" path) # include .nix files
          )
        ) (builtins.readDir path)
      )
    );
  # Derivation agnostic settings for all types of top level derivations (nixos, home-manager && darwin).
  mkUserHome =
    {
      inputs,
      pkgs,
      name,
      hashedPassword,
      uid,
      sshKeys,
      config,
    }:
    {
      users.users.${name} = {
        hashedPassword = hashedPassword;
        isNormalUser = true;
        extraGroups = [
          "audio"
          "video"
        ];
        shell = pkgs.bash;
        uid = uid;
        openssh.authorizedKeys.keys = sshKeys;
      };

      nix.settings.trusted-users = [ name ];

      home-manager.users.${name} = lib.mkMerge [
        {
          imports = [
            (import ../home/modules)
            (import ../home/profiles)
          ];

          # For compatibility with nix-shell, nix-build, etc.
          home.file.".nixpkgs".source = inputs.nixpkgs;
          home.sessionVariables."NIX_PATH" = "nixpkgs=$HOME/.nixpkgs\${NIX_PATH:+:}$NIX_PATH";

          # Use the same Nix configuration for the user
          xdg.configFile."nixpkgs/config.nix".source = ../nix/config.nix;

          # Re-expose self and nixpkgs as flakes.
          xdg.configFile."nix/registry.json".text = builtins.toJSON {
            version = 2;
            flakes =
              let
                toInput =
                  input:
                  {
                    type = "path";
                    path = input.outPath;
                  }
                  // (lib.filterAttrs (
                    n: _: n == "lastModified" || n == "rev" || n == "revCount" || n == "narHash"
                  ) input);
              in
              [
                {
                  from = {
                    id = "shulker";
                    type = "indirect";
                  };
                  to = toInput inputs.self;
                }
                {
                  from = {
                    id = "nixpkgs";
                    type = "indirect";
                  };
                  to = toInput inputs.nixpkgs;
                }
              ];
          };

          # Directories to add to the PATH environment variable
          home.sessionPath = [
            "$HOME/.local/shulker/bin"
            "$XDG_BIN_HOME"
          ];

          home.stateVersion = "22.05";
        }

        config
      ];
    };
}
