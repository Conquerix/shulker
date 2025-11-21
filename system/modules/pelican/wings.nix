{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.pelican.wings;
in
{
  options.shulker.system.modules.pelican.wings = {
    enable = mkEnableOption "Enable Pelican wings service.";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where pelican wings will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "wings";
      description = "Default subdomain where pelican wings will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pelican/wings";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open pelican wings.";
    };
  };

  config = mkIf cfg.enable {

    users.groups.pelican.gid = 988;
    users.users.pelican = {
      isSystemUser = true;
      group = "pelican";
      uid = 988;
    };

    virtualisation.oci-containers.containers."pelican-wings" = {
      image = "ghcr.io/pelican-dev/wings:latest";
      environment = {
        "TZ" = "UTC";
        "WINGS_UID" = "988";
        "WINGS_GID" = "988";
        "WINGS_USERNAME" = "pelican";
      };
      ports = [ "127.0.0.1:${toString cfg.port}:8080" "2022:2022" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "/var/lib/docker/containers/:/var/lib/docker/containers/"
        "${cfg.stateDir}/etc/pelican/:/etc/pelican/"
        "${cfg.stateDir}/var/lib/pelican/:/var/lib/pelican/"
        "${cfg.stateDir}/var/log/pelican/:/var/log/pelican/"
        "${cfg.stateDir}/tmp/pelican/:/tmp/pelican/"
        "${cfg.stateDir}/etc/ssl/certs:/etc/ssl/certs:ro"
      ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."pelican-wings" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    environment.persistence = mkIf (cfg.impermanence) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=,o=";
          user = "pelican";
          group = "pelican";
        }
      ];
    };

    # services.onepassword-secrets.secrets.donetickEnv = {
      # reference = "op://Shulker/${config.networking.hostName}/Donetick env";
      # services = [ "docker" ];
    # };
  };
}
