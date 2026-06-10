{ self, inputs, ... }: {
  flake.nixosModules.comma = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      imports = [
        inputs.nix-index-database.homeModules.nix-index
      ];
      programs.nix-index.enable = true;
      programs.nix-index-database.comma.enable = true;
      home.packages = with pkgs; [
      ];
    };
  };
}
