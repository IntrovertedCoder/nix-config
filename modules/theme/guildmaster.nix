{ config, lib, ...}:
let
  rawPalette = {
    base00 = "060606"; # Black
    base01 = "c0545c"; # Red
    base02 = "308821"; # Green
    base03 = "867718"; # Yellow
    base04 = "238879"; # Blue
    base05 = "ac53b8"; # Magenta
    base06 = "6e6ccd"; # Cyan
    base07 = "a1a1a1"; # LWhite
    base08 = "545454"; # LBlack
    base09 = "de6f75"; # LRed
    base0A = "4da33b"; # LYellow
    base0B = "a19133"; # LGreen
    base0C = "40a090"; # LCyan
    base0D = "c86ed4"; # LBlue
    base0E = "8a85e9"; # LMagenta
    base0F = "efefef"; # White
  };

  expandColors = colors:
    colors // (
      builtins.listToAttrs (
        builtins.concatMap (name:
          let
            hex = colors.${name};
          in [
            { name = "${name}r"; value = builtins.substring 0 2 hex; } # First 2 chars
            { name = "${name}g"; value = builtins.substring 2 2 hex; } # Middle 2 chars
            { name = "${name}b"; value = builtins.substring 4 2 hex; } # Last 2 chars
          ]
        ) (builtins.attrNames colors)
      )
    );
in {
  options.var.colors = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    description = "Base16 color theme";
  };

  config.var.colors = expandColors rawPalette;
}
