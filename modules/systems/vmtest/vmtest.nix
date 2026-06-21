{ self, inputs, ... }: {
  flake.nixosConfigurations.vmtest = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.global
      self.nixosModules.vmtestSettings
      self.nixosModules.vmtestDisko
      self.nixosModules.vmtestPreservation
      self.nixosModules.user-shot
      self.nixosModules.sshd
      self.nixosModules.customFirewall
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

    networking.firewall.enable = true;

    var.firewall.untrustedInterfaces = {
      "ygg0" = {
        ipGroups = {
          "myDevices" = {
            ips = [ 
              "202:d9a4:dafb:21e6:f536:764b:144b:32a6 "
            ];
            allowedTCPPorts = [ 22 ];
          };

          # "friends" = {
          #   ips = [ 
          #     "200:1234:5678::abcd" 
          #   ];
          #   allowedTCPPorts = [ 25565 ]; 
          # };
        };

        # Open a basic landing page or public service to all of yggdrasil
        # generalAllowedTCPPorts = [ 80 443 ]; 
      };
    };

    home-manager.users.shot.home.stateVersion = "26.05";
    system.stateVersion = "26.05";
  };
}
