{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosConfigurations.antimony = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.global
      self.nixosModules.antimonySettings
      self.nixosModules.antimonyDisko
      self.nixosModules.user-shot
      self.nixosModules.sshd
      self.nixosModules.customFirewall
      self.nixosModules.workstation
      self.nixosModules.hypridlesuspend
      self.nixosModules.mullvad
      self.nixosModules.networkManager


      self.nixosModules.communications
      self.nixosModules.meeting
      self.nixosModules.games
      self.nixosModules.recording
      self.nixosModules.creative
      self.nixosModules.fleetFollower
      self.nixosModules.wallpaperSeasonal
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
  };

  flake.nixosModules.antimonySettings = { pkgs, ... }: {

    # var.wallpaperColors = [ c.magenta c.black2 c.cyan ];
    systemd.user.slices.app-games = {
      sliceConfig = {
        Description = "Resource-constrained slice for games";
        # Total ram - normal ram usage
        MemoryMax = "20G";  # Hard limit: Force-kills the scope if exceeded
        # -2G from Max
        MemoryHigh = "18G"; # Soft limit: Throttles memory allocation/reclaim
      };
    };

    systemd.services.seed-persistent-machine-id = {
      description = "Seed /persistent/etc/machine-id before dbus-broker needs it";
      wantedBy = [ "sysinit.target" ];
      before = [ "sysinit.target" "dbus.socket" "dbus-broker.service" ];
      after = [ "persistent.mount" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemd-machine-id-setup --root=/persistent";
      };
    };

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    hardware.enableRedistributableFirmware = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.kernelModules = [ "kvm-amd" ];
    boot.initrd.kernelModules = [ "amdgpu" ];

    networking.hostName = "antimony";

    networking.networkmanager.ensureProfiles.profiles."enp14s0" = {
      connection = {
        id = "enp14s0";
        type = "ethernet";
        interface-name = "enp14s0";
      };
      ipv4 = {
        method = "manual";
        addresses = "10.123.0.51/16";
        gateway = "10.123.0.1";
      };
      ipv6.method = "auto";
    };

    var.monitors = [
      { name = "DP-1"; width = 3440; height = 1440; refresh = 144; x = 0; y = 109; scale = 1.0; primary = true; }
      { name = "DP-3"; width = 1080; height = 1920; refresh = 60; x = 3440; y = 0; transform = 1; }
    ];

    boot.initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "ahci"
      "usbhid"
      "sd_mod"
    ];

    environment.systemPackages = [
    ];

    networking.firewall.enable = true;

    var.firewall.untrustedInterfaces = {
      "enp14s0" = {
        ipGroups = {
          "myDevices" = {
            ips = [
              # "192.168.10.219"
              # "192.168.10.107"
              "10.123.36.69"
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
