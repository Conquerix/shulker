{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.wallos;
in
{
  options.shulker.system.modules.wallos = {
    enable = mkEnableOption "Enable wallos service.";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Url where wallos will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "wallos-aio";
      description = "Subdomain where wallos aio will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Internal port to open wallos.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/wallos";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    # Containers
    virtualisation.oci-containers.containers."wallos" = {
      image = "bellamy/wallos:latest";
      environment = {
        "TZ" = "Europe/Paris";
      };
      volumes = [
        "${cfg.stateDir}/db:/var/www/html/db"
        "${cfg.stateDir}/logos:/var/www/html/images/uploads/logos"
      ];
      ports = [
        "127.0.0.1:${toString cfg.port}:80/tcp"
      ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."wallos" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };
  };
}
