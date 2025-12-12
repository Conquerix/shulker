{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.zitadel;
in
{
  options.shulker.system.modules.zitadel = {
    enable = mkEnableOption "Enable zitadel service";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where zitadel will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "zitadel";
      description = "Default subdomain where zitadel will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open zitadel.";
    };
    dbPort = mkOption {
      type = types.port;
      default = 5432;
      description = "Default internal port to open zitadel's db.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/zitadel";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    users.users.zitadel.extraGroups = [ "onepassword-secrets" ];

    services.zitadel = {
      enable = true;
      openFirewall = true;
      masterKeyFile = config.services.onepassword-secrets.secrets.zitadelMasterKey.path;
      extraSettingsPaths = [ config.services.onepassword-secrets.secrets.zitadelSettings.path ];

      tlsMode = "external";
      steps = {
        FirstInstance = {
          InstanceName = "Zitadel";
          Org = {
            Human = {
              UserName = "Conquerix";
              Password = "changeMe!123";
              PasswordChangeRequired = true;
              Email = {
                Address = "conquerix@shulker.link";
                Verified = true;
              };
            };
          };
        };
      };
      settings = {
        Port = cfg.port;
        ExternalPort = 443;
        ExternalDomain = "${cfg.subDomain}.${cfg.baseUrl}";
        Database = {
          postgres = {
            User = {
              username = "zitadel";
              SSL.Mode = "disable";
            };
            Admin = {
              username = "postgres";
              SSL.Mode = "disable";
            };
            Host = "127.0.0.1";
            Port = cfg.dbPort;
            Database = "zitadel";
            MaxOpenConns = 15;
            MaxIdleConns = 10;
            MaxConnLifetime = "1h";
            MaxConnIdleTime = "5m";
          };
        };
      };
    };

    virtualisation.oci-containers.containers.zitadel-db = {
      image = "postgres:17";
      ports = [ "${toString cfg.dbPort}:5432" ];
      environmentFiles = [ config.services.onepassword-secrets.secrets.zitadelPostgresEnv.path ];
      volumes = [
        "${cfg.stateDir}/db:/var/lib/postgresql/data"
      ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."zitadel" = {
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
          directory = "${cfg.stateDir}";
          mode = "u=rwx,g=,o=";
          user = "zitadel";
          group = "zitadel";
        }
      ];
    };

    services.onepassword-secrets.secrets = {
      zitadelMasterKey = {
        reference = "op://Shulker/${config.networking.hostName}/Zitadel master key";
        services = [ "zitadel" ];
        mode = "0750";
        owner = "zitadel";
        group = "zitadel";
      };
      zitadelSettings = {
        reference = "op://Shulker/${config.networking.hostName}/Zitadel settings";
        services = [ "zitadel" ];
        mode = "0750";
        owner = "zitadel";
        group = "zitadel";
      };
      zitadelPostgresEnv = {
        reference = "op://Shulker/${config.networking.hostName}/Zitadel Postgres env";
        services = [ "zitadel" ];
        mode = "0750";
        owner = "zitadel";
        group = "zitadel";
      };
    };
  };
}
