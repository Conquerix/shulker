{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.users.conquerix;
  isDarwin = config.shulker.global.type == "darwin";
in
{

  config = lib.mkIf (cfg.enable && isDarwin) {
    users.users.conquerix.home = /Users/conquerix;

    home-manager.users.conquerix = {
      home.packages = with pkgs; [
        spotify
        ryubing
      ];

      programs.ghostty.package = pkgs.ghostty-bin;

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
