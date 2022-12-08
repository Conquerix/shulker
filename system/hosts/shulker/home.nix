{ pkgs, ... }:

{
  home.packages = with pkgs; [
    soft-serve
  ];

  shulker = {
    modules = {
      app = {
        discord.enable = true;
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
