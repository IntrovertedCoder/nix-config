{ config, self, inputs, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.mpv = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    environment.systemPackages = with pkgs; [
    ];

    home-manager.users.shot = {
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "video/mp4" = [ "mpv.desktop" ];
          "video/x-matroska" = [ "mpv.desktop" ];
          "video/webm" = [ "mpv.desktop" ];
          "audio/mpeg" = [ "mpv.desktop" ];
          "audio/flac" = [ "mpv.desktop" ];
          "audio/ogg" = [ "mpv.desktop" ];
        };
      };

      programs.mpv = {
        enable = true;

        bindings = {
          "w" = "seek 5";
          "s" = "seek -5";
          "y" = "add volume 5";
          "m" = "add volume -5";
          "p" = "cycle pause";
          "t" = "show-progress";
        };

        config = {
          # Hardware Video Acceleration
          hwdec = "auto-safe";
          vo = "gpu-next"; # Modern, more efficient video output

          # UI and Window Behavior
          keep-open = true;
          border = false;

          # Fixed Background Configuration
          background = "color";
          background-color = "#${c.black}";

          # On-Screen Display (OSD) Styling (Keyboard UI)
          osd-font = "Hack Nerd Font Mono";
          osd-font-size = 32;

          # This color affects the OSD text and the OSD progress bar
          osd-color = "#${c.cyan}";
          osd-border-color = "#${c.black1}";
          osd-back-color = "#${c.black2}"; # Unfilled portion of the progress bar
          osd-border-size = 1;
          osd-shadow-offset = 0;

          # Subtitle Styling (Only applies to text-based subs like SRT/VTT)
          sub-font = "Hack Nerd Font Mono";
          sub-font-size = 44;
          sub-color = "#${c.white}";
          sub-border-color = "#${c.black}";
          sub-shadow-offset = 1;
          sub-shadow-color = "#${c.black1}";
        };

        # Tweaks for the standard bottom-hover UI (OSC)
        scriptOpts = {
          osc = {
            # Changes the seek indicator from a diamond to a solid bar
            seekbarstyle = "bar";
          };
        };
      };
    };
  };
}
