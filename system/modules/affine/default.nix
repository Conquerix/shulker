{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.affine;
in
{
  options.shulker.system.modules.affine = {
    enable = mkEnableOption "Enable affine service.";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where affine will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "affine";
      description = "Default subdomain where affine will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/affine";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open affine.";
    };
    dbPort = mkOption {
      type = types.port;
      default = 5432;
      description = "Default internal port to open affine's DB.";
    };
  };

  config = mkIf cfg.enable {

    # Containers
    virtualisation.oci-containers.containers."affine_migration_job" = {
      image = "ghcr.io/toeverything/affine:stable";
      environment = {
        "AFFINE_INDEXER_ENABLED" = "false";
        "REDIS_SERVER_HOST" = "redis";
      };
      volumes = [
        "${cfg.stateDir}/config:/root/.affine/config:rw"
        "${cfg.stateDir}/storage:/root/.affine/storage:rw"
      ];
      cmd = [ "sh" "-c" "node ./scripts/self-host-predeploy.js" ];
      dependsOn = [ "affine_postgres" "affine_redis" ];
      log-driver = "journald";
      extraOptions = [ "--network-alias=affine_migration" "--network=affine_default" ];
    };
    systemd.services."docker-affine_migration_job" = {
      serviceConfig = { Restart = lib.mkOverride 90 "no"; };
      after = [ "docker-network-affine_default.service" ];
      requires = [ "docker-network-affine_default.service" ];
      partOf = [ "docker-compose-affine-root.target" ];
      wantedBy = [ "docker-compose-affine-root.target" ];
    };
    virtualisation.oci-containers.containers."affine_postgres" = {
      image = "pgvector/pgvector:pg16";
      environment = {
        "POSTGRES_DB" = "affine";
        "POSTGRES_HOST_AUTH_METHOD" = "trust";
        "POSTGRES_INITDB_ARGS" = "--data-checksums";
      };
      volumes = [ "${cfg.stateDir}/postgresql/data:/var/lib/postgresql/data:rw" ];
      log-driver = "journald";
      extraOptions = [
        "--health-cmd=[\"pg_isready\", \"-U\", \"\", \"-d\", \"affine\"]"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-timeout=5s"
        "--network-alias=postgres"
        "--network=affine_default"
      ];
    };
    systemd.services."docker-affine_postgres" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
      };
      after = [ "docker-network-affine_default.service" ];
      requires = [ "docker-network-affine_default.service" ];
      partOf = [ "docker-compose-affine-root.target" ];
      wantedBy = [ "docker-compose-affine-root.target" ];
    };
    virtualisation.oci-containers.containers."affine_redis" = {
      image = "redis";
      log-driver = "journald";
      extraOptions = [
        "--health-cmd=[\"redis-cli\", \"--raw\", \"incr\", \"ping\"]"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-timeout=5s"
        "--network-alias=redis"
        "--network=affine_default"
      ];
    };
    systemd.services."docker-affine_redis" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
      };
      after = [ "docker-network-affine_default.service" ];
      requires = [ "docker-network-affine_default.service" ];
      partOf = [ "docker-compose-affine-root.target" ];
      wantedBy = [ "docker-compose-affine-root.target" ];
    };
    virtualisation.oci-containers.containers."affine_server" = {
      image = "ghcr.io/toeverything/affine:stable";
      environment = {
        "AFFINE_INDEXER_ENABLED" = "false";
        "REDIS_SERVER_HOST" = "redis";
      };
      volumes = [
        "${cfg.stateDir}/config:/root/.affine/config:rw"
        "${cfg.stateDir}/storage:/root/.affine/storage:rw"
      ];
      ports = [ "127.0.0.1:${toString cfg.port}:3010/tcp" ];
      dependsOn = [ "affine_migration_job" "affine_postgres" "affine_redis" ];
      log-driver = "journald";
      extraOptions = [ "--network-alias=affine" "--network=affine_default" ];
    };
    systemd.services."docker-affine_server" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
      };
      after = [ "docker-network-affine_default.service" ];
      requires = [ "docker-network-affine_default.service" ];
      partOf = [ "docker-compose-affine-root.target" ];
      wantedBy = [ "docker-compose-affine-root.target" ];
    };

    # Networks
    systemd.services."docker-network-affine_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "docker network rm -f affine_default";
      };
      script = ''docker network inspect affine_default || docker network create affine_default'';
      partOf = [ "docker-compose-affine-root.target" ];
      wantedBy = [ "docker-compose-affine-root.target" ];
    };

    # Root service
    # When started, this will automatically create all resources and start
    # the containers. When stopped, this will teardown all resources.
    systemd.targets."docker-compose-affine-root" = {
      unitConfig.Description = "Root target generated by compose2nix.";
      wantedBy = [ "multi-user.target" ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."affine" = {
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
          user = "authentik";
          group = "authentik";
        }
      ];
    };

    services.onepassword-secrets.secrets.affineEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Affine env";
      services = [ "docker" ];
    };
  };
}
