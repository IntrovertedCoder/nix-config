{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.foot = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    fonts.packages = with pkgs; [
      nerd-fonts.hack
    ];
    home-manager.users.shot = {
      programs.foot = {
        enable = true;
        settings = {
          main = {
            # font = "monospace:size=9";
            font = "Hack Nerd Font Mono:size=9";
            dpi-aware = "yes";
          };

          colors-dark = {
            flash-alpha=0.0;
            background = c.black;
            foreground = c.white;

            regular0 = c.black;
            regular1 = c.red;
            regular2 = c.green;
            regular3 = c.yellow;
            regular4 = c.blue;
            regular5 = c.magenta;
            regular6 = c.cyan;
            regular7 = c.white;

            bright0 = c.black2;
            bright1 = c.lred;
            bright2 = c.lgreen;
            bright3 = c.lyellow;
            bright4 = c.lblue;
            bright5 = c.lmagenta;
            bright6 = c.lcyan;
            bright7 = c.white2;

            dim0 = c.black1;
            dim1 = c.dred;
            dim2 = c.dgreen;
            dim3 = c.dyellow;
            dim4 = c.dblue;
            dim5 = c.dmagenta;
            dim6 = c.dcyan;
            dim7 = c.white1;
          };
        };
      };
    };
  };
}
