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
        path = [ pkgs.frr pkgs.gnugrep pkgs.coreutils pkgs.systemd ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "5min";
        };
        script = ''
          want=${toString (builtins.length host.ring)}
          up() { vtysh -c "show openfabric neighbor" | grep -c ' Up ' || true; }
          for attempt in 1 2 3 4; do
            for _ in $(seq 1 45); do
              if [ "$(up)" -ge "$want" ]; then
                echo "mesh up: $want/$want adjacencies (attempt $attempt)"
                exit 0
              fi
              sleep 1
            done
            echo "only $(up)/$want adjacencies Up after 45s, restarting frr"
            vtysh -c "show openfabric neighbor"
            systemctl restart frr.service
          done
          echo "mesh did not come up" >&2
          exit 1
        '';
      };
    };
  };
}
