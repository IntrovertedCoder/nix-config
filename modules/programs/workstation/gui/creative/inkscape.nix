{ self, inputs, ... }: {
  flake.nixosModules.inkscape = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/inkscape"
          ".local/share/inkscape"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        inkscape
      ];
    };
  };
}
