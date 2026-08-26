{ lib, ... }:

let
  servicesPath = ./services;
  rootModules = builtins.filter (path: path != servicesPath) (lib.custom.scanPaths ./.);
  serviceModules = (import servicesPath { inherit lib; }).imports;
  moduleName = path: lib.removeSuffix ".nix" (builtins.baseNameOf path);
in
{
  # Flatten the discovered service imports so moving a module does not change
  # traversal depth or the merge order of list-valued options.
  imports = builtins.sort (left: right: moduleName left < moduleName right) (
    rootModules ++ serviceModules
  );
}
