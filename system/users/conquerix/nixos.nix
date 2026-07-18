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
    shulker.system.security.passwordHashSources.conquerix = "/etc/secrets/conquerix-password-hash";

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
      # The activation script validates the external hash and substitutes a
      # locked password when it is absent or unsafe.
      hashedPasswordFile = "/run/password-hashes/conquerix";
    };

    # Keep a password-independent recovery path when an immutable password
    # hash is missing or invalid. Root SSH remains key-only globally.
    users.users.root.openssh.authorizedKeys.keys =
      config.users.users.conquerix.openssh.authorizedKeys.keys;

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
