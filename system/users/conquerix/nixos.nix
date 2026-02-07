{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.users.conquerix;
  isNixOS = config.shulker.global.type == "nixos";
in
{

  config = lib.mkIf (cfg.enable && isNixOS) {
    users.users.conquerix = {
      isNormalUser = true;
      extraGroups = [
        "audio"
        "video"
        "docker"
        "games"
        "locate"
        "networkmanager"
        "wheel"
        "plugdev"
        "adbusers"
        "kvm"
        "disk"
      ];
      hashedPassword = "$6$Na7d9SJRCkC6FyK7$3K.rYNPXX1.aeJe8f.2ylE2ITGLgxqv3CFvVYRsTiarQjFNZ.p2QZ/MIu1n6qz6wOO44lXU6wc9kmgIV.wboC/";
    };

    home-manager.users.conquerix = {
      home.packages = with pkgs; [
        spotify
        prismlauncher
        ferium
        packwiz
        wineWowPackages.waylandFull
        libvlc
        easyeffects
        ryubing
      ];

      shulker.home = {
        modules = {
          app = {
            discord.enable = true;
            libreoffice.enable = true;
            vscode.enable = true;
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

        profiles.development.enable = true;
      };
    };
  };
}
