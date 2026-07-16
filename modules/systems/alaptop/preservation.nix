{ inputs, ... }: {
  flake.nixosModules.alaptopPreservation = {
    imports = [ inputs.preservation.nixosModules.default ];

    preservation = {
      enable = true;

      preserveAt."/persistent" = {
        directories = [
          "/etc/nixos"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/etc/ssh/NetworkManager/system-connections"
          # {
            # directory = "/var/lib/nixos";
            # inInitrd = true;
          # }
        ];

        files = [
          {
            file = "/etc/machine-id";
            inInitrd = true;
            how = "bindmount";
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

  };
}
