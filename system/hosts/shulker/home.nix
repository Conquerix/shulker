{ pkgs, ... }:

{

  shulker = {
    modules = {
      shell = {
        direnv.enable = true;
        ssh.enable = true;
        zsh.enable = true;
      };
    };

    profiles = {
      common.enable = true;
    };
  };
}
