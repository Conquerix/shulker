{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.rauthy;
  configFile = pkgs.writeText "config.toml" 
    ''
    # For details see: https://sebadob.github.io/rauthy/config/config.html
    [bootstrap]
    admin_email = "conquerix@shulker.link"
    password_plain = 'changeMe!123' # password to change when first creating the instance.

    [cluster]
    node_id = 1
    nodes = [ "1 localhost:8100 localhost:8200" ]

    # values to be set in secret env file.
    # HQL_SECRET_RAFT
    # HQL_SECRET_API

    [email]
    # values to be set in secret env file.
    # SMTP_URL
    # SMTP_PORT
    # SMTP_USERNAME
    # SMTP_PASSWORD
    # SMTP_FROM

    [encryption]
    # values to be set in secret env file.
    # ENC_KEYS # generated using 'echo "$(openssl rand -hex 4)/$(openssl rand -base64 32)"'
    # ENC_KEY_ACTIVE

    [events]
    email = "conquerix@shulker.link"

    [server]
    scheme = "http"
    pub_url = "https://${cfg.subDomain}.${cfg.baseUrl}"
    proxy_mode = true
    trusted_proxies = ['127.0.0.1/32']

    [webauthn]
    rp_id = "${cfg.subDomain}.${cfg.baseUrl}"
    rp_origin = "https://${cfg.subDomain}.${cfg.baseUrl}:443"

    '';
in
{
  options.shulker.system.modules.rauthy = {
    enable = mkEnableOption "Enable rauthy service";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where rauthy will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "rauthy";
      description = "Default subdomain where rauthy will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open donetick.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/rauthy";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {
    users.groups.rauthy.gid = 10001;
    users.users.rauthy = {
      isSystemUser = true;
      group = "rauthy";
      uid = 10001;
    };

    virtualisation.oci-containers.containers."rauthy" = {
      image = "ghcr.io/sebadob/rauthy:latest";
      ports = [ "127.0.0.1:${toString cfg.port}:8443" ];
      environmentFiles = [ config.services.onepassword-secrets.secrets.rauthyEnv.path ];
      volumes = [
        "${cfg.stateDir}/data:/app/data"
        "${configFile}:/app/config.toml"
      ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."rauthy" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "https://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    environment.persistence = mkIf (cfg.impermanence) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=,o=";
          user = "rauthy";
          group = "rauthy";
        }
      ];
    };

    services.onepassword-secrets.secrets.rauthyEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Rauthy env";
      services = [ "docker" ];
      owner = "rauthy";
      group = "rauthy";
    };
  };
}
