{ inputs, ... }: {
  # Boot disk only. The OSD disks (host.osdDisks) are left raw for
  # ceph-volume -- disko never touches them, so a reinstall can't wipe Ceph
  # data by accident (wiping them is an explicit runbook step).
  flake.nixosModules.clusterDisko = { config, ... }: {
    imports = [ inputs.disko.nixosModules.disko ];

    boot.tmp.cleanOnBoot = true;

    fileSystems."/nix".neededForBoot = true;
    fileSystems."/persistent".neededForBoot = true;
    fileSystems."/var/log".neededForBoot = true;

    disko.devices.nodev."/" = {
      fsType = "tmpfs";
      # Small on purpose: these nodes need their RAM for OSDs and instances.
      # Anything that writes heavily belongs on /persistent or /var/log.
      mountOptions = [ "size=1G" "mode=755" ];
    };

    disko.devices.disk.main = {
      device = config.var.cluster.host.bootDisk;
      type = "disk";
      content.type = "gpt";

      content.partitions.esp = {
        name = "ESP";
        size = "1G";
        type = "EF00";
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = [ "fmask=0077" "dmask=0077" ];
        };
      };

      content.partitions.root = {
        name = "root";
        size = "100%";
        content = {
          type = "btrfs";
          extraArgs = [ "-f" ];
          subvolumes = {
            "/persistent" = { mountpoint = "/persistent"; mountOptions = [ "subvol=persistent" "noatime" ]; };
            "/nix" = { mountpoint = "/nix"; mountOptions = [ "subvol=nix" "noatime" ]; };
            "/log" = { mountpoint = "/var/log"; mountOptions = [ "subvol=log" "noatime" ]; };
            "/tmp" = { mountpoint = "/tmp"; mountOptions = [ "subvol=tmp" "noatime" ]; };
          };
        };
      };
    };
  };
}
