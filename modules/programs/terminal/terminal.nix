{ self, inputs, ... }: {
  flake.nixosModules.terminal = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.tealdeer
      self.nixosModules.git
      self.nixosModules.comma
      self.nixosModules.nh
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
      };
    };
  };
}
