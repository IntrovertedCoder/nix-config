{ config, lib, ...}:
let
  rawPalette = {
    base00 = "060606"; # color0, background
    base01 = "1c1c1c";
    base02 = "383838";
    base03 = "545454"; # color8
    base04 = "7c7c7c";
    base05 = "a1a1a1"; # lgrey, color7, foreground, cursorColor
    base06 = "a1a1a1"; # lgray, color7
    base07 = "efefef"; # white, color15
    base08 = "c0545c"; # red, color1
    base09 = "de6f75"; # lred, color9
    base0A = "867718"; # yellow, color3
    base0B = "308821"; # green, color2
    base0C = "6e6ccd"; # cyan, color6
    base0D = "238879"; # blue, color4
    base0E = "ac53b8"; # magenta, color5
    base0F = "40a090"; # lblue, color12
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
