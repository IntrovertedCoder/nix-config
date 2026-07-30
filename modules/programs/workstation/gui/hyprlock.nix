{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.hyprlock = { pkgs, lib, config, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.wallpaper
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
                path = "${config.var.wallpaper}";
              }
            ];
            input-field = [
              {
                monitor = "";
                size = "50, 50";
                position = "0, -50";
                halign = "center";
                valign = "center";

                outline_thickness = 2;
                dots_size = 0.2;
                dots_spacing = 0.2; 
                dots_center = true;

                outer_color = "rgb(${c.black2})";
                inner_color = "rgb(${c.black1})";
                font_color = "rgb(${c.white})";
                font_family = "Hack Nerd Font";
                capslock_color = "rgb(${c.blue})";
                numlock_color = "rbg${c.green})";
                bothlock_color = "rbg${c.cyan})";

                fade_on_empty = true;
                hide_input = true;

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
                color = "rbg(${c.white})";
                position = "0, 50";
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
