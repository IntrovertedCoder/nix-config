{ config, lib, ...}:
let
  rawPalette = {
    black    = "060606"; #060606 Black
    black1   = "1d1d1d"; #1d1d1d Black1
    black2   = "353535"; #353535 Black2
    grey1    = "4c4c4c"; #4c4c4c Grey1
    grey2    = "636363"; #636363 Grey2
    greym    = "7b7b7b"; #7b7b7b Greym
    grey3    = "929292"; #929292 Grey3
    grey4    = "a9a9a9"; #a9a9a9 Grey4
    white1   = "c0c0c0"; #c0c0c0 White2
    white2   = "d8d8d8"; #d8d8d8 White2
    white    = "efefef"; #efefef White
    dgrey    = "5e5e5e"; #5e5e5e dgrey
    grey     = "777777"; #777777 grey
    lgrey    = "919191"; #919191 lgrey
    dpink    = "9f3b60"; #9f3b60 DPink
    pink     = "bb5579"; #bb5579 Pink
    lpink    = "d86f92"; #d86f92 LPink
    dred     = "a33a45"; #a33a45 DRed
    red      = "c0545c"; #c0545c Red
    lred     = "de6f75"; #de6f75 LRed
    dorange  = "895025"; #895025 DOrange
    orange   = "a36639"; #a36639 Orange
    lorange  = "c28254"; #c28254 LOrange
    dyellow  = "6b5f00"; #6b5f00 DYellow
    yellow   = "867718"; #867718 Yellow
    lyellow  = "a19133"; #a19133 LYellow
    dgreen   = "056e00"; #056e00 DGreen
    green    = "308821"; #308821 Green
    lgreen   = "4da33b"; #4da33b LGreen
    dblue    = "5254b1"; #5254b1 DBlue
    blue     = "6e6ccd"; #6e6ccd Blue
    lblue    = "8a85e9"; #8a85e9 LBlue
    dmagenta = "90399d"; #90399d DMagenta
    magenta  = "ac53b8"; #ac53b8 Magenta
    lmagenta = "c86ed4"; #c86ed4 LMagenta
    dcyan    = "006c5d"; #006c5d DCyan
    cyan     = "1f8576"; #1f8576 Cyan
    lcyan    = "40a090"; #40a090 LCyan
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

  config.var.colors = expandColors rawPalette;
}
