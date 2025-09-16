{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.dev.rust;
in
{
  options.shulker.home.modules.dev.rust = {
    enable = mkEnableOption "rust configuration";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [ rustup ];

      sessionVariables = {
        RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
        CARGO_HOME = "${config.xdg.dataHome}/cargo";
      };

      sessionPath = [ "$CARGO_HOME/bin" ];
    };
  };
}
