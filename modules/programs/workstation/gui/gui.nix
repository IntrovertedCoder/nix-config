{ self, inputs, ... }: {
  flake.nixosModules.gui = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.mango
      self.nixosModules.foot
      self.nixosModules.uwsm
      self.nixosModules.lemurs
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
