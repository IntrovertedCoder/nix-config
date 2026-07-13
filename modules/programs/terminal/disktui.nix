{ self, inputs, ... }: {
  flake.nixosModules.disktui = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      disktui
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
