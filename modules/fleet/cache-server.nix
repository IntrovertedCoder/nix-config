{ self, inputs, ... }: {
  # Binary-cache server for the fleet, imported only by vmtest.nix. vmtest
  # builds every host's config and serves the results over Tailscale;
  # followers pull from this cache during their own local `nh os boot`
  # instead of compiling from source (see cache-client.nix).
  flake.nixosModules.fleetCacheServer = { pkgs, lib, ... }: {
    services.harmonia.cache = {
      enable = true;
      # Generated once by hand:
      #   nix-store --generate-binary-cache-key vmtest-1 vmtest-1.secret vmtest-1.public
      # Private half goes here (see the TODO below); public half is checked
      # into the repo plaintext in cache-client.nix -- it only lets a
      # follower *verify* vmtest's signature, never forge one.
      signKeyPaths = [ "/persistent/harmonia/vmtest-1.secret" ];
    };

    # TODO (manual, one-time, on the real vmtest): place the generated
    # private signing key at /persistent/harmonia/vmtest-1.secret, mode
    # 0400, owned by root, *before* the first `nixos-rebuild` that enables
    # this module -- harmonia's systemd unit will fail to start without it.
    # This path is under preservation.preserveAt below, so it survives
    # vmtest's tmpfs-root reboots once placed.
    preservation.preserveAt."/persistent".directories = [
      { directory = "harmonia"; mode = "0700"; }
    ];

    # harmonia's default bind is [::]:5000 -- only open it on the Tailscale
    # interface. Unlike SSH (already open fleet-wide via openFirewall),
    # this is new and should never be reachable off the tailnet.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5000 ];
  };
}
