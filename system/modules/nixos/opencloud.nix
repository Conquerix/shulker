{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.opencloud;
  serviceName = "docker-opencloud";
  stateServiceName = "opencloud-state";
  environmentFile = config.services.onepassword-secrets.secrets.opencloudEnv.path;
  oidcWebSocketUrl = lib.replaceStrings [ "https://" ] [ "wss://" ] cfg.oidcIssuer;
  yaml = pkgs.formats.yaml { };
  cspConfig = yaml.generate "opencloud-csp.yaml" {
    directives = {
      "child-src" = [ "'self'" ];
      "connect-src" = [
        "'self'"
        "blob:"
        cfg.oidcIssuer
        oidcWebSocketUrl
      ];
      "default-src" = [ "'none'" ];
      "font-src" = [ "'self'" ];
      "frame-ancestors" = [ "'self'" ];
      "frame-src" = [
        "'self'"
        "blob:"
        cfg.oidcIssuer
      ];
      "img-src" = [
        "'self'"
        "data:"
        "blob:"
      ];
      "manifest-src" = [ "'self'" ];
      "media-src" = [ "'self'" ];
      "object-src" = [
        "'self'"
        "blob:"
      ];
      "script-src" = [
        "'self'"
        "'unsafe-inline'"
        cfg.oidcIssuer
      ];
      "style-src" = [
        "'self'"
        "'unsafe-inline'"
      ];
      "worker-src" = [
        "'self'"
        "blob:"
      ];
    };
  };
  proxyConfig = yaml.generate "opencloud-proxy.yaml" {
    role_quotas = {
      # Stable OpenCloud role IDs: Admin, SpaceAdmin, and User.
      "71881883-1768-46bd-a24d-a356a2afdf7f" = cfg.personalQuotaBytes;
      "2aadd357-682c-406b-8874-293091995fdd" = cfg.personalQuotaBytes;
      "d7beeea8-8ff4-406b-8fb6-ab2dd81e6b11" = cfg.personalQuotaBytes;
    };
  };
  bannedPasswords = pkgs.writeText "opencloud-banned-passwords.txt" ''
    password
    12345678
    OpenCloud
    OpenCloud-1
  '';
in
{
  options.shulker.system.modules.opencloud = {
    enable = lib.mkEnableOption "OpenCloud family file storage";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/opencloud";
      description = "Mount point containing all persistent OpenCloud configuration and data.";
    };

    dataset = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "ZFS dataset mounted at stateDir.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address on which to publish the OpenCloud HTTP listener.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 23236;
      description = "Loopback HTTP port intended for a TLS-terminating reverse proxy.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://cloud.example.com";
      description = "Public HTTPS URL used by the OpenCloud web and native clients.";
    };

    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      example = "https://sso.example.com";
      description = "External OpenID Connect issuer used for OpenCloud authentication.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10001;
      description = "Fixed host and container UID for OpenCloud state.";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10001;
      description = "Fixed host and container GID for OpenCloud state.";
    };

    personalQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 214748364800;
      description = "Default quota in bytes assigned to newly provisioned users.";
    };

    familyQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 805306368000;
      description = "Planned quota in bytes for the manually-created Family project space.";
    };

    backupSnapshotName = lib.mkOption {
      type = lib.types.str;
      default = "borgmatic";
      description = "Exact ZFS snapshot name reserved for Borgmatic backups.";
    };

    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include a consistent ZFS snapshot of all OpenCloud state in Borgmatic.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl;
        message = "OpenCloud publicUrl must use HTTPS.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.oidcIssuer;
        message = "OpenCloud oidcIssuer must use HTTPS.";
      }
      {
        assertion = lib.elem cfg.bindAddress [
          "127.0.0.1"
          "[::1]"
        ];
        message = "OpenCloud must remain bound to host loopback and be exposed through Pangolin.";
      }
      {
        assertion = cfg.stateDir != "" && lib.hasPrefix "/" cfg.stateDir;
        message = "OpenCloud stateDir must be an absolute path.";
      }
      {
        assertion = cfg.dataset != "";
        message = "OpenCloud requires a dedicated ZFS dataset.";
      }
      {
        assertion = !cfg.backUpData || config.shulker.system.modules.backup.enable;
        message = "OpenCloud backup coverage requires the Borgmatic backup module.";
      }
      {
        assertion =
          cfg.backupSnapshotName != ""
          && !(lib.hasInfix "/" cfg.backupSnapshotName)
          && !(lib.hasInfix "@" cfg.backupSnapshotName);
        message = "OpenCloud backupSnapshotName must be a simple ZFS snapshot component.";
      }
    ];

    shulker.system.modules.containers.enable = true;

    users.groups.opencloud.gid = cfg.gid;
    users.users.opencloud = {
      isSystemUser = true;
      uid = cfg.uid;
      group = "opencloud";
      home = cfg.stateDir;
    };

    fileSystems.${cfg.stateDir} = {
      device = cfg.dataset;
      fsType = "zfs";
      options = [ "zfsutil" ];
    };

    systemd.services.${stateServiceName} = {
      description = "Prepare persistent OpenCloud state";
      before = [ "${serviceName}.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        install -d -m 0750 -o opencloud -g opencloud \
          ${lib.escapeShellArg cfg.stateDir}/config \
          ${lib.escapeShellArg cfg.stateDir}/data
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    virtualisation.oci-containers.containers.opencloud = {
      image = "docker.io/opencloudeu/opencloud:7.2.3@sha256:707727b771e3267fc5558e228911007c35a206e5241bde3ffde3c76f6aef1f4c";
      user = "${toString cfg.uid}:${toString cfg.gid}";
      entrypoint = "/bin/sh";
      cmd = [
        "-c"
        "opencloud init || true; exec opencloud server"
      ];
      ports = [ "${cfg.bindAddress}:${toString cfg.port}:9200/tcp" ];
      volumes = [
        "${cfg.stateDir}/config:/etc/opencloud:rw"
        "${cfg.stateDir}/data:/var/lib/opencloud:rw"
        "${cspConfig}:/etc/opencloud/csp.yaml:ro"
        "${proxyConfig}:/etc/opencloud/proxy.yaml:ro"
        "${bannedPasswords}:/etc/opencloud/banned-password-list.txt:ro"
      ];
      environment = {
        OC_URL = cfg.publicUrl;
        OC_LOG_LEVEL = "info";
        OC_LOG_COLOR = "false";
        OC_LOG_PRETTY = "false";
        OC_INSECURE = "false";
        PROXY_HTTP_ADDR = "0.0.0.0:9200";
        PROXY_TLS = "false";
        PROXY_ENABLE_BASIC_AUTH = "false";
        IDM_CREATE_DEMO_USERS = "false";
        FRONTEND_CHECK_FOR_UPDATES = "false";
        PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";

        OC_PASSWORD_POLICY_BANNED_PASSWORDS_LIST = "banned-password-list.txt";
        OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD = "true";
        OC_SHARING_PUBLIC_WRITEABLE_SHARE_MUST_HAVE_PASSWORD = "true";
        OC_PASSWORD_POLICY_DISABLED = "false";
        OC_PASSWORD_POLICY_MIN_CHARACTERS = "12";
        OC_PASSWORD_POLICY_MIN_LOWERCASE_CHARACTERS = "1";
        OC_PASSWORD_POLICY_MIN_UPPERCASE_CHARACTERS = "1";
        OC_PASSWORD_POLICY_MIN_DIGITS = "1";
        OC_PASSWORD_POLICY_MIN_SPECIAL_CHARACTERS = "1";

        OC_EXCLUDE_RUN_SERVICES = "idp";
        OC_OIDC_ISSUER = cfg.oidcIssuer;
        PROXY_OIDC_ISSUER = cfg.oidcIssuer;
        WEB_OIDC_AUTHORITY = cfg.oidcIssuer;
        WEB_OIDC_METADATA_URL = "${cfg.oidcIssuer}/.well-known/openid-configuration";
        WEB_OIDC_RESPONSE_TYPE = "code";
        WEB_OIDC_SCOPE = "openid profile email groups";
        PROXY_OIDC_REWRITE_WELLKNOWN = "true";
        PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";
        PROXY_AUTOPROVISION_ACCOUNTS = "true";
        PROXY_AUTOPROVISION_CLAIM_USERNAME = "preferred_username";
        PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
        PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "name";
        PROXY_AUTOPROVISION_CLAIM_GROUPS = "groups";
        PROXY_USER_OIDC_CLAIM = "preferred_username";
        PROXY_USER_CS3_CLAIM = "username";
        PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
        PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM = "opencloud_role";
        GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";
        GRAPH_USERNAME_MATCH = "none";

        WEBFINGER_ANDROID_OIDC_CLIENT_ID = "OpenCloudAndroid";
        WEBFINGER_ANDROID_OIDC_CLIENT_SCOPES = "openid profile email offline_access";
        WEBFINGER_IOS_OIDC_CLIENT_ID = "OpenCloudIOS";
        WEBFINGER_IOS_OIDC_CLIENT_SCOPES = "openid profile email offline_access";
        WEBFINGER_DESKTOP_OIDC_CLIENT_ID = "OpenCloudDesktop";
        WEBFINGER_DESKTOP_OIDC_CLIENT_SCOPES = "openid profile email offline_access";

        STORAGE_USERS_DRIVER = "posix";
        STORAGE_USERS_ID_CACHE_STORE = "nats-js-kv";
        STORAGE_USERS_POSIX_ROOT = "/var/lib/opencloud/storage/users";
        STORAGE_USERS_POSIX_WATCH_FS = "false";
      };
      environmentFiles = [ environmentFile ];
      extraOptions = [
        "--pids-limit=1024"
        "--security-opt=no-new-privileges:true"
      ];
      log-driver = "journald";
    };

    systemd.services.${serviceName} = {
      requires = [
        "${stateServiceName}.service"
        "opnix-secrets.service"
      ];
      after = [
        "${stateServiceName}.service"
        "opnix-secrets.service"
        "network-online.target"
      ];
      unitConfig.ConditionFileNotEmpty = environmentFile;
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = 5;
      };
    };

    services.onepassword-secrets.secrets.opencloudEnv = {
      reference = "op://Shulker/${config.networking.hostName}/OpenCloud/Environment";
      services = [ serviceName ];
      owner = "opencloud";
      group = "opencloud";
      mode = "0400";
    };
  };
}
