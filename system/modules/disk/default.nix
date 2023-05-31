{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.disk;
in
{
  options.shulker.modules.disk.enable = mkEnableOption "disk utilities and file managers";

  config = mkIf cfg.enable {
    # udiskctl service to manipulate storage devices. Mount and unmount without the need for sudo
    services.udisks2.enable = true;

    # Userspace virtual file system
    services.gvfs.enable = true;

    # Enable thumbnail service
    services.tumbler.enable = true;
  };
}
