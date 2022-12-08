{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.profiles.development;
in
{
  options.shulker.profiles.development.enable =
    mkEnableOption "development configuration";

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      # Generation of executables
      gnumake
      # Benchmarking.
      hyperfine
      # Just a command runner
      just
      # Shell script analysis tool
      shellcheck
      # Codebase statistics.
      tokei
    ];

    # shulker.modules = {
    #   dev.cc.enable = true;
    #   dev.dhall.enable = true;
    #   dev.go.enable = true;
    #   dev.lua.enable = true;
    #   dev.nix.enable = true;
    #   dev.node.enable = true;
    #   dev.python.enable = true;
    #   dev.rust.enable = true;
    #   shell.direnv.enable = true;
    #   shell.lorri.enable = true;
    # };
  };
}
