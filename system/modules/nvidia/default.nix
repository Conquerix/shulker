# https://nixos.wiki/wiki/Nvidia
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.nvidia;

  nvidia-offload = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_REDNER_OFFLOAD=1
    export __NV_PRIME_REDNER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec -a "$0" "$@"
  '';
in
{
  options.shulker.modules.nvidia = {
    enable = mkEnableOption "Nvidia support";

    hybrid = {
      enable = mkEnableOption "Hybrid graphics support";

      intelBusId = mkOption {
        description = ''
          Bus ID for the intel GPU. You can find it by running this nix shell
          `nix-shell -p lshw --run "lshw -c display"`. Taking the output of this for example
          `bus info: pci@0000:01:00.0`, take everything after the first colon, replace the `.` with a `:`
          Remove leading `0`
        '';
        type = types.str;
        default = "";
        example = "PCI:1:0:0";
      };

      nvidiaBusId = mkOption {
        description = ''
          Bus ID for the nvidia GPU. You can find it by running this nix shell
          `nix-shell -p lshw --run "lshw -c display"`. Taking the output of this for example
          `bus info: pci@0000:01:00.0`, take everything after the first colon, replace the `.` with a `:`
          Remove leading `0`
        '';
        type = types.str;
        default = "";
        example = "PCI:1:0:0";
      };
    };
  };

  config = mkIf cfg.enable {

    services.xserver.videoDrivers = [ "nvidia" ];

    environment.systemPackages = mkIf cfg.hybrid.enable [ nvidia-offload ];
    hardware.nvidia.prime = mkIf cfg.hybrid.enable {
      offload.enable = true;
      intelBusId = cfg.intelBusId;
      nvidiaBusId = cfg.nvidiaBusId;
      };
    };
  }
