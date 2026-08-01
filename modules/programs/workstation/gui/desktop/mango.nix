{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.mango = { pkgs, config, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      inputs.mangowm.nixosModules.mango
    ];
    environment.systemPackages = with pkgs; [
    ];
    programs.mangowc.enable = true;
    hardware.graphics.enable = true;
    home-manager.users.shot = {
      imports = [
        inputs.mangowm.hmModules.mango
      ];
      home.packages = with pkgs; [
        nordzy-cursor-theme
      ];
      wayland.windowManager.mango = {
        enable = true;
        extraConfig = ''
          windowrule=appid:launcher,isfloating:1
        '';
        settings = {
          circle_layout = "scroller,vertical_scroller,center_tile";

          # Gaps/border
          borderpx = 4;
          gappih = 8;
          gappiv = 8;
          gappoh = 8;
          gappov = 8;

          # Theme
          rootcolor = "0x${c.black2}ff";
          bordercolor = "0x${c.grey1}ff";
          splitcolor = "0x${c.orange}FF";
          focuscolor = "0x${c.green}ff";
          urgentcolor = "0x${c.magenta}ff";
          dropcolor = "0x${c.cyan}bf";
          maximizescreencolor = "0x${c.orange}ff";
          scratchpadcolor = "0x${c.lorange}ff";
          globalcolor = "0x${c.dorange}ff";
          overlaycolor = "0x${c.lred}ff";
          # Jump mode
          jump_label_decorate_fg_color = "0x${c.white}bf"; #c4939d
          jump_label_decorate_bg_color = "0x${c.black}bf"; #201b14
          jump_label_decorate_focus_fg_color = "0x${c.black}bf"; #201b14
          jump_label_decorate_focus_bg_color = "0x${c.red}bf"; #c4939d
          jump_label_decorate_border_color = "0x${c.blue}bf"; #8baa8b
          jump_label_decorate_border_width = 4;
          jump_label_decorate_corner_radius = 0;
          jump_label_decorate_padding_x = 8;
          jump_label_decorate_padding_y = 8;
          jump_label_decorate_font_desc = "Hack Nerd Font Mono 16";

          cursor_theme = "Nordzy-cursors";
          cursor_size = 24;

          # Mouse
          drag_tile_to_tile = 1;
          mouse_natural_scrolling = 0;
          # Trackpad
          trackpad_natural_scrolling = 1; # Default
          tap_to_click = 1; # Default
          tap_and_drag = 1; # Default


          # Scroller layout
          scroller_structs = 10;
          scroller_default_proportion = 0.6;
          scroller_focus_center = 0; # Default
          scroller_prefer_center = 0; # Default
          scroller_prefer_overspread = 1; # Default
          edge_scroller_pointer_focus = 1; # Default
          edge_scroller_focus_allow_speed = 0.0; # Default
          scroller_default_proportion_single = 1.0;
          scroller_ignore_proportion_single = 0;
          scroller_proportion_preset = "0.2,0.4,0.6,0.8,1.0";

          bind = [
            # Launch Apps
            "Alt,Return,spawn,uwsm app foot"
            "ALT,d,spawn,uwsm app -- foot -a launcher -e otter-launcher"

            "NONE,Print,spawn,uwsm app flameshot gui"
            "ALT,Print,spawn,uwsm app -- sh -c 'hyprpicker | wl-copy; sleep 0.3'"

            "ALT+SHIFT+CTRL,r,reload_config"
            "ALT+SHIFT+CTRL,l,spawn_shell,${config.var.lockCommand}"
            "ALT+SHIFT,q,killclient"
            "ALT,n,switch_layout"
            "ALT,tab,togglejump"

            # Scroller keybinds
            "ALT,x,switch_proportion_preset"

            # Focus window
            "ALT,h,focusdir,left"
            "ALT,j,focusdir,down"
            "ALT,k,focusdir,up"
            "ALT,l,focusdir,right"
            # Move window
            "ALT+SHIFT,h,exchange_client,left"
            "ALT+SHIFT,j,exchange_client,down"
            "ALT+SHIFT,k,exchange_client,up"
            "ALT+SHIFT,l,exchange_client,right"

            # Window status
            "ALT,f,togglefullscreen"
            "ALT+SHIFT,f,togglefloating"
            "ALT,i,minimized"
            "ALT+SHIFT,i,restore_minimized"

            # Tag switching
            "ALT,1,view,1,0"
            "ALT,2,view,2,0"
            "ALT,3,view,3,0"
            "ALT,4,view,4,0"
            "ALT,5,view,5,0"
            "ALT,6,view,6,0"
            "ALT,7,view,7,0"
            "ALT,8,view,8,0"
            "ALT,9,view,9,0"

            # Tag moving
            "ALT+SHIFT,1,tagsilent,1,0"
            "ALT+SHIFT,2,tagsilent,2,0"
            "ALT+SHIFT,3,tagsilent,3,0"
            "ALT+SHIFT,4,tagsilent,4,0"
            "ALT+SHIFT,5,tagsilent,5,0"
            "ALT+SHIFT,6,tagsilent,6,0"
            "ALT+SHIFT,7,tagsilent,7,0"
            "ALT+SHIFT,8,tagsilent,8,0"
            "ALT+SHIFT,9,tagsilent,9,0"
          ];
          mousebind = [
            # Mouse moving
            "ALT,btn_left,moveresize,curmove"
            "ALT,btn_right,moveresize,curresize"
          ];
          tagrule = [
            "id:1,layout_name:scroller"
            "id:2,layout_name:scroller"
            "id:3,layout_name:scroller"
            "id:4,layout_name:scroller"
            "id:5,layout_name:scroller"
            "id:6,layout_name:scroller"
            "id:7,layout_name:scroller"
            "id:8,layout_name:scroller"
            "id:9,layout_name:scroller"
          ];
        };
      };
    };
  };
}
