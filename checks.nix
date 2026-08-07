{
  inputs,
  self,
  system,
  ...
}:

let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  wardenConfig = self.nixosConfigurations.warden.config;
  services = wardenConfig.systemd.services;
  pullService = services."immich-image-pull";
  composeService = services."immich-compose";
  storageBoxKnownHosts = wardenConfig.programs.ssh.knownHosts;
in
{

  backup-ssh-host-key-contract =
    assert builtins.hasAttr "hetzner-storage-box" storageBoxKnownHosts;
    assert builtins.elem "[u515568-sub4.your-storagebox.de]:23"
      storageBoxKnownHosts.hetzner-storage-box.hostNames;
    assert
      storageBoxKnownHosts.hetzner-storage-box.publicKey
      == "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
    pkgs.runCommand "backup-ssh-host-key-contract" { } ''
      touch "$out"
    '';

  immich-service-contract =
    assert builtins.hasAttr "immich-image-pull" services;
    assert !wardenConfig.shulker.system.modules.immich.allowSetup;
    assert pullService.serviceConfig.Type == "oneshot";
    assert pullService.serviceConfig.RemainAfterExit;
    assert pullService.serviceConfig.TimeoutStartSec == 1800;
    assert
      pullService.unitConfig.ConditionFileNotEmpty == composeService.unitConfig.ConditionFileNotEmpty;
    assert builtins.match ".*--project-name immich.* pull" pullService.serviceConfig.ExecStart != null;
    assert builtins.elem "immich-image-pull.service" composeService.requires;
    assert builtins.elem "immich-image-pull.service" composeService.after;
    assert composeService.serviceConfig.TimeoutStartSec == 360;
    assert builtins.match ".*--wait-timeout 300" composeService.serviceConfig.ExecStart != null;
    pkgs.runCommand "immich-service-contract" { } ''
      touch "$out"
    '';

  pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
    src = ./.;
    default_stages = [ "pre-commit" ];
    hooks = {
      # ========== General ==========
      check-added-large-files.enable = true;
      check-case-conflicts.enable = true;
      check-executables-have-shebangs.enable = true;
      check-shebang-scripts-are-executable.enable = false; # many of the scripts in the config aren't executable because they don't need to be.
      check-merge-conflicts.enable = true;
      detect-private-keys.enable = true;
      fix-byte-order-marker.enable = true;
      mixed-line-endings.enable = true;
      trim-trailing-whitespace.enable = true;
      forbid-submodules = {
        enable = true;
        name = "forbid submodules";
        description = "forbids any submodules in the repository";
        language = "fail";
        entry = "submodules are not allowed in this repository:";
        types = [ "directory" ];
      };
      destroyed-symlinks = {
        enable = true;
        name = "destroyed-symlinks";
        description = "detects symlinks which are changed to regular files with a content of a path which that symlink was pointing to.";
        package = inputs.pre-commit-hooks.checks.${system}.pre-commit-hooks;
        entry = "${inputs.pre-commit-hooks.checks.${system}.pre-commit-hooks}/bin/destroyed-symlinks";
        types = [ "symlink" ];
      };
      # ========== nix ==========
      nixfmt.enable = true;
      deadnix = {
        enable = true;
        settings = {
          noLambdaArg = true;
        };
      };
      # ========== shellscripts ==========
      shfmt.enable = true;
      shellcheck.enable = true;
      end-of-file-fixer.enable = true;
    };
  };
}
