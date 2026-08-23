{ self, inputs, config, lib, ... }:
let
  c = config.var.colors;

  # Same 7-stop shape the original static default used: two accent colors
  # bookended and separated by black2, each repeated to give it a wider
  # flat band.
  bandedRamp = primary: secondary:
    [ c.black2 primary primary c.black2 secondary secondary c.black2 ];

  # ISO week -> seasonal banded ramp. Winter wraps the year boundary
  # (weeks 50-52 and 1-9); the rest are contiguous, so all 52 weeks land
  # in exactly one season.
  seasonColors = week:
    if week >= 50 || week <= 9 then bandedRamp c.dred c.dgreen      # winter
    else if week <= 22 then bandedRamp c.dgreen c.lyellow           # spring
    else if week <= 35 then bandedRamp c.dblue c.dcyan              # summer
    else bandedRamp c.dorange c.dyellow;                            # fall

  # Calendar events, checked before the season default -- first match
  # wins. Weeks are approximate (a holiday's exact date shifts year to
  # year; ISO week precision is close enough for a wallpaper). Add more
  # the same way.
  events = [
    { weeks = [ 7 ]; colors = bandedRamp c.dpink c.lred; } # Valentine's Day
    { # Pride Month (June): a full rainbow gradient instead of a banded pair
      weeks = [ 22 23 24 25 26 ];
      colors = [ c.red c.orange c.yellow c.green c.blue c.magenta ];
    }
    { # Thanksgiving (~4th Thu of Nov): brighter/golder than the Fall default
      weeks = [ 47 ];
      colors = bandedRamp c.dorange c.lyellow;
    }
  ];

  weekColors = week:
    let event = lib.findFirst (e: builtins.elem week e.weeks) null events;
    in if event != null then event.colors else seasonColors week;

  # Pure ISO week, no --impure needed: Sakamoto's algorithm (day of week)
  # plus the standard ISO-8601 ordinal-day week formula, both closed-form
  # integer arithmetic -- self.lastModifiedDate already comes pre-split
  # into Y/M/D so no epoch/calendar-library conversion is needed. Not
  # exact right at the Dec31/Jan1 boundary (may resolve to week 0 or 53
  # instead of the "correct" 52/1) -- unnecessary here, since every one of
  # those boundary days already falls in this module's "winter" bucket
  # (week >= 50 || week <= 9) regardless of which of those three numbers
  # it resolves to.
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

  # Shared with perSystem's render-wallpaper CLI below, so a bare
  # `nix run .#render-wallpaper` uses the same palette as the NixOS
  # wallpaper module without depending on any host's evaluated config
  # (wallpaperColors et al. only exist per-nixosConfiguration).
  defaultColors = weekColors currentWeek;
  defaultBg = c.black;
  defaultWorld = c.black2;
in {
  flake.nixosModules.wallpaper = { pkgs, lib, config, ... }: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.monitors
    ];
    key = "modules/theme/wallpaper.nix";

    options.var.wallpaperColors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultColors;
      description = ''
        Ordered list of hex colors (no leading #, e.g. `c.dred`) fed into
        wallpaper.blend's gradient ramp as evenly-spaced stops, left to
        right. Duplicate an entry to give it a wider flat band.
      '';
    };

    options.var.wallpaperBackgroundColor = lib.mkOption {
      type = lib.types.str;
      default = defaultBg;
      description = ''
        Hex color (no leading #) for wallpaper.blend's Material.001 --
        the flat backing material behind the gradient ramp.
      '';
    };

    options.var.wallpaperWorldColor = lib.mkOption {
      type = lib.types.str;
      default = defaultWorld;
      description = ''
        Hex color (no leading #) for wallpaper.blend's World Background
        shader. Confirmed live via render diff -- shows through at the
        Circle mesh's edges and tints lighting -- unlike the file's other
        unwired colors (Emission Color, the Mix node's unused RGBA
        default, the orphaned "Dots Stroke" material), which are leftovers
        with no visual effect.
      '';
    };

    options.var.wallpaperCanvas = lib.mkOption {
      type = lib.types.path;
      description = ''
        The full generated wallpaper, sized to the bounding box of every
        monitor in var.monitors laid out at its configured position. This is
        the "span" image before it's cropped per-monitor.
      '';
    };

    options.var.wallpapers = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      description = ''
        Per-monitor crops of var.wallpaperCanvas, keyed by the monitor's
        `name` from var.monitors, so each output shows the slice of the
        canvas it would occupy in the real layout.
      '';
    };

    options.var.wallpaper = lib.mkOption {
      type = lib.types.path;
      description = ''
        The wallpaper crop for whichever monitor in var.monitors is marked
        `primary` (or the first monitor, if none are). Kept for consumers
        that only want a single image.
      '';
    };

    config = let
      monitors = config.var.monitors;
      colors = config.var.wallpaperColors;

      xs = map (m: m.x) monitors;
      xEnds = map (m: m.x + m.width) monitors;
      ys = map (m: m.y) monitors;
      yEnds = map (m: m.y + m.height) monitors;

      minX = lib.foldl' lib.min (builtins.head xs) xs;
      minY = lib.foldl' lib.min (builtins.head ys) ys;
      canvasWidth = (lib.foldl' lib.max (builtins.head xEnds) xEnds) - minX;
      canvasHeight = (lib.foldl' lib.max (builtins.head yEnds) yEnds) - minY;

      # Rendered once via Cycles (CPU-only: a sandboxed Nix build never gets
      # a GL context, so EEVEE can't run here regardless of the host's GPU).
      # Nix caches this by input hash -- it only re-renders when the blend
      # file, render script, colors, or canvas size actually change.
      canvas = pkgs.runCommand "wallpaper-canvas" {
        nativeBuildInputs = [ pkgs.blender ];
        WALLPAPER_COLORS = lib.concatStringsSep "," colors;
        WALLPAPER_BG = config.var.wallpaperBackgroundColor;
        WALLPAPER_WORLD = config.var.wallpaperWorldColor;
        WALLPAPER_WIDTH = toString canvasWidth;
        WALLPAPER_HEIGHT = toString canvasHeight;
      } ''
        export HOME=$TMPDIR
        WALLPAPER_OUT=$out blender --background ${./wallpaper.blend} --python ${./render-wallpaper.py}
      '';

      cropScript = lib.concatStrings (map (m: ''
        magick ${canvas} -crop ${toString m.width}x${toString m.height}+${toString (m.x - minX)}+${toString (m.y - minY)} +repage $out/${m.name}.png
      '') monitors);

      wallpaperCrops = pkgs.runCommand "wallpaper-crops" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
        mkdir -p $out
        ${cropScript}
      '';

      primaryMonitor = lib.findFirst (m: m.primary) (builtins.head monitors) monitors;

      # Rebuilds with the current ISO week wired in, so the seasonal/event
      # palette above (see defaultColors) picks up whichever band the
      # current week falls in. A plain `nh os switch` wouldn't do this --
      # WALLPAPER_WEEK has to be set and --impure has to be passed, since
      # Nix flakes evaluate purely by default. This can't just re-render
      # the image in place either: swaybg's systemd unit (see
      # modules/programs/workstation/gui/desktop/swaybg.nix) has the
      # wallpaper store path baked into its ExecStart at activation time,
      # so a real `nh os switch` is what actually picks up the new
      # palette and restarts it.
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
      var.wallpaperCanvas = canvas;
      var.wallpapers = builtins.listToAttrs (map (m: {
        name = m.name;
        value = "${wallpaperCrops}/${m.name}.png";
      }) monitors);
      var.wallpaper = config.var.wallpapers.${primaryMonitor.name};

      environment.systemPackages = [
        updateWallpaperScript
      ];
    };
  };

  # Standalone CLI so wallpapers can be rendered for devices with no
  # var.monitors entry -- phones, tablets, etc -- without touching any
  # host's NixOS config. Run `nix run .#render-wallpaper -- --width W
  # --height H --out PATH`, then copy the resulting PNG over however suits
  # the device (adb push, syncthing, airdrop...). Colors default to the
  # same theme wallpaperColors/wallpaperBackgroundColor/wallpaperWorldColor
  # default to above; size defaults to whatever's saved in wallpaper.blend.
  perSystem = { pkgs, lib, ... }: {
    packages.render-wallpaper = pkgs.writeShellApplication {
      name = "render-wallpaper";
      runtimeInputs = [ pkgs.blender ];
      text = ''
        usage() {
          cat <<'USAGE'
        Usage: render-wallpaper [--width W --height H] [--colors c1,c2,...]
                                 [--bg HEX] [--world HEX] [--out PATH]
                                 [--samples N]

        Renders wallpaper.blend standalone, for devices outside this
        flake's NixOS hosts (phones, tablets, etc).
          --width/--height   must be given together; if omitted, keeps the
                              resolution already saved in wallpaper.blend
          --colors/--bg/--world   default to this flake's theme
          --out               defaults to ./wallpaper-render.png
          --samples           defaults to 64
        USAGE
        }

        colors="${lib.concatStringsSep "," defaultColors}"
        bg="${defaultBg}"
        world="${defaultWorld}"
        samples=64
        out="./wallpaper-render.png"
        width=""
        height=""

        while [ $# -gt 0 ]; do
          case "$1" in
            --width) width=$2; shift 2 ;;
            --height) height=$2; shift 2 ;;
            --out) out=$2; shift 2 ;;
            --colors) colors=$2; shift 2 ;;
            --bg) bg=$2; shift 2 ;;
            --world) world=$2; shift 2 ;;
            --samples) samples=$2; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
          esac
        done

        if { [ -n "$width" ] && [ -z "$height" ]; } || { [ -z "$width" ] && [ -n "$height" ]; }; then
          echo "error: --width and --height must be given together" >&2
          usage
          exit 1
        fi

        mkdir -p "$(dirname "$out")"
        export HOME
        HOME=$(mktemp -d)
        export WALLPAPER_COLORS="$colors"
        export WALLPAPER_BG="$bg"
        export WALLPAPER_WORLD="$world"
        export WALLPAPER_OUT="$out"
        export WALLPAPER_SAMPLES="$samples"
        if [ -n "$width" ]; then
          export WALLPAPER_WIDTH="$width"
          export WALLPAPER_HEIGHT="$height"
        fi

        blender --background ${./wallpaper.blend} --python ${./render-wallpaper.py}
      '';
    };
  };
}
