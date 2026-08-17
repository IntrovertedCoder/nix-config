{ self, inputs, ... }: {
  flake.nixosModules.creative = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.blender
      self.nixosModules.audacity
      self.nixosModules.gimp
      self.nixosModules.kdenlive
      self.nixosModules.inkscape
      self.nixosModules.onlyoffice
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
    };
  };
}
