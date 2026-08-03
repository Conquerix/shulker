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
  serviceNodeId = host: service: "service_${safeId host.name}_${safeId service.key}";
  endpointNodeId = endpoint: "endpoint_${safeId endpoint}";

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
    let
      hostId = hostNodeId host;
      serviceLines = concatMapStringsSep "\n" (
        service:
        let
          serviceId = serviceNodeId host service;
          endpointLabel =
            if service.endpoint == null then
              ""
            else
              "<br/><small>${escapeLabel (displayEndpoint service.endpoint)}</small>";
        in
        ''
          ${serviceId}["${escapeLabel service.name}${endpointLabel}"]:::service
          ${hostId} --> ${serviceId}
        ''
      ) host.services;
    in
    ''
          subgraph cluster_${safeId host.name}["${escapeLabel host.name} · ${escapeLabel host.kind}"]
            ${hostId}["${escapeLabel host.name}<br/><small>${escapeLabel host.platform}</small>"]:::host
      ${serviceLines}
          end
    '';

  renderEndpoint =
    endpoint: ''${endpointNodeId endpoint}["${escapeLabel (displayEndpoint endpoint)}"]:::external'';

  renderConnection =
    host: connection:
    let
      service = findFirst (candidate: candidate.key == connection.from) null host.services;
      sourceId = if service == null then hostNodeId host else serviceNodeId host service;
    in
    ''${sourceId} -. "${escapeLabel connection.relation}" .-> ${endpointNodeId connection.to}'';

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
    host: "| `${host.name}` | ${host.kind} | ${host.platform} | ${toString (length host.services)} |"
  ) data.hosts;

  collectionStatus =
    if pangolin.collectedAt or null == null then
      "Not collected yet; the diagram currently contains Nix-derived topology only."
    else
      "Sanitized Pangolin snapshot collected at `${pangolin.collectedAt}`.";

  markdown = ''
    # Infrastructure topology

    This page is generated from evaluated NixOS and nix-darwin configurations,
    enriched with a sanitized external topology snapshot. Change the source
    configuration or refresh the collector; do not edit this page manually.

    Pangolin: ${collectionStatus}

    ```mermaid
    flowchart LR
      classDef host fill:#263238,color:#fff,stroke:#90a4ae,stroke-width:2px
      classDef service fill:#e3f2fd,color:#0d47a1,stroke:#64b5f6
      classDef external fill:#fff3e0,color:#e65100,stroke:#ffb74d
      classDef public fill:#f3e5f5,color:#4a148c,stroke:#ba68c8
      classDef site fill:#e8f5e9,color:#1b5e20,stroke:#81c784

      internet((Internet)):::external

    ${concatMapStringsSep "\n" renderHost data.hosts}
    ${concatMapStringsSep "\n" renderEndpoint endpointValues}
    ${concatMapStringsSep "\n" (
      host: concatMapStringsSep "\n" (renderConnection host) host.connections
    ) data.hosts}
    ${concatMapStringsSep "\n" renderSite pangolinSites}
    ${concatMapStringsSep "\n" renderResource pangolinResources}
    ```

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
