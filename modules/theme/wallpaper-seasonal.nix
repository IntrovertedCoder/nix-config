{ self, inputs, config, lib, ... }:
let
  c = config.var.colors;

  # Ordered list of { weeks; colors; } entries, checked top to bottom,
  # first match wins -- so more specific entries (holidays) are listed
  # before the broader season ranges they sit inside. Each `colors` list
  # is fed directly into wallpaper.blend's gradient ramp as evenly-spaced
  # stops, left to right -- any number of colors, in any order; repeat one
  # to give it a wider band.
  weeklyPalette = [
    { weeks = [ 7 ]; colors = [ c.black2 c.dpink c.dpink c.black2 c.lred c.lred c.black2 ]; } # Valentine's Day
    { # Pride Month (June): a full rainbow gradient
      weeks = lib.range 22 26;
      colors = [ c.red c.orange c.yellow c.green c.blue c.magenta ];
    }
    { # Thanksgiving (~4th Thu of Nov): brighter/golder than the general Fall entry below
      weeks = [ 47 ];
      colors = [ c.black2 c.dorange c.dorange c.black2 c.lyellow c.lyellow c.black2 ];
    }
    { # Winter: wraps the year boundary (weeks 50-53 and 1-9)
      weeks = lib.range 50 53 ++ lib.range 1 9;
      colors = [ c.black2 c.dred c.dred c.black2 c.dgreen c.dgreen c.black2 ];
    }
    { # Spring
      weeks = lib.range 10 22;
      colors = [ c.black2 c.dgreen c.dgreen c.black2 c.lyellow c.lyellow c.black2 ];
    }
    { # Summer
      weeks = lib.range 23 35;
      colors = [ c.black2 c.dblue c.dblue c.black2 c.dcyan c.dcyan c.black2 ];
    }
    { # Fall
      weeks = lib.range 36 49;
      colors = [ c.black2 c.dorange c.dorange c.black2 c.dyellow c.dyellow c.black2 ];
    }
  ];

  # Used when a week isn't covered by any entry above (currently none: the
  # season ranges already span all of 1-53). Same shape wallpaper.nix's own
  # plain default uses.
  fallbackColors = [ c.black2 c.dred c.dred c.black2 c.dcyan c.dcyan c.black2 ];

  weekColors = week:
    let entry = lib.findFirst (e: builtins.elem week e.weeks) null weeklyPalette;
    in if entry != null then entry.colors else fallbackColors;

  # Pure ISO week, no --impure needed: Sakamoto's algorithm (day of week)
  # plus the standard ISO-8601 ordinal-day week formula, both closed-form
  # integer arithmetic -- self.lastModifiedDate already comes pre-split
  # into Y/M/D so no epoch/calendar-library conversion is needed. Not
  # exact right at the Dec31/Jan1 boundary (may resolve to week 0 or 53
  # instead of the "correct" 52/1) -- unnecessary here, since every one of
  # those boundary days already falls in the "winter" entry above
  # regardless of which of those three numbers it resolves to.
  isoWeekOfDate = y: m: d:
    let
      isLeap = lib.mod y 4 == 0 && (lib.mod y 100 != 0 || lib.mod y 400 == 0);
      monthDays = [ 31 (if isLeap then 29 else 28) 31 30 31 30 31 31 30 31 30 31 ];
      ordinalDay = d + lib.foldl' lib.add 0 (lib.take (m - 1) monthDays);

      t = [ 0 3 2 5 0 3 5 1 4 6 2 4 ];
      yy = if m < 3 then y - 1 else y;
      dow0Sun = lib.mod (yy + yy / 4 - yy / 100 + yy / 400 + builtins.elemAt t (m - 1) + d) 7;
      isoWeekday = if dow0Sun == 0 then 7 else dow0Sun; # Monday=1..Sunday=7
    in
      (ordinalDay - isoWeekday + 10) / 7;

  # lib.toInt refuses zero-padded strings ("08") outright -- it won't
  # silently misparse them as octal, it just errors, calling the reading
  # "ambiguous". Same footgun update-wallpaper's bash `10#$(date +%V)`
  # sidesteps, just with no bash-style base-prefix equivalent in Nix;
  # stripping a single leading zero first is enough since month/day here
  # are always exactly 2 digits (01-12/01-31, never "00").
  toIntNoLeadingZero = s:
    lib.toInt (if lib.hasPrefix "0" s then builtins.substring 1 (builtins.stringLength s - 1) s else s);

  # self.lastModifiedDate ("YYYYMMDDHHMMSS", UTC) is the last commit's
  # date, available under plain pure evaluation for a clean git checkout
  # -- the same well-established mechanism version-stamp flakes use (e.g.
  # "unstable-${builtins.substring 0 8 self.lastModifiedDate}"). Since
  # both vmtest's Thursday cache-warm build and a follower's Friday
  # `fleet-pull-update` pull build from the exact same commit (both do a
  # `git merge --ff-only origin/main` first), they always compute the same
  # week here with zero env-var plumbing between them -- no --impure
  # needed anywhere in that path, and no risk of the two machines
  # disagreeing about "today".
  pureCurrentWeek =
    let s = self.lastModifiedDate;
    in isoWeekOfDate
      (toIntNoLeadingZero (builtins.substring 0 4 s))
      (toIntNoLeadingZero (builtins.substring 4 2 s))
      (toIntNoLeadingZero (builtins.substring 6 2 s));

  # Explicit override for previewing a specific week (see the
  # `update-wallpaper` script below, e.g. `update-wallpaper 24` to check
  # Pride month's rainbow before June) -- still needs --impure, since
  # builtins.getEnv throws under Nix's pure-eval mode otherwise; tryEval
  # catches that so any build that doesn't set WALLPAPER_WEEK just falls
  # through to the always-available pure value above instead of erroring.
  currentWeek =
    let raw = builtins.tryEval (builtins.getEnv "WALLPAPER_WEEK");
    in if raw.success && raw.value != "" then lib.toInt raw.value else pureCurrentWeek;

  seasonalColors = weekColors currentWeek;
in {
  # Opt-in seasonal/holiday rotation: import this module on a host instead
  # of self.nixosModules.wallpaper directly (it imports that itself, so
  # importing both isn't needed) to get var.wallpaperColors overridden with
  # the weeklyPalette pick above. Hosts that only import wallpaper.nix
  # (or that don't import this) keep its plain static default untouched.
  flake.nixosModules.wallpaperSeasonal = { pkgs, lib, config, ... }: {
    imports = [ self.nixosModules.wallpaper ];
    key = "modules/theme/wallpaper-seasonal.nix";

    config = let
      # Rebuilds with the current ISO week wired in, forcing a specific
      # week's palette regardless of what pureCurrentWeek above would pick
      # (e.g. to preview a holiday ahead of time). A plain `nh os switch`
      # doesn't need this -- pureCurrentWeek above already applies with no
      # --impure required -- but this can't just re-render the image in
      # place either way: swaybg's systemd unit (see modules/programs/
      # workstation/gui/desktop/swaybg.nix) has the wallpaper store path
      # baked into its ExecStart at activation time, so a real `nh os
      # switch` is what actually picks up a new palette and restarts it.
      updateWallpaperScript = pkgs.writeShellApplication {
        name = "update-wallpaper";
        runtimeInputs = [ pkgs.nh ];
        text = ''
          usage() {
            echo "Usage: update-wallpaper [WEEK]" >&2
            echo "  WEEK: ISO week (1-53) to force; defaults to the current week." >&2
          }
          case "''${1:-}" in -h|--help) usage; exit 0 ;; esac

          # 10#... forces base-10 parsing so date's zero-padded "08"/"09"
          # aren't misread as invalid octal.
          week="''${1:-$(( 10#$(date +%V) ))}"
          WALLPAPER_WEEK="$week" nh os switch -- --impure
        '';
      };
    in {
      # mkDefault: a host's own var.wallpaperColors assignment (e.g.
      # alaptop's commented-out `var.wallpaperColors = [ c.magenta c.black2
      # c.cyan ];`) still wins over this if uncommented -- same precedence
      # wallpaper.nix's own option default already loses to.
      var.wallpaperColors = lib.mkDefault seasonalColors;

      environment.systemPackages = [ updateWallpaperScript ];
    };
  };
}
