{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.wallpaper = { pkgs, lib, config, ... }: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.monitors
    ];
    key = "modules/theme/wallpaper.nix";

    options.var.wallpaperColors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ c.black2 c.dred c.dred c.black2 c.dcyan c.dcyan c.black2 ];
      description = ''
        Ordered list of hex colors (no leading #, e.g. `c.dred`) fed into
        wallpaper.blend's gradient ramp as evenly-spaced stops, left to
        right. Duplicate an entry to give it a wider flat band.
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
        WALLPAPER_WIDTH = toString canvasWidth;
        WALLPAPER_HEIGHT = toString canvasHeight;
      } ''
        export HOME=$TMPDIR
        WALLPAPER_OUT=$out blender --background ${./wallpaper.blend} --python ${./render-wallpaper.py}
      '';

      cropScript = lib.concatStrings (map (m: ''
        convert ${canvas} -crop ${toString m.width}x${toString m.height}+${toString (m.x - minX)}+${toString (m.y - minY)} +repage $out/${m.name}.png
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
}
