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

  # On every node: keep a copy of the controller's backups on local disk,
  # and keep the controller's backup schedule on _schedule.nix's time.
  flake.nixosModules.clusterUnifi = { config, lib, pkgs, ... }: let
    schedule = import ./_schedule.nix { inherit self lib; };
    keep = 8;   # weekly: two months back
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
  in {
    systemd.services.unifi-backup-schedule = {
      description = "Keep the UniFi controller's backup schedule on time";
      after = [ "incus.service" ];
      path = [ config.virtualisation.incus.package pkgs.util-linux pkgs.gawk ];
      serviceConfig.Type = "oneshot";
      script = /* bash */ ''
        # Only the node the controller runs on.
        [ "$(incus list unifi -c L -f csv </dev/null)" = "$(uname -n)" ] || { echo "unifi isn't here"; exit 0; }
        pid=$(incus info unifi </dev/null | awk '/^PID:/ {print $2}')
        [ -n "$pid" ] || { echo "unifi isn't running"; exit 0; }
        rc=0
        nsenter -t "$pid" -n ${setSchedule} "${schedule.unifiBackup.cron}" "${schedule.unifiBackup.timeZone}" ${toString keep} || rc=$?
        case $rc in
          0) ;;
          10) incus exec unifi -- systemctl restart unifi </dev/null; echo "controller restarted" ;;
          *) exit "$rc" ;;
        esac
      '';
    };
    systemd.timers.unifi-backup-schedule = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "15min"; OnUnitActiveSec = "1d"; };
    };

    systemd.services.unifi-backup-copy = {
      description = "Copy the UniFi controller's backups to this node's disk";
      after = [ "incus.service" ];
      path = [ config.virtualisation.incus.package pkgs.coreutils pkgs.findutils ];
      serviceConfig.Type = "oneshot";
      script = /* bash */ ''
        incus info unifi >/dev/null 2>&1 || { echo "no unifi instance"; exit 0; }
        dest=/persistent/backups/unifi
        tmp=$(mktemp -d /persistent/backups/.unifi.XXXXXX)
        trap 'rm -rf "$tmp"' EXIT
        if incus file pull -r unifi/var/lib/unifi/data/backup/autobackup "$tmp/" \
           && [ -n "$(find "$tmp/autobackup" -name '*.unf' -print -quit)" ]; then
          rm -rf "$dest"; mv "$tmp/autobackup" "$dest"
          echo "copied: $(find "$dest" -name '*.unf' | wc -l) backups"
        else
          # Never replace the last good copy with nothing.
          echo "no backups in the controller yet (turn on auto backup in UniFi); kept the old copy"
        fi
      '';
    };
    # Daily, half an hour after the backup's time of day: a node rebuilt
    # mid-week gets its copy the next day, not the next Monday.
    systemd.timers.unifi-backup-copy = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = schedule.unifiBackupCopy.dailyOnCalendar;
        RandomizedDelaySec = "10min";
        Persistent = true;
      };
    };
    systemd.tmpfiles.rules = [ "d /persistent/backups 0700 root root -" ];
  };
}
