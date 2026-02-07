{ pkgs, config, ... }:

{
  imports = [ ./hardware.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # For zfs.
  networking.hostId = "2118dc3b";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      8096
      1900
    ];
    allowedUDPPorts = [
      8096
      1900
    ];
  };

  virtualisation.oci-containers.containers = {
    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      ports = [ "8191:8191" ];
      environment.LOG_LEVEL = "info";
    };
  };

  fileSystems."/remote/torrents" = {
    device = "conquerix@spinel.usbx.me:/home/conquerix/downloads/rtorrent";
    fsType = "fuse.sshfs";
    options = [
      "identityfile=${config.services.onepassword-secrets.secrets.sshed25519HostKey.path}"
      "idmap=user"
      "x-systemd.automount" # mount the filesystem automatically on first access
      "allow_other" # don't restrict access to only the user which `mount`s it (because that's probably systemd who mounts it, not you)
      "user" # allow manual `mount`ing, as ordinary user.
      "_netdev"
    ];
  };
  fileSystems."/remote/usenet" = {
    device = "conquerix@spinel.usbx.me:/home/conquerix/downloads/sabnzbd/complete";
    fsType = "fuse.sshfs";
    options = [
      "identityfile=${config.services.onepassword-secrets.secrets.sshed25519HostKey.path}"
      "idmap=user"
      "x-systemd.automount" # mount the filesystem automatically on first access
      "allow_other" # don't restrict access to only the user which `mount`s it (because that's probably systemd who mounts it, not you)
      "user" # allow manual `mount`ing, as ordinary user.
      "_netdev"
    ];
  };
  boot.supportedFilesystems."fuse.sshfs" = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      (intel-vaapi-driver.override { enableHybridCodec = true; })
      vaapiVdpau
      libvdpau-va-gl
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
      vpl-gpu-rt # QSV on 11th gen or newer
    ];
  };

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
      };
    };
  };
}
