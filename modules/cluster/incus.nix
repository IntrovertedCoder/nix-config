{ lib, ... }: {
  # Incus on every cluster node. The cluster itself (init, joins, the Ceph
  # storage pool, networks, profiles) is created once by
  # cluster-incus-bootstrap.sh -- Incus' preseed can't join a cluster, since
  # joining needs a one-time token from an existing member.
  #
  # Members talk to each other on the mesh loopbacks, like Ceph.
  flake.nixosModules.clusterIncus = { config, lib, pkgs, ... }: let
    cfg = config.virtualisation.incus;
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
      after = [ "mesh-online.service" "ceph.target" ];
      wants = [ "mesh-online.service" ];
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
      path = [ pkgs.ceph pkgs.util-linux pkgs.coreutils pkgs.procps ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        TimeoutStopSec = "120s";
      };
      preStop = ''
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
        pkill -9 qemu-system || true
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
