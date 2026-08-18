{ self, inputs, ... }: {
  flake.nixosModules.mtr = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        mtr
      ];
    };
  };
}
