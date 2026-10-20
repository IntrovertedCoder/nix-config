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
  # backups keep their WAN links down and reach the internet through the
  # master over the transit VLAN. A failover is a WAN reconnect of a few
  # seconds; the client-side gateway (.1 / fe80::1 on each VLAN) moves with it.
  # A master whose WAN link loses carrier (its own cable or port) hands over;
  # an upstream outage doesn't make them take turns.
  #
  # VRRP runs on the transit VLAN only (routers + OVN's router, never
  # clients), so nothing on a client VLAN can take part in the election.
  #
  # DHCP: Kea on every router, each with its own third of every pool. Any one
  # router can serve alone and they never need to share leases; a client
  # whose router died keeps its address until the lease runs out, then gets
  # one from another router.
  #
  # DNS: Blocky on :53 (blocklists, cache) in front of Unbound on
  # 127.0.0.1:5335 (recursive, DNSSEC; no third-party resolver).
  #
  # IPv6 is local only (ULA, design doc "IPv6"): the master advertises each
  # prefix for SLAAC with router lifetime 0 -- "not a default router", so
  # clients keep using IPv4 for the internet -- plus a route to the whole
  # /48 through fe80::1. Guest gets no IPv6. IoT's prefix is not on-link, so
  # even IoT-to-IoT IPv6 goes through the router's firewall.
  #
  #             IPv4            IPv6 (ULA)
  #   Trusted   10.1.0.0/21     fd9a:7af:74af:1::/64
  #   IoT       10.2.0.0/21     fd9a:7af:74af:2::/64  (not on-link)
  #   Guest     10.3.0.0/21     --
  #   Infra     10.4.0.0/21     --                    (UNTAGGED: network gear, UniFi controller)
  #   Transit   10.91.0.0/24    fd9a:7af:74af:91::/64 (to OVN's services network)
  #   .1 / ::1 = gateway (VRRP), .<id+1> / ::<id+1> = the router on node <id>,
  #   DHCP from router <id> in 10.<seg>.<id>.x; reservations in 10.<seg>.4.x,
  #   the same from every router (_lan.nix).
  #
  # Forwarding: every segment out to the internet over IPv4 (NAT); between
  # segments over IPv4 only Trusted -> Infra (managing the gear); locally over
  # IPv6, Trusted may reach anything, nothing else starts connections.
  # Infra DHCP answers UniFi gear only (vendor class "ubnt").
  #
  # Get a shell on this node's router (as root on the node):  router-ssh
  flake.nixosModules.clusterRouter = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host hosts;

    # Shared by all three routers: the upstream DHCP server sees one client.
    # Locally administered (02:...), so it can't collide with real hardware.
    wanMac = "02:74:af:00:00:01";
    hex = n: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString n));
    lanMac = id: "02:74:af:01:00:${hex id}";
    untaggedMac = id: "02:74:af:02:00:${hex id}";
    mgmtMac = id: "02:74:af:fe:00:${hex id}";

    lan = import ./_lan.nix;
    inherit (lan) segments ula;
    clientSegs = lib.filterAttrs (_: s: s.dhcp) segments;
    v6Segs = lib.filterAttrs (_: s: s.v6 != null) segments;
    raSegs = lib.filterAttrs (_: s: s.dhcp && s.v6 != null) segments;   # clients that get IPv6
    # Tagged segments are VLANs on the router's trunk link ("lan"). The
    # untagged one (infra) is a macvlan on it, NOT the trunk link itself: a
    # raw socket there (Kea's) sees the tagged frames too, and Kea answered
    # VLAN 31 requests from the infra subnet (seen in testing). The kernel hands
    # tagged frames to their VLAN devices before the macvlan sees anything.
    taggedSegs = lib.filterAttrs (_: s: !(s.untagged or false)) segments;
    untaggedSeg = lib.findFirst (seg: segments.${seg}.untagged or false) null (lib.attrNames segments);
    segAddrs = seg: s: [ "${routerIp host.id seg}/${toString s.plen}" ]
      ++ lib.optional (s.v6 != null) "${s.v6}::${toString (host.id + 1)}/64";
    segNames = set: lib.concatMapStringsSep ", " (s: ''"${s}"'') (lib.attrNames set);
    routerIp = id: seg: "${segments.${seg}.v4}.${toString (id + 1)}";
    peers = lib.filter (h: h.id != host.id) (lib.attrValues hosts);


    routerSsh = pkgs.writeShellApplication {
      name = "router-ssh";
      runtimeInputs = [ pkgs.openssh ];
      text = /* bash */ ''
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
      # keepalived's transitions. Master: WAN up, start advertising IPv6.
      # Anything else: stop advertising, WAN down (never two WANs up with the
      # same MAC). radvd isn't told to withdraw anything on stop, so clients
      # keep their addresses and the /48 route while the next master (same
      # fe80::1) takes over.
      becomeMaster = pkgs.writeShellScript "router-become-master" /* bash */ ''
        ${pkgs.systemd}/bin/networkctl up wan
        ${pkgs.systemd}/bin/systemctl start radvd.service
      '';
      leaveMaster = pkgs.writeShellScript "router-leave-master" /* bash */ ''
        ${pkgs.systemd}/bin/systemctl stop radvd.service
        ${pkgs.systemd}/bin/networkctl down wan
      '';
      # Fails only on the master with its WAN admin-up and no carrier: this
      # router's own cable/port is dead, so another router should take over.
      # No lease or no internet doesn't count -- upstream outages hit every
      # router alike, and handing over would just flap the WAN between them.
      # (The test lab's virtio NIC always has carrier; set_link via QMP
      # simulates a pulled cable.)
      wanCarrier = pkgs.writeShellScript "router-wan-carrier" /* bash */ ''
        ${pkgs.iproute2}/bin/ip -4 addr show dev transit | ${pkgs.gnugrep}/bin/grep -q ' 10\.91\.0\.1/' || exit 0
        # Admin state from IFF_UP: operstate says "down" for a lost carrier too.
        (( $(cat /sys/class/net/wan/flags) & 1 )) || exit 0   # admin-down: not ours to judge
        [ "$(cat /sys/class/net/wan/carrier 2>/dev/null)" = 1 ]
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
      }) taggedSegs // lib.optionalAttrs (untaggedSeg != null) {
        "20-${untaggedSeg}" = {
          netdevConfig = { Kind = "macvlan"; Name = untaggedSeg; MACAddress = untaggedMac host.id; };
          macvlanConfig.Mode = "bridge";
        };
      };
      systemd.network.networks = {
        # Down until keepalived makes this router master.
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
          vlan = lib.attrNames taggedSegs;
          macvlan = lib.optional (untaggedSeg != null) untaggedSeg;
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
        address = segAddrs seg s;
        networkConfig = { IPv6AcceptRA = false; ConfigureWithoutCarrier = true; };
        linkConfig.RequiredForOnline = "no";
        # Backups (WAN down) reach the internet through the master; on the
        # master its WAN's DHCP route (metric 1024) wins.
        # OVN's services network sits behind OVN's router on transit.
        routes = lib.optionals (seg == "transit") [
          { Gateway = "10.91.0.1"; Metric = 2048; }
          { Destination = "${lan.services.v4}.0/24"; Gateway = lan.ovnUplink.v4; }
          { Destination = "${lan.services.v6}::/64"; Gateway = lan.ovnUplink.v6; }
        ];
      }) segments;

      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
        # Never suggest a direct path: on isolated VLANs it would be blocked.
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
      };

      # ---------------------------------------------------------- VRRP
      services.keepalived = {
        enable = true;
        enableScriptSecurity = true;
        extraGlobalDefs = "script_user root";   # networkctl/systemctl need root
        vrrpScripts.wan_carrier = {
          script = "${wanCarrier}";
          interval = 2; fall = 3; rise = 1;      # 6 s: a real NIC's autonegotiation after link-up
          user = "nobody";
        };
        vrrpInstances.gateway = {
          interface = "transit";
          state = "BACKUP";       # all start as backup; nopreempt needs it
          noPreempt = true;       # a returning router doesn't take over (no extra WAN reconnect)
          virtualRouterId = 51;
          priority = 160 - 10 * host.id;   # first election only: node1 > node2 > node3
          unicastSrcIp = routerIp host.id "transit";
          unicastPeers = map (h: routerIp h.id "transit") peers;
          virtualIps = lib.mapAttrsToList (seg: s: { addr = "${s.v4}.1/${toString s.plen}"; dev = seg; }) segments;
          trackScripts = [ "wan_carrier" ];
          # IPv6 gateway addresses move with the IPv4 ones but aren't carried
          # in the (IPv4) adverts.
          extraConfig = ''
            virtual_ipaddress_excluded {
              ${lib.concatStringsSep "\n  " (lib.concatLists (lib.mapAttrsToList (seg: s: [
                "fe80::1/64 dev ${seg}" "${s.v6}::1/64 dev ${seg}"
              ]) v6Segs))}
            }
            # Keep re-announcing the gateway addresses (gratuitous ARP / NA)
            # while master, not just at the transition. OVN's router never
            # ages out what it learned, and a master elected while the path to
            # OVN's gateway isn't forwarding yet (a router VM booting with its
            # node) announces into nothing: OVN then sent the services network
            # to the old master for 11 hours (seen in testing). Now it heals
            # within 10 s; LAN clients that missed the move heal the same way.
            garp_master_refresh 10
            notify_master "${becomeMaster}"
            notify_backup "${leaveMaster}"
            notify_fault "${leaveMaster}"
            notify_stop "${leaveMaster}"
          '';
        };
      };

      # ---------------------------------------------------------- IPv6 adverts
      # Started and stopped by keepalived: only the master advertises, always
      # from fe80::1, so clients' routes survive a failover.
      services.radvd = {
        enable = true;
        config = lib.concatStrings (lib.mapAttrsToList (seg: s: ''
          interface ${seg} {
            AdvSendAdvert on;
            AdvDefaultLifetime 0;          # not a default router: internet stays on IPv4
            AdvRASrcAddress { fe80::1; };
            MinRtrAdvInterval 30;
            MaxRtrAdvInterval 100;
            prefix ${s.v6}::/64 {
              AdvOnLink ${if s.onLink then "on" else "off"};
              AdvAutonomous on;
              DeprecatePrefix off;
            };
            route ${ula} {
              AdvRouteLifetime 1800;
              RemoveRoute off;
            };
          };
        '') raSegs);
      };
      systemd.services.radvd.wantedBy = lib.mkForce [ ];

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
          # A segment with dhcpClass hands out addresses only to clients whose
          # vendor class (DHCP option 60) starts with it -- UniFi gear sends
          # "ubnt". Keeps whatever else gets plugged into an infra port off it
          # (spoofable: the switch port profiles are the real gate).
          client-classes = lib.mapAttrsToList (seg: s: {
            name = "${seg}-gear";
            test = "substring(option[60].text, 0, ${toString (lib.stringLength s.dhcpClass)}) == '${s.dhcpClass}'";
          }) (lib.filterAttrs (_: s: s ? dhcpClass) clientSegs);
          # Fixed subnet ids (the second octet: trusted 1, iot 2, ...): ids by
          # position shifted when a segment was added, and every stored lease
          # failed Kea's sanity check. fix-del repairs such leases or drops them.
          sanity-checks.lease-checks = "fix-del";
          subnet4 = map (seg: let s = clientSegs.${seg}; in {
            id = lib.toInt (lib.elemAt (lib.splitString "." s.v4) 1);
            subnet = lan.v4net s;
            interface = seg;
            # A reserved device gets its address from whichever router answers
            # (outside every pool, and not subject to the pool's client class).
            reservations = map (r: {
              hw-address = r.mac; ip-address = lan.v4reserved s r.host; hostname = r.name;
            }) (s.reservations or [ ]);
            pools = [({ pool = lan.v4pool s host.id; }
              // lib.optionalAttrs (s ? dhcpClass) { client-classes = [ "${seg}-gear" ]; })];
            option-data = [
              { name = "routers"; data = "${s.v4}.1"; }
              { name = "domain-name-servers"; data = "${s.v4}.1"; }
            ];
          }) (lib.attrNames clientSegs);
        };
      };

      # ---------------------------------------------------------- DNS
      services.unbound = {
        enable = true;
        resolveLocalQueries = false;     # the router itself asks Blocky (below)
        settings.server = {
          interface = [ "127.0.0.1" ];
          port = 5335;
          access-control = [ "127.0.0.0/8 allow" ];
        };
      };
      services.blocky = {
        enable = true;
        settings = {
          ports.dns = 53;                # every address; the firewall decides who asks
          upstreams.groups.default = [ "127.0.0.1:5335" ];
          bootstrapDns = [{ upstream = "127.0.0.1:5335"; }];
          connectIPVersion = "v4";       # the router's IPv6 is local only: fetch lists over v4
          queryLog.type = "none";        # not every client's lookups in the journal
          blocking = {
            denylists.ads = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
            # Blocky tells clients apart by source address: a segment with
            # adblock = false gets the group "none", which has no lists. (An
            # empty list doesn't work: Blocky falls back to "default".)
            clientGroupsBlock = { default = [ "ads" ]; } // lib.mapAttrs' (_: s:
              lib.nameValuePair (lan.v4net s) [ "none" ]
            ) (lib.filterAttrs (_: s: !(s.adblock or true)) segments);
            # Answer straight away and fetch the lists in the background
            # (backups fetch through the master), retrying if that fails.
            loading = {
              strategy = "fast";
              refreshPeriod = "4h";
              downloads = { attempts = 10; cooldown = "30s"; };
            };
          };
        };
      };
      networking.nameservers = [ "127.0.0.1" ];

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

      # Tagged frames for VLANs this router doesn't serve would bypass the VLAN
      # devices and reach the untagged macvlan (and Kea on it): drop them as
      # they come in. Its own unit, loaded once "lan" exists: an ingress hook
      # on a missing device fails the whole ruleset -- at boot, the firewall.
      systemd.services.trunk-vlan-filter = lib.mkIf (untaggedSeg != null) {
        description = "Drop frames for VLANs this router does not serve";
        bindsTo = [ "sys-subsystem-net-devices-lan.device" ];
        after = [ "sys-subsystem-net-devices-lan.device" "nftables.service" ];
        wantedBy = [ "sys-subsystem-net-devices-lan.device" "multi-user.target" ];
        # NixOS's firewall starts with "flush ruleset": load again after it
        # restarts or reloads.
        partOf = [ "nftables.service" ];
        unitConfig.ReloadPropagatedFrom = [ "nftables.service" ];
        serviceConfig = let
          load = "${pkgs.nftables}/bin/nft -f ${pkgs.writeText "trunk-vlan-filter.nft" ''
          table netdev trunk
          delete table netdev trunk
          table netdev trunk {
            chain ingress {
              type filter hook ingress device "lan" priority filter; policy accept;
              vlan id != { ${lib.concatMapStringsSep ", " (seg: toString host.vlans.${seg}) (lib.attrNames taggedSegs)} } drop
            }
          }
          ''}";
        in { Type = "oneshot"; RemainAfterExit = true; ExecStart = load; ExecReload = load; };
      };

      networking.nftables.tables.router = {
        family = "inet";
        content = ''
          # A client VLAN reaches the router only at that VLAN's own
          # addresses (its gateway and DNS), not at the router's other legs.
          chain input {
            type filter hook input priority filter - 10; policy accept;
            ${lib.concatStrings (lib.mapAttrsToList (seg: s: ''
              iifname "${seg}" ip daddr 10.0.0.0/8 ip daddr != ${lan.v4net s} drop
              iifname "${seg}" ip6 daddr ${ula} ${lib.optionalString (s.v6 != null) "ip6 daddr != ${s.v6}::/64 "}drop
            '') clientSegs)}
          }

          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state invalid drop
            ct state { established, related } accept
            # IPv4 internet for everything on the LAN side (routers included).
            meta nfproto ipv4 iifname { ${segNames segments} } oifname "wan" accept
            # Local IPv6: Trusted may start connections to anything local.
            iifname "trusted" ip6 daddr ${ula} accept
            # Network gear has no IPv6: Trusted manages it (and the UniFi
            # controller) over IPv4.
            ${lib.optionalString (segments ? infra) ''iifname "trusted" oifname "infra" meta nfproto ipv4 accept''}
          }

          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "wan" masquerade
          }

          chain output {
            type filter hook output priority filter; policy accept;
            icmpv6 type nd-redirect drop   # IPv6 has no send_redirects switch
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

    # nixpkgs' Incus module loads br_netfilter, whose default sends every
    # bridged frame through the node's own firewall and conntrack -- all the
    # LAN traffic passing the router on br-trunk included. A node's own
    # packets coming back across its bridge (node -> router -> UniFi
    # controller on that node, or out again through the router it hosts) were
    # dropped there. br-trunk is a plain switch; Incus filters with nftables'
    # bridge family and doesn't need this.
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-ip6tables" = 0;
      "net.bridge.bridge-nf-call-arptables" = 0;
    };

    # The router's LAN side has carrier only while the node's trunk NIC does.
    # A router cut off from the LAN (dead cable or switch port) hears no VRRP
    # adverts and would make itself a second master, bringing up a second WAN
    # with the shared MAC. With its LAN link down keepalived goes to FAULT
    # instead, and the WAN stays down. (QEMU doesn't pass a host link's
    # carrier through to the guest, so this does, via QMP set_link.)
    systemd.services.router-lan-carrier = {
      description = "Mirror the trunk NIC's carrier onto the router VM's LAN link";
      bindsTo = [ "microvm@router.service" ];
      after = [ "microvm@router.service" ];
      wantedBy = [ "microvm@router.service" ];
      path = [ pkgs.socat pkgs.coreutils ];
      serviceConfig = { Restart = "always"; RestartSec = 5; };
      script = /* bash */ ''
        sock=/var/lib/microvms/router/${name}-router.sock
        until [ -S "$sock" ]; do sleep 1; done
        setlink() {
          printf '{"execute":"qmp_capabilities"}\n{"execute":"set_link","arguments":{"name":"vm-rtr-lan","up":%s}}\n' "$1" \
            | socat - "UNIX-CONNECT:$sock" >/dev/null
          echo "trunk ${host.trunk} carrier $2: router LAN link up=$1"
        }
        last=""
        while true; do
          # Unreadable (NIC admin-down) counts as no carrier.
          c=$(cat /sys/class/net/${host.trunk}/carrier 2>/dev/null || echo 0)
          if [ "$c" != "$last" ]; then
            if [ "$c" = 1 ]; then setlink true "$c"; else setlink false "$c"; fi
            last=$c
          fi
          sleep 1
        done
      '';
    };

    preservation.preserveAt."/persistent".directories = [
      { directory = "/var/lib/microvms"; user = "microvm"; group = "kvm"; mode = "0775"; }
    ];
    # The router's disk must belong to whatever uid microvm has this boot;
    # once a uid shift left qemu unable to open it and the router never came
    # up (global.nix now keeps uids stable; this keeps the router safe anyway).
    systemd.tmpfiles.rules = [ "z /var/lib/microvms/router/var.img 0644 microvm kvm - -" ];
  };
}
