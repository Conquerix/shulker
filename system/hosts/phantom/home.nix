{ pkgs, ... }:

{
  home.packages = with pkgs; [
    prismlauncher
    spotify
    wineWowPackages.waylandFull
    libvlc
    packwiz
  ];
  
  shulker = {
    modules = {
      app = {
        discord.enable = true;
        libreoffice.enable = true;
        vscodium.enable = true;
      };
      dev = {
        cc.enable = true;
        nix.enable = true;
        python.enable = true;
        rust.enable = true;
      };
      shell = {
        direnv.enable = true;
        ssh = {
          enable = true;
          _1password = true;
        };
        zsh.enable = true;
      };
    };

    profiles = {
      common.enable = true;
      development.enable = true;
    };
  };
}
