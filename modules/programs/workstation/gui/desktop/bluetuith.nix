{self, inputs, ... }: {
  flake.nixosModules.bluetuith = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];

    preservation.preserveAt."/persistent" = {
      directories = [
        "/var/lib/bluetooth"
      ];
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;

      settings = {
        General = {
          JustWorksRepairing = "never";

          Privacy = "device";

          LEAutoSecurity = "true";

          Name = "Bluetooth";

          DiscoverableTimeout = 30;
          PairableTimeout = 30;

          SecureConnections = "only";
        };

        Policy = {
          AutoEnable = "false";
        };

        GATT = {
          MinEncKeySize = 16;
        };
      };

      disabledPlugins = [ "hostname" ];
    };

    home-manager.users.shot = {
      programs.bluetuith.enable = true;
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Bluetuith"
        prefix = "bt"
        cmd = "bluetuith"

        [[modules]]
        description = "Toggle Bluetooth"
        prefix = "btt"
        cmd = "if bluetoothctl show | grep -q 'Powered: yes'; then bluetoothctl power off; else bluetoothctl power on; fi;"
        with_argument = false
    '';
    };
  };
}
