{ self, inputs, ... }: {
  flake.nixosConfigurations.alaptop = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.global
      self.nixosModules.alaptopSettings
      self.nixosModules.alaptopDisko
      self.nixosModules.alaptopPreservation
      self.nixosModules.user-shot
      self.nixosModules.sshd
      self.nixosModules.customFirewall
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
  };

  flake.nixosModules.alaptopSettings = { pkgs, ... }: {

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    hardware.enableRedistributableFirmware = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.kernelModules = [ "kvm-amd" ];
    boot.initrd.kernelModules = [ "amdgpu" ];

    networking.hostName = "alaptop";
    networking.networkmanager.enable = true;

    boot.initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "ahci"
      "usbhid"
      "sd_mod"
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
