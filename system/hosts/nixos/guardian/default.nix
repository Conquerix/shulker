{ ... }:

{
  imports = [ ./hardware.nix ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      443
      30080
      30443
      31443
    ];
  };

  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
    };
  };

  shulker = {
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence = {
          enable = true;
          home = true;
        };
        yubikey.enable = true;
      };
    };
    users.conquerix.enable = true;
  };
}
