{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.webdav;
  serviceName = "graphene-webdav";
  serviceUser = "graphene-webdav";
  portableConfig = pkgs.writeTextDir "sftpgo.json" (builtins.toJSON { });
  passwordFile = config.services.onepassword-secrets.secrets.grapheneWebdavPassword.path;
in
{
  options.shulker.system.modules.webdav = {
    enable = lib.mkEnableOption "SFTPGo WebDAV target for GrapheneOS backups";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/graphene-webdav";
      description = "Persistent directory exposed as the WebDAV user's root.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which the WebDAV listener accepts connections.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 23235;
      description = "Loopback WebDAV port intended for a TLS-terminating reverse proxy.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "grapheneos";
      description = "WebDAV Basic authentication username.";
    };

    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include the received phone backups in this host's Borgmatic sources.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${serviceUser} = { };
    users.users.${serviceUser} = {
      isSystemUser = true;
      group = serviceUser;
      home = cfg.dataDir;
      createHome = false;
    };

    systemd.tmpfiles.settings."10-${serviceName}".${cfg.dataDir}.d = {
      mode = "0700";
      user = serviceUser;
      group = serviceUser;
    };

    systemd.services.${serviceName} = {
      description = "SFTPGo WebDAV target for GrapheneOS backups";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "opnix-secrets.service"
      ];
      wants = [ "opnix-secrets.service" ];
      unitConfig = {
        ConditionPathExists = passwordFile;
        RequiresMountsFor = cfg.dataDir;
      };
      environment.SFTPGO_WEBDAVD__BINDINGS__0__ADDRESS = cfg.bindAddress;
      serviceConfig = {
        User = serviceUser;
        Group = serviceUser;
        WorkingDirectory = cfg.dataDir;
        ExecStart = lib.escapeShellArgs [
          "${pkgs.sftpgo}/bin/sftpgo"
          "portable"
          "--config-dir"
          portableConfig
          "--directory"
          cfg.dataDir
          "--username"
          cfg.username
          "--password-file"
          passwordFile
          "--permissions"
          "*"
          "--sftpd-port"
          "-1"
          "--ftpd-port"
          "-1"
          "--httpd-port"
          "-1"
          "--webdav-port"
          (toString cfg.port)
          "--log-level"
          "info"
          "--log-utc-time"
          "--grace-time"
          "30"
        ];
        Restart = "on-failure";
        RestartSec = "10s";
        UMask = "0077";

        AmbientCapabilities = "";
        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.dataDir ];
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };

    services.onepassword-secrets.secrets.grapheneWebdavPassword = {
      reference = "op://Shulker/${config.networking.hostName}/GrapheneOS WebDAV/password";
      owner = serviceUser;
      group = serviceUser;
      mode = "0400";
      services = [ serviceName ];
    };

    shulker.system.modules.backup.dirs = lib.mkIf cfg.backUpData [ cfg.dataDir ];
  };
}
