# qBittorrent confined behind a ProtonVPN WireGuard tunnel.
#
# Uses the hotio/qbittorrent image (https://hotio.dev/containers/qbittorrent/),
# which bundles qBittorrent, an internal WireGuard VPN and automatic Proton
# port-forwarding in a single container. The container firewalls all traffic
# that isn't the tunnel or the allowed LAN, so if the VPN drops torrent traffic
# is blocked rather than leaked over the WAN. With VPN_AUTO_PORT_FORWARD it asks
# Proton (NAT-PMP) for a forwarded port and sets qBittorrent's listen port to it.
{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.torrent;
in
{
  options.shulker.system.modules.torrent = {
    enable = mkEnableOption "qBittorrent confined behind a ProtonVPN WireGuard tunnel";

    impermanence = mkEnableOption "Persist qBittorrent config across reboots";

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/torrent";
      description = "Where qBittorrent keeps its /config (settings, resume data).";
    };

    downloadDir = mkOption {
      type = types.str;
      default = "/var/lib/torrent/downloads";
      description = "Host path mapped to the container's /data (downloads live here).";
    };

    webUiPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for the qBittorrent web UI.";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address on which to publish the qBittorrent web UI.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the web UI port on the host firewall for LAN access.";
    };

    lanNetwork = mkOption {
      type = types.str;
      default = "192.168.1.0/24";
      description = ''
        LAN CIDR the container's VPN firewall allows, so the web UI stays
        reachable from the LAN. Set this to your actual subnet.
      '';
    };

    portForwarding = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Ask Proton (NAT-PMP) for a forwarded port and set it as qBittorrent's
        listen port automatically. Requires a Proton plan with port forwarding
        and a WireGuard config generated on a P2P server with NAT-PMP enabled.
      '';
    };

    puid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID qBittorrent runs as (owns /config and downloads).";
    };

    group = mkOption {
      type = types.str;
      default = "torrent";
      description = ''
        Shared group qBittorrent writes downloads as. Add other services
        (e.g. Plex) to this group so they can read finished downloads.
      '';
    };

    gid = mkOption {
      type = types.int;
      default = 970;
      description = "Fixed GID for the shared torrent group.";
    };

    timeZone = mkOption {
      type = types.str;
      default = config.time.timeZone or "Etc/UTC";
      description = "Time zone for the container.";
    };
  };

  config = mkIf cfg.enable {

    shulker.system.modules.containers.enable = true;

    # Shared group so downloads are readable by other services (e.g. Plex).
    users.groups.${cfg.group}.gid = cfg.gid;

    # Create the download dir owned by the shared group with the setgid bit, so
    # everything qBittorrent writes there inherits the group regardless of the
    # writing process's primary group.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir}/config 0770 ${toString cfg.puid} ${cfg.group} - -"
      "d ${cfg.downloadDir} 2775 ${toString cfg.puid} ${cfg.group} - -"
    ];

    virtualisation.oci-containers.containers."torrent-qbittorrent" = {
      image = "ghcr.io/hotio/qbittorrent:latest@sha256:26689d60b283a8d026965e7d9a0c941f4c168fbe1af028b31e9db42ce6aa357b";
      environment = {
        PUID = toString cfg.puid;
        PGID = toString cfg.gid;
        # 002 keeps files group-writable so other members of the shared group
        # (e.g. Plex) can read everything qBittorrent writes.
        UMASK = "002";
        TZ = cfg.timeZone;
        WEBUI_PORTS = "${toString cfg.webUiPort}/tcp";
        VPN_ENABLED = "true";
        VPN_PROVIDER = "proton";
        VPN_CONF = "wg0";
        VPN_LAN_NETWORK = cfg.lanNetwork;
        VPN_AUTO_PORT_FORWARD = if cfg.portForwarding then "true" else "false";
      };
      ports = [ "${cfg.bindAddress}:${toString cfg.webUiPort}:${toString cfg.webUiPort}/tcp" ];
      volumes = [
        "${cfg.stateDir}/config:/config"
        "${cfg.downloadDir}:/data"
        # Full Proton WireGuard config, kept in 1Password and mounted read-only.
        # WireGuard is brought up as root inside the container before privileges
        # are dropped, so a root-owned secret is fine.
        "${config.services.onepassword-secrets.secrets.torrentWireguard.path}:/config/wireguard/wg0.conf:ro"
      ];
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun:/dev/net/tun"
      ];
      log-driver = "journald";
    };

    # The secret is the entire wg0.conf ([Interface] + [Peer]) from Proton's
    # WireGuard config generator (use a P2P server with NAT-PMP enabled).
    services.onepassword-secrets.secrets.torrentWireguard = {
      reference = "op://Shulker/${config.networking.hostName}/Torrent VPN/wg0.conf";
      services = [ "docker-torrent-qbittorrent" ];
    };

    # OpNix's service integration uses a soft Wants= dependency. Make this one
    # hard because Docker creates a missing bind-mount source as a directory,
    # which would then prevent OpNix from writing the WireGuard config file.
    systemd.services.docker-torrent-qbittorrent = {
      requires = [ "opnix-secrets.service" ];
      unitConfig.ConditionFileNotEmpty =
        config.services.onepassword-secrets.secrets.torrentWireguard.path;
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.webUiPort ];

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };

    # qBittorrent config is small and worth keeping; downloads are not backed up.
    shulker.system.modules.backup.dirs = [ "${cfg.stateDir}/config" ];
  };
}
