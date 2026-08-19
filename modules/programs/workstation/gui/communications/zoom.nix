{ self, inputs, ... }: {
  flake.nixosModules.zoom = { pkgs, lib, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    custom.allowedUnfree = [
      "zoom"
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        zoom-us
      ];
    };
  };
}
