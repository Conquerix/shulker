{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules._1password;
in
{
  options.shulker.modules._1password = { 
    enable = mkEnableOption "1password app & security wrappers handling for system login usage";

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "list of users authorized to use 1password integration";
    };
  };

  config = mkIf cfg.enable {
    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = cfg.users;
    };
    programs._1password.enable = true;
  };
}
