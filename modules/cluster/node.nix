{ self, lib, ... }: {
  # Shared, headless base for every installed cluster member (test or real).
  # Anything hardware-specific comes from var.cluster.host -- see _hosts.nix.
  # The mesh itself (addresses, FRR, mesh-online) is in mesh.nix, shared
  # with the rescue installers.
  flake.nixosModules.clusterNode = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) host hosts;
    meshPorts = lib.concatMapStringsSep " "
      (h: "[fd9a:7af:74af:ff::${toString h.id}]:20530 [fd9a:7af:74af:ff::${toString h.id}]:22")
      (lib.attrValues hosts);
  in {
    imports = [ self.nixosModules.clusterMesh ];

    config = {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      boot.initrd.availableKernelModules = [
        "nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod"     # MS-01
        "virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net"       # test VMs
      ];
      boot.kernelModules = [ "kvm-intel" ];
      # Ceph 20.2's aes256k auth cipher needs kernel >= 7.0 for the in-kernel
      # RBD client, which is how Incus maps VM disks.
      boot.kernelPackages = pkgs.linuxPackages_latest;

      systemd.network.networks = {
        "10-mgmt" = {
          matchConfig.Name = host.mgmt;
          networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = true; };
          # networkd defaults to a machine-id-derived client ID, so every
          # reinstall looked like a new device to UniFi and got a new lease.
          dhcpV4Config.ClientIdentifier = "mac";
          linkConfig.RequiredForOnline = "routable";
        };

        # Handed to Incus later (router WAN, VLAN trunk). Up, but no
        # addresses on the host -- an address here is what caused the ARP
        # flux / duplicate-IP warnings on the installer ISO.
        "30-unmanaged" = {
          matchConfig.Name = "${host.wan} ${host.trunk}";
          networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
          linkConfig = { ActivationPolicy = "up"; RequiredForOnline = "no"; };
        };
      };

      boot.kernel.sysctl = {
        # Only answer ARP on the interface that owns the address.
        "net.ipv4.conf.all.arp_ignore" = 1;
        "net.ipv4.conf.all.arp_announce" = 2;
      };

      # Ceph, Incus cluster traffic and OVN all ride the mesh.
      var.nftFirewall.trustedInterfaces = [ "tailscale0" ] ++ host.ring;

      # `ssh -J` through a node (to another node, or to a node stuck in its
      # rescue installer) needs TCP forwarding, which sshd.nix turns off.
      # Allow it here only towards the cluster's own SSH ports on mesh
      # addresses -- nothing else can be forwarded.
      services.openssh.settings.AllowTcpForwarding = lib.mkForce "local";
      services.openssh.extraConfig = ''
        PermitOpen ${meshPorts}
      '';

      environment.systemPackages = with pkgs; [ ethtool tcpdump iperf3 jq ];

      # vtysh without sudo, for the `cluster` tool.
      users.users.shot.extraGroups = [ "frrvty" ];

      # journald only syncs non-critical messages every 5 min by default; a
      # power cut or hard reset would lose exactly the minutes before it.
      # (Crash records, core dumps and timer stamps persist via global.nix.)
      services.journald.extraConfig = "SyncIntervalSec=30s";

      # testlab.sh on the Proxmox host reads the VMs' IPs through the agent.
      services.qemuGuest.enable = host.test;

      system.stateVersion = "26.05";
      home-manager.users.shot.home.stateVersion = "26.05";
    };
  };
}
