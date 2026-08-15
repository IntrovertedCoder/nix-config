{ self, inputs, ... }: {
  flake.nixosModules.signal = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/Signal"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        signal-desktop
      ];
    };
  };
}
