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
        # 2. each member's part of the "transit" uplink network (parent=br-trunk),
        #    left pending
        # 3. `nix run .#tofu -- apply` (opentofu/): Incus's link to the Northbound
        #    database, the transit and services networks -- and everything
        #    cluster-incus-bootstrap left pending
        #
        # Safe to re-run: each step skips whatever already exists. Creating the Raft
        # clusters is refused if any node is already a member of one.

        FIRST=''${NODES[0]}
        mesh() { echo "fd9a:7af:74af:ff::$1"; }

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

        echo "== each member's part of the transit uplink network"
        if [ "\$(state network transit)" != CREATED ]; then
          # "parent" is member-specific: each member's own br-trunk. The
          # cluster-wide network (VLAN, addresses) is OpenTofu's.
          for m in $members; do incus network create transit --type=physical parent=br-trunk --target \$m </dev/null >/dev/null 2>&1 || true; done
        else echo "network transit exists"; fi
        EOF

        echo "== OpenTofu: the pool, the networks, the default profile, the link to OVN"
        nix run .#tofu -- apply
      '';
    };
  };
}
