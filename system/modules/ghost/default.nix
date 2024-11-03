{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.ghost;
in
{
  options.shulker.modules.ghost = {
    enable = mkEnableOption "Enable ghost service";
    url = mkOption {
      type = types.str;
      default = "blog.example.com";
      description = "Default url where ghost will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 2368;
      description = "Default internal port to open searx.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which searx will listen.";
    };
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/ghost";
      description = "Data directory of ghost.";
    };
  };

  config = mkIf cfg.enable {

    opnix.secrets.ghost-mailgun-smtp-secret-key = {
      source = "{{ op://Shulker/${config.networking.hostName}/Mailgun SMTP Secret Key }}";
      mode = "0600";
    };

    virtualisation.oci-containers.containers = {
      ghost = {
        image = "ghost:latest";
        ports = [ "${toString cfg.port}:2368" ];
        environment = {
          #NODE_ENV = "development";
          database__client = "sqlite3";
          database__connection__filename = "/var/lib/ghost/content/data/ghost.db";
          url = "https://${cfg.url}";
          #mail__from = "admin@${cfg.url}";
          mail__transport = "SMTP";
          mail__options__service = "Mailgun";
          mail__options__host = "smtp.eu.mailgun.org";
          mail__options__port = "465";
          mail__options__secure = "true";
          mail__options__auth__user = "noreply@${cfg.url}";
          #tls__rejectUnauthorized = "false";
        };
        environmentFiles = [
          config.opnix.secrets.ghost-mailgun-smtp-secret-key.path
        ];
        volumes = [
          "${cfg.dataDir}:/var/lib/ghost/content"
        ];
      };
    };
    
    services.nginx = {
      enable = true;
      virtualHosts."ghost" = {
        serverName = cfg.url;
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
        extraConfig = ''
          client_max_body_size 500M;
        '';
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        cfg.dataDir
      ];
    };
  };
}
