{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.forgejo;
in
{
  options.shulker.system.modules.forgejo = {
    enable = mkEnableOption "Enable forgejo service";
    impermanence = mkEnableOption "Whether to enable impermanence on state directories.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where forgejo will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "forgejo";
      description = "Default subdomain where forgejo will be accessible.";
    };
    httpPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open forgejo.";
    };
    sshPort = mkOption {
      type = types.port;
      default = 22;
      description = "SSH Port to display in forgejo.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/forgejo";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    services.forgejo = {
      enable = true;
      stateDir = cfg.stateDir;
      lfs.enable = true;
      dump = {
        enable = true;
        interval = "06:00";
        age = "3d";
      };
      secrets = {
        security = {
          SECRET_KEY = mkForce config.services.onepassword-secrets.secrets.forgejoSecretKey.path;
          INTERNAL_TOKEN = mkForce config.services.onepassword-secrets.secrets.forgejoInternalToken.path;
        };
        mailer = {
          PASSWD = config.services.onepassword-secrets.secrets.forgejoSMTPPassword.path;
        };
      };
      settings = {
        DEFAULT = {
          APP_NAME = "Amphibian Git forge.";
        };
        repository = {
          MAX_CREATION_LIMIT = 0;
          ALLOW_FORK_WITHOUT_MAXIMUM_LIMIT = false;
        };
        ui = {
          SHOW_USER_EMAIL = false;
        };
        "ui.meta" = {
          AUTHOR = "Amphibian Git forge.";
          DESCRIPTION = "Powered by Forgejo";
        };
        server = {
          ROOT_URL = "https://${cfg.subDomain}.${cfg.baseUrl}:443";
          DOMAIN = "${cfg.subDomain}.${cfg.baseUrl}";
          HTTP_PORT = cfg.httpPort;
          SSH_PORT = cfg.sshPort;
        };
        admin = {
          SEND_NOTIFICATION_EMAIL_ON_NEW_USER = true;
        };
        oauth2_client = {
          ENABLE_AUTO_REGISTRATION = true;
          UPDATE_AVATAR = true;
        };
        service = {
          ENABLE_NOTIFY_MAIL = true;
          DEFAULT_KEEP_EMAIL_PRIVATE = true;
          DEFAULT_ALLOW_CREATE_ORGANIZATION = false;
          SHOW_REGISTRATION_BUTTON = false;
          ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        };
        mailer = {
          ENABLED = true;
          PROTOCOL = "smtps";
          SMTP_ADDR = "smtp.fastmail.com";
          SMTP_PORT = 465;
          USER = "service@shulker.link";
          FROM = "Git Amphibian Network <${cfg.subDomain}@${cfg.baseUrl}>";
        };
        session = {
          COOKIE_SECURE = true;
        };
      };
    };

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
          user = config.services.forgejo.user;
          group = config.services.forgejo.group;
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ config.services.forgejo.dump.backupDir ];

    services.onepassword-secrets.secrets.forgejoSecretKey = {
      reference = "op://Shulker/${config.networking.hostName}/Forgejo/Forgejo Secret Key";
      services = [ "forgejo" ];
      owner = config.services.forgejo.user;
      group = config.services.forgejo.group;
    };

    services.onepassword-secrets.secrets.forgejoInternalToken = {
      reference = "op://Shulker/${config.networking.hostName}/Forgejo/Forgejo Internal Token";
      services = [ "forgejo" ];
      owner = config.services.forgejo.user;
      group = config.services.forgejo.group;
    };

    services.onepassword-secrets.secrets.forgejoSMTPPassword = {
      reference = "op://Shulker/${config.networking.hostName}/Forgejo/Forgejo SMTP Password";
      services = [ "forgejo" ];
      owner = config.services.forgejo.user;
      group = config.services.forgejo.group;
    };
  };
}
