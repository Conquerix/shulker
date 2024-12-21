{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.impermanence;
in
{
  options.shulker.modules.impermanence = {
    enable = mkEnableOption "Ephemeral root (& home) support";

    home = mkEnableOption "Link /home to /nix/persist/home";
  };

  config = mkIf cfg.enable {

    environment.persistence."/nix/persist" = {

      hideMounts = true;

      directories = [
        "/var/log"
        "/var/lib/nixos"
        "/var/lib/bluetooth"
        "/var/lib/systemd/coredump"
        "/var/lib/acme"
        "/etc/NetworkManager/system-connections"
        "/etc/nixos"
        "/etc/secrets"
        "/root/.ssh"
        "/var/lib/docker"
        "/var/lib/tailscale"
        (mkIf (cfg.home) "/home")
      ];

      files = [
        "/etc/machine-id"
        {file = config.opnix.environmentFile; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };
  };
}
