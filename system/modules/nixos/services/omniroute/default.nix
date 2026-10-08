# Private subscription gateway; application state stays writable across image updates.
{ config, lib, ... }:
let
  cfg = config.shulker.system.modules.omniroute;
in
{
  options.shulker.system.modules.omniroute = {
    enable = lib.mkEnableOption "OmniRoute";
    impermanence = lib.mkEnableOption "persistent OmniRoute data";
    image = lib.mkOption {
      type = lib.types.str;
      description = "Verified upstream base image pinned to a registry digest or local image ID.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/omniroute";
    };
    imageArchiveDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/omniroute-images";
      description = "Root-owned recovery archives for locally built images.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 23250;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ai.shulker.link";
      description = "Owner-protected dashboard URL through Pangolin.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasInfix "@sha256:" cfg.image || lib.hasPrefix "sha256:" cfg.image;
        message = "OmniRoute requires a verified registry digest or local image ID.";
      }
    ];
    shulker.system.modules.containers.enable = true;
    users.groups.omniroute.gid = 10002;
    users.users.omniroute = {
      isSystemUser = true;
      uid = 10002;
      group = "omniroute";
    };
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 omniroute omniroute -"
      "d ${cfg.imageArchiveDir} 0700 root root -"
    ];

    virtualisation.oci-containers.containers.omniroute = {
      image = cfg.image;
      pull = "missing";
      user = "10002:10002";
      ports = [ "127.0.0.1:${toString cfg.port}:20128" ];
      volumes = [ "${cfg.stateDir}:/app/data:rw" ];
      environment = {
        HOME = "/app/data";
        DATA_DIR = "/app/data";
        PORT = "20128";
        HOSTNAME = "0.0.0.0";
        NEXT_PUBLIC_BASE_URL = cfg.publicUrl;
        AUTH_COOKIE_SECURE = "true";
        REQUIRE_API_KEY = "true";
        # One private instance needs no Redis or additional client request budget.
        REDIS_URL = "";
        DEFAULT_RATE_LIMIT_PER_DAY = "0";
        OMNIROUTE_MEMORY_MB = "8192";
      };
      environmentFiles = [ config.services.onepassword-secrets.secrets.omnirouteEnv.path ];
      extraOptions = [
        "--memory=10g"
        "--cpus=2"
        "--pids-limit=512"
      ];
    };
    services.onepassword-secrets.secrets.omnirouteEnv = {
      reference = "op://Shulker/${config.networking.hostName}/OmniRoute/Environment";
      services = [ "docker-omniroute" ];
      mode = "0400";
    };
    systemd.services.docker-omniroute = {
      requires = [ "opnix-secrets.service" ];
      unitConfig.RequiresMountsFor = [ cfg.stateDir ];
    };
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "0700";
          user = "omniroute";
          group = "omniroute";
        }
        {
          directory = cfg.imageArchiveDir;
          mode = "0700";
          user = "root";
          group = "root";
        }
      ];
    };
    shulker.system.modules.backup.dirs = [
      cfg.stateDir
      cfg.imageArchiveDir
    ];
    # Capture a consistent SQLite dump; raw WAL files alone are not a restore point.
    services.borgmatic.settings.sqlite_databases = [
      {
        name = "omniroute";
        path = "${cfg.stateDir}/storage.sqlite";
      }
    ];
  };
}
