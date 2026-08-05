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
      # Intentionally declarative: this preserves console and sudo access when
      # external secret storage is unavailable.
      hashedPassword = "$6$Na7d9SJRCkC6FyK7$3K.rYNPXX1.aeJe8f.2ylE2ITGLgxqv3CFvVYRsTiarQjFNZ.p2QZ/MIu1n6qz6wOO44lXU6wc9kmgIV.wboC/";
    };

    # Keep a password-independent recovery path. Root SSH remains key-only.
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
            zsh.enable = true;
          };
        };
      };
    };
  };
}
