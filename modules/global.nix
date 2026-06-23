{ self, inputs, ... }: {
  flake.nixosModules.global = { pkgs, ...}: {
    imports = [
      self.nixosModules.fail2ban
    ];
    nix = {
      settings.experimental-features = [ "nix-command" "flakes"];
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
      registry.nixpkgs.flake = inputs.nixpkgs;
    };
  };
}
