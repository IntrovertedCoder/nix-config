{ self, inputs, ... }: {
  flake.nixosModules.audacity = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/audacity"
          ".local/share/audacity"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        audacity
      ];
    };
  };
}
