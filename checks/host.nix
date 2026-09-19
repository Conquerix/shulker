# Guard host-level backup, SSH recovery, and service startup contracts.
{
  inputs,
  system,
  pkgs,
  wardenConfig,
  services,
  ...
}:

let
  borgmaticService = services.borgmatic;
  borgmaticSourceDirectories = wardenConfig.shulker.system.modules.backup.dirs;
  pullService = services."immich-image-pull";
  composeService = services."immich-compose";
  checkedRebuild = import ../nix/checked-rebuild.nix {
    inherit pkgs;
    opnix = inputs.opnix.packages.${system}.default;
  };
  sshdService = services.sshd;
  sshdKeygenService = services."sshd-keygen";
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

  backup-zfs-device-contract =
    assert borgmaticService.serviceConfig.PrivateDevices;
    assert borgmaticService.serviceConfig.DevicePolicy == "closed";
    assert builtins.elem "/dev/zfs rw" borgmaticService.serviceConfig.DeviceAllow;
    assert builtins.elem "/dev/zfs" borgmaticService.serviceConfig.BindPaths;
    assert builtins.elem "CAP_SYS_ADMIN" (borgmaticService.serviceConfig.CapabilityBoundingSet or [ ]);
    pkgs.runCommand "backup-zfs-device-contract" { } ''
      touch "$out"
    '';

  backup-source-order-contract =
    assert borgmaticSourceDirectories == builtins.sort builtins.lessThan borgmaticSourceDirectories;
    assert wardenConfig.services.borgmatic.settings.source_directories == borgmaticSourceDirectories;
    pkgs.runCommand "backup-source-order-contract" { } ''
      touch "$out"
    '';

  ssh-host-public-key-contract =
    assert builtins.elem "opnix-secrets.service" sshdKeygenService.after;
    assert pkgs.lib.hasInfix "ssh-keygen" sshdKeygenService.postStart;
    assert pkgs.lib.hasInfix "public_key.tmp" sshdKeygenService.postStart;
    assert pkgs.lib.hasInfix "ssh-keygen" sshdService.preStart;
    assert pkgs.lib.hasInfix "public_key.tmp" sshdService.preStart;
    pkgs.runCommand "ssh-host-public-key-contract" { } ''
      touch "$out"
    '';

  immich-service-contract =
    assert builtins.hasAttr "immich-image-pull" services;
    assert !wardenConfig.shulker.system.modules.immich.allowSetup;
    assert wardenConfig.shulker.system.modules.immich.transcodingAcceleration == "qsv";
    assert wardenConfig.shulker.system.modules.immich.preferredHardwareDevice == "/dev/dri/renderD128";
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

  checked-rebuild-secret-schema-contract =
    pkgs.runCommand "checked-rebuild-secret-schema-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
        ];
      }
      ''
        ${pkgs.bash}/bin/bash ${../tests/shulker-rebuild-secret-preflight.sh} ${checkedRebuild}/bin/shulker-rebuild
        touch "$out"
      '';
}
