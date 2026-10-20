{ ... }: {
  perSystem = { pkgs, lib, config, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.cluster-ceph-bootstrap = cluster.mkApp {
      name = "cluster-ceph-bootstrap";
      runtimeInputs = [  ];
      text = /* bash */ ''
        # One-time Ceph bootstrap for the cluster -- the steps Nix can't declare
        # (modules/cluster/ceph.nix has the rest). Run from a workstation after the
        # nodes are installed and the mesh is up:
        #
        #   nix run .#cluster-ceph-bootstrap
        #
        # 1. keyrings + a monmap with all three mons, mon filesystems on each node
        # 2. a mgr on each node
        # 3. every disk in host.osdDisks becomes a BlueStore OSD (WIPES those disks)
        # 4. pools: vms 3x, media 2x (min_size 1), important 3x
        #
        # Same manual-deployment steps as nixpkgs' ceph-multi-node-bluestore test.
        # Refuses to run if any node already has a mon -- wipe/reinstall first.

        copy(){ on "$1" "cat $2" | on "$3" "install -D -m ''${5:-0600} /dev/stdin $4"; }  # from path to path mode

        FIRST=''${NODES[0]}

        echo "== preflight"
        for n in "''${NODES[@]}"; do
          on "$n" "systemctl is-active --quiet mesh-online" || { echo "$(name "$n"): mesh not up" >&2; exit 1; }
          if on "$n" "test -e /var/lib/ceph/mon/ceph-$(name "$n")/keyring"; then
            echo "$(name "$n") already has a mon -- this cluster is bootstrapped" >&2; exit 1
          fi
        done
        echo "== mesh SSH between the nodes (and Tailscale)"
        require_access
        FSID=$(on "$FIRST" "sed -n 's/^fsid *= *//p' /etc/ceph/ceph.conf")
        [ -n "$FSID" ] || { echo "no fsid in /etc/ceph/ceph.conf" >&2; exit 1; }
        echo "fsid $FSID"

        echo "== keyrings and monmap on $(name "$FIRST")"
        addv=""
        i=0
        for n in "''${NODES[@]}"; do
          i=$((i + 1)); m="fd9a:7af:74af:ff::$i"
          addv+=" --addv $(name "$n") '[v2:[$m]:3300,v1:[$m]:6789]'"
        done
        on "$FIRST" bash -euo pipefail -s <<EOF
        mkdir -p /persistent/etc/ceph /var/lib/ceph/bootstrap-osd
        # Written to /persistent directly: /etc/ceph/ceph.client.admin.keyring is
        # preservation's symlink to it, and writing through it can replace the link.
        ceph-authtool --create-keyring /tmp/ceph.mon.keyring --gen-key -n mon. --cap mon 'allow *'
        ceph-authtool --create-keyring /persistent/etc/ceph/ceph.client.admin.keyring --gen-key -n client.admin \
          --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
        ceph-authtool --create-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring --gen-key -n client.bootstrap-osd \
          --cap mon 'profile bootstrap-osd' --cap mgr 'allow r'
        ceph-authtool /tmp/ceph.mon.keyring --import-keyring /persistent/etc/ceph/ceph.client.admin.keyring
        ceph-authtool /tmp/ceph.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
        monmaptool --create $addv \
          --auth-allowed-ciphers aes256k --auth-preferred-cipher aes256k --auth-service-cipher aes256k \
          --fsid $FSID /tmp/monmap
        EOF

        for n in "''${NODES[@]:1}"; do
          echo "== copying keyrings to $(name "$n")"
          on "$n" "mkdir -p /persistent/etc/ceph"
          copy "$FIRST" /tmp/ceph.mon.keyring "$n" /tmp/ceph.mon.keyring
          copy "$FIRST" /tmp/monmap "$n" /tmp/monmap 0644
          copy "$FIRST" /persistent/etc/ceph/ceph.client.admin.keyring "$n" /persistent/etc/ceph/ceph.client.admin.keyring
          copy "$FIRST" /var/lib/ceph/bootstrap-osd/ceph.keyring "$n" /var/lib/ceph/bootstrap-osd/ceph.keyring
        done

        for n in "''${NODES[@]}"; do
          echo "== mon on $(name "$n")"
          on "$n" bash -euo pipefail -s <<EOF
        chown ceph:ceph /tmp/ceph.mon.keyring /tmp/monmap
        install -d -o ceph -g ceph /var/lib/ceph/mon
        runuser -u ceph -- ceph-mon --mkfs -i $(name "$n") --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring
        touch /var/lib/ceph/mon/ceph-$(name "$n")/done
        rm -f /tmp/ceph.mon.keyring /tmp/monmap
        systemctl start ceph-mon-$(name "$n")
        EOF
        done

        echo "== waiting for quorum"
        on "$FIRST" "timeout 180 bash -c 'until ceph mon stat 2>/dev/null | grep -q \"quorum 0,1,2\"; do sleep 3; done'"
        on "$FIRST" "ceph config set mon auth_allow_insecure_global_id_reclaim false"

        for n in "''${NODES[@]}"; do
          echo "== mgr on $(name "$n")"
          on "$n" bash -euo pipefail -s <<EOF
        install -d -o ceph -g ceph /var/lib/ceph/mgr/ceph-$(name "$n")
        ceph auth get-or-create mgr.$(name "$n") mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
          > /var/lib/ceph/mgr/ceph-$(name "$n")/keyring
        chown ceph:ceph /var/lib/ceph/mgr/ceph-$(name "$n")/keyring
        systemctl start ceph-mgr-$(name "$n")
        EOF
        done

        i=0
        for n in "''${NODES[@]}"; do
          i=$((i + 1))
          echo "== OSDs on $(name "$n")"
          # host.osdDisks and the matching ids come from the node's own config
          disks=$(nix eval --raw ".#nixosConfigurations.$(name "$n").config.var.cluster.host.osdDisks" \
                  --apply 'builtins.concatStringsSep " "' 2>/dev/null)
          ids=$(nix eval --raw ".#nixosConfigurations.$(name "$n").config.var.cluster.osdIds" \
                  --apply 'builtins.concatStringsSep " "' 2>/dev/null)
          on "$n" bash -euo pipefail -s <<EOF
        set -- $ids
        for disk in $disks; do
          id=\$1; shift
          ceph-volume lvm zap --destroy "\$disk"
          ceph-volume lvm prepare --objectstore bluestore --no-systemd --osd-id "\$id" --data "\$disk"
          fsid=\$(cat /var/lib/ceph/osd/ceph-\$id/fsid)
          ceph-volume lvm deactivate "\$id" "\$fsid"
          ceph-volume lvm activate --no-tmpfs --no-systemd "\$id" "\$fsid"
          sync
          systemctl start ceph-osd-\$id
        done
        EOF
        done

        echo "== read-only status key (for the cluster tool)"
        on "$FIRST" "ceph auth get-or-create client.status mon 'allow r' mgr 'allow r' \
          > /persistent/etc/ceph/ceph.client.status.keyring"
        for n in "''${NODES[@]}"; do
          [ "$n" = "$FIRST" ] || copy "$FIRST" /persistent/etc/ceph/ceph.client.status.keyring \
                                      "$n" /persistent/etc/ceph/ceph.client.status.keyring 0640
          on "$n" "chgrp cluster-read /persistent/etc/ceph/ceph.client.status.keyring; chmod 0640 /persistent/etc/ceph/ceph.client.status.keyring"
        done

        echo "== pools"
        on "$FIRST" bash -euo pipefail -s <<'EOF'
        timeout 300 bash -c 'until ceph osd stat | grep -q "6 osds: 6 up.*6 in"; do sleep 5; done'
        pool() {  # name size min_size
          ceph osd pool create "$1"
          ceph osd pool set "$1" size "$2"
          ceph osd pool set "$1" min_size "$3"
          ceph osd pool application enable "$1" rbd
          rbd pool init "$1"
        }
        pool vms 3 2
        pool media 2 1        # replaceable; keeps serving (and writing) with a host down
        pool important 3 2
        timeout 300 bash -c 'until ceph health | grep -q HEALTH_OK; do sleep 5; done' || true
        ceph -s
        ceph osd tree
        ceph osd pool ls detail
        EOF
      '';
    };
  };
}
