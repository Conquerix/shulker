{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.hermes-agent;
in
{
  options.shulker.system.modules.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent gateway";

    impermanence = lib.mkEnableOption "persistent Hermes Agent state on an ephemeral root";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes";
      description = "Persistent state directory for Hermes Agent.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-5.5";
      description = "Default OpenAI Codex model used by Hermes Agent through ChatGPT OAuth.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      stateDir = cfg.stateDir;
      workingDirectory = "${cfg.stateDir}/workspace";

      # Native mode keeps the service reproducible and lets systemd provide the
      # security boundary. Agent-created skills and memories remain writable in
      # stateDir; opt into container mode only if mutable OS packages are needed.
      container.enable = false;

      settings = {
        model = {
          provider = "openai-codex";
          default = cfg.model;
        };
        toolsets = [ "all" ];
        group_sessions_per_user = true;
        unauthorized_dm_behavior = "ignore";
        memory = {
          memory_enabled = true;
          user_profile_enabled = true;
        };
        terminal = {
          backend = "local";
          timeout = 180;
        };

        # The gateway is unattended, so repeated failing/no-progress tool calls
        # must be circuit-broken instead of consuming tokens indefinitely.
        tool_loop_guardrails = {
          hard_stop_enabled = true;
          hard_stop_after = {
            exact_failure = 5;
            same_tool_failure = 8;
            idempotent_no_progress = 5;
          };
        };
      };

      # Telegram is a private control surface for this agent. Secrets and the
      # sole authorized user ID stay in the 1Password-provided env file.
      environment = {
        GATEWAY_ALLOW_ALL_USERS = "false";
        TELEGRAM_ALLOW_ALL_USERS = "false";
        TELEGRAM_REQUIRE_MENTION = "true";
        TELEGRAM_EXCLUSIVE_BOT_MENTIONS = "true";
        TELEGRAM_GUEST_MODE = "false";
        TELEGRAM_REACTIONS = "false";
      };
      environmentFiles = [ config.services.onepassword-secrets.secrets.hermesAgentEnv.path ];
      extraDependencyGroups = [ "messaging" ];
      extraPackages = with pkgs; [
        curl
        ffmpeg
        git
        jq
        ripgrep
      ];
      addToSystemPackages = true;
      restart = "always";
      restartSec = 5;
    };

    # The agent needs outbound network access and a writable workspace, but no
    # access to user homes, host devices, kernel controls, or Linux capabilities.
    systemd.services.hermes-agent.serviceConfig = {
      ProtectHome = lib.mkForce true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      RestrictRealtime = true;
      CapabilityBoundingSet = "";
    };
    systemd.services.hermes-agent.requires = [
      "hermes-agent-state.service"
      "opnix-secrets.service"
    ];

    # On the first activation, the persistent bind mount can cover directories
    # created by the upstream activation script. Prepare the workspace only
    # after that mount exists and before systemd attempts Hermes' WorkingDirectory.
    systemd.services.hermes-agent-state = {
      description = "Prepare Hermes Agent persistent state";
      before = [ "hermes-agent.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/install -d -m 0750 -o hermes -g hermes ${cfg.stateDir}/workspace";
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
    # ChatGPT OAuth credentials are created interactively by Hermes and kept in
    # its persistent auth.json; do not place them in this env file.
    services.onepassword-secrets.secrets.hermesAgentEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Hermes/Environment";
      services = [ "hermes-agent" ];
      owner = "hermes";
      group = "hermes";
    };
  };
}
