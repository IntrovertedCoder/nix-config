{ ... }: {
  perSystem = { pkgs, lib, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.cluster-shutdown = cluster.mkApp {
      name = "cluster-shutdown";
      runtimeInputs = [ ];
      text = /* bash */ ''
        # Take the whole cluster down on purpose (power work, a move), or
        # reboot it all at once:
        #
        #   nix run .#cluster-shutdown              power every node off
        #   nix run .#cluster-shutdown -- --reboot  reboot every node
        #
        # Shutting all three down together hung each of them for 10 minutes
        # (found in testing): the first one down took Ceph's quorum with it,
        # and the others' Incus then waited on instance disks that could no
        # longer be written. So every node first stops its own instances, in
        # parallel and while Ceph and Incus still have quorum -- the way
        # Incus does at shutdown (`incusd shutdown`), which remembers them as
        # running, so they start again at the next boot -- and only then do
        # the nodes go down, all at once. The router VMs live on each node's
        # own disk and simply stop with it.
        #
        # For one node, a plain reboot (or cluster-deploy) is right instead:
        # the other two keep everything running.

        action=poweroff
        case "''${1:-}" in
          --reboot) action=reboot ;;
          "") ;;
          *) echo "usage: cluster-shutdown [--reboot]" >&2; exit 1 ;;
        esac

        for n in "''${NODES[@]}"; do
          on "$n" true 2>/dev/null || { echo "$(name "$n") doesn't answer: shut the others down one at a time instead" >&2; exit 1; }
        done

        echo "== stopping every node's instances (they start again at boot)"
        pids=()
        for n in "''${NODES[@]}"; do
          on "$n" 'systemctl stop incus-startup.service' & pids+=($!)
        done
        rc=0
        for p in "''${pids[@]}"; do wait "$p" || rc=1; done
        # Not `incus list`: with the daemon down, its socket would start it again.
        for n in "''${NODES[@]}"; do
          if on "$n" 'pgrep -x incusd >/dev/null || pgrep -f "^\[lxc monitor\]" >/dev/null'; then
            echo "  $(name "$n"): Incus or an instance is still running" >&2; rc=1
          else
            echo "  ok  $(name "$n"): instances stopped, Incus down"
          fi
        done
        [ "$rc" = 0 ] || { echo "not taking the nodes down: check the above (journalctl -u incus-startup)" >&2; exit 1; }

        echo "== $action every node"
        for n in "''${NODES[@]}"; do on "$n" "systemctl $action" 2>/dev/null & done
        wait
        echo "done"
      '';
    };
  };
}
