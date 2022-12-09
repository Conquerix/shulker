{ pkgs, ... }:

{
  home.packages = with pkgs; [
  ];

  shulker = {
    modules = {
      shell = {
        ssh.enable = true;
      };
    };

    profiles = {
      common.enable = true;
    };
  };
}
