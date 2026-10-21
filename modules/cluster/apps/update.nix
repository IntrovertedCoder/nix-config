{ ... }: {
  perSystem = { pkgs, lib, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.elements-update = cluster.mkApp {
      name = "elements-update";
      runtimeInputs = [ pkgs.git ];
      text = /* bash */ ''
        # Update the whole cluster now: the nodes and the controller. It starts
        # the same run as the weekly timer (cluster-update, modules/cluster/
        # update.nix) on every node -- they fetch GitHub's main, take their
        # systems from vmtest's cache and reboot one at a time -- and follows
        # it to the end.
        #
        #   nix run .#elements-update             what's on GitHub's main
        #   nix run .#elements-update -- --local  this checkout's committed main
        #
        # --local, before a push (or in the test lab): the nodes get a git
        # bundle of main instead of GitHub, for this one run, and this machine
        # builds what they need and copies it to them instead of vmtest's
        # cache. Uncommitted changes aren't included.

        local_run=""
        case "''${1:-}" in
          --local) local_run=1 ;;
          "") ;;
          *) echo "usage: elements-update [--local]" >&2; exit 1 ;;
        esac
        D=/var/lib/cluster-update

        for n in "''${NODES[@]}"; do
          on "$n" true 2>/dev/null || { echo "$(name "$n") doesn't answer -- the update needs every node" >&2; exit 1; }
          if on "$n" "test -e $D/failed -o -e $D/in-progress"; then
            echo "$(name "$n") has an unfinished or failed update: ssh in and run cluster-update status" >&2; exit 1
          fi
        done

        if [ -n "$local_run" ]; then
          [ -z "$(git status --porcelain --untracked-files=no)" ] \
            || echo "note: uncommitted changes aren't part of this update (only main's commits are)"
          echo "== building main ($(git rev-parse --short main)) here"
          flake="git+file://$PWD?rev=$(git rev-parse main)"
          image=$(nix build --no-link --print-out-paths \
            "$flake#nixosConfigurations.unifi.config.system.build.metadata" \
            "$flake#nixosConfigurations.unifi.config.system.build.squashfs")
          git bundle create -q "$_TMP/main.bundle" main
          for n in "''${NODES[@]}"; do
            nm=$(name "$n")
            sys=$(nix build --no-link --print-out-paths "$flake#nixosConfigurations.$nm.config.system.build.toplevel")
            echo "== $nm: copying its system, the controller's image and the bundle"
            # shellcheck disable=SC2086  # $image: two store paths
            NIX_SSHOPTS="''${SSH_OPTS[*]}" nix copy --no-check-sigs --to "ssh-ng://root@$(ip "$n")" "$sys" $image
            on "$n" "mkdir -p $D && cat > $D/local.bundle && echo $D/local.bundle > $D/source" < "$_TMP/main.bundle"
          done
        fi

        start=$(date +%s)
        for n in "''${NODES[@]}"; do on "$n" 'systemctl start --no-block cluster-update'; done
        echo "== started on every node; following (Ctrl-C stops following, not the update)"

        # Each node's status object, from whichever node answers (one is
        # always rebooting).
        statuses() {
          local n
          for n in "''${NODES[@]}"; do
            on "$n" "for m in ${lib.concatStringsSep " " (lib.attrNames (import ../_hosts.nix))}; do
                       printf '%s ' \$m; rados -p important -N update get status.\$m - 2>/dev/null || echo '0 - -'; done" \
              2>/dev/null && return 0
          done
          return 1
        }
        last="" final=""
        while :; do
          if now=$(statuses); then
            [ "$now" = "$last" ] || { echo "--- $(date +%T)"; while read -r m t st rev; do
              if [ "$t" -ge "$start" ] 2>/dev/null; then printf '  %-12s %-9s %s\n' "$m" "$st" "$rev"
              else printf '  %-12s (not started yet)\n' "$m"; fi
            done <<<"$now"; last=$now; }
            final=1
            while read -r m t st _; do
              if ! [ "$t" -ge "$start" ] 2>/dev/null; then final=""; continue; fi
              case $st in building|waiting|updating) final="" ;; esac
            done <<<"$now"
            [ -z "$final" ] || break
          fi
          sleep 15
        done

        # The controller comes after the last node; wait for the runs to end.
        echo "== every node is through; waiting for the controller step"
        for n in "''${NODES[@]}"; do
          until on "$n" '! systemctl is-active --quiet cluster-update cluster-update-resume' 2>/dev/null; do sleep 10; done
        done
        echo "== results"
        rc=0
        for n in "''${NODES[@]}"; do
          echo "--- $(name "$n")"
          on "$n" "journalctl -u cluster-update -u cluster-update-resume --since @$start --no-pager -o cat \
                   | grep -E '^(this run|already running|updated to|controller|no system|still waiting|no turn|the cluster|didn.t boot|not healthy)'" || true
          on "$n" "test ! -e $D/failed" || rc=1
        done
        exit $rc
      '';
    };
  };
}
