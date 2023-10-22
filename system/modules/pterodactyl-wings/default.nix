{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.pterodactyl.wings;
  configuration = ''
    # /etc/pterodactyl/configuration.yml managed by /etc/NixOS/wings.nix
  '' + "${cfg.configuration}";
  wings = cfg.pkg;
in
{
  options.shulker.modules.pterodactyl.wings = {
    enable = mkEnableOption "Enable Pterodactyl Wings";
    configuration = mkOption {
      type = types.str;
      default = null;
    };
    version = mkOption {
      type = types.str;
      default = "latest";
    };
    pkg = mkOption { type = types.package; };
  };
  
  config = mkIf cfg.enable {
    assertions = [{
      assertion = cfg.configuration != null;
      message = "wings is enabled, configuration must be set.";
    }];

    shulker.modules.docker.enable = true;
    environment.etc."pterodactyl/config.yml".text = configuration;
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
        WorkingDirectory = "/run/wings";
        LimitNOFILE = 4096;
        PIDFile = "/var/run/wings/daemon.pid";
        ExecStart = "${cfg.pkg}/bin/wings --config /srv/wings/config.yml";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".files = [
        {file = "/srv/wings/config.yml"; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };
  };
}
