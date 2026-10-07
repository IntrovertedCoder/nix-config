{ config, lib, ...}:
let
  rawPalette = {
# HUE  (every hue derived from the cyan + green seeds)
#   pink     h =    0.4   complement of cyan  (cyan + 180)
#   red      h =   20.6   mid(purple, yellow)
#   orange   h =   60.4   triad of cyan       (cyan + 240)
#   yellow   h =  100.7   mid(orange, green)
#   green    h =  141.0   SEED HUE
#   cyan     h =  180.4   SEED HUE
#   azure    h =  240.4   mid(cyan, purple)
#   blue     h =  260.4   triad of red
#   purple   h =  300.4   triad of cyan       (cyan + 120)
#   magenta  h =  330.4   mid(pink, purple)


    black    = "060606"; #060606  L  12.2
    black1   = "171717"; #171717  L  20.5
    black2   = "2b2b2b"; #2b2b2b  L  28.9
    grey1    = "404040"; #404040  L  37.1
    grey2    = "565656"; #565656  L  45.3   <- dark tier
    greym    = "6e6e6e"; #6e6e6e  L  53.8   <- main tier
    grey3    = "868686"; #868686  L  62.0   <- light tier
    grey4    = "9f9f9f"; #9f9f9f  L  70.3
    white1   = "b9b9b9"; #b9b9b9  L  78.6
    white2   = "d4d4d4"; #d4d4d4  L  87.0
    white    = "efefef"; #efefef  L  95.2
    dpink    = "971e52"; #971e52  L  45.4  C 0.160  h   0.4
    pink     = "b33b69"; #b33b69  L  53.7  C 0.160  h   0.5
    lpink    = "d05581"; #d05581  L  62.0  C 0.161  h   0.6
    dred     = "9c1e2d"; #9c1e2d  L  45.4  C 0.160  h  20.8
    red      = "b93b44"; #b93b44  L  53.7  C 0.162  h  20.5
    lred     = "d6565b"; #d6565b  L  62.1  C 0.161  h  20.8
    dorange  = "804600"; #804600  L  45.5  C 0.106  h  60.7  gamut max
    orange   = "a15900"; #a15900  L  53.7  C 0.126  h  60.3  gamut max
    lorange  = "c36d00"; #c36d00  L  61.9  C 0.145  h  60.3  gamut max
    dyellow  = "625700"; #625700  L  45.3  C 0.095  h 100.9  gamut max
    yellow   = "7d6f00"; #7d6f00  L  53.8  C 0.112  h 100.6  gamut max
    lyellow  = "988700"; #988700  L  62.0  C 0.129  h 100.4  gamut max
    dgreen   = "146900"; #146900  L  45.4  C 0.149  h 141.0  gamut max
    green    = "2a831b"; #2a831b  L  53.7  C 0.161  h 141.1
    lgreen   = "469d38"; #469d38  L  62.0  C 0.162  h 141.0
    dcyan    = "006558"; #006558  L  45.4  C 0.082  h 179.9  gamut max
    cyan     = "008070"; #008070  L  53.7  C 0.098  h 180.0  gamut max
    lcyan    = "009c89"; #009c89  L  62.1  C 0.113  h 180.1  gamut max
    dazure   = "005c8a"; #005c8a  L  45.3  C 0.105  h 240.4  gamut max
    azure    = "0075ae"; #0075ae  L  53.7  C 0.124  h 240.5  gamut max
    lazure   = "008fd3"; #008fd3  L  62.0  C 0.143  h 240.4  gamut max
    dblue    = "1b50ae"; #1b50ae  L  45.5  C 0.161  h 260.9
    blue     = "3369ca"; #3369ca  L  53.7  C 0.162  h 261.0
    lblue    = "4b83e6"; #4b83e6  L  62.1  C 0.161  h 260.9
    dpurple  = "6639a0"; #6639a0  L  45.4  C 0.160  h 300.2
    purple   = "7e52bb"; #7e52bb  L  53.7  C 0.160  h 300.4
    lpurple  = "976bd7"; #976bd7  L  62.0  C 0.161  h 300.6
    dmagenta = "85297f"; #85297f  L  45.4  C 0.161  h 330.6
    magenta  = "9f4499"; #9f4499  L  53.7  C 0.160  h 330.1
    lmagenta = "bb5db3"; #bb5db3  L  62.1  C 0.161  h 330.6
  };

  expandColors = colors:
    colors // (
      builtins.listToAttrs (
        builtins.concatMap (name:
          let
            hex = colors.${name};
            rHex = builtins.substring 0 2 hex;
            gHex = builtins.substring 2 2 hex;
            bHex = builtins.substring 4 2 hex;

            # Helper function to convert 2-char hex to decimal integer
            hexToDec = hStr:
              let
                dict = {
                  "0"=0; "1"=1; "2"=2; "3"=3; "4"=4; "5"=5; "6"=6; "7"=7; "8"=8; "9"=9;
                  "a"=10; "b"=11; "c"=12; "d"=13; "e"=14; "f"=15;
                  "A"=10; "B"=11; "C"=12; "D"=13; "E"=14; "F"=15;
                };
                first = builtins.substring 0 1 hStr;
                second = builtins.substring 1 1 hStr;
              in (dict.${first} * 16) + dict.${second};
          in [
            # Your original hex substrings
            { name = "${name}r"; value = rHex; }
            { name = "${name}g"; value = gHex; }
            { name = "${name}b"; value = bHex; }
            # New distinct decimal integer fields
            { name = "${name}rd"; value = hexToDec rHex; }
            { name = "${name}gd"; value = hexToDec gHex; }
            { name = "${name}bd"; value = hexToDec bHex; }
          ]
        ) (builtins.attrNames colors)
      )
    );
in {
  options.var.colors = lib.mkOption {
    type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.int);
    description = "Base16 color theme";
  };

  options.var.opacity = lib.mkOption {
    type = lib.types.float;
    default = 0.75;
    description = "Shared background opacity (0-1) for translucent surfaces, e.g. foot and vesktop";
  };

  options.var.opacityByte = lib.mkOption {
    type = lib.types.int;
    description = "var.opacity expressed as a 0-255 byte, derived from var.opacity";
  };

  options.var.opacityHex = lib.mkOption {
    type = lib.types.str;
    description = "var.opacity expressed as a 2-char lowercase hex string (for #RRGGBBAA CSS), derived from var.opacity";
  };

  config.var.colors = expandColors rawPalette;

  config.var.opacityByte = builtins.floor (config.var.opacity * 255 + 0.5);

  config.var.opacityHex =
    let
      hexDigits = "0123456789abcdef";
      byte = config.var.opacityByte;
      high = byte / 16;
      low = byte - (high * 16);
    in (builtins.substring high 1 hexDigits) + (builtins.substring low 1 hexDigits);
}
