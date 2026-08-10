{
  data,
  lib,
  pkgs,
}:

let
  inherit (builtins)
    length
    map
    toJSON
    toString
    ;
  inherit (lib)
    concatMapStringsSep
    concatStringsSep
    filter
    findFirst
    unique
    ;

  safeId =
    value:
    concatStringsSep "" (
      map (character: if builtins.match "[A-Za-z0-9]" character != null then character else "_") (
        lib.stringToCharacters (toString value)
      )
    );
  escapeLabel = value: lib.replaceStrings [ "\"" "\n" "<" ">" ] [ "'" " " "(" ")" ] (toString value);
  displayEndpoint = endpoint: lib.removePrefix "https://" (lib.removePrefix "http://" endpoint);

  hostNodeId = host: "host_${safeId host.name}";
  endpointNodeId = endpoint: "endpoint_${safeId endpoint}";
  localHostNodeId = host: "local_host_${safeId host.name}";
  localServiceNodeId = host: service: "local_service_${safeId host.name}_${safeId service.key}";

  pangolin =
    data.external.pangolin or {
      collectedAt = null;
      domains = [ ];
      resources = [ ];
      sites = [ ];
    };
  pangolinResources = pangolin.resources or [ ];
  pangolinSites = pangolin.sites or [ ];

  endpointValues = unique (
    builtins.concatLists (map (host: map (connection: connection.to) host.connections) data.hosts)
  );

  renderHost =
    host:
    ''${hostNodeId host}["${escapeLabel host.name}<br/><small>${escapeLabel host.kind}</small>"]:::host'';

  renderEndpoint =
    endpoint: ''${endpointNodeId endpoint}["${escapeLabel (displayEndpoint endpoint)}"]:::external'';

  renderConnection =
    host: connection:
    let
      service = findFirst (candidate: candidate.key == connection.from) null host.services;
      serviceName = if service == null then connection.from else service.name;
    in
    ''${hostNodeId host} -. "${escapeLabel serviceName}: ${escapeLabel connection.relation}" .-> ${endpointNodeId connection.to}'';

  localComponentKeys =
    host:
    unique (
      builtins.concatLists (
        map (dependency: [
          dependency.from
          dependency.to
        ]) (host.dependencies or [ ])
      )
    );

  localService =
    host: key:
    let
      found = findFirst (service: service.key == key) null host.services;
    in
    if found == null then
      throw "Infrastructure dependency ${host.name}:${key} does not resolve to a local service."
    else
      found;

  renderLocalService =
    host: key:
    let
      service = localService host key;
    in
    ''${localServiceNodeId host service}["${escapeLabel service.name}"]:::component'';

  renderLocalDependency =
    host: dependency:
    let
      from = localService host dependency.from;
      to = localService host dependency.to;
    in
    "${localServiceNodeId host from} -->|${escapeLabel dependency.relation}| ${localServiceNodeId host to}";

  renderLocalHost =
    host:
    if host.dependencies or [ ] == [ ] then
      ""
    else
      ''
        subgraph ${localHostNodeId host}["${escapeLabel host.name} local components"]
          ${concatMapStringsSep "\n          " (renderLocalService host) (localComponentKeys host)}
        end
        ${concatMapStringsSep "\n        " (renderLocalDependency host) (host.dependencies or [ ])}
      '';

  siteNodeId = site: "pangolin_site_${safeId (site.id or site.name)}";
  renderSite =
    site:
    let
      matchingHost = findFirst (
        host:
        lib.toLower host.name == lib.toLower site.name
        || lib.toLower host.name == lib.toLower (site.id or "")
      ) null data.hosts;
      onlineLabel = if site.online or false then "online" else "offline or unknown";
      hostEdge =
        if matchingHost == null then
          ""
        else
          ''
            ${siteNodeId site} -. "Newt" .-> ${hostNodeId matchingHost}
          '';
    in
    ''
          ${siteNodeId site}["${escapeLabel site.name}<br/><small>${onlineLabel}</small>"]:::site
      ${hostEdge}
    '';

  publicHosts = filter (
    host:
    lib.any (
      site:
      lib.toLower host.name == lib.toLower site.name
      || lib.toLower host.name == lib.toLower (site.id or "")
    ) pangolinSites
  ) data.hosts;

  findSite =
    reference:
    findFirst (site: (site.id or "") == reference || site.name == reference) null pangolinSites;

  renderResource =
    resource:
    let
      resourceId = "pangolin_resource_${safeId (resource.id or resource.domain)}";
      siteEdges = concatMapStringsSep "\n" (
        siteReference:
        let
          site = findSite siteReference;
        in
        if site == null then "" else "${resourceId} -->|Pangolin| ${siteNodeId site}"
      ) (resource.sites or [ ]);
    in
    ''
          ${resourceId}["${escapeLabel resource.domain}<br/><small>${escapeLabel resource.name}</small>"]:::public
          internet --> ${resourceId}
      ${siteEdges}
    '';

  hostRows = concatMapStringsSep "\n" (
    host:
    let
      hostName = "[${host.name}](Host-${host.name})";
    in
    "| ${hostName} | ${host.kind} | ${host.platform} | ${toString (length host.services)} |"
  ) data.hosts;

  collectionStatus =
    if pangolin.collectedAt or null == null then
      "Not collected yet; the diagram currently contains Nix-derived topology only."
    else
      "Sanitized Pangolin snapshot collected at `${pangolin.collectedAt}`.";

  publicDiagram =
    if pangolinResources == [ ] then
      "_No sanitized Pangolin snapshot is available._"
    else
      ''
        ```mermaid
        flowchart LR
          classDef host fill:#263238,color:#fff,stroke:#90a4ae,stroke-width:2px
          classDef external fill:#fff3e0,color:#e65100,stroke:#ffb74d
          classDef public fill:#f3e5f5,color:#4a148c,stroke:#ba68c8
          classDef site fill:#e8f5e9,color:#1b5e20,stroke:#81c784

          internet((Internet)):::external

        ${concatMapStringsSep "\n" renderHost publicHosts}
        ${concatMapStringsSep "\n" renderSite pangolinSites}
        ${concatMapStringsSep "\n" renderResource pangolinResources}
        ```
      '';

  markdown = ''
    # Infrastructure topology

    The topology is split into management dependencies and public ingress so
    each diagram stays readable. Use [Fleet](Fleet) for machine roles,
    [Services](Services) for service placement, and
    [Public services](Public-Services) for the tabular Pangolin inventory.

    Pangolin: ${collectionStatus}

    ## Local component dependencies

    Local arrows are evaluated dependencies between components on the same
    managed host. They do not imply public exposure.

    ```mermaid
    flowchart LR
      classDef component fill:#e3f2fd,color:#0d47a1,stroke:#64b5f6

    ${concatMapStringsSep "\n" renderLocalHost data.hosts}
    ```

    ## Management dependencies

    Outbound arrows show cross-host control, monitoring, and tunnel
    relationships declared in the evaluated Nix configuration.

    ```mermaid
    flowchart LR
      classDef host fill:#263238,color:#fff,stroke:#90a4ae,stroke-width:2px
      classDef external fill:#fff3e0,color:#e65100,stroke:#ffb74d

    ${concatMapStringsSep "\n" renderHost data.hosts}
    ${concatMapStringsSep "\n" renderEndpoint endpointValues}
    ${concatMapStringsSep "\n" (
      host: concatMapStringsSep "\n" (renderConnection host) host.connections
    ) data.hosts}
    ```

    ## Public access

    Public resources flow through Pangolin sites to the matching managed host.

    ${publicDiagram}

    ## Host summary

    | Host | Kind | Platform | Services |
    | --- | --- | --- | ---: |
    ${hostRows}

    ## Data boundaries

    The public external snapshot contains only Pangolin site names and status,
    public resource names and domains, enabled state, protocol, and site
    relationships. Internal target addresses, ports, private resources, access
    policies, identities, and credentials are deliberately excluded.
  '';

  markdownFile = pkgs.writeText "Infrastructure.md" markdown;
  jsonFile = pkgs.writeText "infrastructure.json" (toJSON data + "\n");
in
pkgs.runCommand "infrastructure-diagram" { } ''
  mkdir -p "$out"
  cp ${markdownFile} "$out/Infrastructure.md"
  cp ${jsonFile} "$out/infrastructure.json"
''
