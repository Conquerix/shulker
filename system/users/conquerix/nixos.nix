{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.users.conquerix;
in
{

  config = lib.mkIf (cfg.enable && config.shulker.global.type == "nixos") {
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
      uid = 1000;
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILCQToe+S6lXjwMCrcg9smHlb8tEp2613jW/lOkfSSm1"
      ];
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
