{ inputs, ... }: {
  flake.nixosModules.vmtestPreservation = {
    imports = [ inputs.preservation.nixosModules.default ];

    preservation = {
      enable = true;

      preserveAt."/persistent" = {
        directories = [
          "/etc/nixos"
          "/var/lib/bluetooth"
          {
            directory = "/var/lib/nixos";
            inInitrd = true;
          }
        ];

        files = [
          {
            file = "/etc/machine-id";
            inInitrd = true;
            how = "symlink";
          }
        ];

        # Preserve user files
        users.shot = {
          directories = [
            ".ssh"
            "nix-config"
          ];
       
          files = [
       
          ];
        };
      };
    };

    # This systemd service fails unless this is here
    systemd.services.systemd-machine-id-commit = {
      unitConfig.ConditionPathIsMountPoint = [ "" "/persistent/etc/machine-id" ];
      serviceConfig.ExecStart = [ "" "systemd-machine-id-setup --commit --root /persistent" ];
    };
  };
}
