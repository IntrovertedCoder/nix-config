{ self, lib, ... }: {
  # The UniFi controller is UniFi OS Server (unifi-os.nix, a VM on Ceph at
  # infra .10). It replaced the Network Server container that was declared
  # here; to go back, `git revert` the switch commit and apply (design doc,
  # "Finish the move"), while its `unifi-data` volume is still kept
  # (opentofu/unifi.tf).
  #
  # Backups: UniFi's own auto-backup, weekly an hour before vmtest's update
  # (_schedule.nix, kept below), lands in the console's data volume (on
  # Ceph); every node also copies it to its own disk daily, so losing Ceph
  # doesn't lose them. Not yet off-cluster (design doc, open questions). A
  # reset UX7 can restore one of those .unf files (same or newer Network
  # version).
  #
  # On every node: keep a copy of the console's backups on local disk, and
  # keep its backup schedule on _schedule.nix's time.
  flake.nixosModules.clusterUnifi = { config, lib, pkgs, ... }: let
    schedule = import ./_schedule.nix { inherit self lib; };
    inherit (schedule.unifiBackup) cron timeZone;
    keep = 8;   # weekly: two months back
    incus = config.virtualisation.incus.package;

    # Where the console keeps its auto-backups (the .unf files)
    backups = "/var/lib/uosserver/home/.local/share/containers/storage/volumes/uosserver_var_lib_unifi/_data/backup/autobackup";

    # The node the console runs on does it, once the console runs and no
    # update is moving or replacing it. Every node whose timer fires
    # meanwhile waits too: the console may come up on any of them. By its
    # exact name: `incus list unifi-os` also matches unifi-os-debian.
    waitForConsole = /* bash */ ''
      where() {
        timeout 30 incus list -f json </dev/null 2>/dev/null \
          | jq -r '.[] | select(.name == "unifi-os") | "\(.location) \(.status)"' || true
      }
      # The weekly update's lock (update.nix): held from before a node moves
      # the console away until it's back, and while the update replaces it.
      # Ceph not answering reads as free: the lock only keeps this out of the
      # update's way, and a read cut off by a move is retried below anyway.
      update_lock() {
        timeout 20 rados -p important -N update lock info lock update --format=json 2>/dev/null \
          | jq -er '.lockers[0].description // empty' 2>/dev/null
      }
      # Up to 30 min. A console still not running then is for elements-health
      # to report (healthchecks.nix), an update that keeps its lock for the
      # update: neither is a failure here.
      deadline=$((SECONDS + 1800)) said=""
      while :; do
        read -r loc st < <(where) || true
        if lock=$(update_lock); then why="an update is under way ($lock)"
        elif [ -z "''${loc:-}" ]; then why="there's no unifi-os (being replaced?)"
        elif [ "''${st:-}" != Running ]; then why="unifi-os is ''${st:-} on $loc"
        elif [ "$loc" != "$(uname -n)" ]; then echo "unifi-os runs on $loc: that node checks it"; exit 0
        else break; fi
        [ "$why" = "$said" ] || { echo "$why: waiting"; said=$why; }
        [ $SECONDS -lt $deadline ] || { echo "$why, still after 30 min: not checked today"; exit 0; }
        sleep 30
      done
    '';

    # The console's MongoDB is in its container, inside the VM, and the
    # container has its own mongo shell, run as the console's user.
    consoleUid = toString self.nixosConfigurations.unifi-os.config.users.users.uosserver.uid;
    consoleSchedule = /* bash */ ''
      ${waitForConsole}
      console() {
        incus exec unifi-os --cwd /tmp -- /run/current-system/sw/bin/runuser -u uosserver -- \
          /run/current-system/sw/bin/env XDG_RUNTIME_DIR=/run/user/${consoleUid} \
          /usr/bin/podman exec -i uosserver "$@"
      }
      # The backup task (what runs it) and super_mgmt (what the UI shows);
      # nothing, and a failure, unless the database answers.
      current() {
        console mongo --quiet --port 27117 ace 2>/dev/null <<'EOF' | tail -1 | jq -ce 'select(type == "object")' 2>/dev/null
      var t = db.scheduletask.findOne({action: "backup"}) || {};
      var m = db.setting.findOne({key: "super_mgmt"}) || {};
      print(JSON.stringify({cron: t.cron_expr || null, tz: t.timezone || null,
        shown: m.autobackup_cron_expr || null, keep: m.autobackup_max_files || null,
        on: m.autobackup_enabled === true}));
      EOF
      }
      on_time() { [ "$(jq -r '[.cron, .shown, .keep, .on] | map(tostring) | join("|")' <<<"$1")" = "${cron}|${cron}|${toString keep}|true" ]; }

      # Up to 10 min for its database: Network takes a minute or two after
      # the VM starts. From here on the console is followed wherever it runs
      # (incus exec works from any node): only an unplanned move is left.
      deadline=$((SECONDS + 600)) said=""
      until cur=$(current); do
        [ $SECONDS -lt $deadline ] || { echo "the console's database hasn't answered for 10 min" >&2; exit 1; }
        [ -n "$said" ] || { echo "its database doesn't answer yet (Network starting?): waiting"; said=1; }
        sleep 20
      done
      tz=$(jq -r .tz <<<"$cur")
      [ "$tz" != null ] || { echo "no backup task in the console yet (fresh, not set up)"; exit 0; }
      # The console keeps Network's backup time zone in step with its own
      # (its settings), so setting one here wouldn't stick, and would restart
      # Network every day. What matters is the clock: the console's zone has
      # to keep ${timeZone}'s time, now and in half a year (summer time).
      export TZDIR=${pkgs.tzdata}/share/zoneinfo
      [ -e "$TZDIR/$tz" ] || { echo "the console's time zone $tz is unknown here" >&2; exit 1; }
      for when in now "+182 days"; do
        if [ "$(TZ=$tz date -d "$when" +%z)" != "$(TZ=${timeZone} date -d "$when" +%z)" ]; then
          echo "the console's time zone is $tz, which doesn't keep ${timeZone}'s time: its backups would run at another hour. Change the console's time zone." >&2
          exit 1
        fi
      done
      if on_time "$cur"; then echo "backup schedule already ${cron} $tz, keeping ${toString keep}"; exit 0; fi

      console mongo --quiet --port 27117 ace >/dev/null <<EOF
      var t = db.scheduletask.findOne({action: "backup"});
      db.scheduletask.updateOne({_id: t._id}, {\$set: {cron_expr: "${cron}"}});
      db.setting.updateOne({key: "super_mgmt"}, {\$set: {autobackup_enabled: true,
        autobackup_cron_expr: "${cron}", autobackup_timezone: "$tz", autobackup_max_files: ${toString keep}}});
      EOF
      new=$(current) || true
      on_time "$new" || { echo "couldn't set the backup schedule: still ''${new:-unknown}" >&2; exit 1; }
      # Network only reads the schedule when it starts. Retried: saved but
      # not loaded, the next run would find it on time and never restart it.
      deadline=$((SECONDS + 600))
      until console systemctl restart unifi </dev/null; do
        [ $SECONDS -lt $deadline ] || { echo "the new schedule is saved, but Network didn't restart to load it: incus restart unifi-os" >&2; exit 1; }
        sleep 20
      done
      echo "backup schedule was $(jq -r '"\(.cron) (shown \(.shown)), keeping \(.keep), on \(.on)"' <<<"$cur"): now ${cron} $tz, keeping ${toString keep}; Network restarted"
    '';
  in {
    systemd.services = {
      unifi-os-backup-schedule = {
        description = "Keep the UniFi OS console's backup schedule on time";
        after = [ "incus.service" ];
        path = [ incus pkgs.jq pkgs.coreutils pkgs.ceph ];
        serviceConfig = {
          Type = "oneshot";
          # Its own waits come to 50 min at most (30 + 10 + 10)
          TimeoutStartSec = "1h";
        };
        script = consoleSchedule;
      };
      unifi-os-backup-copy = {
        description = "Copy the UniFi OS console's backups to this node's disk";
        after = [ "incus.service" ];
        path = [ incus pkgs.coreutils pkgs.findutils pkgs.gnused ];
        serviceConfig.Type = "oneshot";
        script = /* bash */ ''
          incus info unifi-os >/dev/null 2>&1 </dev/null || { echo "no unifi-os instance"; exit 0; }
          dest=/persistent/backups/unifi-os
          tmp=$(mktemp -d /persistent/backups/.unifi-os.XXXXXX)
          trap 'rm -rf "$tmp"' EXIT
          if incus file pull -r unifi-os${backups} "$tmp/" </dev/null \
             && [ -n "$(find "$tmp/autobackup" -name '*.unf' -print -quit)" ]; then
            rm -rf "$dest"; mv "$tmp/autobackup" "$dest"
            n=$(find "$dest" -name '*.unf' | wc -l)
            # For `cluster vm-debug unifi-os`, which can't read the backups
            # (they hold the Wi-Fi keys): "<copied at> <count> <newest backup
            # at>", the newest from its name (..._<unix ms>.unf).
            newest=$(find "$dest" -name '*.unf' -printf '%f\n' | sed -nE 's/.*_([0-9]{13})\.unf$/\1/p' | sort -n | tail -1)
            echo "$(date +%s) $n $(( ''${newest:-0} / 1000 ))" > /var/lib/unifi-backup-status/unifi-os
            echo "copied: $n backups"
          else
            # Never replace the last good copy with nothing.
            echo "no backups in the console yet (turn on auto backup in UniFi); kept the old copy"
          fi
        '';
      };
    };
    systemd.timers = {
      unifi-os-backup-schedule = {
        wantedBy = [ "timers.target" ];
        timerConfig = { OnBootSec = "15min"; OnUnitActiveSec = "1d"; };
      };
      # Daily, half an hour after the backup's time of day: a node rebuilt
      # mid-week gets its copy the next day, not the next Monday.
      unifi-os-backup-copy = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = schedule.unifiBackupCopy.dailyOnCalendar;
          RandomizedDelaySec = "10min";
          Persistent = true;
        };
      };
    };
    # The old controller's last copies stay in /persistent/backups/unifi.
    systemd.tmpfiles.rules = [ "d /persistent/backups 0700 root root -" ];
    # The last good copy's time, readable by cluster-agent (see above)
    preservation.preserveAt."/persistent".directories = [
      { directory = "/var/lib/unifi-backup-status"; mode = "0755"; }
    ];
  };
}
