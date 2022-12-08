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
      "/var/lib/bluetooth"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      {directory = "/etc/nixos"; user = "root"; group = "config"; mode = "u=rw,g=rw,o=r";}
      (mkIf (cfg.home) "/home")
      ];

    files = [
      "/etc/machine-id"
      ];
    };
  };
}
