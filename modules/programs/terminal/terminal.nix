{ self, inputs, ... }: {
  flake.nixosModules.terminal = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.tealdeer
      self.nixosModules.git
    ];
    environment.systemPackages = with pkgs; [
      comma
      tealdeer
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.ssh.enable = true;
    };
  };
}
