{ self, lib, ... }: {
  # The weekly update, pulled by the nodes themselves: vmtest updates
  # flake.lock, pushes it and builds everything into its cache (Monday
  # 03:00, modules/fleet); an hour later every node fetches GitHub's main,
  # takes its new system from vmtest's cache -- never building it -- and
  # they install it one at a time, each rebooting into it. Nothing reaches
  # into the cluster from outside.
  #
  #   cluster-update run       what the timer starts (root); by hand:
  #                            `systemctl start --no-block cluster-update` on
  #                            every node -- they take turns by themselves
  #   cluster-update status    each node's state this cycle, and the lock
  #   cluster-update release   after a failed node is fixed: let the others go
  #
  # One cycle, per node:
  # - Fetch main; build this node's system from the cache only (retrying
  #   every 10 min, for up to 4 h, while vmtest is still building). Already
  #   booted into it: done.
  # - Wait for its turn: a Ceph lock, one node at a time. The node whose
  #   router holds the gateway goes last (as cluster-deploy does): one
  #   router hand-over instead of up to three.
  # - Check the cluster is healthy, install the system for the next boot,
  #   live-migrate its running VMs to the other nodes (containers restart
  #   with it), switch healing off and reboot (cluster-deploy's reasoning).
  # - Back up (cluster-update-resume): once the cluster is healthy again,
  #   bring the VMs back and release the lock. If the node doesn't come
  #   back healthy it keeps the lock, so no other node updates this week.
  # - The last node to finish updates the controller (OpenTofu), but only
  #   when the plan does nothing else; anything more is left for you.
  #
  # Each node's state is an object in Ceph (pool `important`, namespace
  # `update`): status.<node> = "<unix time> <state> <rev>".
  flake.nixosModules.clusterUpdate = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host hosts;
    cfg = config.var.cluster.autoUpdate;
    lan = import ./_lan.nix;
    others = lib.filter (n: n != name) (lib.attrNames hosts);
    tofuRun = self.packages.${pkgs.stdenv.hostPlatform.system}.elements-tofu-run;
    tofuPrepare = self.packages.${pkgs.stdenv.hostPlatform.system}.elements-tofu-prepare;

    clusterUpdate = pkgs.writeShellApplication {
      name = "cluster-update";
      runtimeInputs = with pkgs; [
        coreutils gnugrep gawk jq git iproute2 iputils
        ceph config.virtualisation.incus.clientPackage
        config.nix.package config.systemd.package
        tofuRun tofuPrepare
      ];
      text = /* bash */ ''
        D=/var/lib/cluster-update
        SELF=${name}
        OTHERS=(${lib.escapeShellArgs others})
        R=(rados -p important -N update)
        # The checkout is a shallow clone: Nix only reads one as a flake with this.
        FLAKE="git+file://$D/src?shallow=1"
        # Only what vmtest's cache (or cache.nixos.org) has: nothing is built
        # here. always-allow-substitutes: the small local-only derivations
        # (unit files, scripts) come from the cache too.
        NIXB=(--max-jobs 0 --option always-allow-substitutes true)

        notify() {
          echo "$*"
          if command -v notify-discord >/dev/null 2>&1; then notify-discord "cluster-update on $SELF: $*" || true; fi
        }
        set_status() { printf '%s %s %s\n' "$(date +%s)" "$1" "''${2:--}" | "''${R[@]}" put "status.$SELF" - ; }

        # Nodes still on their way through this cycle: a status from the last
        # 6 h that isn't final.
        pending_others() {
          local n s t st now; now=$(date +%s)
          for n in "''${OTHERS[@]}"; do
            s=$("''${R[@]}" get "status.$n" - 2>/dev/null) || continue
            read -r t st _ <<<"$s"
            [ $((now - t)) -lt 21600 ] || continue
            case $st in building|waiting|updating) echo "$n" ;; esac
          done
        }

        # Which node's router holds the gateway (same as cluster-agent's, in
        # tools.nix: LAN MACs end in the node id; ping first, since a stopped
        # router's MAC lingers as STALE).
        MGMT_IF=br-trunk.${toString host.vlans.trusted}
        GATEWAY=${lan.segments.trusted.v4}.1
        gateway_router() {
          local mac
          ping -c1 -W1 -I "$MGMT_IF" "$GATEWAY" >/dev/null 2>&1 || return 1
          mac=$(ip -4 neigh show "$GATEWAY" dev "$MGMT_IF" | awk '/lladdr/ && !/FAILED|INCOMPLETE/ {print $3}')
          [ -n "$mac" ] || return 1
          case $(( 16#''${mac##*:} )) in
            ${lib.concatStrings (lib.mapAttrsToList (n: h: "${toString h.id}) echo ${n} ;; ") hosts)}
            *) return 1 ;;
          esac
        }

        # Ceph OK, every Incus member online, and healing re-armed on this
        # node -- so a pending re-arm can't undo the switch-off before a
        # reboot (cluster-deploy found that one).
        healthy() {
          local m
          ceph health 2>/dev/null | grep -q HEALTH_OK || return 1
          m=$(incus cluster list -f csv -c s </dev/null 2>/dev/null) && [ -n "$m" ] || return 1
          ! grep -qvx ONLINE <<<"$m" || return 1
          systemctl is-active --quiet incus-healing-arm
        }
        wait_healthy() {  # wait_healthy <seconds>
          local until=$((SECONDS + $1))
          until healthy; do [ $SECONDS -lt "$until" ] || return 1; sleep 10; done
        }

        unlock() {
          local cookie locker
          cookie=$(cat "$D/cookie" 2>/dev/null) || return 0
          locker=$("''${R[@]}" lock info lock update --format=json \
            | jq -r --arg c "$cookie" '.lockers[] | select(.cookie == $c) | .name') || true
          [ -z "$locker" ] || "''${R[@]}" lock break lock update "$locker" --lock-cookie "$cookie" || true
          rm -f "$D/cookie"
        }

        # Running VMs that can live-migrate go to another node and come back
        # afterwards; the rest (containers, VMs without migration.stateful)
        # restart with this node, as before.
        vms_away() {
          local vm m moved
          : > "$D/moved-vms"
          for vm in $(incus list -f json </dev/null | jq -r --arg n "$SELF" '.[]
              | select(.location == $n and .type == "virtual-machine" and .status == "Running"
                       and .expanded_config["migration.stateful"] == "true") | .name'); do
            moved=""
            for m in $(incus cluster list -f json </dev/null | jq -r --arg n "$SELF" '.[]
                | select(.server_name != $n and .status == "Online") | .server_name'); do
              if incus move "$vm" --target "$m" </dev/null >/dev/null; then
                echo "$vm" >> "$D/moved-vms"; echo "  $vm moved to $m (live)"; moved=1; break
              fi
            done
            [ -n "$moved" ] || echo "  couldn't live-migrate $vm: it restarts with this node"
          done
        }
        vms_back() {
          local vm
          [ -s "$D/moved-vms" ] || return 0
          while read -r vm; do
            if incus move "$vm" --target "$SELF" </dev/null >/dev/null; then
              echo "  $vm back (live)"
            else
              echo "  couldn't bring $vm back -- it's still running elsewhere; cluster restore won't know (move it by hand)"
            fi
          done < "$D/moved-vms"
          rm -f "$D/moved-vms"
        }

        # The controller, from the same checkout -- by the last node to finish.
        controller() {
          local work=$D/tofu changes other
          if [ -n "$(pending_others)" ]; then echo "other nodes are still updating: the last one does the controller"; return 0; fi
          # One node at a time here too: when several were already up to date,
          # each gets this far.
          local cookie n=0
          cookie="$SELF-ctl-$(date +%s)"
          until "''${R[@]}" lock get lock update --lock-cookie "$cookie" --lock-duration 3600 \
                --lock-description "$SELF controller" 2>/dev/null; do
            n=$((n + 1)); [ $n -lt 120 ] || { echo "controller: no turn within an hour"; return 1; }
            sleep 30
          done
          echo "$cookie" > "$D/cookie"
          trap unlock RETURN
          echo "== the controller (OpenTofu)"
          if ! FLAKE=$FLAKE elements-tofu-prepare "$D/src" "$work" "''${NIXB[@]}" >/dev/null; then
            notify "controller: the UniFi image isn't in vmtest's cache -- not updated"; return 1
          fi
          rm -f "$work/update.plan"
          elements-tofu-run "$work" plan -input=false -out=update.plan >/dev/null \
            || { notify "controller: OpenTofu plan failed (journalctl -u cluster-update)"; return 1; }
          elements-tofu-run "$work" show -json update.plan | grep '^{' > "$work/plan.json"
          changes=$(jq -r '.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"]) | .address' "$work/plan.json")
          if [ -z "$changes" ]; then echo "controller: nothing to change"; return 0; fi
          other=$(grep -vxE 'incus_image\.unifi|incus_instance\.unifi' <<<"$changes" || true)
          if [ -n "$other" ]; then
            notify "controller: the plan also changes $(echo "$other" | tr '\n' ' ')-- not applied; review it with nix run .#tofu -- plan"
            return 1
          fi
          if ! elements-tofu-run "$work" apply -input=false update.plan; then
            notify "controller: OpenTofu apply FAILED (journalctl -u cluster-update)"; return 1
          fi
          notify "controller updated"
        }

        cmd_run() {
          local repo rev target cookie master start=$SECONDS
          mkdir -p "$D"
          if [ -e "$D/in-progress" ]; then echo "this node's last update hasn't finished (cluster-update-resume): not starting another" >&2; exit 1; fi
          if [ -e "$D/failed" ]; then echo "this node's last update failed ($D/failed): fix it, then cluster-update release" >&2; exit 1; fi
          # `elements-update --local` points one run at a git bundle of the
          # workstation's checkout instead of GitHub (before a push, or in the
          # test lab). One run only: a forgotten override can't pin the node.
          repo=${lib.escapeShellArg cfg.repo}
          if [ -s "$D/source" ]; then repo=$(cat "$D/source"); rm -f "$D/source"; echo "this run: $repo"; fi
          [ -d "$D/src/.git" ] || git init -q "$D/src"

          # ---- this node's system, from the cache (vmtest may still be building)
          set_status building
          while :; do
            # Shallow from GitHub; a bundle is a file, which has no shallow fetch.
            depth=(--depth 1); [ -f "$repo" ] && depth=()
            if git -C "$D/src" fetch -q "''${depth[@]}" "$repo" main && git -C "$D/src" checkout -q -f FETCH_HEAD; then
              rev=$(git -C "$D/src" rev-parse --short HEAD)
              if target=$(nix build --no-link --print-out-paths "''${NIXB[@]}" \
                  "$FLAKE#nixosConfigurations.$SELF.config.system.build.toplevel" 2>"$D/build.log"); then
                break
              fi
              echo "$rev: not in vmtest's cache yet ($(grep -m1 -E 'error|will be built' "$D/build.log" || tail -1 "$D/build.log"))"
            else
              echo "couldn't fetch $repo"
            fi
            if [ $((SECONDS - start)) -ge 14400 ]; then
              set_status failed "''${rev:-}"; notify "no system for ''${rev:-main} in the cache after 4 h -- not updating this week"; exit 1
            fi
            sleep 600
          done
          if [ "$target" = "$(readlink -f /run/booted-system)" ]; then
            set_status uptodate "$rev"; echo "already running $rev"
            controller || true
            return 0
          fi

          # ---- its turn: the gateway's node last, then one at a time
          set_status waiting "$rev"
          while master=$(gateway_router) && [ "$master" = "$SELF" ] && [ -n "$(pending_others)" ]; do
            [ $((SECONDS - start)) -lt 14400 ] || { set_status skipped "$rev"; notify "still waiting for the others after 4 h -- skipped this week"; exit 1; }
            sleep 30
          done
          cookie="$SELF-$(date +%s)"
          until "''${R[@]}" lock get lock update --lock-cookie "$cookie" --lock-duration 21600 \
                --lock-description "$SELF $rev" 2>/dev/null; do
            [ $((SECONDS - start)) -lt 14400 ] || { set_status skipped "$rev"; notify "no turn within 4 h (a failed node holds the lock?) -- skipped this week"; exit 1; }
            sleep 30
          done
          echo "$cookie" > "$D/cookie"

          echo "== $rev: checking the cluster is healthy"
          if ! wait_healthy 900; then
            unlock; set_status failed "$rev"; notify "the cluster isn't healthy -- not updating"; exit 1
          fi
          set_status updating "$rev"
          printf '%s %s\n' "$target" "$rev" > "$D/in-progress"
          echo "== $rev: installing for the next boot"
          nix-env -p /nix/var/nix/profiles/system --set "$target"
          "$target/bin/switch-to-configuration" boot
          echo "== moving running VMs away"
          vms_away
          incus config set cluster.healing_threshold=0 </dev/null
          echo "== rebooting"
          systemctl reboot
        }

        cmd_resume() {
          local target rev
          read -r target rev < "$D/in-progress"
          if [ "$(readlink -f /run/booted-system)" != "$target" ]; then
            mv "$D/in-progress" "$D/failed"; set_status failed "$rev"
            notify "didn't boot into $rev's system -- holding the update lock, so no other node updates. Fix it, then cluster-update release"
            exit 1
          fi
          echo "== waiting for the cluster to be healthy"
          if ! wait_healthy 1200; then
            mv "$D/in-progress" "$D/failed"; set_status failed "$rev"
            notify "not healthy 20 min after updating to $rev -- holding the update lock, so no other node updates. Fix it, then cluster-update release"
            exit 1
          fi
          echo "== bringing VMs back"
          vms_back
          rm -f "$D/in-progress"
          set_status "done" "$rev"
          unlock
          notify "updated to $rev"
          controller || true
        }

        cmd_status() {
          local n s
          for n in "$SELF" "''${OTHERS[@]}"; do
            s=$("''${R[@]}" get "status.$n" - 2>/dev/null) || s="- never -"
            read -r t st rev <<<"$s"
            [ "$t" = - ] && when=never || when=$(date -d "@$t" '+%F %T')
            printf '%-12s %-9s %-10s %s\n' "$n" "$st" "$rev" "$when"
          done
          echo
          "''${R[@]}" lock info lock update --format=json 2>/dev/null \
            | jq -r '.lockers[]? | "update lock held: \(.description) (expires \(.expiration))"' || true
          [ ! -e "$D/failed" ] || echo "THIS NODE'S LAST UPDATE FAILED: $(cat "$D/failed")"
        }

        cmd_release() {
          rm -f "$D/failed" "$D/in-progress"
          unlock
          # Also a lock left by this node's failed run under an older cookie.
          "''${R[@]}" lock info lock update --format=json 2>/dev/null \
            | jq -r --arg n "$SELF " '.lockers[]? | select(.description | startswith($n)) | "\(.name) \(.cookie)"' \
            | while read -r locker cookie; do "''${R[@]}" lock break lock update "$locker" --lock-cookie "$cookie"; done
          echo "released: the other nodes can update again"
        }

        case "''${1:-}" in
          run) cmd_run ;;
          resume) cmd_resume ;;
          status) cmd_status ;;
          release) cmd_release ;;
          vms-away) mkdir -p "$D"; vms_away ;;
          vms-back) vms_back ;;
          *) echo "usage: cluster-update run|status|release|vms-away|vms-back" >&2; exit 1 ;;
        esac
      '';
    };
  in {
    imports = [ self.nixosModules.fleetCacheClient ];

    options.var.cluster.autoUpdate = {
      enable = lib.mkEnableOption ''
        the weekly timer. Off until this repo's main on GitHub has the
        cluster in it: the nodes install exactly what's on main, so a node
        deployed from an unpushed checkout would be taken back to main'';
      repo = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/IntrovertedCoder/nix-config.git";
        description = "Where the nodes fetch main from (public: no key).";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        # vmtest starts at 03:00 Monday (modules/fleet/vmtest-orchestrator.nix).
        default = "Mon *-*-* 04:00:00";
        description = "When every node starts its update.";
      };
    };

    config = {
      environment.systemPackages = [ clusterUpdate ];

      # vmtest's cache, over Tailscale; give up on it quickly when it's away.
      nix.settings.connect-timeout = 5;

      systemd.services.cluster-update = {
        description = "Update this node from main, in turn with the others";
        after = [ "network-online.target" "ceph-online.service" "incus.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe clusterUpdate} run";
          TimeoutStartSec = "infinity";  # it may wait hours for vmtest or its turn
        };
      };
      systemd.timers.cluster-update = lib.mkIf cfg.enable {
        wantedBy = [ "timers.target" ];
        # Not Persistent: a cluster powered on after the time waits a week
        # rather than updating while it's still coming up.
        timerConfig.OnCalendar = cfg.onCalendar;
      };

      systemd.services.cluster-update-resume = {
        description = "Finish this node's update after its reboot";
        wantedBy = [ "multi-user.target" ];
        after = [ "incus.service" "ceph-online.service" "incus-healing-arm.service" ];
        unitConfig.ConditionPathExists = "/var/lib/cluster-update/in-progress";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe clusterUpdate} resume";
          TimeoutStartSec = "1h";
        };
      };

      preservation.preserveAt."/persistent".directories = [
        { directory = "/var/lib/cluster-update"; mode = "0700"; }
      ];
    };
  };
}
