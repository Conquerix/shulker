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
      default = "bookstack";
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

    opnix.secrets.bookstack-client-secret-key = {
      source = "{{ op://Shulker/${config.networking.hostName}/Bookstack Client Secret Key }}";
      user = config.services.bookstack.user;
      group = config.services.bookstack.group;
      mode = "0600";
    };

    opnix.secrets.bookstack-app-secret = {
      source = "{{ op://Shulker/${config.networking.hostName}/Bookstack App Secret }}";
      user = config.services.bookstack.user;
      group = config.services.bookstack.group;
      mode = "0600";
    };

    opnix.systemdWantedBy = [ "bookstack-setup" ];

    services.bookstack = {
      enable = true;
      hostname = "${cfg.subDomain}.${cfg.baseUrl}";
      dataDir = cfg.stateDir;
      database.createLocally = true;
      appKeyFile = config.opnix.secrets.bookstack-client-secret-key.path;
      config = {
        DISCORD_APP_ID = 1170421650861334618;
        DISCORD_APP_SECRET = {_secret = config.opnix.secrets.bookstack-app-secret.path;};
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
          user = config.services.bookstack.user;
          group = config.services.bookstack.group;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };
  };
}
