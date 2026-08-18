{ self, inputs, ... }: {
  flake.nixosModules.smartmontools = { pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      smartmontools
    ];
  };
}
