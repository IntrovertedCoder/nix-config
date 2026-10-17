{ lib, ... }: {
  # Ceph on every cluster node: a mon + mgr each (3 mons = quorum survives
  # one node down), and the node's OSD disks. Everything binds to the mesh
  # loopbacks only (fd9a:7af:74af:ff::<id>), so Ceph traffic never leaves
  # the Thunderbolt ring.
  #
  # What Nix can't declare -- keyrings, the monmap, creating the OSDs, pool
  # sizes -- is done once by cluster-ceph-bootstrap.sh. Until then every
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
      systemd.services = lib.genAttrs daemonUnits (_: {
        after = [ "mesh-online.service" ];
        wants = [ "mesh-online.service" ];
        serviceConfig.Restart = lib.mkForce "always";
        serviceConfig.RestartSec = lib.mkForce "5";
        unitConfig.StartLimitIntervalSec = lib.mkForce 0;
      });

      preservation.preserveAt."/persistent" = lib.mkIf cfg.enable {
        directories = [
          { directory = "/var/lib/ceph"; user = "ceph"; group = "ceph"; mode = "0750"; }
        ];
        files = lib.optionals cfg.mon.enable [
          { file = "/etc/ceph/ceph.client.admin.keyring"; mode = "0600"; how = "symlink"; }
          # Read-only (mon/mgr 'allow r'), group wheel -- what the `cluster`
          # tool uses as shot, so debug/restore never need root.
          { file = "/etc/ceph/ceph.client.status.keyring"; mode = "0640"; how = "symlink"; }
        ];
      };

      # ceph-volume needs lvm on PATH; the OSDs live in LVM volumes it creates.
      environment.systemPackages = [ pkgs.ceph pkgs.lvm2 ];
    };
  };
}
