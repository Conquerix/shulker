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
  options.shulker.users.conquerix = {
    enable = lib.mkEnableOption "Enable conquerix' profile";
  };

  config = lib.mkIf cfg.enable {

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
        prismlauncher
        ferium
        packwiz
        spotify
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

      services.linux-wallpaperengine = {
        enable = true;
        assetsPath = "/home/conquerix/.local/share/Steam/steamapps/common/wallpaper_engine";
        wallpapers = [
          {
            monitor = "HDMI-2";
            wallpaperId = "3485875486";
          }
        ];
      };
    };
  };
}
