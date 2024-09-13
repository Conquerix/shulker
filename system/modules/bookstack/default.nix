{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.bookstack;
in
{
  options.shulker.modules.bookstack = {
    enable = mkEnableOption "Enable bookstack service.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where bookstack will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "gitea";
      description = "Default subdomain where bookstack will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Default internal port to open bookstack.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which bookstack will listen.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/bookstack";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    opsm.secrets.bookstack-client-secret-key = {
      secretRef = "op://Shulker/${config.networking.hostName}/Bookstack Client Secret Key";
      user = config.services.bookstack.user;
      group = config.services.bookstack.group;
    };

    services.bookstack = {
      enable = true;
      hostName = "${cfg.subDomain}.${cfg.baseUrl}";
      dataDir = cfg.stateDir;
      database.createLocally = true;
      config = {
        AUTH_METHOD = "oidc";
        OIDC_NAME = "Discord";
        OIDC_DISPLAY_NAME_CLAIMS = "preferred_username";
        OIDC_CLIENT_ID = "1170421650861334618";
        OIDC_CLIENT_SECRET = {_secret = "/secrets/bookstack-client-secret-key";};
        OIDC_ISSUER_DISCOVER = false;
        OIDC_AUTH_ENDPOINT = "https://discordapp.com/api/oauth2/authorize";
        OIDC_TOKEN_ENDPOINT = "https://discordapp.com/api/oauth2/token";
        OIDC_USERINFO_ENDPOINT = "https://discordapp.com/api/users/@me";
      };
      nginx = {
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          user = services.bookstack.user;
          group = services.bookstack.group;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };
  };
}
