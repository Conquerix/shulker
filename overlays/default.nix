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
    vesktop = prev.vesktop.overrideAttrs (old: {
      buildPhase = ''
        runHook preBuild

        pnpm build
        pnpm exec electron-builder \
          --dir \
          -c.asarUnpack="**/*.node" \
          -c.electronDist=${if prev.stdenv.hostPlatform.isDarwin then "." else "electron-dist"} \
          -c.electronVersion=${prev.electron.version} \
          ${if prev.stdenv.hostPlatform.isDarwin then "-c.mac.identity=null" else ""}

        runHook postBuild
      '';
    });
  };

in
{
  default =
    final: prev:

    (additions final prev) // (modifications final prev) // (linuxModifications final prev);
}
