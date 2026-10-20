{ lib, ... }: {
  # The Thunderbolt mesh: the node's /128 on lo, IPv6 link-local ring links,
  # FRR OpenFabric routing between them, and the mesh-online gate. Shared by
  # installed nodes (node.nix) and their rescue installers (installer.nix),
  # so a node stuck in its installer is reachable at its usual mesh address.
  flake.nixosModules.clusterMesh = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host;
    id = toString host.id;
    meshAddr = "fd9a:7af:74af:ff::${id}";
  in {
    options.var.cluster = {
      name = lib.mkOption { type = lib.types.str; };
      host = lib.mkOption { type = lib.types.attrs; description = "This node's entry from _hosts.nix."; };
      hosts = lib.mkOption { type = lib.types.attrs; description = "Every node's entry from _hosts.nix."; };
      meshAddr = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = meshAddr;
        description = "This node's /128 on the mesh -- what Ceph, Incus and OVN bind to.";
      };
    };

    config = {
      networking.useNetworkd = true;
      networking.useDHCP = false;
      systemd.network.enable = true;

      systemd.network.networks = {
        # Mesh loopback. On lo rather than a dummy so it exists before any
        # link does; FRR advertises it, Ceph/Incus bind to it.
        "05-lo" = {
          matchConfig.Name = "lo";
          address = [ "${meshAddr}/128" ];
        };

        # Ring links: IPv6 link-local only, OpenFabric routes over them.
        "20-ring" = {
          matchConfig.Name = lib.concatStringsSep " " host.ring;
          networkConfig = { LinkLocalAddressing = "ipv6"; IPv6AcceptRA = false; };
          linkConfig = { MTUBytes = toString host.ringMtu; RequiredForOnline = "no"; };
        };
      };

      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

      # Transit traffic around the ring can come back on the other link
      # after a reroute; strict reverse-path filtering would drop it.
      networking.firewall.checkReversePath = "loose";

      # ---- Thunderbolt ring: FRR OpenFabric, same as scyto's gist ----
      services.frr = {
        fabricd.enable = true;
        config = ''
          frr defaults datacenter
          hostname ${name}
          log syslog informational
          service integrated-vtysh-config
          !
          interface lo
           ipv6 router openfabric 1
           openfabric passive
          !
          ${lib.concatMapStrings (iface: ''
            interface ${iface}
             ipv6 router openfabric 1
             openfabric csnp-interval 2
             openfabric hello-interval 1
             openfabric hello-multiplier 2
            !
          '') host.ring}
          router openfabric 1
           net 49.0001.0000.0000.000${id}.00
           lsp-gen-interval 1
           max-lsp-lifetime 600
           lsp-refresh-interval 180
          !
        '';
      };

      # fabricd started before the ring links have their link-local
      # addresses can leave an adjacency stuck in "Initializing" for good.
      systemd.services.frr = {
        wants = map (i: "systemd-networkd-wait-online@${i}:degraded.service") host.ring;
        after = map (i: "systemd-networkd-wait-online@${i}:degraded.service") host.ring;
      };

      # The mesh-up gate from the design doc: done when every ring link has
      # an Up OpenFabric adjacency. If one is still stuck after a while,
      # restart FRR (that has always cleared it), a few times at most, then
      # fail -- Ceph and Incus order themselves after this unit.
      systemd.services.mesh-online = {
        description = "Wait for every Thunderbolt ring adjacency to be Up";
        wantedBy = [ "multi-user.target" ];
        after = [ "frr.service" ];
        wants = [ "frr.service" ];
        path = [ pkgs.frr pkgs.gnugrep pkgs.gawk pkgs.coreutils pkgs.systemd ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "5min";
          # A node that booted alone fails this after 4 minutes (Ceph and
          # Incus start anyway). Without a retry it stayed failed after the
          # others came up, and cluster-deploy.sh / cluster restore refused
          # the node (seen in testing). Re-check until a neighbour appears.
          Restart = "on-failure";
          RestartSec = "30s";
        };
        # retrying all night on an isolated node is fine
        unitConfig.StartLimitIntervalSec = 0;
        # A neighbour that's listed but not Up is the FRR start-up race this
        # unit exists for: restart FRR, once. A neighbour that isn't listed at
        # all is a node that's down -- restarting FRR then only tears down the
        # links that do work, and doing it repeatedly hit systemd's start
        # limit and left FRR dead (seen in testing, cold start with one node
        # off). So with at least one adjacency Up and none stuck, the mesh is
        # as up as it can be; only a node with no adjacency at all fails.
        script = /* bash */ ''
          want=${toString (builtins.length host.ring)}
          neighbours() { vtysh -c "show openfabric neighbor"; }
          up() { neighbours | grep -c ' Up ' || true; }
          stuck() { neighbours | awk 'NF >= 5 && $1 != "System" && $1 != "Area" && $4 != "Up"' | grep -c . || true; }
          grace=45 restarted=0
          for t in $(seq 1 240); do
            u=$(up)
            if [ "$u" -ge "$want" ]; then
              echo "mesh up: $u/$want adjacencies after ''${t}s"
              exit 0
            fi
            if [ "$t" -ge "$grace" ]; then
              if [ "$(stuck)" -gt 0 ] && [ $restarted = 0 ]; then
                echo "an adjacency is stuck after ''${t}s, restarting frr (once)"
                neighbours
                systemctl restart frr.service
                restarted=1 grace=$((t + 45))
              elif [ "$u" -ge 1 ]; then
                echo "mesh up on $u/$want ring links; no working neighbour on the rest (a node down, or a link fault)"
                neighbours
                exit 0
              fi
            fi
            sleep 1
          done
          echo "no ring adjacency at all after 4 minutes" >&2
          neighbours >&2
          exit 1
        '';
      };
    };
  };
}
