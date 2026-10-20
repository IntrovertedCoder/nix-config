{ lib, ... }: {
  # Clock sync for cluster nodes. Ceph mons refuse to agree once their
  # clocks differ by more than 0.05s (MON_CLOCK_SKEW) -- seen in testing
  # right after a reboot, when timesyncd hadn't synced yet and nothing made
  # Ceph wait for it.
  #
  # chrony (what Ceph's docs recommend) syncs to the internet pool *and*
  # peers with the other nodes over the mesh. With no internet at all
  # (power cut, ISP down at cutover) the nodes still agree with each other
  # ("local stratum 10 orphan"), which is what the mons actually need.
  flake.nixosModules.clusterTime = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name hosts;
    mesh = h: "fd9a:7af:74af:ff::${toString h.id}";
    peers = lib.attrValues (lib.filterAttrs (n: _: n != name) hosts);
  in {
    services.chrony = {
      enable = true;   # replaces timesyncd (the module forces it off)
      extraConfig = ''
        ${lib.concatMapStrings (h: "peer ${mesh h} iburst minpoll 3\n") peers}
        allow fd9a:7af:74af:ff::/64
        # orphan: with no real source, the node with the smallest reference
        # ID serves its own clock and the others follow it. waitunsynced is
        # how long a fresh start waits for real sources first; orphan mode's
        # default (300s) outlasted chrony-wait-sync below, so a cold start
        # with no internet started Ceph on unsynced clocks (1.3s skew, seen
        # in testing). With internet, real sources sync well within 20s.
        # minpoll 3 (8s) lets the followers lock on in seconds, not minutes.
        local stratum 10 orphan waitunsynced 20
        # step (rather than slew) a large offset during the first updates
        makestep 0.1 3
      '';
    };

    # time-sync.target normally only means "chronyd started". Make it mean
    # "synced", so Ceph (ordered after it) starts with a good clock -- but
    # give up after ~2 minutes and boot anyway: a cluster with no internet
    # and no peers yet must still come up.
    systemd.services.chrony-wait-sync = {
      description = "Wait (bounded) for chrony to sync before Ceph starts";
      after = [ "chronyd.service" ];
      before = [ "time-sync.target" ];
      wantedBy = [ "time-sync.target" ];
      wants = [ "time-sync.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "150s";
      };
      # Synced (to the internet, a peer, or -- as the orphan leader -- its own
      # clock) with under 10ms left to correct; up to 2 minutes, then go on
      # anyway. Not `chronyc waitsync`: it never counts the local reference
      # as synced, so the orphan leader always waited out the full cap.
      path = [ pkgs.chrony pkgs.coreutils ];
      script = /* bash */ ''
        for _ in $(seq 120); do
          IFS=, read -r _ _ _ _ offset _ _ _ _ _ _ _ _ leap < <(chronyc -c tracking || true)
          if [ "$leap" = Normal ] && [ "''${offset#-}" \< 0.01 ]; then
            echo "chrony synced (offset ''${offset}s)"; exit 0
          fi
          sleep 1
        done
        echo "chrony not synced after 2 minutes -- starting anyway"
      '';
    };

    preservation.preserveAt."/persistent" = lib.mkIf config.services.chrony.enable {
      directories = [
        { directory = config.services.chrony.directory; user = "chrony"; group = "chrony"; mode = "0750"; }
      ];
    };
  };
}
