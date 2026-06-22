{ config, inputs, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.tealdeer = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.tealdeer = {
        enable = true;
        settings = {
          display = {
            compact = true;
          };
          style = {
            description = {
              foreground = {
                rgb = { r = c.whiterd; g = c.whitegd; b = c.whitebd; };
              };
            };
            command_name = {
              foreground = {
                rgb = { r = c.bluerd; g = c.bluegd; b = c.bluebd; };
              };
            };
            example_text = {
              foreground = {
                rgb = { r = c.greenrd; g = c.greengd; b = c.greenbd; };
              };
            };
            example_code = {
              foreground = {
                rgb = { r = c.magentard; g = c.magentagd; b = c.magentabd; };
              };
            };
            example_variable = {
              foreground = {
                rgb = { r = c.cyanrd; g = c.cyangd; b = c.cyanbd; };
              };
            };
          };
        };
      };
    };
  };
}
