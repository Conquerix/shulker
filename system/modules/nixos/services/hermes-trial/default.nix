# Opt-in Overseer trial; production Hermes remains owned by hermes-agent.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.hermes-trial;
  source = import ./package.nix { inherit pkgs; };
  upstream = import ./upstream.nix;
  state = "/var/lib/hermes-trial/overseer";
  codingEnabled = config.shulker.system.modules.openhands.broker.enable;
  runtimeConfig = {
    model = {
      provider = "openai-codex";
      default = cfg.model;
    };
    plugins.enabled = [ "zulip-platform" ] ++ lib.optional codingEnabled "overseer-coding";
    platforms.zulip = {
      enabled = true;
      extra = {
        site_url = cfg.zulipUrl;
        allowed_user_ids = map toString cfg.allowedUsers;
        allowed_channel_ids = map toString cfg.allowedChannels;
      };
    };
  };
  hermesConfig = (pkgs.formats.yaml { }).generate "overseer-config.yaml" runtimeConfig;
in
{
  options.shulker.system.modules.hermes-trial = {
    enable = lib.mkEnableOption "the isolated Overseer trial";
    zulipUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://chat.shulker.link";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Model ID verified in the authenticated ChatGPT provider catalog.";
    };
    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.ints.positive;
      default = [ ];
    };
    allowedChannels = lib.mkOption {
      type = lib.types.listOf lib.types.ints.positive;
      default = [ ];
    };
    secretReference = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Dedicated bot/integration environment file in 1Password.";
    };
    runtimeConfig = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
    };
    impermanence = lib.mkEnableOption "persisting trial state across boot";
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.hermes-trial = { inherit runtimeConfig; };
    assertions = [
      {
        assertion = cfg.model != "";
        message = "Overseer requires an explicitly selected ChatGPT subscription model.";
      }
      {
        assertion = builtins.length cfg.allowedUsers == 1 && cfg.allowedChannels != [ ];
        message = "Overseer requires exactly one authorized user and explicit private channels.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.zulipUrl && cfg.secretReference != "";
        message = "Overseer requires HTTPS Zulip and a dedicated secret reference.";
      }
    ];
    shulker.system.modules.containers.enable = true;
    users.groups.hermes-overseer.gid = 10010;
    users.users.hermes-overseer = {
      isSystemUser = true;
      uid = 10010;
      group = "hermes-overseer";
      home = state;
    };
    services.onepassword-secrets.secrets.hermesOverseerEnv = {
      reference = cfg.secretReference;
      owner = "root";
      group = "root";
      mode = "0400";
      services = [ "docker-hermes-overseer" ];
    };
    systemd.services.hermes-overseer-state = {
      unitConfig.RequiresMountsFor = state;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.coreutils ];
      script = ''
        install -d -m 0700 -o hermes-overseer -g hermes-overseer ${state} ${state}/home ${state}/workspace ${state}/home/plugins
      '';
    };
    virtualisation.oci-containers.containers.hermes-overseer = {
      inherit (upstream) image;
      pull = "missing";
      user = "10010:10010";
      entrypoint = "/opt/hermes/.venv/bin/python";
      cmd = [
        "-m"
        "hermes_cli.main"
        "gateway"
        "run"
      ];
      workdir = "/opt/hermes";
      environment = {
        HOME = "/opt/data/home";
        HERMES_HOME = "/opt/data";
        PYTHONDONTWRITEBYTECODE = "1";
        ZULIP_ALLOWED_USER_IDS = lib.concatMapStringsSep "," toString cfg.allowedUsers;
        ZULIP_ALLOWED_CHANNEL_IDS = lib.concatMapStringsSep "," toString cfg.allowedChannels;
        ZULIP_SITE_URL = cfg.zulipUrl;
        ZULIP_BOT_FULL_NAME = "Overseer";
        ZULIP_RESPOND_TO_ALL_AUTHORIZED_STREAM_MESSAGES = "true";
        HERMES_YOLO_MODE = "false";
        GATEWAY_ALLOW_ALL_USERS = "false";
        TERMINAL_CWD = "/workspace";
      };
      environmentFiles = [ config.services.onepassword-secrets.secrets.hermesOverseerEnv.path ];
      volumes = [
        "${state}/home:/opt/data:rw"
        "${state}/workspace:/workspace:rw"
        "${hermesConfig}:/opt/data/config.yaml:ro"
        "${./plugin}:/opt/data/plugins/zulip:ro"
        "${source}/gateway/run_turn_runner.py:/opt/hermes/gateway/run_turn_runner.py:ro"
      ]
      ++ lib.optionals codingEnabled [
        "${./coding}:/opt/data/plugins/coding:ro"
        "/run/openhands-broker:/run/openhands-broker:ro"
      ];
      extraOptions = [
        "--init"
        "--log-driver=json-file"
        "--read-only"
        "--tmpfs=/tmp:rw,nosuid,nodev,size=256m"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges:true"
        "--memory=2g"
        "--cpus=1"
        "--pids-limit=256"
        "--log-opt=max-size=10m"
        "--log-opt=max-file=3"
      ];
    };
    systemd.services.docker-hermes-overseer = {
      wants =
        lib.optional codingEnabled "openhands-broker.service"
        ++ lib.optional config.services.newt.enable "newt.service"
        ++ lib.optional config.shulker.system.modules.zulip.enable "zulip-trial.service";
      requires = [
        "hermes-overseer-state.service"
        "opnix-secrets.service"
      ];
      after = [
        "hermes-overseer-state.service"
        "opnix-secrets.service"
      ]
      ++ lib.optional codingEnabled "openhands-broker.service"
      ++ lib.optional config.services.newt.enable "newt.service"
      ++ lib.optional config.shulker.system.modules.zulip.enable "zulip-trial.service";
      # A running Newt process can precede its live tunnel; an initial 502 leaves
      # the pinned gateway with no adapter, so wait for the public Zulip route.
      preStart = lib.mkAfter ''
        ${pkgs.curl}/bin/curl --fail --silent --show-error --output /dev/null \
          --max-time 3 --retry 15 --retry-delay 2 --retry-max-time 45 --retry-all-errors \
          ${lib.escapeShellArg "${cfg.zulipUrl}/api/v1/server_settings"}
      '';
      unitConfig.RequiresMountsFor = state;
    };
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = state;
          user = "hermes-overseer";
          group = "hermes-overseer";
          mode = "u=rwx,g=,o=";
        }
      ];
    };
    shulker.system.modules.backup.dirs = [ state ];
  };
}
