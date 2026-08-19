{ self, inputs, ... }: {
  flake.nixosModules.teams = { pkgs, lib, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/teams-for-linux"
        ];
      };
    };

    home-manager.users.shot = {
      home.packages = with pkgs; [
        teams-for-linux
      ];
    };
  };
}
