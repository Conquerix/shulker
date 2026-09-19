# Collect named flake checks around the evaluated Warden configuration.
{
  inputs,
  self,
  system,
  ...
}:

let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  wardenConfig = self.nixosConfigurations.warden.config;
  context = {
    inherit
      inputs
      self
      system
      pkgs
      wardenConfig
      ;
    services = wardenConfig.systemd.services;
  };
  documentation = import ./checks/documentation.nix context;
  # Keep groups independent; the merge below rejects duplicate public check names.
  groups = [
    documentation.checks
    (import ./checks/host.nix context)
    (import ./checks/seafile-runtime.nix context)
    (import ./checks/seafile-operations.nix context)
    (import ./checks/seafile-docs.nix context)
    (import ./checks/paperless.nix context)
    (import ./checks/suites.nix context)
    (import ./checks/pre-commit.nix context)
  ];
in
assert documentation.validation;
builtins.foldl' (
  checks: group:
  assert pkgs.lib.assertMsg (
    builtins.intersectAttrs checks group == { }
  ) "Duplicate flake check names across checks/ modules";
  checks // group
) { } groups
