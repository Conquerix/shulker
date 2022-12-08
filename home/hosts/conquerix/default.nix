{pkgs, ... }:

{
  home.stateVersion = "22.05";

  home.packages = [ pkgs.guake ];
  
  shulker = {
    modules = {
      dev = {
        cc.enable = true;
        rust.enable = true;
      };
    };
    profiles = {
      common.enable = true;
      extended.enable = true;
      development.enable = true;
    };
  };
}
