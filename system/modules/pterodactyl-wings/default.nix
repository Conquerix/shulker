{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.pterodactyl.wings;
  wings = cfg.pkg;
in
{
  options.shulker.modules.pterodactyl.wings = {
    enable = mkEnableOption "Enable Pterodactyl Wings";
    version = mkOption {
      type = types.str;
      default = "latest";
    };
    pkg = mkOption { type = types.package; };
  };
  
  config = mkIf cfg.enable {

    users.users."pterodactyl" = {
      isSystemUser = true;
      createHome = true;
      home = "/srv/pterodactyl";
      group = "pterodactyl";
    };

    users.groups."pterodactyl" = { };

    shulker.modules.docker.enable = true;
    environment.systemPackages = [ wings ];
    systemd.services.wings = {
      enable = cfg.enable;
      description = "Pterodactyl Wings daemon";
      after = [ "docker.service" ];
      partOf = [ "docker.service" ];
      requires = [ "docker.service" ];
      startLimitIntervalSec = 180;
      startLimitBurst = 30;
      serviceConfig = {
        User = "root";
        WorkingDirectory = "/srv/wings";
        LimitNOFILE = 4096;
        PIDFile = "/var/run/wings/daemon.pid";
        ExecStart = "${cfg.pkg}/bin/wings --config /srv/wings/config.yml";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ "/srv/wings/" "/srv/pterodactyl/" ];
    };
  };
}
