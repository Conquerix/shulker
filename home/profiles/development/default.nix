{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.profiles.development;
in
{
  options.shulker.home.profiles.development.enable = mkEnableOption "development configuration";

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
  };
}
