{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.fzf = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.fzf = {
        enable = true;
        enableFishIntegration = true;
        enableBashIntegration = true;
        colors = {
          "fg" = "#${c.white}";
          "bg" = "#${c.black}";
          "preview-fg" = "#${c.white}";
          "preview-bg" = "#${c.black}";
          "hl" = "#${c.green}";
          "fg+" = "#${c.white1}";
          "bg+" = "#${c.black2}";
          "gutter" = "#${c.black2}";
          "hl+" = "#${c.cyan}";
          "info" = "#${c.pink}";
          "border" = "#${c.black1}";
          "prompt" = "#${c.red}";
          "marker" = "#${c.green}";
          "spinner" = "#${c.magenta}";
          "header" = "#${c.yellow}";
        };
      };
    };
  };
}
