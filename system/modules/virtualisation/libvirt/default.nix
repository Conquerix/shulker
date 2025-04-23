# https://gist.github.com/CRTified/43b7ce84cd238673f7f24652c85980b3?permalink_comment_id=3793931
{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.virtualisation.libvirtd;

  boolToZeroOne = x: if x then "1" else "0";

  aclString = with lib.strings;
    concatMapStringsSep ''
      ,
        '' escapeNixString cfg.deviceACL;
in {
  options.virtualisation.libvirtd = {
    deviceACL = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    clearEmulationCapabilities = mkOption {
      type = types.bool;
      default = true;
    };
    persistence = mkEnableOption "Enable libvirt persistence in /nix/persist";
  };

  config = {
    # Add qemu-libvirtd to the input group if required
    users.users."qemu-libvirtd" = {
      extraGroups = optionals (!cfg.qemu.runAsRoot) [ "kvm" "input" ];
      isSystemUser = true;
    };

    virtualisation.libvirtd.qemu.verbatimConfig = ''
      clear_emulation_capabilities = ${
        boolToZeroOne cfg.clearEmulationCapabilities
      }
      cgroup_device_acl = [
        ${aclString}
      ]
    '';

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable && cfg.persistence) {
      "/nix/persist".directories = [ 
        {
          directory = "/var/lib/libvirt";
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };
  };
}