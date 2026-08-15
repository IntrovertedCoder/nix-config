{ self, inputs, ... }: {
  flake.nixosModules.flameshot = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      wayland.windowManager.mango.settings.bind = [
        "NONE,Print,spawn,uwsm app flameshot gui"
        "ALT,Print,spawn,uwsm app -- sh -c 'hyprpicker | wl-copy; sleep 0.3'"
      ];
      services.flameshot = {
        enable = true;
        settings = {
          General = {
            useGrimAdapter = true;
            disabledGrimWarning = true;
          };
        };
      };
      home.packages = with pkgs; [
        grim
        hyprpicker
      ];
    };
  };
}
