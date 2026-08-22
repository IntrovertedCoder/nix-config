{ lib, ... }: {
  flake.nixosModules.fleetRegistry = { lib, ... }: {
    # Imported by vmtest-orchestrator.nix; keyed explicitly in case anything
    # else ever needs to read the registry too (see modules/theme/monitors.nix
    # for why this matters once an option is imported from more than one place).
    key = "modules/fleet/fleet.nix";

    options.var.fleet.hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Explicit opt-in list of `nixosConfigurations` attribute names that
        vmtest's weekly cycle builds and caches for. Never derived by
        enumerating all `nixosConfigurations` -- vmtest itself, and future
        service-hosting VMs, may intentionally not want to be included.

        Each entry must exactly match a `flake.nixosConfigurations.<name>`
        attribute, and in practice also that host's `networking.hostName`
        (used to resolve it over Tailscale when relevant).
      '';
    };
  };
}
