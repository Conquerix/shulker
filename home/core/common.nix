{
  lib,
  pkgs,
  inputs,
  ...
}:

with lib;
{
  config = {

    # For compatibility with nix-shell, nix-build, etc.
    home.file.".nixpkgs".source = inputs.nixpkgs;
    home.sessionVariables."NIX_PATH" = "nixpkgs=$HOME/.nixpkgs\${NIX_PATH:+:}$NIX_PATH";

    # Use the same Nix configuration for the user
    xdg.configFile."nixpkgs/config.nix".source = lib.custom.relativeToRoot "nix/config.nix";

    # Re-expose self and nixpkgs as flakes.
    xdg.configFile."nix/registry.json".text = builtins.toJSON {
      version = 2;
      flakes =
        let
          toInput =
            input:
            {
              type = "path";
              path = input.outPath;
            }
            // (lib.filterAttrs (
              n: _: n == "lastModified" || n == "rev" || n == "revCount" || n == "narHash"
            ) input);
        in
        [
          {
            from = {
              id = "shulker";
              type = "indirect";
            };
            to = toInput inputs.self;
          }
          {
            from = {
              id = "nixpkgs";
              type = "indirect";
            };
            to = toInput inputs.nixpkgs;
          }
        ];
    };

    # Directories to add to the PATH environment variable
    home.sessionPath = [
      "$HOME/.local/shulker/bin"
      "$XDG_BIN_HOME"
    ];

    home.stateVersion = "22.05";

    #nixpkgs.config.allowUnfree = true;
    home = {
      enableDebugInfo = true;
      packages = with pkgs; [
        # Determine file type.
        file
        # Show full path of shell commands.
        which
        # Daemon to execute scheduled commands.
        cron
        # Collection of useful tools that aren't coreutils.
        moreutils
        # Non-interactive network downloader.
        wget
        # List directory contents in tree-like format.
        tree
        # Mote interactive top (btm)
        bottom
        # Man pages
        man
        man-pages
        man-pages-posix
        stdman
        # grep alternative.
        ripgrep
        # Simple, fast and user-friendly alternative to find.
        fd
        # sed alternative
        sd
        # Interactive du with rm functionality
        dua
        # A modern replacement for ps
        procs
      ];
    };

    # Manage home-manager with home-manager (inception)
    programs.home-manager.enable = true;

    # Install home-manager manpages.
    manual.manpages.enable = true;

    # Install man output for any Nix packages.
    programs.man.enable = true;

    programs.bat.enable = true;
    programs.zoxide.enable = true;

    shulker.home.modules = {
      # shell.ssh.enable = true;
      shell.starship.enable = true;
      # shell.xdg.enable = true;
    };
  };
}
