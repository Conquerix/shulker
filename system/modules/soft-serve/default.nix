{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.soft-serve;
in
{
  options.shulker.modules.soft-serve = {
    enable = mkEnableOption "Enable soft serve service";
    path = mkOption {
      description = ''Path of repos directory'';
      type = types.str;
      default = "/var/lib/soft-serve";
    };
    port = mkOption {
      description = ''Port to bind the ssh interface to.'';
      type = types.port;
      default = 23231;
    };
  };

  config = mkIf cfg.enable {

    environment = mkIf (config.shulker.modules.impermanence.enable) {
      persistence."/nix/persist".directories = [{ directory = cfg.path; user = "root"; group = "root"; mode = "u=rw,g=rw,o="; }];
    };

    virtualisation.oci-containers.containers = {
      "soft-serve" = {
        image = "charmcli/soft-serve:latest";
        ports = [ "${toString cfg.port}:23231" ];
        volumes = [ "${cfg.path}:/soft-serve" ];
      };
    };
  };
}
