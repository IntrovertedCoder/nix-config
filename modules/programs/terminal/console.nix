{ config, ...}:
let
  c = config.var.colors;
in {
  flake.nixosModules.console = { pkgs, ...}: {
    console = {
      enable = true;
      colors = [
        c.base00 # Black
        c.base01 # Red
        c.base02 # Greep
        c.base03 # Yellow
        c.base04 # Blue
        c.base05 # Magenta
        c.base06 # White
        c.base07 # Bright black
        c.base08 # Bright red
        c.base09 # Bright green
        c.base0A # Bright yellow
        c.base0B # Bright blue
        c.base0C # Bright magenta
        c.base0D # Bright cyan
        c.base0E
        c.base0F # Bright white
      ];
    };
  };
}
