{ self, inputs, ... }: {
  flake.nixosModules.stui = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        s-tui
      ];
    };
  };
}
