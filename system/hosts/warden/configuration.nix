# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostId = "2118dc3b";
  networking.hostName = "nixos-cloud";
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Paris";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "fr_FR.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "fr";
  };


  # Define a user account. Don't forget to set a password with ‘passwd’.
  
  users.mutableUsers = false;

  users.users.conquerix = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    initialHashedPassword = "$6$Na7d9SJRCkC6FyK7$3K.rYNPXX1.aeJe8f.2ylE2ITGLgxqv3CFvVYRsTiarQjFNZ.p2QZ/MIu1n6qz6wOO44lXU6wc9kmgIV.wboC/";
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    micro
    wget
    neofetch
    htop
    ncdu
    git
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Persistent directories :

  # /etc :

  environment.etc = {
    "machine-id".source                   = "/persist/etc/machine-id";
    "ssh/ssh_host_rsa_key".source         = "/persist/etc/ssh/ssh_host_rsa_key";
    "ssh/ssh_host_rsa_key.pub".source     = "/persist/etc/ssh/ssh_host_rsa_key.pub";
    "ssh/ssh_host_ed25519_key".source     = "/persist/etc/ssh/ssh_host_ed25519_key";
    "ssh/ssh_host_ed25519_key.pub".source = "/persist/etc/ssh/ssh_host_ed25519_key.pub";
    "nixos".source                        = "/persist/etc/nixos";
  };

  # /var/lib/tor :

  systemd.tmpfiles.rules = [
      "L /run/keys/tor/ssh_access/hs_ed25519_secret_key - - - - /persist/tor/ssh_access/hs_ed25519_secret_key"
  #    "L /var/lib/tor/ - - - - /persist/var/lib/tor/"
  ];
  
  # List services that you want to enable:

  services.tor = {
    enable = true;
    enableGeoIP = false;
    relay.onionServices = {
      ssh_access = {
        version = 3;
        secretKey = "/run/keys/tor/ssh_access/hs_ed25519_secret_key";
        path = "/var/lib/tor/onion/ssh_access";
        map = [{
          port = 45022;
          target = {
            addr = "127.0.0.1";
            port = 22;
          };
        }];
      };
    };
    settings = {
      ClientUseIPv4 = true;
      ClientUseIPv6 = false;
      ClientPreferIPv6ORPort = false;
    };
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?

}
