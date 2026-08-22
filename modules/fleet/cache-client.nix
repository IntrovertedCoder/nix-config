{ self, inputs, ... }: {
  # Trusts vmtest's binary cache. Imported automatically by follower.nix --
  # every follower always wants to trust the cache it's built to pull from.
  flake.nixosModules.fleetCacheClient = { lib, ... }: {
    nix.settings = {
      substituters = [ "http://vmtest:5000" ]; # Tailscale MagicDNS name
      trusted-public-keys = [
        # Public half of the keypair generated for cache-server.nix's
        # signKeyPaths. Not sensitive -- only verifies vmtest's signature.
        "vmtest-1:FHqwA+5C3phjpHYoFAfuBJecLWqQR2rvy2c3SroYrAQ="
      ];
    };
  };
}
