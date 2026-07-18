{ self, inputs, ... }: {
  flake.nixosModules.dua = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      dua
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
