{ self, inputs, ... }: {
  flake.nixosModules.kdenlive = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".local/share/kdenlive"
        ];
        files = [
          ".config/kdenliverc"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        kdePackages.kdenlive
      ];
    };
  };
}
