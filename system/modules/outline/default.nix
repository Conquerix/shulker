{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.outline;
in
{
  options.shulker.modules.outline = {
    enable = mkEnableOption "Enable outline service.";
    url = mkOption {
      type = types.str;
      default = "wiki.example.com";
      description = "Url where outline will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Default internal port to open outline.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which outline will listen.";
    };
  };

  config = mkIf cfg.enable {

    opnix.secrets.outline-client-secret-key = {
      source = "{{ op://Shulker/${config.networking.hostName}/Outline Client Secret Key }}";
      user = config.services.outline.user;
      group = config.services.outline.group;
      mode = "0600";
    };

    opnix.systemdWantedBy = [ "outline-postgresql" ];

    services.outline = {
      enable = cfg.enable;
      publicUrl = "https://${cfg.url}";
      port = cfg.port;
      storage.storageType = "local";
      forceHttps = false;
      oidcAuthentication = {
        authUrl = "https://discordapp.com/api/oauth2/authorize";
        tokenUrl = "https://discordapp.com/api/oauth2/token";
        userinfoUrl = "https://discordapp.com/api/users/@me";
        clientId = "1170421650861334618";
        clientSecretFile = config.opnix.secrets.outline-client-secret-key.path;
        scopes = [ "email" "identify" ];
        usernameClaim = "preferred_username";
        displayName = "Discord";
      };
    };
    
    services.nginx = {
      enable = true;
      virtualHosts = {
        "outline" = {
        serverName = cfg.url;
        forceSSL = true;
        useACMEHost = "the-inbetween.net";
        locations."/" = {
          proxyPass = "http://${cfg.address}:${toString cfg.port}";
          extraConfig = ''
            proxy_set_header Upgrade $http_upgrade;    
            proxy_set_header Connection "upgrade";
          '';
        };
      };
    };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        "/var/lib/outline" 
        {
          directory = "/var/lib/redis-outline";
          user = "outline";
          group = "outline";
          mode = "u=rwx,g=rx,o=";
        }
        config.services.postgresql.dataDir
      ];
    };
  };
}
