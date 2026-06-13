{ self, inputs, ... }: {
  flake.nixosConfigurations.vmtest = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.global
      self.nixosModules.vmtestSettings
      self.nixosModules.vmtestDisko
      self.nixosModules.vmtestPreservation
      self.nixosModules.user-shot
      self.nixosModules.sshd
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
  };

  flake.nixosModules.vmtestSettings = { pkgs, ... }: {

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostName = "vmtest";
    networking.networkmanager.enable = true;

    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "sd_mod"
      "ata_piix"
    ];

    environment.systemPackages = [
      pkgs.vim
    ];

    home-manager.users.shot.home.stateVersion = "26.05";
    system.stateVersion = "26.05";
  };
}
