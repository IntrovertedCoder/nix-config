{ lib, ... }: {
  # Incus on every cluster node. The cluster itself (init, joins, the Ceph
  # storage pool, networks, profiles) is created once by
  # cluster-incus-bootstrap.sh -- Incus' preseed can't join a cluster, since
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
      # broke cluster-rebuild.sh's rejoin). A joining node gets the cluster's
      # database, healing setting and all, from the others.
      preStart = ''
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
      script = ''
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
    # won't start after 10 minutes.
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
      script = ''
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
      preStop = ''
        if systemctl is-active --quiet incus.service; then
          echo "incus is still running -- its instances aren't stale, not touching them"
          exit 0
        fi
        for dev in /sys/bus/rbd/devices/*; do
          [ -e "$dev" ] || continue
          id=''${dev##*/}
          echo "force-unmapping stale /dev/rbd$id"
          for m in $(findmnt -rn -S "/dev/rbd$id" -o TARGET); do umount -l "$m" || true; done
          rbd unmap -o force "/dev/rbd$id" || echo "$id force" > /sys/bus/rbd/remove || true
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
      ];
    };
  };
}
