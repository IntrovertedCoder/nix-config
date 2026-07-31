{ self, inputs, ... }: {
  flake.nixosModules.hypridle = { pkgs, config, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        wlopm
        brightnessctl
      ];
    services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "pidof hyprlock || ${config.var.lockCommand}";

            unlock_cmd = "pkill -USR1 hyprlock";

            before_sleep_cmd = "loginctl lock-session";

            after_sleep_cmd = "${pkgs.wlopm}/bin/wlopm --on '*'";

            # YT ignore
            ignore_dbus_inhibit = false; 
          };

          listener = [
            {
              timeout = 150;
              on-timeout = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10"; 
              on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -r";
            }
            {
              timeout = 300;
              on-timeout = "pidof hyprlock || ( ${config.var.lockGrace} & disown; sleep 0.2; loginctl lock-session )";
            }
            {
              timeout = 330;
              on-timeout = "${pkgs.wlopm}/bin/wlopm --off '*'";
              on-resume = "${pkgs.wlopm}/bin/wlopm --on '*'";
            }
            # Prevent suspend on rebuild, but allow locking
            {
              timeout = 900;
              on-timeout = "pidof nh || pidof nixos-rebuild || systemctl suspend";
            }
            {
              timeout = 1800;
              on-timeout = "pidof nh || pidof nixos-rebuild || systemctl suspend";
            }
            {
              timeout = 2700;
              on-timeout = "pidof nh || pidof nixos-rebuild || systemctl suspend";
            }
            {
              timeout = 3600;
              on-timeout = "pidof nh || pidof nixos-rebuild || systemctl suspend";
            }
          ];
        };
      };
    };
  };
}
