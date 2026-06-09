{ inputs, ... }: {
  flake.nixosModules.global = { pkgs, ...}: {
    nix = {
      settings.experimental-features = [ "nix-command" "flakes"];
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
      registry.nixpkgs.flake = inputs.nixpkgs;
    };
  };
}
