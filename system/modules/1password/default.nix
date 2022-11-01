{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules._1password;
in
{
  options.shulker.modules._1password = { 
    enable = mkEnableOption "1password app & security wrappers handling for system login usage";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      [
        _1password-gui
        _1password
      ];

    users.groups.onepassword.gid = 5000;

    security.wrappers = {
        "1Password-BrowserSupport" =
          {
            source = "${config.programs._1password-gui.package}/share/1password/1Password-BrowserSupport";
            owner = "root";
            group = "onepassword";
            setuid = false;
            setgid = true;
          };
      
        "1Password-KeyringHelper" =
          {
            source = "${config.programs._1password-gui.package}/share/1password/1Password-KeyringHelper";
            owner = "root";
            group = "onepassword";
            setuid = true;
            setgid = true;
          };
        };
  };
}
