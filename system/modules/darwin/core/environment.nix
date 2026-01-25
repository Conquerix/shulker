{
  lib,
  ...
}:

with lib;
{
  config = {
    system.stateVersion = 6;
    nixpkgs.hostPlatform = "aarch64-darwin";
    shulker.global.type = "darwin";
    system.defaults.CustomSystemPreferences = {
      "com.apple.systempreferences" = {
        AttentionPrefBundleIDs = false;
      };
    };
  };
}
