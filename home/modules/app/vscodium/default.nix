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
      mutableExtensionsDir = true;
      extensions = with pkgs.vscode-extensions; [
        njpwerner.autodocstring
        ms-python.black-formatter
        yzhang.markdown-all-in-one
        eamodio.gitlens
        donjayamanne.githistory
        streetsidesoftware.code-spell-checker
        vscode-icons-team.vscode-icons
        oderwat.indent-rainbow
        naumovs.color-highlight
        alexdima.copy-relative-path
        usernamehw.errorlens
        tamasfe.even-better-toml
        ms-python.isort
        alefragnani.project-manager
        jnoortheen.nix-ide
        ms-vscode-remote.remote-ssh
        #rust-lang.rust-analyzer
        github.github-vscode-theme
        mkhl.direnv
      ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "better-comments";
          publisher = "aaron-bond";
          version = "3.0.2";
          sha256 = "sha256-hQmA8PWjf2Nd60v5EAuqqD8LIEu7slrNs8luc3ePgZc=";
        }
        {
          name = "devbox";
          publisher = "jetpack-io";
          version = "0.1.5";
          sha256 = "sha256-+nIeDaz1NPYFoxFVC8GQxtU1MU/sbdFETAQWzVX6LGQ=";
        }
        {
          name = "python-environment-manager";
          publisher = "donjayamanne";
          version = "1.2.4";
          sha256 = "sha256-1jvuoaP+bn8uR7O7kIDZiBKuG3VwMTQMjCJbSlnC7Qo=";
        }
      ];
    };
  };
}

  
