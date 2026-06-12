{ self, inputs, ... }: {

  flake.nixosModules.user-shot = { pkgs, ...}: {
    imports = [
      self.nixosModules.terminal
      inputs.home-manager.nixosModules.home-manager
    ];

    environment.systemPackages = with pkgs; [
    ];

    users.mutableUsers = false;

    users.users.shot= {
      isNormalUser = true;
      description = "shot";
      extraGroups = [ "wheel" "networkmanager" "video" "audio" ];

      hashedPassword = "$y$j9T$xaTOftkAyVD6OBl1BrHTK/$/zSwrOGjzoJuXYU8nhqKf2Vq8UcqQMPaWX23PJ04P/3"; 
    };
  };
}
