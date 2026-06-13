{ config, lib, ...}:
let
  rawPalette = {
    black    = "060606"; #060606 Black
    black1   = "202020"; #202020 Black1
    black2   = "3a3a3a"; #3a3a3a Black2
    grey1    = "545454"; #545454 Grey1
    grey2    = "6e6e6e"; #6e6e6e Grey2
    grey3    = "878787"; #878787 Grey3
    grey4    = "a1a1a1"; #a1a1a1 Grey4
    white1   = "bbbbbb"; #bbbbbb White2
    white2   = "d5d5d5"; #d5d5d5 White2
    white    = "efefef"; #efefef White
    red      = "c0545c"; #c0545c Red
    orange   = "A36639"; #A36639 Orange
    yellow   = "867718"; #867718 Yellow
    green    = "308821"; #308821 Green
    blue     = "6E6CCD"; #6E6CCD Blue
    magenta  = "ac53b8"; #ac53b8 Magenta
    cyan     = "1F8576"; #1F8576 Cyan
    lred     = "de6f75"; #de6f75 LRed
    lorange  = "C28254"; #C28254 LOrange
    lyellow  = "a19133"; #a19133 LYellow
    lgreen   = "4da33b"; #4da33b LGreen
    lblue    = "8a85e9"; #8a85e9 LBlue
    lmagenta = "c86ed4"; #c86ed4 LMagenta
    lcyan    = "40a090"; #40a090 LCyan
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
