{ self, inputs, ... }: {
  flake.nixosModules.nh = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 21d --keep 3"; # was 4d -- too aggressive for a weekly fleet-update cadence
      flake = "/home/shot/nix-config";
    };
  };
}
