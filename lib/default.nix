# Helpers shared through lib.custom in system and Home Manager modules.
{ lib, ... }:
{
  # Resolve assets independently of the importing module's directory depth.
  relativeToRoot = lib.path.append ../.;
  # Discover direct directories and Nix files in lexical order, excluding this entry point.
  scanPaths =
    path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          path: _type:
          (_type == "directory") || ((path != "default.nix") && (lib.strings.hasSuffix ".nix" path))
        ) (builtins.readDir path)
      )
    );
}
