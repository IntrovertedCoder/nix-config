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
        ${lib.concatMapStrings (h: "peer ${mesh h} iburst\n") peers}
        allow fd9a:7af:74af:ff::/64
        local stratum 10 orphan
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
        # 12 tries, 10s apart, until the offset is under 10ms
        ExecStart = "-${pkgs.chrony}/bin/chronyc waitsync 12 0.01";
        TimeoutStartSec = "150s";
      };
    };

    preservation.preserveAt."/persistent" = lib.mkIf config.services.chrony.enable {
      directories = [
        { directory = config.services.chrony.directory; user = "chrony"; group = "chrony"; mode = "0750"; }
      ];
    };
  };
}
