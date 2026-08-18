{ self, inputs, ... }: {
  flake.nixosModules.nmap = { pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      nmap
    ];
  };
}
