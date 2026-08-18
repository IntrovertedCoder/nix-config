{ self, inputs, ... }: {
  flake.nixosModules.moonlight = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/Moonlight Game Streaming Project"
        ];
      };
    };

    home-manager.users.shot = {
      home.packages = with pkgs; [
        moonlight-qt
      ];
    };
  };
}
