# https://cmacr.ae/post/2020-05-09-managing-firefox-on-macos-with-nix/
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.app.vscode;
in
{
  options.shulker.home.modules.app.vscode = {
    enable = mkEnableOption "VSCode configuration";
  };

  config = mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      mutableExtensionsDir = false;
      profiles.default = {
        enableExtensionUpdateCheck = false;
        enableUpdateCheck = false;
        extensions =
          with pkgs.vscode-extensions;
          [
            yzhang.markdown-all-in-one
            vscode-icons-team.vscode-icons
            oderwat.indent-rainbow
            alexdima.copy-relative-path
            tamasfe.even-better-toml
            alefragnani.project-manager
            jnoortheen.nix-ide
            ms-vscode-remote.remote-ssh
            mkhl.direnv
            jgclark.vscode-todo-highlight
            alefragnani.bookmarks
            mhutchie.git-graph
          ]
          ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
            {
              name = "better-comments";
              publisher = "aaron-bond";
              version = "3.0.2";
              sha256 = "sha256-hQmA8PWjf2Nd60v5EAuqqD8LIEu7slrNs8luc3ePgZc=";
            }
            {
              name = "better-git-line-blame";
              publisher = "mk12";
              version = "0.2.14";
              sha256 = "sha256-mPPNM8QnmZfmC3lKT8Gy4J4Old0Fpu/5TU8KKmAUiYg=";
            }
            {
              name = "oled-neon-theme";
              publisher = "gustavoinacio";
              version = "0.0.3";
              sha256 = "sha256-EenTsFS17WBDpjpIOdupdL9NAL3QmQvTr77XvaDGIQE=";
            }
          ];
        userSettings = {
          "window.titleBarStyle" = "custom";
          "terminal.integrated.sendKeybindingsToShell" = true;
          "projectManager.git.baseFolders" = [ "~/Fichiers/Git" ];
          "workbench.startupEditor" = "none";
          "editor.mouseWheelZoom" = true;
          "explorer.confirmDragAndDrop" = false;
          "terminal.integrated.smoothScrolling" = true;
          "editor.selectionClipboard" = false;
          "editor.smoothScrolling" = true;
          "editor.formatOnPaste" = true;
          "editor.formatOnSave" = true;
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
          "workbench.settings.showAISearchToggle" = false;
          "chat.disableAIFeatures" = true;
          "workbench.colorTheme" = "Oled Neon Theme Black";
        };
      };
    };
  };
}
