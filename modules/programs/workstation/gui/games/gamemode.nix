{ self, inputs, ... }: {
  flake.nixosModules.gamemode = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    programs.gamemode = {
      enable = true;
      enableRenice = true;
      settings = {
        general = {
          renice = 10;
          inhibit_screensaver = 1;
        };
        custom = {
          start = "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Optimizations Activated'";
          end = "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Optimizations Deactivated'";
        };
      };
    };
  };
}
