{ self, inputs, ... }: {
  flake.nixosModules.global = { config, pkgs, lib, ...}: {

    imports = [
      inputs.preservation.nixosModules.default
      self.nixosModules.fail2ban
    ];

    options.custom.allowedUnfree = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of unfree packages allowed to be installed.";
    };

    config = {

      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) config.custom.allowedUnfree;

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

          users.shot = {
            directories = [
              "nix-config"
            ];
          };
        };
      };
    };
  };
}
