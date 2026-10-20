{ ... }: {
  perSystem = { pkgs, lib, config, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.cluster-ovn-bootstrap = cluster.mkApp {
      name = "cluster-ovn-bootstrap";
      runtimeInputs = [  ];
      text = /* bash */ ''
        # One-time OVN bootstrap -- the parts Nix can't declare (modules/cluster/ovn.nix
        # runs the daemons). Run after cluster-incus-bootstrap:
        #
        #   nix run .#cluster-ovn-bootstrap
        #
        # 1. create the OVN Northbound/Southbound Raft clusters on the first node;
        #    the other nodes are already asking to join and do so by themselves
        # 2. point Incus at the Northbound database
        # 3. "transit" uplink network: VLAN <transit> on br-trunk, where the router
        #    VMs are the gateway (10.91.0.1); OVN's router gets the pinned address the
        #    routers route the services network to (modules/cluster/_lan.nix)
        # 4. "services" OVN network: 10.90.0.0/24 and fd9a:7af:74af:90::/64, routed
        #    (no NAT in OVN -- the routers NAT once, to the WAN)
        #
        # Safe to re-run: each step skips whatever already exists. Creating the Raft
        # clusters is refused if any node is already a member of one.

        FIRST=''${NODES[0]}
        mesh() { echo "fd9a:7af:74af:ff::$1"; }
        remotes() { local p=$1 i out=""; for i in $(seq ''${#NODES[@]}); do out+="''${out:+,}tcp:[$(mesh "$i")]:$p"; done; echo "$out"; }

        # Network plan from the flake, so it's typed only once.
        eval_cfg() { nix eval --raw ".#nixosConfigurations.$(name "$FIRST").config.$1" --apply toString 2>/dev/null; }
        TRANSIT_VLAN=$(eval_cfg var.cluster.host.vlans.transit)
        # Instance traffic between nodes is Geneve over IPv6 on the ring: 78 bytes
        # of headers (IPv6 40, UDP 8, Geneve 8, OVN's metadata option 8, inner
        # Ethernet 14 -- measured: the tunnel reported a path MTU of 1500 - 78).
        # The real ring (65520) fits 1500; the test lab's 1500 does not.
        RING_MTU=$(eval_cfg var.cluster.host.ringMtu)
        OVN_MTU=$(( RING_MTU - 78 < 1500 ? RING_MTU - 78 : 1500 ))
        lan() { nix eval --raw --impure --expr "toString (import ./modules/cluster/_lan.nix).$1" 2>/dev/null; }
        T4=$(lan segments.transit.v4); T6=$(lan segments.transit.v6)
        S4=$(lan services.v4); S6=$(lan services.v6)
        U4=$(lan ovnUplink.v4); U6=$(lan ovnUplink.v6)
        echo "OVN MTU $OVN_MTU; transit VLAN $TRANSIT_VLAN: $T4.0/24 $T6::/64; services $S4.0/24 $S6::/64 behind $U4 / $U6"

        status() {  # status <node> <nb|sb>: this member's Raft status line
          local db=OVN_Northbound; [ "$2" = sb ] && db=OVN_Southbound
          on "$1" "ovs-appctl -t /run/ovn/ovn''${2}_db.ctl cluster/status $db 2>/dev/null | sed -n 's/^Status: //p'" </dev/null
        }

        echo "== preflight"
        for n in "''${NODES[@]}"; do
          for u in ovn-nb ovn-sb ovn-northd ovn-controller ovs-vswitchd incus; do
            on "$n" "systemctl is-active --quiet $u" </dev/null || { echo "$(name "$n"): $u not running" >&2; exit 1; }
          done
        done
        echo "== mesh SSH between the nodes (and Tailscale)"
        require_access

        for db in nb sb; do
          states=""; for n in "''${NODES[@]}"; do states+="$(name "$n")=$(status "$n" $db); "; done
          echo "== OVN ''${db^^}: $states"
          if grep -q "cluster member" <<<"$states"; then
            echo "   a Raft cluster exists; not creating one"
            continue
          fi
          echo "== create the ''${db^^} cluster on $(name "$FIRST")"
          port=6643; schema=ovn-nb
          [ $db = sb ] && { port=6644; schema=ovn-sb; }
          on "$FIRST" bash -euo pipefail -s <<EOF
        systemctl stop ovn-$db
        rm -f /var/lib/ovn/ovn''${db}_db.db /var/lib/ovn/.ovn''${db}_db.db.~lock~
        ovsdb-tool create-cluster /var/lib/ovn/ovn''${db}_db.db \$(dirname \$(readlink -f \$(command -v ovn-northd)))/../share/ovn/$schema.ovsschema tcp:[$(mesh 1)]:$port
        systemctl start ovn-$db
        EOF
        done

        echo "== waiting for every node to be a Raft member of both databases"
        start=$(date +%s)
        until ok=1; for n in "''${NODES[@]}"; do for db in nb sb; do
                [ "$(status "$n" $db)" = "cluster member" ] || ok=0; done; done; [ $ok = 1 ]; do
          [ $(( $(date +%s) - start )) -lt 120 ] || { echo "not all members after 2 min" >&2; exit 1; }
          sleep 3
        done
        on "$FIRST" "ovs-appctl -t /run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound | sed -n '/^Servers:/,\$p'" </dev/null

        members=""
        for n in "''${NODES[@]}"; do members+=" $(name "$n")"; done
        # This script reaches the node on stdin, so every incus command gets </dev/null.
        on "$FIRST" bash -euo pipefail -s <<EOF
        state() { incus \$1 list -f csv -c ns </dev/null | awk -F, -v n="\$2" '\$1==n {print \$2}'; }

        echo "== Incus -> OVN Northbound"
        incus config set network.ovn.northbound_connection="$(remotes 6641)" </dev/null

        echo "== transit uplink network"
        if [ "\$(state network transit)" != CREATED ]; then
          # "parent" is member-specific: each member's own br-trunk.
          for m in $members; do incus network create transit --type=physical parent=br-trunk --target \$m </dev/null || true; done
          incus network create transit --type=physical vlan=$TRANSIT_VLAN \
            ipv4.gateway=$T4.1/24 ipv4.ovn.ranges=$U4-$T4.19 ipv4.routes=$S4.0/24 \
            ipv6.gateway=$T6::1/64 ipv6.ovn.ranges=$U6-$T6::1f ipv6.routes=$S6::/64 \
            ovn.ingress_mode=routed dns.nameservers=$T4.1 </dev/null
        else echo "network transit exists"; fi

        echo "== services OVN network"
        if [ "\$(state network services)" != CREATED ]; then
          incus network create services --type=ovn network=transit \
            ipv4.address=$S4.1/24 ipv4.nat=false ipv6.address=$S6::1/64 ipv6.nat=false bridge.mtu=$OVN_MTU \
            volatile.network.ipv4.address=$U4 volatile.network.ipv6.address=$U6 </dev/null
        else echo "network services exists"; incus network set services bridge.mtu=$OVN_MTU </dev/null; fi

        incus network show transit </dev/null
        incus network show services </dev/null
        EOF
      '';
    };
  };
}
