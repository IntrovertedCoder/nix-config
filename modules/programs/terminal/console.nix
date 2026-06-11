{ config, ...}:
let
  c = config.var.colors;
in {
  flake.nixosModules.console = { pkgs, ...}: {
    console = {
      enable = true;
      colors = [
        c.black
        c.red
        c.green
        c.yellow
        c.blue
        c.magenta
        c.cyan
        c.grey4
        c.grey1
        c.lred
        c.lyellow
        c.lgreen
        c.lcyan
        c.lblue
        c.lmagenta
        c.white
      ];
    };
  };
}
