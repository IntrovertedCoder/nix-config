{ self, inputs, ... }: {
  flake.nixosModules.terminal = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.tealdeer
      self.nixosModules.git
      self.nixosModules.gitui
      self.nixosModules.comma
      self.nixosModules.nh
      self.nixosModules.console
      self.nixosModules.zoxide
      self.nixosModules.nvim
      self.nixosModules.fish
      self.nixosModules.fd
      self.nixosModules.fsel
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.bash.enable = true;
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
      };
    };
  };
}
