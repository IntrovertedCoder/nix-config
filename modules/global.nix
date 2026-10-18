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
            # NixOS's record of the uids/gids it handed out. Must be there
            # before stage 2 creates users, i.e. mounted in the initrd -- as a
            # later bind mount it was ignored, users without a fixed uid got
            # new numbers whenever the user set changed, and files they own
            # on /persistent became unreadable (the router VM's disk did).
            { directory = "/var/lib/nixos"; inInitrd = true; }
            "/etc/NetworkManager/system-connections"
            # Kernel panic records (moved here from the firmware's pstore at
            # the next boot -- on tmpfs they'd survive exactly one boot),
            # core dumps, and timer stamps so missed timers catch up.
            "/var/lib/systemd/pstore"
            "/var/lib/systemd/coredump"
            "/var/lib/systemd/timers"
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

      # The machine-id symlink above dangles on a fresh install, which breaks
      # dbus-broker and networkd's DHCP client ID. Seed it once; a no-op
      # whenever /persistent/etc/machine-id already exists.
      systemd.services.seed-persistent-machine-id = {
        description = "Seed /persistent/etc/machine-id before dbus-broker needs it";
        wantedBy = [ "sysinit.target" ];
        before = [ "sysinit.target" "dbus.socket" "dbus-broker.service" "systemd-networkd.service" ];
        after = [ "persistent.mount" ];
        unitConfig.DefaultDependencies = false;
        unitConfig.ConditionPathExists = "!/persistent/etc/machine-id";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.systemd}/bin/systemd-machine-id-setup --root=/persistent";
        };
      };
    };
  };
}
