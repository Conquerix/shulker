# Direct loopback targets for Pangolin; schema changes complete before writers start.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.taskview;
  rawEnv = name: [
    {
      path = "/run/taskview/${name}.env";
      format = "raw";
    }
  ];
  dbEnv = {
    DB_HOST = "database";
    DB_PORT = "5432";
    DB_NAME = "taskview";
    DB_USER = "taskview";
  };
  common = name: {
    image = cfg.images.${name};
    container_name = "taskview-${name}";
    # Retry process crashes, but never restore containers directly at daemon boot:
    # systemd must validate the ZFS mount before any database startup.
    restart = "on-failure:5";
    logging = {
      driver = "json-file";
      options = {
        max-size = "10m";
        max-file = "3";
      };
    };
    stop_grace_period = "60s";
  };
  probe = test: {
    inherit test;
    interval = "30s";
    timeout = "10s";
    retries = 5;
    start_period = "30s";
  };
  composeConfig = {
    name = "taskview";
    networks = {
      private.internal = true;
      egress = { };
    };
    services = {
      database = common "database" // {
        networks = [ "private" ];
        env_file = rawEnv "database";
        environment = {
          POSTGRES_DB = "taskview";
          POSTGRES_USER = "taskview";
          POSTGRES_INITDB_ARGS = "--data-checksums";
        };
        volumes = [ "${cfg.stateDir}/postgres:/var/lib/postgresql/data" ];
        healthcheck = probe [
          "CMD-SHELL"
          "pg_isready -U taskview -d taskview && psql -U taskview -d taskview -tAc 'SELECT 1' | grep -qx 1"
        ];
      };
      migration = common "migration" // {
        restart = "no";
        profiles = [ "maintenance" ];
        networks = [ "private" ];
        env_file = rawEnv "migration";
        environment = dbEnv;
      };
      api = common "api" // {
        networks = [
          "private"
          "egress"
        ];
        ports = [ "127.0.0.1:${toString cfg.apiPort}:1401/tcp" ];
        env_file = rawEnv "api";
        environment = dbEnv // {
          APP_PORT = "1401";
          APP_URL = cfg.publicUrl;
          API_PUBLIC_URL = cfg.apiPublicUrl;
          AUTH_LOGIN_METHODS = "password,sso";
          ALLOW_PUBLIC_REGISTRATION = "false";
          PASSWORD_CHANGE_CONFIRMATION = "email";
          INVITE_EMAIL_ENABLED = "true";
          PM2_INSTANCES = "1";
          DB_POOL_MAX = "10";
          JWT_ALG = "HS256";
          ACCESS_LIFE_TIME = "1d";
          REFRESH_LIFE_TIME = "2d";
          CORS_REMOVE_DEFAULT_ALLOWED_ORIGINS = "true";
          CORS_ALLOWED_ORIGINS = "${cfg.publicUrl},capacitor://app.taskview.tech,https://app.taskview.tech";
          TRUST_PROXY = cfg.trustProxy;
          CENTRIFUGO_API_URL = "http://centrifugo:9000";
          CENTRIFUGO_PUBLIC_URL = cfg.centrifugoPublicUrl;
        };
        healthcheck = probe [
          "CMD"
          "node"
          "-e"
          "fetch('http://127.0.0.1:1401/module/auth/login-options').then(async r=>{if(!r.ok)throw Error();await r.json()}).catch(()=>process.exit(1))"
        ];
      };
      web = common "web" // {
        networks = [ "egress" ];
        ports = [ "127.0.0.1:${toString cfg.webPort}:80/tcp" ];
        environment.TASKVIEW_API_URL = cfg.apiPublicUrl;
        healthcheck = probe [
          "CMD-SHELL"
          "wget -q -O - http://127.0.0.1/ | grep -qi '<!doctype html>'"
        ];
      };
      mcp = common "mcp" // {
        networks = [ "egress" ];
        ports = [ "127.0.0.1:${toString cfg.mcpPort}:3100/tcp" ];
        environment = {
          TASKVIEW_URL = "http://api:1401";
          MCP_HTTP_PORT = "3100";
        };
        healthcheck = probe [
          "CMD"
          "node"
          "-e"
          "fetch('http://127.0.0.1:3100/health').then(async r=>{if(!r.ok||(await r.json()).status!=='ok')throw Error()}).catch(()=>process.exit(1))"
        ];
      };
      centrifugo = common "centrifugo" // {
        networks = [
          "private"
          "egress"
        ];
        # The root-owned bind mount contains signing keys; no unprivileged host access.
        user = "0:0";
        ports = [ "127.0.0.1:${toString cfg.centrifugoPort}:8000/tcp" ];
        volumes = [ "/run/taskview/centrifugo.json:/centrifugo/config.json:ro" ];
        command = [
          "centrifugo"
          "--config=/centrifugo/config.json"
          "--health.enabled"
        ];
        healthcheck = probe [
          "CMD-SHELL"
          "wget -q -O /dev/null http://127.0.0.1:9000/health"
        ];
      };
    };
  };
  composeFile = (pkgs.formats.yaml { }).generate "taskview-compose.yaml" composeConfig;
  compose = pkgs.writeShellApplication {
    name = "taskview-compose";
    runtimeInputs = [ pkgs.docker-compose ];
    text = ''exec docker-compose --project-name taskview --file ${composeFile} "$@"'';
  };
  health = pkgs.writeShellApplication {
    name = "taskview-health-check";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.curl
      pkgs.jq
      cfg.validateStatePackage
    ];
    text = ''
      taskview-validate-state
      for name in database api web mcp centrifugo; do
        [ "$(docker inspect --format '{{.State.Health.Status}}' "taskview-$name")" = healthy ]
      done
      curl --fail --silent --show-error --max-time 10 http://127.0.0.1:${toString cfg.apiPort}/module/auth/login-options | jq -e 'type == "object"' >/dev/null
      curl --fail --silent --show-error --max-time 10 http://127.0.0.1:${toString cfg.mcpPort}/health | jq -e '.status == "ok"' >/dev/null
    '';
  };
  lifecycle = pkgs.writeShellApplication {
    name = "taskview-lifecycle";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''exec ${pkgs.bash}/bin/bash ${./lifecycle.sh} "$1" ${lib.escapeShellArg cfg.stateDir} /run/lock/taskview-maintenance.lock ${compose}/bin/taskview-compose ${cfg.validateStatePackage}/bin/taskview-validate-state ${cfg.backupPreparePackage}/bin/taskview-backup-prepare ${health}/bin/taskview-health-check'';
  };
in
{
  options.shulker.system.modules.taskview = {
    composeConfig = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      readOnly = true;
    };
    composeFile = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.taskview = { inherit composeConfig composeFile; };
    environment.systemPackages = [
      compose
      health
    ];
    systemd.services.taskview-image-pull = {
      description = "Pull pinned TaskView images";
      wants = [ "network-online.target" ];
      requires = [
        "docker.service"
        "taskview-config.service"
        "taskview-state.service"
      ];
      after = [
        "docker.service"
        "taskview-config.service"
        "taskview-state.service"
        "network-online.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [ "COMPOSE_PARALLEL_LIMIT=1" ];
        ExecStartPre = "${compose}/bin/taskview-compose --profile maintenance config --quiet";
        ExecStart = "${compose}/bin/taskview-compose --profile maintenance pull";
        TimeoutStartSec = 7200;
        UMask = "0077";
      };
    };
    systemd.services.taskview-compose = {
      description = "TaskView household task management";
      wantedBy = [
        "multi-user.target"
        "docker.service"
      ];
      requires = [
        "docker.service"
        "taskview-state.service"
        "taskview-config.service"
        "taskview-image-pull.service"
      ];
      after = [
        "docker.service"
        "taskview-state.service"
        "taskview-config.service"
        "taskview-image-pull.service"
      ];
      unitConfig = {
        RequiresMountsFor = cfg.stateDir;
        BindsTo = [ "docker.service" ];
      };
      restartTriggers = [ composeFile ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lifecycle}/bin/taskview-lifecycle start";
        ExecStop = "${lifecycle}/bin/taskview-lifecycle stop";
        TimeoutStartSec = 1800;
        TimeoutStopSec = 1080;
        UMask = "0077";
      };
    };
    systemd.services.taskview-health-check = {
      description = "Check TaskView containers and application health";
      after = [ "taskview-compose.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${health}/bin/taskview-health-check";
      };
    };
    systemd.timers.taskview-health-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        RandomizedDelaySec = "2m";
        Persistent = true;
      };
    };
  };
}
