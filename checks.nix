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
  checkedRebuild = import ./nix/checked-rebuild.nix {
    inherit pkgs;
    opnix = inputs.opnix.packages.${system}.default;
  };
  seafile = wardenConfig.shulker.system.modules.seafile;
  seafileConfigService = services."seafile-config";
  seafileComposeService = services."seafile-compose";
  seafilePullService = services."seafile-image-pull";
  seafileStateService = services."seafile-state";
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
  paperless = wardenConfig.shulker.system.modules.paperless;
  paperlessFastmailRoutesFilter = paperless.fastmailRoutesFilter;
  paperlessComposeService = services."paperless-compose";
  paperlessHealthService = services."paperless-health-check";
  paperlessLogicalBackupService = services."paperless-logical-backup";
  paperlessPullService = services."paperless-image-pull";
  paperlessSchemaService = services."paperless-schema-check";
  paperlessStateService = services."paperless-state";
  systemPackageNames = map pkgs.lib.getName wardenConfig.environment.systemPackages;
  seafileBootstrapPackageNames = [
    "seafile-list-users"
    "seafile-license-status"
    "seafile-promote-oauth-admin"
    "seafile-revoke-oauth-admin"
    "seafile-reset-native-admin"
    "seafile-bootstrap-status"
  ];
  seafileBootstrapPackages = builtins.filter (
    package: builtins.elem (pkgs.lib.getName package) seafileBootstrapPackageNames
  ) wardenConfig.environment.systemPackages;
  seafileMaintenancePackages = builtins.filter (
    package: builtins.elem (pkgs.lib.getName package) seafileMaintenancePackageNames
  ) wardenConfig.environment.systemPackages;
  sshdService = services.sshd;
  sshdKeygenService = services."sshd-keygen";
  storageBoxKnownHosts = wardenConfig.programs.ssh.knownHosts;
  wardenServerDocs = self.packages.${system}."server-docs-warden";
  infrastructureData = self.packages.${system}.infrastructure-data;
  infrastructureDiagram = self.packages.${system}.infrastructure-diagram;
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

  seafile-core-contract =
    assert seafile.enable;
    assert seafile.version == "13.0.25";
    assert seafile.licenseUserLimit == 3;
    assert seafile.stateDir == "/storage/flash/seafile";
    assert seafile.dataset == "flash_pool/flash/storage/seafile";
    assert seafile.datasetQuotaBytes == 1649267441664;
    assert seafile.bindAddress == "127.0.0.1";
    assert seafile.port == 23239;
    assert seafile.onlyOfficePort == 23240;
    assert seafile.notificationPort == 23241;
    assert seafile.publicUrl == "https://files.shulker.link";
    assert seafile.onlyOfficePublicUrl == "https://office.shulker.link";
    assert seafile.oidcIssuer == "https://sso.shulker.link";
    assert seafile.oauthCallbackUrl == "https://files.shulker.link/oauth/callback/";
    assert seafile.notificationPublicUrl == "https://files.shulker.link/notification";
    assert seafile.notificationInternalUrl == "http://seafile-notification:8083";
    assert seafile.onlyOfficeApiUrl == "https://office.shulker.link/web-apps/apps/api/documents/api.js";
    assert seafile.metadataFileCountLimit == 100000;
    assert seafile.metadataCacheSize == "1GB";
    assert seafile.metadataCheckUpdateInterval == "30m";
    assert seafile.logicalDumpRetention == 14;
    assert
      seafile.editableExtensions == [
        "docx"
        "xlsx"
        "pptx"
        "csv"
      ];
    assert
      seafile.seafileImage
      == "docker.io/seafileltd/seafile-pro-mc:13.0.25@sha256:82fa05a844303912066a7ded86864dbf6fb45273f08f6448a0842863beefabb4";
    assert
      seafile.databaseImage
      == "docker.io/library/mariadb:10.11.18@sha256:992d5668eb9a5f153253c2f13d4e72717b7c24a27f271f47647af3b7e5a3c109";
    assert
      seafile.redisImage
      == "docker.io/library/redis:7.4.10-alpine@sha256:9702d01c1f10c3ea9f48211b4362e44f154ff02d063e6f7268eba804059f53bf";
    assert
      seafile.seasearchImage
      == "docker.io/seafileltd/seasearch:1.0.4@sha256:192284f4f2fe7ca879fdfb8301dd0ebc6a5da6efaa4a99c53febfad8a75b7edc";
    assert
      seafile.notificationImage
      == "docker.io/seafileltd/notification-server:13.0.21@sha256:be7b6c6887b921a86ec4990c0c8b0b57f7f5ba3046dcf0adb007bbc80abaec86";
    assert
      seafile.metadataImage
      == "docker.io/seafileltd/seafile-md-server:13.0.22@sha256:8ccee7ea9139c288a24bf1d7e29c5a1579256ee5f887eb93967e790f571eb973";
    assert
      seafile.onlyOfficeImage
      == "docker.io/onlyoffice/documentserver:9.4.0.1@sha256:e231bc62da8c1f0c1f78188f8c7e17e67716f38955d0ad1d703cf911ad6db84b";
    assert pkgs.lib.all (image: pkgs.lib.hasInfix "@sha256:" image) [
      seafile.seafileImage
      seafile.databaseImage
      seafile.redisImage
      seafile.seasearchImage
      seafile.notificationImage
      seafile.metadataImage
      seafile.onlyOfficeImage
    ];
    assert builtins.hasAttr "seafile-state" services;
    assert seafileStateService.unitConfig.RequiresMountsFor == seafile.stateDir;
    assert
      wardenConfig.services.onepassword-secrets.secrets.seafileEnv.services == [
        "seafile-config"
        "seafile-image-pull"
        "seafile-compose"
      ];
    pkgs.runCommand "seafile-core-contract" { } ''
      touch "$out"
    '';

  seafile-runtime-state-machine-contract =
    let
      validator = pkgs.writeText "seafile-validate-state-under-test" ''
        ${seafile.validateStateScript}
      '';
      validatorPackage = pkgs.writeShellApplication {
        name = "seafile-validate-state-contract-wrapper";
        text = seafile.validateStateScript;
      };
      parserPackage = pkgs.writeShellApplication {
        name = "seafile-parse-environment";
        runtimeInputs = [ pkgs.coreutils ];
        text = seafile.parseEnvironmentScript;
      };
      rendererPackage = pkgs.writeShellApplication {
        name = "seafile-render-runtime-config";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.util-linux
          parserPackage
        ];
        text = seafile.renderRuntimeConfigScript;
      };
      reconcilerPackage = pkgs.writeShellApplication {
        name = "seafile-reconcile-runtime-config";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.util-linux
          parserPackage
        ];
        text = seafile.reconcileRuntimeConfigScript;
      };
      composeStartPackage = pkgs.writeShellApplication {
        name = "seafile-compose-start";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.util-linux
        ];
        text = builtins.unsafeDiscardStringContext (
          builtins.replaceStrings
            [
              (toString seafile.composeFile)
              (toString seafile.bootstrapComposeFile)
            ]
            [
              "/unused/seafile-compose.yml"
              "/unused/seafile-bootstrap-compose.yml"
            ]
            seafile.composeStartScript
        );
      };
    in
    pkgs.runCommand "seafile-runtime-state-machine-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.util-linux
          validatorPackage
        ];
      }
      ''
        ${./tests/seafile-runtime-state-machine.sh} \
          ${validator} \
          ${rendererPackage}/bin/seafile-render-runtime-config \
          ${reconcilerPackage}/bin/seafile-reconcile-runtime-config \
          ${composeStartPackage}/bin/seafile-compose-start
        touch "$out"
      '';

  seafile-stack-contract =
    let
      compose = seafile.composeConfig;
      services' = compose.services;
      environmentKeys = service: builtins.attrNames (service.environment or { });
      publications = pkgs.lib.concatMap (service: service.ports or [ ]) (builtins.attrValues services');
      secretFixtureValues = [
        "fixture-root-secret"
        "fixture-database-secret"
        "fixture-redis-secret"
        "fixture-jwt-secret"
      ];
      composeJson = builtins.toJSON compose;
      redisStartScriptUnderTest = pkgs.writeText "seafile-start-redis-under-test" (
        seafile.redisStartScriptText
      );
    in
    assert compose.name == "seafile";
    assert
      builtins.attrNames services' == [
        "database"
        "metadata"
        "notification"
        "onlyoffice"
        "redis"
        "seafile"
        "seasearch"
      ];
    assert
      map (name: services'.${name}.container_name) (builtins.attrNames services') == [
        "seafile-mariadb"
        "seafile-metadata"
        "seafile-notification"
        "seafile-onlyoffice"
        "seafile-redis"
        "seafile"
        "seafile-seasearch"
      ];
    assert
      compose.networks == {
        seafile-net = {
          name = "seafile-net";
          internal = true;
        };
      };
    assert
      publications == [
        "127.0.0.1:23241:8083/tcp"
        "127.0.0.1:23240:80/tcp"
        "127.0.0.1:23239:80/tcp"
      ];
    assert pkgs.lib.all (service: service.restart == "no") (builtins.attrValues services');
    assert pkgs.lib.all (service: !(service.privileged or false)) (builtins.attrValues services');
    assert services'.redis.tmpfs == [ "/run/redis" ];
    assert services'.redis.entrypoint == [ "/usr/local/sbin/seafile-start-redis" ];
    assert services'.redis.command == [ "/run/redis/redis.conf" ];
    assert
      services'.seafile.volumes == [
        "/storage/flash/seafile/shared:/shared"
        "/run/seafile-app:/run/seafile:ro"
      ];
    assert
      services'.database.volumes == [
        "/storage/flash/seafile/database:/var/lib/mysql"
      ];
    assert
      services'.seasearch.volumes == [
        "/storage/flash/seafile/search:/opt/seasearch/data"
      ];
    assert
      services'.notification.volumes == [
        "/storage/flash/seafile/shared/seafile/logs:/shared/seafile/logs"
      ];
    assert
      services'.metadata.volumes == [
        "/storage/flash/seafile/shared:/shared"
        "/run/seafile-metadata:/run/seafile:ro"
      ];
    assert
      map (volume: volume.source) (
        builtins.filter (volume: builtins.isAttrs volume) services'.onlyoffice.volumes
      ) == [
        "/storage/flash/seafile/onlyoffice/logs"
        "/storage/flash/seafile/onlyoffice/data"
        "/storage/flash/seafile/onlyoffice/lib"
        (toString seafile.onlyOfficeConfig)
      ];
    assert pkgs.lib.all (volume: volume.bind.create_host_path == false) (
      builtins.filter (volume: builtins.isAttrs volume) services'.onlyoffice.volumes
    );
    assert environmentKeys services'.redis == [ "REDIS_PASSWORD" ];
    assert
      environmentKeys services'.onlyoffice == [
        "EXAMPLE_ENABLED"
        "JWT_ENABLED"
        "JWT_SECRET"
      ];
    assert
      environmentKeys services'.notification == [
        "JWT_PRIVATE_KEY"
        "NOTIFICATION_SERVER_LOG_LEVEL"
        "SEAFILE_LOG_TO_STDOUT"
        "SEAFILE_MYSQL_DB_CCNET_DB_NAME"
        "SEAFILE_MYSQL_DB_HOST"
        "SEAFILE_MYSQL_DB_PASSWORD"
        "SEAFILE_MYSQL_DB_PORT"
        "SEAFILE_MYSQL_DB_SEAFILE_DB_NAME"
        "SEAFILE_MYSQL_DB_USER"
      ];
    assert
      environmentKeys services'.metadata == [
        "CACHE_PROVIDER"
        "JWT_PRIVATE_KEY"
        "MD_CHECK_UPDATE_INTERVAL"
        "MD_FILE_COUNT_LIMIT"
        "MD_MAX_CACHE_SIZE"
        "MD_STORAGE_TYPE"
        "REDIS_HOST"
        "REDIS_PASSWORD"
        "REDIS_PORT"
        "SEAFILE_LOG_TO_STDOUT"
        "SEAFILE_MYSQL_DB_HOST"
        "SEAFILE_MYSQL_DB_PASSWORD"
        "SEAFILE_MYSQL_DB_PORT"
        "SEAFILE_MYSQL_DB_SEAFILE_DB_NAME"
        "SEAFILE_MYSQL_DB_USER"
        "SEAF_SERVER_STORAGE_TYPE"
      ];
    assert !(builtins.hasAttr "MYSQL_ROOT_PASSWORD" services'.database.environment);
    assert !(builtins.hasAttr "SS_FIRST_ADMIN_USER" services'.seasearch.environment);
    assert !(builtins.hasAttr "SS_FIRST_ADMIN_PASSWORD" services'.seasearch.environment);
    assert
      seafile.bootstrapComposeConfig.services.database.environment.MYSQL_ROOT_PASSWORD
      == "\${INIT_SEAFILE_MYSQL_ROOT_PASSWORD:?INIT_SEAFILE_MYSQL_ROOT_PASSWORD is required}";
    assert
      seafile.bootstrapComposeConfig.services.seasearch.environment.SS_FIRST_ADMIN_USER
      == "\${INIT_SS_ADMIN_USER:?INIT_SS_ADMIN_USER is required}";
    assert
      services'.onlyoffice.environment.EXAMPLE_ENABLED == "false"
      && services'.onlyoffice.environment.JWT_ENABLED == "true";
    assert
      services'.seafile.depends_on.database.condition == "service_healthy"
      && services'.seafile.depends_on.redis.condition == "service_healthy";
    assert
      services'.notification.depends_on.seafile.condition == "service_healthy"
      && services'.metadata.depends_on.seafile.condition == "service_healthy";
    assert pkgs.lib.all (value: !(pkgs.lib.hasInfix value composeJson)) secretFixtureValues;
    assert pkgs.lib.all (forbidden: !(pkgs.lib.hasInfix forbidden composeJson)) [
      "/storage/flash/immich"
      "caddy"
      "seadoc"
      "webdav"
      "elasticsearch"
      "network_mode"
      "privileged"
    ];
    assert pkgs.lib.all (
      name:
      services'.${name}.image == {
        database = seafile.databaseImage;
        metadata = seafile.metadataImage;
        notification = seafile.notificationImage;
        onlyoffice = seafile.onlyOfficeImage;
        redis = seafile.redisImage;
        seafile = seafile.seafileImage;
        seasearch = seafile.seasearchImage;
      }
      .${name}
    ) (builtins.attrNames services');
    assert seafilePullService.serviceConfig.Type == "oneshot";
    assert seafilePullService.serviceConfig.RemainAfterExit;
    assert seafilePullService.serviceConfig.TimeoutStartSec == 10800;
    assert builtins.elem "COMPOSE_PARALLEL_LIMIT=1" seafilePullService.serviceConfig.Environment;
    assert
      seafilePullService.unitConfig.ConditionFileNotEmpty
      == seafileComposeService.unitConfig.ConditionFileNotEmpty;
    assert builtins.elem "seafile-image-pull.service" seafileComposeService.requires;
    assert builtins.elem "seafile-config.service" seafileComposeService.requires;
    assert builtins.elem "seafile-image-pull.service" seafileComposeService.after;
    assert builtins.elem "seafile-config.service" seafileComposeService.after;
    assert builtins.elem "docker.service" seafileComposeService.unitConfig.BindsTo;
    assert seafileComposeService.serviceConfig.TimeoutStartSec > 1800;
    assert builtins.hasAttr "seafile-compose-recovery" services;
    assert builtins.hasAttr "seafile-compose-recovery" wardenConfig.systemd.timers;
    assert !(builtins.elem seafile.port wardenConfig.networking.firewall.allowedTCPPorts);
    assert !(builtins.elem seafile.onlyOfficePort wardenConfig.networking.firewall.allowedTCPPorts);
    assert !(builtins.elem seafile.notificationPort wardenConfig.networking.firewall.allowedTCPPorts);
    pkgs.runCommand "seafile-stack-contract" { } ''
      test "$(head -n 1 ${redisStartScriptUnderTest})" = '#!/bin/sh'
      ! grep -F '/nix/store' ${redisStartScriptUnderTest}
      grep -F 'chown 999:1000' ${redisStartScriptUnderTest} >/dev/null
      grep -F 'chmod 0700 /run/redis' ${redisStartScriptUnderTest} >/dev/null
      grep -F 'chmod 0600 "$config"' ${redisStartScriptUnderTest} >/dev/null
      grep -F 'su-exec 999:1000 test -r "$config"' ${redisStartScriptUnderTest} >/dev/null
      grep -F 'unset REDIS_PASSWORD' ${redisStartScriptUnderTest} >/dev/null
      grep -F 'exec su-exec 999:1000 redis-server /run/redis/redis.conf' ${redisStartScriptUnderTest} >/dev/null
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
        ${./tests/shulker-rebuild-secret-preflight.sh} ${checkedRebuild}/bin/shulker-rebuild
        touch "$out"
      '';

  seafile-secret-contract =
    assert
      seafile.requiredEnvironmentKeys == [
        "INIT_SEAFILE_MYSQL_ROOT_PASSWORD"
        "SEAFILE_MYSQL_DB_PASSWORD"
        "REDIS_PASSWORD"
        "JWT_PRIVATE_KEY"
        "SEAHUB_SECRET_KEY"
        "INIT_SEAFILE_ADMIN_EMAIL"
        "INIT_SEAFILE_ADMIN_PASSWORD"
        "INIT_SS_ADMIN_USER"
        "INIT_SS_ADMIN_PASSWORD"
        "SEAFILE_OAUTH_CLIENT_ID"
        "SEAFILE_OAUTH_CLIENT_SECRET"
        "ONLYOFFICE_JWT_SECRET"
      ];
    assert
      builtins.attrNames wardenConfig.shulker.system.secretPreflight.schemas.seafileEnv.exactKeys
      == builtins.sort builtins.lessThan seafile.requiredEnvironmentKeys;
    assert
      wardenConfig.shulker.system.secretPreflight.schemas.seafileEnv.exactKeys.SEAFILE_MYSQL_DB_PASSWORD.pattern
      == "^[A-Za-z0-9._~!@+,/:=-]+$";
    assert
      wardenConfig.shulker.system.secretPreflight.schemas.seafileEnv.exactKeys.SEAHUB_SECRET_KEY.minLength
      == 50;
    assert seafileConfigService.serviceConfig.Type == "oneshot";
    assert seafileConfigService.serviceConfig.RemainAfterExit;
    assert seafileConfigService.serviceConfig.RuntimeDirectoryPreserve == "yes";
    assert
      seafileConfigService.unitConfig.ConditionFileNotEmpty
      == wardenConfig.services.onepassword-secrets.secrets.seafileEnv.path;
    assert builtins.elem "opnix-secrets.service" seafileConfigService.requires;
    assert builtins.elem "seafile-state.service" seafileConfigService.requires;
    assert builtins.elem "opnix-secrets.service" seafileConfigService.after;
    assert builtins.elem "seafile-state.service" seafileConfigService.after;
    assert pkgs.lib.hasInfix "/run/seafile-host" seafile.runtimeConfigContractText;
    assert pkgs.lib.hasInfix "/run/seafile-app" seafile.runtimeConfigContractText;
    assert pkgs.lib.hasInfix "/run/seafile-metadata" seafile.runtimeConfigContractText;
    assert pkgs.lib.hasInfix "RuntimeDirectoryPreserve" seafile.runtimeConfigContractText;
    pkgs.runCommand "seafile-secret-contract" { } ''
      touch "$out"
    '';

  seafile-identity-boundary-contract =
    pkgs.runCommand "seafile-identity-boundary-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.jq
        ];
      }
      ''
        ${./tests/seafile-identity-boundary.sh} \
          ${./.}/scripts/validate-seafile-identities.sh
        touch "$out"
      '';

  seafile-bootstrap-contract =
    let
      settings = pkgs.writeText "seahub_settings.py" seafile.seahubSettingsText;
      contract = seafile.bootstrapContractText;
      revokeStart = "from django.contrib.sessions.models import Session";
      revokeAfterStart = builtins.elemAt (pkgs.lib.splitString revokeStart contract) 1;
      revokeBody = builtins.unsafeDiscardStringContext (
        builtins.elemAt (pkgs.lib.splitString "\nfrom seaserv import ccnet_api" revokeAfterStart) 0
      );
      revokeScript = pkgs.writeText "seafile-revoke-oauth-admin.py" ''
        import os

        ${revokeStart}${revokeBody}
      '';

    in
    assert pkgs.lib.all (name: builtins.elem name systemPackageNames) seafileBootstrapPackageNames;
    assert builtins.length seafileBootstrapPackages == builtins.length seafileBootstrapPackageNames;
    assert pkgs.lib.hasInfix "/run/lock/seafile-maintenance.lock" contract;
    assert pkgs.lib.hasInfix "com.docker.compose.project" contract;
    assert pkgs.lib.hasInfix "SEAFILE_ADMIN_USER_ID" contract;
    assert pkgs.lib.hasInfix "SocialAuthUser" contract;
    assert pkgs.lib.hasInfix "provider=\"pocket-id\"" contract;
    assert pkgs.lib.hasInfix "license_user_limit = 3" contract;
    assert pkgs.lib.hasInfix "active_user_count > license_user_limit" contract;
    assert pkgs.lib.hasInfix "docker restart seafile" contract;
    assert pkgs.lib.hasInfix "reset-admin.sh" contract;
    assert pkgs.lib.hasInfix "INIT_SEAFILE_ADMIN_EMAIL" contract;
    assert pkgs.lib.hasInfix "INIT_SEAFILE_ADMIN_PASSWORD" contract;
    assert !(pkgs.lib.hasInfix "set_password(" contract);
    assert !(pkgs.lib.hasInfix "create_user(" contract);
    assert !(pkgs.lib.hasInfix "DISABLE_ADFS_USER_PWD_LOGIN" seafile.seahubSettingsText);
    assert !(pkgs.lib.hasInfix "pangolin" (pkgs.lib.toLower (contract + seafile.seahubSettingsText)));
    pkgs.runCommand "seafile-bootstrap-contract"
      {
        nativeBuildInputs = [
          pkgs.python3
        ]
        ++ pkgs.lib.optionals (system == "x86_64-linux") seafileBootstrapPackages;
      }
      ''
        export SEAHUB_SECRET_KEY=fixture-secret-key
        export JWT_PRIVATE_KEY=fixture-private-key
        export SEAFILE_MYSQL_DB_PASSWORD=fixture-database-password
        export SEAFILE_OAUTH_CLIENT_ID=fixture-client-id
        export SEAFILE_OAUTH_CLIENT_SECRET=fixture-client-secret
        export ONLYOFFICE_JWT_SECRET=fixture-office-secret
        python - ${settings} <<'PY'
        import runpy
        import sys

        settings = runpy.run_path(sys.argv[1])
        expected = {
            "TIME_ZONE": "Europe/Paris",
            "ENABLE_OAUTH": True,
            "OAUTH_CREATE_UNKNOWN_USER": True,
            "OAUTH_ACTIVATE_USER_AFTER_CREATION": True,
            "OAUTH_ENABLE_INSECURE_TRANSPORT": False,
            "OAUTH_PROVIDER": "pocket-id",
            "OAUTH_REDIRECT_URL": "https://files.shulker.link/oauth/callback/",
            "OAUTH_AUTHORIZATION_URL": "https://sso.shulker.link/authorize",
            "OAUTH_TOKEN_URL": "https://sso.shulker.link/api/oidc/token",
            "OAUTH_USER_INFO_URL": "https://sso.shulker.link/api/oidc/userinfo",
            "OAUTH_SCOPE": ["openid", "profile", "email"],
            "OAUTH_ATTRIBUTE_MAP": {
                "sub": (True, "uid"),
                "name": (False, "name"),
                "email": (False, "contact_email"),
            },
            "CLIENT_SSO_VIA_LOCAL_BROWSER": True,
            "ENABLE_SSO_USER_CHANGE_PASSWORD": False,
            "ENABLE_SETTINGS_VIA_WEB": False,
            "ENABLE_METADATA_MANAGEMENT": True,
            "METADATA_SERVER_URL": "http://seafile-metadata:8084",
            "SHARE_LINK_FORCE_USE_PASSWORD": True,
            "SHARE_LINK_PASSWORD_MIN_LENGTH": 12,
            "SHARE_LINK_PASSWORD_STRENGTH_LEVEL": 3,
            "SHARE_LINK_EXPIRE_DAYS_DEFAULT": 7,
            "SHARE_LINK_EXPIRE_DAYS_MAX": 30,
            "UPLOAD_LINK_EXPIRE_DAYS_DEFAULT": 7,
            "UPLOAD_LINK_EXPIRE_DAYS_MAX": 30,
            "SHARE_LINK_LOGIN_REQUIRED": False,
            "ENABLE_ONLYOFFICE": True,
            "ONLYOFFICE_APIJS_URL": "https://office.shulker.link/web-apps/apps/api/documents/api.js",
            "ONLYOFFICE_EDIT_FILE_EXTENSION": ("docx", "xlsx", "pptx", "csv"),
            "ENABLE_WIKI": False,
        }
        for key, value in expected.items():
            assert settings.get(key) == value, (key, settings.get(key))
        assert not any(
            key.startswith("OAUTH_") and any(term in key for term in ("ADMIN", "GROUP", "ROLE"))
            for key in settings
        )
        assert settings["DATABASES"] == {
            "default": {
                "ENGINE": "django.db.backends.mysql",
                "NAME": "seahub_db",
                "USER": "seafile",
                "PASSWORD": "fixture-database-password",
                "HOST": "database",
                "PORT": "3306",
                "OPTIONS": {"charset": "utf8mb4"},
            }
        }
        assert settings["ONLYOFFICE_JWT_SECRET"] == "fixture-office-secret"
        PY

        python ${./tests/seafile-revoke-admin.py} ${revokeScript}

        touch "$out"
      '';

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
        ${./tests/seafile-maintenance.sh} \
          ${health}/bin/seafile-health-check-under-test \
          ${extended}/bin/seafile-extended-health-under-test \
          ${metadata}/bin/seafile-metadata-probe-under-test \
          ${enablePublic}/bin/seafile-enable-public-health-under-test \
          ${contractFile} \
          ${onlyOfficeDriver} \
          ${onlyOffice}/bin/seafile-onlyoffice-smoke-test-under-test
        touch "$out"
      '';

  seafile-backup-state-machine-contract =
    let
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
      restoreVerify = mkBackupHelper "seafile-restore-verify-under-test" seafile.restoreVerifyScript [ ];
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
        ];
      }
      ''
        ${./tests/seafile-backup-state-machine.sh} \
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
    assert pkgs.lib.hasInfix "seafile-restore-net" contract;
    assert pkgs.lib.hasInfix "https://files.restore.invalid:24239" contract;
    assert pkgs.lib.hasInfix "https://office.restore.invalid:24240" contract;
    assert pkgs.lib.hasInfix "DynamicUser" contract;
    assert pkgs.lib.hasInfix "--sandbox" contract;
    assert !(pkgs.lib.hasInfix "--no-sandbox" contract);
    assert !(pkgs.lib.hasInfix "--ignore-certificate-errors" contract);
    assert !(pkgs.lib.hasInfix "/storage/flash/immich" contract);
    assert !(pkgs.lib.hasInfix "INIT_SEAFILE_ADMIN_PASSWORD=" contract);
    pkgs.runCommand "seafile-backup-contract" { } ''
      touch "$out"
    '';

  seafile-docs-contract =
    pkgs.runCommand "seafile-docs-contract"
      {
        nativeBuildInputs = [
          pkgs.gawk
          pkgs.gnugrep
          pkgs.jq
        ];
      }
      ''
        combined="$TMPDIR/seafile-generated-docs"
        readme=${./README.md}
        seafile_readme="$TMPDIR/seafile-readme"
        seafile_readme_text="$TMPDIR/seafile-readme-text"
        seafile_service_row="$TMPDIR/seafile-service-row"
        seafile_operations="$TMPDIR/seafile-operations"
        mkdir -p "$combined/warden" "$combined/infrastructure" "$combined/diagram" "$combined/wiki"
        cp -R ${wardenServerDocs}/. "$combined/warden"
        cp -R ${infrastructureData}/. "$combined/infrastructure"
        cp -R ${infrastructureDiagram}/. "$combined/diagram"
        cp -R ${wikiDocs}/. "$combined/wiki"
        cp "$readme" "$combined/README.md"

        warden_report="$combined/warden/warden.md"
        inventory="$combined/infrastructure/infrastructure.json"
        diagram="$combined/diagram/Infrastructure.md"
        wiki_services="$combined/wiki/Services.md"
        test -f "$warden_report"
        test -f "$inventory"
        test -f "$diagram"
        test -f "$wiki_services"
        test -f "$combined/wiki/Fleet.md"
        test -f "$combined/wiki/Public-Services.md"

        awk '
          $0 == "## Seafile family files" { in_section = 1 }
          $0 == "## OpenCloud family storage" { in_section = 0 }
          in_section { print }
        ' "$readme" > "$seafile_readme"
        test -s "$seafile_readme"
        tr '\n' ' ' < "$seafile_readme" > "$seafile_readme_text"

        grep -F -- '| Seafile Pro 13.0.25 |' "$warden_report" > "$seafile_service_row"
        test "$(wc -l < "$seafile_service_row")" -eq 1

        awk '
          $0 == "Inspect Seafile Pro and run its bounded operator checks:" { in_section = 1 }
          $0 == "Roll back the active system profile:" { in_section = 0 }
          in_section { print }
        ' "$warden_report" > "$seafile_operations"
        test -s "$seafile_operations"

        for container in \
          seafile \
          seafile-mariadb \
          seafile-redis \
          seafile-seasearch \
          seafile-notification \
          seafile-metadata \
          seafile-onlyoffice
        do
          test "$(grep -F -c -- "| $container |" "$warden_report")" -eq 1
        done

        test "$(grep -E -o '@sha256:[0-9a-f]{64}' "$seafile_readme" | wc -l)" -eq 7

        for expected in \
          'Seafile Pro 13.0.25' \
          'https://files.shulker.link' \
          'https://office.shulker.link' \
          '127.0.0.1:23239' \
          '127.0.0.1:23240' \
          '127.0.0.1:23241' \
          'flash_pool/flash/storage/seafile' \
          '1.5 TiB' \
          '3 named users maximum' \
          'Pocket ID OIDC' \
          'SeaSearch' \
          'Notification' \
          'Metadata' \
          'OnlyOffice' \
          'Borgmatic' \
          '/storage/flash/seafile/.zfs/snapshot/borgmatic/shared' \
          '/storage/flash/seafile/.zfs/snapshot/borgmatic/backups'
        do
          grep -R -F -- "$expected" "$combined" >/dev/null
        done

        for secret_name in \
          INIT_SEAFILE_MYSQL_ROOT_PASSWORD \
          SEAFILE_MYSQL_DB_PASSWORD \
          REDIS_PASSWORD \
          JWT_PRIVATE_KEY \
          SEAHUB_SECRET_KEY \
          INIT_SEAFILE_ADMIN_EMAIL \
          INIT_SEAFILE_ADMIN_PASSWORD \
          INIT_SS_ADMIN_USER \
          INIT_SS_ADMIN_PASSWORD \
          SEAFILE_OAUTH_CLIENT_ID \
          SEAFILE_OAUTH_CLIENT_SECRET \
          ONLYOFFICE_JWT_SECRET
        do
          grep -F -- "$secret_name" "$seafile_readme" >/dev/null
        done

        for command in \
          seafile-health-check \
          seafile-extended-health \
          seafile-fsck-shallow \
          seafile-fsck-full \
          seafile-gc-dry-run \
          seafile-search-status \
          seafile-search-update \
          seafile-search-rebuild \
          seafile-metadata-probe \
          seafile-onlyoffice-smoke-test \
          seafile-backup-status \
          seafile-pre-upgrade-check \
          seafile-restore-prepare \
          seafile-restore-verify \
          seafile-restore-teardown \
          'borgmatic create' \
          'borgmatic check'
        do
          grep -F -- "$command" "$seafile_readme" >/dev/null
          grep -F -- "$command" "$seafile_operations" >/dev/null
        done

        for policy in \
          'Repository implementation and commits do not deploy Seafile' \
          'OpenCloud remains enabled as the rollback path' \
          'Immich is the sole authoritative store' \
          'no documented server-side switch that enforces this preference' \
          'They do not extract archive data automatically' \
          'OpenCloud removal and dataset deletion are separate, destructive, approval-gated work'
        do
          grep -F -- "$policy" "$seafile_readme_text" >/dev/null
        done

        jq -e '
          . as $root
          | ($root.schema == 2)
          and all(
            $root.hosts[];
            . as $host
            | (([$host.services[].key] | length) == ([$host.services[].key] | unique | length))
            and all(
              $host.dependencies[]?;
              .from as $from
              | .to as $to
              | (([$host.services[].key] | index($from)) != null)
              and (([$host.services[].key] | index($to)) != null)
            )
          )
          and (
            ($root.hosts[] | select(.name == "warden")) as $warden
            | (([
                $warden.services[]
                | select(.key | startswith("seafile"))
                | .key
              ] | sort) == [
                "seafile",
                "seafile-mariadb",
                "seafile-metadata",
                "seafile-notification",
                "seafile-onlyoffice",
                "seafile-redis",
                "seafile-seasearch"
              ])
            and all(
              $warden.services[] | select(.key | startswith("seafile"));
              if .key == "seafile" then
                .endpoint == "https://files.shulker.link"
              elif .key == "seafile-onlyoffice" then
                .endpoint == "https://office.shulker.link"
              else
                .endpoint == null
              end
            )
            and (([
                $warden.dependencies[]
                | "\(.from)|\(.to)|\(.relation)"
              ] | sort) == ([
                "seafile|backup|writer-quiesced backup",
                "seafile|seafile-mariadb|application metadata",
                "seafile|seafile-metadata|extended metadata",
                "seafile|seafile-notification|real-time notifications",
                "seafile|seafile-onlyoffice|browser Office editing",
                "seafile|seafile-redis|cache and coordination",
                "seafile|seafile-seasearch|full-text search",
                "seafile-metadata|seafile-mariadb|file metadata",
                "seafile-metadata|seafile-redis|cache and event queue",
                "seafile-metadata|seafile|shared object and configuration state",
                "seafile-notification|seafile-mariadb|notification database",
                "seafile-notification|seafile|application events"
              ] | sort))
            and any(
              $warden.connections[];
              .from == "seafile"
              and .to == "https://sso.shulker.link"
              and .relation == "OIDC authentication"
            )
          )
        ' "$inventory" >/dev/null

        grep -F -- '## Local component dependencies' "$diagram" >/dev/null
        grep -F -- 'warden local components' "$diagram" >/dev/null
        grep -F -- '## Management dependencies' "$diagram" >/dev/null
        grep -F -- '## Public access' "$diagram" >/dev/null
        grep -F -- '## Local component dependencies' "$wiki_services" >/dev/null

        unexpected_loopback="$({
          grep -E -o '127\.0\.0\.1:[0-9]+' "$seafile_readme" || true
        } | grep -E -v '^127\.0\.0\.1:(23239|23240|23241)$' || true)"
        if test -n "$unexpected_loopback"; then
          echo "Seafile runbook contains an undeclared private target" >&2
          exit 1
        fi

        if grep -R -E \
          '(INIT_SEAFILE_MYSQL_ROOT_PASSWORD|SEAFILE_MYSQL_DB_PASSWORD|REDIS_PASSWORD|JWT_PRIVATE_KEY|SEAHUB_SECRET_KEY|INIT_SEAFILE_ADMIN_EMAIL|INIT_SEAFILE_ADMIN_PASSWORD|INIT_SS_ADMIN_USER|INIT_SS_ADMIN_PASSWORD|SEAFILE_OAUTH_CLIENT_ID|SEAFILE_OAUTH_CLIENT_SECRET|ONLYOFFICE_JWT_SECRET)[[:space:]]*=' \
          "$combined" >/dev/null
        then
          echo "Generated Seafile documentation contains a secret value assignment" >&2
          exit 1
        fi

        if grep -R -E \
          'op://|/run/seafile|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}|share[_ -]?token[[:space:]]*[:=]|document[_ -]?filename[[:space:]]*[:=]|"(targets?|accessPolicies|identities|credentials)"[[:space:]]*:' \
          "$combined" >/dev/null
        then
          echo "Generated Seafile documentation contains private runtime or account material" >&2
          exit 1
        fi

        for unsupported in \
          'Nix proves live Pangolin' \
          'Nix proves Pangolin routing' \
          'Metadata has a manual consistency command' \
          'server enforces camera upload disabled' \
          'server disables camera upload' \
          'forcesave captures every edit' \
          'forcesave preserves every edit' \
          "every forced save appears in OnlyOffice's own history"
        do
          if grep -R -F -- "$unsupported" "$combined" >/dev/null; then
            echo "Seafile documentation contains an unsupported claim: $unsupported" >&2
            exit 1
          fi
        done

        if grep -R -F -- 'seafile-release-monitor' "$combined" >/dev/null; then
          echo "Seafile release-monitor documentation landed before its workflow" >&2
          exit 1
        fi

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
    assert builtins.elem "paperless-bootstrap-groups" systemPackageNames;
    assert builtins.elem "paperless-promote-oidc-admin" systemPackageNames;
    assert builtins.elem "paperless-revoke-admin" systemPackageNames;
    assert builtins.elem "paperless-bootstrap-fastmail" systemPackageNames;
    assert builtins.elem "paperless-list-users" systemPackageNames;
    assert builtins.elem "paperless-enable-user" systemPackageNames;
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

  seafile-release-workflow-contract =
    pkgs.runCommand "seafile-release-workflow-contract"
      {
        nativeBuildInputs = [
          pkgs.gawk
          pkgs.gnugrep
        ];
      }
      ''
        workflow=${./.}/.github/workflows/check-seafile-release.yml
        check_workflow=${./.}/.github/workflows/check.yml
        update_workflow=${./.}/.github/workflows/update-flake.yml
        root_readme=${./README.md}
        github_readme=${./.github/README.md}
        wiki_automation=${wikiDocs}/Automation.md

        test -f "$workflow"

        test "$(grep -F -c -- 'workflow_dispatch:' "$workflow")" -eq 1
        test "$(grep -F -c -- 'cron: "43 5 * * 1"' "$workflow")" -eq 1

        concurrency="$TMPDIR/seafile-release-concurrency"
        awk '
          $0 == "concurrency:" { in_block = 1; next }
          $0 == "permissions:" { in_block = 0 }
          in_block && NF { print }
        ' "$workflow" > "$concurrency"
        test "$(wc -l < "$concurrency")" -eq 2
        grep -F -x -- '  group: seafile-release-monitor' "$concurrency" >/dev/null
        grep -F -x -- '  cancel-in-progress: false' "$concurrency" >/dev/null

        permissions="$TMPDIR/seafile-release-permissions"
        awk '
          $0 == "permissions:" { in_block = 1; next }
          $0 == "jobs:" { in_block = 0 }
          in_block && NF { print }
        ' "$workflow" > "$permissions"
        test "$(wc -l < "$permissions")" -eq 2
        grep -F -x -- '  contents: read' "$permissions" >/dev/null
        grep -F -x -- '  issues: write' "$permissions" >/dev/null

        test "$(grep -E -c '^[[:space:]]*- uses:' "$workflow")" -eq 2
        test "$(grep -E -c '^[[:space:]]*- uses: [^@]+@[0-9a-f]{40}( # .*)?$' "$workflow")" -eq 2
        grep -F -- \
          'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2' \
          "$workflow" >/dev/null
        grep -F -- \
          'cachix/install-nix-action@630ae543ea3a38a9a4166f03376c02c50f408342 # v31.11.0' \
          "$workflow" >/dev/null

        test "$(grep -F -c -- 'nix eval --json' "$workflow")" -eq 1
        test "$(grep -F -c -- '.#nixosConfigurations.warden.config.shulker.system.modules.seafile.releaseVersions' "$workflow")" -eq 1
        grep -F -- \
          'components=(seafile mariadb redis seasearch notification metadata onlyoffice)' \
          "$workflow" >/dev/null
        grep -F -- 'https://hub.docker.com/v2/repositories/$repository/tags' "$workflow" >/dev/null
        grep -F -- 'for component in "''${components[@]}"' "$workflow" >/dev/null
        grep -F -- 'configured[$component]' "$workflow" >/dev/null
        grep -F -- 'detected_tags[$component]' "$workflow" >/dev/null

        for expected in \
          "[seafile]='seafileltd/seafile-pro-mc'" \
          "[mariadb]='library/mariadb'" \
          "[redis]='library/redis'" \
          "[seasearch]='seafileltd/seasearch'" \
          "[notification]='seafileltd/notification-server'" \
          "[metadata]='seafileltd/seafile-md-server'" \
          "[onlyoffice]='onlyoffice/documentserver'" \
          "[seafile]='^13[.]0[.][0-9]+$'" \
          "[mariadb]='^10[.]11[.][0-9]+$'" \
          "[redis]='^7[.]4[.][0-9]+-alpine$'" \
          "[seasearch]='^1[.]0[.][0-9]+$'" \
          "[notification]='^13[.]0[.][0-9]+$'" \
          "[metadata]='^13[.]0[.][0-9]+$'" \
          "[onlyoffice]='^9[.]4[.][0-9]+[.][0-9]+$'"
        do
          grep -F -- "$expected" "$workflow" >/dev/null
        done

        test "$(grep -F -c -- '<!-- seafile-release-monitor -->' "$workflow")" -eq 1
        test "$(grep -F -c -- 'chore: review Seafile stack updates' "$workflow")" -eq 1
        for expected in \
          'gh issue list --state open' \
          'select(.title == \"$issue_title\")' \
          'if grep -F -- "$marker" <<<"$issue_body"' \
          'gh issue edit "$managed_issue"' \
          'gh issue create --title "$issue_title"'
        do
          grep -F -- "$expected" "$workflow" >/dev/null
        done

        for expected in \
          'Check Seafile stack releases' \
          'weekly or manual' \
          'non-deploying'
        do
          grep -F -i -- "$expected" "$root_readme" >/dev/null
          grep -F -i -- "$expected" "$wiki_automation" >/dev/null
        done
        for expected in \
          'every Monday and on demand' \
          'contents: read' \
          'issues: write' \
          'official Docker Hub tag API' \
          '<!-- seafile-release-monitor -->' \
          'similarly titled human-authored issue is never changed' \
          'never edits image pins' \
          'mutates a host'
        do
          grep -F -i -- "$expected" "$github_readme" >/dev/null
        done

        suite_command='nix build --no-link .#checks.x86_64-linux.seafile-contract-suite'
        grep -F -- "$suite_command" "$check_workflow" >/dev/null
        grep -F -- "$suite_command" "$update_workflow" >/dev/null

        for forbidden in \
          'contents: write' \
          'pull-requests: write' \
          'git add' \
          'git apply' \
          'git checkout' \
          'git commit' \
          'git push' \
          'git switch' \
          'nixos-rebuild' \
          'ssh ' \
          'op://' \
          '1password' \
          'pocket id' \
          'pangolin'
        do
          if grep -F -i -- "$forbidden" "$workflow" >/dev/null; then
            echo "Seafile release monitor contains forbidden access or mutation: $forbidden" >&2
            exit 1
          fi
        done

        touch "$out"
      '';

  seafile-contract-suite =
    pkgs.runCommand "seafile-contract-suite"
      {
        contractInputs = [
          self.checks.${system}.seafile-core-contract
          self.checks.${system}.seafile-runtime-state-machine-contract
          self.checks.${system}.seafile-secret-contract
          self.checks.${system}.seafile-stack-contract
          self.checks.${system}.seafile-identity-boundary-contract
          self.checks.${system}.seafile-bootstrap-contract
          self.checks.${system}.seafile-maintenance-contract
          self.checks.${system}.seafile-backup-state-machine-contract
          self.checks.${system}.seafile-backup-contract
          self.checks.${system}.seafile-docs-contract
          self.checks.${system}.seafile-release-workflow-contract
        ];
      }
      ''
        for contract in $contractInputs; do
          test -e "$contract"
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
