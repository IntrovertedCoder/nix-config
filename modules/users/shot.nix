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

      hashedPassword = "$y$j9T$BNfZNKNNKEyCyPuAcAnUl/$VTC2fLWujyNvInhMvQip3AS13BP9nFyohzAE7qDzHP5";
    };
  };
}
