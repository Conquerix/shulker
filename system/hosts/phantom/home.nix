{ pkgs, ... }:

{
  home.packages = with pkgs; [
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
        ssh.enable = true;
        zsh.enable = true;
      };
    };

    profiles = {
      common.enable = true;
      development.enable = true;
    };
  };
}
