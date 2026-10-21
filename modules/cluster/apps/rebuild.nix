{ ... }: {
  perSystem = { pkgs, lib, config, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.cluster-rebuild = cluster.mkApp {
      name = "cluster-rebuild";
      runtimeInputs = [  ];
      text = /* bash */ ''
        # Rebuild one cluster node whose boot disk died (or was wiped), keeping its
        # OSD disks, and rejoin it to Ceph and Incus. Run from a workstation while
        # the node is booted into the installer (USB stick, or the test lab's ISO):
        #
        #   nix run .#cluster-rebuild -- test-node3
        #
        # 1. preflight: node on the installer; the other nodes healthy and holding
        #    Ceph quorum; no instances still registered to the dead node
        # 2. reinstall the boot disk only (pre-seeded host key), wait for the mesh
        #    and for mesh SSH to the other nodes (what the `cluster` tool uses)
        # 3. Ceph: replace its mon, restore its mgr, re-activate its OSDs from the
        #    intact disks, wait for HEALTH_OK
        # 4. Incus: remove the dead member, join again with a fresh token
        #
        # Every step checks before acting and the script stops at the first problem.
        # `git add` new files first -- flakes only see tracked files.

        die()  { echo "rebuild: $*" >&2; exit 1; }
        step() { echo; echo "== $*"; }
        mesh() { echo "fd9a:7af:74af:ff::$1"; }
        copy() {  # copy <from-node> <path> <to-node> <path> [mode]
          on "$1" "cat $2" | on "$3" "install -D -m ''${5:-0600} /dev/stdin $4"
        }
        wait_for() {  # wait_for <seconds> <description> <node> <script that exits 0 when done>
          local secs=$1 what=$2 node=$3 check=$4 start
          start=$(date +%s)
          until on "$node" "$check" >/dev/null 2>&1; do
            [ $(( $(date +%s) - start )) -lt "$secs" ] || die "timed out after ''${secs}s waiting for: $what"
            sleep 5
          done
          echo "  ok  $what ($(( $(date +%s) - start ))s)"
        }

        target=''${1:-}
        [ -n "$target" ] || die "usage: nix run .#cluster-rebuild -- <node>"
        T=""; tid=0; i=0; others=()
        for n in "''${NODES[@]}"; do
          i=$((i + 1))
          if [ "$(name "$n")" = "$target" ]; then T=$n; tid=$i; else others+=("$n"); fi
        done
        [ -n "$T" ] || die "unknown node $target"
        CTRL=''${others[0]}
        addr=$(mesh "$tid")
        # Left on the node after the reinstall, removed when the rebuild finishes:
        # the only thing that lets a re-run resume (see preflight).
        REBUILD_MARK=/persistent/cluster-rebuild-in-progress   # / is tmpfs: must survive a reboot

        # ------------------------------------------------------------------ preflight
        step "preflight"
        resume=0
        if installer_find "$T"; then
          echo "  ok  $target is on the installer (''${INST_HOST[$target]}:''${INST_PORT[$target]})"
        elif on "$T" "test -e $REBUILD_MARK" 2>/dev/null; then
          # A previous run reinstalled it and stopped partway. Only a node carrying
          # the marker this script leaves after the install qualifies -- never a
          # working member, even one whose services are down. Every step below
          # skips what that run already finished.
          resume=1
          echo "  ok  $target was reinstalled by an unfinished rebuild -- resuming after the install"
        else
          die "$target isn't booted into an installer (checked its management address, and its mesh address through the other nodes)"
        fi

        for n in "''${others[@]}"; do
          on "$n" "systemctl is-active --quiet mesh-online" || die "$(name "$n") isn't healthy (mesh-online) -- fix that first"
        done
        quorum=$(on "$CTRL" "ceph quorum_status -f json | jq -r '.quorum_names | join(\" \")'")
        for n in "''${others[@]}"; do
          [[ " $quorum " == *" $(name "$n") "* ]] || die "$(name "$n") isn't in Ceph quorum ($quorum) -- fix that first"
        done
        echo "  ok  other nodes healthy, Ceph quorum: $quorum"

        # pipefail: an empty answer must mean "no instances", never "incus list
        # failed" -- just after a node drops, Incus's database can time out while it
        # picks a new leader (seen in testing). Retry for 2 minutes, then give up.
        start=$(date +%s)
        until stuck=$(on "$CTRL" "set -o pipefail; incus list -f json </dev/null | jq -r --arg n $target '.[] | select(.location == \$n) | .name'" 2>/dev/null); do
          [ $(( $(date +%s) - start )) -lt 120 ] || die "incus list on $(name "$CTRL") keeps failing -- can't tell whether instances are still registered to $target"
          sleep 5
        done
        [ -z "$stuck" ] || die "instances still registered to $target: $stuck. Removing the member would delete them. Move or evacuate them first."
        echo "  ok  no instances registered to $target"

        expected_osds=$(nix eval --raw ".#nixosConfigurations.$target.config.var.cluster.osdIds" --apply 'builtins.concatStringsSep " "' 2>/dev/null)
        echo "  ..  $target should have OSDs: $expected_osds"


        # ----------------------------------------------------------------- ovn raft
        # The reinstalled node joins the OVN databases as a new Raft member. Its old
        # membership died with the boot disk and must go first: left in, each
        # database would count 4 members, one dead, and need 3 alive for quorum.
        # (On a resumed run the new node may have joined already: keep its member.)
        step "OVN: drop $target's old database membership"
        for db in nb sb; do
          dbname=OVN_Northbound; port=6643; [ $db = sb ] && { dbname=OVN_Southbound; port=6644; }
          ctl=/run/ovn/ovn''${db}_db.ctl
          cur=""
          [ $resume = 1 ] && cur=$(on "$T" "ovs-appctl -t $ctl cluster/sid $dbname 2>/dev/null | cut -c1-4" </dev/null || true)
          olds=$(on "$CTRL" "ovs-appctl -t $ctl cluster/status $dbname | awk -v a='tcp:[$addr]:$port' '/^Servers:/ {s=1; next} s && index(\$0, a) {print \$1}'" </dev/null)
          for sid in $olds; do
            [ "$sid" = "$cur" ] && continue
            on "$CTRL" "ovs-appctl -t $ctl cluster/kick $dbname $sid" </dev/null >/dev/null
            echo "  ok  removed $target's old $dbname member $sid"
          done
        done

        # -------------------------------------------------------------------- install
        if [ $resume = 0 ]; then
          step "reinstall the boot disk"
          ${config.packages.cluster-testlab}/bin/cluster-testlab "$target"
        fi
        wait_for 600 "$target booted, mesh up" "$T" 'systemctl is-active --quiet mesh-online'
        on "$T" "touch $REBUILD_MARK"
        # The `cluster` tool on the rebuilt node reaches every other node over the
        # mesh (needs its key decrypted with the pre-seeded host key). Tailscale is
        # only remote access -- reported at the end, never waited for.
        wait_for 120 "$target reaches the other nodes over mesh SSH" "$T" "runuser -u shot -- cluster check-ssh"
        # A fresh node asks to join the OVN databases by itself (ovn.nix); its old
        # membership was dropped above.
        wait_for 180 "$target rejoined both OVN databases" "$T" \
          "for d in nb:OVN_Northbound sb:OVN_Southbound; do ovs-appctl -t /run/ovn/ovn\''${d%%:*}_db.ctl cluster/status \''${d#*:} | grep -qx 'Status: cluster member' || exit 1; done"
        wait_for 180 "$target's router VM running" "$T" "systemctl is-active --quiet microvm@router"

        # ---------------------------------------------------------------------- ceph
        step "Ceph: monitor"
        if on "$CTRL" "ceph quorum_status -f json | jq -e --arg n $target '.quorum_names | index(\$n)' >/dev/null" </dev/null 2>&1; then
          echo "  ok  mon.$target is already in quorum"
        else
        on "$CTRL" bash -euo pipefail -s <<EOF
        # The old mon's store died with the boot disk; drop it from the monmap and
        # let the fresh one join. Quorum stays 2 of the remaining 2.
        if ceph mon dump -f json | jq -e --arg n $target '.mons[] | select(.name == \$n)' >/dev/null; then
          ceph mon remove $target
        fi
        ceph mon getmap -o /tmp/rebuild.monmap
        ceph auth get mon. -o /tmp/rebuild.mon.keyring
        ceph auth get client.bootstrap-osd -o /tmp/rebuild.bootstrap-osd.keyring
        EOF
        copy "$CTRL" /tmp/rebuild.monmap "$T" /tmp/rebuild.monmap 0644
        copy "$CTRL" /tmp/rebuild.mon.keyring "$T" /tmp/rebuild.mon.keyring
        copy "$CTRL" /persistent/etc/ceph/ceph.client.admin.keyring "$T" /persistent/etc/ceph/ceph.client.admin.keyring
        copy "$CTRL" /persistent/etc/ceph/ceph.client.status.keyring "$T" /persistent/etc/ceph/ceph.client.status.keyring 0640
        copy "$CTRL" /tmp/rebuild.bootstrap-osd.keyring "$T" /var/lib/ceph/bootstrap-osd/ceph.keyring
        on "$CTRL" "rm -f /tmp/rebuild.monmap /tmp/rebuild.mon.keyring /tmp/rebuild.bootstrap-osd.keyring"

        on "$T" bash -euo pipefail -s <<EOF
        chgrp cluster-read /persistent/etc/ceph/ceph.client.status.keyring
        chown ceph:ceph /tmp/rebuild.monmap /tmp/rebuild.mon.keyring
        install -d -o ceph -g ceph /var/lib/ceph/mon
        rm -rf /var/lib/ceph/mon/ceph-$target
        runuser -u ceph -- ceph-mon --mkfs -i $target --monmap /tmp/rebuild.monmap --keyring /tmp/rebuild.mon.keyring
        touch /var/lib/ceph/mon/ceph-$target/done
        rm -f /tmp/rebuild.monmap /tmp/rebuild.mon.keyring
        systemctl start ceph-mon-$target
        EOF
        wait_for 300 "mon.$target back in quorum" "$CTRL" \
          "ceph quorum_status -f json | jq -e --arg n $target '.quorum_names | index(\$n)' >/dev/null"
        fi

        step "Ceph: manager"
        if on "$T" "systemctl is-active --quiet ceph-mgr-$target" </dev/null; then
          echo "  ok  mgr.$target already running"
        else
        on "$T" bash -euo pipefail -s <<EOF
        install -d -o ceph -g ceph /var/lib/ceph/mgr/ceph-$target
        ceph auth get mgr.$target -o /var/lib/ceph/mgr/ceph-$target/keyring
        chown ceph:ceph /var/lib/ceph/mgr/ceph-$target/keyring
        systemctl start ceph-mgr-$target
        EOF
          echo "  ok  mgr.$target started"
        fi

        step "Ceph: OSDs from the intact disks"
        found=$(on "$T" "ceph-volume lvm list --format json | jq -r 'to_entries[] | \"\(.key) \(.value[0].tags[\"ceph.osd_fsid\"]) \(.value[0].devices | join(\",\"))\"'")
        [ -n "$found" ] || die "no Ceph OSD volumes found on $target's disks -- were they wiped? (use cluster replace-osd for a dead OSD disk)"
        while read -r id fsid devs; do
          if [[ " $expected_osds " != *" $id "* ]]; then
            die "found osd.$id on $devs, but $target should only have: $expected_osds -- wrong disks in this node?"
          fi
          if on "$T" "systemctl is-active --quiet ceph-osd-$id" </dev/null; then echo "  ok  osd.$id already running"; continue; fi
          # </dev/null: ssh would otherwise read the rest of this loop's input
          on "$T" "ceph-volume lvm activate --no-tmpfs --no-systemd $id $fsid >/dev/null && systemctl start ceph-osd-$id" </dev/null
          echo "  ok  osd.$id re-activated from $devs"
        done <<<"$found"
        for id in $expected_osds; do
          grep -q "^$id " <<<"$found" || echo "  !!  osd.$id not found on $target -- its disk may be dead: cluster replace-osd"
        done
        wait_for 900 "Ceph HEALTH_OK" "$CTRL" 'ceph health | grep -q HEALTH_OK'
        # HEALTH_OK alone can hide a missing OSD: after 10 min down Ceph marks it out
        # and re-replicates without it (seen in testing). Check each one is up and in.
        for id in $expected_osds; do
          state=$(on "$CTRL" "ceph osd dump -f json | jq -r '.osds[] | select(.osd == $id) | \"\(.up) \(.in)\"'" </dev/null)
          [ "$state" = "1 1" ] || die "osd.$id isn't up and in (up/in: ''${state:-missing}) -- check 'cluster debug'"
          echo "  ok  osd.$id up and in"
        done

        # ---------------------------------------------------------------------- incus
        step "Incus: rejoin"
        if on "$CTRL" "incus cluster list -f csv -c ns </dev/null | grep -qx '$target,ONLINE'" </dev/null; then
          echo "  ok  $target is already an Incus member"
        else
        # The member's database and identity died with the boot disk; remove it and
        # join again. Safe because preflight confirmed no instances are registered to it.
        on "$CTRL" "! incus cluster list -f csv -c n </dev/null | grep -qx $target || incus cluster remove $target --force --yes </dev/null"
        # Removing the member leaves its server certificate trusted (seen: the
        # old test-node2's, after its rebuild). Its key died with the disk, and
        # every join below starts from an empty Incus with a new one.
        on "$CTRL" "incus config trust list -f json </dev/null | jq -r '.[] | select(.type==\"server\" and .name==\"$target\") | .fingerprint' | while read -r fp; do incus config trust remove \$fp </dev/null && echo \"  ok  removed $target's old certificate \''${fp:0:12}\"; done"
        # A failed join leaves a half-made member database behind (pools and
        # networks created before the error), and the next join then fails on it.
        # The fresh node's Incus holds nothing yet -- preflight confirmed no
        # instances are registered to it -- so start every join attempt from empty.
        on "$T" bash -euo pipefail -s <<'EOF'
        systemctl stop incus.service incus.socket
        find /var/lib/incus -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        systemctl start incus.socket incus.service
        EOF
        on "$CTRL" "incus cluster list-tokens -f csv </dev/null | awk -F, -v n=$target '\$1==n {print \$1}' | xargs -r -n1 incus cluster revoke-token </dev/null" || true
        token=$(on "$CTRL" "incus cluster add $target -q </dev/null")
        # Member-specific settings the join must supply: the storage pool's source,
        # and (once cluster-ovn-bootstrap has made it) the OVN uplink's parent.
        transit_member=""
        if on "$CTRL" "incus network list -f csv -c n </dev/null | grep -qx transit" </dev/null; then
          transit_member="  - entity: network
            name: transit
            key: parent
            value: br-trunk"
        fi
        on "$T" "incus admin init --preseed" <<EOF
        cluster:
          enabled: true
          server_name: $target
          server_address: "[$addr]:8443"
          cluster_token: "$token"
          member_config:
          - entity: storage-pool
            name: remote
            key: source
            value: vms
        $transit_member
        EOF
        wait_for 120 "$target ONLINE in Incus" "$CTRL" \
          "incus cluster list -f csv -c ns </dev/null | grep -qx '$target,ONLINE'"
        fi

        # ------------------------------------------------------------------- report
        step "done"
        on "$T" "rm -f $REBUILD_MARK"
        on "$CTRL" "ceph -s | sed -n '/health:/p;/mon:/p;/osd:/p'; incus cluster list -f csv -c ns </dev/null"
        dns=$(on "$T" "tailscale status --self --peers=false --json | jq -r 'select(.BackendState == \"Running\") | .Self.DNSName'" 2>/dev/null || true)
        if [ -z "$dns" ]; then
          echo
          echo "Tailscale: $target isn't on the tailnet yet (no internet?). Only remote access needs"
          echo "it; it joins on its own once it can reach Tailscale."
        elif [[ "''${dns%%.*}" != "$target" ]]; then
          short=''${dns%%.*}
          echo
          echo "Tailscale: the rebuilt node joined as '$short' because the old '$target' entry"
          echo "was still in the tailnet. Only its tailnet name is affected. To tidy up in the"
          echo "admin console (Machines): delete the old, offline '$target',"
          echo "then rename '$short' back to '$target'."
        fi
        echo "$target rebuilt and rejoined."
      '';
    };
  };
}
