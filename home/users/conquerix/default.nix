{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.shulker.users.conquerix;
in
{
  options.shulker.users.conquerix = {
    enable = lib.mkEnableOption "Enable conquerix' profile";
  };

  config = lib.mkIf cfg.enable (
    lib.custom.mkUserHome {
      inherit pkgs inputs;
      name = "conquerix";
      uid = 1000;
      hashedPassword = "$6$Na7d9SJRCkC6FyK7$3K.rYNPXX1.aeJe8f.2ylE2ITGLgxqv3CFvVYRsTiarQjFNZ.p2QZ/MIu1n6qz6wOO44lXU6wc9kmgIV.wboC/";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV"
      ];

      config = {

        home.packages = with pkgs; [
          prismlauncher
          ferium
          packwiz
          zoom-us
          spotify
          spotify-tray
          wineWowPackages.waylandFull
          libvlc
          easyeffects
          packwiz
          obsidian
        ];

        shulker.home = {
          modules = {
            app = {
              discord.enable = true;
              libreoffice.enable = true;
              vscodium.enable = true;
            };
            dev = {
              cc.enable = true;
              nix.enable = true;
              python.enable = true;
              ocaml.enable = true;
            };
            shell = {
              direnv.enable = true;
              ssh = {
                enable = true;
                _1password = true;
              };
              zsh.enable = true;
            };
          };

          profiles = {
            common.enable = true;
            development.enable = true;
          };
        };
      };
    }
  );
}
