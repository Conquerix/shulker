{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.gitea;
in
{
  options.shulker.modules.gitea = {
    enable = mkEnableOption "Enable gitea service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where gitea will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "gitea";
      description = "Default subdomain where gitea will be accessible.";
    };
    httpPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open gitea.";
    };
    sshPort = mkOption {
      type = types.port;
      default = 22;
      description = "SSH Port to display in gitea.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/gitea";
      description = "State Directory.";
    };
    backupDir = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/dump";
      description = "Backup Directory.";
    };
  };

  config = mkIf cfg.enable {

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };

    services.gitea = {
      enable = true;
      #useWizard = true;
      stateDir = cfg.stateDir;
      lfs.enable = true;
      settings = {
        session = {
          COOKIE_SECURE = true;
        };
        service = {
          #DISABLE_REGISTRATION = true;
        };
        server = {
          ROOT_URL = "https://${cfg.subDomain}.${cfg.baseUrl}:443";
          DOMAIN = "${cfg.subDomain}.${cfg.baseUrl}";
          HTTP_PORT = cfg.httpPort;
          SSH_PORT = cfg.sshPort;
          #PROTOCOL = "https";
        };
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts."gitea" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          #extraConfig = "rewrite ^/user/login.*$ /user/oauth2/Zitadel last;";
        };
      };
    };
  };
}
