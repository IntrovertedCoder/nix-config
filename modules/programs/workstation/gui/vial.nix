{ self, inputs, ... }: {
  flake.nixosModules.Vial = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    services.udev.packages = with pkgs; [
      vial
      qmk
      qmk-udev-rules
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        vial
      ];
    };
  };
}
