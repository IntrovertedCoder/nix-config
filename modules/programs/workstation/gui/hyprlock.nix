{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.hyprlock = { pkgs, lib, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    options.var.lockCommand = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.hyprlock}/bin/hyprlock";
      description = "The command used to lock the screen";
    };

    config = {
      programs.hyprlock.enable = true;

      home-manager.users.shot = {
        programs.hyprlock = {
          enable = true;
          settings = {
            general = {
              disable_loading_bar = true;
              hide_cursor = true;
              grace = 0;
              no_fade_in = false;
            };
            background = [
              {
                monitor = "";
                path = "screenshot";
                blur_passes = 2;
                blur_size = 8;
              }
            ];
            input-field = [
              {
                monitor = "";
                size = "250, 50";
                position = "0, -100";
                halign = "center";
                valign = "center";

                outline_thickness = 2;
                dots_size = 0.2; 
                dots_spacing = 0.2; 
                dots_center = true;

                outer_color = "rgb(${c.black2})";
                inner_color = "rgb(${c.black1})";
                font_color = "rgb(${c.white})";

                fade_on_empty = false;
                hide_input = false;

                check_color = "rgb(${c.cyan})";
                fail_color = "rgb(${c.red})";
                fail_text = ''<i>$FAIL <b>($ATTEMPTS)</b></i>'';
              }
            ];
            label = [
              {
                monitor = "";
                text = "$TIME";
                font_size = 40;
                font_family = "Hack Nerd Font";
                color = "rbg(${c.white})";
                position = "0, 100";
                halign = "center";
                valign = "center";
              }
            ];
          };
        };
      };
    };
  };
}
