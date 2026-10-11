# One upstream Hermes container, including its built-in dashboard.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.hermes-agent;
  useOmniroute = config.shulker.system.modules.omniroute.enable;
  operator = cfg.overseer;
  operatorUser = "hermes-operator";
  sshConfig = pkgs.writeText "hermes-host-ssh-config" ''
    Host shulker
      HostName shulker-host
      HostKeyAlias shulker-host
      User ${operatorUser}
      IdentityFile /run/hermes-host-key
      UserKnownHostsFile /etc/hermes-host-known-hosts
      StrictHostKeyChecking yes
      BatchMode yes
      IdentitiesOnly yes
      IdentityAgent none
      ForwardAgent no
      RequestTTY no
      ConnectTimeout 10
  '';
  knownHosts = pkgs.writeText "hermes-host-known-hosts" "shulker-host ${operator.hostPublicKey}\n";
  seedContext =
    lib.concatMapStringsSep "\n"
      (
        name:
        let
          target = if name == "AGENTS.md" then "workspace/AGENTS.md" else "data/${name}";
        in
        ''
          if [ ! -e ${cfg.stateDir}/${target} ] && [ ! -L ${cfg.stateDir}/${target} ]; then
            (umask 077; set -C; cat ${./overseer + "/${name}"} > ${cfg.stateDir}/${target})
          fi
        ''
      )
      [
        "SOUL.md"
        "AGENTS.md"
        "memories/USER.md"
        "memories/MEMORY.md"
      ];
  seedBootstrap = pkgs.writeShellScript "hermes-seed-context" ''
    set -eu
    install -d -m 0700 ${cfg.stateDir}/data/memories ${cfg.stateDir}/workspace/knowledge
    ${seedContext}
    if [ ! -e ${cfg.stateDir}/workspace/knowledge/README.md ] && [ ! -L ${cfg.stateDir}/workspace/knowledge/README.md ]; then
      (umask 077; set -C; cat ${./overseer/knowledge/README.md} > ${cfg.stateDir}/workspace/knowledge/README.md)
    fi
  '';
in
{
  options.shulker.system.modules.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent";
    impermanence = lib.mkEnableOption "persistent Hermes data";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes-clean";
    };
    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/nousresearch/hermes-agent:stable@sha256:9774f4f39a9bb8c2f68ce728ed5e99ddbad282163be56764afacf88ed952b784";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 23234;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://hermes.shulker.link";
    };
    discord = {
      enable = lib.mkEnableOption "native Discord messaging";
      allowedUsers = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "[0-9]+");
        default = [ ];
        description = "Discord user IDs allowed to interact with this Hermes agent.";
      };
    };
    overseer = {
      enable = lib.mkEnableOption "Overseer context and restricted host administration";
      sshPublicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Public key for Overseer's dedicated host identity.";
      };
      hostPublicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Verified Shulker SSH host public key.";
      };
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.discord.enable || cfg.discord.allowedUsers != [ ];
        message = "Hermes Discord requires an explicit user ID allowlist.";
      }
      {
        assertion =
          !operator.enable
          || (
            lib.hasPrefix "ssh-ed25519 " operator.sshPublicKey
            && lib.hasPrefix "ssh-ed25519 " operator.hostPublicKey
          );
        message = "Overseer host access requires its public key and a verified SSH host key.";
      }
    ];
    shulker.system.modules.containers.enable = true;
    users.groups.hermes.gid = 10000;
    users.users.hermes = {
      isSystemUser = true;
      uid = 10000;
      group = "hermes";
    };
    users.groups.${operatorUser} = lib.mkIf operator.enable { };
    users.users.${operatorUser} = lib.mkIf operator.enable {
      isSystemUser = true;
      group = operatorUser;
      shell = pkgs.bashInteractive;
      # No Docker, wheel or journal group: only the exact sudo commands below.
      openssh.authorizedKeys.keys = [ "restrict ${operator.sshPublicKey}" ];
    };
    # Allow the non-wheel account to invoke sudo-rs; grants stay command-specific.
    security.sudo-rs.execWheelOnly = lib.mkIf operator.enable (lib.mkForce false);
    security.sudo-rs.extraRules = lib.mkIf operator.enable [
      {
        users = [ operatorUser ];
        runAs = "root";
        commands =
          lib.concatMap
            (unit: [
              {
                command = "/run/current-system/sw/bin/systemctl restart ${unit}";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/journalctl --no-pager -n 100 -u ${unit}";
                options = [ "NOPASSWD" ];
              }
            ])
            [
              "docker-hermes.service"
              "docker-omniroute.service"
            ];
      }
    ];
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 hermes hermes -"
      "d ${cfg.stateDir}/data 0700 hermes hermes -"
      "d ${cfg.stateDir}/workspace 0700 hermes hermes -"
    ];
    virtualisation.oci-containers.containers.hermes = {
      image = cfg.image;
      pull = "missing";
      cmd = [
        "gateway"
        "run"
      ];
      ports = [ "127.0.0.1:${toString cfg.port}:9119" ];
      volumes = [
        "${cfg.stateDir}/data:/opt/data:rw"
        "${cfg.stateDir}/workspace:/workspace:rw"
      ]
      ++ lib.optionals operator.enable [
        "${sshConfig}:/etc/ssh/ssh_config.d/90-overseer.conf:ro"
        "${knownHosts}:/etc/hermes-host-known-hosts:ro"
        "${config.services.onepassword-secrets.secrets.hermesHostKey.path}:/run/hermes-host-key:ro"
      ];
      environment = {
        HERMES_UID = "10000";
        HERMES_GID = "10000";
        HERMES_DASHBOARD = "1";
        HERMES_DASHBOARD_HOST = "0.0.0.0";
        API_SERVER_ENABLED = "true";
        API_SERVER_HOST = "127.0.0.1";
        TERMINAL_CWD = "/workspace";
        HERMES_WRITE_SAFE_ROOT = "/opt/data:/workspace";
      }
      // lib.optionalAttrs cfg.discord.enable {
        DISCORD_ALLOWED_USERS = lib.concatStringsSep "," cfg.discord.allowedUsers;
        DISCORD_ALLOW_ALL_USERS = "false";
        DISCORD_REQUIRE_MENTION = "true";
        DISCORD_ALLOW_BOTS = "none";
      };
      environmentFiles = [
        config.services.onepassword-secrets.secrets.hermesDashboardEnv.path
      ]
      ++ lib.optional useOmniroute config.services.onepassword-secrets.secrets.hermesProviderEnv.path
      ++ lib.optional cfg.discord.enable config.services.onepassword-secrets.secrets.hermesDiscordEnv.path;
      extraOptions = [
        "--memory=4g"
        "--cpus=2"
        "--pids-limit=512"
      ]
      ++ lib.optional useOmniroute "--network=omniroute"
      ++ lib.optional operator.enable "--add-host=shulker-host:host-gateway";
    };
    services.onepassword-secrets.secrets.hermesProviderEnv = lib.mkIf useOmniroute {
      reference = "op://Shulker/${config.networking.hostName}/Hermes/Provider environment";
      services = [ "docker-hermes" ];
      mode = "0400";
    };
    services.onepassword-secrets.secrets.hermesDashboardEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Hermes/Dashboard environment";
      services = [ "docker-hermes" ];
      mode = "0400";
    };
    services.onepassword-secrets.secrets.hermesDiscordEnv = lib.mkIf cfg.discord.enable {
      reference = "op://Shulker/${config.networking.hostName}/Hermes/Discord environment";
      services = [ "docker-hermes" ];
      mode = "0400";
    };
    services.onepassword-secrets.secrets.hermesHostKey = lib.mkIf operator.enable {
      reference = "op://Shulker/p5yzdcosjfv3qdpepcsjes5kwi/private_key?ssh-format=openssh";
      services = [ "docker-hermes" ];
      owner = "hermes";
      group = "hermes";
      mode = "0400";
    };
    systemd.services.docker-hermes = {
      # Seed new homes only; learning and user edits survive every deployment.
      preStart = lib.mkIf operator.enable ''
        ${pkgs.util-linux}/bin/runuser -u hermes -- ${seedBootstrap}
      '';
      requires = [
        "opnix-secrets.service"
      ]
      ++ lib.optional useOmniroute "docker-network-omniroute.service";
      after = lib.optional useOmniroute "docker-network-omniroute.service";
      unitConfig.RequiresMountsFor = [ cfg.stateDir ];
    };
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "0700";
          user = "hermes";
          group = "hermes";
        }
      ];
    };
    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
  };
}
