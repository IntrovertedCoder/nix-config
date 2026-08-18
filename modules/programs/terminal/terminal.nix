{ self, inputs, ... }: {
  flake.nixosModules.terminal = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.tealdeer
      self.nixosModules.ssh
      self.nixosModules.git
      self.nixosModules.gitui
      self.nixosModules.comma
      self.nixosModules.nh
      self.nixosModules.console
      self.nixosModules.zoxide
      self.nixosModules.nvim
      self.nixosModules.fish
      self.nixosModules.starship
      self.nixosModules.fd
      self.nixosModules.fsel
      self.nixosModules.vs
      self.nixosModules.eza
      self.nixosModules.bat
      self.nixosModules.yazi
      self.nixosModules.btop
      self.nixosModules.fzf
      self.nixosModules.ripgrep
      self.nixosModules.rgf
      self.nixosModules.fileManagement
      self.nixosModules.ex
      self.nixosModules.disktui
      self.nixosModules.doggo
      self.nixosModules.fend
      self.nixosModules.dua
      self.nixosModules.tailscale
      self.nixosModules.smartmontools
      self.nixosModules.mtr
      self.nixosModules.nmap
      self.nixosModules.stui
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.bash.enable = true;
    };
  };
}
