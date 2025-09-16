{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.dev.lua;
in
{

  options.shulker.home.modules.dev.lua = {
    enable = mkEnableOption "lua configuration";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      lua52Packages.lua
      sumneko-lua-language-server
    ];
  };
}
