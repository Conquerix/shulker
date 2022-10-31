{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.onepassword;
in
{
  options.shulker.modules.onepassword = { 
    enable = mkEnableOption "1password app & security wrappers handling for system login usage";
  };

  config = mkIf cfg.enable {
    system.packages = with pkgs;
      [
        _1password-gui
        _1password
      ];

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
