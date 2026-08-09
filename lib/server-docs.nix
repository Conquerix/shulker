{
  config,
  hostName,
  lib,
  pkgs,
  revision ? null,
}:

let
  inherit (builtins)
    attrNames
    concatLists
    isAttrs
    isBool
    isString
    map
    toString
    ;
  inherit (lib)
    concatMapStringsSep
    concatStringsSep
    filter
    hasInfix
    hasPrefix
    mapAttrsToList
    optional
    optionals
    sort
    unique
    ;

  modules = config.shulker.system.modules;
  profiles = config.shulker.system.profiles;

  escapeCell = value: lib.replaceStrings [ "|" "\n" ] [ "\\|" "<br>" ] (toString value);
  code = value: "`${escapeCell value}`";
  yesNo = value: if value then "yes" else "no";
  enabledDisabled = value: if value then "enabled" else "disabled";
  bytesAsGiB = value: "${toString (builtins.div value 1073741824)} GiB";
  orNone = values: if values == [ ] then "_None._" else concatStringsSep ", " values;
  codeList = values: orNone (map code values);
  bulletList =
    values:
    if values == [ ] then "_None._\n" else concatMapStringsSep "" (value: "- ${value}\n") values;
  markdownTable =
    headers: rows:
    let
      renderRow = row: "| ${concatStringsSep " | " (map escapeCell row)} |\n";
      separator = map (_: "---") headers;
    in
    renderRow headers + renderRow separator + concatMapStringsSep "" renderRow rows;

  collectEnabled =
    path: value:
    if isAttrs value && value ? enable && isBool value.enable then
      optionals value.enable [ (concatStringsSep "." path) ]
    else if isAttrs value then
      concatLists (mapAttrsToList (name: child: collectEnabled (path ++ [ name ]) child) value)
    else
      [ ];

  enabledProfiles = collectEnabled [ ] profiles;
  enabledModules = collectEnabled [ ] modules;

  service =
    name: enabled: access: state: notes:
    optional enabled {
      inherit
        access
        name
        notes
        state
        ;
    };

  gitPageDetails = concatMapStringsSep "; " (
    repo:
    let
      index = lib.lists.findFirstIndex (candidate: candidate.name == repo.name) 0 modules.git-pages.repos;
      port = if repo.port != 0 then repo.port else modules.git-pages.basePort + index;
    in
    "${repo.name}: ${modules.git-pages.bindAddress}:${toString port} from ${repo.url}@${repo.branch}"
  ) modules.git-pages.repos;

  configuredServices = concatLists [
    (service "Borgmatic" modules.backup.enable
      "Hetzner Storage Box ${modules.backup.hetznerStorageBoxAccount}"
      "/var/lib/borgmatic"
      "Scheduled encrypted backups"
    )
    (service "Beszel agent" modules.beszel.agent.enable modules.beszel.agent.hubEndpoint
      modules.beszel.agent.stateDir
      "Filesystems: ${modules.beszel.agent.extraFilesystems}"
    )
    (service "Beszel hub" modules.beszel.hub.enable
      "${modules.beszel.hub.appUrl} via 127.0.0.1:${toString modules.beszel.hub.port}"
      modules.beszel.hub.stateDir
      "Local monitoring hub"
    )
    (service "Forgejo" modules.forgejo.enable
      "https://${modules.forgejo.subDomain}.${modules.forgejo.baseUrl} via 127.0.0.1:${toString modules.forgejo.httpPort}"
      modules.forgejo.stateDir
      "Scheduled Forgejo dumps enabled"
    )
    (service "Git Pages" modules.git-pages.enable gitPageDetails modules.git-pages.stateDir
      "Static sites synchronized from Git"
    )
    (service "Hermes Agent" modules.hermes-agent.enable "Telegram gateway; no published host port"
      modules.hermes-agent.stateDir
      "Containerized agent"
    )
    (service "Hermes WebUI" (modules.hermes-agent.enable && modules.hermes-agent.webUi.enable)
      "${modules.hermes-agent.webUi.publicUrl} via ${modules.hermes-agent.webUi.bindAddress}:${toString modules.hermes-agent.webUi.port}"
      "${modules.hermes-agent.stateDir}/.hermes/webui"
      "Community WebUI and native client backend; password authentication required"
    )
    (service "Home Assistant" modules.home-assistant.enable
      "Host network; firewall ${enabledDisabled modules.home-assistant.openFirewall}"
      modules.home-assistant.stateDir
      "Home automation"
    )
    (service "Immich" modules.immich.enable
      "${modules.immich.publicUrl} via ${modules.immich.bindAddress}:${toString modules.immich.port}"
      "${modules.immich.stateDir} (${modules.immich.dataset})"
      "Quota ${bytesAsGiB modules.immich.datasetQuotaBytes}; upload-managed library; Immich server, OpenVINO ML, PostgreSQL, and Valkey; Quick Sync; first-admin setup ${enabledDisabled modules.immich.allowSetup}; snapshot backup ${enabledDisabled modules.immich.backUpData}"
    )
    (service "Paperless-ngx" modules.paperless.enable
      "${modules.paperless.publicUrl} via ${modules.paperless.bindAddress}:${toString modules.paperless.port}"
      "${modules.paperless.stateDir} (${modules.paperless.dataset})"
      "Version ${modules.paperless.version}; quota ${bytesAsGiB modules.paperless.datasetQuotaBytes}; OCR ${modules.paperless.ocrLanguage}; French search stemming; Office conversion with Tika and Gotenberg; Pocket ID for normal login; exactly one password-capable native break-glass administrator; Pangolin-authenticated /admin; administrator-only public /share bearer links; ${toString modules.paperless.trashDelayDays}-day trash; snapshot backup ${enabledDisabled modules.paperless.backUpData}; scanner listener disabled"
    )
    (service "Newt" modules.newt.enable modules.newt.endpoint modules.newt.stateDir
      "Outbound Pangolin tunnel"
    )
    (service "Nextcloud AIO" modules.nextcloud.enable
      "Apache 127.0.0.1:${toString modules.nextcloud.mainPort}; admin 127.0.0.1:${toString modules.nextcloud.aioPort}"
      "Docker-managed volumes"
      "AIO manages its child containers"
    )
    (service "OpenCloud" modules.opencloud.enable
      "${modules.opencloud.publicUrl} via ${modules.opencloud.bindAddress}:${toString modules.opencloud.port}"
      "${modules.opencloud.stateDir} (${modules.opencloud.dataset})"
      "Non-collaborative PosixFS; personal quota ${bytesAsGiB modules.opencloud.personalQuotaBytes}; planned Family space ${bytesAsGiB modules.opencloud.familyQuotaBytes}; snapshot backup ${enabledDisabled modules.opencloud.backUpData}"
    )
    (service "Ollama" modules.ollama.enable
      "Port ${toString modules.ollama.port}; firewall ${enabledDisabled modules.ollama.openFirewall}"
      modules.ollama.stateDir
      "Local model service"
    )
    (service "Pangolin" modules.pangolin.enable "Docker-published edge ports" modules.pangolin.stateDir
      "Gerbil, Pangolin, and Traefik"
    )
    (service "Pelican Panel" modules.pelican.panel.enable
      "${modules.pelican.panel.appUrl} via 127.0.0.1:${toString modules.pelican.panel.port}"
      modules.pelican.panel.stateDir
      "Containerized panel"
    )
    (service "Pelican Wings" modules.pelican.wings.enable
      "${config.services.wings.node.remote}; API ${toString modules.pelican.wings.port}; firewall ${enabledDisabled modules.pelican.wings.openFirewall}"
      modules.pelican.wings.stateDir
      "Node identity and token values omitted"
    )
    (service "Plex" modules.plex.enable
      "NixOS Plex ports; firewall ${enabledDisabled modules.plex.openFirewall}"
      modules.plex.dataDir
      "Hardware transcoding ${enabledDisabled modules.plex.hardwareTranscoding}"
    )
    (service "Pocket ID" modules.pocket-id.enable
      "${modules.pocket-id.appUrl} via 127.0.0.1:${toString modules.pocket-id.port}"
      modules.pocket-id.stateDir
      "Identity provider"
    )
    (service "qBittorrent" modules.torrent.enable
      "${modules.torrent.bindAddress}:${toString modules.torrent.webUiPort}; firewall ${enabledDisabled modules.torrent.openFirewall}"
      "${modules.torrent.stateDir}; downloads ${modules.torrent.downloadDir}"
      "VPN LAN ${modules.torrent.lanNetwork}; port forwarding ${enabledDisabled modules.torrent.portForwarding}"
    )
    (service "Steam" modules.steam.enable
      "Remote Play firewall ${enabledDisabled modules.steam.remotePlay}; dedicated server firewall ${enabledDisabled modules.steam.dedicatedServer}"
      "-"
      "Gaming service"
    )
    (service "Sunshine" modules.sunshine.enable
      "Moonlight firewall ${enabledDisabled modules.sunshine.openFirewall}"
      "-"
      "Game streaming"
    )
    (service "WebDAV (SFTPGo)" modules.webdav.enable
      "${modules.webdav.bindAddress}:${toString modules.webdav.port}; firewall closed"
      modules.webdav.dataDir
      "GrapheneOS backup target; Borgmatic coverage ${enabledDisabled modules.webdav.backUpData}"
    )
    (service "YubiKey" modules.yubikey.enable "Local hardware" "-" "Authentication support")
  ];

  serviceRows = map (entry: [
    entry.name
    entry.access
    entry.state
    entry.notes
  ]) configuredServices;

  formatPortRange =
    range:
    if range.from == range.to then
      toString range.from
    else
      "${toString range.from}-${toString range.to}";
  tcpPorts =
    (map toString config.networking.firewall.allowedTCPPorts)
    ++ (map formatPortRange config.networking.firewall.allowedTCPPortRanges);
  udpPorts =
    (map toString config.networking.firewall.allowedUDPPorts)
    ++ (map formatPortRange config.networking.firewall.allowedUDPPortRanges);

  immichComposeContainers = [
    {
      name = "immich_server";
      image = modules.immich.serverImage;
      ports = [ "${modules.immich.bindAddress}:${toString modules.immich.port}:2283/tcp" ];
    }
    {
      name = "immich_machine_learning";
      image = modules.immich.machineLearningImage;
      ports = [ ];
    }
    {
      name = "immich_redis";
      image = modules.immich.valkeyImage;
      ports = [ ];
    }
    {
      name = "immich_postgres";
      image = modules.immich.databaseImage;
      ports = [ ];
    }
  ];
  enabledImmichComposeContainers = optionals modules.immich.enable immichComposeContainers;
  paperlessComposeContainers = [
    {
      name = "paperless_webserver";
      image = modules.paperless.paperlessImage;
      ports = [ "${modules.paperless.bindAddress}:${toString modules.paperless.port}:8000/tcp" ];
    }
    {
      name = "paperless_postgres";
      image = modules.paperless.databaseImage;
      ports = [ ];
    }
    {
      name = "paperless_broker";
      image = modules.paperless.valkeyImage;
      ports = [ ];
    }
    {
      name = "paperless_gotenberg";
      image = modules.paperless.gotenbergImage;
      ports = [ ];
    }
    {
      name = "paperless_tika";
      image = modules.paperless.tikaImage;
      ports = [ ];
    }
  ];
  enabledPaperlessComposeContainers = optionals modules.paperless.enable paperlessComposeContainers;
  enabledComposeContainers = enabledImmichComposeContainers ++ enabledPaperlessComposeContainers;
  containerRows =
    mapAttrsToList (name: container: [
      name
      container.image
      (codeList container.ports)
      (codeList (filter (option: hasPrefix "--network=" option) container.extraOptions))
    ]) config.virtualisation.oci-containers.containers
    ++ map (container: [
      container.name
      container.image
      (codeList container.ports)
      (codeList [ "Compose private network" ])
    ]) enabledComposeContainers;

  publishedContainerPorts =
    concatLists (
      mapAttrsToList (_: container: container.ports) config.virtualisation.oci-containers.containers
    )
    ++ concatLists (map (container: container.ports) enabledComposeContainers);
  nonLoopbackContainerPorts = filter (
    port: !(hasPrefix "127.0.0.1:" port || hasPrefix "[::1]:" port)
  ) publishedContainerPorts;
  unpinnedContainers =
    mapAttrsToList (name: _: name) (
      lib.filterAttrs (
        _: container: !(hasInfix "@sha256:" container.image)
      ) config.virtualisation.oci-containers.containers
    )
    ++ map (container: container.name) (
      filter (container: !(hasInfix "@sha256:" container.image)) enabledComposeContainers
    );

  fileSystemRows = mapAttrsToList (mountPoint: fileSystem: [
    mountPoint
    fileSystem.device
    fileSystem.fsType
    (codeList fileSystem.options)
    (yesNo fileSystem.neededForBoot)
  ]) config.fileSystems;
  zfsFileSystems = filter (fileSystem: fileSystem.fsType == "zfs") (
    mapAttrsToList (_: value: value) config.fileSystems
  );

  persistenceRoot = "/nix/persist";
  persistence = config.environment.persistence.${persistenceRoot};
  persistenceDirectories = sort builtins.lessThan (
    unique (map (entry: if isString entry then entry else entry.directory) persistence.directories)
  );
  persistenceFiles = sort builtins.lessThan (
    unique (map (entry: if isString entry then entry else entry.file) persistence.files)
  );

  backupSources = sort builtins.lessThan (unique modules.backup.dirs);
  immichSnapshotPath = "${modules.immich.stateDir}/.zfs/snapshot/${modules.immich.backupSnapshotName}";
  opencloudSnapshotPath = "${modules.opencloud.stateDir}/.zfs/snapshot/${modules.opencloud.backupSnapshotName}";
  paperlessSnapshotPath = "${modules.paperless.stateDir}/.zfs/snapshot/${modules.paperless.backupSnapshotName}";
  sqliteDatabases = config.services.borgmatic.settings.sqlite_databases or [ ];
  sqliteRows = map (database: [
    database.name
    database.path
  ]) sqliteDatabases;
  backupChecks = config.services.borgmatic.settings.checks or [ ];

  secretNames = attrNames config.services.onepassword-secrets.secrets;
  normalUsers = mapAttrsToList (name: _: name) (
    lib.filterAttrs (_: user: user.isNormalUser) config.users.users
  );

  bootLoaders = filter (value: value != null) [
    (if config.boot.loader.grub.enable then "GRUB" else null)
    (if config.boot.loader.systemd-boot.enable then "systemd-boot" else null)
    (if config.boot.loader.generic-extlinux-compatible.enable then "generic extlinux" else null)
  ];

  warnings =
    optional (!modules.backup.enable && backupSources != [ ])
      "Backup sources are registered, but Borgmatic is disabled; those sources are not actively backed up."
    ++ optional (!modules.backup.enable) "No Borgmatic backup job is enabled for this host."
    ++ optional (
      zfsFileSystems != [ ] && config.networking.hostId == ""
    ) "ZFS filesystems are configured without a networking host ID."
    ++
      optional (nonLoopbackContainerPorts != [ ])
        "Docker publishes non-loopback ports: ${concatStringsSep ", " nonLoopbackContainerPorts}. Review these separately from the NixOS firewall allowlists."
    ++
      optional (unpinnedContainers != [ ])
        "Containers without digest-pinned images: ${concatStringsSep ", " unpinnedContainers}. This can be intentional for self-updating services."
    ++ optional config.boot.initrd.network.ssh.enable "Initrd SSH is enabled on port ${toString config.boot.initrd.network.ssh.port}; preserve its persistent host key and recovery authorization."
    ++
      optional (modules.torrent.enable && modules.torrent.lanNetwork == "192.168.1.0/24")
        "qBittorrent uses the default VPN LAN allowlist 192.168.1.0/24; verify that it matches the host's real LAN."
    ++
      optional
        (modules.nextcloud.enable && !(lib.any (source: hasPrefix "/var/lib/docker" source) backupSources))
        "Nextcloud AIO uses Docker-managed storage that is not directly present in the Borgmatic source list."
    ++ optional (
      modules.plex.enable
      && !(lib.any (
        source: hasPrefix modules.plex.dataDir source || hasPrefix source modules.plex.dataDir
      ) backupSources)
    ) "Plex data is not present in the Borgmatic source list."
    ++ optional (
      modules.opencloud.enable
      && modules.opencloud.backUpData
      && !(lib.elem opencloudSnapshotPath backupSources)
    ) "OpenCloud snapshot data is not present in the Borgmatic source list."
    ++ optional (
      modules.opencloud.enable && !modules.opencloud.backUpData
    ) "OpenCloud state is not included in Borgmatic backups."
    ++ optional (
      modules.immich.enable && modules.immich.backUpData && !(lib.elem immichSnapshotPath backupSources)
    ) "Immich snapshot data is not present in the Borgmatic source list."
    ++ optional (
      modules.immich.enable && !modules.immich.backUpData
    ) "Immich state is not included in Borgmatic backups."
    ++ optional (
      modules.immich.enable
      && !(lib.elem modules.immich.bindAddress [
        "127.0.0.1"
        "[::1]"
      ])
    ) "Immich is not bound to host loopback."
    ++
      optional (modules.immich.enable && modules.immich.allowSetup)
        "Immich first-administrator setup is enabled; keep the service loopback-only and disable setup immediately after bootstrap."
    ++ optional (
      modules.paperless.enable
      && modules.paperless.backUpData
      && !(lib.elem paperlessSnapshotPath backupSources)
    ) "Paperless snapshot data is not present in the Borgmatic source list."
    ++ optional (
      modules.paperless.enable && !modules.paperless.backUpData
    ) "Paperless state is not included in Borgmatic backups."
    ++ optional (
      modules.paperless.enable
      && !(lib.elem modules.paperless.bindAddress [
        "127.0.0.1"
        "[::1]"
      ])
    ) "Paperless is not bound to host loopback.";

  revisionLine = if revision == null then "" else "\nFlake revision: `${revision}`.\n";

  markdown = ''
    # ${hostName}

    This file is generated from the evaluated NixOS configuration. Do not edit
    the build output manually; change the host or module configuration instead.
    ${revisionLine}
    ## System

    ${markdownTable
      [ "Setting" "Value" ]
      [
        [
          "Hostname"
          hostName
        ]
        [
          "Platform"
          config.nixpkgs.hostPlatform.system
        ]
        [
          "NixOS state version"
          config.system.stateVersion
        ]
        [
          "Time zone"
          config.time.timeZone
        ]
        [
          "Enabled profiles"
          (codeList enabledProfiles)
        ]
        [
          "Enabled modules"
          (codeList enabledModules)
        ]
        [
          "Normal users"
          (codeList normalUsers)
        ]
        [
          "Mutable users"
          (yesNo config.users.mutableUsers)
        ]
      ]
    }

    ## Configured services

    ${
      if serviceRows == [ ] then
        "_None._\n"
      else
        markdownTable [ "Service" "Access or endpoint" "State" "Notes" ] serviceRows
    }

    ## Network exposure

    ${markdownTable
      [ "Setting" "Value" ]
      [
        [
          "NixOS firewall"
          (enabledDisabled config.networking.firewall.enable)
        ]
        [
          "Allowed TCP ports/ranges"
          (codeList tcpPorts)
        ]
        [
          "Allowed UDP ports/ranges"
          (codeList udpPorts)
        ]
        [
          "SSH ports"
          (codeList (map toString config.services.openssh.ports))
        ]
        [
          "SSH password authentication"
          (enabledDisabled config.services.openssh.settings.PasswordAuthentication)
        ]
        [
          "SSH keyboard-interactive authentication"
          (enabledDisabled config.services.openssh.settings.KbdInteractiveAuthentication)
        ]
        [
          "SSH root login"
          config.services.openssh.settings.PermitRootLogin
        ]
        [
          "NetworkManager"
          (enabledDisabled config.networking.networkmanager.enable)
        ]
        [
          "systemd-networkd"
          (enabledDisabled config.systemd.network.enable)
        ]
        [
          "Name servers"
          (codeList config.networking.nameservers)
        ]
      ]
    }

    ### OCI containers

    ${
      if containerRows == [ ] then
        "_None._\n"
      else
        markdownTable [ "Container" "Image" "Published ports" "Network mode" ] containerRows
    }

    ## Storage and boot

    ${markdownTable
      [ "Setting" "Value" ]
      [
        [
          "Boot loader"
          (orNone bootLoaders)
        ]
        [
          "EFI variable access"
          (yesNo config.boot.loader.efi.canTouchEfiVariables)
        ]
        [
          "ZFS host ID"
          (if config.networking.hostId == "" then "_None._" else code config.networking.hostId)
        ]
        [
          "Force-import ZFS root"
          (yesNo config.boot.zfs.forceImportRoot)
        ]
        [
          "Zram swap"
          (enabledDisabled config.zramSwap.enable)
        ]
        [
          "Swap devices"
          (codeList (map (swap: swap.device) config.swapDevices))
        ]
        [
          "Initrd SSH"
          (
            if config.boot.initrd.network.ssh.enable then
              "port ${code config.boot.initrd.network.ssh.port}"
            else
              "disabled"
          )
        ]
      ]
    }

    ### Filesystems

    ${markdownTable [ "Mount point" "Device" "Type" "Options" "Needed for boot" ] fileSystemRows}

    ## Persistence

    Persistence root: `${persistenceRoot}`.

    ### Directories

    ${bulletList (map code persistenceDirectories)}

    ### Files

    ${bulletList (map code persistenceFiles)}

    Persistence keeps state across ephemeral-root reboots. It does not imply
    that the same state is included in a backup.

    ## Backups

    ${markdownTable
      [ "Setting" "Value" ]
      [
        [
          "Borgmatic"
          (enabledDisabled modules.backup.enable)
        ]
        [
          "Storage Box account"
          (if modules.backup.enable then code modules.backup.hetznerStorageBoxAccount else "_None._")
        ]
        [
          "Daily retention"
          (if modules.backup.enable then toString config.services.borgmatic.settings.keep_daily else "-")
        ]
        [
          "Weekly retention"
          (if modules.backup.enable then toString config.services.borgmatic.settings.keep_weekly else "-")
        ]
        [
          "Monthly retention"
          (if modules.backup.enable then toString config.services.borgmatic.settings.keep_monthly else "-")
        ]
        [
          "Checks"
          (
            if modules.backup.enable then
              concatStringsSep ", " (map (check: "${check.name}: ${check.frequency}") backupChecks)
            else
              "-"
          )
        ]
      ]
    }

    ### Source directories

    ${bulletList (map code backupSources)}

    ### SQLite databases

    ${if sqliteRows == [ ] then "_None._\n" else markdownTable [ "Name" "Path" ] sqliteRows}

    ## Secret inventory

    Only secret option names are included; references, generated paths, and
    values are deliberately omitted.

    ${bulletList (map code secretNames)}

    ## Generated observations

    ${bulletList warnings}

    ## Operations

    Validate and deploy this host:

    ```sh
    nix flake check --no-build --all-systems
    nix build .#nixosConfigurations.${hostName}.config.system.build.toplevel
    sudo shulker-rebuild dry-activate --flake .#${hostName}
    sudo shulker-rebuild test --flake .#${hostName}
    sudo shulker-rebuild switch --flake .#${hostName}
    ```

    Inspect the running host:

    ```sh
    systemctl --failed
    systemctl status opnix-secrets.service sshd.service
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    sudo ss -lntup
    ```

    ${
      if modules.immich.enable then
        ''
          Inspect Immich and run its declarative checks:

          ```sh
          sudo systemctl status immich-compose.service --no-pager
          sudo systemctl start immich-health-check.service
          sudo systemctl start immich-schema-check.service
          curl --fail http://${modules.immich.bindAddress}:${toString modules.immich.port}/api/server/ping
          ```

          Immich's off-host backup source is `${immichSnapshotPath}`. Follow the
          repository README for the guarded bootstrap and disposable restore
          rehearsal.
        ''
      else
        ""
    }

    ${
      if modules.paperless.enable then
        ''
          Inspect Paperless and run its declarative checks:

          ```sh
          sudo systemctl status paperless-compose.service --no-pager
          sudo systemctl start paperless-health-check.service
          sudo systemctl start paperless-schema-check.service
          sudo paperless-list-users
          sudo paperless-logical-backup
          sudo paperless-pre-upgrade-export
          curl --fail http://${modules.paperless.bindAddress}:${toString modules.paperless.port}/
          ```

          Paperless's off-host backup source is `${paperlessSnapshotPath}`.
          Portable exports are written under `${modules.paperless.stateDir}/export/current`
          and require Paperless ${modules.paperless.version} for import. Normal login
          uses Pocket ID; exactly one password-capable native break-glass
          administrator is retained; Pangolin-authenticated /admin protects
          recovery; and administrator-only public /share bearer links are enabled.
          The scanner listener remains intentionally disabled. Follow the repository
          README for bootstrap, Fastmail routing, path-rule ordering, and isolated
          restore rehearsal.
        ''
      else
        ""
    }

    Roll back the active system profile:

    ```sh
    sudo nixos-rebuild switch --rollback
    ```
  '';
in
pkgs.writeTextDir "${hostName}.md" markdown
