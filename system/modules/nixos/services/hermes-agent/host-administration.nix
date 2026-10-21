{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.hermes-agent;
  operators = builtins.attrValues (
    lib.filterAttrs (_: i: cfg.enable && i.enable && i.hostAdministration.enable) cfg.instances
  );
in
{
  config = lib.mkIf (operators != [ ]) {
    users.groups = builtins.listToAttrs (
      map (i: lib.nameValuePair i.hostAdministration.user { }) operators
    );
    users.users = builtins.listToAttrs (
      map (
        i:
        lib.nameValuePair i.hostAdministration.user {
          isSystemUser = true;
          group = i.hostAdministration.user;
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = [ "restrict ${i.hostAdministration.sshPublicKey}" ];
        }
      ) operators
    );
    # Intentionally retain approved ALL root authority, not a sudo allowlist.
    security.sudo-rs.execWheelOnly = lib.mkForce false;
    security.sudo-rs.extraRules = map (i: {
      users = [ i.hostAdministration.user ];
      runAs = "root";
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }) operators;
  };
}
