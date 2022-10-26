{ config, lib, pkgs, self, user, ... }:

with self.lib;
let
  cfg = config.shulker.modules.user;

  defaultName = existsOrDefault "name" user null;

  isPasswdCompatible = str: !(hasInfix ":" str || hasInfix "\n" str);
  passwdEntry = type: lib.types.addCheck type isPasswdCompatible // {
    name = "passwdEntry ${type.name}";
    description = "${type.description}, not containing newlines or colons";
  };

  defaultHashedPassword = existsOrDefault "hashedPassword" user null;

  defaultExtraGroups = [
    "audio"
    "docker"
    "games"
    "locate"
    "networmanager"
    "wheel"
  ];
in
{
  options.shulker.modules.user = {

    name = mkOption {
      type = types.str;
      default = defaultName;
      description = "User's name";
    };

    home = mkOption {
      type = with types; nullOr types.path;
      default = null;
      description = "Path of home manager home file";
    };

    extraGroups = mkOption {
      type = types.listOf types.str;
      default = defaultExtraGroups;
      description = "The user's auxiliary groups.";
    };

    hashedPassword = mkOption {
      type = with types; nullOr (passwdEntry str);
      default = defaultHashedPassword;
      description = ''
        Specifies the hashed password for the user.
      '';
    };
  };

  config = mkMerge [

    (
      mkIf (cfg.home != null) {
        home-manager.users."${cfg.name}" = mkUserHome { inherit system; config = cfg.home; };
      }
    )

    {
      users = {
        users."${cfg.name}" = with cfg; {
          inherit hashedPassword extraGroups;
          isNormalUser = true;
          # `shell` attribute cannot be removed! If no value is present then there will be no shell
          # configured for the user and SSH will not allow logins!
          shell = pkgs.zsh;
          uid = 1000;
        };

        # Do not allow users to be added or modified except through Nix configuration.
        mutableUsers = false;
      };

      nix.settings.trusted-users = [ "${cfg.name}" ];
    }
  ];
}
