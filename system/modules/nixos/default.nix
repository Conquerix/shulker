{ lib, ... }:

let
  servicesPath = ./services;
  rootModules = builtins.filter (path: path != servicesPath) (lib.custom.scanPaths ./.);
  serviceModules = (import servicesPath { inherit lib; }).imports;
  moduleName = path: lib.removeSuffix ".nix" (builtins.baseNameOf path);
in
{
  # Scan root and service modules separately, then flatten them into one sorted
  # list. A nested services import would change traversal depth and list merges.
  imports = builtins.sort (left: right: moduleName left < moduleName right) (
    rootModules ++ serviceModules
  );
}
