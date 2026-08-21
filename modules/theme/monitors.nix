{ self, inputs, ... }: {
  flake.nixosModules.monitors = { lib, ... }: {
    # Imported from several places (wallpaper.nix, mango.nix, hyprlock.nix).
    # Without an explicit key, the module system keys each import by its
    # call-site position, so the same option ends up "declared" more than
    # once and evalModules errors out -- an explicit key makes every import
    # site resolve to the same module instance.
    key = "modules/theme/monitors.nix";

    options.var.monitors = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Output/connector name (see `wlr-randr`). Used to match this monitor in mango's monitorrule and to pick its cropped wallpaper.";
          };
          width = lib.mkOption {
            type = lib.types.ints.positive;
            description = "Horizontal resolution in pixels, as displayed (i.e. post-rotation for vertical monitors).";
          };
          height = lib.mkOption {
            type = lib.types.ints.positive;
            description = "Vertical resolution in pixels, as displayed (i.e. post-rotation for vertical monitors).";
          };
          refresh = lib.mkOption {
            type = lib.types.number;
            description = "Refresh rate in Hz.";
          };
          x = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Horizontal position in the virtual layout. May be negative.";
          };
          y = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Vertical position in the virtual layout. May be negative.";
          };
          scale = lib.mkOption {
            type = lib.types.number;
            default = 1.0;
            description = "Output scale factor, passed straight to mango's monitorrule.";
          };
          primary = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Use this monitor's cropped wallpaper as the default var.wallpaper. First monitor wins if none are marked primary.";
          };
        };
      });
      default = [
        { name = "output-0"; width = 1920; height = 1080; refresh = 60; x = 0; y = 0; scale = 1.0; primary = true; }
      ];
      description = ''
        Declarative monitor layout for this machine: positions, resolutions and
        refresh rates. Drives mango's monitorrule config, and is used to render
        the generated wallpaper as one canvas that's cropped per-monitor so it
        appears to span the whole desk, the way a span background manager would
        on X11.
      '';
    };
  };
}
