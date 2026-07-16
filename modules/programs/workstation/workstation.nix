{ self, inputs, ... }: {
  flake.nixosModules.workstation = { pkgs, ...}: {
    imports = [
      self.nixosModules.gui
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
