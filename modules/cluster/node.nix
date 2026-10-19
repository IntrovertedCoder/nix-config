{ self, lib, ... }: {
  # Shared, headless base for every installed cluster member (test or real).
  # Anything hardware-specific comes from var.cluster.host -- see _hosts.nix.
  # The mesh itself (addresses, FRR, mesh-online) is in mesh.nix, shared
  # with the rescue installers.
  flake.nixosModules.clusterNode = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) host hosts;
    lan = import ./_lan.nix;
    mgmtSeg = lan.segments.trusted;
    # Named the way Incus names a VLAN it creates on br-trunk, so an instance
    # put on the Trusted VLAN (macvlan, vlan=<id>) reuses this interface
    # instead of failing to add a second one -- and never deletes it, since
    # Incus didn't create it.
    mgmtIf = "br-trunk.${toString host.vlans.trusted}";
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

      # Management: static on the Trusted VLAN of the trunk, carried by
      # br-trunk (router.nix). Gateway and DNS are the routers' .1, but the
      # address itself never waits for them, and fe80::<lanId> answers even
      # with every router down (break-glass, design doc "Router & WAN").
      systemd.network.netdevs."25-mgmt" = {
        netdevConfig = { Kind = "vlan"; Name = mgmtIf; };
        vlanConfig.Id = host.vlans.trusted;
      };
      systemd.network.networks = {
        "20-br-trunk".vlan = [ mgmtIf ];
        "25-mgmt" = {
          matchConfig.Name = mgmtIf;
          address = [
            "${mgmtSeg.v4}.${toString host.lanId}/${toString mgmtSeg.plen}"
            "${mgmtSeg.v6}::${toString host.lanId}/64"
            "fe80::${toString host.lanId}/64"
          ];
          gateway = [ "${mgmtSeg.v4}.1" ];
          dns = [ "${mgmtSeg.v4}.1" ];
          routes = [{ Destination = lan.ula; Gateway = "fe80::1"; }];   # the other VLANs over v6
          networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; ConfigureWithoutCarrier = true; };
          linkConfig.RequiredForOnline = "routable";
        };

        # The router VM's WAN parent (router.nix; the trunk is bridged
        # there). Up, but no addresses on the host -- an address here is
        # what caused the ARP flux / duplicate-IP warnings on the installer ISO.
        "30-unmanaged" = {
          matchConfig.Name = host.wan;
          networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
          linkConfig = { ActivationPolicy = "up"; RequiredForOnline = "no"; };
        };
      } // lib.optionalAttrs ((host.testLan or null) != null) {
        # Test lab side door (_hosts.nix testLan): address only.
        "10-testlan" = {
          matchConfig.Name = host.testLan;
          networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = false; };
          dhcpV4Config = {
            # networkd defaults to a machine-id-derived client ID, so every
            # reinstall looked like a new device to UniFi and got a new lease.
            ClientIdentifier = "mac";
            UseRoutes = false;   # no default route: internet goes via the routers
            UseDNS = false;
          };
          linkConfig.RequiredForOnline = "no";
        };
      };

      # SSH and ping on the management VLAN: the LAN break-glass path.
      var.nftFirewall.interfaces.${mgmtIf} = {
        allowedTCPPorts = config.services.openssh.ports;
        allowPing = true;
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
