{ pkgs, ... }:

{
  home.packages = with pkgs; [
  ];

  shulker = {
    modules = {
      dev = {
        python.enable = true;
      };
      shell = {
        ssh.enable = true;
      };
    };

    profiles = {
      common.enable = true;
    };
  };
}
