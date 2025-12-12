#
# This file defines overlays/custom modifications to upstream packages
#

{ ... }:

let
  # Adds my custom packages
  # FIXME: Add per-system packages
  additions =
    final: prev:
    (prev.lib.packagesFromDirectoryRecursive {
      callPackage = prev.lib.callPackageWith final;
      directory = ../pkgs;
    });

  linuxModifications = final: prev: prev.lib.mkIf final.stdenv.isLinux { };

  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: let ... in {
    # ...
    # });
    #    flameshot = prev.flameshot.overrideAttrs {
    #      cmakeFlags = [
    #        (prev.lib.cmakeBool "USE_WAYLAND_GRIM" true)
    #        (prev.lib.cmakeBool "USE_WAYLAND_CLIPBOARD" true)
    #      ];
    #    };
  };

in
{
  default =
    final: prev:

    (additions final prev) // (modifications final prev) // (linuxModifications final prev);
}
