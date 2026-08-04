{ self, inputs, ... }: {
  flake.nixosModules.hypridlesuspend = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Toggle suspend lock"
        prefix = "sl"
        cmd = "if systemctl --user is-active --quiet suspend-block; then systemctl --user stop suspend-block; else systemd-run --user --unit=suspend-block sleep infinity; fi"
        with_argument = false
      '';
      services.hypridle = {
        settings = {
          listener = [
            {
              timeout = 900;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
            {
              timeout = 1800;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
            {
              timeout = 2700;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
            {
              timeout = 3600;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
          ];
        };
      };
    };
  };
}
