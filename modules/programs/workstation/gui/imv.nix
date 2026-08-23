{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.imv = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "image/png" = [ "imv-dir.desktop" ];
          "image/jpeg" = [ "imv-dir.desktop" ];
          "image/gif" = [ "imv-dir.desktop" ];
          "image/webp" = [ "imv-dir.desktop" ];
        };
      };
      programs.imv = {
        enable = true;
        settings = {
          binds = {
            w = "next";
            s = "prev";
            y = "slideshow +1";
            p = "slideshow 0";
            m = "slideshow -1";
            t = "slideshow 10";
          };
          options = {
            background = "${c.black}";
            overlay = true;
            overlay_text_color = "${c.white}";
            overlay_background_color = "${c.black1}";
            overlay_font = "Hack Nerd Font Mono:12";
            overlay_text = "$(basename \"$imv_current_file\")  [$imv_current_index / $imv_file_count]";
          };
        };
      };
    };
  };
}
