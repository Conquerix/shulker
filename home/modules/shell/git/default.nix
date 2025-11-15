{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.git;

  signModule = types.submodule {
    options = {
      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The default GPG signing key fingerprint.";
      };

      signByDefault = mkOption {
        type = types.bool;
        default = false;
        description = "Whether commits should be signed by default.";
      };

      gpgPath = mkOption {
        type = types.nullOr types.str;
        default = "${pkgs.gnupg}/bin/gpg2";
        defaultText = "\${pkgs.gnupg}/bin/gpg2";
        description = "Path to GnuPG binary to use.";
      };
    };
  };
in
{
  options.shulker.home.modules.shell.git = {
    enable = mkEnableOption "git configuration";

    inheritUser = mkOption {
      type = types.bool;
      default = true;
      description = "Inherit username, email and signingKey from user";
    };

    minimal = mkOption {
      type = types.bool;
      default = false;
      description = "Minimal install without extra packages";
    };

    username = mkOption {
      type = types.str;
      default = "Conquerix";
      description = "Default user name to use.";
    };

    email = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default user email to use.";
    };

    signing = mkOption {
      type = signModule;
      default = { };
      description = "Options related to signing commits using GnuPG.";
    };
  };

  config = mkIf cfg.enable {
    home.sessionPath = [ "${config.xdg.configHome}/git/bin" ];

    home.packages =
      with pkgs;
      let
        minimal = [
          git
          jq
        ];

        extra =
          if !cfg.minimal then
            [
              git-lfs
              delta
              gh
              glab
              git-filter-repo
              git-open
              (mkIf config.shulker.home.modules.shell.gnupg.enable git-crypt)
            ]
          else
            [ ];

        total = minimal ++ extra;
      in
      total;

    xdg.dataFile."git/nyx-gen".text =
      let
        firstOrDefault =
          x: y:
          if !isNull x then
            x
          else if cfg.inheritUser then
            y
          else
            null;
        username = cfg.username;
        email = cfg.email;
        signkey = cfg.signing.key;
        signByDefault = (!isNull signkey) || cfg.signing.signByDefault;
      in
      ''
        [user]
        name = "${cfg.username}"
        ${
          if isNull email then
            ""
          else
            ''
              [user]
              email = "${email}"
            ''
        }
        ${
          if isNull signkey then
            ""
          else
            ''
              [user]
              signingKey = "${signkey}"
            ''
        }
        ${
          if !signByDefault then
            ""
          else
            ''
              [commit]
              gpgSign = true
              [tag]
              gpgSign = true
            ''
        }
        [gpg]
        program = ${cfg.signing.gpgPath}
      '';

    shulker.home.modules.shell.bash.profileExtra = ''
      source "${pkgs.git}/share/bash-completion/completions/git"
      __git_complete g __git_main
    '';
  };
}
