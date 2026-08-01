{ self, inputs, ... }: {
  flake.nixosModules.flameshot = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      services.flameshot = {
        enable = true;
        settings = {
          General = {
            useGrimAdapter = true;
            disabledGrimWarning = true;
          };
        };
      };
      home.packages = with pkgs; [
        grim
      ];
    };
  };
}
