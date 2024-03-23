{ pkgs, ... }:

{
  home.packages = with pkgs; [
    spotify
    libvlc
  ];
  
  shulker = {
    modules = {
      app = {
        libreoffice.enable = true;
      };
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
