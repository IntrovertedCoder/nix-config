{ inputs, ... }: {
  flake.nixosModules.antimonyDisko = {
    boot.tmp.cleanOnBoot = true;

    imports = [ inputs.disko.nixosModules.disko ];

    fileSystems."/nix".neededForBoot = true;
    fileSystems."/persistent".neededForBoot = true; # sometimes needed too

    disko.devices.nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [
          "size=25%"
          "mode=755"
        ];
      };
    };

    disko.devices.disk.main = {
      device = "/dev/nvme0n1";
      type = "disk";

      content.type = "gpt";

      content.partitions.esp = {
        name = "ESP";
        size = "3G";
        type = "EF00";

        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = [ "fmask=0077" "dmask=0077" ];
        };
      };

      content.partitions.swap = {
        size = "64G";

        content = {
          type = "swap";
          resumeDevice = true;
        };
      };

      content.partitions.root = {
        name = "root";
        size = "100%";

        content = {
          type = "btrfs";
          extraArgs = ["-f"];

          subvolumes = {
            "/persistent" = {
              mountOptions = ["subvol=persistent" "noatime"];
              mountpoint = "/persistent";
            };

            "/nix" = {
              mountOptions = ["subvol=nix" "noatime"];
              mountpoint = "/nix";
            };

            "/log" = {
              mountOptions = ["subvol=log" "noatime"];
              mountpoint = "/var/log";
            };

            "/tmp" = {
              mountOptions = ["subvol=tmp" "noatime"];
              mountpoint = "/tmp";
            };
          };
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d /games/hdd 0755 shot users -"
      "d /games/ssd 0755 shot users -"
    ];

    disko.devices.disk.gameHdd = {
      device = "/dev/sda";
      type = "disk";
      content.type = "gpt";
      content.partitions.data = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/games/hdd";
          mountOptions = [ "noatime" "nofail" ];
        };
      };
    };

    disko.devices.disk.gameSsd = {
      device = "/dev/nvme1n1";
      type = "disk";
      content.type = "gpt";
      content.partitions.data = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/games/ssd";
          mountOptions = [ "noatime" "nofail" ];
        };
      };
    };
  };
}
