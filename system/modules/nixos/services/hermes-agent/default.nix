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
  discordPolicy = lib.optionalAttrs cfg.discord.enable {
    DISCORD_ALLOWED_USERS = lib.concatStringsSep "," cfg.discord.allowedUsers;
    DISCORD_ALLOW_ALL_USERS = "false";
    DISCORD_REQUIRE_MENTION = "true";
    DISCORD_ALLOW_BOTS = "none";
  };
  managedDir = "/run/hermes-managed";
  managedEnv = "${managedDir}/current/.env";
  credentialItem = if cfg.credentialItem == null then "" else cfg.credentialItem;
  bootstrapToken = config.services.onepassword-secrets.secrets.hermesVaultToken.path;
  credentialReferences = pkgs.writeText "hermes-credential-references.json" (
    builtins.toJSON {
      environment = [
        {
          label = "dashboard";
          reference = "${credentialItem}/Hermes/Dashboard environment";
          requiredKeys = [
            "HERMES_DASHBOARD_BASIC_AUTH_USERNAME"
            "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
            "HERMES_DASHBOARD_BASIC_AUTH_SECRET"
            "API_SERVER_KEY"
          ];
        }
      ]
      ++ lib.optional useOmniroute {
        label = "provider";
        reference = "${credentialItem}/Hermes/Provider environment";
        requiredKeys = [ "HERMES_OMNIROUTE_API_KEY" ];
      }
      ++ lib.optional cfg.discord.enable {
        label = "discord";
        reference = "${credentialItem}/Hermes/Discord environment";
        requiredKeys = [ "DISCORD_BOT_TOKEN" ];
      };
      sshKey = if cfg.overseer.enable then "${credentialItem}/SSH/Private key" else null;
      policy = discordPolicy;
      owner = [
        config.users.users.hermes.uid
        config.users.groups.hermes.gid
      ];
    }
  );
  opWrapper = pkgs.writeTextFile {
    name = "hermes-op";
    executable = true;
    text = ''
      #!/bin/sh
      set -eu
      OP_SERVICE_ACCOUNT_TOKEN="$(cat /run/overseer-op-token)"
      export OP_SERVICE_ACCOUNT_TOKEN
      exec /run/overseer-tools/op "$@"
    '';
  };
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
    credentialItem = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "1Password item reference for this agent's bootstrap and startup credentials.";
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
      enable = lib.mkEnableOption "Overseer context and root host administration";
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
        assertion = cfg.credentialItem != null && lib.hasPrefix "op://" credentialItem;
        message = "Hermes requires its own 1Password credential item reference.";
      }
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
      # Keep a distinct SSH login identity; its root authority comes through sudo.
      openssh.authorizedKeys.keys = [ "restrict ${operator.sshPublicKey}" ];
    };
    # Allow the dedicated non-wheel identity to invoke its requested root sudo grant.
    security.sudo-rs.execWheelOnly = lib.mkIf operator.enable (lib.mkForce false);
    security.sudo-rs.extraRules = lib.mkIf operator.enable [
      {
        users = [ operatorUser ];
        runAs = "root";
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
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
        # Profile isolation reads managed credentials instead of ambient Docker env.
        "${managedEnv}:/etc/hermes/.env:ro"
        "${bootstrapToken}:/run/overseer-op-token:ro"
        # The original binary uses the container's loader, not Nix's patched loader.
        "${pkgs._1password-cli.src}/op:/run/overseer-tools/op:ro"
        "${opWrapper}:/usr/local/bin/op:ro"
      ]
      ++ lib.optionals operator.enable [
        "${sshConfig}:/etc/ssh/ssh_config.d/90-overseer.conf:ro"
        "${knownHosts}:/etc/hermes-host-known-hosts:ro"
        "${managedDir}/current/host-key:/run/hermes-host-key:ro"
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
      // discordPolicy;
      environmentFiles = [ managedEnv ];
      extraOptions = [
        "--memory=4g"
        "--cpus=2"
        "--pids-limit=512"
      ]
      ++ lib.optional useOmniroute "--network=omniroute"
      ++ lib.optional operator.enable "--add-host=shulker-host:host-gateway";
    };
    services.onepassword-secrets.secrets.hermesVaultToken = {
      reference = "${credentialItem}/1Password/Service account token";
      services = [ "docker-hermes" ];
      owner = "hermes";
      group = "hermes";
      mode = "0400";
    };
    systemd.services.docker-hermes = {
      path = [ pkgs.openssh ];
      serviceConfig = {
        RuntimeDirectory = "hermes-managed";
        RuntimeDirectoryMode = "0700";
        # Keep recovery files after terminal failures or a stop; /run clears on reboot.
        RuntimeDirectoryPreserve = "yes";
      };
      preStart = ''
        set -eu
        umask 077
        # Refetch only this agent's fields; publish nothing on an incomplete fetch.
        ${pkgs.python3}/bin/python3 ${./render-credentials.py} \
          ${pkgs._1password-cli}/bin/op ${lib.escapeShellArg bootstrapToken} \
          ${credentialReferences} ${managedDir}
        ${lib.optionalString operator.enable ''
          ${pkgs.util-linux}/bin/runuser -u hermes -- ${seedBootstrap}
        ''}
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
