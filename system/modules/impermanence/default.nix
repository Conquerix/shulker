{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.impermanence;
in
{
  options.shulker.modules.impermanence = {
    enable = mkEnableOption "Ephemeral root (& home) support";

    home = mkEnableOption "Link /home to /nix/persist/home";

    docker = mkEnableOption "Link /var/lib/docker to /nix/persist/var/lib/docker";
  };

  config = mkIf cfg.enable {

    environment.persistence."/nix/persist" = {

      hideMounts = true;

      directories = [
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/systemd/coredump"
        "/etc/NetworkManager/system-connections"
        "/etc/nixos"
        "/etc/ssh"
        "/etc/secrets"
        "/root/.ssh"
        (mkIf (cfg.home) "/home")
        (mkIf (cfg.docker) "/var/lib/docker")
      ];

      files = [
        "/etc/machine-id"
      ];
    };
  };
}
