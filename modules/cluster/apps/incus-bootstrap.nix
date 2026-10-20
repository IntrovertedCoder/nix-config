{ ... }: {
  perSystem = { pkgs, lib, config, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.cluster-incus-bootstrap = cluster.mkApp {
      name = "cluster-incus-bootstrap";
      runtimeInputs = [  ];
      text = /* bash */ ''
        # One-time Incus cluster bootstrap -- the parts Nix can't declare
        # (modules/cluster/incus.nix has the rest). Run after cluster-ceph-bootstrap:
        #
        #   nix run .#cluster-incus-bootstrap
        #
        # 1. init the first node as a cluster, join the others with one-time tokens
        # 2. each member's part of the "remote" storage pool (on the Ceph `vms`
        #    pool) and of the incusbr0 NAT bridge, left pending
        # 3. (the cluster-wide pool and networks, the default profile and the
        #    link to OVN are OpenTofu's, opentofu/cluster.tf: cluster-ovn-bootstrap
        #    applies it; cluster.healing_threshold is set by incus-healing-arm on
        #    the nodes, see modules/cluster/incus.nix)
        #
        # Safe to re-run: each step skips whatever already exists.

        FIRST=''${NODES[0]}

        mesh() { echo "fd9a:7af:74af:ff::$1"; }

        echo "== preflight"
        for n in "''${NODES[@]}"; do
          on "$n" "systemctl is-active --quiet incus" || { echo "$(name "$n"): incus not running" >&2; exit 1; }
        done
        on "$FIRST" "ceph health | grep -q HEALTH_OK" || { echo "ceph is not HEALTH_OK" >&2; exit 1; }
        echo "== mesh SSH between the nodes (and Tailscale)"
        require_access
        # Every step below skips what already exists, so a run that stopped halfway
        # can simply be re-run.
        members_now=$(on "$FIRST" "incus cluster list -f csv -c n 2>/dev/null" </dev/null || true)

        if [ -z "$members_now" ]; then
          echo "== init $(name "$FIRST")"
          on "$FIRST" "incus admin init --preseed" <<EOF
        config:
          core.https_address: "[$(mesh 1)]:8443"
          cluster.https_address: "[$(mesh 1)]:8443"
        cluster:
          server_name: $(name "$FIRST")
          enabled: true
        EOF
        else
          echo "== $(name "$FIRST") already clustered"
        fi

        i=1
        for n in "''${NODES[@]:1}"; do
          i=$((i + 1))
          if grep -qx "$(name "$n")" <<<"$members_now"; then
            echo "== $(name "$n") already a member"; continue
          fi
          echo "== join $(name "$n")"
          token=$(on "$FIRST" "incus cluster add $(name "$n") -q" </dev/null)
          on "$n" "incus admin init --preseed" <<EOF
        cluster:
          enabled: true
          server_name: $(name "$n")
          server_address: "[$(mesh $i)]:8443"
          cluster_token: "$token"
        EOF
        done

        echo "== each member's part of the storage pool and incusbr0"
        members=""
        for n in "''${NODES[@]}"; do members+=" $(name "$n")"; done
        # This script reaches the node on stdin, so every incus command gets
        # </dev/null -- otherwise `incus ... create` reads the rest of the script as
        # YAML config.
        on "$FIRST" bash -euo pipefail -s <<EOF
        state() { incus \$1 list -f csv -c ns </dev/null | awk -F, -v n="\$2" '\$1==n {print \$2}'; }

        # Only the "pending" per-member parts ("source" is member-specific); the
        # cluster-wide pool and network come from OpenTofu (opentofu/cluster.tf).
        if [ "\$(state storage remote)" != CREATED ]; then
          for m in $members; do incus storage create remote ceph source=vms --target \$m </dev/null >/dev/null 2>&1 || true; done
        else echo "storage pool remote exists"; fi

        if [ "\$(state network incusbr0)" != CREATED ]; then
          for m in $members; do incus network create incusbr0 --target \$m </dev/null >/dev/null 2>&1 || true; done
        else echo "network incusbr0 exists"; fi

        # Healing (cluster.healing_threshold) is switched on by incus-healing-arm on
        # the nodes once no member has been Offline for 2 minutes.

        incus cluster list </dev/null
        EOF
        echo "== next: nix run .#cluster-ovn-bootstrap (it ends with the OpenTofu apply"
        echo "   that creates the pool, the networks and the default profile)"
      '';
    };
  };
}
