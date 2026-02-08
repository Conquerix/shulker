{
  config,
  lib,
  ...
}:

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

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 2022 ];
      allowedUDPPorts = [ 2022 ];
    };

    systemd.services.wings.serviceConfig.StateDirectory = mkForce cfg.stateDir;

    services.wings = {
      enable = true;
      node = {
        api.port = cfg.port;
        system = {
          root_directory = "${cfg.stateDir}";
          backup_directory = "${cfg.stateDir}/backups";
          archive_directory = "${cfg.stateDir}/archives";
          data = "${cfg.stateDir}/volumes";
        };
        tokenPath = config.services.onepassword-secrets.secrets.pelicanWingsToken.path;
        docker.network = {
          interface = "172.55.0.1";
          interfaces.v4 = {
            subnet = "172.55.0.0/16";
            gateway = "172.55.0.1";
          };
        };
        # Configure the rest in the node's config directly.
        # uuid = "<node-uuid>";
        # tokenId = "<node-token>";
        # remote = "<node-remote>";
      };
    };

    # services.nginx = {
    #   enable = true;
    #   virtualHosts."pelican-wings" = {
    #     serverName = "${cfg.subDomain}.${cfg.baseUrl}";
    #     forceSSL = true;
    #     useACMEHost = cfg.baseUrl;
    #     locations."/" = {
    #       proxyWebsockets = true;
    #       proxyPass = "http://127.0.0.1:${toString cfg.port}";
    #     };
    #   };
    # };

    environment = mkIf (cfg.impermanence) {
      persistence."/nix/persist".directories = [
        {
          directory = "${cfg.stateDir}/archives";
          mode = "u=rwx,g=,o=";
          user = "pelican";
          group = "pelican";
        }
        {
          directory = "${cfg.stateDir}/backups";
          mode = "u=rwx,g=,o=";
          user = "pelican";
          group = "pelican";
        }
        {
          directory = "${cfg.stateDir}/volumes";
          mode = "u=rwx,g=,o=";
          user = "pelican";
          group = "pelican";
        }
      ];
      persistence."/nix/persist".files = [
        {
          file = "${cfg.stateDir}/wings.db";
          parentDirectory = {
            mode = "u=rwx,g=,o=";
            user = "pelican";
            group = "pelican";
          };
        }
      ];
    };

    shulker.system.modules.backup.dirs = [
      "${cfg.stateDir}/backups"
      "${cfg.stateDir}/archives"
    ];
    services.borgmatic.settings.sqlite_databases = [
      {
        name = "pelican-wings-db";
        path = "${cfg.stateDir}/wings.db";
      }
    ];

    services.onepassword-secrets.secrets.pelicanWingsToken = {
      reference = "op://Shulker/${config.networking.hostName}/Pelican Wings token";
      services = [
        "wings"
        "wings-config-setup"
      ];
    };
  };
}
