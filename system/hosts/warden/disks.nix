let 
  flash_pool_content = {
    type = "gpt";
    partitions = {
      zfs = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "flash_pool";
        };
      };
    };
  };

  hdd_pool_content = {
    type = "gpt";
    partitions = {
      zfs = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "hdd_pool";
        };
      };
    };
  };
in

{
  disko.devices = {
    disk = {
      nvme0 = {
        device= "/dev/disk/by-id/nvme-FOX_SPIRIT_PM18_960GB_01262221A0065";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "nvme_pool";
              };
            };
          };
        };
      };
      sata0 = {
        device= "/dev/disk/by-id/ata-Samsung_SSD_840_EVO_500GB_S1DHNSAF707788N";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "sata_pool";
              };
            };
          };
        };
      };
      sd0 = {
        device= "/dev/disk/by-id/usb-DELL_IDSDM_012345678901-0:0";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "4G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            secrets = {
              size = "4G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/secrets";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "sd_pool";
              };
            };
          };
        };
      };
      flash0 = {
        device= "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA240227S301KG00048";
        type = "disk";
        content = flash_pool_content;
      };
      flash1 = {
        device= "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA240227S301KG00457";
        type = "disk";
        content = flash_pool_content;
      };
      flash2 = {
        device= "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA240227S301KG00498";
        type = "disk";
        content = flash_pool_content;
      };
      flash3 = {
        device= "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA240227S301KG02004";
        type = "disk";
        content = flash_pool_content;
      };
      flash4 = {
        device= "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA240227S301KG03008";
        type = "disk";
        content = flash_pool_content;
      };
      flash5 = {
        device= "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA240227S301KG03764";
        type = "disk";
        content = flash_pool_content;
      };
      hdd0 = {
        device= "/dev/disk/by-id/ata-ST4000NE001-2MA101_WS21PD5H";
        type = "disk";
        content = hdd_pool_content;
      };
      hdd1 = {
        device= "/dev/disk/by-id/ata-ST4000NE001-2MA101_WS21PNEL";
        type = "disk";
        content = hdd_pool_content;
      };
    };
    nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [
          "size=16G"
        ];
      };
    };
    zpool = {
      nvme_pool = {
        type = "zpool";
        rootFsOptions.compression = "zstd";
        mountOptions = ["mountpoint=none"];
        datasets = {
          "nvme" = {
            type = "zfs_fs";
            options.mountpoint = "/storage/nvme";
          };
        };
      };
      sata_pool = {
        type = "zpool";
        rootFsOptions.compression = "zstd";
        mountOptions = ["mountpoint=none"];
        datasets = {
          "sata" = {
            type = "zfs_fs";
            options.mountpoint = "/storage/sata";
          };
        };
      };
      sd_pool = {
        type = "zpool";
        rootFsOptions.compression = "zstd";
        mountOptions = ["mountpoint=none"];
        datasets = {
          "persist" = {
            type = "zfs_fs";
            options.mountpoint = "/nix/persist";
          };
        };
      };
      flash_pool = {
        type = "zpool";
        mode = "raidz2";
        rootFsOptions.compression = "zstd";
        mountOptions = ["mountpoint=none"];
        datasets = {
          "flash" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "flash/nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
          };
          "flash/home" = {
            type = "zfs_fs";
            options.mountpoint = "/home";
          };
          "flash/storage" = {
            type = "zfs_fs";
            options.mountpoint = "/storage/flash";
          };
        };
      };
      hdd_pool = {
        type = "zpool";
        mode = "mirror";
        rootFsOptions.compression = "zstd";
        mountOptions = ["mountpoint=none"];
        datasets = {
          "hdd" = {
            type = "zfs_fs";
            options.mountpoint = "/storage/hdd";
          };
        };
      };
    };
  };
}