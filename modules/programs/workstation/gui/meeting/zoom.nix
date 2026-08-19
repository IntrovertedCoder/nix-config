{ self, inputs, ... }: {
  flake.nixosModules.zoom = { pkgs, lib, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".zoom" 
        ];
        files = [
          ".config/zoomus.conf"
        ];
      };
    };

    custom.allowedUnfree = [
      "zoom"
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        zoom-us
      ];
    };
  };
}
