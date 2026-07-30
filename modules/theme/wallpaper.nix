{ self, inputs, lib, ... }: {
  flake.nixosModules.wallpaper = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    options.var.wallpaper = lib.mkOption {
      type = lib.types.path;
      # Point this to the relative path of your image.
      # No quotes around the path! This tells Nix to put it in the store.
      default = ./wallpaper.png;
      description = "Path to the main wallpaper image in the Nix store";
    };
    config = {
      environment.systemPackages = with pkgs; [
      ];
    };
  };
}
