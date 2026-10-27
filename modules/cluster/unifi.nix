{ self, inputs, lib, ... }: let
  lan = import ./_lan.nix;
  infra = lan.segments.infra;
  address = "${infra.v4}.10";
in {
  # The UniFi controller (design doc, "Switches, VLANs & UniFi"): an Incus
  # system container on Ceph, so it heals to another node like any instance.
  # It sits directly on the untagged infra segment with the gear it manages
  # (layer-2 adoption, no router in between), at a fixed address.
  #
  # The container is NixOS, built from this flake into an Incus image, and
  # declared in OpenTofu (opentofu/unifi.tf): image, instance, and the
  # `unifi-data` volume holding /var/lib/unifi. The container itself is
  # disposable -- an update builds a new image and `nix run .#tofu -- apply`
  # replaces the instance, keeping the volume. It has no SSH. The switches
  # and APs keep forwarding on their last config while the controller is down.
  #
  # Backups: UniFi's own auto-backup, weekly an hour before vmtest's update
  # (_schedule.nix, set below), lands in the container (on Ceph); every
  # node also copies it to its own disk daily, so losing Ceph doesn't lose
  # them. Not yet off-cluster (design doc, open questions). A reset UX7 can
  # restore one of those .unf files (same or newer Network version).
  flake.nixosConfigurations.unifi = inputs.nixpkgs.lib.nixosSystem {
    modules = [ self.nixosModules.unifiController ];
  };

  flake.nixosModules.unifiController = { config, lib, pkgs, modulesPath, ... }: let
    # UniFi Network 9.0+ supports MongoDB up to 8.0; nixpkgs' prebuilt
    # mongodb-ce is 8.2 (support not confirmed), and its mongodb-7_0 builds
    # from source for hours (unfree: not in the binary cache). MongoDB's own
    # 8.0 binary, then. Don't jump major versions under existing data.
    mongodb80 = pkgs.mongodb-ce.overrideAttrs (old: rec {
      version = "8.0.34";
      src = pkgs.fetchurl {
        url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2404-${version}.tgz";
        hash = "sha256-PlXNz3AT+8gF0p2BlSMN9LI8dohzPuFa1YrGvCpBZhE=";
      };
    });
  in {
    imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];

    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "unifi-controller" "mongodb-ce" ];
    networking.hostName = "unifi";
    system.stateVersion = "26.05";
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    networking.useNetworkd = true;
    networking.useHostResolvConf = false;   # its own DNS: the infra gateway
    networking.useDHCP = false;
    systemd.network.networks."10-eth0" = {
      matchConfig.Name = "eth0";
      address = [ "${address}/${toString infra.plen}" ];
      gateway = [ "${infra.v4}.1" ];
      dns = [ "${infra.v4}.1" ];
      networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
    };

    services.unifi = {
      enable = true;
      unifiPackage = pkgs.unifi;
      mongodbPackage = mongodb80;
      openFirewall = true;            # inform 8080, STUN 3478, discovery 10001, ...
      maximumJavaHeapSize = 1024;
    };
    networking.firewall.allowedTCPPorts = [ 8443 ];   # the web UI

    # The data volume outlives each container, and a fresh image hands out
    # system uids anew: pin them to what owns the data (UniFi and its MongoDB
    # both run as `unifi`), or a replaced container couldn't read its state.
    users.users.unifi.uid = 997;
    users.groups.unifi.gid = 996;

    services.openssh.enable = lib.mkForce false;
    environment.systemPackages = [ pkgs.curl ];   # debugging from inside
  };

  # On every node: keep a copy of each controller's backups on local disk,
  # and keep its backup schedule on _schedule.nix's time. Until the switch
  # there are two: this one (`unifi`, a container) and the UniFi OS console
  # (`unifi-os`, a VM, unifi-os.nix) beside it.
  flake.nixosModules.clusterUnifi = { config, lib, pkgs, ... }: let
    schedule = import ./_schedule.nix { inherit self lib; };
    inherit (schedule.unifiBackup) cron timeZone;
    keep = 8;   # weekly: two months back
    incus = config.virtualisation.incus.package;

    # Where each one keeps its auto-backups (the .unf files)
    backups = {
      unifi = "/var/lib/unifi/data/backup/autobackup";
      unifi-os = "/var/lib/uosserver/home/.local/share/containers/storage/volumes/uosserver_var_lib_unifi/_data/backup/autobackup";
    };

    # Only the node the instance runs on, and only while it runs. By its
    # exact name: `incus list unifi` matches unifi-os too, so with the
    # console there this check never matched, on any node.
    hereAndRunning = name: /* bash */ ''
      read -r loc st < <(incus list -f json </dev/null \
        | jq -r --arg n ${name} '.[] | select(.name == $n) | "\(.location) \(.status)"') || true
      [ "''${loc:-}" = "$(uname -n)" ] || { echo "${name} isn't here"; exit 0; }
      [ "''${st:-}" = Running ] || { echo "${name} isn't running"; exit 0; }
    '';

    setSchedule = pkgs.writers.writePython3 "unifi-backup-schedule"
      { libraries = [ pkgs.python3Packages.pymongo ]; } /* python */ ''
        # Run inside the container's network namespace. UniFi schedules its
        # auto-backup from the `scheduletask` document (what the UI's
        # setting turns into); super_mgmt is what the UI shows. A restored
        # backup brings its own schedule back, so this runs daily.
        import sys
        from pymongo import MongoClient

        cron, tz, keep = sys.argv[1], sys.argv[2], int(sys.argv[3])
        db = MongoClient("localhost", 27117,
                         serverSelectionTimeoutMS=10000)["ace"]
        task = db.scheduletask.find_one({"action": "backup"}) or {}
        mgmt = db.setting.find_one({"key": "super_mgmt"}) or {}
        if (task.get("cron_expr"), task.get("timezone")) == (cron, tz) \
                and mgmt.get("autobackup_cron_expr") == cron \
                and mgmt.get("autobackup_max_files") == keep \
                and mgmt.get("autobackup_enabled") is True:
            print(f"backup schedule already {cron} {tz}, keeping {keep}")
            sys.exit(0)
        if not task:
            print("no backup task in the controller yet (fresh, not set up)")
            sys.exit(0)
        db.scheduletask.update_one({"_id": task["_id"]}, {"$set": {
            "cron_expr": cron, "timezone": tz}})
        db.setting.update_one({"key": "super_mgmt"}, {"$set": {
            "autobackup_enabled": True, "autobackup_cron_expr": cron,
            "autobackup_timezone": tz, "autobackup_max_files": keep}})
        print(f"backup schedule was {task.get('cron_expr')} "
              f"{task.get('timezone')}: now {cron} {tz}, keeping {keep}")
        sys.exit(10)   # changed: the controller has to restart to load it
      '';

    # The console's version: its MongoDB is in its container, inside the VM,
    # and the container has its own mongo shell, run as the console's user.
    consoleUid = toString self.nixosConfigurations.unifi-os.config.users.users.uosserver.uid;
    consoleSchedule = /* bash */ ''
      ${hereAndRunning "unifi-os"}
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

    copy = name: {
      description = "Copy the UniFi backups of ${name} to this node's disk";
      after = [ "incus.service" ];
      path = [ incus pkgs.coreutils pkgs.findutils ];
      serviceConfig.Type = "oneshot";
      script = /* bash */ ''
        incus info ${name} >/dev/null 2>&1 </dev/null || { echo "no ${name} instance"; exit 0; }
        dest=/persistent/backups/${name}
        tmp=$(mktemp -d /persistent/backups/.${name}.XXXXXX)
        trap 'rm -rf "$tmp"' EXIT
        if incus file pull -r ${name}${backups.${name}} "$tmp/" </dev/null \
           && [ -n "$(find "$tmp/autobackup" -name '*.unf' -print -quit)" ]; then
          rm -rf "$dest"; mv "$tmp/autobackup" "$dest"
          echo "copied: $(find "$dest" -name '*.unf' | wc -l) backups"
        else
          # Never replace the last good copy with nothing.
          echo "no backups in ${name} yet (turn on auto backup in UniFi); kept the old copy"
        fi
      '';
    };
  in {
    systemd.services = {
      unifi-backup-schedule = {
        description = "Keep the UniFi controller's backup schedule on time";
        after = [ "incus.service" ];
        path = [ incus pkgs.util-linux pkgs.gawk pkgs.jq ];
        serviceConfig.Type = "oneshot";
        script = /* bash */ ''
          ${hereAndRunning "unifi"}
          pid=$(incus info unifi </dev/null | awk '/^PID:/ {print $2}')
          [ -n "$pid" ] || { echo "unifi isn't running"; exit 0; }
          rc=0
          nsenter -t "$pid" -n ${setSchedule} "${cron}" "${timeZone}" ${toString keep} || rc=$?
          case $rc in
            0) ;;
            10) incus exec unifi -- systemctl restart unifi </dev/null; echo "controller restarted" ;;
            *) exit "$rc" ;;
          esac
        '';
      };
      unifi-os-backup-schedule = {
        description = "Keep the UniFi OS console's backup schedule on time";
        after = [ "incus.service" ];
        path = [ incus pkgs.jq pkgs.coreutils ];
        serviceConfig.Type = "oneshot";
        script = consoleSchedule;
      };
      unifi-backup-copy = copy "unifi";
      unifi-os-backup-copy = copy "unifi-os";
    };
    systemd.timers = lib.genAttrs [ "unifi-backup-schedule" "unifi-os-backup-schedule" ] (_: {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "15min"; OnUnitActiveSec = "1d"; };
    })
    # Daily, half an hour after the backup's time of day: a node rebuilt
    # mid-week gets its copy the next day, not the next Monday.
    // lib.genAttrs [ "unifi-backup-copy" "unifi-os-backup-copy" ] (_: {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = schedule.unifiBackupCopy.dailyOnCalendar;
        RandomizedDelaySec = "10min";
        Persistent = true;
      };
    });
    systemd.tmpfiles.rules = [ "d /persistent/backups 0700 root root -" ];
  };
}
