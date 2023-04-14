# https://cmacr.ae/post/2020-05-09-managing-firefox-on-macos-with-nix/
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.app.vscodium;
in
{
  options.shulker.modules.app.vscodium = {
    enable = mkEnableOption "VSCodium configuration";
  };

  config = mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      extensions = with pkgs.vscode-extensions; [
        yzhang.markdown-all-in-one
        eamodio.gitlens
        donjayamanne.githistory
        streetsidesoftware.code-spell-checker
        vscode-icons-team.vscode-icons
        oderwat.indent-rainbow
        github.copilot
      ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "better-comments";
          publisher = "aaron-bond";
          version = "3.0.2";
          sha256 = "sha256-hQmA8PWjf2Nd60v5EAuqqD8LIEu7slrNs8luc3ePgZc=";
        }
      ];
    };
  };
}

  
