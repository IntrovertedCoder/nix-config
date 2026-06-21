{ self, inputs, ... }: {
  flake.nixosModules.template = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
