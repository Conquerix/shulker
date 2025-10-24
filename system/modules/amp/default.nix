{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.amp;
in
{
  options.shulker.system.modules.amp = {
    enable = mkEnableOption "Enable amp service.";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where amp will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "amp";
      description = "Default subdomain where amp will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/amp";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open amp.";
    };
  };

  config = mkIf cfg.enable {

    users.groups.amp.gid = 2000;
    users.users.amp = {
      isSystemUser = true;
      group = "amp";
      uid = 2000;
    };

    # Containers
    virtualisation.oci-containers.containers."amp" = {
      image = "mitchtalmadge/amp-dockerized:latest";
      environmentFiles = [ config.services.onepassword-secrets.secrets.ampEnv.path ];
      environment = {
        "USERNAME" = "conquerix";
        "PASSWORD" = "please_change_me!"; # This is only the initial password.
        "TZ" = "Europe/Paris";
        "UID" = "${toString config.users.users.amp.uid}";
        "GID" = "${toString config.users.groups.amp.gid}";
      };
      volumes = [ "${cfg.stateDir}:/home/amp/:rw" ];
      ports = [
        "127.0.0.1:${toString cfg.port}:8080/tcp"
        "25565:25565" # Main minecraft port
        "35565:35565" # Secondary minecraft port for staging server
        "45565:45565" # Tertiary minecraft port for small test servers
      ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."amp" = {
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
          user = "amp";
          group = "amp";
        }
      ];
    };

    services.onepassword-secrets.secrets.ampEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Cubecoders AMP env";
      services = [ "docker" ];
    };
  };
}
