{ ... }: {
  perSystem = { pkgs, lib, config, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.cluster-unifi = cluster.mkApp {
      name = "cluster-unifi";
      runtimeInputs = [  ];
      text = /* bash */ ''
        # The UniFi controller container (modules/cluster/unifi.nix):
        #
        #   nix run .#cluster-unifi -- create   build its image, import it into Incus, start it
        #   nix run .#cluster-unifi -- update   build its system and switch the running container
        #                               to it (the container has no SSH: the closure goes
        #                               in through `incus exec`, via the first node)
        #
        # The web UI: https://10.4.0.10:8443 from Trusted (later unifi.trotnic.xyz).
        # (Every incus command below gets </dev/null: the script reaches the node on
        # stdin, and incus init reads instance config from stdin when it isn't a tty.)

        N=''${NODES[0]}
        OUT=/tmp/unifi-build             # not /: the workstation's / is RAM
        STAGE=/persistent/unifi-image    # not the node's /: also RAM
        IMAGE=unifi-base
        MAC=02:74:af:04:00:0a            # fixed: infra .10, like the routers' MACs
        build() { nix build -o "$OUT/$1" ".#nixosConfigurations.unifi.config.system.build.$1"; }
        cexec() { echo "incus exec unifi -- /run/current-system/sw/bin/$*"; }   # NixOS has no /usr/bin

        case ''${1:-} in
        create)
          if on "$N" "incus info unifi" </dev/null >/dev/null 2>&1; then
            echo "the unifi instance exists already; use: nix run .#cluster-unifi -- update" >&2; exit 1
          fi
          echo "== build the image"
          build metadata; build squashfs
          meta=$(echo "$OUT"/metadata/tarball/*.tar.xz); root=$(echo "$OUT"/squashfs/*.squashfs)
          echo "== copy it to $(name "$N") ($(du -shL "$root" | cut -f1))"
          on "$N" "mkdir -p $STAGE" </dev/null
          on "$N" "cat > $STAGE/meta.tar.xz" < "$meta"
          on "$N" "cat > $STAGE/root.squashfs" < "$root"
          on "$N" bash -euo pipefail -s <<EOF
        echo "== import as image $IMAGE"
        incus image delete $IMAGE </dev/null 2>/dev/null || true
        incus image import $STAGE/meta.tar.xz $STAGE/root.squashfs --alias $IMAGE </dev/null
        rm -rf $STAGE
        echo "== create the instance (root disk on Ceph, NIC untagged on the trunk = infra)"
        incus init $IMAGE unifi -c limits.cpu=2 -c limits.memory=2GiB -c boot.autostart=true </dev/null
        incus config device add unifi eth0 nic nictype=bridged parent=br-trunk hwaddr=$MAC name=eth0 </dev/null
        incus start unifi </dev/null
        EOF
          ;;

        update)
          echo "== build the system"
          build toplevel
          sys=$(readlink -f "$OUT/toplevel")
          echo "== copy it to $(name "$N")"
          NIX_SSHOPTS="''${SSH_OPTS[*]}" nix copy --to "ssh://root@$(ip "$N")" "$sys"
          on "$N" bash -euo pipefail -s <<EOF
        echo "== into the container: only the store paths it doesn't have yet"
        missing=\$(nix-store -qR $sys | $(cexec bash) -c 'xargs nix-store --check-validity --print-invalid')
        echo "   \$(echo "\$missing" | grep -c . || true) paths"
        [ -z "\$missing" ] || nix-store --export \$missing | $(cexec nix-store) --import >/dev/null
        echo "== switch"
        $(cexec nix-env) -p /nix/var/nix/profiles/system --set $sys </dev/null
        $(cexec bash) -c '$sys/bin/switch-to-configuration switch' </dev/null
        # check: it must be running the new system now (and boot it: /sbin/init)
        [ "\$($(cexec readlink) -f /run/current-system </dev/null)" = $sys ] || { echo 'switch did not take' >&2; exit 1; }
        EOF
          ;;

        *) echo "usage: nix run .#cluster-unifi -- create|update" >&2; exit 1 ;;
        esac

        echo "== waiting for the web UI (UniFi's first start takes a few minutes)"
        start=$(date +%s)
        # from the node: its management address is on Trusted, so this also checks
        # that Trusted reaches infra through the routers
        until on "$N" "curl -sk -o /dev/null -m 5 https://10.4.0.10:8443" </dev/null 2>/dev/null; do
          [ $(( $(date +%s) - start )) -lt 900 ] || { echo "no web UI after 15 min" >&2; exit 1; }
          sleep 10
        done
        echo "UniFi is up: https://10.4.0.10:8443 (from Trusted)"
      '';
    };
  };
}
