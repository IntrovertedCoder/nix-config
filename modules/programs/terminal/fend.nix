{ self, inputs, ... }: {
  flake.nixosModules.fend = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      fend
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
