{ self, ... }: {
  flake.nixosModules.terminal = { pkgs, ...}: {
    imports = [
      self.nixosModules.tealdeer
      self.nixosModules.git
    ];
    environment.systemPackages = with pkgs; [
      comma
      tealdeer
    ];
  };
}
