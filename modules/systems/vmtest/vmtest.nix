{ self, inputs, ... }: {
  flake.nixosConfigurations.vmtest = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.global
      self.nixosModules.vmtestSettings
      self.nixosModules.vmtestDisko
      self.nixosModules.user-shot
      self.nixosModules.sshd
      self.nixosModules.customFirewall
      self.nixosModules.workstation
      self.nixosModules.sunshine
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ];
  };

  flake.nixosModules.vmtestSettings = { pkgs, ... }: {

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostName = "vmtest";
    networking.networkmanager.enable = true;

    fileSystems."/mnt/tv" = {
      device = "10.123.123.10:/mnt/share";
      fsType = "nfs";
    };
    # optional, but ensures rpc-statsd is running for on demand mounting
    boot.supportedFilesystems = [ "nfs" ];

    users.users.sat = {
      isNormalUser = true;
      description = "User for SMB share";
      # Optional: prevent local login if this user is purely for the share
      shell = pkgs.shadow; 
    };

    services.samba = {
      enable = true;
      openFirewall = true; # Opens TCP 139/445 and UDP 137/138
      
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "NixOS SMB Server";
          "netbios name" = "nixos-smb";
          "security" = "user";
          # Disable guest access globally for extra security
          "guest account" = "nobody";
          "map to guest" = "bad user";
        };
        
        "PrivateShare" = {
          "path" = "/mnt/tv/share/Movies Shows"; # Replace with your actual path
          "browseable" = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "sat";      # Restricts access to this user ONLY
          "force user" = "shot";       # Forces all file operations to be owned by this user
          "create mask" = "0644";
          "directory mask" = "0755";
        };
      };
    };






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
