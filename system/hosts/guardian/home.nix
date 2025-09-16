{ pkgs, lib, ... }:

{
  manual = {
    html.enable = false;
    manpages.enable = lib.mkForce false;
    json.enable = false;
  };
  shulker = {
    modules = {
      shell = {
        ssh = {
          enable = true;
          _1password = true;
        };
      };
    };

    profiles = {
      common.enable = true;
    };
  };
}
