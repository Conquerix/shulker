{
  data,
  infrastructureDiagram,
  lib,
  pkgs,
}:

let
  inherit (builtins)
    concatLists
    length
    map
    toString
    ;
  inherit (lib)
    concatMapStringsSep
    concatStringsSep
    filter
    findFirst
    sort
    unique
    ;

  escapeCell = value: lib.replaceStrings [ "|" "\n" ] [ "\\|" "<br>" ] (toString value);
  code = value: "`${escapeCell value}`";
  yesNo = value: if value then "yes" else "no";
  orNone = values: if values == [ ] then "_None._" else concatStringsSep ", " values;
  codeList = values: orNone (map code values);
  markdownTable =
    headers: rows:
    let
      renderRow = row: "| ${concatStringsSep " | " (map escapeCell row)} |\n";
    in
    renderRow headers + renderRow (map (_: "---") headers) + concatMapStringsSep "" renderRow rows;

  hosts = sort (left: right: left.name < right.name) data.hosts;
  serverHosts = filter (host: host.kind == "server") hosts;
  desktopHosts = filter (host: host.kind == "desktop") hosts;
  darwinHosts = filter (host: host.kind == "darwin") hosts;

  hostLink = host: "[${host.name}](Host-${host.name})";
  findHost = name: findFirst (host: host.name == name) null hosts;
  hostLinkByName = name: hostLink (findHost name);

  allServices = concatLists (
    map (
      host:
      map (
        service:
        service
        // {
          hostName = host.name;
        }
      ) host.services
    ) hosts
  );
  serviceKeys = sort builtins.lessThan (unique (map (service: service.key) allServices));
  serviceByKey = key: findFirst (service: service.key == key) null allServices;
  serviceInstances = key: filter (service: service.key == key) allServices;
  serviceEndpoints =
    key:
    unique (
      filter (endpoint: endpoint != null && endpoint != "") (
        map (service: service.endpoint) (serviceInstances key)
      )
    );
  endpointLink =
    endpoint:
    if lib.hasPrefix "https://" endpoint || lib.hasPrefix "http://" endpoint then
      "[${lib.removePrefix "https://" (lib.removePrefix "http://" endpoint)}](${endpoint})"
    else
      code endpoint;

  connectionInstances = concatLists (
    map (
      host:
      map (
        connection:
        connection
        // {
          hostName = host.name;
          serviceName =
            let
              service = findFirst (candidate: candidate.key == connection.from) null host.services;
            in
            if service == null then connection.from else service.name;
        }
      ) host.connections
    ) hosts
  );

  pangolin =
    data.external.pangolin or {
      collectedAt = null;
      domains = [ ];
      resources = [ ];
      sites = [ ];
    };
  pangolinDomains = pangolin.domains or [ ];
  pangolinResources = pangolin.resources or [ ];
  pangolinSites = pangolin.sites or [ ];
  onlineSites = filter (site: site.online or false) pangolinSites;
  findSite =
    reference:
    findFirst (site: (site.id or "") == reference || site.name == reference) null pangolinSites;
  siteName =
    reference:
    let
      site = findSite reference;
    in
    if site == null then code reference else site.name;

  revisionText = if data.revision or null == null then "working tree" else code data.revision;
  collectionText =
    if pangolin.collectedAt or null == null then "not collected" else code pangolin.collectedAt;

  hostRows = map (host: [
    (hostLink host)
    host.kind
    (code host.platform)
    (codeList host.profiles)
    (toString (length host.modules))
    (toString (length host.services))
  ]) hosts;

  serverRows = map (
    host:
    let
      serviceKeysForHost = map (service: service.key) host.services;
    in
    [
      (hostLink host)
      (code host.platform)
      (orNone (map (service: service.name) host.services))
      (yesNo (builtins.elem "backup" serviceKeysForHost))
      (yesNo (builtins.elem "beszel-agent" serviceKeysForHost))
    ]
  ) serverHosts;

  serviceRows = map (
    key:
    let
      service = serviceByKey key;
      instances = serviceInstances key;
    in
    [
      service.name
      service.category
      (concatStringsSep ", " (map (instance: hostLinkByName instance.hostName) instances))
      (orNone (map endpointLink (serviceEndpoints key)))
    ]
  ) serviceKeys;

  serviceCoverageRows = map (host: [
    (hostLink host)
    (orNone (map (service: service.name) host.services))
  ]) hosts;

  connectionRows = map (connection: [
    (hostLinkByName connection.hostName)
    connection.serviceName
    connection.relation
    (endpointLink connection.to)
  ]) connectionInstances;

  siteRows = map (site: [
    site.name
    (site.type or "unknown")
    (if site.online or false then "online" else "offline or unknown")
  ]) pangolinSites;

  resourceRows = map (resource: [
    (
      if lib.hasPrefix "http" (resource.protocol or "") then
        "[${resource.domain}](${resource.protocol}://${resource.domain})"
      else
        code resource.domain
    )
    resource.name
    (resource.protocol or "unknown")
    (yesNo (resource.enabled or true))
    (orNone (map siteName (resource.sites or [ ])))
  ]) pangolinResources;

  domainRows = map (domain: [
    domain.domain
    (domain.type or "unknown")
    (yesNo (domain.verified or false))
  ]) pangolinDomains;

  home = ''
    # Shulker infrastructure

    This Wiki is the generated operations and architecture guide for the
    infrastructure managed by the Shulker Nix flake. Start with the fleet or
    service catalog, then use the detailed host reports for machine-level work.

    ## At a glance

    | Area | Current state |
    | --- | ---: |
    | Managed hosts | ${toString (length hosts)} |
    | NixOS servers | ${toString (length serverHosts)} |
    | NixOS desktops | ${toString (length desktopHosts)} |
    | Darwin hosts | ${toString (length darwinHosts)} |
    | Configured service instances | ${toString (length allServices)} |
    | Pangolin sites online | ${toString (length onlineSites)} / ${toString (length pangolinSites)} |
    | Published Pangolin resources | ${toString (length pangolinResources)} |

    ## Browse the documentation

    | Page | Use it for |
    | --- | --- |
    | [Fleet](Fleet) | Every managed machine, role, platform, profile, and report |
    | [Services](Services) | Service ownership, placement, endpoints, and dependencies |
    | [Public services](Public-Services) | Sanitized Pangolin sites, domains, and published resources |
    | [Infrastructure topology](Infrastructure) | Management and public-access diagrams |
    | [Servers](Servers) | Detailed evaluated reports for server-profile hosts |
    | [Operations](Operations) | Validation, deployment, health checks, backups, and rollback |
    | [Automation](Automation) | Documentation pipeline and GitHub Actions routines |

    ## Source of truth

    Host and service facts come from the evaluated NixOS and nix-darwin
    configurations. Public routing facts come from the sanitized Pangolin
    collector. Generated pages should be changed through
    [Conquerix/shulker](https://github.com/Conquerix/shulker), not edited in the
    Wiki.

    Flake revision: ${revisionText}. Pangolin snapshot: ${collectionText}.
  '';

  fleet = ''
    # Fleet

    The fleet inventory includes every evaluated NixOS and nix-darwin host,
    including machines that do not use the server profile.

    ${markdownTable [ "Host" "Role" "Platform" "Profiles" "Modules" "Services" ] hostRows}

    ## Reading the inventory

    - Every host name links to its detailed evaluated report.
    - Profiles describe broad machine roles; modules are reusable capabilities.
    - Service placement and cross-host dependencies are expanded in the
      [service catalog](Services).
    - Public ingress is documented separately under [public services](Public-Services).
  '';

  servers = ''
    # Servers

    These hosts enable the reusable NixOS server profile. Each report contains
    evaluated service, exposure, storage, persistence, backup, secret-name,
    warning, and recovery information.

    ${markdownTable [ "Server" "Platform" "Services" "Backups" "Monitoring" ] serverRows}

    Use [Fleet](Fleet) for desktops and Darwin machines, or [Operations](Operations)
    for the shared validation and deployment workflow.
  '';

  services = ''
    # Service catalog

    This catalog answers where a service runs and which configured endpoint it
    uses. Public exposure is not implied; consult [Public services](Public-Services)
    and the host's network-exposure report before treating an endpoint as public.

    ## Catalog

    ${markdownTable [ "Service" "Category" "Hosts" "Configured endpoints" ] serviceRows}

    ## Host coverage

    ${markdownTable [ "Host" "Services" ] serviceCoverageRows}

    ## Cross-host dependencies

    ${
      if connectionRows == [ ] then
        "_None._\n"
      else
        markdownTable [ "Source host" "Service" "Relation" "Destination" ] connectionRows
    }
  '';

  publicServices = ''
    # Public services

    This page is generated from the sanitized Pangolin Integration API snapshot.
    It intentionally documents public routing without publishing internal target
    addresses, ports, private resources, policies, identities, or credentials.

    Snapshot: ${collectionText}.

    ## Sites

    ${
      if siteRows == [ ] then
        "_No Pangolin snapshot is available._\n"
      else
        markdownTable [ "Site" "Type" "Status" ] siteRows
    }

    ## Published resources

    ${
      if resourceRows == [ ] then
        "_No public resources were collected._\n"
      else
        markdownTable [ "Public endpoint" "Resource" "Protocol" "Enabled" "Sites" ] resourceRows
    }

    ## Managed domains

    ${
      if domainRows == [ ] then
        "_No domains were collected._\n"
      else
        markdownTable [ "Domain" "Type" "Verified" ] domainRows
    }

    See [Infrastructure topology](Infrastructure) for the resource-to-site flow.
  '';

  operations = ''
    # Operations

    Use this as the fleet-level runbook. Host-specific storage, service, warning,
    and recovery details remain in the reports linked from [Fleet](Fleet).

    ## Safe change sequence

    1. Inspect the relevant host, profile, and module configuration.
    2. Evaluate the full flake before building or deploying.
    3. Dry-activate, test, and only then switch the selected host.
    4. Verify the evaluated change against runtime state.

    ```sh
    nix flake check --no-build --all-systems
    nix build .#nixosConfigurations.<host>.config.system.build.toplevel
    sudo shulker-rebuild dry-activate --flake .#<host>
    sudo shulker-rebuild test --flake .#<host>
    sudo shulker-rebuild switch --flake .#<host>
    ```

    Before restarting a gaming host, do not interrupt an active game:

    ```sh
    pgrep -f 'steamapps/[c]ommon'
    ```

    ## Health checks

    ```sh
    systemctl --failed
    systemctl status opnix-secrets.service sshd.service
    docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'
    sudo ss -lntup
    ```

    ## Backups

    ```sh
    sudo borgmatic check --force
    sudo borgmatic repo-list
    ```

    Restore files into a fresh temporary directory first. Database restoration
    is separate and destructive; validate the extracted backup before changing
    a live database.

    ## Rollback

    ```sh
    sudo nixos-rebuild switch --rollback
    ```

    Immutable users, declarative password hashes, persistent SSH host keys, and
    independent SSH recovery keys are part of the recovery model. Do not weaken
    those controls as incidental cleanup.
  '';

  automation = ''
    # Automation

    GitHub Actions validates the flake, maintains dependencies, and republishes
    this Wiki from evaluated configuration and sanitized external data.

    | Routine | Trigger | Result |
    | --- | --- | --- |
    | [Checks](https://github.com/Conquerix/shulker/actions/workflows/check.yml) | Push and pull request | Evaluates the flake, runs checks, builds reports, uploads artifacts |
    | [Publish infrastructure Wiki](https://github.com/Conquerix/shulker/actions/workflows/wiki.yml) | Relevant push, weekly schedule, manual | Refreshes Pangolin data and synchronizes generated Wiki pages |
    | [Update flake inputs](https://github.com/Conquerix/shulker/actions/workflows/update-flake.yml) | Weekly schedule, manual | Opens or refreshes a validated dependency-update pull request |
    | [Check Paperless-ngx release](https://github.com/Conquerix/shulker/actions/workflows/check-paperless-release.yml) | Weekly schedule, manual | Opens or refreshes one marked review issue when upstream is newer; never deploys |
    | Dependabot | Weekly | Groups pinned GitHub Action updates into pull requests |

    ## Documentation pipeline

    ```mermaid
    flowchart LR
      nix[Evaluated Nix configurations] --> inventory[Infrastructure inventory]
      pangolin[Pangolin Integration API] --> sanitize[Sanitized public snapshot]
      inventory --> pages[Generated Wiki pages]
      sanitize --> pages
      reports[Per-host evaluated reports] --> sync[Wiki synchronizer]
      pages --> sync
      sync --> wiki[GitHub Wiki]
    ```

    ## Build locally

    ```sh
    nix build .#host-docs
    nix build .#infrastructure-data
    nix build .#infrastructure-diagram
    nix build .#wiki-docs
    ```

    Pangolin enrichment uses repository variables `PANGOLIN_API_ENDPOINT` and
    `PANGOLIN_ORG_ID`, plus the secret `PANGOLIN_TOPOLOGY_API_KEY`. Secret values
    and raw API responses are never published.
  '';

  sidebar = ''
    ## Shulker

    - [Overview](Home)
    - **Infrastructure**
      - [Fleet](Fleet)
      - [Services](Services)
      - [Public services](Public-Services)
      - [Topology](Infrastructure)
    - **Operations**
      - [Runbook](Operations)
      - [Automation](Automation)
    - **Host reports**
      - _Servers_
    ${concatMapStringsSep "\n" (host: "    - [${host.name}](Host-${host.name})") serverHosts}
      - _Other hosts_
    ${concatMapStringsSep "\n" (host: "    - [${host.name}](Host-${host.name})") (
      desktopHosts ++ darwinHosts
    )}

    [Source repository](https://github.com/Conquerix/shulker)
  '';

  footer = ''
    Generated from [Conquerix/shulker](https://github.com/Conquerix/shulker) at ${revisionText}. Pangolin snapshot: ${collectionText}.
  '';

  files = {
    "Home.md" = pkgs.writeText "Home.md" home;
    "Fleet.md" = pkgs.writeText "Fleet.md" fleet;
    "Servers.md" = pkgs.writeText "Servers.md" servers;
    "Services.md" = pkgs.writeText "Services.md" services;
    "Public-Services.md" = pkgs.writeText "Public-Services.md" publicServices;
    "Operations.md" = pkgs.writeText "Operations.md" operations;
    "Automation.md" = pkgs.writeText "Automation.md" automation;
    "_Sidebar.md" = pkgs.writeText "_Sidebar.md" sidebar;
    "_Footer.md" = pkgs.writeText "_Footer.md" footer;
  };
in
pkgs.runCommand "wiki-docs" { } ''
  mkdir -p "$out"
  ${concatMapStringsSep "\n" (name: "cp ${files.${name}} \"$out/${name}\"") (
    builtins.attrNames files
  )}
  cp ${infrastructureDiagram}/Infrastructure.md "$out/Infrastructure.md"
  cp ${infrastructureDiagram}/infrastructure.json "$out/infrastructure.json"
''
