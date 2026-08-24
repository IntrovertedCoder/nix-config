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
    { weeks = [  1 ]; colors = [ c.dmagenta c.dyellow c.yellow ]; } # New Years
    { weeks = [  2 ]; colors = [ c.dblue c.lblue c.dpink ]; } # Mid Winter Frost
    { weeks = [  3 ]; colors = [ c.black1 c.dblue c.dmagenta ]; } # Deep Space
    { weeks = [  4 ]; colors = [ c.dblue c.dred c.dyellow ]; } # Lunar Eve
    { weeks = [  5 ]; colors = [ c.dgreen c.dred c.dyellow ]; } # Lunar New Year
    { weeks = [  6 ]; colors = [ c.dmagenta c.dpink c.pink ]; } # Pre-Valentine
    { weeks = [  7 ]; colors = [ c.dred c.dpink c.pink c.lpink ]; } # Valentines
    { weeks = [  8 ]; colors = [ c.dmagenta c.dyellow c.dgreen ]; } # MardiGras
    { weeks = [  9 ]; colors = [ c.grey1 c.dgrey c.dblue c.dmagenta ]; } # Late Winter Dusk
    { weeks = [ 10 ]; colors = [ c.dgrey c.cyan c.green ]; } # Early Thaw
    { weeks = [ 11 ]; colors = [ c.dgreen c.dgrey c.orange ]; } # St. Patrick's
    { weeks = [ 12 ]; colors = [ c.dgreen c.lcyan c.dblue ]; } # Vernal Equinox
    { weeks = [ 13 ]; colors = [ c.dmagenta c.orange c.cyan ]; } # April Fools
    { weeks = [ 14 ]; colors = [ c.dgrey c.grey2 c.dcyan ]; } # Rain and Mist
    { weeks = [ 15 ]; colors = [ c.dpink c.lpink c.lcyan c.lmagenta ]; } # Spring Pastel
    { weeks = [ 16 ]; colors = [ c.dblue c.dgreen c.green ]; } # Earth Day
    { weeks = [ 17 ]; colors = [ c.dorange c.dgreen c.green ]; } # Arbor Day
    { weeks = [ 18 ]; colors = [ c.dblue c.dred c.green ]; } # May the 4th
    { weeks = [ 19 ]; colors = [ c.dgreen c.grey2 c.dred ]; } # Cinco de Mayo
    { weeks = [ 20 ]; colors = [ c.dcyan c.blue c.dmagenta ]; } # Synth
    { weeks = [ 21 ]; colors = [ c.dred c.white c.dblue ]; } # Memorial Day
    { weeks = [ 22 ]; colors = [ c.dblue c.dorange c.yellow ]; } # Pre Summer Sun
    { weeks = [ 23 ]; colors = [ c.dred c.orange c.yellow c.dmagenta ]; } # Pride Month Warm
    { weeks = [ 24 ]; colors = [ c.green c.dcyan c.blue c.dmagenta ]; } # Pride Month Cool
    { weeks = [ 25 ]; colors = [ c.dyellow c.orange c.dmagenta ]; } # Summer Solstice
    { weeks = [ 26 ]; colors = [ c.dred c.orange c.yellow c.green c.dblue c.dmagenta ]; } # Pride Month Rainbow
    { weeks = [ 27 ]; colors = [ c.dblue c.dgrey c.dred ]; } # Forth of July
    { weeks = [ 28 ]; colors = [ c.dred c.red c.dblue c.blue ]; } # Independence Day
    { weeks = [ 29 ]; colors = [ c.dblue c.dcyan c.cyan ]; } # Mid Summer Coast
    { weeks = [ 30 ]; colors = [ c.dmagenta c.dpink c.orange ]; } # Neon Sunset
    { weeks = [ 31 ]; colors = [ c.black1 c.dblue c.lblue ]; } # Persid Meteor Shower
    { weeks = [ 32 ]; colors = [ c.dorange c.dgreen c.dblue ]; } # Late Summer Dusk
    { weeks = [ 33 ]; colors = [ c.dcyan c.cyan c.dmagenta ]; } # Tropical Dusk
    { weeks = [ 34 ]; colors = [ c.dorange c.dyellow c.dgreen ]; } # Earthy Fade
    { weeks = [ 35 ]; colors = [ c.dorange c.lorange c.dblue ]; } # Labor Day
    { weeks = [ 36 ]; colors = [ c.grey1 c.dorange c.dmagenta ]; } # Early Autumn
    { weeks = [ 37 ]; colors = [ c.dblue c.dmagenta c.orange ]; } # Harvest Moon
    { weeks = [ 38 ]; colors = [ c.grey1 c.dgrey c.dred c.dyellow ]; } # Priate Day
    { weeks = [ 39 ]; colors = [ c.dblue c.dorange c.dyellow ]; } # Oktoberfest
    { weeks = [ 40 ]; colors = [ c.dmagenta c.dpink c.magenta ]; } # Spooky Season Twilight
    { weeks = [ 41 ]; colors = [ c.dmagenta c.dpink c.orange ]; } # Spooky Season Warm
    { weeks = [ 42 ]; colors = [ c.dgreen c.dmagenta c.magenta ]; } # Spooky Season Witching Hour
    { weeks = [ 43 ]; colors = [ c.black1 c.dmagenta c.orange c.lorange ]; } # Halloween
    { weeks = [ 44 ]; colors = [ c.dmagenta c.orange c.lorange ]; } # Halloween
    { weeks = [ 45 ]; colors = [ c.dblue c.dgreen c.cyan c.dmagenta ]; } # Northern Lights
    { weeks = [ 46 ]; colors = [ c.grey1 c.grey2 c.dblue ]; } # Late Fall Frost
    { weeks = [ 47 ]; colors = [ c.dred c.dorange c.dgreen ]; } # Thanksgiving
    { weeks = [ 48 ]; colors = [ c.dgrey c.dred c.dyellow ]; } # Dark Ember
    { weeks = [ 49 ]; colors = [ c.grey2 c.dblue c.cyan ]; } # Winter Onset
    { weeks = [ 50 ]; colors = [ c.black1 c.dgrey c.dcyan c.dblue ]; } # Deep December Solstice
    { weeks = [ 51 ]; colors = [ c.dblue c.dcyan c.cyan ]; } # Winter Solstice
    { weeks = [ 52 ]; colors = [ c.dred c.red c.dgreen c.green ]; } # Christmas
    { weeks = [ 53 ]; colors = [ c.dblue c.dmagenta c.dyellow ]; } # Midnight Count Down
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
