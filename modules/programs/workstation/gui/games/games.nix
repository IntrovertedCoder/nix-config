{ self, inputs, ... }: {
  flake.nixosModules.games = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.steam
    ];
    environment.systemPackages = with pkgs; [
    ];
    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          "Games"
        ];
      };
    };
    home-manager.users.shot = {
      xdg.mimeApps.enable = true;
      home.packages = with pkgs; [
      ];
    };
  };
}
