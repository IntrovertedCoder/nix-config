{ self, inputs, ... }: {
  flake.nixosModules.gamescope = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    programs.gamescope = {
      enable = true;
      capSysNice = true;
    };
  };
}
