{ self, inputs, lib, ... }: {
  # The router VM on every node: the cluster's edge (design doc, Router & WAN).
  #
  # Each node runs its own router as a microvm.nix VM, started by systemd at
  # boot from the node's own disk. It depends on nothing in the cluster (no
  # Ceph, no Incus), so a node that's up alone still gives clients DHCP, DNS
  # and internet. A VM rather than a container: internet traffic is parsed by
  # the router's kernel, never the node's.
  #
  # The three routers share one WAN MAC address. keepalived (VRRP) picks a
  # master; only the master brings its WAN link up and takes the DHCP lease
  # from upstream, so the upstream network only ever sees one device. The
  # backups keep their WAN links down. A failover is a WAN reconnect of a
  # few seconds; the client-side gateway (.1 on each VLAN) moves with it.
  #
  # VRRP runs on the transit VLAN only (routers + OVN's router, never
  # clients), so nothing on a client VLAN can take part in the election.
  #
  # DHCP: Kea on every router, each with its own third of every pool. Any one
  # router can serve alone and they never need to share leases; a client
  # whose router died keeps its address until the lease runs out, then gets
  # one from another router.
  #
  #   Trusted 10.1.0.0/24   IoT 10.2.0.0/24   Guest 10.3.0.0/24
  #   Transit 10.91.0.0/24 (to OVN's services network, 10.90.0.0/24)
  #   .1 = gateway (VRRP), .<id+1> = the router on node <id>,
  #   DHCP .100-.149 / .150-.199 / .200-.249 from routers 1 / 2 / 3.
  #
  # Get a shell on this node's router (as root on the node):  router-ssh
  flake.nixosModules.clusterRouter = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host hosts;

    # Shared by all three routers: the upstream DHCP server sees one client.
    # Locally administered (02:...), so it can't collide with real hardware.
    wanMac = "02:74:af:00:00:01";
    hex = n: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString n));
    lanMac = id: "02:74:af:01:00:${hex id}";
    mgmtMac = id: "02:74:af:fe:00:${hex id}";

    segments = {
      trusted = { v4 = "10.1.0"; dhcp = true; };
      iot     = { v4 = "10.2.0"; dhcp = true; };
      guest   = { v4 = "10.3.0"; dhcp = true; };
      transit = { v4 = "10.91.0"; dhcp = false; };
    };
    clientSegs = lib.filterAttrs (_: s: s.dhcp) segments;
    routerIp = id: seg: "${segments.${seg}.v4}.${toString (id + 1)}";
    peers = lib.filter (h: h.id != host.id) (lib.attrValues hosts);

    poolStart = 100 + (host.id - 1) * 50;

    routerSsh = pkgs.writeShellApplication {
      name = "router-ssh";
      runtimeInputs = [ pkgs.openssh ];
      text = ''
        # The node's own host key is the router's admin key (root only); the
        # link is a point-to-point tap to this node's router, nothing else.
        exec ssh -i /etc/ssh/ssh_host_ed25519_key \
          -o StrictHostKeyChecking=accept-new \
          -o UserKnownHostsFile=/var/lib/microvms/router/known_hosts \
          root@fe80::2%vm-rtr-mgmt "$@"
      '';
    };

    # ------------------------------------------------------------ the router
    routerConfig = { config, lib, pkgs, ... }: let
      wanUp = pkgs.writeShellScript "router-wan-up" ''
        ${pkgs.systemd}/bin/networkctl up wan
      '';
      wanDown = pkgs.writeShellScript "router-wan-down" ''
        ${pkgs.systemd}/bin/networkctl down wan
      '';
    in {
      imports = [ self.nixosModules.nftFirewall ];

      networking.hostName = "${name}-router";
      system.stateVersion = "26.05";

      microvm = {
        hypervisor = "qemu";
        vcpu = 1;
        mem = 768;
        shares = [{
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }];
        # Leases, DHCP state, SSH host keys and the journal survive restarts;
        # the file lives in the node's /var/lib/microvms/router.
        volumes = [{ image = "var.img"; mountPoint = "/var"; size = 1024; }];
        interfaces = [
          { type = "tap"; id = "vm-rtr-lan"; mac = lanMac host.id; }
          { type = "tap"; id = "vm-rtr-mgmt"; mac = mgmtMac host.id; }
        ] ++ lib.optional (host.wanPci == null) {
          type = "macvtap"; id = "vm-rtr-wan"; mac = wanMac;
          macvtap = { link = host.wan; mode = "bridge"; };
        };
        devices = lib.optional (host.wanPci != null) { bus = "pci"; path = host.wanPci; };
      };

      # ---------------------------------------------------------- interfaces
      networking.useNetworkd = true;
      networking.useDHCP = false;
      services.resolved.enable = false;
      systemd.network.links = {
        "10-lan" = { matchConfig.MACAddress = lanMac host.id; linkConfig.Name = "lan"; };
        "10-mgmt" = { matchConfig.MACAddress = mgmtMac host.id; linkConfig.Name = "mgmt"; };
        # The passed-through NIC has its own hardware MAC: clone the shared
        # one onto it. (The test macvtap already has it.)
        "10-wan" = if host.wanPci == null
          then { matchConfig.MACAddress = wanMac; linkConfig.Name = "wan"; }
          else { matchConfig.Driver = "igc"; linkConfig = { Name = "wan"; MACAddress = wanMac; }; };
      };
      systemd.network.netdevs = lib.mapAttrs' (seg: _: lib.nameValuePair "20-${seg}" {
        netdevConfig = { Kind = "vlan"; Name = seg; };
        vlanConfig.Id = host.vlans.${seg};
      }) segments;
      systemd.network.networks = {
        # Down until keepalived makes this router master (wanUp/wanDown).
        "10-wan" = {
          matchConfig.Name = "wan";
          networkConfig = { DHCP = "ipv4"; LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
          dhcpV4Config = {
            ClientIdentifier = "mac";       # the same client, whichever router asks
            Hostname = "elements-router";
            UseDNS = false;                 # Unbound resolves itself
          };
          linkConfig = { ActivationPolicy = "manual"; RequiredForOnline = "no"; };
        };
        "10-lan" = {
          matchConfig.Name = "lan";
          vlan = lib.attrNames segments;
          networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
          linkConfig.RequiredForOnline = "carrier";
        };
        "10-mgmt" = {
          matchConfig.Name = "mgmt";
          address = [ "fe80::2/64" ];
          networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
          linkConfig.RequiredForOnline = "no";
        };
      } // lib.mapAttrs' (seg: s: lib.nameValuePair "20-${seg}" {
        matchConfig.Name = seg;
        address = [ "${routerIp host.id seg}/24" ];
        networkConfig = { IPv6AcceptRA = false; ConfigureWithoutCarrier = true; };
        linkConfig.RequiredForOnline = "no";
      }) segments;

      boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = 1;

      # ---------------------------------------------------------- VRRP
      services.keepalived = {
        enable = true;
        enableScriptSecurity = true;
        extraGlobalDefs = "script_user root";   # networkctl needs root
        vrrpInstances.gateway = {
          interface = "transit";
          state = "BACKUP";       # all start as backup; nopreempt needs it
          noPreempt = true;       # a returning router doesn't take over (no extra WAN reconnect)
          virtualRouterId = 51;
          priority = 160 - 10 * host.id;   # first election only: node1 > node2 > node3
          unicastSrcIp = routerIp host.id "transit";
          unicastPeers = map (h: routerIp h.id "transit") peers;
          virtualIps = lib.mapAttrsToList (seg: s: { addr = "${s.v4}.1/24"; dev = seg; }) segments;
          extraConfig = ''
            notify_master "${wanUp}"
            notify_backup "${wanDown}"
            notify_fault "${wanDown}"
            notify_stop "${wanDown}"
          '';
        };
      };

      # ---------------------------------------------------------- DHCP
      services.kea.dhcp4 = {
        enable = true;
        settings = {
          interfaces-config = {
            interfaces = lib.attrNames clientSegs;
            # The VLAN interfaces can appear after Kea starts.
            service-sockets-max-retries = 60;
            service-sockets-retry-wait-time = 2000;
          };
          lease-database = { type = "memfile"; persist = true; name = "/var/lib/kea/dhcp4.leases"; };
          valid-lifetime = 3600;
          # Not authoritative: a client renewing a lease from a router that's
          # gone is ignored rather than refused, so it keeps its address
          # until the lease runs out.
          authoritative = false;
          subnet4 = lib.imap1 (i: seg: let s = clientSegs.${seg}; in {
            id = i;
            subnet = "${s.v4}.0/24";
            interface = seg;
            pools = [{ pool = "${s.v4}.${toString poolStart} - ${s.v4}.${toString (poolStart + 49)}"; }];
            option-data = [
              { name = "routers"; data = "${s.v4}.1"; }
              { name = "domain-name-servers"; data = "${s.v4}.1"; }
            ];
          }) (lib.attrNames clientSegs);
        };
      };

      # ---------------------------------------------------------- DNS
      # Recursive resolver for the clients (Blocky goes in front later).
      # Only the master has internet, and only the master holds .1.
      services.unbound = {
        enable = true;
        settings.server = {
          interface = [ "0.0.0.0" "::0" ];
          interface-automatic = true;    # answer from the address that was asked (the VIP)
          access-control = [
            "127.0.0.0/8 allow" "::1 allow"
            "10.0.0.0/8 allow" "fd9a:7af:74af::/48 allow"
          ];
        };
      };

      # ---------------------------------------------------------- firewall
      var.nftFirewall.trustedInterfaces = [ ];
      var.nftFirewall.interfaces = {
        mgmt = { allowedTCPPorts = [ 22 ]; allowPing = true; };
        transit = {
          allowedTCPPorts = [ 53 ]; allowedUDPPorts = [ 53 ]; allowPing = true;
          extraRules = ''iifname "transit" ip saddr 10.91.0.0/24 ip protocol vrrp accept'';
        };
      } // lib.mapAttrs (_: _: {
        allowedTCPPorts = [ 53 ]; allowedUDPPorts = [ 53 67 ]; allowPing = true;
      }) clientSegs;
      networking.firewall.extraInputRules = ''
        iifname "transit" ip saddr 10.91.0.0/24 ip protocol vrrp accept
      '';

      # Forwarding policy: every VLAN out to the internet, and replies back.
      # Nothing between VLANs over v4 (local access is v6, added later).
      networking.nftables.tables.router = {
        family = "inet";
        content = ''
          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state invalid drop
            ct state { established, related } accept
            iifname { ${lib.concatMapStringsSep ", " (s: ''"${s}"'') (lib.attrNames segments)} } oifname "wan" accept
          }
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "wan" masquerade
          }
        '';
      };

      # ---------------------------------------------------------- access
      services.openssh = {
        enable = true;
        settings = { PermitRootLogin = "prohibit-password"; PasswordAuthentication = false; KbdInteractiveAuthentication = false; };
        hostKeys = [{ path = "/var/lib/ssh/ssh_host_ed25519_key"; type = "ed25519"; }];
      };
      users.users.root.openssh.authorizedKeys.keys = [ host.hostKey ] ++ shotKeys;

      environment.systemPackages = with pkgs; [ tcpdump ethtool conntrack-tools dig ];
      documentation.enable = false;
    };

    shotKeys = config.users.users.shot.openssh.authorizedKeys.keys;
  in {
    imports = [ inputs.microvm.nixosModules.host ];

    microvm.vms.router.config = routerConfig;

    # The trunk becomes a bridge shared by the trunk NIC and the router's LAN
    # tap (later also OVN's uplink and test client instances). The node
    # itself has no address on it.
    systemd.network.netdevs."20-br-trunk".netdevConfig = { Kind = "bridge"; Name = "br-trunk"; };
    systemd.network.networks = {
      "20-br-trunk" = {
        matchConfig.Name = "br-trunk";
        networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; ConfigureWithoutCarrier = true; };
        linkConfig.RequiredForOnline = "no";
      };
      "21-br-trunk-ports" = {
        matchConfig.Name = "${host.trunk} vm-rtr-lan";
        networkConfig = { Bridge = "br-trunk"; LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
        linkConfig = { ActivationPolicy = "up"; RequiredForOnline = "no"; };
      };
      "22-router-mgmt" = {
        matchConfig.Name = "vm-rtr-mgmt";
        address = [ "fe80::1/64" ];
        networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; ConfigureWithoutCarrier = true; };
        linkConfig.RequiredForOnline = "no";
      };
      # vm-rtr-wan (macvtap, test lab) is left unmanaged: microvm.nix creates
      # it with IPv6 off, so the node never sends with the shared WAN MAC.
    };

    environment.systemPackages = [ routerSsh ];

    preservation.preserveAt."/persistent".directories = [
      { directory = "/var/lib/microvms"; user = "microvm"; group = "kvm"; mode = "0775"; }
    ];
  };
}
