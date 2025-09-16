{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.userSpecs;
in
{
  options.shulker.home.userSpecs = {
    name = mkOption {
      type = types.str;
      description = "Name of the currently configured user.";
    };
    email = mkOption {
      type = types.str;
      description = "Email adress of the currently configured user.";
    };
  };
}
