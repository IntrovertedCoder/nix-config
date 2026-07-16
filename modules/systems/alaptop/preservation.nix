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
          "/etc/NetworkManager/system-connections"
          # {
          #   directory = "/var/lib/nixos";
          #   inInitrd = true;
          # }
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

  };
}
