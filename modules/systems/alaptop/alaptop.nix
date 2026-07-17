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
      self.nixosModules.workstation
      self.nixosModules.sunshine
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
      "wlp2s0" = {
        ipGroups = {
          "myDevices" = {
            ips = [
              "192.168.10.219"
              "192.168.10.107"
            ];
            allowedTCPPorts = [ 20530 47984 47989 47990 48010 ];
            allowedUDPPortRanges = [
              { from = 47998; to = 48000; }
              { from = 8000; to = 8010; }
            ];
          };

          # "friends" = {
          #   ips = [ 
          #     "200:1234:5678::abcd" 
          #   ];
          #   allowedTCPPorts = [ 25565 ]; 
          # };
        };

        # Open a basic landing page or public service to all of interface
        # generalAllowedTCPPorts = [ 80 443 ]; 
        # Allow 68 for DHCP
        generalAllowedUDPPorts = [ 68 ];
      };
    };

    home-manager.users.shot.home.stateVersion = "26.05";
    system.stateVersion = "26.05";
  };
}
