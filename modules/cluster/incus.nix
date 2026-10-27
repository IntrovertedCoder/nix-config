{ lib, ... }: {
  # Incus on every cluster node. The cluster itself (init, joins, the Ceph
  # storage pool, networks, profiles) is created once by
  # the cluster-incus-bootstrap app -- Incus' preseed can't join a cluster, since
  # joining needs a one-time token from an existing member.
  #
  # Members talk to each other on the mesh loopbacks, like Ceph.
  flake.nixosModules.clusterIncus = { config, lib, pkgs, ... }: let
    cfg = config.virtualisation.incus;
    # Seconds a member may be offline before its instances restart elsewhere
    # (instances were back 95-120s after a node dropped, in the test lab).
    # 60 for the test lab; the real value waits on measured Thunderbolt
    # reconvergence (see the design doc's open questions).
    healingThreshold = 60;
    # The other nodes' mesh loopbacks (the addresses mesh.nix puts on lo).
    meshPeers = map (h: "fd9a:7af:74af:ff::${toString h.id}")
      (lib.filter (h: h.id != config.var.cluster.host.id) (lib.attrValues config.var.cluster.hosts));
  in {
    virtualisation.incus.enable = true;

    # Puts the ceph client tools on incusd's PATH (see the nixpkgs module);
    # Incus maps RBD volumes with the kernel client.
    services.ceph.client.enable = true;

    # Incus attaches Ceph disks to VMs through QEMU's own rbd driver (not
    # krbd), and nixpkgs' qemu_kvm is built without it. qemu_full has it and
    # is in cache.nixos.org; the cost is a ~3 GB closure (samba, glusterfs
    # come along). The slimmer `qemu_kvm.override { cephSupport = true; }`
    # works too but recompiles QEMU on every nixpkgs bump.
    nixpkgs.overlays = [ (final: prev: { qemu_kvm = prev.qemu_full; }) ];

    users.users.shot.extraGroups = [ "incus-admin" ];

    systemd.services.incus = {
      after = [ "mesh-online.service" "ceph.target" "ceph-online.service" ];
      wants = [ "mesh-online.service" "ceph-online.service" ];
      # Healing guard, part 1. Incus measures a member's downtime from its
      # last heartbeat, so after a whole-cluster power cut every member looks
      # long overdue and the first ones up "heal" the rest: in testing, two
      # still-booting members were marked EVACUATED within seconds. Incus
      # applies patch.global.sql to the cluster database as it starts,
      # before healing can run: disable healing on every start, and let
      # incus-healing-arm turn it back on once the cluster has settled.
      # Only once this node has been part of the running cluster (marker left
      # by incus-healing-arm): on a fresh install there's no config table yet,
      # the patch fails and Incus never starts (that
      # broke cluster-rebuild's rejoin). A joining node gets the cluster's
      # database, healing setting and all, from the others.
      preStart = /* bash */ ''
        install -d -m 0700 /var/lib/incus/database
        if [ -e /var/lib/incus/.healing-guard ]; then
          echo "UPDATE config SET value = '0' WHERE key = 'cluster.healing_threshold';" \
            > /var/lib/incus/database/patch.global.sql
        else
          rm -f /var/lib/incus/database/patch.global.sql
        fi
      '';
    };

    # Healing guard, part 2: re-arm healing (cluster.healing_threshold) once
    # no member has been Offline for 2 minutes, or 10 minutes after the
    # cluster first answered, whichever comes first -- so a member that
    # really is dead still gets its instances moved, just later.
    systemd.services.incus-healing-arm = {
      description = "Re-enable Incus healing once the cluster has settled";
      # started with incus every time: each incus start disables healing again
      wantedBy = [ "incus.service" "multi-user.target" ];
      after = [ "incus.service" ];
      bindsTo = [ "incus.service" ];
      path = [ cfg.package pkgs.coreutils pkgs.gnugrep ];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      # waits as long as it takes (a fresh node joins the cluster later)
      serviceConfig.TimeoutStartSec = "infinity";
      script = /* bash */ ''
        first="" settled=""
        while :; do
          if members=$(incus cluster list -f csv -c s 2>/dev/null) && [ -n "$members" ]; then
            now=$(date +%s)
            first=''${first:-$now}
            # EVACUATED members are up (drained); only OFFLINE ones are still booting
            if grep -qx OFFLINE <<<"$members"; then settled=""; else settled=''${settled:-$now}; fi
            if { [ -n "$settled" ] && [ $((now - settled)) -ge 120 ]; } || [ $((now - first)) -ge 600 ]; then
              incus config set cluster.healing_threshold=${toString healingThreshold}
              echo "healing re-armed: cluster.healing_threshold=${toString healingThreshold}"
              # from now on every Incus start on this node disables healing first
              touch /var/lib/incus/.healing-guard
              exit 0
            fi
          fi
          sleep 10
        done
      '';
    };

    # When Incus starts before its Ceph pool answers (ceph-online gave up:
    # a node that came up alone, or Ceph slower than 90 s), it skips
    # autostarting this node's instances and never tries again by itself.
    # Start the ones Incus would have started: boot.autostart=true, or
    # unset (Incus's default: restore the last state) and running before.
    # An instance someone stopped on purpose stays stopped. Only this
    # node's instances -- every node runs this for its own. Runs in the
    # background (Type=simple) so a slow pool never holds up a boot or a
    # deploy; fails, and shows in `cluster debug`, if something still
    # won't start after 10 minutes. mesh-fence (below) stops it while the
    # node is fenced.
    systemd.services.incus-autostart-recover = {
      description = "Start this node's instances Incus didn't autostart";
      wantedBy = [ "incus.service" ];
      after = [ "incus.service" "ceph-online.service" ];
      bindsTo = [ "incus.service" ];
      path = [ cfg.package pkgs.coreutils pkgs.jq ];
      serviceConfig = {
        Type = "simple";
        RemainAfterExit = true;
      };
      script = /* bash */ ''
        me=${config.var.cluster.name}
        todo=""
        for i in $(seq 1 60); do
          # Incus may not answer yet right after it starts: retry, never
          # read a failed list as "nothing to do".
          if json=$(incus list -f json </dev/null 2>/dev/null); then
            todo=$(jq -r --arg me "$me" '.[]
              | select(.location == $me and .status == "Stopped")
              | select((.config["boot.autostart"] // "") as $a
                  | $a == "true" or ($a == "" and .config["volatile.last_state.power"] == "RUNNING"))
              | .name' <<<"$json")
            [ -n "$todo" ] || exit 0
            for n in $todo; do
              echo "starting $n (Incus didn't autostart it)"
              incus start "$n" </dev/null || true
            done
          fi
          sleep 10
        done
        echo "still not running after 10 minutes: $todo" >&2
        exit 1
      '';
    };

    # Self-fence a node cut off from the mesh but still on the LAN (design
    # doc, Fencing). The other two heal its instances elsewhere, but its
    # own copies keep running: the ones bridged onto the LAN (the UniFi
    # controller) answered with the same MAC and IP as their healed
    # copies, and sent traffic once the mesh came back (seen in testing).
    # So when no other node has answered a ping over the mesh for 45 s --
    # before healing can start (about 80 s: 20 s offline + 60 s threshold)
    # -- take this node's Incus instances off the network and kill them.
    # They're frozen on Ceph by then anyway. Pings test the path Ceph and
    # Incus actually use: an FRR that stopped answering doesn't count as a
    # cut unless the routes are gone too. The routers aren't Incus
    # instances and are never touched.
    #
    # Nothing in the fence may wait on the unreachable cluster, so it never
    # touches the Ceph disks: links down first (kernel only, instant -- a
    # process stuck on frozen Ceph I/O keeps its network namespace alive,
    # but can't answer on the LAN with every link down), then the kill.
    # Found in testing: `rbd unmap` blocks while cut off (the kill then only
    # ran once the mesh was back, on instances that had resumed), and disks
    # released after the mesh returned left the containers' mounts dead, so
    # Incus put them in Error and wouldn't start them. Left alone, the
    # mappings are simply reused. Incus itself keeps running too: stopping
    # it runs incus-startup's clean shutdown, which waits up to 10 minutes
    # on the frozen disks.
    #
    # The fence writes down what it killed. When a peer answers again it
    # starts exactly those that are still on this node. Not Incus's own
    # "last state": it records a killed VM as stopped once it can reach its
    # database again (seen in testing). If healing moved any of them
    # instead, this node's kernel Ceph client was blocklisted when healing
    # took their disks, and it outlives them (a kernel reference leak: the
    # rbd module can't even be unloaded), so every new map here fails
    # until a reboot. Then the fence reboots the node itself -- the normal
    # shutdown cleanup releases the old disks -- and `cluster restore`
    # brings the instances home. A stale client with no disk left (the leak
    # outside a fence) is flagged in /run/mesh-fence/stale-ceph-client,
    # which `cluster restore` refuses on and `cluster debug` reports
    # (tools.nix), as it refuses while any disk is still mapped.
    #
    # Armed only once a peer has answered this boot, so a node booting
    # alone (a staged start) is left alone. A node whose two peers both
    # die does fence, harmlessly: no quorum anywhere, its disks are frozen.
    systemd.services.mesh-fence = {
      description = "Take this node's Incus instances off the network when it's cut off from the mesh";
      wantedBy = [ "multi-user.target" ];
      after = [ "mesh-online.service" "incus.service" ];
      path = with pkgs; [
        iputils iproute2 util-linux procps coreutils gnugrep gnused gawk jq
        cfg.package config.systemd.package
      ];
      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
      };
      unitConfig.StartLimitIntervalSec = 0;
      script = /* bash */ ''
        me=${config.var.cluster.name}
        peers="${lib.concatStringsSep " " meshPeers}"
        # In /run: survives this unit restarting (a deploy) while fenced,
        # but not a reboot, which starts the instances again by itself.
        state=/run/mesh-fence
        fenced=$state/fenced      # present while fenced
        pending=$state/pending    # instances to start again once a peer answers
        moved=$state/moved        # healing moved at least one of them
        mkdir -p "$state"

        reach() {
          for p in $peers; do ping -6 -c1 -W2 "$p" >/dev/null 2>&1 && return 0; done
          return 1
        }

        # A kernel Ceph client with no disk left (only root sees clients).
        stale_client() {
          [ -z "$(ls /sys/bus/rbd/devices)" ] && ls -d /sys/kernel/debug/ceph/*.client* >/dev/null 2>&1
        }

        fence() {
          echo "no peer has answered over the mesh for 45 s: fencing"
          touch "$fenced"; : > "$pending"; rm -f "$moved"
          systemctl stop incus-autostart-recover.service || true
          # 1. Off the network. Containers: every link inside their
          # namespace (covers veth and macvlan NICs alike), found through
          # their LXC monitor -- titled "[lxc monitor] <path> <name>", parent
          # of the container's init. (Not the lxc.payload.* cgroup names: a
          # killed container leaves its cgroup behind and the restarted one
          # gets "<name>-1", seen in testing.) VMs: their host-side tap
          # devices (the router's are vm-rtr-*, untouched).
          for m in $(pgrep -f '^\[lxc monitor\]'); do
            name=$(tr '\0' ' ' < "/proc/$m/cmdline" | awk '{print $NF}')
            pid=$(pgrep -P "$m" | head -n1)
            [ -n "$name" ] && echo "$name" >> "$pending"
            [ -n "$pid" ] || continue
            for i in $(nsenter -t "$pid" -n ip -o link show | awk -F': ' '{print $2}' | cut -d@ -f1); do
              [ "$i" = lo ] || nsenter -t "$pid" -n ip link set "$i" down || true
            done
            echo "container $name: network down"
          done
          for p in $(pgrep --cgroup /system.slice/incus.service qemu-system); do
            name=$(tr '\0' '\n' < "/proc/$p/cmdline" | sed -n '/^-name$/{n;p;q}')
            [ -n "$name" ] && echo "$name" >> "$pending"
          done
          for t in $(ip -o link show | awk -F': ' '{print $2}' | cut -d@ -f1 | grep '^tap' || true); do
            ip link set "$t" down && echo "VM tap $t down"
          done
          # 2. Kill. A process stuck on Ceph I/O dies once that I/O fails
          # or the mesh is back.
          for cg in /sys/fs/cgroup/lxc.payload.*; do
            [ -e "$cg/cgroup.kill" ] && echo 1 > "$cg/cgroup.kill" || true
          done
          pkill -9 -f '^\[lxc monitor\]' || true
          pkill -9 --cgroup /system.slice/incus.service qemu-system || true
          echo "fenced: $(tr '\n' ' ' < "$pending")"
        }

        # Start what the fence killed, if it's still on this node and not
        # running yet. Called every loop while the mesh is back, until
        # nothing is left (or 10 minutes have passed).
        restart_killed() {
          json=$(timeout 15 incus list -f json </dev/null 2>/dev/null) || return 0
          left=""
          for n in $(cat "$pending"); do
            st=$(jq -r --arg n "$n" --arg me "$me" \
              '.[] | select(.name == $n) | if .location != $me then "moved" else .status end' <<<"$json")
            case $st in
              Running) echo "$n is running again" ;;
              moved) echo "$n was moved to another node by healing"; touch "$moved" ;;
              "") echo "$n no longer exists" ;;
              *) echo "starting $n again"; timeout 120 incus start "$n" </dev/null || true; left="$left $n" ;;
            esac
          done
          if [ -n "$left" ]; then printf '%s\n' $left > "$pending"; else : > "$pending"; fi
        }

        if [ -e "$fenced" ]; then
          echo "still fenced from before this unit restarted"
        else
          until reach; do sleep 5; done
          echo "armed: a peer answers over the mesh"
        fi
        last_ok=$(date +%s); back_since=$last_ok; stale_seen=0
        while true; do
          if reach; then
            last_ok=$(date +%s)
            if [ -e "$fenced" ]; then
              rm -f "$fenced"; back_since=$last_ok
              echo "a peer answers again: starting what the fence killed, where healing didn't move it"
            fi
            if [ -s "$pending" ]; then
              if [ $(( last_ok - back_since )) -lt 600 ]; then
                restart_killed
              else
                echo "gave up starting after 10 minutes: $(tr '\n' ' ' < "$pending")" >&2
                : > "$pending"
              fi
            fi
            # Everything handled and healing moved something: only a reboot
            # clears this node's blocklisted Ceph client (see above).
            if [ -e "$moved" ] && [ ! -s "$pending" ] && [ ! -e "$fenced" ]; then
              rm -f "$moved"
              echo "healing moved instances off this node, so its kernel Ceph client is blocklisted -- rebooting to clear it; then run: cluster restore $me"
              systemctl reboot
            fi
          elif [ ! -e "$fenced" ] && [ $(( $(date +%s) - last_ok )) -ge 45 ]; then
            fence
          fi
          # The flag for cluster restore / cluster debug: stale for two checks
          # in a row (a client also lingers a moment after a normal unmap).
          if stale_client; then stale_seen=$((stale_seen + 1)); else stale_seen=0; fi
          if [ "$stale_seen" -ge 2 ]; then touch "$state/stale-ceph-client"; else rm -f "$state/stale-ceph-client"; fi
          sleep 5
        done
      '';
    };

    # After a node is healed away from, Incus leaves its stale instance
    # copies running (fenced: their RBD client is blocklisted). Incus no
    # longer owns them, so it doesn't stop them at shutdown; they linger
    # until FRR has taken the mesh down, their RBD I/O can then never fail,
    # and the reboot hangs in systemd-shutdown forever (seen in testing).
    #
    # This unit's ExecStop runs after incus-startup and incus have stopped
    # (it's ordered Before= them) and before frr does (After= it), so the mesh is
    # still up: force-unmap whatever RBD devices are left (in-flight I/O
    # errors out instead of hanging), then kill any instance processes still
    # alive -- after Incus has stopped, anything left is stale.
    systemd.services.incus-stale-cleanup = {
      description = "Kill stale Incus instance copies before the mesh goes down";
      wantedBy = [ "multi-user.target" ];
      after = [ "frr.service" "mesh-online.service" "ceph.target" ];
      # incus-startup is what stops real instances at shutdown (softDaemonRestart)
      before = [ "incus.service" "incus-startup.service" ];
      path = [ pkgs.ceph pkgs.util-linux pkgs.coreutils pkgs.procps pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        TimeoutStopSec = "120s";
      };
      # A switch must never stop this unit: its stop IS the cleanup, and on a
      # live node it would unmap and kill running instances (happened once,
      # when this script changed). A changed script still applies at the next
      # shutdown -- systemd reads the new unit file.
      restartIfChanged = false;
      preStop = /* bash */ ''
        if systemctl is-active --quiet incus.service; then
          echo "incus is still running -- its instances aren't stale, not touching them"
          exit 0
        fi
        for dev in /sys/bus/rbd/devices/*; do
          [ -e "$dev" ] || continue
          id=''${dev##*/}
          echo "force-unmapping stale /dev/rbd$id"
          for m in $(findmnt -rn -S "/dev/rbd$id" -o TARGET); do umount -l "$m" || true; done
          # rbd runs with single_major: plain "remove" only answers EINVAL.
          rbd unmap -o force "/dev/rbd$id" || echo "$id force" > /sys/bus/rbd/remove_single_major || true
        done
        for cg in /sys/fs/cgroup/lxc.payload.*; do
          [ -e "$cg/cgroup.kill" ] || continue
          echo "killing stale container ''${cg##*.payload.}"
          echo 1 > "$cg/cgroup.kill" || true
        done
        pkill -9 -f '^\[lxc monitor\]' || true
        # Only Incus's own VMs: the router VMs (microvm@router) run qemu too,
        # and must outlive Incus.
        pkill -9 --cgroup /system.slice/incus.service qemu-system || true
      '';
    };

    # Instances on the per-member NAT bridge get DHCP/DNS from incusd's
    # dnsmasq on the host -- the only thing that bridge may reach here.
    var.nftFirewall.interfaces.incusbr0 = {
      allowedUDPPorts = [ 53 67 547 ];
      allowedTCPPorts = [ 53 ];
    };

    preservation.preserveAt."/persistent" = lib.mkIf cfg.enable {
      directories = [
        { directory = "/var/lib/incus"; mode = "0711"; }
        # OpenTofu's work directory for `nix run .#tofu` (apps/tofu.nix).
        # The state lives in Ceph, but during a run it's a file here: a run
        # that dies before saving it (the node crashes mid-apply) leaves the
        # newer one, and on disk that survives the reboot. The runner then
        # refuses to start over it.
        { directory = "/var/lib/elements-tofu"; mode = "0700"; }
      ];
    };
  };
}
