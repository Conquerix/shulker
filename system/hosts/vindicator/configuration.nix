# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./impermanence/nixos.nix
    ];

  zramSwap.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  networking.hostId =   "f58f5990";
  
  networking.hostName = "vindicator"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";


  users.mutableUsers = false;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.conquerix = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    hashedPassword = "$6$Na7d9SJRCkC6FyK7$3K.rYNPXX1.aeJe8f.2ylE2ITGLgxqv3CFvVYRsTiarQjFNZ.p2QZ/MIu1n6qz6wOO44lXU6wc9kmgIV.wboC/";
    packages = with pkgs; [
      firefox
      tree
      micro
      git
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV"
    ];
  };

  environment.systemPackages = with pkgs; [
    micro
    wget
    git
    htop
    neofetch
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    openFirewall = true;
    hostKeys = [
      {
        bits = 4096;
        path = "/nix/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
      }
      {
        path = "/nix/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  networking = {
    networkmanager.enable = false;
    useDHCP = false;

    nameservers = [ "9.9.9.9" ];
  
    interfaces.enp1s0f0 = {
      useDHCP = false;
  
      ipv4.addresses = [{
        address = "141.94.96.139";
        prefixLength = 32;
      }];
  
      ipv6.addresses = [{
        address = "2001:41d0:403:478b::";
        prefixLength = 64;
      }];
    };
 
    defaultGateway = {
      address = "141.94.96.254";
      interface = "enp1s0f0";
    };
    defaultGateway6 = {
      address = "2001:41d0:0403:47ff:00ff:00ff:00ff:00ff";
      interface = "enp1s0f0";
    };
  };

  environment.persistence."/nix/persist" = {
    hideMounts = true;
    files = [
      "/etc/machine-id"
    ];
  
    directories = [
      "/var/log"
      "/etc/ssh"
      "/etc/secrets"
      "/etc/nixos"
    ];
  };

  boot = {
    # Set up static IPv4 address in the initrd.
    kernelParams = [ "ip=141.94.96.139::141.94.96.254:255.255.255.0::enp1s0f0:none" ];
  
    initrd = {
      # Switch this to your ethernet's kernel module.
      # You can check what module you're currently using by running: lspci -v
      kernelModules = [ "ixgbe" ];

      preLVMCommands = lib.mkOrder 400 "sleep 1";
  
      network = {
        # This will use udhcp to get an ip address.
        # Make sure you have added the kernel module for your network driver to `boot.initrd.availableKernelModules`,
        # so your initrd can load it!
        # Static ip addresses might be configured using the ip argument in kernel command line:
        # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
        enable = true;
        ssh = {
          enable = true;
          # To prevent ssh clients from freaking out because a different host key is used,
          # a different port for ssh is useful (assuming the same host has also a regular sshd running)
          port = 2222;
          # hostKeys paths must be unquoted strings, otherwise you'll run into issues with boot.initrd.secrets
          # the keys are copied to initrd from the path specified; multiple keys can be set
          # you can generate any number of host keys using
          # `ssh-keygen -t ed25519 -N "" -f /path/to/ssh_host_ed25519_key`
          hostKeys = [ /nix/persist/etc/secrets/initrd/ssh_host_ed25519_key ];
          # public ssh key used for login
          authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV" ];
        };
        # this will automatically load the zfs password prompt on login
        # and kill the other prompt so boot can continue
        postCommands = ''
          cat <<EOF > /root/.profile
          if pgrep -x "zfs" > /dev/null
          then
            zfs load-key -a
            killall zfs
          else
            echo "zfs not running -- maybe the pool is taking some time to load for some unforseen reason."
          fi
          EOF
        '';
      };
    };
  };
  
  

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 2222 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}

