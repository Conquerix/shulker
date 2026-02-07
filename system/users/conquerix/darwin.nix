{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.users.conquerix;
in
{

  config = lib.mkIf (cfg.enable && config.shulker.global.type == "darwin") {
    users.users.conquerix = {
      home = /Users/conquerix;
      uid = 1000;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILCQToe+S6lXjwMCrcg9smHlb8tEp2613jW/lOkfSSm1"
      ];
    };

    home-manager.users.conquerix = {
      home.packages = with pkgs; [
        spotify
        ryubing
      ];

      programs.ghostty.package = lib.mkIf cfg.darwin pkgs.ghostty-bin;

      shulker.home = {
        modules = {
          app = {
            discord.enable = true;
            vscode.enable = true;
            ghostty.enable = true;
          };
          dev = {
            nix.enable = true;
            python.enable = true;
          };
          shell = {
            direnv.enable = true;
            zsh.enable = true;
            opencode.enable = true;
            starship.enable = true;
          };
        };
      };
    };
  };
}
