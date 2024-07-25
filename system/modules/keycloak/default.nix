{ config, lib, pkgs, callPackage, ... }:

with lib;
let
  cfg = config.shulker.modules.keycloak;
in
{
  options.shulker.modules.keycloak = {
    enable = mkEnableOption "Enable keycloak service.";
    url = mkOption {
      type = types.str;
      default = "auth.example.com";
      description = "Url where keycloak will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open keycloak.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which keycloak will listen.";
    };
  };

  config = mkIf cfg.enable {
    
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
      virtualHosts."keycloak" = {
        serverName = cfg.url;
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://${cfg.address}:${toString cfg.port}";
        };
      };
    };
  
    services.keycloak = {
      enable = true;

      plugins = with pkgs; [ keycloak-discord ];
  
      database = {
        type = "mariadb";
        createLocally = true;
  
        username = "keycloak";
        passwordFile = "/etc/keycloak/secrets/db_pass";
      };
  
      settings = {
        hostname = cfg.url;
        http-port = cfg.port;
        proxy = "edge";
        http-enabled = true;
        hostname-strict-backchannel = true;
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ "/etc/keycloak/secrets" ];
    };
  };
}
