{ self, inputs, ... }: {
  flake.nixosModules.gui = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.mango
      self.nixosModules.foot
      self.nixosModules.uwsm
      self.nixosModules.tuigreet
      self.nixosModules.launcher
      self.nixosModules.easyeffects
      self.nixosModules.pulsemixer

      self.nixosModules.firefox
      self.nixosModules.hyprlock
      self.nixosModules.hypridle
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      xdg.mimeApps.enable = true;
      home.packages = with pkgs; [
      ];
    };
  };
}
