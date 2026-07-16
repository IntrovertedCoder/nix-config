{ self, inputs, ... }: {
  flake.nixosModules.gui = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.mango
      self.nixosModules.foot
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
