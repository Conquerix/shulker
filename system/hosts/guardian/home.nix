{ pkgs, ... }:

{
  
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
