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
  borgmaticService = services.borgmatic;
  pullService = services."immich-image-pull";
  composeService = services."immich-compose";
  paperless = wardenConfig.shulker.system.modules.paperless;
  paperlessComposeService = services."paperless-compose";
  paperlessHealthService = services."paperless-health-check";
  paperlessPullService = services."paperless-image-pull";
  paperlessSchemaService = services."paperless-schema-check";
  paperlessStateService = services."paperless-state";
  paperlessSystemPackageNames = map pkgs.lib.getName wardenConfig.environment.systemPackages;
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

  paperless-core-contract =
    assert paperless.enable;
    assert paperless.version == "3.0.5";
    assert paperless.stateDir == "/storage/flash/paperless";
    assert paperless.dataset == "flash_pool/flash/storage/paperless";
    assert paperless.datasetQuotaBytes == 536870912000;
    assert paperless.bindAddress == "127.0.0.1";
    assert paperless.port == 23238;
    assert paperless.publicUrl == "https://documents.shulker.link";
    assert paperless.oidcIssuer == "https://sso.shulker.link";
    assert paperless.ocrLanguage == "fra+eng+deu";
    assert paperless.searchLanguage == "fr";
    assert paperless.trashDelayDays == 90;
    assert builtins.hasAttr "paperless-state" services;
    assert paperlessStateService.unitConfig.RequiresMountsFor == paperless.stateDir;
    pkgs.runCommand "paperless-core-contract" { } ''
      touch "$out"
    '';

  paperless-stack-contract =
    assert paperlessPullService.serviceConfig.Type == "oneshot";
    assert paperlessPullService.serviceConfig.RemainAfterExit;
    assert paperlessPullService.serviceConfig.TimeoutStartSec == 1800;
    assert
      paperlessPullService.unitConfig.ConditionFileNotEmpty
      == paperlessComposeService.unitConfig.ConditionFileNotEmpty;
    assert
      builtins.match ".*--project-name paperless.* pull" paperlessPullService.serviceConfig.ExecStart
      != null;
    assert builtins.elem "paperless-image-pull.service" paperlessComposeService.requires;
    assert builtins.elem "paperless-image-pull.service" paperlessComposeService.after;
    assert paperlessComposeService.serviceConfig.TimeoutStartSec == 360;
    assert
      builtins.match ".*--wait-timeout 300" paperlessComposeService.serviceConfig.ExecStart != null;
    assert builtins.hasAttr "paperless-health-check" services;
    assert builtins.hasAttr "paperless-schema-check" services;
    assert paperlessHealthService.serviceConfig.Type == "oneshot";
    assert paperlessSchemaService.serviceConfig.Type == "oneshot";
    assert pkgs.lib.all (image: pkgs.lib.hasInfix "@sha256:" image) [
      paperless.paperlessImage
      paperless.valkeyImage
      paperless.databaseImage
      paperless.gotenbergImage
      paperless.tikaImage
    ];
    assert paperless.composeConfig.name == "paperless";
    assert
      builtins.attrNames paperless.composeConfig.services == [
        "broker"
        "database"
        "gotenberg"
        "tika"
        "webserver"
      ];
    assert paperless.composeConfig.services.webserver.ports == [ "127.0.0.1:23238:8000/tcp" ];
    assert
      paperless.composeConfig.services.webserver.environment.PAPERLESS_DISABLE_REGULAR_LOGIN == "true";
    assert paperless.composeConfig.services.webserver.environment.PAPERLESS_SEARCH_LANGUAGE == "fr";
    assert paperless.composeConfig.services.webserver.environment.PAPERLESS_EMPTY_TRASH_DELAY == "90";
    pkgs.runCommand "paperless-stack-contract" { } ''
      touch "$out"
    '';

  paperless-bootstrap-contract =
    assert builtins.elem "paperless-bootstrap-groups" paperlessSystemPackageNames;
    assert builtins.elem "paperless-promote-oidc-admin" paperlessSystemPackageNames;
    assert builtins.elem "paperless-revoke-admin" paperlessSystemPackageNames;
    assert builtins.elem "paperless-bootstrap-fastmail" paperlessSystemPackageNames;
    assert builtins.elem "paperless-list-users" paperlessSystemPackageNames;
    assert pkgs.lib.hasInfix "paperless_users" paperless.bootstrapContractText;
    assert pkgs.lib.hasInfix "paperless_family" paperless.bootstrapContractText;
    assert pkgs.lib.hasInfix "paperless_admins" paperless.bootstrapContractText;
    assert !(pkgs.lib.hasInfix "set_password(" paperless.bootstrapContractText);
    assert !(pkgs.lib.hasInfix "createsuperuser" paperless.bootstrapContractText);
    pkgs.runCommand "paperless-bootstrap-contract" { } ''
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
