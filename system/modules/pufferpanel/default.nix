{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.pufferpanel;
in
{
  options.shulker.modules.pufferpanel = {
    enable = mkEnableOption "Enable pufferpanel";
    webPort= mkOption {
      description = "Port of pufferpanel webui";
      type = types.port;
      default = 8080;
    };
    sftpPort= mkOption {
      description = "Port of pufferpanel sftp server";
      type = types.port;
      default = 5657;
    };
    companyName= mkOption {
      description = "Name of pufferpanel company/org";
      type = types.str;
      default = "PufferPanel";
    };
  };

  config = mkIf cfg.enable {
    services.pufferpanel = {
      enable = true;
      extraPackages = with pkgs; [ bash curl gawk gnutar gzip ];
      package = pkgs.buildFHSEnv {
        name = "pufferpanel-fhs";
        runScript = lib.getExe pkgs.pufferpanel;
        targetPkgs = pkgs': with pkgs'; [ icu openssl zlib ];
      };
      environment = {
        PUFFER_WEB_HOST = ":${cfg.webPort}";
        PUFFER_DAEMON_SFTP_HOST = ":${cfg.sftpPort}";
        PUFFER_PANEL_SETTINGS_COMPANYNAME = "${cfg.companyName}";
        PUFFER_PANEL_REGISTRATIONENABLED = "false";
      };
    };
  };
}
