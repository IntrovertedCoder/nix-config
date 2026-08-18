{ self, inputs, ... }: {
  flake.nixosModules.global = { pkgs, lib, ...}: {
    imports = [
      inputs.preservation.nixosModules.default
      self.nixosModules.fail2ban
    ];
    nix = {
      settings.experimental-features = [ "nix-command" "flakes"];
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
      registry.nixpkgs.flake = inputs.nixpkgs;
    };

    preservation = {
      enable = lib.mkDefault true;

      preserveAt."/persistent" = {
        directories = [
          "/etc/nixos"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/etc/NetworkManager/system-connections"
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
            "nix-config"
          ];
        };
      };
    };
  };
}
