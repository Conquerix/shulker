{ pkgs, ... }:

{
  home.packages = with pkgs; [
    prismlauncher
    android-tools
    vlc
    pinta
    zoom-us
    spotify
    lapce
    (with eclipses; eclipseWithPlugins {
      eclipse = eclipse-modeling;
      plugins = [ plugins.cdt ];
    })
    openmodelica.combined
  ];

  shulker = {
    modules = {
      app = {
        discord.enable = true;
        libreoffice.enable = true;
      };
      dev = {
        cc.enable = true;
        nix.enable = true;
        python.enable = true;
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
