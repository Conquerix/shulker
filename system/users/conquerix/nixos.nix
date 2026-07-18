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
        "wheel"
      ]
      ++ lib.optionals config.shulker.system.profiles.desktop.enable [
        "audio"
        "video"
        "games"
        "networkmanager"
        "plugdev"
        "adbusers"
        "kvm"
      ];
      # Keep the password hash out of the Nix store and Git history. With
      # mutableUsers enabled, an existing password remains valid when this
      # file is absent; fresh installs start with password login disabled.
      hashedPasswordFile = "/etc/secrets/conquerix-password-hash";
    };

    home-manager.users.conquerix = {
      home.packages = with pkgs; [
        prismlauncher
        packwiz
        wineWow64Packages.waylandFull
        libvlc
        easyeffects
      ];

      shulker.home = {
        modules = {
          app = {
            discord.enable = true;
            vscode.enable = true;
          };
          dev = {
            cc.enable = true;
            nix.enable = true;
            #python.enable = true;
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
      };
    };
  };
}
