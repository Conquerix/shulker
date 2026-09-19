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
