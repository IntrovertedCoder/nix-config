{ self, inputs, ... }: {
  flake.nixosModules.blender = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/blender"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        blender
      ];
    };
  };
}
