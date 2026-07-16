{ inputs, ... }: {
  flake.nixosModules.alaptopDisko = {
    boot.tmp.cleanOnBoot = true;

    imports = [ inputs.disko.nixosModules.disko ];

    fileSystems."/nix".neededForBoot = true;
    fileSystems."/persistent".neededForBoot = true; # sometimes needed too

    disko.devices.nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [
          "size=50%"
          "mode=755"
        ];
      };
    };

    disko.devices.disk.esp = {
      device = "/dev/nvme0n1p5";
      type = "disk";
      content = {
        type = "filesystem";
        format = "vfat";
        mountpoint = "/boot";
        mountOptions = [ "fmask=0077" "dmask=0077" ];
      };
    };

    disko.devices.disk.swap = {
      device = "/dev/nvme0n1p6";
      type = "disk";
      content = {
        type = "swap";
        resumeDevice = true;
      };
    };

    disko.devices.disk.root = {
      device = "/dev/nvme0n1p7";
      type = "disk";
      content = {
        type = "luks";
        name = "crypted";
        passwordFile = "/tmp/luks.txt";
        content = {
          type = "btrfs";
          extraArgs = [ "-f" ];
          subvolumes = {
            "/persistent" = {
              mountOptions = [ "subvol=persistent" "noatime" ];
              mountpoint = "/persistent";
            };
            "/nix" = {
              mountOptions = [ "subvol=nix" "noatime" ];
              mountpoint = "/nix";
            };
            "/tmp" = {
              mountOptions = [ "subvol=tmp" "noatime" ];
              mountpoint = "/tmp";
            };
            "/log" = {
              mountOptions = [ "subvol=log" "noatime" ];
              mountpoint = "/var/log";
            };
          };
        };
      };
    };
  };
}
