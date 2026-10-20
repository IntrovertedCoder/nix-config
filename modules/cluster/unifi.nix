{ self, inputs, lib, ... }: let
  lan = import ./_lan.nix;
  infra = lan.segments.infra;
  address = "${infra.v4}.10";
in {
  # The UniFi controller (design doc, "Switches, VLANs & UniFi"): an Incus
  # system container on Ceph, so it heals to another node like any instance.
  # It sits directly on the untagged infra segment with the gear it manages
  # (layer-2 adoption, no router in between), at a fixed address.
  #
  # The container is NixOS, built from this flake into an Incus image, and
  # declared in OpenTofu (opentofu/unifi.tf): image, instance, and the
  # `unifi-data` volume holding /var/lib/unifi. The container itself is
  # disposable -- an update builds a new image and `nix run .#tofu -- apply`
  # replaces the instance, keeping the volume. It has no SSH. The switches
  # and APs keep forwarding on their last config while the controller is down.
  #
  # Backups: UniFi's own auto-backup lands in the container (on Ceph); every
  # node also copies it to its own disk daily, so losing Ceph doesn't lose
  # them. Not yet off-cluster (design doc, open questions). A reset UX7 can
  # restore one of those .unf files (same or newer Network version).
  flake.nixosConfigurations.unifi = inputs.nixpkgs.lib.nixosSystem {
    modules = [ self.nixosModules.unifiController ];
  };

  flake.nixosModules.unifiController = { config, lib, pkgs, modulesPath, ... }: let
    # UniFi Network 9.0+ supports MongoDB up to 8.0; nixpkgs' prebuilt
    # mongodb-ce is 8.2 (support not confirmed), and its mongodb-7_0 builds
    # from source for hours (unfree: not in the binary cache). MongoDB's own
    # 8.0 binary, then. Don't jump major versions under existing data.
    mongodb80 = pkgs.mongodb-ce.overrideAttrs (old: rec {
      version = "8.0.34";
      src = pkgs.fetchurl {
        url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2404-${version}.tgz";
        hash = "sha256-PlXNz3AT+8gF0p2BlSMN9LI8dohzPuFa1YrGvCpBZhE=";
      };
    });
  in {
    imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];

    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "unifi-controller" "mongodb-ce" ];
    networking.hostName = "unifi";
    system.stateVersion = "26.05";
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    networking.useNetworkd = true;
    networking.useHostResolvConf = false;   # its own DNS: the infra gateway
    networking.useDHCP = false;
    systemd.network.networks."10-eth0" = {
      matchConfig.Name = "eth0";
      address = [ "${address}/${toString infra.plen}" ];
      gateway = [ "${infra.v4}.1" ];
      dns = [ "${infra.v4}.1" ];
      networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
    };

    services.unifi = {
      enable = true;
      unifiPackage = pkgs.unifi;
      mongodbPackage = mongodb80;
      openFirewall = true;            # inform 8080, STUN 3478, discovery 10001, ...
      maximumJavaHeapSize = 1024;
    };
    networking.firewall.allowedTCPPorts = [ 8443 ];   # the web UI

    # The data volume outlives each container, and a fresh image hands out
    # system uids anew: pin them to what owns the data (UniFi and its MongoDB
    # both run as `unifi`), or a replaced container couldn't read its state.
    users.users.unifi.uid = 997;
    users.groups.unifi.gid = 996;

    services.openssh.enable = lib.mkForce false;
    environment.systemPackages = [ pkgs.curl ];   # debugging from inside
  };

  # On every node: keep a copy of the controller's backups on local disk.
  flake.nixosModules.clusterUnifi = { config, lib, pkgs, ... }: {
    systemd.services.unifi-backup-copy = {
      description = "Copy the UniFi controller's backups to this node's disk";
      after = [ "incus.service" ];
      path = [ config.virtualisation.incus.package pkgs.coreutils pkgs.findutils ];
      serviceConfig.Type = "oneshot";
      script = /* bash */ ''
        incus info unifi >/dev/null 2>&1 || { echo "no unifi instance"; exit 0; }
        dest=/persistent/backups/unifi
        tmp=$(mktemp -d /persistent/backups/.unifi.XXXXXX)
        trap 'rm -rf "$tmp"' EXIT
        if incus file pull -r unifi/var/lib/unifi/data/backup/autobackup "$tmp/" \
           && [ -n "$(find "$tmp/autobackup" -name '*.unf' -print -quit)" ]; then
          rm -rf "$dest"; mv "$tmp/autobackup" "$dest"
          echo "copied: $(find "$dest" -name '*.unf' | wc -l) backups"
        else
          # Never replace the last good copy with nothing.
          echo "no backups in the controller yet (turn on auto backup in UniFi); kept the old copy"
        fi
      '';
    };
    systemd.timers.unifi-backup-copy = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "daily"; RandomizedDelaySec = "1h"; Persistent = true; };
    };
    systemd.tmpfiles.rules = [ "d /persistent/backups 0700 root root -" ];
  };
}
