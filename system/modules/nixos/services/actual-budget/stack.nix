{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.actual-budget;
  composeConfig = {
    name = "actual-budget";
    services.server = {
      image = cfg.image;
      container_name = "actual-budget";
      command = [
        "node"
        "/run/actual-budget-start.mjs"
      ];
      restart = "on-failure:5";
      stop_grace_period = "60s";
      ports = [ "127.0.0.1:${toString cfg.port}:5006/tcp" ];
      volumes = [
        "${cfg.stateDir}/data:/data"
        "${./start.mjs}:/run/actual-budget-start.mjs:ro"
      ];
      env_file = [
        {
          path = config.services.onepassword-secrets.secrets.actualBudgetEnv.path;
          format = "raw";
        }
      ];
      environment = {
        ACTUAL_OPENID_DISCOVERY_URL = "${cfg.oidcIssuer}/.well-known/openid-configuration";
        ACTUAL_OPENID_SERVER_HOSTNAME = cfg.publicUrl;
        ACTUAL_OPENID_AUTH_METHOD = "openid";
        ACTUAL_OPENID_ENFORCE = "true";
        ACTUAL_USER_CREATION_MODE = "manual";
        ACTUAL_TOKEN_EXPIRATION = "2592000";
      };
      logging = {
        driver = "json-file";
        options = {
          max-size = "10m";
          max-file = "3";
        };
      };
      healthcheck = {
        test = [
          "CMD"
          "node"
          "-e"
          "fetch('http://127.0.0.1:5006/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
        ];
        interval = "30s";
        timeout = "10s";
        retries = 5;
        start_period = "30s";
      };
    };
  };
  composeFile = pkgs.writeText "actual-budget-compose.json" (builtins.toJSON composeConfig);
  compose = pkgs.writeShellApplication {
    name = "actual-budget-compose";
    runtimeInputs = [ pkgs.docker-compose ];
    text = ''exec docker-compose --project-name actual-budget --file ${composeFile} "$@"'';
  };
  runtime = pkgs.writeShellApplication {
    name = "actual-budget-runtime";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''exec ${pkgs.bash}/bin/bash ${./runtime.sh} "$1" ${lib.escapeShellArg cfg.stateDir} ${lib.escapeShellArg cfg.dataset} /run/lock/actual-budget-maintenance.lock ${compose}/bin/actual-budget-compose ${cfg.validateStatePackage}/bin/actual-budget-validate-state'';
  };
  health = pkgs.writeShellApplication {
    name = "actual-budget-health-check";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.curl
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      exec 9>/run/lock/actual-budget-maintenance.lock
      flock -w 900 9
      systemctl is-active --quiet actual-budget-compose.service || exit 0
      curl --fail --silent --show-error http://127.0.0.1:${toString cfg.port}/health >/dev/null
      [ "$(docker inspect --format '{{.State.Health.Status}}' actual-budget)" = healthy ]
    '';
  };
in
{
  options.shulker.system.modules.actual-budget = {
    composeConfig = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
    };
    runtimePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
    };
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.actual-budget = {
      inherit composeConfig;
      runtimePackage = runtime;
    };
    environment.systemPackages = [
      compose
      runtime
      health
    ];
    systemd.services.actual-budget-image-pull = {
      description = "Pull pinned Actual Budget image";
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      after = [
        "docker.service"
        "network-online.target"
      ];
      restartTriggers = [ cfg.image ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.virtualisation.docker.package}/bin/docker pull ${cfg.image}";
        TimeoutStartSec = 1800;
      };
    };
    systemd.services.actual-budget-compose = {
      description = "Actual Budget server";
      wantedBy = [
        "multi-user.target"
        "docker.service"
      ];
      requires = [
        "docker.service"
        "opnix-secrets.service"
        "actual-budget-state.service"
        "actual-budget-image-pull.service"
      ];
      after = [
        "docker.service"
        "opnix-secrets.service"
        "actual-budget-state.service"
        "actual-budget-image-pull.service"
      ];
      unitConfig = {
        RequiresMountsFor = cfg.stateDir;
        BindsTo = [ "docker.service" ];
      };
      restartTriggers = [ composeFile ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        ExecStart = "${runtime}/bin/actual-budget-runtime start";
        ExecStop = "${runtime}/bin/actual-budget-runtime stop";
        TimeoutStartSec = 1200;
        TimeoutStopSec = 1080;
      };
    };
    systemd.services.actual-budget-health-check = {
      description = "Check Actual Budget HTTP and container health";
      after = [ "actual-budget-compose.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${health}/bin/actual-budget-health-check";
      };
    };
    systemd.timers.actual-budget-health-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        RandomizedDelaySec = "2m";
        Persistent = true;
      };
    };
  };
}
