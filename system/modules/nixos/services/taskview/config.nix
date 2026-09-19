# Materialize secrets outside the Nix store; Compose raw env files preserve literal values.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.taskview;
  centrifugoConfig = {
    http_server = {
      port = 8000;
      internal_port = "9000";
    };
    client.allowed_origins = [ cfg.publicUrl ];
    channel.namespaces = [
      {
        name = "personal";
        allow_user_limited_channels = true;
        presence = false;
        join_leave = false;
        history_size = 0;
        history_ttl = "0s";
      }
    ];
  };
  base = pkgs.writeText "taskview-centrifugo-public.json" (builtins.toJSON centrifugoConfig);
in
{
  options.shulker.system.modules.taskview.centrifugoConfig = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    internal = true;
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.taskview.centrifugoConfig = centrifugoConfig;
    shulker.system.secretPreflight.schemas.taskviewEnv = {
      format = "dotenv";
      exactKeys =
        (lib.genAttrs
          [
            "DB_PASSWORD"
            "JWT_SIGN"
            "ENCRYPTION_KEY"
            "CENTRIFUGO_API_KEY"
            "CENTRIFUGO_TOKEN_SECRET"
            "SMTP_HOST"
            "SMTP_PORT"
            "SMTP_ENCRYPTION"
            "SMTP_FROM_NAME"
            "SMTP_FROM_EMAIL"
            "SMTP_USERNAME"
            "SMTP_PASSWORD"
            "SSO_TRUSTED_DOMAINS"
          ]
          (_: {
            minLength = 1;
            pattern = "^.+$";
          })
        )
        // {
          ENCRYPTION_KEY = {
            minLength = 64;
            pattern = "^[0-9a-fA-F]{64}$";
          };
          JWT_SIGN = {
            minLength = 32;
            pattern = "^.+$";
          };
          CENTRIFUGO_API_KEY = {
            minLength = 32;
            pattern = "^.+$";
          };
          CENTRIFUGO_TOKEN_SECRET = {
            minLength = 32;
            pattern = "^.+$";
          };
          SSO_TRUSTED_DOMAINS = {
            minLength = 1;
            pattern = "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+(,[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+)*$";
          };
          SMTP_PORT = {
            minLength = 1;
            pattern = "^[0-9]{1,5}$";
          };
          SMTP_ENCRYPTION = {
            minLength = 3;
            pattern = "^(ssl|tls)$";
          };
        };
    };
    systemd.services.taskview-config = {
      description = "Render TaskView runtime secrets";
      requires = [ "opnix-secrets.service" ];
      after = [ "opnix-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "taskview";
        RuntimeDirectoryMode = "0700";
        RuntimeDirectoryPreserve = "yes";
        UMask = "0077";
        ExecStart = "${pkgs.python3}/bin/python3 ${./render-config.py} ${config.services.onepassword-secrets.secrets.taskviewEnv.path} /run/taskview ${base}";
      };
    };
  };
}
