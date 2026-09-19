{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.kitchenowl;
  composeConfig = {
    name = "kitchenowl";
    services.server = {
      image = cfg.image;
      container_name = "kitchenowl";
      restart = "on-failure:5";
      stop_grace_period = "60s";
      ports = [ "127.0.0.1:${toString cfg.port}:8080/tcp" ];
      volumes = [
        "${cfg.stateDir}/data:/data"
      ];
      env_file = [
        {
          path = config.services.onepassword-secrets.secrets.kitchenowlEnv.path;
          format = "raw";
        }
      ];
      environment = {
        FRONT_URL = cfg.publicUrl;
        OIDC_ISSUER = cfg.oidcIssuer;
        DISABLE_USERNAME_PASSWORD_LOGIN = "true";
        DISABLE_ONBOARDING = "true";
        OPEN_REGISTRATION = "false";
        OIDC_RFC_COMPLIANT_REDIRECT = "true";
        JWT_REFRESH_TOKEN_EXPIRES = "30";
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
          "python"
          "-c"
          "import json,urllib.request; d=json.load(urllib.request.urlopen('http://127.0.0.1:8080/api/health/8M4F88S8ooi4sMbLBfkkV7ctWwgibW6V',timeout=5)); assert d.get('oidc_provider')==['custom'] and d.get('disable_username_password_login') is True and not d.get('open_registration',False)"
        ];
        interval = "30s";
        timeout = "10s";
        retries = 5;
        start_period = "30s";
      };
    };
  };
  composeFile = pkgs.writeText "kitchenowl-compose.json" (builtins.toJSON composeConfig);
  compose = pkgs.writeShellApplication {
    name = "kitchenowl-compose";
    runtimeInputs = [ pkgs.docker-compose ];
    text = ''exec docker-compose --project-name kitchenowl --file ${composeFile} "$@"'';
  };
  runtime = pkgs.writeShellApplication {
    name = "kitchenowl-runtime";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''exec ${pkgs.bash}/bin/bash ${./runtime.sh} "$1" ${lib.escapeShellArg cfg.stateDir} ${lib.escapeShellArg cfg.dataset} /run/lock/kitchenowl-maintenance.lock ${compose}/bin/kitchenowl-compose ${cfg.validateStatePackage}/bin/kitchenowl-validate-state'';
  };
  health = pkgs.writeShellApplication {
    name = "kitchenowl-health-check";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.curl
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      exec 9>/run/lock/kitchenowl-maintenance.lock
      flock -w 900 9
      systemctl is-active --quiet kitchenowl-compose.service || exit 0
      curl --fail --silent --show-error http://127.0.0.1:${toString cfg.port}/api/health/8M4F88S8ooi4sMbLBfkkV7ctWwgibW6V >/dev/null
      [ "$(docker inspect --format '{{.State.Health.Status}}' kitchenowl)" = healthy ]
    '';
  };
in
{
  options.shulker.system.modules.kitchenowl = {
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
    shulker.system.modules.kitchenowl = {
      inherit composeConfig;
      runtimePackage = runtime;
    };
    environment.systemPackages = [
      compose
      runtime
      health
    ];
    systemd.services.kitchenowl-image-pull = {
      description = "Pull pinned KitchenOwl image";
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
    systemd.services.kitchenowl-compose = {
      description = "KitchenOwl server";
      wantedBy = [
        "multi-user.target"
        "docker.service"
      ];
      requires = [
        "docker.service"
        "opnix-secrets.service"
        "kitchenowl-state.service"
        "kitchenowl-image-pull.service"
      ];
      after = [
        "docker.service"
        "opnix-secrets.service"
        "kitchenowl-state.service"
        "kitchenowl-image-pull.service"
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
        ExecStart = "${runtime}/bin/kitchenowl-runtime start";
        ExecStop = "${runtime}/bin/kitchenowl-runtime stop";
        TimeoutStartSec = 1200;
        TimeoutStopSec = 1080;
      };
    };
    systemd.services.kitchenowl-health-check = {
      description = "Check KitchenOwl HTTP and container health";
      after = [ "kitchenowl-compose.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${health}/bin/kitchenowl-health-check";
      };
    };
    systemd.timers.kitchenowl-health-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        RandomizedDelaySec = "2m";
        Persistent = true;
      };
    };
  };
}
