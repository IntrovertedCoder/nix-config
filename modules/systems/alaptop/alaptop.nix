{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosConfigurations.alaptop = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.global
      self.nixosModules.alaptopSettings
      self.nixosModules.alaptopDisko
      self.nixosModules.user-shot
      self.nixosModules.sshd
      self.nixosModules.customFirewall
      self.nixosModules.workstation
      self.nixosModules.hypridlesuspend
      self.nixosModules.mullvad


      self.nixosModules.communications
      self.nixosModules.meeting
      self.nixosModules.games
      self.nixosModules.recording
      self.nixosModules.creative
      self.nixosModules.fleetFollower
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
  };

  flake.nixosModules.alaptopSettings = { pkgs, ... }: {

    # var.wallpaperColors = [ c.magenta c.black2 c.cyan ];
    systemd.user.slices.app-games = {
      sliceConfig = {
        Description = "Resource-constrained slice for games";
        # Total ram - normal ram usage
        MemoryMax = "5G";  # Hard limit: Force-kills the scope if exceeded
        # -2G from Max
        MemoryHigh = "3G"; # Soft limit: Throttles memory allocation/reclaim
      };
    };

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    hardware.enableRedistributableFirmware = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.kernelModules = [ "kvm-amd" ];
    boot.initrd.kernelModules = [ "amdgpu" ];


    networking.hostName = "alaptop";
    networking.networkmanager.enable = true;

    # Built-in laptop panel. Check the actual output name with `wlr-randr`
    # once booted (eDP-1 is the common default) and adjust if it differs.
    var.monitors = [
      { name = "eDP-1"; width = 1920; height = 1080; refresh = 60; x = 0; y = 0; scale = 1.0; primary = true; }
    ];

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
            allowedTCPPorts = [ 20530 ];
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
