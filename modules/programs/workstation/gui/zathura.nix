{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.zathura = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "application/postscript" = [ "org.pwmt.zathura.desktop" ];
          "application/x+fictionbook+xml" = [ "org.pwmt.zathura.desktop" ];
          "application/epub+zip" = [ "org.pwmt.zathura.desktop" ];
          "application/pdf" = [ "org.pwmt.zathura.desktop" ];
          "application/x-tar" = [ "org.pwmt.zathura.desktop" ];
        };
      };
      programs.zathura = {
        enable = true;
        options = {
          default-bg = "#${c.black}";
          default-fg = "#${c.white}";
          completion-highlight-fg = "#${c.black2}";
          completion-highlight-bg = "#${c.blue}";
          completion-group-fg = "#${c.white2}";
          completion-group-bg = "#${c.black}";
          completion-bg = "#${c.black2}";
          completion-fg = "#${c.greym}";
          font = "Hack Nerd Font Mono";

          selection-clipboard = "clipboard";

          continuous-hist-save = "true";
        };
      };
    };
  };
}
