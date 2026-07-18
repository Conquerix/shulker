{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.hermes-agent;
  containerService = "docker-hermes-agent.service";
in
{
  options.shulker.system.modules.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent Docker gateway";

    impermanence = lib.mkEnableOption "persistent Hermes Agent state on an ephemeral root";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes";
      description = "Persistent state directory for Hermes Agent.";
    };
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.containers.enable = true;

    # Keep the host and container identities stable so the bind-mounted state
    # remains writable across rebuilds and future host migrations.
    users.groups.hermes.gid = 10000;
    users.users.hermes = {
      isSystemUser = true;
      uid = 10000;
      group = "hermes";
      home = cfg.stateDir;
    };

    virtualisation.oci-containers.containers.hermes-agent = {
      # Hermes' official image keeps the runtime replaceable and all agent
      # configuration/state under /opt/data. Pull on service starts so an
      # explicit restart is enough to adopt a newer image.
      image = "docker.io/nousresearch/hermes-agent:latest";
      pull = "always";
      cmd = [
        "gateway"
        "run"
      ];
      workdir = "/workspace";
      volumes = [
        "${cfg.stateDir}/.hermes:/opt/data:rw"
        "${cfg.stateDir}/workspace:/workspace:rw"
      ];
      environment = {
        HOME = "/opt/data/home";
        HERMES_HOME = "/opt/data";
        HERMES_UID = "10000";
        HERMES_GID = "10000";

        # Telegram remains a private control surface even though Hermes now
        # owns and may update its application configuration.
        GATEWAY_ALLOW_ALL_USERS = "false";
        TELEGRAM_ALLOW_ALL_USERS = "false";
        TELEGRAM_REQUIRE_MENTION = "true";
        TELEGRAM_EXCLUSIVE_BOT_MENTIONS = "true";
        TELEGRAM_GUEST_MODE = "false";
        TELEGRAM_REACTIONS = "false";
      };
      environmentFiles = [ config.services.onepassword-secrets.secrets.hermesAgentEnv.path ];
      extraOptions = [
        "--pids-limit=512"
        "--security-opt=no-new-privileges:true"
      ];
    };

    systemd.services."docker-hermes-agent" = {
      requires = [
        "hermes-agent-state.service"
        "opnix-secrets.service"
      ];
      after = [
        "hermes-agent-state.service"
        "opnix-secrets.service"
        "network-online.target"
      ];
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = 5;
      };
    };

    # The previous NixOS module left a .managed marker that intentionally
    # blocked Hermes' config commands. Remove only that marker during the
    # one-way migration and preserve all OAuth, Telegram, memory, and session
    # state around it.
    systemd.services.hermes-agent-state = {
      description = "Prepare mutable Hermes Agent state";
      before = [ containerService ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        install -d -m 0750 -o hermes -g hermes \
          ${cfg.stateDir} \
          ${cfg.stateDir}/.hermes \
          ${cfg.stateDir}/.hermes/home \
          ${cfg.stateDir}/workspace
        chown -R hermes:hermes ${cfg.stateDir}
        rm -f ${cfg.stateDir}/.hermes/.managed
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
          user = "hermes";
          group = "hermes";
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];

    # Store an env-file in the shulker 1Password item containing:
    # TELEGRAM_BOT_TOKEN=<BotFather token>
    # TELEGRAM_ALLOWED_USERS=<your numeric Telegram user ID>
    # ChatGPT OAuth remains in the persistent /opt/data/auth.json file.
    services.onepassword-secrets.secrets.hermesAgentEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Hermes/Environment";
      services = [ "docker-hermes-agent" ];
      owner = "hermes";
      group = "hermes";
    };
  };
}
