{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.hermes-agent;
  containerService = "docker-hermes-agent.service";
  webUiContainerService = "docker-hermes-webui.service";
  webUiAgentSourceDir = "/run/hermes-webui-agent-source";
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

    webUi = {
      enable = lib.mkEnableOption "the community Hermes WebUI and its native client backend";

      image = lib.mkOption {
        type = lib.types.str;
        default = "ghcr.io/nesquena/hermes-webui:latest";
        description = "Hermes WebUI container image.";
      };

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host address on which to publish the authenticated Hermes WebUI.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8787;
        description = "Host port on which to publish the authenticated Hermes WebUI.";
      };

      publicUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://hermes.example.com";
        description = "Public HTTPS URL used by Hermes WebUI and its native clients.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.containers.enable = true;

    assertions = lib.optionals cfg.webUi.enable [
      {
        assertion = cfg.webUi.publicUrl != null;
        message = "Hermes WebUI requires shulker.system.modules.hermes-agent.webUi.publicUrl.";
      }
      {
        assertion = lib.elem cfg.webUi.bindAddress [
          "127.0.0.1"
          "[::1]"
        ];
        message = "Hermes WebUI must remain bound to host loopback and be exposed through an authenticated HTTPS proxy.";
      }
    ];

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

    virtualisation.oci-containers.containers.hermes-webui = lib.mkIf cfg.webUi.enable {
      image = cfg.webUi.image;
      pull = "always";
      dependsOn = [ "hermes-agent" ];
      volumes = [
        "${cfg.stateDir}/.hermes:/home/hermeswebui/.hermes:rw"
        "${webUiAgentSourceDir}:/home/hermeswebui/.hermes/hermes-agent:ro"
        "${cfg.stateDir}/workspace:/workspace:rw"
      ];
      ports = [ "${cfg.webUi.bindAddress}:${toString cfg.webUi.port}:8787/tcp" ];
      environment = {
        HERMES_HOME = "/home/hermeswebui/.hermes";
        HERMES_WEBUI_HOST = "0.0.0.0";
        HERMES_WEBUI_PORT = "8787";
        HERMES_WEBUI_STATE_DIR = "/home/hermeswebui/.hermes/webui";
        HERMES_WEBUI_DEFAULT_WORKSPACE = "/workspace";
        HERMES_WEBUI_AGENT_DIR = "/home/hermeswebui/.hermes/hermes-agent";
        HERMES_WEBUI_SSE_CHUNKED = "true";
        WANTED_UID = "10000";
        WANTED_GID = "10000";
      };
      environmentFiles = [ config.services.onepassword-secrets.secrets.hermesWebUiEnv.path ];
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

    systemd.services."docker-hermes-webui" = lib.mkIf cfg.webUi.enable {
      partOf = [ containerService ];
      requires = [ "hermes-agent-state.service" ];
      after = [ "hermes-agent-state.service" ];
      path = [
        config.virtualisation.docker.package
        pkgs.coreutils
      ];
      # The upstream two-container layout shares the Agent source with WebUI.
      # Refresh it from the running image on every WebUI start so pull=always
      # cannot leave a stale named volume hiding a newer Agent release.
      preStart = ''
        rm -rf -- ${webUiAgentSourceDir}
        install -d -m 0755 ${webUiAgentSourceDir}
        docker cp hermes-agent:/opt/hermes/. ${webUiAgentSourceDir}
      '';
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
      before = [
        containerService
        webUiContainerService
      ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        install -d -m 0750 -o hermes -g hermes \
          ${cfg.stateDir} \
          ${cfg.stateDir}/.hermes \
          ${cfg.stateDir}/.hermes/home \
          ${cfg.stateDir}/.hermes/webui \
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

    # Store HERMES_WEBUI_PASSWORD in this separate env-file. Hermes WebUI's
    # native authentication is required before Pangolin exposes the service.
    services.onepassword-secrets.secrets.hermesWebUiEnv = lib.mkIf cfg.webUi.enable {
      reference = "op://Shulker/${config.networking.hostName}/Hermes/WebUI Environment";
      services = [ "docker-hermes-webui" ];
      owner = "hermes";
      group = "hermes";
    };
  };
}
