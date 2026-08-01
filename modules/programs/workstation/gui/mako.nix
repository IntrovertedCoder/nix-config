{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.mako = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      libnotify
    ];
    home-manager.users.shot = {
      services.mako = {
        enable = true;
        settings = {
          background-color = "#${c.black}";
          text-color = "#${c.white}";
          progress-color = "#${c.cyan}";
          border-color = "#${c.blue}";
          border-size = 2;
          default-timeout = 5000;

          "urgency=low" = {
            border-color = "#${c.green}";
            default-timeout = 2000;
          };

          "urgency=critical" = {
            border-color = "#${c.red}";
            default-timeout = 0;
            background-color = "#${c.red}";
            text-color = "#${c.white}";
          };
        };
      };
      home.packages = with pkgs; [
      ];
    };
  };
}
