{ lib, ... }: {
  # OVN: the cluster-wide virtual network for Incus instances (design doc,
  # "Backend services ... their own Incus OVN network"). nixpkgs has the OVN
  # package but no module, so the daemons are declared here.
  #
  # - Northbound and Southbound databases: a 3-member Raft cluster (like the
  #   Ceph mons) on the mesh addresses, NB on 6641, SB on 6642, Raft on 6643
  #   and 6644. Plain TCP: the mesh is point-to-point cables between the
  #   nodes, and those interfaces are trusted already (node.nix).
  # - ovn-northd on every node; they take turns through a database lock.
  # - ovn-controller on every node, its Geneve tunnel endpoint on the node's
  #   mesh address, so instance traffic between nodes rides the mesh. Every
  #   node may host the gateway (enable-chassis-as-gw), once Incus has set up
  #   its uplink there (see ovn-controller below).
  #
  # A node never creates a database cluster by itself: with no database it
  # asks to join the existing one. Only cluster-ovn-bootstrap creates it,
  # once, on the first node -- so a rebuilt node can't start a second cluster.
  # (cluster-rebuild removes the dead node's old Raft membership first.)
  #
  # The networks themselves (the transit uplink and the services network)
  # are Incus objects, declared in OpenTofu (opentofu/cluster.tf).
  #
  # Status:  ovs-appctl -t /run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound
  #          ovn-sbctl show     (chassis and their tunnels)
  flake.nixosModules.clusterOvn = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host hosts;
    ovs = config.virtualisation.vswitch.package;
    ovn = pkgs.ovn;
    mesh = id: "fd9a:7af:74af:ff::${toString id}";
    me = mesh host.id;
    peers = lib.filter (h: h.id != host.id) (lib.attrValues hosts);
    remotes = port: lib.concatMapStringsSep "," (h: "tcp:[${mesh h.id}]:${toString port}") (lib.attrValues hosts);

    # OVS and OVN default to /usr/local/var/run/...; NixOS runs OVS in
    # /run/openvswitch (ovn-controller couldn't reach br-int's control socket).
    runDirs = { OVS_RUNDIR = "/run/openvswitch"; OVN_RUNDIR = "/run/ovn"; };

    mkDb = { db, schema, file, port, raftPort }: {
      environment = runDirs;
      description = "OVN ${db} database (Raft member)";
      wantedBy = [ "multi-user.target" ];
      after = [ "mesh-online.service" ];
      wants = [ "mesh-online.service" ];
      path = [ ovs pkgs.coreutils ];
      preStart = /* bash */ ''
        mkdir -p /var/lib/ovn /run/ovn
        if [ ! -e /var/lib/ovn/${file} ]; then
          # Never create: ask to join the cluster cluster-ovn-bootstrap.sh made.
          # Until it exists this member just keeps waiting (cluster/status:
          # "joining cluster").
          echo "no ${db} database here: joining the existing cluster"
          ovsdb-tool join-cluster /var/lib/ovn/${file} ${db} tcp:[${me}]:${toString raftPort} \
            ${lib.concatMapStringsSep " " (h: "tcp:[${mesh h.id}]:${toString raftPort}") peers}
        fi
      '';
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${ovs}/bin/ovsdb-server /var/lib/ovn/${file}"
          "--remote=punix:/run/ovn/${lib.removeSuffix ".db" file}.sock"
          "--remote=ptcp:${toString port}:[${me}]"
          "--unixctl=/run/ovn/${lib.removeSuffix ".db" file}.ctl"
          "-vconsole:info -vsyslog:off -vfile:off"
        ];
        Restart = "always";
        RestartSec = 5;
      };
    };
  in {
    config = {
      virtualisation.vswitch.enable = true;

      systemd.services.ovn-nb = mkDb {
        db = "OVN_Northbound"; schema = "ovn-nb"; file = "ovnnb_db.db"; port = 6641; raftPort = 6643;
      };
      systemd.services.ovn-sb = mkDb {
        db = "OVN_Southbound"; schema = "ovn-sb"; file = "ovnsb_db.db"; port = 6642; raftPort = 6644;
      };

      systemd.services.ovn-northd = {
        description = "OVN northd (one active cluster-wide, by database lock)";
        environment = runDirs;
        wantedBy = [ "multi-user.target" ];
        after = [ "ovn-nb.service" "ovn-sb.service" ];
        wants = [ "ovn-nb.service" "ovn-sb.service" ];
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " [
            "${ovn}/bin/ovn-northd"
            "--ovnnb-db=${remotes 6641}" "--ovnsb-db=${remotes 6642}"
            "--unixctl=/run/ovn/ovn-northd.ctl"
            "-vconsole:info -vsyslog:off -vfile:off"
          ];
          RuntimeDirectory = "ovn";
          RuntimeDirectoryPreserve = true;
          Restart = "always";
          RestartSec = 5;
        };
      };

      systemd.services.ovn-controller = {
        description = "OVN controller (this node's chassis)";
        environment = runDirs;
        wantedBy = [ "multi-user.target" ];
        after = [ "ovs-vswitchd.service" "mesh-online.service" ];
        requires = [ "ovs-vswitchd.service" ];
        wants = [ "mesh-online.service" ];
        path = [ ovs ovn pkgs.coreutils pkgs.gnugrep ];
        # Open vSwitch's database is on the tmpfs root, so this node's chassis
        # settings are written at every start rather than kept.
        preStart = /* bash */ ''
          ovs-vsctl --no-wait set open_vswitch . \
            external_ids:system-id=${name} \
            external_ids:hostname=${name} \
            external_ids:ovn-remote="${remotes 6642}" \
            external_ids:ovn-encap-type=geneve \
            external_ids:ovn-encap-ip=${me} \
            external_ids:ovn-cms-options=enable-chassis-as-gw

          # Incus adds this node to each OVN network's gateway group when it
          # starts the network, and removes it only on a clean stop. After a
          # power cut or crash the entry is still there, so this ovn-controller
          # would take the gateway (if its priority is highest) before Incus
          # has set up the uplink -- and on a node that comes back Evacuated,
          # Incus doesn't start its networks until `cluster restore`. Found in
          # testing: the services network had no way out from test-node3's
          # boot until its entry was removed by hand. So with no uplink here
          # yet (the bridge mapping is in OVS's tmpfs database: gone after a
          # boot, kept across a restart of this service), leave every gateway
          # group first; Incus puts this node back along with its uplink.
          if [ -z "$(ovs-vsctl --no-wait get open . external_ids:ovn-bridge-mappings 2>/dev/null)" ]; then
            nb=(--db=${remotes 6641} --timeout=5)
            for _ in $(seq 1 12); do
              if groups=$(ovn-nbctl "''${nb[@]}" --bare --columns=name list HA_Chassis_Group); then
                for g in $groups; do
                  if ovn-nbctl "''${nb[@]}" ha-chassis-group-list "$g" | grep -qF "(${name})"; then
                    ovn-nbctl "''${nb[@]}" ha-chassis-group-remove-chassis "$g" ${name} \
                      && echo "left gateway group $g until Incus sets up the uplink"
                  fi
                done
                break
              fi
              # No Northbound quorum yet (a node starting alone): its gateway
              # can't matter until there is one. Give up after 2 minutes.
              sleep 5
            done
          fi
        '';
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " [
            "${ovn}/bin/ovn-controller unix:/run/openvswitch/db.sock"
            "--unixctl=/run/ovn/ovn-controller.ctl"
            "-vconsole:info -vsyslog:off -vfile:off"
          ];
          RuntimeDirectory = "ovn";
          RuntimeDirectoryPreserve = true;
          Restart = "always";
          RestartSec = 5;
          # Room for the wait on the Northbound database above.
          TimeoutStartSec = 180;
        };
      };

      # Incus starts its OVN networks at startup; give it a chassis to use.
      systemd.services.incus.after = [ "ovn-controller.service" ];
      systemd.services.incus.wants = [ "ovn-controller.service" ];

      # ovn-nbctl / ovn-sbctl / ovn-appctl for debugging, pointed at the cluster.
      environment.systemPackages = [ ovn ];
      environment.variables = runDirs // {
        OVN_NB_DB = remotes 6641;
        OVN_SB_DB = remotes 6642;
      };

      preservation.preserveAt."/persistent".directories = [
        { directory = "/var/lib/ovn"; mode = "0750"; }
      ];
    };
  };
}
