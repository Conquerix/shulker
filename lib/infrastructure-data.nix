{
  darwinConfigurations,
  darwinHostNames,
  external,
  hostNames,
  lib,
  nixosConfigurations,
  revision ? null,
}:

let
  inherit (builtins)
    concatLists
    isAttrs
    isBool
    map
    ;
  inherit (lib)
    filter
    mapAttrsToList
    optional
    optionals
    ;

  collectEnabled =
    path: value:
    if isAttrs value && value ? enable && isBool value.enable then
      optionals value.enable [ (lib.concatStringsSep "." path) ]
    else if isAttrs value then
      concatLists (mapAttrsToList (name: child: collectEnabled (path ++ [ name ]) child) value)
    else
      [ ];

  service =
    key: name: category: enabled: endpoint:
    if enabled then
      {
        inherit
          category
          endpoint
          key
          name
          ;
      }
    else
      null;

  connection =
    enabled: from: to: relation:
    optional (enabled && to != null && to != "") {
      inherit from relation to;
    };

  nixosHost =
    hostName:
    let
      config = nixosConfigurations.${hostName}.config;
      modules = config.shulker.system.modules;
      profiles = config.shulker.system.profiles;
      hostKind =
        if profiles.server.enable then
          "server"
        else if profiles.desktop.enable then
          "desktop"
        else
          "nixos";
    in
    {
      kind = hostKind;
      name = hostName;
      platform = config.nixpkgs.hostPlatform.system;
      profiles = collectEnabled [ ] profiles;
      modules = collectEnabled [ ] modules;
      services = filter (entry: entry != null) [
        (service "backup" "Borgmatic" "backup" modules.backup.enable "Hetzner Storage Box")
        (service "beszel-agent" "Beszel agent" "monitoring" modules.beszel.agent.enable
          modules.beszel.agent.hubEndpoint
        )
        (service "beszel-hub" "Beszel hub" "monitoring" modules.beszel.hub.enable modules.beszel.hub.appUrl)
        (service "forgejo" "Forgejo" "development" modules.forgejo.enable
          "https://${modules.forgejo.subDomain}.${modules.forgejo.baseUrl}"
        )
        (service "git-pages" "Git Pages" "development" modules.git-pages.enable null)
        (service "hermes-agent" "Hermes Agent" "automation" modules.hermes-agent.enable null)
        (service "home-assistant" "Home Assistant" "automation" modules.home-assistant.enable null)
        (service "newt" "Newt" "edge" modules.newt.enable modules.newt.endpoint)
        (service "nextcloud" "Nextcloud AIO" "collaboration" modules.nextcloud.enable null)
        (service "ollama" "Ollama" "ai" modules.ollama.enable null)
        (service "pangolin" "Pangolin" "edge" modules.pangolin.enable null)
        (service "pelican-panel" "Pelican Panel" "gaming" modules.pelican.panel.enable
          modules.pelican.panel.appUrl
        )
        (service "pelican-wings" "Pelican Wings" "gaming" modules.pelican.wings.enable
          config.services.wings.node.remote
        )
        (service "plex" "Plex" "media" modules.plex.enable null)
        (service "pocket-id" "Pocket ID" "identity" modules.pocket-id.enable modules.pocket-id.appUrl)
        (service "qbittorrent" "qBittorrent" "media" modules.torrent.enable null)
        (service "steam" "Steam" "gaming" modules.steam.enable null)
        (service "sunshine" "Sunshine" "gaming" modules.sunshine.enable null)
      ];
      connections = concatLists [
        (connection modules.newt.enable "newt" modules.newt.endpoint "outbound tunnel")
        (connection modules.beszel.agent.enable "beszel-agent" modules.beszel.agent.hubEndpoint "metrics")
        (connection modules.pelican.wings.enable "pelican-wings" config.services.wings.node.remote
          "node control"
        )
      ];
    };

  darwinHost =
    hostName:
    let
      config = darwinConfigurations.${hostName}.config;
    in
    {
      kind = "darwin";
      name = hostName;
      platform = config.nixpkgs.hostPlatform.system;
      profiles = collectEnabled [ ] (config.shulker.system.profiles or { });
      modules = collectEnabled [ ] (config.shulker.system.modules or { });
      services = [ ];
      connections = [ ];
    };
in
{
  schema = 1;
  inherit external revision;
  hosts = (map nixosHost hostNames) ++ (map darwinHost darwinHostNames);
}
