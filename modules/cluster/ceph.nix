{ lib, ... }: {
  # Ceph on every cluster node: a mon + mgr each (3 mons = quorum survives
  # one node down), and the node's OSD disks. Everything binds to the mesh
  # loopbacks only (fd9a:7af:74af:ff::<id>), so Ceph traffic never leaves
  # the Thunderbolt ring.
  #
  # What Nix can't declare -- keyrings, the monmap, creating the OSDs, pool
  # sizes -- is done once by cluster-ceph-bootstrap (nix run .#cluster-ceph-bootstrap). Until then every
  # daemon sits idle: the nixpkgs module only starts a daemon once its
  # keyring exists.
  flake.nixosModules.clusterCeph = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host hosts;
    mesh = h: "fd9a:7af:74af:ff::${toString h.id}";
    monAddr = h: "[v2:[${mesh h}]:3300,v1:[${mesh h}]:6789]";
    cfg = config.services.ceph;

    daemonUnits = lib.concatMap (type:
      lib.optionals cfg.${type}.enable (map (d: "ceph-${type}-${d}") cfg.${type}.daemons)
    ) [ "mon" "mgr" "osd" ];
  in {
    options.var.cluster.osdIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      # Two OSD ids per node, derived from the node id: node1 -> 0 1, node2 -> 2 3, ...
      default = lib.imap0 (i: _: toString ((host.id - 1) * 2 + i)) host.osdDisks;
      description = "OSD ids on this node, one per entry in host.osdDisks.";
    };

    config = {
      services.ceph = {
        enable = true;
        global = {
          fsid = host.cephFsid;
          monInitialMembers = lib.concatStringsSep "," (lib.attrNames hosts);
          monHost = lib.concatStringsSep "," (map monAddr (lib.attrValues hosts));
          publicNetwork = "fd9a:7af:74af:ff::/64";
        };
        extraConfig = {
          ms_bind_ipv6 = "true";
          ms_bind_ipv4 = "false";
          osd_pool_default_size = "3";
          osd_pool_default_min_size = "2";
          mon_allow_pool_delete = "false";
          # Space the OSDs free goes back to the disk: an SSD's own wear
          # levelling, and a test node's thin disk, which only grew without
          # it (it filled the host's pool on 2026-10-27). Async: in the
          # background, not in the write path.
          bdev_enable_discard = "true";
          bdev_async_discard_threads = "1";
        } // lib.optionalAttrs (host ? osdMemoryTarget) {
          osd_memory_target = toString host.osdMemoryTarget;
        };
        mon = { enable = true; daemons = [ name ]; };
        mgr = { enable = true; daemons = [ name ]; };
        osd = { enable = true; daemons = config.var.cluster.osdIds; };
      };

      # Same reasoning as nixpkgs' own multi-node Ceph test: daemons have to
      # come back from arbitrary outages, so never hit a start limit. And
      # none of them start before the mesh they bind to is up.
      systemd.services = lib.mkMerge [ (lib.genAttrs daemonUnits (_: {
        after = [ "mesh-online.service" ];
        wants = [ "mesh-online.service" ];
        serviceConfig.Restart = lib.mkForce "always";
        serviceConfig.RestartSec = lib.mkForce "5";
        unitConfig.StartLimitIntervalSec = lib.mkForce 0;
      }))
      # A planned stop (a reboot, a deploy) shouldn't pause everyone's I/O.
      # It did, for 15-16 s every time in testing: the mon and the OSDs
      # stopped back to back, the OSDs marked themselves down, and the others
      # began re-peering -- which has to commit to the OSD map, so needs
      # every mon in the quorum, and this one was already gone. The rest
      # only noticed when its lease ran out (10 s), then held an election
      # (5 s); writes resumed the moment the new quorum formed. The OSDs
      # already stop first (they're ordered after ceph-mon.target), so the
      # mon now stays until the OSD map has been quiet for 3 s -- peering
      # done -- or 30 s at most. Its leaving then commits nothing. (A crash
      # still pays the full pause; accepted.)
      {
        "ceph-mon-${name}" = {
          path = [ pkgs.ceph pkgs.jq pkgs.coreutils ];
          preStop = /* bash */ ''
            # It runs as the mon (user ceph), so it uses the mon's own key. No
            # quorum (the whole cluster stopping): nothing to wait for.
            key=/var/lib/ceph/mon/ceph-${name}/keyring
            [ -s "$key" ] || exit 0
            epoch() { timeout 5 ceph -n mon. -k "$key" osd stat -f json 2>/dev/null | jq -e .epoch; }
            last=$(epoch) || { echo "no answer from the monitors: not waiting"; exit 0; }
            quiet=0
            for _ in $(seq 1 30); do
              sleep 1
              e=$(epoch) || exit 0
              if [ "$e" = "$last" ]; then
                quiet=$((quiet + 1))
                [ $quiet -lt 3 ] || { echo "OSD map quiet at epoch $e: leaving the quorum"; exit 0; }
              else
                quiet=0; last=$e
              fi
            done
            echo "OSD map still changing after 30 s: stopping anyway"
          '';
        };
      }
      {
        # ceph.target only means the daemons were started. When Incus
        # starts it reads its storage pool once (`rbd info incus_vms` in
        # the vms pool); if that read hangs it's killed, and Incus marks the
        # pool unavailable, so none of its instances autostart. Seen after
        # whole-cluster power cuts, both before mon quorum formed and after
        # (quorum up, the pool's placement groups not active yet). Wait for
        # that exact read to work. Give up after 90 s so a slow Ceph can't
        # hold Incus back for good (incus-autostart-recover in incus.nix
        # then starts the instances once the pool answers), and keep
        # checking in the background like mesh-online. A node that came up
        # alone never gets this far: its Incus waits behind mesh-online
        # until a neighbour appears (seen in testing). Before the cluster is
        # bootstrapped (no admin keyring, or no incus_vms image yet) there's
        # nothing to wait for.
        ceph-online = {
          description = "Wait until Incus's Ceph pool answers";
          wantedBy = [ "multi-user.target" ];
          after = map (u: "${u}.service") daemonUnits ++ [ "mesh-online.service" ];
          wants = map (u: "${u}.service") daemonUnits ++ [ "mesh-online.service" ];
          path = [ pkgs.ceph pkgs.coreutils pkgs.gnugrep ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "3min";
            Restart = "on-failure";
            RestartSec = "15s";
          };
          unitConfig.StartLimitIntervalSec = 0;
          script = /* bash */ ''
            [ -s /etc/ceph/ceph.client.admin.keyring ] || { echo "Ceph isn't bootstrapped yet"; exit 0; }
            # rbd hangs rather than failing while the cluster can't serve the
            # read, so every call gets a timeout.
            vms() { timeout 15 rbd --id admin --cluster ceph --pool vms "$@"; }
            deadline=$((SECONDS + 90))
            while [ $SECONDS -lt $deadline ]; do
              if images=$(vms ls 2>/dev/null); then
                grep -qx incus_vms <<<"$images" || { echo "no Incus storage pool yet"; exit 0; }
                if vms info incus_vms >/dev/null 2>&1; then
                  echo "Incus's pool answers after ''${SECONDS}s"
                  exit 0
                fi
              fi
              sleep 5
            done
            echo "Incus's pool still doesn't answer after 90 s (no quorum, or placement groups not active)" >&2
            exit 1
          '';
        };
      } ];

      preservation.preserveAt."/persistent" = lib.mkIf cfg.enable {
        directories = [
          { directory = "/var/lib/ceph"; user = "ceph"; group = "ceph"; mode = "0750"; }
        ];
        files = lib.optionals cfg.mon.enable [
          { file = "/etc/ceph/ceph.client.admin.keyring"; mode = "0600"; how = "symlink"; }
          # Read-only (mon/mgr 'allow r'), group cluster-read (tools.nix) --
          # what the `cluster` tool uses, so debug/restore never need root.
          { file = "/etc/ceph/ceph.client.status.keyring"; mode = "0640"; how = "symlink"; }
        ];
      };

      # The bootstrap and rebuild scripts set the keyring's group when they
      # create it; this keeps it right on every boot and switch (it was group
      # wheel before cluster-read existed).
      systemd.tmpfiles.rules = lib.mkIf (cfg.enable && cfg.mon.enable) [
        "z /persistent/etc/ceph/ceph.client.status.keyring 0640 root cluster-read - -"
      ];

      # ceph-volume needs lvm on PATH; the OSDs live in LVM volumes it creates.
      environment.systemPackages = [ pkgs.ceph pkgs.lvm2 ];
    };
  };
}
