# The cluster's weekly times, all taken from vmtest's weekly update
# (modules/fleet/vmtest-orchestrator.nix, Monday 03:00 at the moment):
#
#   an hour before       the UniFi controller's backup (unifi.nix)
#   half an hour before  the nodes copy those backups, daily (unifi.nix)
#   vmtest's time        vmtest updates flake.lock and builds everything
#   an hour after        the nodes update themselves (update.nix)
#
# Change vmtest's timer (or its time.timeZone) and the rest follow. Plain
# data, imported by the modules that need it (the leading underscore keeps
# import-tree from loading it as a flake module).
{ self, lib }: let
  vmtest = self.nixosConfigurations.vmtest.config;
  spec = vmtest.systemd.timers.fleet-update.timerConfig.OnCalendar;
  m = builtins.match "([A-Z][a-z][a-z]) [*]-[*]-[*] ([0-9][0-9]):([0-9][0-9])(:00)?" spec;
  days = [ "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat" ];   # cron numbers them 0-6
  dayNo = lib.lists.findFirstIndex (d: d == builtins.elemAt m 0) null days;
  toInt = s: lib.toInt (lib.removePrefix "0" s);   # "08" -> 8
  # Minutes into the week, so "an hour before Monday 00:30" lands on Sunday.
  base = dayNo * 1440 + toInt (builtins.elemAt m 1) * 60 + toInt (builtins.elemAt m 2);
  week = 7 * 1440;
  pad = n: lib.fixedWidthNumber 2 n;
  # vmtest's zone (null means UTC, which is also what the nodes run in).
  timeZone = if vmtest.time.timeZone == null then "UTC" else vmtest.time.timeZone;
  at = offsetMinutes: let
    t = lib.mod (lib.mod (base + offsetMinutes) week + week) week;
    day = t / 1440;
    hour = lib.mod t 1440 / 60;
    minute = lib.mod t 60;
  in {
    # systemd, in vmtest's zone whatever zone the node itself runs in
    onCalendar = "${builtins.elemAt days day} *-*-* ${pad hour}:${pad minute}:00 ${timeZone}";
    # every day at the same time of day
    dailyOnCalendar = "*-*-* ${pad hour}:${pad minute}:00 ${timeZone}";
    cron = "${toString minute} ${toString hour} * * ${toString day}";
    inherit timeZone;
  };
in
  assert lib.assertMsg (m != null && dayNo != null)
    "modules/cluster/_schedule.nix only understands vmtest timers like \"Mon *-*-* 03:00:00\", not \"${spec}\"";
  {
    vmtest = at 0;
    unifiBackup = at (-60);
    unifiBackupCopy = at (-30);   # daily, after the backup's time of day
    clusterUpdate = at 60;
  }
