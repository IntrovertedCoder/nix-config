{ self, inputs, ... }: {
  flake.nixosModules.communications = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.vesktop
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
