{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.profiles.extended;
in
{
  options.shulker.profiles.extended = {
    enable = mkEnableOption "extended profile";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        # Bandwidth monitor and rate estimator.
        bmon
        # Dump traffic on a network.
        tcpdump
        # A command-line tool to generate, analyze, convert and manipulate colors.
        # pastel
        # Tool for indexing, slicing, analyzing, splitting and joining CSV files.
        xsv
        # Command line image viewer
        viu
        # Tool for discovering and probing hosts on a computer network
        arping
        # Recover dead disks :(
        ddrescue
        # Hosted binary caches
        cachix
        # A TUI file explorer
        # xplr
        # lookatme
      ] ++ optionals pkgs.stdenv.isLinux [
        # Power consumption and management diagnosis tool.
        powertop
        # Top-like I/O monitor.
        iotop
      ];
    };

    shulker.modules = {
      shell.direnv.enable = true;
      shell.glow.enable = true;
      shell.zoxide.enable = true;
      shell.zsh.enable = true;
    };
  };
}
