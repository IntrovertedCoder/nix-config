{ self, inputs, ... }: {
  flake.nixosModules.heroic = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/heroic"
          ".local/share/heroic"
          "Games/Heroic"
        ];
      };
    };
    home-manager.users.shot = {
      home.packages = with pkgs; [
        heroic
      ];
    };
  };
}
