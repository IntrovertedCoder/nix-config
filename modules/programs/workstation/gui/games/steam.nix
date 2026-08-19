{ self, inputs, ... }: {
  flake.nixosModules.steam = { pkgs, lib, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".local/share/Steam"
          ".steam"
          "Games/Steam"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];

    custom.allowedUnfree = [
      "steam"
      "steam-unwrapped"
    ];

    programs.steam = {
      enable = true;

      # Add GE-Proton versions directly to Steam
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };
  };
}
