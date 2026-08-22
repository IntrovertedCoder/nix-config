{ self, inputs, config, ... }:
let
  c = config.var.colors;

  # Shared with perSystem's render-wallpaper CLI below, so a bare
  # `nix run .#render-wallpaper` uses the same palette as the NixOS
  # wallpaper module without depending on any host's evaluated config
  # (wallpaperColors et al. only exist per-nixosConfiguration).
  defaultColors = [ c.black2 c.dred c.dred c.black2 c.dcyan c.dcyan c.black2 ];
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
    in {
      var.wallpaperCanvas = canvas;
      var.wallpapers = builtins.listToAttrs (map (m: {
        name = m.name;
        value = "${wallpaperCrops}/${m.name}.png";
      }) monitors);
      var.wallpaper = config.var.wallpapers.${primaryMonitor.name};

      environment.systemPackages = with pkgs; [
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
