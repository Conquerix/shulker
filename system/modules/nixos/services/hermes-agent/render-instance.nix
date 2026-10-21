# Pure shared renderer used for every enabled instance and by structural checks.
{
  lib,
  pkgs,
  config,
}:
name: instance:
let
  i = instance;
  unit = "docker-${i.containerName}";
  runtime = "${i.containerName}-managed";
  managed = "/run/${runtime}";
  env = "${managed}/current/.env";
  secretName =
    label:
    "hermes"
    + lib.concatMapStrings (
      part: lib.toUpper (builtins.substring 0 1 part) + builtins.substring 1 (-1) part
    ) (lib.splitString "-" "${name}-${label}");
  secretPath = label: config.services.onepassword-secrets.secrets.${secretName label}.path;
  policy = lib.optionalAttrs i.discord.enable {
    DISCORD_ALLOWED_USERS = lib.concatStringsSep "," i.discord.allowedUsers;
    DISCORD_ALLOW_ALL_USERS = "false";
    DISCORD_REQUIRE_MENTION = "true";
    DISCORD_ALLOW_BOTS = "none";
  };
  secrets =
    lib.mapAttrs' (
      label: source:
      lib.nameValuePair (secretName label) {
        inherit (source) reference;
        services = [ unit ];
        mode = "0400";
      }
    ) i.credentials
    // lib.optionalAttrs i.serviceAccount.enable {
      ${secretName "service-account"} = {
        reference = i.serviceAccount.reference;
        services = [ unit ];
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };
    }
    // lib.optionalAttrs i.hostAdministration.enable {
      ${secretName "host-key"} = {
        reference = i.hostAdministration.privateKeyReference;
        services = [ unit ];
        mode = "0400";
      };
    };
  manifest = pkgs.writeText "${i.containerName}-credentials.json" (
    builtins.toJSON {
      environment = lib.mapAttrsToList (label: source: {
        inherit label;
        path = secretPath label;
        inherit (source) requiredKeys;
      }) i.credentials;
      sshKey = if i.hostAdministration.enable then secretPath "host-key" else null;
      inherit policy;
      owner = [
        config.users.users.hermes.uid
        config.users.groups.hermes.gid
      ];
    }
  );
  initial = pkgs.writeText "${i.containerName}-initial.json" (builtins.toJSON i.initial);
  opWrapper = pkgs.writeTextFile {
    name = "${i.containerName}-op";
    executable = true;
    text = ''
      #!/bin/sh
      set -eu
      OP_SERVICE_ACCOUNT_TOKEN="$(cat /run/overseer-op-token)"
      export OP_SERVICE_ACCOUNT_TOKEN
      exec /run/overseer-tools/op "$@"
    '';
  };
  sshConfig = pkgs.writeText "${i.containerName}-ssh-config" ''
    Host shulker
      HostName shulker-host
      HostKeyAlias shulker-host
      User ${i.hostAdministration.user}
      IdentityFile /run/hermes-host-key
      UserKnownHostsFile /etc/hermes-host-known-hosts
      StrictHostKeyChecking yes
      BatchMode yes
      IdentitiesOnly yes
      IdentityAgent none
      ForwardAgent no
      RequestTTY no
      ConnectTimeout 10
  '';
  knownHosts = pkgs.writeText "${i.containerName}-known-hosts" "shulker-host ${i.hostAdministration.hostPublicKey}\n";
in
{
  inherit secrets;
  secretNames = map secretName (
    builtins.attrNames i.credentials
    ++ lib.optional i.serviceAccount.enable "service-account"
    ++ lib.optional i.hostAdministration.enable "host-key"
  );
  container = {
    image = i.image;
    pull = "missing";
    cmd = [
      "gateway"
      "run"
    ];
    ports = lib.optional i.dashboard.enable "127.0.0.1:${toString i.dashboard.port}:9119";
    volumes = [
      "${i.stateDir}/data:/opt/data:rw"
      "${i.stateDir}/workspace:/workspace:rw"
      "${env}:/etc/hermes/.env:ro"
    ]
    ++ lib.optionals i.serviceAccount.enable [
      "${secretPath "service-account"}:/run/overseer-op-token:ro"
      # Use the image's loader, not Nix's patched executable.
      "${pkgs._1password-cli.src}/op:/run/overseer-tools/op:ro"
      "${opWrapper}:/usr/local/bin/op:ro"
    ]
    ++ lib.optionals i.hostAdministration.enable [
      "${sshConfig}:/etc/ssh/ssh_config.d/90-overseer.conf:ro"
      "${knownHosts}:/etc/hermes-host-known-hosts:ro"
      "${managed}/current/host-key:/run/hermes-host-key:ro"
    ];
    environment = {
      HERMES_UID = "10000";
      HERMES_GID = "10000";
      HERMES_DASHBOARD = if i.dashboard.enable then "1" else "0";
      API_SERVER_ENABLED = if i.dashboard.enable then "true" else "false";
      TERMINAL_CWD = "/workspace";
      HERMES_WRITE_SAFE_ROOT = "/opt/data:/workspace";
    }
    // lib.optionalAttrs i.dashboard.enable {
      HERMES_DASHBOARD_HOST = "0.0.0.0";
      API_SERVER_HOST = "127.0.0.1";
    }
    // policy;
    environmentFiles = [ env ];
    extraOptions = [
      "--memory=4g"
      "--cpus=2"
      "--pids-limit=512"
    ]
    ++ lib.optional i.omniroute.enable "--network=omniroute"
    ++ lib.optional i.hostAdministration.enable "--add-host=shulker-host:host-gateway";
  };
  service = {
    path = [ pkgs.openssh ];
    serviceConfig = {
      RuntimeDirectory = runtime;
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "yes";
    };
    preStart = ''
      set -eu
      umask 077
      ${pkgs.python3}/bin/python3 ${./render-credentials.py} ${manifest} ${managed}
      ${pkgs.util-linux}/bin/runuser -u hermes -- \
        ${pkgs.python3}/bin/python3 ${./bootstrap.py} files ${initial} ${lib.escapeShellArg i.stateDir}
      ${lib.optionalString (i.initial.settings != { } || i.initial.plugins != [ ]) ''
        if [ ! -e ${i.stateDir}/data/config.yaml ] && [ ! -L ${i.stateDir}/data/config.yaml ]; then
          # Native CLI bootstrap in the pinned image, with no network or credentials.
          # Docker's generated pull step may run later; pull only the declared image.
          if ! ${pkgs.docker}/bin/docker image inspect ${lib.escapeShellArg i.image} >/dev/null 2>&1; then
            ${pkgs.docker}/bin/docker pull ${lib.escapeShellArg i.image}
          fi
          ${pkgs.docker}/bin/docker run --rm --pull=never --network=none \
            --user 10000:10000 --entrypoint python \
            -e HERMES_HOME=/opt/data -e HERMES_WRITE_SAFE_ROOT=/opt/data:/workspace \
            -v ${i.stateDir}/data:/opt/data:rw -v ${i.stateDir}/workspace:/workspace:rw \
            -v ${./bootstrap.py}:/run/hermes-bootstrap.py:ro \
            -v ${initial}:/run/hermes-initial.json:ro \
            ${lib.escapeShellArg i.image} /run/hermes-bootstrap.py native /run/hermes-initial.json /opt/data
        fi
      ''}
    '';
    requires = [
      "opnix-secrets.service"
    ]
    ++ lib.optional i.omniroute.enable "docker-network-omniroute.service";
    after = [
      "opnix-secrets.service"
    ]
    ++ lib.optional i.omniroute.enable "docker-network-omniroute.service";
    unitConfig.RequiresMountsFor = [ i.stateDir ];
  };
  tmpfiles = map (suffix: "d ${i.stateDir}${suffix} 0700 hermes hermes -") [
    ""
    "/data"
    "/workspace"
  ];
  persistence = {
    directory = i.stateDir;
    mode = "0700";
    user = "hermes";
    group = "hermes";
  };
}
