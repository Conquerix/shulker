{
  pkgs,
  wardenConfig,
  services,
  ...
}:

let
  borgmaticService = services.borgmatic;
  seafile = wardenConfig.shulker.system.modules.seafile;
  seafileHealthService = services."seafile-health-check";
  seafileExtendedHealthService = services."seafile-extended-health";
  seafileMaintenancePackageNames = [
    "seafile-health-check"
    "seafile-extended-health"
    "seafile-metadata-probe"
    "seafile-notification-public-check"
    "seafile-onlyoffice-smoke-test"
    "seafile-enable-public-health"
    "seafile-fsck-shallow"
    "seafile-fsck-full"
    "seafile-gc-dry-run"
    "seafile-search-status"
    "seafile-search-update"
    "seafile-search-rebuild"
  ];
  systemPackageNames = map pkgs.lib.getName wardenConfig.environment.systemPackages;
  seafileMaintenancePackages = builtins.filter (
    package: builtins.elem (pkgs.lib.getName package) seafileMaintenancePackageNames
  ) wardenConfig.environment.systemPackages;
in
{
  seafile-maintenance-contract =
    let
      contract = seafile.maintenanceContractText;
      contractFile = pkgs.writeText "seafile-maintenance-contract.txt" (
        builtins.unsafeDiscardStringContext contract
      );
      health = pkgs.writeShellApplication {
        name = "seafile-health-check-under-test";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.util-linux
        ];
        text = builtins.unsafeDiscardStringContext seafile.healthCheckScript;
      };
      extended = pkgs.writeShellApplication {
        name = "seafile-extended-health-under-test";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.jq
          pkgs.util-linux
        ];
        text = builtins.unsafeDiscardStringContext seafile.extendedHealthScript;
      };
      metadata = pkgs.writeShellApplication {
        name = "seafile-metadata-probe-under-test";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = builtins.unsafeDiscardStringContext seafile.metadataProbeScript;
      };
      enablePublic = pkgs.writeShellApplication {
        name = "seafile-enable-public-health-under-test";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.unsafeDiscardStringContext seafile.enablePublicHealthScript;
      };
      search = pkgs.writeShellApplication {
        name = "seafile-search-status-under-test";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = builtins.unsafeDiscardStringContext seafile.searchStatusScript;
      };
      onlyOfficeDriver = pkgs.writeText "seafile-onlyoffice-driver-under-test.py" (
        builtins.unsafeDiscardStringContext seafile.onlyOfficeProbePython
      );
      onlyOffice = pkgs.writeShellApplication {
        name = "seafile-onlyoffice-smoke-test-under-test";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = builtins.unsafeDiscardStringContext seafile.onlyOfficeSmokeTestScript;
      };
      maintenanceServiceNames = [
        "seafile-extended-health"
        "seafile-fsck-full"
        "seafile-fsck-shallow"
        "seafile-gc-dry-run"
        "seafile-health-check"
        "seafile-metadata-probe"
        "seafile-notification-public-check"
        "seafile-onlyoffice-smoke-test"
        "seafile-search-rebuild"
        "seafile-search-status"
        "seafile-search-update"
      ];
      maintenanceTimerNames = [
        "seafile-extended-health"
        "seafile-fsck-full"
        "seafile-fsck-shallow"
        "seafile-gc-dry-run"
        "seafile-health-check"
      ];
    in
    assert pkgs.lib.all (name: builtins.elem name systemPackageNames) seafileMaintenancePackageNames;
    assert builtins.length seafileMaintenancePackages == builtins.length seafileMaintenancePackageNames;
    assert pkgs.lib.all (name: builtins.hasAttr name services) maintenanceServiceNames;
    assert pkgs.lib.all (name: builtins.hasAttr name wardenConfig.systemd.timers) maintenanceTimerNames;
    assert seafileHealthService.serviceConfig.Type == "oneshot";
    assert seafileHealthService.unitConfig.RequiresMountsFor == seafile.stateDir;
    assert builtins.elem "seafile-compose.service" seafileHealthService.after;
    assert seafileExtendedHealthService.unitConfig.RequiresMountsFor == seafile.stateDir;
    assert builtins.elem "seafile-compose.service" seafileExtendedHealthService.after;
    assert wardenConfig.systemd.timers.seafile-health-check.timerConfig.OnUnitActiveSec == "15m";
    assert wardenConfig.systemd.timers.seafile-health-check.timerConfig.Persistent;
    assert wardenConfig.systemd.timers.seafile-extended-health.timerConfig.OnCalendar == "daily";
    assert wardenConfig.systemd.timers.seafile-fsck-shallow.timerConfig.OnCalendar == "weekly";
    assert wardenConfig.systemd.timers.seafile-fsck-full.timerConfig.OnCalendar == "monthly";
    assert wardenConfig.systemd.timers.seafile-gc-dry-run.timerConfig.OnCalendar == "weekly";
    assert pkgs.lib.hasInfix "/run/lock/seafile-maintenance.lock" contract;
    assert pkgs.lib.hasInfix "-w 1800" contract;
    assert pkgs.lib.hasInfix "seaf-fsck.sh --shallow" contract;
    assert pkgs.lib.hasInfix "seaf-fsck.sh" contract;
    assert !(pkgs.lib.hasInfix "seaf-fsck.sh --repair" contract);
    assert pkgs.lib.hasInfix "seaf-gc.sh --dry-run" contract;
    assert !(pkgs.lib.hasInfix "metadata consistency" (pkgs.lib.toLower contract));
    assert !(pkgs.lib.hasInfix "/storage/flash/immich" contract);
    assert !(pkgs.lib.hasInfix "INIT_SEAFILE_ADMIN_PASSWORD=" contract);
    assert !(pkgs.lib.hasInfix "INIT_SS_ADMIN_PASSWORD=" contract);
    assert !(pkgs.lib.hasInfix "$INIT_SS_ADMIN_USER" contract);
    assert !(pkgs.lib.hasInfix "$INIT_SS_ADMIN_PASSWORD" contract);
    assert pkgs.lib.hasInfix "load_search_token" contract;
    assert pkgs.lib.hasInfix "http://seafile-seasearch:4080/api/permissions" contract;
    assert !(pkgs.lib.hasInfix "seafile-seasearch curl --config" contract);
    pkgs.runCommand "seafile-maintenance-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.python3
          pkgs.util-linux
        ];
      }
      ''
        ${pkgs.bash}/bin/bash ${../tests/seafile-maintenance.sh} \
          ${health}/bin/seafile-health-check-under-test \
          ${extended}/bin/seafile-extended-health-under-test \
          ${metadata}/bin/seafile-metadata-probe-under-test \
          ${enablePublic}/bin/seafile-enable-public-health-under-test \
          ${search}/bin/seafile-search-status-under-test \
          ${contractFile} \
          ${onlyOfficeDriver} \
          ${onlyOffice}/bin/seafile-onlyoffice-smoke-test-under-test
        touch "$out"
      '';

  seafile-backup-state-machine-contract =
    let
      restoreIdentify = pkgs.writeText "seafile-restore-identify-native-admin.py" seafile.restoreIdentifyNativeAdminScript;
      restoreReset = pkgs.writeText "seafile-restore-reset-native-admin.py" seafile.restoreResetNativeAdminScript;
      restoreVerifyIdentity = pkgs.writeText "seafile-restore-verify-native-admin.py" seafile.restoreVerifyNativeAdminScript;
      restoreVerifyText =
        builtins.replaceStrings
          [
            (toString seafile.restoreIdentifyNativeAdminFile)
            (toString seafile.restoreResetNativeAdminFile)
            (toString seafile.restoreVerifyNativeAdminFile)
          ]
          [
            (toString restoreIdentify)
            (toString restoreReset)
            (toString restoreVerifyIdentity)
          ]
          seafile.restoreVerifyScript;
      mkBackupHelper =
        name: text: inputs:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.openssl
            pkgs.procps
            pkgs.util-linux
          ]
          ++ inputs;
          text = builtins.unsafeDiscardStringContext text;
        };
      logical = mkBackupHelper "seafile-logical-backup-under-test" seafile.logicalBackupScript [ ];
      validate =
        mkBackupHelper "seafile-validate-logical-backup-under-test" seafile.validateLogicalBackupScript
          [ ];
      prepare = mkBackupHelper "seafile-backup-prepare-under-test" seafile.backupPrepareScript [ ];
      cleanup = mkBackupHelper "seafile-backup-cleanup-under-test" seafile.backupCleanupScript [ ];
      restorePrepare =
        mkBackupHelper "seafile-restore-prepare-under-test" seafile.restorePrepareScript
          [ ];
      restoreVerify = mkBackupHelper "seafile-restore-verify-under-test" restoreVerifyText [
        pkgs.gawk
        restoreIdentify
        restoreReset
        restoreVerifyIdentity
      ];
      restoreTeardown =
        mkBackupHelper "seafile-restore-teardown-under-test" seafile.restoreTeardownScript
          [ ];
    in
    pkgs.runCommand "seafile-backup-state-machine-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.jq
        ];
      }
      ''
        ${pkgs.bash}/bin/bash ${../tests/seafile-backup-state-machine.sh} \
          ${logical}/bin/seafile-logical-backup-under-test \
          ${validate}/bin/seafile-validate-logical-backup-under-test \
          ${prepare}/bin/seafile-backup-prepare-under-test \
          ${cleanup}/bin/seafile-backup-cleanup-under-test \
          ${restorePrepare}/bin/seafile-restore-prepare-under-test \
          ${restoreVerify}/bin/seafile-restore-verify-under-test \
          ${restoreTeardown}/bin/seafile-restore-teardown-under-test
        touch "$out"
      '';

  seafile-backup-contract =
    let
      contract = seafile.backupContractText;
      borgmatic = wardenConfig.services.borgmatic.settings;
      commands = builtins.toJSON borgmatic.commands;
      restoreInvocationLabel = "\${SEAFILE_RESTORE_INVOCATION:?SEAFILE_RESTORE_INVOCATION is required}";
      backupPackageNames = [
        "seafile-backup-cleanup"
        "seafile-backup-prepare"
        "seafile-backup-status"
        "seafile-logical-backup"
        "seafile-pre-upgrade-check"
        "seafile-restore-prepare"
        "seafile-restore-teardown"
        "seafile-restore-verify"
        "seafile-validate-logical-backup"
      ];
    in
    assert pkgs.lib.all (name: builtins.elem name systemPackageNames) backupPackageNames;
    assert builtins.elem "/storage/flash/seafile/.zfs/snapshot/borgmatic/shared"
      wardenConfig.shulker.system.modules.backup.dirs;
    assert builtins.elem "/storage/flash/seafile/.zfs/snapshot/borgmatic/backups"
      wardenConfig.shulker.system.modules.backup.dirs;
    assert builtins.elem seafile.stateDir borgmaticService.unitConfig.RequiresMountsFor;
    assert pkgs.lib.hasInfix "seafile-backup-prepare" commands;
    assert pkgs.lib.hasInfix "seafile-backup-cleanup" commands;
    assert pkgs.lib.hasInfix "finish" commands;
    assert pkgs.lib.hasInfix "fail" commands;
    assert pkgs.lib.hasInfix "error" commands;
    assert builtins.elem "/storage/flash/seafile/.zfs/snapshot/borgmatic/shared/logs"
      borgmatic.exclude_patterns;
    assert builtins.elem "/storage/flash/seafile/.zfs/snapshot/borgmatic/shared/seafile/logs"
      borgmatic.exclude_patterns;
    assert !(borgmatic.follow_symlinks or false);
    assert !(borgmatic.read_special or false);
    assert seafile.restoreComposeConfig.name == "seafile-restore";
    assert seafile.restoreComposeConfig.services.seafile.ports == [ ];
    assert seafile.restoreComposeConfig.services.onlyoffice.ports == [ ];
    assert seafile.restoreComposeConfig.services.notification.ports == [ ];
    assert pkgs.lib.all (
      service: service.labels."shulker.seafile.restore-invocation" == restoreInvocationLabel
    ) (builtins.attrValues seafile.restoreComposeConfig.services);
    assert
      seafile.restoreComposeConfig.services.proxy.ports == [
        "127.0.0.1:24239:443/tcp"
        "127.0.0.1:24240:444/tcp"
        "127.0.0.1:24241:445/tcp"
      ];
    assert pkgs.lib.hasInfix "ccnet_db.sql" contract;
    assert pkgs.lib.hasInfix "seafile_db.sql" contract;
    assert pkgs.lib.hasInfix "seahub_db.sql" contract;
    assert pkgs.lib.hasInfix "writers_quiesced=true" contract;
    assert pkgs.lib.hasInfix "documentserver-prepare4shutdown.sh" contract;
    assert pkgs.lib.hasInfix "330" contract;
    assert pkgs.lib.hasInfix "backup-snapshot-owner" contract;
    assert pkgs.lib.hasInfix "cleanup-armed" contract;
    assert pkgs.lib.hasInfix "guid" (pkgs.lib.toLower contract);
    assert pkgs.lib.hasInfix "/run/lock/seafile-maintenance.lock" contract;
    assert pkgs.lib.hasInfix "--execute 'SELECT 1'" contract;
    assert pkgs.lib.hasInfix "--kill-after=1 \"$validator_probe_timeout\"" contract;
    assert pkgs.lib.hasInfix "validator database authentication did not become ready" contract;
    assert !(pkgs.lib.hasInfix "mariadb-admin --user root ping" contract);
    assert pkgs.lib.hasInfix "--network=none --pull=never --read-only" contract;
    assert pkgs.lib.hasInfix "--security-opt=no-new-privileges=true --pids-limit=16" contract;
    assert pkgs.lib.hasInfix "--user 0:0 --cap-drop=ALL --cap-add=DAC_OVERRIDE" contract;
    assert pkgs.lib.hasInfix "type=bind,source=$workspace,target=/cleanup" contract;
    assert pkgs.lib.hasInfix "--entrypoint /usr/bin/find" contract;
    assert
      !(builtins.elem "CAP_DAC_OVERRIDE" (borgmaticService.serviceConfig.CapabilityBoundingSet or [ ]));
    assert !(builtins.elem "CAP_CHOWN" (borgmaticService.serviceConfig.CapabilityBoundingSet or [ ]));
    assert !(builtins.elem "CAP_FOWNER" (borgmaticService.serviceConfig.CapabilityBoundingSet or [ ]));
    assert pkgs.lib.hasInfix "seafile-restore-net" contract;
    assert pkgs.lib.hasInfix "https://files.restore.invalid:24239" contract;
    assert pkgs.lib.hasInfix "https://office.restore.invalid:24240" contract;
    assert pkgs.lib.hasInfix "--backup-set" contract;
    assert pkgs.lib.hasInfix "--no-recreate" contract;
    assert pkgs.lib.hasInfix "--container-project" contract;
    assert pkgs.lib.hasInfix "SEAFILE_RESTORE_NATIVE_MODE=reset" contract;
    assert !(pkgs.lib.hasInfix "reset-admin.sh" contract);
    assert pkgs.lib.hasInfix "backup manifest or release matrix is incompatible" contract;
    assert !(pkgs.lib.hasInfix "--ignore-certificate-errors" contract);
    assert !(pkgs.lib.hasInfix "/storage/flash/immich" contract);
    assert !(pkgs.lib.hasInfix "INIT_SEAFILE_ADMIN_PASSWORD=" contract);
    pkgs.runCommand "seafile-backup-contract" { } ''
      touch "$out"
    '';
}
