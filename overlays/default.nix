# Package overrides applied to every host's shared nixpkgs instance.
{ ... }:
{
  default = final: prev: {
    # Use the packaged Electron bundle and disable signing for sandboxed macOS builds.
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
}
