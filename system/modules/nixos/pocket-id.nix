{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.pocket-id;
in
{
  options.shulker.system.modules.pocket-id = {
    enable = mkEnableOption "Enable pocket-id service";
    impermanence = mkEnableOption "Enable impermanence for pocket-id.";
    appUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Url where pocket-id will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pocket-id";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open pocket-id.";
    };
  };

  config = mkIf cfg.enable {

    services.pocket-id = {
      enable = true;
      dataDir = cfg.stateDir;
      settings = {
        TRUST_PROXY = true;
        APP_URL = "https://${cfg.subDomain}.${cfg.baseUrl}";
        HOST = "127.0.0.1";
        PORT = cfg.port;
        APP_NAME = "Shulker SSO";
        EMAILS_VERIFIED = true;
        SMTP_USER = "service@shulker.link";
        SMTP_HOST = "smtp.fastmail.com";
        SMTP_PORT = 465;
        SMTP_FROM = "sso@shulker.link";
        SMTP_TLS = "tls";
        EMAIL_LOGIN_NOTIFICATION_ENABLED = true;
        EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED = true;
        EMAIL_API_KEY_EXPIRATION_ENABLED = true;
      };
      credentials = {
        ENCRYPTION_KEY = config.services.onepassword-secrets.secrets.pocketIdEncryptionKey.path;
        MAXMIND_LICENSE_KEY = config.services.onepassword-secrets.secrets.pocketIdMaxminLicenseKey.path;
        SMTP_PASSWORD = config.services.onepassword-secrets.secrets.pocketIdSMTPPassword.path;
      };
    };

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
          user = "pocket-id";
          group = "pocket-id";
        }
      ];
    };

    services.onepassword-secrets.secrets.pocketIdEncryptionKey = {
      reference = "op://Shulker/${config.networking.hostName}/Pocket ID Encryption Key";
      services = [ "pocket-id" ];
    };

    services.onepassword-secrets.secrets.pocketIdMaxminLicenseKey = {
      reference = "op://Shulker/${config.networking.hostName}/Pocket ID Maxmind License Key";
      services = [ "pocket-id" ];
    };

    services.onepassword-secrets.secrets.pocketIdSMTPPassword = {
      reference = "op://Shulker/${config.networking.hostName}/Pocket ID SMTP Password";
      services = [ "pocket-id" ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
    services.borgmatic.settings.sqlite_databases = [
      {
        name = "pocket-id-db";
        path = "${cfg.stateDir}/data/pocket-id.db";
      }
    ];
  };
}
