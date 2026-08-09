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
  paperlessFastmailRoutesFilter = paperless.fastmailRoutesFilter;
  paperlessComposeService = services."paperless-compose";
  paperlessHealthService = services."paperless-health-check";
  paperlessLogicalBackupService = services."paperless-logical-backup";
  paperlessPullService = services."paperless-image-pull";
  paperlessSchemaService = services."paperless-schema-check";
  paperlessStateService = services."paperless-state";
  paperlessSystemPackageNames = map pkgs.lib.getName wardenConfig.environment.systemPackages;
  sshdService = services.sshd;
  sshdKeygenService = services."sshd-keygen";
  storageBoxKnownHosts = wardenConfig.programs.ssh.knownHosts;
  wardenServerDocs = self.packages.${system}."server-docs-warden";
  infrastructureData = self.packages.${system}.infrastructure-data;
  wikiDocs = self.packages.${system}.wiki-docs;
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
    assert paperless.trashDelayDays == 90;
    assert builtins.hasAttr "paperless-state" services;
    assert paperlessStateService.unitConfig.RequiresMountsFor == paperless.stateDir;
    assert pkgs.lib.hasInfix "validate_property acltype posix" paperless.validateStateScript;
    assert pkgs.lib.hasInfix "/consume/family" paperlessStateService.script;
    assert pkgs.lib.hasInfix "/consume/private" paperlessStateService.script;
    pkgs.runCommand "paperless-core-contract" { } ''
      touch "$out"
    '';

  paperless-stack-contract =
    assert paperlessPullService.serviceConfig.Type == "oneshot";
    assert paperlessPullService.serviceConfig.RemainAfterExit;
    assert paperlessPullService.serviceConfig.TimeoutStartSec == 7200;
    assert builtins.elem "COMPOSE_PARALLEL_LIMIT=1" (
      paperlessPullService.serviceConfig.Environment or [ ]
    );
    assert
      paperlessPullService.unitConfig.ConditionFileNotEmpty
      == paperlessComposeService.unitConfig.ConditionFileNotEmpty;
    assert
      builtins.match ".*--project-name paperless.* pull" paperlessPullService.serviceConfig.ExecStart
      != null;
    assert builtins.elem "paperless-image-pull.service" paperlessComposeService.requires;
    assert builtins.elem "paperless-image-pull.service" paperlessComposeService.after;
    assert paperlessComposeService.serviceConfig.TimeoutStartSec == 2160;
    assert
      builtins.match ".*--wait-timeout 2100" paperlessComposeService.serviceConfig.ExecStart != null;
    assert builtins.hasAttr "paperless-health-check" services;
    assert builtins.hasAttr "paperless-schema-check" services;
    assert paperlessHealthService.serviceConfig.Type == "oneshot";
    assert paperlessSchemaService.serviceConfig.Type == "oneshot";
    assert builtins.elem paperless.validateStatePackage paperless.healthCheckRuntimeInputs;
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
    assert (paperless.composeConfig.services.webserver.healthcheck.start_period or null) == "30m";
    assert
      paperless.composeConfig.services.webserver.environment.PAPERLESS_DISABLE_REGULAR_LOGIN == "true";
    assert
      paperless.composeConfig.services.webserver.environment.PAPERLESS_OCR_LANGUAGE
      == paperless.ocrLanguage;
    assert
      !(builtins.hasAttr "PAPERLESS_SEARCH_LANGUAGE" paperless.composeConfig.services.webserver.environment);
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
    assert builtins.elem "paperless-enable-user" paperlessSystemPackageNames;
    assert pkgs.lib.hasInfix "paperless_users" paperless.bootstrapContractText;
    assert pkgs.lib.hasInfix "paperless_family" paperless.bootstrapContractText;
    assert pkgs.lib.hasInfix "paperless_admins" paperless.bootstrapContractText;
    assert !(pkgs.lib.hasInfix "set_password(" paperless.bootstrapContractText);
    assert !(pkgs.lib.hasInfix "createsuperuser" paperless.bootstrapContractText);
    assert pkgs.lib.hasInfix "user.is_active = False" paperless.bootstrapContractText;
    assert pkgs.lib.hasInfix "Refusing to enable" paperless.bootstrapContractText;
    pkgs.runCommand "paperless-bootstrap-contract"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        normalize_routes() {
          jq --compact-output --exit-status ${pkgs.lib.escapeShellArg paperlessFastmailRoutesFilter} "$1"
        }

        valid_routes="$TMPDIR/valid-routes.json"
        printf '%s' '[{"name":"family","address":"family@example.invalid","owner":"owner","scope":"family"},{"name":"private-alice","address":"alice@example.invalid","owner":"alice","scope":"private"}]' > "$valid_routes"
        normalized="$(normalize_routes "$valid_routes")"
        test "$normalized" = '[{"name":"family","address":"family@example.invalid","owner":"owner","scope":"family"},{"name":"private-alice","address":"alice@example.invalid","owner":"alice","scope":"private"}]'

        invalid_scope="$TMPDIR/invalid-scope.json"
        printf '%s' '[{"name":"family","address":"family@example.invalid","owner":"owner","scope":"private"},{"name":"another","address":"other@example.invalid","owner":"owner","scope":"family"}]' > "$invalid_scope"
        if normalize_routes "$invalid_scope" >/dev/null 2>&1; then
          echo "Paperless accepted a family scope under the wrong managed rule name" >&2
          exit 1
        fi

        duplicate_address="$TMPDIR/duplicate-address.json"
        printf '%s' '[{"name":"family","address":"same@example.invalid","owner":"owner","scope":"family"},{"name":"private-owner","address":"same@example.invalid","owner":"owner","scope":"private"}]' > "$duplicate_address"
        if normalize_routes "$duplicate_address" >/dev/null 2>&1; then
          echo "Paperless accepted duplicate Fastmail intake addresses" >&2
          exit 1
        fi

        touch "$out"
      '';

  paperless-backup-contract =
    assert paperless.backUpData;
    assert builtins.elem "/storage/flash/paperless/.zfs/snapshot/borgmatic"
      wardenConfig.shulker.system.modules.backup.dirs;
    assert builtins.hasAttr "paperless-logical-backup" services;
    assert paperlessLogicalBackupService.serviceConfig.Type == "oneshot";
    assert pkgs.lib.hasInfix "pg_dump" paperless.logicalBackupScript;
    assert pkgs.lib.hasInfix "flash_pool/flash/storage/paperless@borgmatic"
      paperless.backupPrepareScript;
    assert pkgs.lib.hasInfix "PAPERLESS_BACKUP_TEST_FAIL_AFTER_SNAPSHOT" paperless.backupPrepareScript;
    assert pkgs.lib.hasInfix "flash_pool/flash/storage/paperless@borgmatic"
      paperless.backupCleanupScript;
    assert builtins.elem paperless.stateDir borgmaticService.unitConfig.RequiresMountsFor;
    assert pkgs.lib.hasInfix "paperless-backup-prepare" (
      builtins.toJSON wardenConfig.services.borgmatic.settings.commands
    );
    assert pkgs.lib.hasInfix "paperless-backup-cleanup" (
      builtins.toJSON wardenConfig.services.borgmatic.settings.commands
    );
    pkgs.runCommand "paperless-backup-contract" { } ''
      touch "$out"
    '';

  paperless-docs-contract = pkgs.runCommand "paperless-docs-contract" { } ''
    combined="$TMPDIR/paperless-generated-docs"
    readme=${./README.md}
    paperless_readme="$TMPDIR/paperless-readme"
    paperless_readme_text="$TMPDIR/paperless-readme-text"
    paperless_service_row="$TMPDIR/paperless-service-row"
    paperless_operations="$TMPDIR/paperless-operations"
    paperless_operations_text="$TMPDIR/paperless-operations-text"
    mkdir -p "$combined"
    cp -R ${wardenServerDocs}/. "$combined/warden"
    cp -R ${infrastructureData}/. "$combined/infrastructure"
    cp -R ${wikiDocs}/. "$combined/wiki"

    warden_report="$combined/warden/warden.md"
    test -f "$warden_report"

    awk '
      $0 == "## Paperless family documents" { in_section = 1 }
      $0 == "## Development and validation" { in_section = 0 }
      in_section { print }
    ' "$readme" > "$paperless_readme"
    test -s "$paperless_readme"
    tr '\n' ' ' < "$paperless_readme" > "$paperless_readme_text"

    grep -F -- '| Paperless-ngx |' "$warden_report" > "$paperless_service_row"
    test "$(wc -l < "$paperless_service_row")" -eq 1

    awk '
      $0 == "Inspect Paperless and run its declarative checks:" { in_section = 1 }
      $0 == "Roll back the active system profile:" { in_section = 0 }
      in_section { print }
    ' "$warden_report" > "$paperless_operations"
    test -s "$paperless_operations"
    tr '\n' ' ' < "$paperless_operations" > "$paperless_operations_text"

    for expected in \
      'Paperless-ngx' \
      'https://documents.shulker.link' \
      'flash_pool/flash/storage/paperless' \
      '500 GiB' \
      'fra+eng+deu' \
      'paperless-health-check' \
      'paperless-pre-upgrade-export'
    do
      grep -R -F -- "$expected" "$combined" >/dev/null
    done

    for expected_policy in \
      'exactly one password-capable native break-glass administrator' \
      'Pangolin-authenticated /admin' \
      'administrator-only public /share'
    do
      if ! grep -F -- "$expected_policy" "$paperless_readme_text" >/dev/null; then
        echo "README is missing Paperless access policy: $expected_policy" >&2
        exit 1
      fi
      if ! grep -F -- "$expected_policy" "$paperless_service_row" >/dev/null; then
        echo "Generated Warden service summary is missing Paperless access policy: $expected_policy" >&2
        exit 1
      fi
      if ! grep -F -- "$expected_policy" "$paperless_operations_text" >/dev/null; then
        echo "Generated Warden operations are missing Paperless access policy: $expected_policy" >&2
        exit 1
      fi
    done

    for obsolete_policy in \
      'Pocket ID-only login' \
      'public share links disabled' \
      'public share links remain intentionally disabled' \
      'Pangolin path denials'
    do
      if grep -F -- "$obsolete_policy" \
        "$paperless_readme_text" "$paperless_service_row" \
        "$paperless_operations_text" >/dev/null
      then
        echo "Paperless documentation contains obsolete access policy: $obsolete_policy" >&2
        exit 1
      fi
    done

    if grep -R -E \
      'PAPERLESS_(DB_PASSWORD|OIDC_CLIENT_SECRET|FASTMAIL_APP_PASSWORD|SECRET_KEY)=|op://Shulker/warden/Paperless|[[:alnum:]._%+-]+@fastmail\.' \
      "$combined" >/dev/null
    then
      echo "Generated Paperless documentation contains private configuration" >&2
      exit 1
    fi

    touch "$out"
  '';

  paperless-release-workflow-contract = pkgs.runCommand "paperless-release-workflow-contract" { } ''
    workflow=${./.}/.github/workflows/check-paperless-release.yml

    test -f "$workflow"
    for expected in \
      'schedule:' \
      'workflow_dispatch:' \
      'contents: read' \
      'issues: write' \
      'paperless-release-monitor' \
      'nix eval --raw .#nixosConfigurations.warden.config.shulker.system.modules.paperless.version' \
      'gh api repos/paperless-ngx/paperless-ngx/releases/latest --jq .tag_name' \
      'chore: review Paperless-ngx update' \
      '<!-- paperless-release-monitor -->'
    do
      grep -F -- "$expected" "$workflow" >/dev/null
    done

    for forbidden in \
      'contents: write' \
      'pull-requests: write' \
      'git commit' \
      'git push' \
      'nixos-rebuild'
    do
      if grep -F -- "$forbidden" "$workflow" >/dev/null; then
        echo "Paperless release monitor contains forbidden mutation: $forbidden" >&2
        exit 1
      fi
    done

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
