# Opt-in official Zulip stack. Native authentication protects mobile API traffic.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.zulip;
  secretNames = [
    "postgres_password"
    "memcached_password"
    "rabbitmq_password"
    "redis_password"
    "secret_key"
    "email_password"
    "social_auth_oidc_secret"
  ];
  secret = name: "zulip__${name}";
  secretPath = name: "/run/secrets/${secret name}";
  common = name: {
    image = cfg.images.${name};
    restart = "on-failure:5";
    logging = {
      driver = "json-file";
      options = {
        max-size = "10m";
        max-file = "3";
      };
    };
    networks = [ "private" ];
  };
  composeConfig = {
    name = "zulip-trial";
    networks = {
      private.internal = true;
      egress = { };
    };
    secrets = lib.genAttrs (map secret secretNames) (name: {
      file = "/run/zulip-trial/${name}";
    });
    services = {
      database = common "database" // {
        environment = {
          POSTGRES_DB = "zulip";
          POSTGRES_USER = "zulip";
          POSTGRES_PASSWORD_FILE = secretPath "postgres_password";
        };
        secrets = [ (secret "postgres_password") ];
        volumes = [ "${cfg.stateDir}/postgres:/var/lib/postgresql/data" ];
        healthcheck = {
          test = [
            "CMD-SHELL"
            "pg_isready -U zulip -d zulip"
          ];
          interval = "10s";
          retries = 12;
        };
      };
      memcached = common "memcached" // {
        command = [
          "sh"
          "-euc"
          ''
            echo 'mech_list: plain' > "$$SASL_CONF_PATH"
            printf 'zulip@localhost:%s\n' "$$(cat /run/secrets/zulip__memcached_password)" > "$$MEMCACHED_SASL_PWDB"
            printf 'zulip@%s:%s\n' "$$HOSTNAME" "$$(cat /run/secrets/zulip__memcached_password)" >> "$$MEMCACHED_SASL_PWDB"
            exec memcached -S
          ''
        ];
        environment = {
          SASL_CONF_PATH = "/home/memcache/memcached.conf";
          MEMCACHED_SASL_PWDB = "/home/memcache/memcached-sasl-db";
        };
        secrets = [ (secret "memcached_password") ];
      };
      rabbitmq = common "rabbitmq" // {
        environment.RABBITMQ_DEFAULT_USER = "zulip";
        command = [
          "sh"
          "-euc"
          ''
            export RABBITMQ_DEFAULT_PASS="$$(cat /run/secrets/zulip__rabbitmq_password)"
            exec docker-entrypoint.sh rabbitmq-server
          ''
        ];
        secrets = [ (secret "rabbitmq_password") ];
        volumes = [ "${cfg.stateDir}/rabbitmq:/var/lib/rabbitmq" ];
      };
      redis = common "redis" // {
        command = [
          "sh"
          "-euc"
          ''exec /usr/local/bin/docker-entrypoint.sh --requirepass "$$(cat /run/secrets/zulip__redis_password)"''
        ];
        secrets = [ (secret "redis_password") ];
        volumes = [ "${cfg.stateDir}/redis:/data" ];
      };
      zulip = common "zulip" // {
        networks = [
          "private"
          "egress"
        ];
        ports = [ "127.0.0.1:${toString cfg.port}:80" ];
        secrets = map secret secretNames;
        volumes = [ "${cfg.stateDir}/data:/data" ];
        depends_on = [
          "database"
          "memcached"
          "rabbitmq"
          "redis"
        ];
        ulimits.nofile = {
          soft = 1000000;
          hard = 1048576;
        };
        environment = {
          SETTING_EXTERNAL_HOST = lib.removePrefix "https://" cfg.publicUrl;
          SETTING_ZULIP_ADMINISTRATOR = cfg.administratorEmail;
          SETTING_REMOTE_POSTGRES_HOST = "database";
          SETTING_MEMCACHED_LOCATION = "memcached:11211";
          SETTING_RABBITMQ_HOST = "rabbitmq";
          SETTING_REDIS_HOST = "redis";
          CERTIFICATES = "";
          TRUST_GATEWAY_IP = "False";
          LOADBALANCER_IPS = lib.concatStringsSep "," cfg.trustedProxyAddresses;
          ZULIP_AUTH_BACKENDS = "EmailAuthBackend,GenericOpenIdConnectBackend";
          SETTING_SOCIAL_AUTH_OIDC_ENABLED_IDPS = ''{"pocketid": {"oidc_url": ${builtins.toJSON cfg.oidcIssuer}, "display_name": "Pocket ID", "client_id": ${builtins.toJSON cfg.oidcClientId}, "secret": get_secret("social_auth_oidc_secret"), "auto_signup": False}}'';
          SETTING_ZULIP_SERVICE_SUBMIT_USAGE_STATISTICS = "False";
          SETTING_EMAIL_HOST = cfg.smtpHost;
          SETTING_EMAIL_HOST_USER = cfg.smtpUser;
          SETTING_EMAIL_PORT = toString cfg.smtpPort;
          SETTING_EMAIL_USE_SSL = "True";
          SETTING_NOREPLY_EMAIL_ADDRESS = cfg.smtpFrom;
          AUTO_BACKUP_ENABLED = "False";
        };
      };
    };
  };
  composeFile = (pkgs.formats.yaml { }).generate "zulip-trial-compose.yaml" composeConfig;
  compose = pkgs.writeShellApplication {
    name = "zulip-trial-compose";
    runtimeInputs = [ pkgs.docker-compose ];
    text = ''exec docker-compose --project-name zulip-trial --file ${composeFile} "$@"'';
  };
  backup = pkgs.writeShellApplication {
    name = "zulip-trial-backup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.gnutar
      pkgs.gzip
      compose
    ];
    text = "exec ${pkgs.bash}/bin/bash ${./backup.sh} ${lib.escapeShellArg cfg.stateDir} ${compose}/bin/zulip-trial-compose";
  };
in
{
  options.shulker.system.modules.zulip = {
    enable = lib.mkEnableOption "the private Zulip trial";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/zulip-trial";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 23248;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://chat.shulker.link";
    };
    administratorEmail = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "https://sso.shulker.link";
    };
    oidcClientId = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    trustedProxyAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    secretReference = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    smtpHost = lib.mkOption {
      type = lib.types.str;
      default = "smtp.fastmail.com";
    };
    smtpUser = lib.mkOption {
      type = lib.types.str;
      default = "service@shulker.link";
    };
    smtpFrom = lib.mkOption {
      type = lib.types.str;
      default = "service@shulker.link";
    };
    smtpPort = lib.mkOption {
      type = lib.types.port;
      default = 465;
    };
    impermanence = lib.mkEnableOption "persisting Zulip trial data across boot";
    images = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = import ./images.nix;
    };
    composeConfig = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
    };
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.zulip = { inherit composeConfig; };
    shulker.system.modules.containers.enable = true;
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/zulip-" cfg.stateDir && !(lib.hasInfix ".." cfg.stateDir);
        message = "Zulip requires a dedicated trial state root.";
      }
      {
        assertion =
          cfg.secretReference != ""
          && cfg.administratorEmail != ""
          && cfg.oidcClientId != ""
          && cfg.trustedProxyAddresses != [ ];
        message = "Zulip requires explicit identity, secret and trusted proxy configuration.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl && lib.hasPrefix "https://" cfg.oidcIssuer;
        message = "Zulip and OIDC must use HTTPS.";
      }
      {
        assertion = config.shulker.system.modules.backup.enable;
        message = "Zulip trial requires configured backups.";
      }
    ];
    services.onepassword-secrets.secrets.zulipTrialSecrets = {
      reference = cfg.secretReference;
      owner = "root";
      group = "root";
      mode = "0400";
      services = [ "zulip-trial" ];
    };
    systemd.services.zulip-trial = {
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      requires = [
        "docker.service"
        "opnix-secrets.service"
      ];
      after = [
        "docker.service"
        "opnix-secrets.service"
        "network-online.target"
      ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [
        pkgs.coreutils
        compose
      ];
      script = ''
        install -d -m 0700 ${cfg.stateDir} ${cfg.stateDir}/postgres ${cfg.stateDir}/rabbitmq ${cfg.stateDir}/redis ${cfg.stateDir}/backups
        # The private parent protects host access; Zulip must traverse its mounted /data.
        install -d -m 0755 ${cfg.stateDir}/data
        exec 9> ${cfg.stateDir}/maintenance.lock
        ${pkgs.util-linux}/bin/flock 9
        ${pkgs.python3}/bin/python ${./render-config.py} ${config.services.onepassword-secrets.secrets.zulipTrialSecrets.path} /run/zulip-trial
        zulip-trial-compose config --quiet
        zulip-trial-compose up -d --wait
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        TimeoutStartSec = 1800;
        RuntimeDirectory = "zulip-trial";
        RuntimeDirectoryMode = "0700";
        ExecStop = "${pkgs.util-linux}/bin/flock ${cfg.stateDir}/maintenance.lock ${compose}/bin/zulip-trial-compose stop";
      };
    };
    environment.systemPackages = [
      compose
      backup
    ];
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=,o=";
        }
      ];
    };
    services.borgmatic.settings.commands = [
      {
        before = "action";
        when = [ "create" ];
        run = [ "${backup}/bin/zulip-trial-backup" ];
      }
    ];
    shulker.system.modules.backup.dirs = [ "${cfg.stateDir}/backups" ];
  };
}
