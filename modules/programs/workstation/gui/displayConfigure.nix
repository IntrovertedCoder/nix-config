{ self, inputs, ... }: {
  flake.nixosModules.displayConfigure = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        wlay
      ];
      xdg.desktopEntries = {
        wlay = {
          name = "Wlay";
          genericName = "Display Layout Manager";
          comment = "Graphical layout manager for Wayland";
          exec = "wlay";
          terminal = false;
          categories = [ "Settings" "HardwareSettings" ];
          icon = "preferences-desktop-display";
        };
      };
    };
  };
}
