{ self, inputs, ... }: {
  flake.nixosModules.meeting = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.zoom
      self.nixosModules.teams
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
