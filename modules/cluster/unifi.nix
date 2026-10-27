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

    # Only the node the console runs on, and only while it runs. By its
    # exact name: `incus list unifi-os` also matches unifi-os-debian.
    hereAndRunning = /* bash */ ''
      read -r loc st < <(incus list -f json </dev/null \
        | jq -r '.[] | select(.name == "unifi-os") | "\(.location) \(.status)"') || true
      [ "''${loc:-}" = "$(uname -n)" ] || { echo "unifi-os isn't here"; exit 0; }
      [ "''${st:-}" = Running ] || { echo "unifi-os isn't running"; exit 0; }
    '';

    # The console's MongoDB is in its container, inside the VM, and the
    # container has its own mongo shell, run as the console's user.
    consoleUid = toString self.nixosConfigurations.unifi-os.config.users.users.uosserver.uid;
    consoleSchedule = /* bash */ ''
      ${hereAndRunning}
      console() {
        incus exec unifi-os --cwd /tmp -- /run/current-system/sw/bin/runuser -u uosserver -- \
          /run/current-system/sw/bin/env XDG_RUNTIME_DIR=/run/user/${consoleUid} \
          /usr/bin/podman exec -i uosserver "$@"
      }
      # The backup task (what runs it) and super_mgmt (what the UI shows)
      current() {
        console mongo --quiet --port 27117 ace <<'EOF' | tail -1 | jq -ce .
      var t = db.scheduletask.findOne({action: "backup"}) || {};
      var m = db.setting.findOne({key: "super_mgmt"}) || {};
      print(JSON.stringify({cron: t.cron_expr || null, tz: t.timezone || null,
        shown: m.autobackup_cron_expr || null, keep: m.autobackup_max_files || null,
        on: m.autobackup_enabled === true}));
      EOF
      }
      on_time() { [ "$(jq -r '[.cron, .shown, .keep, .on] | map(tostring) | join("|")' <<<"$1")" = "${cron}|${cron}|${toString keep}|true" ]; }

      cur=$(current) || { echo "the console's database doesn't answer (Network still starting?)" >&2; exit 1; }
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
      new=$(current)
      on_time "$new" || { echo "couldn't set the backup schedule: still $new" >&2; exit 1; }
      # Network only reads the schedule when it starts
      console systemctl restart unifi </dev/null
      echo "backup schedule was $(jq -r '"\(.cron) (shown \(.shown)), keeping \(.keep), on \(.on)"' <<<"$cur"): now ${cron} $tz, keeping ${toString keep}; Network restarted"
    '';
  in {
    systemd.services = {
      unifi-os-backup-schedule = {
        description = "Keep the UniFi OS console's backup schedule on time";
        after = [ "incus.service" ];
        path = [ incus pkgs.jq pkgs.coreutils ];
        serviceConfig.Type = "oneshot";
        script = consoleSchedule;
      };
      unifi-os-backup-copy = {
        description = "Copy the UniFi OS console's backups to this node's disk";
        after = [ "incus.service" ];
        path = [ incus pkgs.coreutils pkgs.findutils ];
        serviceConfig.Type = "oneshot";
        script = /* bash */ ''
          incus info unifi-os >/dev/null 2>&1 </dev/null || { echo "no unifi-os instance"; exit 0; }
          dest=/persistent/backups/unifi-os
          tmp=$(mktemp -d /persistent/backups/.unifi-os.XXXXXX)
          trap 'rm -rf "$tmp"' EXIT
          if incus file pull -r unifi-os${backups} "$tmp/" </dev/null \
             && [ -n "$(find "$tmp/autobackup" -name '*.unf' -print -quit)" ]; then
            rm -rf "$dest"; mv "$tmp/autobackup" "$dest"
            echo "copied: $(find "$dest" -name '*.unf' | wc -l) backups"
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
  };
}
