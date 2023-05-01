{ pkgs, ... }:

{
  home.packages = with pkgs; [
    prismlauncher
    zoom-us
    spotify
    wineWowPackages.waylandFull
  ];

  gtk = {
    enable = true;
  
      theme = {
        name = "colloid-gtk-theme";
        package = pkgs.colloid-gtk-theme;
      };
  
      iconTheme = {
        name = "colloid-icon-theme";
        package = pkgs.colloid-icon-theme;
      };

    gtk3.extraConfig = {
      Settings = ''
        gtk-application-prefer-dark-theme=1
      '';
    };

    gtk4.extraConfig = {
      Settings = ''
        gtk-application-prefer-dark-theme=1
      '';
    };
  };
  
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
        ocaml.enable = true;
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
