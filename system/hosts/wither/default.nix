{pkgs, lib, inputs, config, ... }:

{
  imports = [ ./hardware.nix ];


  boot.kernel.sysctl = { "vm.max_map_count" = 1048576; };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  programs.gamemode.enable = true;

  networking.hostId = "7fbe10c9";

  services.udev.extraRules = ''
    # Rules for Oryx web flashing and live training
    KERNEL=="hidraw*", ATTRS{idVendor}=="16c0", MODE="0664", GROUP="plugdev"
    KERNEL=="hidraw*", ATTRS{idVendor}=="3297", MODE="0664", GROUP="plugdev"
    
    # Legacy rules for live training over webusb (Not needed for firmware v21+)
    # Rule for all ZSA keyboards
    SUBSYSTEM=="usb", ATTR{idVendor}=="3297", GROUP="plugdev"
    # Rule for the Moonlander
    SUBSYSTEM=="usb", ATTR{idVendor}=="3297", ATTR{idProduct}=="1969", GROUP="plugdev"
    # Rule for the Ergodox EZ
    SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="1307", GROUP="plugdev"
    # Rule for the Planck EZ
    SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="6060", GROUP="plugdev"
    
    # Wally Flashing rules for the Ergodox EZ
    ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", ENV{ID_MM_DEVICE_IGNORE}="1"
    ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789A]?", ENV{MTP_NO_PROBE}="1"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789ABCD]?", MODE:="0666"
    KERNEL=="ttyACM*", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", MODE:="0666"
    
    # Keymapp / Wally Flashing rules for the Moonlander and Planck EZ
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE:="0666", SYMLINK+="stm32_dfu"
    # Keymapp Flashing rules for the Voyager
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="3297", MODE:="0666", SYMLINK+="ignition_dfu"

    # Try to prevent gnome-shell from executing on nvidia dGPU
    #ENV{DEVNAME}=="/dev/dri/card1", TAG+="mutter-device-preferred-primary"
  '';

  boot = {
    initrd.kernelModules = [
      "vfio_pci"
      "vfio"
      "vfio_iommu_type1"

      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];

    kernelParams = [
      # enable IOMMU
      "amd_iommu=on"
      "amd_iommu=pt"
      "kvm.ignore_msrs=1"
    ];
    #extraModprobeConfig = "options vfio-pci ids=10de:2b85,10de:2b85";
  };

  systemd.tmpfiles.rules = [
      "f /dev/shm/looking-glass 0660 conquerix qemu-libvirtd -"
  ];

  programs.dconf.enable = true;
  programs.virt-manager.enable = true;
  hardware.graphics.enable = true;
  virtualisation = {
    spiceUSBRedirection.enable = true;
    libvirtd = {
      enable = true;
      persistence = true;
      extraConfig = ''
        user="conquerix"
      '';

      # Don't start any VMs automatically on boot.
      onBoot = "ignore";
      # Stop all running VMs on shutdown.
      onShutdown = "shutdown";

      qemu = {
        package = pkgs.qemu_kvm;
        ovmf = {
          enable = true;
          packages = [ pkgs.OVMFFull.fd ];
        };
        vhostUserPackages = [ pkgs.virtiofsd ];
        swtpm.enable = true;
        runAsRoot = false;
      };
      clearEmulationCapabilities = false;
      deviceACL = [
        "/dev/ptmx"
        "/dev/kvm"
        "/dev/kvmfr0"
        "/dev/vfio/vfio"
        "/dev/vfio/30"
      ];
    };
  };

  programs.adb.enable = true;
  users.users.conquerix.extraGroups = [ "adbusers" "kvm" "qemu-libvirtd" "libvirtd" "disk" ];

  environment.systemPackages = with pkgs; [
    chromium
    netflix
    keymapp
    trezor-suite
    protonvpn-gui
    bisq2
    looking-glass-client
    ryubing
    linux-wallpaperengine
  ];

  shulker = {
    profiles.desktop.enable = true;
    modules = {
      steam = {
        enable = true;
        protonGE = true;
      };
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
      };
      yubikey.enable = true;
      wireguard.enable = true;
      nvidia  = {
        enable = true;
        hybrid = {
          enable = true;
          offload = true;
          amdgpuBusId = "PCI:108:0:0";
          nvidiaBusId = "PCI:1:0:0";
        };
      };
      virtualisation.kvmfr = {
        enable = true;
        shm = {
          enable = true;
          size = 512;
          user = "conquerix";
          group = "qemu-libvirtd";
          mode = "0666";
        };
      };
    };
  };
}
