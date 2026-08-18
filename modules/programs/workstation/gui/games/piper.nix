{ self, inputs, ... }: {
  flake.nixosModules.piper = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    services.ratbagd.enable = true;
    home-manager.users.shot = {
      home.packages = with pkgs; [
        piper
      ];
    };
  };
}
