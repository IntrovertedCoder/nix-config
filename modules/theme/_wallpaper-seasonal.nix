# The seasonal/holiday wallpaper color table -- kept in its own file so
# it's easy to find and edit without wading through wallpaper.nix's
# mechanics. Consumed by wallpaper.nix's `weekColors` as an ordered list,
# checked top to bottom, first match wins -- so more specific entries
# (holidays) are listed before the broader season ranges they sit inside.
# Any week not covered by an entry here falls back to wallpaper.nix's
# `fallbackColors`.
#
# Each `colors` list is fed directly into wallpaper.blend's gradient ramp
# as evenly-spaced stops, left to right -- any number of colors, in any
# order; repeat one to give it a wider band. No banding/shape is imposed
# for you (there used to be a `bandedRamp` helper doing that automatically
# -- gone now, so the lists below spell out that same black2-bookended
# shape by hand as a starting point; edit freely).
{ c, lib }: [
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
]
